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

                Text("Gateway Configuration")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Set an auth token to secure your OpenClaw gateway")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Configuration form
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gateway Auth Token")
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField("Enter a token for gateway access", text: $viewModel.gatewayAuthToken)
                            .textFieldStyle(.roundedBorder)

                        Button(action: {
                            viewModel.generateRandomToken()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "dice")
                                Text("Generate")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 500)

                    Text("This token is required to access the OpenClaw dashboard and API. You can change it later in the configuration page.")
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
                    Text("Why is a token needed?")
                        .font(.headline)

                    Text("The auth token protects your gateway from unauthorized access. It will be written to ~/.openclaw/openclaw.json and used when opening the dashboard.")
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
                        Text("Continue")
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
