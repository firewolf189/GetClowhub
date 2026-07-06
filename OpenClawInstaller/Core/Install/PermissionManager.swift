import Combine
import Foundation
import Security

enum PermissionError: LocalizedError {
    case authorizationFailed
    case executionFailed(String)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "Failed to obtain administrator privileges"
        case .executionFailed(let message):
            return "Failed to execute command with privileges: \(message)"
        case .notAuthorized:
            return "Not authorized. Please restart the application."
        }
    }
}

@MainActor
class PermissionManager: ObservableObject {
    @Published var isAuthorized = false
    private var authRef: AuthorizationRef?

    init() {
        // Check if already authorized
        checkAuthorization()
    }

    deinit {
        Task { @MainActor in
            cleanup()
        }
    }

    /// Check current authorization status
    private func checkAuthorization() {
        isAuthorized = authRef != nil
    }

    /// Request administrator rights
    func requestAdminRights() -> Bool {
        var authRef: AuthorizationRef?

        // Create authorization with no specific rights first
        let flags: AuthorizationFlags = [
            .interactionAllowed,
            .extendRights,
            .preAuthorize
        ]

        // Use kAuthorizationRightExecute as a stable C string pointer
        let rightName = kAuthorizationRightExecute
        var status: OSStatus = errAuthorizationDenied

        // withCString keeps the pointer valid for the entire closure scope
        rightName.withCString { cString in
            var rights = AuthorizationItem(
                name: cString,
                valueLength: 0,
                value: nil,
                flags: 0
            )

            var rightSet = AuthorizationRights(
                count: 1,
                items: &rights
            )

            status = AuthorizationCreate(
                &rightSet,
                nil,
                flags,
                &authRef
            )
        }

        if status == errAuthorizationSuccess {
            self.authRef = authRef
            self.isAuthorized = true
            return true
        } else {
            self.isAuthorized = false
            return false
        }
    }

    /// Execute command with administrator privileges (nonisolated to allow background thread calls)
    nonisolated func executeWithPrivileges(command: String, args: [String]) throws -> String {
        // Write the command to a temporary script file to avoid escaping issues
        // with AppleScript's do shell script.
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let scriptFile = tempDir.appendingPathComponent("openclaw_sudo_\(UUID().uuidString).sh")

        // Build the command line for the script
        var scriptContent = "#!/bin/sh\n"

        // If the caller used "/bin/bash -c <cmd>", extract the inner command
        // and run it directly (do shell script already uses /bin/sh).
        if command == "/bin/bash" || command == "/bin/sh",
           args.count == 2, args[0] == "-c" {
            scriptContent += args[1] + "\n"
        } else {
            // Shell-quote each argument
            let components = [command] + args
            let quoted = components.map { arg -> String in
                if arg.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\"'\\$`!#&|;(){}[]<>?*~")) != nil {
                    // Use single quotes; escape embedded single quotes
                    let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                    return "'\(escaped)'"
                }
                return arg
            }
            scriptContent += quoted.joined(separator: " ") + "\n"
        }

        do {
            try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
            // Make the script executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        } catch {
            throw PermissionError.executionFailed("Failed to create temporary script: \(error.localizedDescription)")
        }

        defer {
            try? fm.removeItem(at: scriptFile)
        }

        // Execute the script with administrator privileges via AppleScript
        let scriptPath = scriptFile.path
        let escapedPath = scriptPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScriptSource = """
        do shell script "\(escapedPath)" with administrator privileges
        """

        let appleScript = NSAppleScript(source: appleScriptSource)
        var errorDict: NSDictionary?

        guard let output = appleScript?.executeAndReturnError(&errorDict) else {
            let errorMessage: String
            if let error = errorDict,
               let msg = error[NSAppleScript.errorMessage] as? String {
                errorMessage = msg
            } else {
                errorMessage = "Unknown error executing privileged command"
            }
            throw PermissionError.executionFailed(errorMessage)
        }

        return output.stringValue ?? ""
    }

    /// Check if command exists in system
    func checkCommandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Clean up authorization
    func cleanup() {
        if let authRef = authRef {
            AuthorizationFree(authRef, [])
            self.authRef = nil
            self.isAuthorized = false
        }
    }
}
