import Foundation

// MARK: - App Error Types

enum AppError: Error {
    // Installation Errors
    case installationFailed(reason: String)
    case nodeInstallationFailed(reason: String)
    case openclawInstallationFailed(reason: String)
    case downloadFailed(reason: String)
    case verificationFailed(reason: String)

    // Permission Errors
    case permissionDenied
    case authorizationFailed
    case insufficientPrivileges

    // Service Errors
    case serviceStartFailed(reason: String)
    case serviceStopFailed(reason: String)
    case serviceNotInstalled
    case serviceAlreadyRunning
    case serviceNotResponding

    // Configuration Errors
    case configurationInvalid(reason: String)
    case configurationNotFound
    case configurationCorrupted
    case invalidPort(port: Int)

    // System Errors
    case systemRequirementsNotMet(reason: String)
    case incompatibleVersion(current: String, required: String)
    case insufficientDiskSpace(available: String, required: String)
    case networkError(reason: String)
    case commandExecutionFailed(command: String, reason: String)

    // File System Errors
    case fileNotFound(path: String)
    case fileAccessDenied(path: String)
    case fileCorrupted(path: String)

    // Unknown/Generic Errors
    case unknown(reason: String)

    // MARK: - User-Friendly Messages

    var title: String {
        switch self {
        case .installationFailed, .nodeInstallationFailed, .openclawInstallationFailed:
            return "Installation Failed"
        case .downloadFailed:
            return "Download Failed"
        case .verificationFailed:
            return "Verification Failed"
        case .permissionDenied, .authorizationFailed, .insufficientPrivileges:
            return "Permission Error"
        case .serviceStartFailed, .serviceStopFailed:
            return "Service Error"
        case .serviceNotInstalled:
            return "Service Not Installed"
        case .serviceAlreadyRunning:
            return "Service Already Running"
        case .serviceNotResponding:
            return "Service Not Responding"
        case .configurationInvalid, .configurationNotFound, .configurationCorrupted:
            return "Configuration Error"
        case .invalidPort:
            return "Invalid Port"
        case .systemRequirementsNotMet:
            return "System Requirements Not Met"
        case .incompatibleVersion:
            return "Incompatible Version"
        case .insufficientDiskSpace:
            return "Insufficient Disk Space"
        case .networkError:
            return "Network Error"
        case .commandExecutionFailed:
            return "Command Failed"
        case .fileNotFound, .fileAccessDenied, .fileCorrupted:
            return "File Error"
        case .unknown:
            return "Error"
        }
    }

    var message: String {
        switch self {
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .nodeInstallationFailed(let reason):
            return "Node.js installation failed: \(reason)"
        case .openclawInstallationFailed(let reason):
            return "OpenClaw installation failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .verificationFailed(let reason):
            return "Installation verification failed: \(reason)"

        case .permissionDenied:
            return "Administrator privileges are required. Please restart the application and grant access when prompted."
        case .authorizationFailed:
            return "Failed to obtain administrator privileges. The application cannot proceed without elevated permissions."
        case .insufficientPrivileges:
            return "Your user account does not have sufficient privileges to perform this operation."

        case .serviceStartFailed(let reason):
            return "Failed to start the service: \(reason)"
        case .serviceStopFailed(let reason):
            return "Failed to stop the service: \(reason)"
        case .serviceNotInstalled:
            return "OpenClaw is not installed. Please run the installation wizard first."
        case .serviceAlreadyRunning:
            return "The service is already running."
        case .serviceNotResponding:
            return "The service is not responding. Try restarting it."

        case .configurationInvalid(let reason):
            return "Configuration is invalid: \(reason)"
        case .configurationNotFound:
            return "Configuration file not found. The application may need to be reinstalled."
        case .configurationCorrupted:
            return "Configuration file is corrupted. Try resetting to default settings."
        case .invalidPort(let port):
            return "Port \(port) is invalid. Please choose a port between 1024 and 65535."

        case .systemRequirementsNotMet(let reason):
            return "Your system does not meet the requirements: \(reason)"
        case .incompatibleVersion(let current, let required):
            return "Incompatible version detected. Current: \(current), Required: \(required) or higher."
        case .insufficientDiskSpace(let available, let required):
            return "Insufficient disk space. Available: \(available), Required: \(required)"
        case .networkError(let reason):
            return "Network error: \(reason). Please check your internet connection."
        case .commandExecutionFailed(let command, let reason):
            return "Command '\(command)' failed: \(reason)"

        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileAccessDenied(let path):
            return "Access denied to file: \(path)"
        case .fileCorrupted(let path):
            return "File is corrupted: \(path)"

        case .unknown(let reason):
            return "An unexpected error occurred: \(reason)"
        }
    }

