import SwiftUI

struct NodeInstallationView: View {
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

                Text("Node.js Installation")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(viewModel.nodeInstaller.installationStatus.isEmpty ?
                     "Installing Node.js..." :
                     viewModel.nodeInstaller.installationStatus)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }

            // Installation log
            if !viewModel.nodeInstaller.installationLog.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("Installation Log")
                            .font(.headline)

                        Spacer()

                        if viewModel.nodeInstaller.isInstalling {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Installing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    ScrollView {
                        ScrollViewReader { proxy in
                            Text(viewModel.nodeInstaller.installationLog)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                                .id("logBottom")
                                .onChange(of: viewModel.nodeInstaller.installationLog) { _ in
                                    withAnimation {
                                        proxy.scrollTo("logBottom", anchor: .bottom)
                                    }
                                }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
                .padding(.horizontal, 60)
            }

            // Progress section
            if viewModel.nodeInstaller.isInstalling {
                VStack(spacing: 16) {
                    // Progress bar with detailed status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                            Text("Installing Node.js")
                                .font(.headline)

                            Spacer()

                            Text("\(Int(viewModel.nodeInstaller.downloadProgress * 100))%")
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }

                        ProgressView(value: viewModel.nodeInstaller.downloadProgress)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 3)
                            .animation(.easeInOut, value: viewModel.nodeInstaller.downloadProgress)

                        // Detailed status message
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            Text(viewModel.nodeInstaller.installationStatus)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 80)
            }

            // Error message
            if let error = viewModel.nodeInstaller.error {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)

                        Text("Installation Failed")
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error Details:")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(error.localizedDescription)
                            .font(.body)
                            .foregroundColor(.primary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Possible Solutions:")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Check your internet connection")
                            Text("• Verify you have sufficient disk space")
                            Text("• Try using a VPN if downloads are slow")
                            Text("• Click 'Retry' to attempt installation again")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 60)
            }

            // Success info
            if viewModel.installationState.nodeInstallationComplete {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)

                        Text("Node.js Successfully Installed!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }

                    Divider()

                    if let nodeInfo = viewModel.systemEnvironment.nodeInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.green)
                                Text("Version:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(nodeInfo.version)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.green)
                                Text("Location:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(nodeInfo.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            HStack {
                                Image(systemName: "checkmark.shield")
                                    .foregroundColor(.green)
                                Text("Status:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Ready to use")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 80)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                if viewModel.nodeInstaller.error != nil {
                    Button(action: {
                        viewModel.nodeInstaller.reset()
                        Task {
                            await viewModel.installNodeJS()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .frame(width: 140)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        viewModel.cancelInstallation()
                    }) {
                        Text("Cancel")
                            .frame(width: 140)
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.nodeInstaller.isInstalling {
                    Button(action: {
                        viewModel.nodeInstaller.cancelDownload()
                    }) {
                        Text("Cancel")
                            .frame(width: 140)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !viewModel.nodeInstaller.isInstalling &&
               !viewModel.installationState.nodeInstallationComplete &&
               viewModel.installationState.currentStep == .nodeInstallation {
                Task {
                    await viewModel.installNodeJS()
                }
            }
        }
    }
}

#Preview {
    NodeInstallationView(
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
