import SwiftUI

struct ContentView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var installationState: InstallationState
    @EnvironmentObject var settingsManager: AppSettingsManager

    @StateObject private var commandExecutor: CommandExecutor
    @StateObject private var systemEnvironment: SystemEnvironment

    @State private var isCheckingEnvironment = false

    init() {
        // Initialize command executor with permission manager
        // Note: We'll get the actual permission manager from environment
        let tempPermissionManager = PermissionManager()
        let executor = CommandExecutor(permissionManager: tempPermissionManager)
        _commandExecutor = StateObject(wrappedValue: executor)
        _systemEnvironment = StateObject(wrappedValue: SystemEnvironment(commandExecutor: executor))
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("OpenClaw Installer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("for macOS")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            Divider()
                .padding(.horizontal, 40)

            // Status Section
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    title: "Administrator Privileges",
                    status: permissionManager.isAuthorized ? "Granted" : "Not Granted",
                    icon: permissionManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: permissionManager.isAuthorized ? .green : .red
                )

                if isCheckingEnvironment {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking environment...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    StatusRow(
                        title: "Node.js",
                        status: systemEnvironment.nodeInfo?.version ?? "Not Detected",
                        icon: systemEnvironment.nodeInfo != nil ? "checkmark.circle.fill" : "circle",
                        color: systemEnvironment.nodeInfo != nil ? .green : .gray
                    )

                    StatusRow(
                        title: "OpenClaw",
                        status: systemEnvironment.openclawInfo?.version ?? "Not Detected",
                        icon: systemEnvironment.openclawInfo != nil ? "checkmark.circle.fill" : "circle",
                        color: systemEnvironment.openclawInfo != nil ? .green : .gray
                    )
                }

                Divider()

                // System Info
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Information")
                        .font(.headline)
                        .padding(.bottom, 4)

                    InfoRow(label: "macOS Version", value: systemEnvironment.osVersion)
                    InfoRow(label: "Architecture", value: systemEnvironment.architecture)
                    InfoRow(label: "Available Space", value: systemEnvironment.availableDiskSpace)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        isCheckingEnvironment = true
                        await systemEnvironment.performFullCheck()
                        isCheckingEnvironment = false
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Environment")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingEnvironment)

                Button(action: {
                    // TODO: Start installation wizard
                    installationState.nextStep()
                }) {
                    HStack {
                        Text("Start Installation")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!permissionManager.isAuthorized)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Initial environment check
            isCheckingEnvironment = true
            await systemEnvironment.performFullCheck()
            isCheckingEnvironment = false
        }
    }
}

// MARK: - Helper Views

struct StatusRow: View {
    let title: String
    let status: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            Text(title)
                .frame(width: 150, alignment: .leading)

            Text(status)
                .foregroundColor(.secondary)

            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    ContentView()
        .environmentObject(PermissionManager())
        .environmentObject(InstallationState())
        .environmentObject(AppSettingsManager())
        .frame(width: 800, height: 600)
}
