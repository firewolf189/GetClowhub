import SwiftUI

struct InstallationWizardView: View {
    @ObservedObject var viewModel: InstallationViewModel
    var onFinish: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressIndicatorView(currentStep: viewModel.installationState.currentStep)
                .padding(.top, 20)
                .padding(.horizontal, 40)

            Divider()
                .padding(.vertical, 16)

            // Current step view
            ZStack {
                switch viewModel.installationState.currentStep {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                case .environmentCheck:
                    EnvironmentCheckView(viewModel: viewModel)
                case .nodeInstallation:
                    NodeInstallationView(viewModel: viewModel)
                case .openclawInstallation:
                    OpenClawInstallationView(viewModel: viewModel)
                case .configuration:
                    ConfigurationView(viewModel: viewModel)
                case .complete:
                    CompletionView(viewModel: viewModel, onFinish: onFinish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut, value: viewModel.installationState.currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Progress Indicator

struct ProgressIndicatorView: View {
    let currentStep: InstallationStep

    private let steps: [InstallationStep] = [
        .welcome,
        .environmentCheck,
        .nodeInstallation,
        .openclawInstallation,
        .configuration,
        .complete
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 0) {
                    // Step circle
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 32, height: 32)

                        if isStepComplete(step) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                        } else {
                            Text("\(step.stepNumber)")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }

                    // Connecting line (if not last step)
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(isStepComplete(steps[index + 1]) ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func stepColor(for step: InstallationStep) -> Color {
        if step.stepNumber < currentStep.stepNumber {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }

    private func isStepComplete(_ step: InstallationStep) -> Bool {
        return step.stepNumber < currentStep.stepNumber
    }
}

#Preview {
    InstallationWizardView(
        viewModel: InstallationViewModel(
            installationState: InstallationState(),
            systemEnvironment: SystemEnvironment(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            commandExecutor: CommandExecutor(
                permissionManager: PermissionManager()
            ),
            openclawService: OpenClawService(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            )
        )
    )
    .frame(width: 800, height: 600)
}
