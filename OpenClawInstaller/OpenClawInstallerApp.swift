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
    private let coreUpgradeCoordinator: OpenClawCoreUpgradeCoordinator
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
        let cuc = OpenClawCoreUpgradeCoordinator(commandExecutor: ce, openclawService: os)

        self.permissionManager = pm
        self.installationState = is_
        self.settingsManager = sm
        self.commandExecutor = ce
        self.systemEnvironment = se
        self.openclawService = os
        self.coreUpgradeCoordinator = cuc
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

    func ensureOpenClawCoreIsCurrent() async {
        await coreUpgradeCoordinator.ensureBundledCoreIsCurrent()
    }

    func ensureBundledCoreForInstalledOpenClaw() async {
        await systemEnvironment.detectOpenClaw()
        guard systemEnvironment.openclawInfo != nil else {
            return
        }
        await ensureOpenClawCoreIsCurrent()
        await systemEnvironment.detectOpenClaw()
        await openclawService.fetchVersion()
    }
}

@main
struct OpenClawInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var services = AppServices()
    @StateObject private var sparkleUpdater = SparkleUpdater()
    @StateObject private var languageManager = LanguageManager.shared
    #if REQUIRE_LOGIN
    @StateObject private var authManager = AuthManager()
    @StateObject private var membershipManager = MembershipManager()
    #endif

    @State private var showPermissionAlert = false
    @State private var didStartBundledCoreCheck = false

    var body: some Scene {
        WindowGroup {
            MainContentView(services: services)
                .frame(minWidth: 960, minHeight: 680)
                .environmentObject(sparkleUpdater)
                .environmentObject(languageManager)
                #if REQUIRE_LOGIN
                .environmentObject(authManager)
                .environmentObject(membershipManager)
                #endif
                .environment(\.locale, languageManager.currentLocale)
                .id(languageManager.selectedLanguage)
                .onAppear {
                    appDelegate.openclawService = services.openclawService
                    appDelegate.sparkleUpdater = sparkleUpdater
                    Task { await sparkleUpdater.checkLatestVersionOnLaunch() }
                    if !didStartBundledCoreCheck {
                        didStartBundledCoreCheck = true
                        Task { await services.ensureBundledCoreForInstalledOpenClaw() }
                    }
                    #if REQUIRE_LOGIN
                    appDelegate.authManager = authManager
                    appDelegate.membershipManager = membershipManager
                    membershipManager.setup(authManager: authManager)
                    services.dashboardViewModel.membershipManager = membershipManager
                    authManager.checkOnLaunch()
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Main Content View Router

struct MainContentView: View {
    @ObservedObject var services: AppServices
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif

    @State private var viewMode: ViewMode = .checking
    @State private var startupRouteToken = 0

    enum ViewMode {
        case checking
        case initial
        case installation
        case dashboard
    }

    private var isStartupRouteAllowed: Bool {
        #if REQUIRE_LOGIN
        authManager.isLoggedIn
        #else
        true
        #endif
    }

    var body: some View {
        Group {
            #if REQUIRE_LOGIN
            if authManager.isLoggedIn {
                routedContent
            } else {
                AuthGateView(
                    state: authManager.state,
                    onLogin: {
                        authManager.login()
                    },
                    onRetry: {
                        authManager.retry()
                    },
                    onReopenLogin: {
                        authManager.login()
                    }
                )
            }
            #else
            routedContent
            #endif
        }
        .task(id: startupRouteToken) {
            await determineInitialView()
        }
        #if REQUIRE_LOGIN
        .onChange(of: authManager.isLoggedIn) { loggedIn in
            viewMode = .checking
            if loggedIn {
                startupRouteToken += 1
            }
        }
        #endif
    }

    @ViewBuilder
    private var routedContent: some View {
        switch viewMode {
        case .checking:
            StartupCheckingView()

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

    private func determineInitialView() async {
        guard isStartupRouteAllowed else { return }
        #if REQUIRE_LOGIN
        guard authManager.isLoggedIn else { return }
        #endif
        await services.systemEnvironment.performFullCheck()
        if services.systemEnvironment.openclawInfo != nil {
            await services.ensureOpenClawCoreIsCurrent()
            await services.systemEnvironment.detectOpenClaw()
            viewMode = .dashboard
        } else {
            viewMode = .initial
        }
    }
}

#if REQUIRE_LOGIN
private struct AuthGateView: View {
    let state: AuthState
    let onLogin: () -> Void
    let onRetry: () -> Void
    let onReopenLogin: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                Image("Logo1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)

                Text("GetClawHub")
                    .font(.system(size: 26, weight: .semibold))

                statusContent
            }
            .frame(width: 380)
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
            Text(I18n.t("login.status.checking"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

        case .notLoggedIn:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(I18n.t("login.status.signIn"))
                .font(.system(size: 15, weight: .semibold))
            Button(I18n.t("login.action.logIn"), action: onLogin)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .polling:
            ProgressView()
                .controlSize(.small)
            Text(I18n.t("login.status.waitingBrowser"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button(I18n.t("login.action.reopen"), action: onReopenLogin)
                .buttonStyle(.bordered)

        case .timeout:
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.orange)
            Text(I18n.t("login.status.timeout"))
                .font(.system(size: 15, weight: .semibold))
            Button(I18n.t("common.action.retry"), action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(I18n.t("common.action.retry"), action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .loggedIn:
            ProgressView()
                .controlSize(.small)
            Text(I18n.t("login.status.preparingWorkspace"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
#endif

private struct StartupCheckingView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("Logo1")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)

            BrandTextView()

            ProgressView()
                .scaleEffect(1.1)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Initial View (Landing Page)

struct InitialView: View {
    @ObservedObject var systemEnvironment: SystemEnvironment

    let onStartInstallation: () -> Void
    let onOpenDashboard: () -> Void

    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false
    @State private var uninstallComplete = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image("Logo1")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            BrandTextView()

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isUninstalling {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(I18n.t("install.status.uninstalling"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else if uninstallComplete {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text(I18n.t("install.status.uninstallComplete"))
                        .font(.title3)
                        .foregroundColor(.green)
                    Text(I18n.t("install.status.dataPreserved"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: onStartInstallation) {
                        HStack {
                            Text(I18n.t("install.action.start"))
                            Image(systemName: "arrow.right")
                        }
                        .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if systemEnvironment.isChecking {
                ProgressView()
                    .scaleEffect(1.2)
            } else if systemEnvironment.openclawInfo != nil {
                VStack(spacing: 16) {
                    Text(I18n.t("install.status.openclawInstalled"))
                        .font(.title3)
                        .foregroundColor(.green)

                    HStack(spacing: 40) {
                        Button(action: onOpenDashboard) {
                            HStack {
                                Text(I18n.t("install.action.openDashboard"))
                                Image(systemName: "arrow.right")
                            }
                            .frame(width: 180)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { showUninstallConfirm = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text(I18n.t("install.action.uninstall"))
                            }
                            .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Text(I18n.t("install.status.readyToInstall"))
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Button(action: onStartInstallation) {
                        HStack {
                            Text(I18n.t("install.action.start"))
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
        .alert(I18n.t("install.alert.uninstallTitle"), isPresented: $showUninstallConfirm) {
            Button(I18n.t("common.action.cancel"), role: .cancel) {}
            Button(I18n.t("install.action.uninstall"), role: .destructive) {
                performUninstall()
            }
        } message: {
            Text(I18n.t("install.alert.uninstallMessage"))
        }
    }

    private func performUninstall() {
        isUninstalling = true
        Task {
            await UninstallManager.uninstall()
            await systemEnvironment.performFullCheck()
            isUninstalling = false
            uninstallComplete = true
        }
    }
}
