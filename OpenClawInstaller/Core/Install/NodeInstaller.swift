import Combine
import CryptoKit
import Foundation

struct NodeVersion: Codable {
    let version: String
    let lts: Bool

    var versionNumber: String {
        return version.replacingOccurrences(of: "v", with: "")
    }
}

enum NodeInstallationError: LocalizedError {
    case downloadFailed(String)
    case installationFailed(String)
    case verificationFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Failed to download Node.js: \(message)"
        case .installationFailed(let message):
            return "Failed to install Node.js: \(message)"
        case .verificationFailed:
            return "Node.js installation could not be verified"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

@MainActor
class NodeInstaller: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var installationStatus: String = ""
    @Published var installationLog: String = ""
    @Published var isInstalling = false
    @Published var error: NodeInstallationError?

    private let commandExecutor: CommandExecutor
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var isChinaRegion: Bool = false

    // Bundled Node.js version
    private let bundledNodeVersion = "v24.14.0"

    /// SHA256 of the official Node.js tarballs for the pinned bundled
    /// version, keyed by arch. Network downloads of this version are
    /// verified against these; other versions verify against the
    /// mirror's SHASUMS256.txt. Update together with bundledNodeVersion.
    private static let pinnedNodeTarballSHA256: [String: String] = [
        "arm64": "a1a54f46a750d2523d628d924aab61758a51c9dad3e0238beb14141be9615dd3",
        "x64": "f2879eb810e25993a0578e5d878930266fd2eafcffe9f2839b3d8db354d4879e",
    ]

