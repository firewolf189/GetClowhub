import SwiftUI
import AppKit
import Combine
import UserNotifications

private extension ServiceStatus {
    var localizedTitle: String {
        switch self {
        case .running: return I18n.t("dashboard.status.service.running")
        case .stopped: return I18n.t("dashboard.status.service.stopped")
        case .starting: return I18n.t("dashboard.status.service.starting")
        case .stopping: return I18n.t("dashboard.status.service.stopping")
        case .error: return I18n.t("dashboard.status.service.error")
        case .unknown: return I18n.t("dashboard.status.service.unknown")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Service reference (to be set from App)
    var openclawService: OpenClawService?

    // Sparkle updater reference (to be set from App)
    var sparkleUpdater: SparkleUpdater?

    // Auth manager reference (to be set from App)
    var authManager: AuthManager?

    // Membership manager reference (to be set from App)
    #if REQUIRE_LOGIN
    var membershipManager: MembershipManager?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        cleanupMainMenu()
        requestNotificationPermission()
        maximizeWindowOnFirstLaunch()
    }

    /// Maximize the main window on first launch
    private func maximizeWindowOnFirstLaunch() {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.zoom(nil)
            }
        }
    }

    /// Request notification permission on app launch
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("[AppDelegate] Notification permission requested - granted: \(granted), error: \(error?.localizedDescription ?? "none")")
        }
    }

    // MARK: - Main Menu Cleanup

    /// Remove unwanted menus and menu items that SwiftUI auto-generates.
    private func cleanupMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // Remove top-level menus: View, Help
        for item in mainMenu.items.reversed() {
            let title = item.submenu?.title ?? ""
            if title == "View" || title == "Help" {
                removeItemIfPresent(item, from: mainMenu)
            }
        }

        // Remove "Services" from the App menu (first menu)
        if let appMenu = mainMenu.items.first?.submenu {
            for (index, item) in appMenu.items.enumerated().reversed() {
                if item.title == "Services" || item.submenu === NSApp.servicesMenu {
                    removeItemIfPresent(item, from: appMenu)
                    // Remove the separator above it if present
                    if index > 0 && index - 1 < appMenu.items.count
                        && appMenu.items[index - 1].isSeparatorItem {
                        appMenu.removeItem(at: index - 1)
                    }
                }
            }
            NSApp.servicesMenu = nil
        }
    }

    private func removeItemIfPresent(_ item: NSMenuItem, from menu: NSMenu) {
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.removeItem(at: index)
    }

    @objc func copy(_ sender: Any?) {
        if NativeSelectableTextSelectionRegistry.copySelectedTextFromFirstResponder(sender) {
            return
        }
        if NativeSelectableTextSelectionRegistry.copyActiveSelection() {
            return
        }
        if WebViewMarkdownSelectionRegistry.copyActiveSelection() {
            return
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private var localizedServiceStatus: String {
        openclawService?.status.localizedTitle ?? I18n.t("dashboard.status.service.unknown")
    }

    func createMenu() -> NSMenu {
        let menu = NSMenu()
        #if REQUIRE_LOGIN
        let loggedIn = authManager?.isLoggedIn ?? false
        #else
        let loggedIn = true
        #endif

        // Status item
        let statusItem = NSMenuItem(
            title: I18n.format("menu.status.statusLine", localizedServiceStatus),
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop
        if openclawService?.status == .running {
            let stopItem = NSMenuItem(
                title: I18n.t("menu.status.stopService"),
                action: #selector(stopService),
                keyEquivalent: "s"
            )
            stopItem.isEnabled = loggedIn
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: I18n.t("menu.status.startService"),
                action: #selector(startService),
                keyEquivalent: "s"
            )
            startItem.isEnabled = loggedIn
            menu.addItem(startItem)
        }

        let restartItem = NSMenuItem(
            title: I18n.t("menu.status.restartService"),
            action: #selector(restartService),
            keyEquivalent: "r"
        )
        restartItem.isEnabled = loggedIn
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        // Dashboard
        let dashboardItem = NSMenuItem(
            title: I18n.t("menu.status.openDashboard"),
            action: #selector(openDashboardFromMenu),
            keyEquivalent: "d"
        )
        dashboardItem.isEnabled = loggedIn && openclawService?.status == .running
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem(
            title: I18n.t("menu.status.showMainWindow"),
            action: #selector(showMainWindow),
            keyEquivalent: "w"
        ))

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        menu.addItem(NSMenuItem(
            title: I18n.t("menu.status.checkUpdates"),
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        ))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: I18n.t("menu.status.quitInstaller"),
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

                    Text(openclawService?.status.localizedTitle ?? I18n.t("dashboard.status.service.unknown"))
                        .font(.body)

                    Spacer()
                }

                if let service = openclawService, service.status == .running {
                    HStack {
                        Text(I18n.t("menu.status.uptime"))
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
                        title: I18n.t("menu.status.openDashboard"),
                        icon: "safari",
                        action: {
                            openclawService?.openDashboard()
                            onClose()
                        }
                    )

                    MenuButton(
                        title: I18n.t("menu.status.stopService"),
                        icon: "stop.fill",
                        action: {
                            Task {
                                try? await openclawService?.stop()
                            }
                        }
                    )
                } else {
                    MenuButton(
                        title: I18n.t("menu.status.startService"),
                        icon: "play.fill",
                        action: {
                            Task {
                                try? await openclawService?.start()
                            }
                        }
                    )
                }

                MenuButton(
                    title: I18n.t("menu.status.showMainWindow"),
                    icon: "macwindow",
                    action: onOpenDashboard
                )
            }

            Divider()

            // Version info
            VStack(spacing: 2) {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text(I18n.format("menu.status.helperVersion", appVersion, buildNumber))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let version = openclawService?.version, !version.isEmpty {
                    Text(I18n.format("menu.status.serviceVersion", version))
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
