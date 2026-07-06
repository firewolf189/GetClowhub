import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: InstallationViewModel

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo and title
            VStack(spacing: 16) {
                Image("Logo1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                BrandTextView()

                Text(I18n.t("install.welcome.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(I18n.t("install.welcome.subtitle"))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "checkmark.circle.fill",
                    title: I18n.t("install.welcome.feature.automated.title"),
                    description: I18n.t("install.welcome.feature.automated.description")
                )

                FeatureRow(
                    icon: "gear.circle.fill",
                    title: I18n.t("install.welcome.feature.configuration.title"),
                    description: I18n.t("install.welcome.feature.configuration.description")
                )

                FeatureRow(
                    icon: "shield.checkered",
                    title: I18n.t("install.welcome.feature.secure.title"),
                    description: I18n.t("install.welcome.feature.secure.description")
                )

                FeatureRow(
                    icon: "clock.fill",
                    title: I18n.t("install.welcome.feature.quick.title"),
                    description: I18n.t("install.welcome.feature.quick.description")
                )
            }
            .padding(.horizontal, 100)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text(I18n.t("install.action.quit"))
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    startInstallation()
                }) {
                    HStack {
                        Text(I18n.t("install.action.getStarted"))
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
