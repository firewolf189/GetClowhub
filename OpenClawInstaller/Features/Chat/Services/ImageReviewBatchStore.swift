import CryptoKit
import Foundation

struct ImageReviewBatchStore {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    struct Configuration {
        var rootDirectory: URL
        var maxImagesPerChunk: Int
        var successfulImageRetentionDays: Int
        var maxCacheBytes: Int64

        init(
            rootDirectory: URL = ImageReviewBatchStore.defaultRootDirectory(),
            maxImagesPerChunk: Int = 8,
            successfulImageRetentionDays: Int = 30,
            maxCacheBytes: Int64 = 10 * 1024 * 1024 * 1024
        ) {
            self.rootDirectory = rootDirectory
            self.maxImagesPerChunk = max(1, maxImagesPerChunk)
            self.successfulImageRetentionDays = max(1, successfulImageRetentionDays)
            self.maxCacheBytes = max(1, maxCacheBytes)
        }
    }

    enum BatchStatus: String, Codable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    struct BatchMetadata: Codable {
        let id: String
        let status: BatchStatus
        let createdAt: Date
        let completedAt: Date?
        let sourcePaths: [String]
        let imageCount: Int
        let chunkCount: Int
        let chunkSize: Int
        let totalBytes: Int64
        let inputDirectory: String
        let manifestPath: String
        let resultsPath: String
        let reviewResultsPath: String
        let reportPath: String
    }

    struct Batch {
        let id: String
        let rootDirectory: URL
        let inputDirectory: URL
        let manifestURL: URL
        let resultsURL: URL
        let reviewResultsURL: URL
        let reportURL: URL
        let batchMetadataURL: URL
        let sourcePaths: [String]
        let imageCount: Int
        let chunkCount: Int
        let chunkSize: Int
        let totalBytes: Int64
    }

    struct ManifestEntry: Codable {
        let batchId: String
        let originalPath: String
        let cachedPath: String
        let relativePath: String
        let fileName: String
        let person: String
        let sha256: String
        let byteSize: Int64
        let chunkIndex: Int
        let status: String
    }

    struct CleanupSummary {
        let removedBatchCount: Int
        let removedBytes: Int64
    }

    private let configuration: Configuration
    private let fileManager: FileManager

    init(configuration: Configuration = .init(), fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    static func defaultRootDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let appName = Bundle.main.bundleIdentifier ?? "GetClowHub"
        return appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("ImageReviewBatches", isDirectory: true)
    }

    static func isImageReviewBatchCandidate(
        urls: [URL],
        messageText: String,
        selectedAgentId: String?
    ) -> Bool {
        let summary = summarize(urls: urls, fileManager: .default)
        guard summary.imageCount > 0 else { return false }
        if summary.imageCount > 8 { return true }
        if containsReviewIntent(messageText) { return true }
        if selectedAgentId?.lowercased().contains("image") == true { return true }
        return summary.hasDirectory && summary.nonImageCount == 0 && summary.imageCount > 1
    }