    /// Node.js installation directory (user-local, no sudo needed)
    var nodeInstallDir: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.openclaw/node"
    }

    /// Detect CPU architecture at runtime (handles Rosetta correctly)
    private var bundledNodeArch: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine == "arm64" ? "arm64" : "x64"
    }

    init(commandExecutor: CommandExecutor) {
        self.commandExecutor = commandExecutor
    }

    /// Check if bundled Node.js package exists
    private func getBundledNodePath() -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let bundledPath = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("node-\(bundledNodeVersion)-darwin-\(bundledNodeArch).tar.gz")

        return FileManager.default.fileExists(atPath: bundledPath.path) ? bundledPath : nil
    }

    /// Detect if user is in China by checking IP location
    private func detectRegion() async -> Bool {
        do {
            // Try multiple IP detection services
            let services = [
                "https://api.ip.sb/geoip",
                "https://ipapi.co/json",
                "https://ip-api.com/json"
            ]

            for serviceURL in services {
                guard let url = URL(string: serviceURL) else { continue }

                do {
                    let (data, _) = try await URLSession.shared.data(from: url)

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check country code
                        let countryCode = json["country_code"] as? String ??
                                         json["countryCode"] as? String ??
                                         json["country"] as? String ?? ""

                        if countryCode.uppercased() == "CN" {
                            return true
                        }
                    }
                } catch {
                    continue
                }
            }

            return false
        } catch {
            return false
        }
    }

    /// Get Node.js mirror URL based on region
    private func getNodeMirrorURL() -> String {
        if isChinaRegion {
            // Use Alibaba Cloud mirror (fastest in China)
            return "https://registry.npmmirror.com/-/binary/node"
        } else {
            // Use official Node.js distribution
            return "https://nodejs.org/dist"
        }
    }

    /// Get latest LTS Node.js version
    func getLatestNodeVersion() async throws -> String {
        installationStatus = "Detecting region..."

        // Detect region first
        isChinaRegion = await detectRegion()

        let region = isChinaRegion ? "中国" : "International"
        installationStatus = "Region detected: \(region). Fetching latest Node.js version..."

        // Use appropriate mirror
        let baseURL = isChinaRegion ?
            "https://registry.npmmirror.com/-/binary/node/index.json" :
            "https://nodejs.org/dist/index.json"

        let url = URL(string: baseURL)!

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let versions = try JSONDecoder().decode([NodeVersion].self, from: data)

            // Find latest LTS version
            guard let latestLTS = versions.first(where: { $0.lts }) else {
                throw NodeInstallationError.networkError("No LTS version found")
            }

            installationStatus = "Latest LTS version: \(latestLTS.version)"
            return latestLTS.version
        } catch {
            throw NodeInstallationError.networkError(error.localizedDescription)
        }
    }

    /// Download Node.js tar.gz package
    func downloadNodePkg(version: String) async throws -> URL {
        let mirror = isChinaRegion ? "国内镜像" : "Official mirror"
        installationStatus = "Downloading Node.js \(version) from \(mirror)..."
        downloadProgress = 0.0

        // Determine architecture at runtime
        let arch = bundledNodeArch

        // Construct download URL based on region — download tar.gz (not .pkg)
        // so we can install to ~/.openclaw/node/ without sudo
        let mirrorURL = getNodeMirrorURL()
        let urlString = "\(mirrorURL)/\(version)/node-\(version)-darwin-\(arch).tar.gz"

        guard let url = URL(string: urlString) else {
            throw NodeInstallationError.downloadFailed("Invalid download URL")
        }

        // Log the download source
        print("📦 Downloading from: \(urlString)")

        // Create temporary directory for download
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("node-\(version)-darwin-\(arch).tar.gz")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destinationURL)

        let downloaded: URL = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: NodeInstallationError.downloadFailed(error.localizedDescription))
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: NodeInstallationError.downloadFailed("No download URL"))
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    Task { @MainActor in
                        self.installationStatus = "Download complete"
                        self.downloadProgress = 1.0
                    }
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: NodeInstallationError.downloadFailed(error.localizedDescription))
                }
            }

            // Observe download progress
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.downloadProgress = progress.fractionCompleted
                    let percent = Int(progress.fractionCompleted * 100)
                    self.installationStatus = "Downloading... \(percent)%"
                }
            }

            // Start download
            task.resume()
            self.downloadTask = task
        }

        try await verifyNodeTarball(at: downloaded, version: version, arch: arch)
        return downloaded
    }

    /// Verify a downloaded Node.js tarball against its official SHA256.
    /// The pinned bundled version checks the hash compiled into the app;
    /// other versions check the SHASUMS256.txt published next to the
    /// tarball on the same mirror — that still catches truncation and
    /// corruption even though it shares the download channel.
    private func verifyNodeTarball(at fileURL: URL, version: String, arch: String) async throws {
        installationStatus = "Verifying download integrity..."
        let actual = try Self.sha256Hex(of: fileURL)

        let expected: String
        if version == bundledNodeVersion, let pinned = Self.pinnedNodeTarballSHA256[arch] {
            expected = pinned
        } else {
            let fileName = "node-\(version)-darwin-\(arch).tar.gz"
            guard let shasumsURL = URL(string: "\(getNodeMirrorURL())/\(version)/SHASUMS256.txt") else {
                throw NodeInstallationError.downloadFailed("Invalid SHASUMS256.txt URL")
            }
            let (data, _) = try await URLSession.shared.data(from: shasumsURL)
            guard let text = String(data: data, encoding: .utf8),
                  let line = text.components(separatedBy: "\n")
                      .first(where: { $0.hasSuffix(fileName) }),
                  let hash = line.components(separatedBy: " ").first,
                  hash.count == 64 else {
                throw NodeInstallationError.downloadFailed("SHASUMS256.txt has no entry for \(fileName)")
            }
            expected = hash.lowercased()
        }

        guard actual == expected else {
            try? FileManager.default.removeItem(at: fileURL)
            throw NodeInstallationError.downloadFailed(
                "Checksum mismatch for \(fileURL.lastPathComponent): expected \(expected.prefix(12))…, got \(actual.prefix(12))…"
            )
        }
        appendLog("Node tarball checksum verified (sha256 \(actual.prefix(12))…)")
    }

    /// Streamed SHA256 so a ~50MB tarball isn't loaded into memory at once.
    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { handle.readData(ofLength: 4 * 1024 * 1024) }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Install Node.js from tar.gz file
    func installNodeFromTarGz(from tarPath: URL) async throws {
        installationStatus = "Preparing to extract Node.js..."
        appendLog("Preparing to extract Node.js from \(tarPath.lastPathComponent)...")
        downloadProgress = 0.1

        let targetDir = nodeInstallDir

        do {
            // Remove quarantine attribute from tar.gz before extraction
            let _ = try? await commandExecutor.execute(
                "/usr/bin/xattr",
                args: ["-d", "com.apple.quarantine", tarPath.path],
                withSudo: false
            )

            installationStatus = "Extracting Node.js (this may take a moment)..."
            appendLog("Extracting Node.js to \(targetDir)...")
            downloadProgress = 0.2

            // Start a timer to simulate progress during extraction
            let progressTask = Task { @MainActor in
                var progress = 0.2
                while progress < 0.65 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    progress += 0.05
                    self.downloadProgress = progress
                    self.installationStatus = "Extracting Node.js... \(Int(progress * 100))%"
                }
            }

            // Extract to ~/.openclaw/node/ (no sudo needed)
            let installCommand = """
            mkdir -p "\(targetDir)" && \
            tar -xzf "\(tarPath.path)" -C "\(targetDir)" --strip-components=1 && \
            xattr -cr "\(targetDir)/bin/node" "\(targetDir)/bin/npm" "\(targetDir)/bin/npx" 2>/dev/null; \
            xattr -cr "\(targetDir)/lib/node_modules" 2>/dev/null; \
            true
            """

            _ = try await commandExecutor.execute(
                "/bin/bash",
                args: ["-c", installCommand],
                withSudo: false
            ) { output in
                self.appendLog(output)
            }

            progressTask.cancel()
            appendLog("Extraction complete, quarantine attributes removed.")

            installationStatus = "Verifying extracted binaries..."
            appendLog("Verifying extracted binaries...")
            downloadProgress = 0.75

            // Verify the key binary exists after extraction
            let nodeBinPath = "\(targetDir)/bin/node"
            let npmBinPath = "\(targetDir)/bin/npm"
            let nodeExists = FileManager.default.isExecutableFile(atPath: nodeBinPath)
            let npmExists = FileManager.default.isExecutableFile(atPath: npmBinPath)
            appendLog("node binary exists: \(nodeExists), npm binary exists: \(npmExists)")

            if !nodeExists {
                throw NodeInstallationError.installationFailed(
                    "Node binary not found at \(nodeBinPath) after extraction"
                )
            }

            installationStatus = "Installation complete"
            downloadProgress = 1.0

        } catch {
            appendLog("Error: \(error.localizedDescription)")
            throw NodeInstallationError.installationFailed(error.localizedDescription)
        }
    }

    /// Install Node.js from package file
    func installNode(from pkgPath: URL) async throws {
        installationStatus = "Installing Node.js..."
        appendLog("Installing Node.js from \(pkgPath.lastPathComponent)...")
        downloadProgress = 0.0

        do {
            // Use installer command with sudo
            let result = try await commandExecutor.execute(
                "/usr/sbin/installer",
                args: [
                    "-pkg", pkgPath.path,
                    "-target", "/"
                ],
                withSudo: true
            ) { output in
                self.appendLog(output)
            }

            appendLog(result)
            installationStatus = "Installation complete"
            downloadProgress = 1.0

            // Clean up downloaded package
            try? FileManager.default.removeItem(at: pkgPath)
            appendLog("Cleaned up downloaded package.")

        } catch {
            appendLog("Error: \(error.localizedDescription)")
            throw NodeInstallationError.installationFailed(error.localizedDescription)
        }
    }

    /// Verify Node.js installation
    func verifyInstallation() async throws -> Bool {
        installationStatus = "Verifying installation..."
        appendLog("Verifying Node.js installation...")

        // Wait a moment for installation to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Try multiple strategies to find the node binary
        var nodePath: String? = nil

        // 1. Check known installation paths directly (most reliable after tar extraction)
        let knownPaths = ["\(nodeInstallDir)/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/node"]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                nodePath = path
                appendLog("Found node at known path: \(path)")
                break
            }
        }

        // 2. Fall back to getCommandPath (login shell + additional locations)
        if nodePath == nil {
            nodePath = await commandExecutor.getCommandPath("node")
            if let p = nodePath {
                appendLog("Found node via getCommandPath: \(p)")
            }
        }

        guard let verifiedNodePath = nodePath else {
            appendLog("Error: node command not found at any known location")
            appendLog("Checked: \(knownPaths.joined(separator: ", "))")
            throw NodeInstallationError.verificationFailed
        }

        // Get version by running the binary directly (not via shell)
        let version = await commandExecutor.getCommandVersion("node", versionArg: "--version")
        let versionStr = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        installationStatus = "Node.js \(versionStr) installed at \(verifiedNodePath)"
        appendLog("Node.js \(versionStr) installed at \(verifiedNodePath)")
        return true
    }

    /// Complete Node.js installation process
    func installNodeJS() async throws {
        isInstalling = true
        error = nil
        installationLog = ""

        do {
            // Check if we have bundled Node.js
            if let bundledPath = getBundledNodePath() {
                installationStatus = "Using bundled Node.js \(bundledNodeVersion)..."
                appendLog("Found bundled Node.js \(bundledNodeVersion)")
                downloadProgress = 0.1

                // Install from bundled tar.gz
                try await installNodeFromTarGz(from: bundledPath)

            } else {
                // Fallback to download
                installationStatus = "Bundled Node.js not found, downloading..."
                appendLog("Bundled Node.js not found, will download from network...")

                // Detect region
                isChinaRegion = await detectRegion()

                // Get latest version
                let version = try await getLatestNodeVersion()
                appendLog("Latest LTS version: \(version)")

                // Download tar.gz package
                let pkgPath = try await downloadNodePkg(version: version)
                appendLog("Download complete: \(pkgPath.lastPathComponent)")

                // Install from tar.gz to ~/.openclaw/node/
                try await installNodeFromTarGz(from: pkgPath)

                // Clean up downloaded file
                try? FileManager.default.removeItem(at: pkgPath)
                appendLog("Cleaned up downloaded package.")
            }

            // Verify installation
            _ = try await verifyInstallation()

            isInstalling = false
            installationStatus = "Node.js installation successful!"
            appendLog("Node.js installation successful!")

        } catch let err as NodeInstallationError {
            self.error = err
            installationStatus = err.localizedDescription
            appendLog("Error: \(err.localizedDescription)")
            isInstalling = false
            throw err
        } catch {
            let err = NodeInstallationError.installationFailed(error.localizedDescription)
            self.error = err
            installationStatus = err.localizedDescription
            appendLog("Error: \(error.localizedDescription)")
            isInstalling = false
            throw err
        }
    }

    /// Cancel download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        installationStatus = "Download cancelled"
        isInstalling = false
    }

    /// Reset state
    func reset() {
        downloadProgress = 0.0
        installationStatus = ""
        installationLog = ""
        isInstalling = false
        error = nil
        progressObservation?.invalidate()
        progressObservation = nil
    }

    /// Append to installation log
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        installationLog += "[\(timestamp)] \(message)\n"
    }
}
