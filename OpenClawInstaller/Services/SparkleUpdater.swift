import Foundation
import Combine
import Sparkle

@MainActor
final class SparkleUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var isCheckingVersion = false
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var checkSucceeded = false

    private let appcastURL = "https://firewolf189.github.io/GetClowhub/appcast.xml"

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        print("[SparkleUpdater] checkForUpdates called, canCheck=\(updaterController.updater.canCheckForUpdates)")
        print("[SparkleUpdater] feedURL=\(updaterController.updater.feedURL?.absoluteString ?? "nil")")
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Fetch appcast.xml and compare versions.
    func checkLatestVersion() async {
        guard !isCheckingVersion else { return }
        isCheckingVersion = true
        updateAvailable = false
        checkSucceeded = false

        defer { isCheckingVersion = false }

        guard let url = URL(string: appcastURL) else { return }

        do {
            // Use a no-cache request to avoid stale responses
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let parser = AppcastParser()
            if let remoteVersion = parser.parseVersion(from: data) {
                latestVersion = remoteVersion
                if compareVersions(remoteVersion, isNewerThan: currentVersion) {
                    updateAvailable = true
                } else {
                    checkSucceeded = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        checkSucceeded = false
                    }
                }
            }
        } catch {
            print("[SparkleUpdater] checkLatestVersion error: \(error)")
        }
    }

    /// Simple version comparison: "1.2.0" > "1.1.0"
    private func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}

// MARK: - Appcast XML Parser

/// Minimal parser that extracts sparkle:shortVersionString from appcast.xml.
private class AppcastParser: NSObject, XMLParserDelegate {
    private var foundVersion: String?
    private var isReadingVersion = false
    private var versionBuffer = ""

    func parseVersion(from data: Data) -> String? {
        let parser = XMLParser(data: data)
        // Disable namespace processing so "sparkle:shortVersionString"
        // appears as the raw element name rather than being split.
        parser.shouldProcessNamespaces = false
        parser.delegate = self
        parser.parse()
        return foundVersion
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "sparkle:shortVersionString" && foundVersion == nil {
            isReadingVersion = true
            versionBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingVersion {
            versionBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "sparkle:shortVersionString" && isReadingVersion {
            isReadingVersion = false
            let version = versionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty {
                foundVersion = version
            }
        }
    }
}
