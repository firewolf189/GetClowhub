import Foundation
import Combine

enum CommandError: LocalizedError {
    case executionFailed(String)
    case commandNotFound(String)
    case permissionDenied
    case timeout

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Command execution failed: \(message)"
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .permissionDenied:
            return "Permission denied"
        case .timeout:
            return "Command execution timed out"
        }
    }
}

@MainActor
class CommandExecutor: ObservableObject {
    @Published var output: String = ""
    @Published var isExecuting = false

    private let permissionManager: PermissionManager

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    /// Execute shell command
    func execute(
        _ command: String,
        args: [String] = [],
        withSudo: Bool = false,
        outputHandler: ((String) -> Void)? = nil
    ) async throws -> String {
        isExecuting = true
        defer { isExecuting = false }

        if withSudo {
            return try await executeWithSudo(command, args: args)
        } else {
            return try await executeNormal(command, args: args, outputHandler: outputHandler)
        }
    }

    /// Execute command with sudo (dispatched to background to avoid blocking UI)
    private func executeWithSudo(_ command: String, args: [String]) async throws -> String {
        // Note: executeWithPrivileges uses AppleScript "do shell script ... with administrator privileges"
        // which prompts the user for their password if needed, so we don't need to check isAuthorized here.
        let pm = self.permissionManager
        let cmd = command
        let arguments = args
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try pm.executeWithPrivileges(command: cmd, args: arguments)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Execute normal command
    private func executeNormal(
        _ command: String,
        args: [String],
        outputHandler: ((String) -> Void)?
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = args

                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.standardOutput = outputPipe
                process.standardError = errorPipe

                var outputData = Data()
                var errorData = Data()

                // Handle output in real-time
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.count > 0 {
                        outputData.append(data)
                        if let string = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                self.output += string
                                outputHandler?(string)
                            }
                        }
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.count > 0 {
                        errorData.append(data)
                        if let string = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                self.output += string
                                outputHandler?(string)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    // Clean up handlers
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    if process.terminationStatus == 0 {
                        let result = String(data: outputData, encoding: .utf8) ?? ""
                        continuation.resume(returning: result)
                    } else {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: CommandError.executionFailed(errorMessage))
                    }
                } catch {
                    continuation.resume(throwing: CommandError.executionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Check if command exists
    func checkCommandExists(_ command: String) -> Bool {
        return permissionManager.checkCommandExists(command)
    }

    /// Get command path (uses login shell to get full user PATH)
    func getCommandPath(_ command: String) async -> String? {
        // 1. Try `which` via login shells (both zsh and bash)
        for shell in ["/bin/zsh", "/bin/bash"] {
            let path = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: shell)
                    process.arguments = ["-l", "-c", "which \(command)"]

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = Pipe()

                    do {
                        try process.run()
                        process.waitUntilExit()

                        if process.terminationStatus == 0 {
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let output = (String(data: data, encoding: .utf8) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            // Take only the last line (skip shell init output)
                            let lastLine = output.components(separatedBy: .newlines).last?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            // Validate: must be an absolute path to an existing executable
                            if !lastLine.isEmpty,
                               lastLine.hasPrefix("/"),
                               FileManager.default.isExecutableFile(atPath: lastLine) {
                                continuation.resume(returning: lastLine)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let path = path {
                return path
            }
        }

        // 2. Fallback: check common installation locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(homeDir)/.npm-global/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "\(homeDir)/.volta/bin/\(command)",
            "\(homeDir)/Library/pnpm/\(command)",
            "\(homeDir)/.nvs/default/bin/\(command)",
            "\(homeDir)/tools/nvs/default/bin/\(command)",
        ]
        // nvm: scan ~/.nvm/versions/node/*/bin, pick latest version
        if let nvmBin = Self.findLatestNvmBin(homeDir: homeDir, command: command) {
            candidates.insert(nvmBin, at: 0)
        }
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Find the latest nvm-installed binary for a given command
    static func findLatestNvmBin(homeDir: String, command: String) -> String? {
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) else {
            return nil
        }
        // Sort version directories descending (e.g. v22.22.0 > v18.17.0)
        let sorted = entries
            .filter { $0.hasPrefix("v") }
            .sorted { a, b in compareNodeVersions(a, b) }
        for version in sorted {
            let binPath = "\(nvmVersionsDir)/\(version)/bin/\(command)"
            if FileManager.default.isExecutableFile(atPath: binPath) {
                return binPath
            }
        }
        return nil
    }

    /// Compare node version strings like "v22.22.0" > "v18.17.0" (descending)
    private static func compareNodeVersions(_ a: String, _ b: String) -> Bool {
        let partsA = a.dropFirst().split(separator: ".").compactMap { Int($0) }
        let partsB = b.dropFirst().split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    /// Get command version (resolves path first, then runs with version arg)
    func getCommandVersion(_ command: String, versionArg: String = "--version") async -> String? {
        // Resolve full path first to avoid PATH issues in GUI environment
        guard let fullPath = await getCommandPath(command) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", "'\(fullPath)' \(versionArg)"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = (String(data: data, encoding: .utf8) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        // Take only the last line (skip shell init output)
                        let lastLine = output.components(separatedBy: .newlines).last?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(returning: lastLine.isEmpty ? nil : lastLine)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Clear output
    func clearOutput() {
        output = ""
    }
}
