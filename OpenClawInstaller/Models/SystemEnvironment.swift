import Combine
import Foundation

struct NodeInfo: Codable {
    let version: String
    let path: String

    var versionNumber: String {
        // Extract version number (e.g., "v18.17.0" -> "18.17.0")
        return version.replacingOccurrences(of: "v", with: "")
    }

    var majorVersion: Int? {
        let components = versionNumber.split(separator: ".")
        guard let first = components.first,
              let major = Int(first) else {
            return nil
        }
        return major
    }

    var isCompatible: Bool {
        // OpenClaw requires Node.js 22 or higher
        guard let major = majorVersion else { return false }
        return major >= 22
    }
}

struct OpenClawInfo: Codable {
    let version: String
    let path: String
    let configPath: String?

    var isConfigured: Bool {
        return configPath != nil
    }
}

@MainActor
class SystemEnvironment: ObservableObject {
    @Published var nodeInfo: NodeInfo?
    @Published var openclawInfo: OpenClawInfo?
    @Published var isChecking = false
    @Published var checkError: String?

    // System info
    @Published var osVersion: String = ""
    @Published var architecture: String = ""
    @Published var availableDiskSpace: String = ""

    private let commandExecutor: CommandExecutor

    init(commandExecutor: CommandExecutor) {
        self.commandExecutor = commandExecutor
        detectSystemInfo()
    }

    /// Detect system information
    private func detectSystemInfo() {
        // OS Version
        let osVersionProcess = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(osVersionProcess.majorVersion).\(osVersionProcess.minorVersion).\(osVersionProcess.patchVersion)"

        // Architecture
        #if arch(arm64)
        architecture = "Apple Silicon (ARM64)"
        #elseif arch(x86_64)
        architecture = "Intel (x86_64)"
        #else
        architecture = "Unknown"
        #endif

        // Disk space
        if let homeURL = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first {
            do {
                let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                if let capacity = values.volumeAvailableCapacity {
                    let gb = Double(capacity) / 1_000_000_000
                    availableDiskSpace = String(format: "%.1f GB", gb)
                }
            } catch {
                availableDiskSpace = "Unknown"
            }
        }
    }

    /// Detect Node.js installation
    func detectNode() async {
        isChecking = true
        checkError = nil

        do {
            // Check if node command exists
            guard let nodePath = await commandExecutor.getCommandPath("node") else {
                nodeInfo = nil
                isChecking = false
                return
            }

            // Get Node.js version
            if let versionOutput = await commandExecutor.getCommandVersion("node", versionArg: "--version") {
                let version = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                nodeInfo = NodeInfo(version: version, path: nodePath)
            } else {
                nodeInfo = nil
            }
        } catch {
            checkError = "Failed to detect Node.js: \(error.localizedDescription)"
            nodeInfo = nil
        }

        isChecking = false
    }

    /// Detect OpenClaw installation
    func detectOpenClaw() async {
        isChecking = true
        checkError = nil

        do {
            // Check if openclaw command exists
            guard let openclawPath = await commandExecutor.getCommandPath("openclaw") else {
                openclawInfo = nil
                isChecking = false
                return
            }

            // Verify core files exist (not just the bin symlink).
            // Resolve the real path of the executable to find the module directory.
            let fm = FileManager.default
            let resolvedPath: String
            do {
                // Follow symlink: ~/.npm-global/bin/openclaw -> ../lib/node_modules/openclaw/openclaw.mjs
                resolvedPath = try fm.destinationOfSymbolicLink(atPath: openclawPath)
                    .isEmpty ? openclawPath : openclawPath
            } catch {
                resolvedPath = openclawPath
            }

            // Determine the openclaw module directory from the executable path.
            // e.g. /Users/x/.npm-global/bin/openclaw -> module at /Users/x/.npm-global/lib/node_modules/openclaw/
            // e.g. /Users/x/.npm-global/lib/node_modules/openclaw/openclaw.mjs -> module at parent dir
            let moduleDir: String
            let parentDir = (openclawPath as NSString).deletingLastPathComponent  // .../bin
            let candidateFromBin = ((parentDir as NSString)
                .deletingLastPathComponent as NSString)
                .appendingPathComponent("lib/node_modules/openclaw")
            let candidateFromMjs = (openclawPath as NSString).deletingLastPathComponent

            if fm.fileExists(atPath: (candidateFromBin as NSString).appendingPathComponent("package.json")) {
                moduleDir = candidateFromBin
            } else if fm.fileExists(atPath: (candidateFromMjs as NSString).appendingPathComponent("package.json")) {
                moduleDir = candidateFromMjs
            } else {
                // Module directory not found — installation is broken
                openclawInfo = nil
                isChecking = false
                return
            }

            // Verify critical files/directories exist
            let homeDir = fm.homeDirectoryForCurrentUser.path
            let criticalPaths = [
                (moduleDir as NSString).appendingPathComponent("package.json"),
                (moduleDir as NSString).appendingPathComponent("dist"),
                (moduleDir as NSString).appendingPathComponent("node_modules"),
                (homeDir as NSString).appendingPathComponent(".openclaw/openclaw.json")
            ]
            for path in criticalPaths {
                if !fm.fileExists(atPath: path) {
                    openclawInfo = nil
                    isChecking = false
                    return
                }
            }

            // Get OpenClaw version
            let version: String
            if let versionOutput = await commandExecutor.getCommandVersion("openclaw", versionArg: "--version") {
                version = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // Binary and module directory verified, but version command failed
                // (e.g. node not in PATH in GUI environment) — still treat as installed
                version = "unknown"
            }

            // Check for config file (config.json is the legacy name)
            let configPath = (homeDir as NSString).appendingPathComponent(".openclaw/config.json")
            let configExists = fm.fileExists(atPath: configPath)

            openclawInfo = OpenClawInfo(
                version: version,
                path: openclawPath,
                configPath: configExists ? configPath : nil
            )
        } catch {
            checkError = "Failed to detect OpenClaw: \(error.localizedDescription)"
            openclawInfo = nil
        }

        isChecking = false
    }

    /// Perform full environment check
    func performFullCheck() async {
        await detectNode()
        await detectOpenClaw()
    }

    /// Check if system meets requirements
    func checkRequirements() -> (passed: Bool, issues: [String]) {
        var issues: [String] = []

        // Check macOS version (require 13.0+ - Ventura)
        let osVersionComponents = osVersion.split(separator: ".").compactMap { Int($0) }
        if let major = osVersionComponents.first, major < 13 {
            issues.append("macOS 13.0 (Ventura) or later is required")
        }

        // Check disk space (require at least 1GB)
        if let spaceStr = availableDiskSpace.split(separator: " ").first,
           let space = Double(spaceStr),
           space < 1.0 {
            issues.append("At least 1 GB of free disk space is required")
        }

        // Check Node.js compatibility
        if let node = nodeInfo, !node.isCompatible {
            issues.append("Node.js version \(node.version) is not compatible. Version 22 or higher is required.")
        }

        return (issues.isEmpty, issues)
    }
}
