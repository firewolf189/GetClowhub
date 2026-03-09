import SwiftUI
import Combine

/// Single container that owns all shared service objects.
/// Created once as a @StateObject in the App, never recreated.
@MainActor
class AppServices: ObservableObject {
    let permissionManager: PermissionManager
    let installationState: InstallationState
    let settingsManager: AppSettingsManager
    let commandExecutor: CommandExecutor
    let systemEnvironment: SystemEnvironment
    let openclawService: OpenClawService
    let installationViewModel: InstallationViewModel
    let dashboardViewModel: DashboardViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        let pm = PermissionManager()
        let is_ = InstallationState()
        let sm = AppSettingsManager()
        let ce = CommandExecutor(permissionManager: pm)
        let se = SystemEnvironment(commandExecutor: ce)
        let os = OpenClawService(commandExecutor: ce)

        self.permissionManager = pm
        self.installationState = is_
        self.settingsManager = sm
        self.commandExecutor = ce
        self.systemEnvironment = se
        self.openclawService = os
        self.installationViewModel = InstallationViewModel(
            installationState: is_,
            systemEnvironment: se,
            commandExecutor: ce,
            openclawService: os
        )
        self.dashboardViewModel = DashboardViewModel(
            openclawService: os,
            settings: sm,
            systemEnvironment: se,
            commandExecutor: ce
        )

        // Forward child objectWillChange so SwiftUI re-renders
        se.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

@main
struct OpenClawInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var services = AppServices()
    @StateObject private var sparkleUpdater = SparkleUpdater()

    @State private var showPermissionAlert = false

    var body: some Scene {
        WindowGroup {
            MainContentView(services: services)
                .frame(minWidth: 960, minHeight: 680)
                .onAppear {
                    appDelegate.openclawService = services.openclawService
                    appDelegate.sparkleUpdater = sparkleUpdater
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Main Content View Router

struct MainContentView: View {
    @ObservedObject var services: AppServices

    @State private var viewMode: ViewMode = .initial

    enum ViewMode {
        case initial
        case installation
        case dashboard
    }

    var body: some View {
        Group {
            switch viewMode {
            case .initial:
                InitialView(
                    systemEnvironment: services.systemEnvironment,
                    onStartInstallation: {
                        viewMode = .installation
                    },
                    onOpenDashboard: {
                        viewMode = .dashboard
                    }
                )

            case .installation:
                InstallationWizardView(
                    viewModel: services.installationViewModel,
                    onFinish: {
                        viewMode = .dashboard
                    }
                )
                .onAppear {
                    services.installationState.goToStep(.welcome)
                }

            case .dashboard:
                DashboardView(
                    viewModel: services.dashboardViewModel
                )
                .onAppear {
                    // Reload config from disk in case installation wizard just wrote new values
                    services.dashboardViewModel.loadConfiguration()
                }
            }
        }
        .task {
            await determineInitialView()
        }
    }

    private func determineInitialView() async {
        // Always start on the initial landing page.
        // The InitialView will show different options depending on
        // whether OpenClaw is detected (dashboard button vs install button).
        await services.systemEnvironment.performFullCheck()
        viewMode = .initial
    }
}

// MARK: - Initial View (Landing Page)

struct InitialView: View {
    @ObservedObject var systemEnvironment: SystemEnvironment

    let onStartInstallation: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("OpenClaw Helper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if systemEnvironment.isChecking {
                ProgressView()
                    .scaleEffect(1.2)
            } else if systemEnvironment.openclawInfo != nil {
                VStack(spacing: 16) {
                    Text("OpenClaw is installed")
                        .font(.title3)
                        .foregroundColor(.green)

                    HStack(spacing: 16) {
                        Button(action: onOpenDashboard) {
                            HStack {
                                Text("Open Dashboard")
                                Image(systemName: "arrow.right")
                            }
                            .frame(width: 180)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: onStartInstallation) {
                            HStack {
                                Text("Reinstall")
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .frame(width: 120)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Text("Ready to install OpenClaw")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Button(action: onStartInstallation) {
                        HStack {
                            Text("Start Installation")
                            Image(systemName: "arrow.right")
                        }
                        .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
