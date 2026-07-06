import Combine
import Foundation

enum InstallationStep: String, CaseIterable {
    case welcome = "Welcome"
    case environmentCheck = "Environment Check"
    case nodeInstallation = "Node.js Installation"
    case openclawInstallation = "OpenClaw Installation"
    case configuration = "Configuration"
    case complete = "Complete"

    var stepNumber: Int {
        switch self {
        case .welcome: return 1
        case .environmentCheck: return 2
        case .nodeInstallation: return 3
        case .openclawInstallation: return 4
        case .configuration: return 5
        case .complete: return 6
        }
    }

    var description: String {
        switch self {
        case .welcome:
            return "Welcome to OpenClaw Installer"
        case .environmentCheck:
            return "Checking your system environment"
        case .nodeInstallation:
            return "Installing Node.js"
        case .openclawInstallation:
            return "Installing OpenClaw"
        case .configuration:
            return "Configuring OpenClaw"
        case .complete:
            return "Installation complete!"
        }
    }
}

@MainActor
class InstallationState: ObservableObject {
    @Published var currentStep: InstallationStep = .welcome
    @Published var isInstalling = false
    @Published var errorMessage: String?
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var canProceed = true
    @Published var canGoBack = false

    // Installation flags
    @Published var nodeInstallationRequired = false
    @Published var nodeInstallationComplete = false
    @Published var openclawInstallationRequired = false
    @Published var openclawInstallationComplete = false
    @Published var configurationComplete = false

    /// Move to next step
    func nextStep() {
        guard let currentIndex = InstallationStep.allCases.firstIndex(of: currentStep) else {
            return
        }

        if currentIndex < InstallationStep.allCases.count - 1 {
            currentStep = InstallationStep.allCases[currentIndex + 1]
            updateNavigationState()
        }
    }

    /// Move to previous step
    func previousStep() {
        guard let currentIndex = InstallationStep.allCases.firstIndex(of: currentStep) else {
            return
        }

        if currentIndex > 0 {
            currentStep = InstallationStep.allCases[currentIndex - 1]
            updateNavigationState()
        }
    }

    /// Go to specific step
    func goToStep(_ step: InstallationStep) {
        currentStep = step
        updateNavigationState()
    }

    /// Update navigation button states
    private func updateNavigationState() {
        canGoBack = currentStep != .welcome && !isInstalling
        canProceed = !isInstalling

        // Special rules for specific steps
        switch currentStep {
        case .complete:
            canGoBack = false
            canProceed = false
        case .environmentCheck, .nodeInstallation, .openclawInstallation:
            canGoBack = false
        default:
            break
        }
    }

    /// Reset installation state
    func reset() {
        currentStep = .welcome
        isInstalling = false
        errorMessage = nil
        progress = 0.0
        statusMessage = ""
        nodeInstallationRequired = false
        nodeInstallationComplete = false
        openclawInstallationRequired = false
        openclawInstallationComplete = false
        configurationComplete = false
        updateNavigationState()
    }

    /// Set error
    func setError(_ message: String) {
        errorMessage = message
        isInstalling = false
    }

    /// Clear error
    func clearError() {
        errorMessage = nil
    }

    /// Update progress
    func updateProgress(_ value: Double, message: String = "") {
        progress = value
        if !message.isEmpty {
            statusMessage = message
        }
    }
}
