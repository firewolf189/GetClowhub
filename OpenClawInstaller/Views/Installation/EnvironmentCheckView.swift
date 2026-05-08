import SwiftUI

struct EnvironmentCheckView: View {
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

                Text("Environment Check")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(viewModel.installationState.statusMessage.isEmpty ?
                     "Checking your system environment..." :
                     viewModel.installationState.statusMessage)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // Check results
            if !viewModel.systemEnvironment.isChecking {
                VStack(alignment: .leading, spacing: 16) {
                    CheckResultRow(
                        title: "Operating System",
                        value: "macOS \(viewModel.systemEnvironment.osVersion)",
                        status: .success
                    )

                    CheckResultRow(
                        title: "Architecture",
                        value: viewModel.systemEnvironment.architecture,
                        status: .success
                    )

                    CheckResultRow(
                        title: "Available Disk Space",
                        value: viewModel.systemEnvironment.availableDiskSpace,
                        status: .success
                    )

                    Divider()

                    // We ship our own Node.js v24.14.0 to ~/.openclaw/node/bin and run
                    // openclaw exclusively against that, so the user's system Node
                    // version is never a blocker — show whatever we detected (or
                    // "未安装") as plain info, with a caption clarifying the bundled
                    // runtime is independent.
                    CheckResultRow(
                        title: "Node.js",
                        value: {
                            if let v = viewModel.systemEnvironment.nodeInfo?.version {
                                return "\(v) (将使用内置 v24.14.0)"
                            }
                            return "未安装 (将自动安装内置 v24.14.0)"
                        }(),
                        status: .info
                    )

                    Text("ℹ️ OpenClaw 自带独立的 Node.js v24.14.0，无需系统 Node 即可运行")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 40)

                    CheckResultRow(
                        title: "OpenClaw",
                        value: viewModel.systemEnvironment.openclawInfo?.version ?? "Not Installed",
                        status: viewModel.systemEnvironment.openclawInfo != nil ? .success : .info
                    )
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal, 60)
            }

            // Error message
            if let errorMessage = viewModel.installationState.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues Found:")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 60)
            }

            Spacer()

            // Action buttons
            if !viewModel.systemEnvironment.isChecking {
                HStack(spacing: 16) {
                    if viewModel.installationState.errorMessage != nil {
                        Button(action: {
                            Task {
                                await viewModel.retryCurrentStep()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry")
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !viewModel.systemEnvironment.isChecking &&
               viewModel.installationState.currentStep == .environmentCheck {
                Task {
                    await viewModel.performEnvironmentCheck()
                }
            }
        }
    }
}

enum CheckStatus {
    case success
    case warning
    case error
    case info

    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct CheckResultRow: View {
    let title: String
    let value: String
    let status: CheckStatus

    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .frame(width: 20)

            Text(title)
                .frame(width: 180, alignment: .leading)
                .fontWeight(.medium)

            Text(value)
                .foregroundColor(.secondary)

            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    EnvironmentCheckView(
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
