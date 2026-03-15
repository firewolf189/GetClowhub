import SwiftUI

struct CompletionView: View {
    @ObservedObject var viewModel: InstallationViewModel
    var onFinish: (() -> Void)?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Success icon
            VStack(spacing: 16) {
                Image("Logo1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                BrandTextView()

                Text("Installation Complete!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("OpenClaw has been successfully installed on your Mac")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // Installation summary
            VStack(spacing: 16) {
                SummaryRow(
                    icon: "checkmark.circle.fill",
                    title: "Node.js",
                    value: viewModel.systemEnvironment.nodeInfo?.version ?? "Installed",
                    color: .green
                )

                SummaryRow(
                    icon: "checkmark.circle.fill",
                    title: "OpenClaw",
                    value: viewModel.systemEnvironment.openclawInfo?.version ?? "Installed",
                    color: .green
                )

                if viewModel.installationState.configurationComplete {
                    SummaryRow(
                        icon: "checkmark.circle.fill",
                        title: "Configuration",
                        value: "Completed",
                        color: .green
                    )
                }

                // Gateway status row
                if viewModel.gatewayStarting {
                    SummaryRow(
                        icon: "arrow.clockwise.circle.fill",
                        title: "Gateway",
                        value: "Starting...",
                        color: .orange
                    )
                } else if viewModel.gatewayStarted {
                    SummaryRow(
                        icon: "checkmark.circle.fill",
                        title: "Gateway",
                        value: "Running",
                        color: .green
                    )
                } else if let error = viewModel.gatewayError {
                    SummaryRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Gateway",
                        value: error,
                        color: .red
                    )
                }
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 100)

            // Gateway status message
            if viewModel.gatewayStarting {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Starting OpenClaw Gateway service...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.gatewayStarted {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("OpenClaw Gateway 已启动")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 100)
            } else if let errMsg = viewModel.gatewayError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Gateway failed to start")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Text(errMsg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 100)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                if viewModel.gatewayError != nil {
                    Button(action: {
                        Task {
                            await viewModel.startGateway()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Start")
                        }
                        .frame(width: 180)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: {
                    onFinish?()
                }) {
                    HStack {
                        Text("Go to Management")
                        Image(systemName: "arrow.right")
                    }
                    .frame(width: 180)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.gatewayStarting)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.startGateway()
        }
    }
}

struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(title)
                .frame(width: 120, alignment: .leading)
                .fontWeight(.medium)

            Text(value)
                .foregroundColor(.secondary)

            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

struct NextStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)

                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    CompletionView(
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
