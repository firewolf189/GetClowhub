import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Service reference (to be set from App)
    var openclawService: OpenClawService?

    // Sparkle updater reference (to be set from App)
    var sparkleUpdater: SparkleUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        statusItem = nil
        openclawService?.stopMonitoring()
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Set default icon
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "OpenClaw")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true

        // Update icon based on service status
        startMonitoringServiceStatus()
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                showPopover(button)
            }
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        // Create menu view
        if let popover = popover {
            popover.contentViewController = NSHostingController(
                rootView: MenuBarPopoverView(
                    openclawService: openclawService,
                    onClose: { [weak self] in
                        self?.popover?.performClose(nil)
                    },
                    onOpenDashboard: { [weak self] in
                        self?.openMainWindow()
                        self?.popover?.performClose(nil)
                    }
                )
            )
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    // MARK: - Status Monitoring

    private func startMonitoringServiceStatus() {
        // Update icon periodically based on service status
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarIcon()
        }

        // Initial update
        updateMenuBarIcon()
    }

    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let status = openclawService?.status ?? .unknown

        // Update icon based on status
        let iconName: String
        switch status {
        case .running:
            iconName = "checkmark.circle.fill"
        case .stopped:
            iconName = "stop.circle"
        case .starting, .stopping:
            iconName = "arrow.clockwise.circle"
        case .error:
            iconName = "exclamationmark.triangle.fill"
        case .unknown:
            iconName = "questionmark.circle"
        }

        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "OpenClaw - \(status.rawValue)")

        // Add tooltip
        button.toolTip = "OpenClaw - \(status.rawValue)"
    }

    // MARK: - Window Management

    func openMainWindow() {
        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        // Show main window
        for window in NSApp.windows {
            if window.title.contains("OpenClaw") || window.isMainWindow {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }

        // If no window found, create one (handled by SwiftUI App)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Actions

    func createMenu() -> NSMenu {
        let menu = NSMenu()

        // Status item
        let statusItem = NSMenuItem(
            title: "Status: \(openclawService?.status.rawValue ?? "Unknown")",
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop
        if openclawService?.status == .running {
            menu.addItem(NSMenuItem(
                title: "Stop Service",
                action: #selector(stopService),
                keyEquivalent: "s"
            ))
        } else {
            menu.addItem(NSMenuItem(
                title: "Start Service",
                action: #selector(startService),
                keyEquivalent: "s"
            ))
        }

        menu.addItem(NSMenuItem(
            title: "Restart Service",
            action: #selector(restartService),
            keyEquivalent: "r"
        ))

        menu.addItem(NSMenuItem.separator())

        // Dashboard
        let dashboardItem = NSMenuItem(
            title: "Open Dashboard",
            action: #selector(openDashboardFromMenu),
            keyEquivalent: "d"
        )
        dashboardItem.isEnabled = openclawService?.status == .running
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem(
            title: "Show Main Window",
            action: #selector(showMainWindow),
            keyEquivalent: "w"
        ))

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        menu.addItem(NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        ))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit OpenClaw Installer",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))

        // Set target for all items
        for item in menu.items {
            item.target = self
        }

        return menu
    }

    // MARK: - Menu Actions

    @objc func startService() {
        Task { @MainActor in
            try? await openclawService?.start()
        }
    }

    @objc func stopService() {
        Task { @MainActor in
            try? await openclawService?.stop()
        }
    }

    @objc func restartService() {
        Task { @MainActor in
            try? await openclawService?.restart()
        }
    }

    @objc func openDashboardFromMenu() {
        openclawService?.openDashboard()
    }

    @objc func showMainWindow() {
        openMainWindow()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func checkForUpdates() {
        sparkleUpdater?.checkForUpdates()
    }

    // MARK: - Context Menu Support

    func showContextMenu() {
        guard let button = statusItem?.button else { return }

        let menu = createMenu()
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }
}

// MARK: - Menu Bar Popover View

struct MenuBarPopoverView: View {
    let openclawService: OpenClawService?
    let onClose: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("OpenClaw")
                    .font(.headline)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Status
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(openclawService?.status.rawValue ?? "Unknown")
                        .font(.body)

                    Spacer()
                }

                if let service = openclawService, service.status == .running {
                    HStack {
                        Text("Uptime:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(formatUptime(service.uptime))
                            .font(.caption)

                        Spacer()
                    }
                }
            }

            Divider()

            // Quick Actions
            VStack(spacing: 8) {
                if openclawService?.status == .running {
                    MenuButton(
                        title: "Open Dashboard",
                        icon: "safari",
                        action: {
                            openclawService?.openDashboard()
                            onClose()
                        }
                    )

                    MenuButton(
                        title: "Stop Service",
                        icon: "stop.fill",
                        action: {
                            Task {
                                try? await openclawService?.stop()
                            }
                        }
                    )
                } else {
                    MenuButton(
                        title: "Start Service",
                        icon: "play.fill",
                        action: {
                            Task {
                                try? await openclawService?.start()
                            }
                        }
                    )
                }

                MenuButton(
                    title: "Show Main Window",
                    icon: "macwindow",
                    action: onOpenDashboard
                )
            }

            Divider()

            // Version info
            VStack(spacing: 2) {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text("OpenClaw Helper v\(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let version = openclawService?.version, !version.isEmpty {
                    Text("OpenClaw Service \(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 250)
    }

    private var statusColor: Color {
        guard let status = openclawService?.status else { return .gray }

        switch status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)

                Text(title)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
