import SwiftUI
import AppKit

// MARK: - Collab Panel View

struct CollabWindowView: View {
    @ObservedObject var viewModel: CollabViewModel
    var onCollapse: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    @State private var showConfigPopover = false
    @State private var customTimeoutHours = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Task cards
            if let session = viewModel.session {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // Clarify history (persists across phases)
                        if !viewModel.clarifyHistory.isEmpty {
                            clarifyingView
                        }

                        // Research progress checklist
                        if !viewModel.researchStages.isEmpty {
                            researchingView
                        }

                        // Decompose progress checklist
                        if !viewModel.decomposeStages.isEmpty {
                            decomposingView
                        }

                        // Awaiting approval — show plan cards with confirm button
                        if viewModel.phase == .awaitingApproval {
                            awaitingApprovalView
                        }

                        // Recruitment progress
                        if !viewModel.recruitEntries.isEmpty {
                            recruitProgressView
                        }

                        ForEach(session.subtasks) { task in
                            CollabTaskCard(task: task, viewModel: viewModel)
                        }

                        // Final result
                        if let finalResult = session.finalResult {
                            finalResultView(finalResult)
                        }
                    }
                    .padding(12)
                }
            } else if !viewModel.sessionHistory.isEmpty {
                // No active session but has history — show history list
                sessionHistoryList
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "No collaboration tasks", bundle: LanguageManager.shared.localizedBundle))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(String(localized: "Type /collab in chat or select Commander to send a task", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            }

            Divider()

            // Bottom bar
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                Text("Collab Tasks")
                    .font(.headline)

                // History picker — prominent button
                if !viewModel.sessionHistory.isEmpty {
                    Menu {
                        if let current = viewModel.session {
                            Button(action: {}) {
                                Label(Self.sessionMenuLabel(current, isCurrent: true), systemImage: "circle.fill")
                            }
                            .disabled(true)
                            Divider()
                        }
                        ForEach(viewModel.sessionHistory) { hist in
                            Button(action: { viewModel.switchToSession(hist) }) {
                                Label(Self.sessionMenuLabel(hist, isCurrent: false), systemImage: "clock")
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                            Text("\(viewModel.sessionHistory.count)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(String(localized: "Collaboration history (\(viewModel.sessionHistory.count))", bundle: LanguageManager.shared.localizedBundle))
                }

                Spacer()
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(phaseStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                // Config gear button
                Button(action: { showConfigPopover.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Commander Settings", bundle: LanguageManager.shared.localizedBundle))
                .popover(isPresented: $showConfigPopover, arrowEdge: .bottom) {
                    commanderConfigPopover
                }

                if onCollapse != nil {
                    Button(action: { onCollapse?() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse panel")
                }
                if onClose != nil {
                    Button(action: { onClose?() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close panel")
                }
            }

            if let session = viewModel.session {
                Text(session.taskDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if viewModel.phase == .executing || viewModel.phase == .completed || viewModel.phase == .summarizing || viewModel.phase == .verifying {
                        Text("Progress: \(viewModel.progressText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(session.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    private var phaseStatusText: String {
        switch viewModel.phase {
        case .clarifying: return "Understanding..."
        case .researching: return "Researching..."
        case .decomposing: return "Decomposing..."
        case .awaitingApproval: return "Awaiting approval"
        case .executing: return "Running..."
        case .verifying: return "Verifying..."
        case .summarizing: return "Summarizing..."
        case .completed: return "Done"
        }
    }

    // MARK: - Clarifying View

    private var clarifyingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if viewModel.phase == .clarifying && viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: viewModel.phase == .clarifying ? "questionmark.circle" : "checkmark.circle.fill")
                    .foregroundColor(viewModel.phase == .clarifying ? .purple : .green)
                    .font(.system(size: 14))
                Text(String(localized: "Requirements Gathering", bundle: LanguageManager.shared.localizedBundle))
                    .font(.subheadline.bold())
                    .foregroundColor(viewModel.phase == .clarifying ? .purple : .secondary)
            }

            ForEach(viewModel.clarifyHistory) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.role == "commander" ? "🎯" : "👤")
                        .font(.caption)
                    Text(entry.content)
                        .font(.caption)
                        .foregroundColor(entry.role == "commander" ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Show taskContext summary when clarify phase is done
            if viewModel.phase != .clarifying,
               let session = viewModel.session,
               !session.taskContext.isEmpty {
                Divider()
                Text(String(localized: "Requirements Summary", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                let limit = viewModel.config.taskContextDisplayLimit
                Text(session.taskContext.prefix(limit) + (session.taskContext.count > limit ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.phase == .clarifying && !viewModel.isRunning {
                Text(String(localized: "Please answer Commander's questions in the chat window", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Awaiting Approval View

    private var awaitingApprovalView: some View {
        let recruitCount = viewModel.session?.subtasks.filter { $0.needsRecruit }.count ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.orange)
                Text(String(localized: "Plan Awaiting Approval", bundle: LanguageManager.shared.localizedBundle))
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
            }

            if recruitCount > 0 {
                Text(String(localized: "After confirmation, \(recruitCount) expert agents will be recruited, then tasks will execute.", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text(String(localized: "Type 'ok' or 'go' in chat to start, or continue discussing to adjust.", bundle: LanguageManager.shared.localizedBundle))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button(action: {
                    Task { await viewModel.confirmAndExecute() }
                }) {
                    Label(String(localized: "Confirm & Execute", bundle: LanguageManager.shared.localizedBundle), systemImage: "play.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: {
                    // Switch back to clarifying so user can discuss more
                    viewModel.phase = .clarifying
                }) {
                    Label(String(localized: "Continue Discussion", bundle: LanguageManager.shared.localizedBundle), systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Decomposing View

    // MARK: - Research Progress View

    private var researchingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if viewModel.isResearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: viewModel.isResearching ? "magnifyingglass" : "checkmark.circle.fill")
                    .foregroundColor(viewModel.isResearching ? .purple : .green)
                    .font(.system(size: 14))
                Text(String(localized: "Project Research", bundle: LanguageManager.shared.localizedBundle))
                    .font(.subheadline.bold())
                    .foregroundColor(viewModel.isResearching ? .purple : .secondary)
            }

            ForEach(viewModel.researchStages) { stage in
                HStack(spacing: 6) {
                    switch stage.status {
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    case .inProgress:
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 11, height: 11)
                    case .pending:
                        Image(systemName: "circle")
                            .font(.system(size: 11))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    Text(stage.text)
                        .font(.caption)
                        .foregroundColor(stage.status == .pending ? .secondary.opacity(0.5) : .primary)
                }
            }

            // Real-time output preview
            if viewModel.isResearching, !viewModel.researchOutput.isEmpty {
                let previewText = researchOutputPreview(viewModel.researchOutput)
                Text(previewText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    /// Extract the last ~500 chars of research output for preview
    private func researchOutputPreview(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 500 {
            return trimmed
        }
        return "..." + String(trimmed.suffix(500))
    }

    private var decomposingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if viewModel.isDecomposing {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: viewModel.isDecomposing ? "gearshape.2" : "checkmark.circle.fill")
                    .foregroundColor(viewModel.isDecomposing ? .accentColor : .green)
                    .font(.system(size: 14))
                Text(String(localized: "Task Decomposition", bundle: LanguageManager.shared.localizedBundle))
                    .font(.subheadline.bold())
                    .foregroundColor(viewModel.isDecomposing ? .accentColor : .secondary)
            }

            ForEach(viewModel.decomposeStages) { stage in
                HStack(spacing: 6) {
                    switch stage.status {
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    case .inProgress:
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 11, height: 11)
                    case .pending:
                        Image(systemName: "circle")
                            .font(.system(size: 11))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    Text(stage.text)
                        .font(.caption)
                        .foregroundColor(stage.status == .pending ? .secondary.opacity(0.5) : .primary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Recruit Progress View

    private var recruitProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                let allDone = viewModel.recruitEntries.allSatisfy { $0.status == .recruited || $0.status == .failed || $0.status == .ready }
                if !allDone {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: "person.3.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text(String(localized: "Team Members", bundle: LanguageManager.shared.localizedBundle))
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
            }

            ForEach(viewModel.recruitEntries) { entry in
                HStack(spacing: 6) {
                    switch entry.status {
                    case .ready:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    case .recruited:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    case .recruiting:
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 11, height: 11)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    case .pending:
                        Image(systemName: "circle")
                            .font(.system(size: 11))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    Text(entry.id)
                        .font(.caption)
                        .foregroundColor(entry.status == .pending ? .secondary.opacity(0.5) : .primary)
                    if entry.status == .ready {
                        Text(String(localized: "(Ready)", bundle: LanguageManager.shared.localizedBundle))
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                    } else if entry.status == .recruited {
                        Text(String(localized: "(Recruited)", bundle: LanguageManager.shared.localizedBundle))
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    } else if entry.status == .failed {
                        Text(String(localized: "(Downgraded)", bundle: LanguageManager.shared.localizedBundle))
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Final Result

    private func finalResultView(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.green)
                Text("Final Summary")
                    .font(.subheadline.bold())
            }

            Text(result)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Commander Config Popover

    private var commanderConfigPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Commander Settings", bundle: LanguageManager.shared.localizedBundle))
                .font(.headline)

            Divider()

            // Agent timeout
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Agent Timeout", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption.bold())
                // Preset minute-level quick picks
                Picker("", selection: Binding<Int>(
                    get: {
                        let presets = [600, 1200, 1800, 2700, 3600]
                        return presets.contains(viewModel.config.agentTimeout) ? viewModel.config.agentTimeout : -1
                    },
                    set: { newValue in
                        if newValue != -1 {
                            viewModel.config.agentTimeout = newValue
                            customTimeoutHours = ""
                        }
                    }
                )) {
                    Text("10m").tag(600)
                    Text("20m").tag(1200)
                    Text("30m").tag(1800)
                    Text("45m").tag(2700)
                    Text("60m").tag(3600)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Custom hour-level input
                HStack(spacing: 6) {
                    Text(String(localized: "Custom", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextField("", text: $customTimeoutHours)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .font(.caption)
                        .onSubmit {
                            applyCustomTimeout()
                        }
                    Text(String(localized: "hours", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !customTimeoutHours.isEmpty, let h = Double(customTimeoutHours), h >= 0.5 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                Text(String(localized: "Max execution time per subtask (current: \(viewModel.config.timeoutDisplay))", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Max concurrency
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Max Concurrency", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption.bold())
                Picker("", selection: $viewModel.config.maxConcurrency) {
                    Text(String(localized: "Unlimited", bundle: LanguageManager.shared.localizedBundle)).tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(String(localized: "Max concurrent subtasks (0 = unlimited)", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Progress history limit
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Retry Context Length", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption.bold())
                HStack(spacing: 4) {
                    Picker("", selection: $viewModel.config.progressHistoryLimit) {
                        Text("1k").tag(1000)
                        Text("2k").tag(2000)
                        Text("3k").tag(3000)
                        Text("5k").tag(5000)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(String(localized: "chars", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(String(localized: "History length passed to agent on retry", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button(String(localized: "Reset Defaults", bundle: LanguageManager.shared.localizedBundle)) {
                    viewModel.config = CommanderConfig()
                    viewModel.config.save()
                    customTimeoutHours = ""
                }
                .font(.caption)

                Spacer()

                Button(String(localized: "Save", bundle: LanguageManager.shared.localizedBundle)) {
                    applyCustomTimeout()
                    viewModel.config.save()
                    showConfigPopover = false
                }
                .font(.caption)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            // Sync custom input if current timeout is not a preset
            let presets = [600, 1200, 1800, 2700, 3600]
            if !presets.contains(viewModel.config.agentTimeout) {
                let hours = Double(viewModel.config.agentTimeout) / 3600.0
                if hours == hours.rounded() {
                    customTimeoutHours = String(Int(hours))
                } else {
                    customTimeoutHours = String(format: "%.1f", hours)
                }
            }
        }
        .onChange(of: viewModel.config) { newConfig in
            newConfig.save()
        }
    }

    private func applyCustomTimeout() {
        guard !customTimeoutHours.isEmpty,
              let hours = Double(customTimeoutHours),
              hours >= 0.5 else { return }
        viewModel.config.agentTimeout = Int(hours * 3600)
    }

    // MARK: - Session Menu Label

    static func sessionMenuLabel(_ session: CollabSession, isCurrent: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd HH:mm"
        let dateStr = dateFormatter.string(from: session.createdAt)

        let desc = session.taskDescription.prefix(20)
        let suffix = session.taskDescription.count > 20 ? "..." : ""

        let status: String
        switch session.phase {
        case .completed: status = "[done]"
        case .executing: status = "[running]"
        case .clarifying, .researching, .decomposing, .awaitingApproval: status = "[prep]"
        case .verifying: status = "[verify]"
        case .summarizing: status = "[summary]"
        }

        let prefix = isCurrent ? "[current] " : ""
        return "\(prefix)\(dateStr) \(desc)\(suffix) \(status)"
    }

    // MARK: - Session History List

    private var sessionHistoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(String(localized: "History", bundle: LanguageManager.shared.localizedBundle))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(localized: "\(viewModel.sessionHistory.count) records", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.bottom, 4)

                ForEach(viewModel.sessionHistory) { hist in
                    Button(action: { viewModel.switchToSession(hist) }) {
                        sessionHistoryRow(hist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func sessionHistoryRow(_ session: CollabSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.taskDescription)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
                sessionStatusBadge(session.phase)
            }
            HStack(spacing: 8) {
                let dateFormatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateFormat = "MM/dd HH:mm"
                    return f
                }()
                Text(dateFormatter.string(from: session.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)

                let completedCount = session.subtasks.filter { $0.status == .completed }.count
                let totalCount = session.subtasks.count
                if totalCount > 0 {
                    Text(String(localized: "\(completedCount)/\(totalCount) subtasks", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func sessionStatusBadge(_ phase: CollabPhase) -> some View {
        let (text, color): (String, Color) = {
            switch phase {
            case .completed: return (String(localized: "Done", bundle: LanguageManager.shared.localizedBundle), .green)
            case .executing: return (String(localized: "Running", bundle: LanguageManager.shared.localizedBundle), .blue)
            case .verifying: return (String(localized: "Verifying", bundle: LanguageManager.shared.localizedBundle), .orange)
            case .summarizing: return (String(localized: "Summarizing", bundle: LanguageManager.shared.localizedBundle), .purple)
            case .clarifying, .researching, .decomposing, .awaitingApproval: return (String(localized: "Preparing", bundle: LanguageManager.shared.localizedBundle), .gray)
            }
        }()

        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if viewModel.isRunning {
                Button(action: { viewModel.cancelAll() }) {
                    Label("Cancel All", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Task Card

struct CollabTaskCard: View {
    let task: CollabSubTask
    @ObservedObject var viewModel: CollabViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(task.id) \(task.title)")
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        agentLabel
                        if let elapsed = task.elapsedTime {
                            Text(String(format: "%.1fs", elapsed))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Retry button for failed tasks
                if case .failed = task.status {
                    Button(action: {
                        Task { await viewModel.retryTask(task.id) }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Retry this task")

                    // Force complete button — mark failed task as completed to unblock downstream
                    Button(action: {
                        Task { await viewModel.forceCompleteTask(task.id) }
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Mark as completed (unblock downstream tasks)")
                }

                // Skip button for pending tasks
                if task.status == .pending {
                    Button(action: { Task { await viewModel.skipTask(task.id) } }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Skip this task")
                }

                // Expand/collapse toggle
                if task.result != nil || (task.status != .pending && task.status != .skipped) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            // Real-time progress for in-progress tasks
            if task.status == .inProgress {
                let progressInfo = viewModel.taskProgress[task.id]
                let displayText = progressInfo?.displayText

                if let displayText = displayText, !displayText.isEmpty {
                    Divider()
                        .padding(.horizontal, 10)

                    VStack(alignment: .leading, spacing: 3) {
                        // System-level stats bar (always show when we have data)
                        if let info = progressInfo {
                            HStack(spacing: 8) {
                                // Process alive indicator
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(info.isProcessAlive ? Color.green : Color.gray)
                                        .frame(width: 6, height: 6)
                                    Text(info.isProcessAlive ? String(localized: "Process running", bundle: LanguageManager.shared.localizedBundle) : String(localized: "Process ended", bundle: LanguageManager.shared.localizedBundle))
                                        .font(.system(size: 9))
                                        .foregroundColor(info.isProcessAlive ? .green : .secondary)
                                }
                                if info.outputLineCount > 0 {
                                    Label(String(localized: "\(info.outputLineCount) lines", bundle: LanguageManager.shared.localizedBundle), systemImage: "text.alignleft")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                if !info.discoveredFiles.isEmpty {
                                    Label(String(localized: "\(info.discoveredFiles.count) files", bundle: LanguageManager.shared.localizedBundle), systemImage: "doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                }
                                Label(String(format: "%.0fs", info.elapsed), systemImage: "clock")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                if info.isStale {
                                    Label(String(localized: "Long running", bundle: LanguageManager.shared.localizedBundle), systemImage: "hourglass")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                            }
                            .padding(.bottom, 2)
                        }

                        // Agent-authored progress or fallback text
                        if let agentProgress = progressInfo?.agentProgress {
                            let lines = agentProgress.components(separatedBy: "\n").suffix(6)
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        // Show discovered files in real-time
                        if let files = progressInfo?.discoveredFiles, !files.isEmpty {
                            Divider().padding(.vertical, 2)
                            HStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                Text(String(localized: "Output files:", bundle: LanguageManager.shared.localizedBundle))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            ForEach(files, id: \.self) { file in
                                Text("  \(file)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        } else if progressInfo?.agentProgress == nil,
                                  progressInfo?.isProcessAlive == true,
                                  (progressInfo?.discoveredFiles ?? []).isEmpty {
                            Text(String(localized: "Agent running...", bundle: LanguageManager.shared.localizedBundle))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 6) {
                    if !task.dependsOn.isEmpty {
                        Text("Depends on: #\(task.dependsOn.map(String.init).joined(separator: ", #"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let result = task.result {
                        Text(result)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if case .failed(let error) = task.status {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.gray)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .skipped:
            Image(systemName: "forward.circle.fill")
                .foregroundColor(.gray)
        }
    }

    // MARK: - Agent Label

    private var agentLabel: some View {
        HStack(spacing: 4) {
            if let agentId = task.agentId {
                Text(agentId)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundColor(.accentColor)

                if task.needsRecruit {
                    Text(String(localized: "Recruit", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundColor(.orange)
                }
            } else if let role = task.role {
                Text("main/\(role)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .foregroundColor(.orange)

                Text(String(localized: "Generic", bundle: LanguageManager.shared.localizedBundle))
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                    .foregroundColor(.secondary)
            } else {
                Text("main")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Card Styling

    private var cardBackground: Color {
        switch task.status {
        case .completed: return Color.green.opacity(0.04)
        case .failed: return Color.red.opacity(0.04)
        case .inProgress: return Color.blue.opacity(0.04)
        default: return Color(NSColor.controlBackgroundColor)
        }
    }

    private var cardBorder: Color {
        switch task.status {
        case .completed: return Color.green.opacity(0.2)
        case .failed: return Color.red.opacity(0.2)
        case .inProgress: return Color.blue.opacity(0.2)
        default: return Color.gray.opacity(0.15)
        }
    }
}
