import SwiftUI
import UniformTypeIdentifiers

struct LogsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var searchText: String = ""
    @State private var isAutoRefresh = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            LogsToolbar(
                searchText: $searchText,
                isAutoRefresh: $isAutoRefresh,
                isLoading: viewModel.isLoadingLogs,
                onRefresh: {
                    Task {
                        await viewModel.loadGatewayLogs()
                    }
                },
                onExport: {
                    exportLogsToFile()
                },
                onOpenFile: {
                    viewModel.openLogFile()
                }
            )
            .padding(16)

            Divider()

            // Logs display
            LogsDisplay(
                logs: filteredLogs,
                isEmpty: viewModel.gatewayLogs.isEmpty,
                isLoading: viewModel.isLoadingLogs
            )
            .padding(16)
        }
        .onAppear {
            if isAutoRefresh {
                viewModel.startLogRefresh()
            }
        }
        .onDisappear {
            viewModel.stopLogRefresh()
        }
        .onChange(of: isAutoRefresh) { newValue in
            if newValue {
                viewModel.startLogRefresh()
            } else {
                viewModel.stopLogRefresh()
            }
        }
    }

    private var filteredLogs: [String] {
        if searchText.isEmpty {
            return viewModel.gatewayLogs
        }
        return viewModel.gatewayLogs.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func exportLogsToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "openclaw-gateway-logs-\(Date().timeIntervalSince1970).txt"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let logsString = viewModel.gatewayLogs.joined(separator: "\n")
                try? logsString.write(to: url, atomically: true, encoding: .utf8)
                viewModel.showSuccess = true
                viewModel.successMessage = "Logs exported successfully"
            }
        }
    }
}

// MARK: - Logs Toolbar

struct LogsToolbar: View {
    @Binding var searchText: String
    @Binding var isAutoRefresh: Bool
    let isLoading: Bool
    let onRefresh: () -> Void
    let onExport: () -> Void
    let onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Auto-refresh toggle
                Toggle(isOn: $isAutoRefresh) {
                    Label("Auto", systemImage: "arrow.clockwise")
                }
                .toggleStyle(.switch)
                .frame(width: 100)
            }

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button(action: onOpenFile) {
                    Label("Open File", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Text("gateway.log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Logs Display

struct LogsDisplay: View {
    let logs: [String]
    let isEmpty: Bool
    let isLoading: Bool

    var body: some View {
        if isEmpty && !isLoading {
            EmptyLogsView()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                            LogLine(text: log)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onChange(of: logs.count) { _ in
                    // Auto-scroll to bottom when new logs arrive
                    if let lastIndex = logs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct LogLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(lineColor)
            .padding(.vertical, 2)
            .textSelection(.enabled)
    }

    private var lineColor: Color {
        let lower = text.lowercased()
        if lower.contains("error") || lower.contains("fatal") {
            return .red
        } else if lower.contains("warn") {
            return .orange
        } else if lower.contains("info") {
            return .blue
        } else {
            return .primary
        }
    }
}

struct EmptyLogsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Logs Available")
                .font(.title3)
                .fontWeight(.medium)

            Text("Logs will appear here when the gateway service is running")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    LogsTabView(
        viewModel: DashboardViewModel(
            openclawService: OpenClawService(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            settings: AppSettingsManager(),
            systemEnvironment: SystemEnvironment(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            commandExecutor: CommandExecutor(
                permissionManager: PermissionManager()
            )
        )
    )
    .frame(width: 700, height: 600)
}