    var icon: String {
        switch self {
        case .installationFailed, .nodeInstallationFailed, .openclawInstallationFailed,
             .downloadFailed, .verificationFailed:
            return "xmark.circle.fill"
        case .permissionDenied, .authorizationFailed, .insufficientPrivileges:
            return "lock.fill"
        case .serviceStartFailed, .serviceStopFailed, .serviceNotResponding:
            return "exclamationmark.triangle.fill"
        case .serviceNotInstalled:
            return "tray.fill"
        case .serviceAlreadyRunning:
            return "checkmark.circle.fill"
        case .configurationInvalid, .configurationNotFound, .configurationCorrupted:
            return "gearshape.fill"
        case .invalidPort:
            return "number.circle.fill"
        case .systemRequirementsNotMet, .incompatibleVersion:
            return "exclamationmark.octagon.fill"
        case .insufficientDiskSpace:
            return "internaldrive.fill"
        case .networkError:
            return "wifi.slash"
        case .commandExecutionFailed:
            return "terminal.fill"
        case .fileNotFound, .fileAccessDenied, .fileCorrupted:
            return "doc.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .serviceAlreadyRunning:
            return "orange"
        case .permissionDenied, .authorizationFailed, .insufficientPrivileges:
            return "yellow"
        default:
            return "red"
        }
    }

    // MARK: - Recovery Suggestions

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied, .authorizationFailed:
            return "Restart the application and grant administrator access when prompted."
        case .insufficientPrivileges:
            return "Contact your system administrator to grant you the necessary privileges."
        case .serviceNotInstalled:
            return "Run the installation wizard to install OpenClaw."
        case .serviceNotResponding:
            return "Try restarting the service. If the problem persists, reinstall OpenClaw."
        case .configurationCorrupted:
            return "Reset the configuration to default settings or reinstall the application."
        case .networkError:
            return "Check your internet connection and try again."
        case .insufficientDiskSpace:
            return "Free up disk space and try again."
        case .incompatibleVersion:
            return "Update to a compatible version."
        case .invalidPort:
            return "Choose a different port number between 1024 and 65535."
        default:
            return nil
        }
    }

    // MARK: - Reportable

    var isReportable: Bool {
        switch self {
        case .unknown, .commandExecutionFailed, .fileCorrupted, .configurationCorrupted:
            return true
        default:
            return false
        }
    }

    // MARK: - Retry Logic

    var isRetryable: Bool {
        switch self {
        case .networkError, .downloadFailed, .serviceNotResponding, .commandExecutionFailed:
            return true
        case .serviceStartFailed, .serviceStopFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - LocalizedError Conformance

extension AppError: LocalizedError {
    var errorDescription: String? {
        return message
    }

    var failureReason: String? {
        return title
    }
}

// MARK: - Error Helper

struct ErrorHelper {
    /// Convert any error to AppError
    static func convert(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        // Convert common errors
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return .networkError(reason: nsError.localizedDescription)
        case NSCocoaErrorDomain:
            if nsError.code == NSFileNoSuchFileError {
                return .fileNotFound(path: nsError.userInfo[NSFilePathErrorKey] as? String ?? "unknown")
            } else if nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
                return .fileAccessDenied(path: nsError.userInfo[NSFilePathErrorKey] as? String ?? "unknown")
            }
        default:
            break
        }

        return .unknown(reason: error.localizedDescription)
    }

    /// Check if error is critical (requires app restart or user intervention)
    static func isCritical(_ error: AppError) -> Bool {
        switch error {
        case .permissionDenied, .authorizationFailed, .systemRequirementsNotMet:
            return true
        default:
            return false
        }
    }
}