    func createBatch(from urls: [URL], messageText: String, now: Date = Date()) throws -> Batch? {
        let sources = Self.collectImageSources(from: urls, fileManager: fileManager)
        guard !sources.isEmpty else { return nil }

        try fileManager.createDirectory(at: configuration.rootDirectory, withIntermediateDirectories: true)

        let batchId = Self.makeBatchId(now: now)
        let batchRoot = configuration.rootDirectory.appendingPathComponent(batchId, isDirectory: true)
        let inputDirectory = batchRoot.appendingPathComponent("input", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var entries: [ManifestEntry] = []
        var totalBytes: Int64 = 0
        for (index, source) in sources.enumerated() {
            let data = try Data(contentsOf: source.fileURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let byteSize = Int64(data.count)
            totalBytes += byteSize

            let relativePath = Self.relativePath(for: source.fileURL, under: source.rootURL)
            let sourceFolder = "\(index)-\(Self.sanitizedPathComponent(source.rootURL.lastPathComponent))"
            let cachedURL = inputDirectory
                .appendingPathComponent(sourceFolder, isDirectory: true)
                .appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: cachedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cachedURL, options: .atomic)

            let chunkIndex = index / configuration.maxImagesPerChunk
            entries.append(
                ManifestEntry(
                    batchId: batchId,
                    originalPath: source.fileURL.path,
                    cachedPath: cachedURL.path,
                    relativePath: relativePath,
                    fileName: source.fileURL.lastPathComponent,
                    person: Self.personName(for: source.fileURL, root: source.rootURL),
                    sha256: hash,
                    byteSize: byteSize,
                    chunkIndex: chunkIndex,
                    status: "pending"
                )
            )
        }

        let manifestURL = batchRoot.appendingPathComponent("manifest.jsonl")
        let manifestData = entries
            .map { entry -> String in
                guard let data = try? encoder.encode(entry),
                      let line = String(data: data, encoding: .utf8) else {
                    return "{}"
                }
                return line
            }
            .joined(separator: "\n")
            .appending("\n")
        try Data(manifestData.utf8).write(to: manifestURL, options: .atomic)

        let chunkCount = Int(ceil(Double(entries.count) / Double(configuration.maxImagesPerChunk)))
        let resultsURL = batchRoot.appendingPathComponent("results.jsonl")
        let reviewResultsURL = batchRoot.appendingPathComponent("review_results.json")
        let reportURL = batchRoot.appendingPathComponent("report.md")
        let batchMetadataURL = batchRoot.appendingPathComponent("batch.json")

        let batch = Batch(
            id: batchId,
            rootDirectory: batchRoot,
            inputDirectory: inputDirectory,
            manifestURL: manifestURL,
            resultsURL: resultsURL,
            reviewResultsURL: reviewResultsURL,
            reportURL: reportURL,
            batchMetadataURL: batchMetadataURL,
            sourcePaths: urls.map(\.path),
            imageCount: entries.count,
            chunkCount: chunkCount,
            chunkSize: configuration.maxImagesPerChunk,
            totalBytes: totalBytes
        )
        try writeMetadata(for: batch, status: .pending, completedAt: nil, createdAt: now)
        return batch
    }

    func loadManifest(for batch: Batch) throws -> [ManifestEntry] {
        let text = try String(contentsOf: batch.manifestURL, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                try decoder.decode(ManifestEntry.self, from: Data(line.utf8))
            }
    }

    func markBatch(_ batch: Batch, status: BatchStatus, completedAt: Date? = nil) throws {
        try writeMetadata(for: batch, status: status, completedAt: completedAt)
    }

    func appendChunkResult(batch: Batch, chunkIndex: Int, status: String, responseText: String) throws {
        let payload: [String: Any] = [
            "batchId": batch.id,
            "chunkIndex": chunkIndex,
            "status": status,
            "responseText": responseText,
            "recordedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var line = data
        line.append(0x0A)
        if fileManager.fileExists(atPath: batch.resultsURL.path) {
            let handle = try FileHandle(forWritingTo: batch.resultsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: batch.resultsURL, options: .atomic)
        }
    }

    static func buildReviewPrompt(batch: Batch, userMessage: String) -> String {
        let sessionIds = (0..<batch.chunkCount)
            .map { chunkSessionId(batchId: batch.id, chunkIndex: $0) }
            .joined(separator: "\n")
        return """
        Detected a local image compliance review batch.

        User request:
        \(userMessage)

        Batch ID: \(batch.id)
        Input snapshot: \(batch.inputDirectory.path)
        Manifest: \(batch.manifestURL.path)
        Chunk size: \(batch.chunkSize)
        Total images: \(batch.imageCount)

        Review the images by chunk. Inspect only the image paths listed for the current chunk, write structured per-image results, and do not inline image file contents into the chat message.

        Chunk session ids:
        \(sessionIds)
        """
    }

    static func buildChunkReviewPrompt(
        batch: Batch,
        chunkIndex: Int,
        entries: [ManifestEntry],
        userMessage: String
    ) -> String {
        let imageList = entries
            .map { "- \($0.cachedPath) (person: \($0.person), original: \($0.originalPath))" }
            .joined(separator: "\n")
        return """
        You are reviewing one local image compliance chunk.

        User request:
        \(userMessage)

        Batch ID: \(batch.id)
        Chunk: \(chunkIndex + 1)/\(batch.chunkCount)
        Manifest: \(batch.manifestURL.path)
        Results file to append/update if tools are available: \(batch.resultsURL.path)

        Review only these image files:
        \(imageList)

        Return concise JSON with a top-level "results" array. Each item must include image_path, person, is_pass, summary, and issues.
        """
    }

    static func chunkSessionId(batchId: String, chunkIndex: Int) -> String {
        "image-review-\(batchId)-\(String(format: "%04d", chunkIndex))"
    }

    static func chunkSessionKey(agentId: String, batchId: String, chunkIndex: Int) -> String {
        // Lowercased to match the gateway's canonical session-key form — chat
        // events echo the lowercase key, and the chunk event loop compares keys
        // for equality (see sessionKeyForAgent for the same rule).
        "agent:\(agentId):\(chunkSessionId(batchId: batchId, chunkIndex: chunkIndex))".lowercased()
    }

    func cleanupImageCache(now: Date = Date()) throws -> CleanupSummary {
        guard fileManager.fileExists(atPath: configuration.rootDirectory.path) else {
            return CleanupSummary(removedBatchCount: 0, removedBytes: 0)
        }

        let batchDirectories = try fileManager.contentsOfDirectory(
            at: configuration.rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var removable: [(metadata: BatchMetadata, inputURL: URL, bytes: Int64)] = []
        for directory in batchDirectories {
            let metadataURL = directory.appendingPathComponent("batch.json")
            guard let metadata = try? readMetadata(at: metadataURL),
                  metadata.status == .completed else {
                continue
            }
            let inputURL = URL(fileURLWithPath: metadata.inputDirectory)
            guard fileManager.fileExists(atPath: inputURL.path) else { continue }
            let completedAt = metadata.completedAt ?? metadata.createdAt
            let age = now.timeIntervalSince(completedAt)
            let retention = TimeInterval(configuration.successfulImageRetentionDays * 24 * 60 * 60)
            if age >= retention {
                removable.append((metadata, inputURL, directorySize(inputURL)))
            }
        }

        var removedCount = 0
        var removedBytes: Int64 = 0
        for item in removable.sorted(by: { $0.metadata.createdAt < $1.metadata.createdAt }) {
            try fileManager.removeItem(at: item.inputURL)
            removedCount += 1
            removedBytes += item.bytes
        }

        var currentBytes = directorySize(configuration.rootDirectory)
        if currentBytes > configuration.maxCacheBytes {
            let completedWithInput = batchDirectories.compactMap { directory -> (BatchMetadata, URL, Int64)? in
                let metadataURL = directory.appendingPathComponent("batch.json")
                guard let metadata = try? readMetadata(at: metadataURL),
                      metadata.status == .completed else {
                    return nil
                }
                let inputURL = URL(fileURLWithPath: metadata.inputDirectory)
                guard fileManager.fileExists(atPath: inputURL.path) else { return nil }
                return (metadata, inputURL, directorySize(inputURL))
            }
            for item in completedWithInput.sorted(by: { $0.0.createdAt < $1.0.createdAt }) {
                guard currentBytes > configuration.maxCacheBytes else { break }
                try fileManager.removeItem(at: item.1)
                removedCount += 1
                removedBytes += item.2
                currentBytes -= item.2
            }
        }

        return CleanupSummary(removedBatchCount: removedCount, removedBytes: removedBytes)
    }

    private func writeMetadata(
        for batch: Batch,
        status: BatchStatus,
        completedAt: Date?,
        createdAt: Date = Date()
    ) throws {
        let existing = try? readMetadata(at: batch.batchMetadataURL)
        let metadata = BatchMetadata(
            id: batch.id,
            status: status,
            createdAt: existing?.createdAt ?? createdAt,
            completedAt: completedAt ?? existing?.completedAt,
            sourcePaths: batch.sourcePaths,
            imageCount: batch.imageCount,
            chunkCount: batch.chunkCount,
            chunkSize: batch.chunkSize,
            totalBytes: batch.totalBytes,
            inputDirectory: batch.inputDirectory.path,
            manifestPath: batch.manifestURL.path,
            resultsPath: batch.resultsURL.path,
            reviewResultsPath: batch.reviewResultsURL.path,
            reportPath: batch.reportURL.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: batch.batchMetadataURL, options: .atomic)
    }

    private func readMetadata(at url: URL) throws -> BatchMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BatchMetadata.self, from: Data(contentsOf: url))
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func makeBatchId(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: now))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func containsReviewIntent(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = ["审核", "合规", "检查", "通过率", "不合格", "review", "compliance", "audit"]
        return keywords.contains { lowered.contains($0) }
    }

    private static func summarize(urls: [URL], fileManager: FileManager) -> (imageCount: Int, nonImageCount: Int, hasDirectory: Bool) {
        var imageCount = 0
        var nonImageCount = 0
        var hasDirectory = false
        for url in urls {
            if urlIsDirectory(url, fileManager: fileManager) {
                hasDirectory = true
                for file in enumerateFiles(under: url, fileManager: fileManager) {
                    if imageExtensions.contains(file.pathExtension.lowercased()) {
                        imageCount += 1
                    } else {
                        nonImageCount += 1
                    }
                }
            } else if imageExtensions.contains(url.pathExtension.lowercased()) {
                imageCount += 1
            } else {
                nonImageCount += 1
            }
        }
        return (imageCount, nonImageCount, hasDirectory)
    }

    private struct ImageSource {
        let fileURL: URL
        let rootURL: URL
    }

    private static func collectImageSources(from urls: [URL], fileManager: FileManager) -> [ImageSource] {
        var sources: [ImageSource] = []
        for url in urls {
            if urlIsDirectory(url, fileManager: fileManager) {
                let images = enumerateFiles(under: url, fileManager: fileManager)
                    .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.path < $1.path }
                sources.append(contentsOf: images.map { ImageSource(fileURL: $0, rootURL: url) })
            } else if imageExtensions.contains(url.pathExtension.lowercased()) {
                sources.append(ImageSource(fileURL: url, rootURL: url.deletingLastPathComponent()))
            }
        }
        return sources.sorted { $0.fileURL.path < $1.fileURL.path }
    }

    private static func enumerateFiles(under directory: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private static func urlIsDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func relativePath(for fileURL: URL, under rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func personName(for fileURL: URL, root: URL) -> String {
        let relative = relativePath(for: fileURL, under: root)
        let components = relative.split(separator: "/").map(String.init)
        if components.count > 1 {
            return components[0]
        }
        return fileURL.deletingLastPathComponent().lastPathComponent
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? "source" : result
    }
}
