import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var viewModel: InstallationViewModel

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Title
            VStack(spacing: 12) {
                Image("Logo1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                BrandTextView()

                Text(I18n.t("install.config.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(I18n.t("install.config.subtitle"))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Configuration form
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(I18n.t("install.config.authToken"))
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField(I18n.t("install.config.tokenPlaceholder"), text: $viewModel.gatewayAuthToken)
                            .textFieldStyle(.roundedBorder)

                        Button(action: {
                            viewModel.generateRandomToken()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "dice")
                                Text(I18n.t("install.action.generate"))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 500)

                    Text(I18n.t("install.config.tokenHelp"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 100)

            // Info box
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(I18n.t("install.config.whyToken"))
                        .font(.headline)

                    Text(I18n.t("install.config.whyTokenDetail"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 100)

            Spacer()

            // Action button
            HStack {
                Spacer()

                Button(action: {
                    Task {
                        await viewModel.saveTokenAndContinue()
                    }
                }) {
                    HStack {
                        Text(I18n.t("install.action.continue"))
                        Image(systemName: "arrow.right")
                    }
                    .frame(width: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.gatewayAuthToken.isEmpty || viewModel.installationState.isInstalling)
            }
            .padding(.horizontal, 100)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConfigurationView(
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
