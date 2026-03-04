import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: InstallationViewModel

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon and title
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Welcome to OpenClaw Installer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("This wizard will guide you through installing OpenClaw on your Mac")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "checkmark.circle.fill",
                    title: "Automated Installation",
                    description: "Installs Node.js and OpenClaw automatically"
                )

                FeatureRow(
                    icon: "gear.circle.fill",
                    title: "Easy Configuration",
                    description: "Guided setup for your OpenClaw instance"
                )

                FeatureRow(
                    icon: "shield.checkered",
                    title: "Secure",
                    description: "Requires administrator privileges for system-level installation"
                )

                FeatureRow(
                    icon: "clock.fill",
                    title: "Quick Setup",
                    description: "Complete installation in just a few minutes"
                )
            }
            .padding(.horizontal, 100)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    startInstallation()
                }) {
                    HStack {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .frame(width: 160)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startInstallation() {
        viewModel.installationState.goToStep(.environmentCheck)
        Task {
            await viewModel.performEnvironmentCheck()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView(
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
