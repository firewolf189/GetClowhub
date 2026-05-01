import SwiftUI
import MarkdownUI

struct MarketplaceDetailView: View {
    let agent: MarketplaceAgent
    let openclawService: OpenClawService
    let onInstalled: (String) -> Void  // callback with agentId
    var onBack: (() -> Void)? = nil    // callback to return to marketplace

    @EnvironmentObject var languageManager: LanguageManager
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var showContent = true
    @State private var installError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Back to marketplace
                if let onBack = onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Marketplace")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Header
                headerSection

                Divider()

                // Description
                descriptionSection

                // Vibe
                if !agent.vibe.isEmpty {
                    vibeSection
                }

                Divider()

                // Persona content preview
                contentSection

                Spacer(minLength: 40)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkInstalled()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            Text(agent.emoji)
                .font(.system(size: 56))

            VStack(alignment: .leading, spacing: 6) {
                Text(agent.name)
                    .font(.title)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text(agent.division)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)

                    if !agent.color.isEmpty {
                        Circle()
                            .fill(Color(hex: agent.color))
                            .frame(width: 10, height: 10)
                    }
                }
            }

            Spacer()

            installButton
        }
    }

    // MARK: - Install Button

    private var installButton: some View {
        Button {
            installAgent()
        } label: {
            if isInstalling {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 100)
            } else if isInstalled {
                Label(String(localized: "Recruited", bundle: languageManager.localizedBundle), systemImage: "checkmark.circle.fill")
                    .frame(width: 100)
            } else {
                Label(String(localized: "Recruit", bundle: languageManager.localizedBundle), systemImage: "arrow.down.circle")
                    .frame(width: 100)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(isInstalled ? .green : .accentColor)
        .disabled(isInstalling || isInstalled)
        .alert(String(localized: "Recruit Failed", bundle: languageManager.localizedBundle), isPresented: Binding<Bool>(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Description", bundle: languageManager.localizedBundle))
                .font(.headline)
            Text(agent.description)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Vibe

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Vibe", bundle: languageManager.localizedBundle))
                .font(.headline)
            Text(agent.vibe)
                .italic()
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Content Preview

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showContent.toggle()
                }
            } label: {
                HStack {
                    Text(String(localized: "Persona Content", bundle: languageManager.localizedBundle))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: showContent ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showContent {
                Markdown(agent.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Install Logic

    private func checkInstalled() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let agentDir = "\(homeDir)/.openclaw/agents/\(sanitizedAgentId)/agent"
        isInstalled = FileManager.default.fileExists(atPath: agentDir)
    }

    private var sanitizedAgentId: String {
        // Convert agent id to a valid openclaw agent id (lowercase, alphanumeric + hyphens)
        agent.id
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func installAgent() {
        isInstalling = true
        let agentId = sanitizedAgentId
        let displayName = agent.name

        Task {
            // Step 0: Load available models to auto-pick the best one
            let modelsOutput = await openclawService.runCommand(
                "openclaw models list --json 2>&1",
                timeout: 30
            )
            let availableModels = SubAgentsViewModel.parseModelList(output: modelsOutput)
            let bestModel = availableModels.first(where: { $0.tags.contains("default") })
                ?? availableModels.first

            // Step 1: Create agent via CLI
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            var cmd = "openclaw agents add '\(agentId)'"
            cmd += " --workspace '\(homeDir)/.openclaw/workspace-\(agentId)/'"
            cmd += " --agent-dir '\(homeDir)/.openclaw/agents/\(agentId)/agent/'"
            if let model = bestModel {
                cmd += " --model '\(model.id)'"
            }
            cmd += " --non-interactive --json 2>&1"

            NSLog("[Marketplace] Installing agent: %@, model: %@, cmd: %@",
                  agentId, bestModel?.id ?? "(default)", cmd)
            let _ = await openclawService.runCommand(cmd, timeout: 30)

            // Step 2: Patch agent identity in openclaw.json
            let configPath = "\(homeDir)/.openclaw/openclaw.json"
            SubAgentsViewModel.patchAgentIdentity(
                configPath: configPath,
                agentId: agentId,
                name: displayName,
                emoji: agent.emoji
            )

            // Step 3: Patch agent model in openclaw.json
            if let model = bestModel {
                SubAgentsViewModel.patchAgentModel(
                    configPath: configPath,
                    agentId: agentId,
                    model: model.id
                )
                NSLog("[Marketplace] Agent %@ model set to %@", agentId, model.id)
            }

            // Step 4: Write marketplace-converted persona files
            let workspace = "\(homeDir)/.openclaw/workspace-\(agentId)"
            let fm = FileManager.default
            try? fm.createDirectory(atPath: workspace, withIntermediateDirectories: true)

            let identityContent = MarketplaceContentConverter.identityMarkdown(for: agent)
            let soulContent = MarketplaceContentConverter.soulMarkdown(for: agent)
            let agentsContent = MarketplaceContentConverter.agentsMarkdown(for: agent)
            let memoryContent = MarketplaceContentConverter.memoryMarkdown()

            try? identityContent.write(toFile: (workspace as NSString).appendingPathComponent("IDENTITY.md"),
                                        atomically: true, encoding: .utf8)
            try? soulContent.write(toFile: (workspace as NSString).appendingPathComponent("SOUL.md"),
                                    atomically: true, encoding: .utf8)
            try? agentsContent.write(toFile: (workspace as NSString).appendingPathComponent("AGENTS.md"),
                                      atomically: true, encoding: .utf8)
            try? memoryContent.write(toFile: (workspace as NSString).appendingPathComponent("MEMORY.md"),
                                      atomically: true, encoding: .utf8)

            // Step 5: For awesome-design-system agent, copy DesignSystems folder
            if agentId == "awesome-design-system" {
                let designSystemsDestPath = (workspace as NSString).appendingPathComponent("DesignSystems")
                var designSystemsSourcePath = ""

                // Strategy 1: Try Bundle.main.resourcePath (standard path)
                if let resourcePath = Bundle.main.resourcePath {
                    let bundleDesignPath = (resourcePath as NSString).appendingPathComponent("DesignSystems")
                    NSLog("[Marketplace] Checking Bundle resource path: %@", bundleDesignPath)
                    if fm.fileExists(atPath: bundleDesignPath) {
                        designSystemsSourcePath = bundleDesignPath
                        NSLog("[Marketplace] Found DesignSystems in Bundle resource path")
                    }
                }

                // Strategy 2: Try app bundle Contents/Resources (macOS app structure)
                if designSystemsSourcePath.isEmpty {
                    let bundlePath = Bundle.main.bundlePath
                    let contentsResourcesPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources/DesignSystems")
                    NSLog("[Marketplace] Checking Bundle Contents/Resources path: %@", contentsResourcesPath)
                    if fm.fileExists(atPath: contentsResourcesPath) {
                        designSystemsSourcePath = contentsResourcesPath
                        NSLog("[Marketplace] Found DesignSystems in Bundle Contents/Resources path")
                    }
                }

                // Strategy 3: Try direct path from bundle executable directory
                if designSystemsSourcePath.isEmpty {
                    if let exePath = Bundle.main.executablePath {
                        let execDir = (exePath as NSString).deletingLastPathComponent
                        let resourcesDir = (execDir as NSString).appendingPathComponent("Resources")
                        let designPath = (resourcesDir as NSString).appendingPathComponent("DesignSystems")
                        NSLog("[Marketplace] Checking executable directory path: %@", designPath)
                        if fm.fileExists(atPath: designPath) {
                            designSystemsSourcePath = designPath
                            NSLog("[Marketplace] Found DesignSystems in executable directory path")
                        }
                    }
                }

                // Perform copy if source found
                if !designSystemsSourcePath.isEmpty {
                    do {
                        try? fm.removeItem(atPath: designSystemsDestPath)  // Remove if exists
                        try fm.copyItem(atPath: designSystemsSourcePath, toPath: designSystemsDestPath)
                        NSLog("[Marketplace] Successfully copied DesignSystems to workspace for awesome-design-system agent")
                    } catch {
                        NSLog("[Marketplace] Error: Failed to copy DesignSystems from %@ to %@: %@",
                              designSystemsSourcePath, designSystemsDestPath, error.localizedDescription)
                    }
                } else {
                    NSLog("[Marketplace] Error: DesignSystems folder not found in any expected Bundle resource paths")
                }
            }

            NSLog("[Marketplace] Agent %@ installed successfully", agentId)

            await MainActor.run {
                isInstalling = false
                isInstalled = true
                onInstalled(agentId)
            }
        }
    }
}

// MARK: - Color hex extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            // Try to match named colors
            switch hex.lowercased() {
            case "blue": r = 0.2; g = 0.4; b = 0.9
            case "red": r = 0.9; g = 0.2; b = 0.2
            case "green": r = 0.2; g = 0.8; b = 0.4
            case "purple": r = 0.6; g = 0.3; b = 0.8
            case "orange": r = 0.9; g = 0.5; b = 0.1
            case "yellow": r = 0.9; g = 0.8; b = 0.1
            case "pink": r = 0.9; g = 0.4; b = 0.6
            case "teal": r = 0.2; g = 0.7; b = 0.7
            case "indigo": r = 0.3; g = 0.2; b = 0.8
            case "cyan": r = 0.2; g = 0.8; b = 0.9
            default: r = 0.5; g = 0.5; b = 0.5
            }
        }
        self.init(red: r, green: g, blue: b)
    }
}
