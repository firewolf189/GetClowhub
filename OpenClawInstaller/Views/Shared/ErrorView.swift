import SwiftUI

struct ErrorView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Error Icon
            Image(systemName: error.icon)
                .font(.system(size: 64))
                .foregroundColor(iconColor)

            // Error Title
            Text(error.title)
                .font(.title2)
                .fontWeight(.bold)

            // Error Message
            VStack(spacing: 12) {
                Text(error.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Recovery Suggestion
                if let suggestion = error.recoverySuggestion {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.blue)

                        Text(suggestion)
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)

            // Action Buttons
            HStack(spacing: 12) {
                // Retry button (if retryable)
                if error.isRetryable, let onRetry = onRetry {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .frame(width: 120)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }

                // Dismiss button
                if error.isRetryable {
                    Button(action: onDismiss) {
                        Text("Cancel")
                            .frame(width: 120)
                    }
                    .buttonStyle(BorderedButtonStyle())
                } else {
                    Button(action: onDismiss) {
                        Text("OK")
                            .frame(width: 120)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
            }

            // Report button (if reportable)
            if error.isReportable {
                Button(action: reportError) {
                    HStack {
                        Image(systemName: "exclamationmark.bubble")
                        Text("Report Issue")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(32)
        .frame(width: 450)
    }

    private var iconColor: Color {
        switch error.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .red
        }
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func reportError() {
        // Copy error details to clipboard
        let errorReport = """
        Error Report
        ============
        Title: \(error.title)
        Message: \(error.message)

        System Info:
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(getArchitecture())

        Please report this issue to the developers.
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(errorReport, forType: .string)

        // Show feedback
        let alert = NSAlert()
        alert.messageText = "Error Report Copied"
        alert.informativeText = "Error details have been copied to your clipboard. Please paste them when reporting the issue."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    let onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { error.map { ErrorWrapper(error: $0) } },
                set: { error = $0?.error }
            )) { wrapper in
                ErrorView(
                    error: wrapper.error,
                    onRetry: onRetry,
                    onDismiss: {
                        error = nil
                    }
                )
            }
    }
}

struct ErrorWrapper: Identifiable {
    let id = UUID()
    let error: AppError
}

extension View {
    func errorAlert(_ error: Binding<AppError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(error: error, onRetry: onRetry))
    }
}

// MARK: - Inline Error View

struct InlineErrorView: View {
    let error: AppError
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.icon)
                .foregroundColor(iconColor)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(8)
    }

    private var iconColor: Color {
        switch error.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .red
        }
    }

    private var backgroundColor: Color {
        switch error.color {
        case "red": return Color.red.opacity(0.1)
        case "orange": return Color.orange.opacity(0.1)
        case "yellow": return Color.yellow.opacity(0.1)
        default: return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: error.icon)
                    .foregroundColor(.white)

                Text(error.title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            Text(error.message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))

            if error.isRetryable, let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(16)
        .background(bannerColor)
        .cornerRadius(12)
        .shadow(radius: 4)
    }

    private var bannerColor: Color {
        switch error.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview("Error View") {
    ErrorView(
        error: .nodeInstallationFailed(reason: "Network timeout"),
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Inline Error") {
    InlineErrorView(
        error: .serviceNotResponding,
        onDismiss: {}
    )
    .padding()
}

#Preview("Error Banner") {
    ErrorBannerView(
        error: .networkError(reason: "Connection timed out"),
        onRetry: {},
        onDismiss: {}
    )
    .padding()
}
