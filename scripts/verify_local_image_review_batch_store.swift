import Foundation

// This guard exercises the real ImageReviewBatchStore app logic. `swift` can
// only interpret a single file, so we compile the app source together with an
// embedded behavioral driver via swiftc and run the result.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Features/Chat/Services/ImageReviewBatchStore.swift",
]

let driverSource = #"""
import Foundation

@main
struct VerifyLocalImageReviewBatchStore {
    static func main() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory
            .appendingPathComponent("getclowhub-image-review-batch-test-\(UUID().uuidString)")
        let sourceRoot = tempRoot.appendingPathComponent("source")
        let personA = sourceRoot.appendingPathComponent("Alice")
        let personB = sourceRoot.appendingPathComponent("Bob")
        try fm.createDirectory(at: personA, withIntermediateDirectories: true)
        try fm.createDirectory(at: personB, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: tempRoot)
        }

        for index in 0..<9 {
            let file = personA.appendingPathComponent("image-\(index).png")
            try Data("fake-png-\(index)".utf8).write(to: file)
        }
        try Data("fake-jpeg".utf8).write(to: personB.appendingPathComponent("portrait.jpg"))
        try Data("ignore me".utf8).write(to: sourceRoot.appendingPathComponent("notes.txt"))

        let storeRoot = tempRoot.appendingPathComponent("batches")
        let store = ImageReviewBatchStore(
            configuration: .init(
                rootDirectory: storeRoot,
                maxImagesPerChunk: 8,
                successfulImageRetentionDays: 30,
                maxCacheBytes: 1_000_000
            )
        )

        guard ImageReviewBatchStore.isImageReviewBatchCandidate(
            urls: [sourceRoot],
            messageText: "请审核这些图片是否合规",
            selectedAgentId: nil
        ) else {
            throw VerificationError("folder of review images should be detected as local batch candidate")
        }

        guard let batch = try store.createBatch(from: [sourceRoot], messageText: "请审核这些图片是否合规") else {
            throw VerificationError("expected a local image review batch")
        }

        try require(fm.fileExists(atPath: batch.manifestURL.path), "manifest.jsonl should exist")
        try require(fm.fileExists(atPath: batch.batchMetadataURL.path), "batch.json should exist")
        try require(batch.imageCount == 10, "batch should contain exactly 10 images")
        try require(batch.chunkCount == 2, "10 images with max chunk 8 should create 2 chunks")

        let manifest = try String(contentsOf: batch.manifestURL, encoding: .utf8)
        try require(manifest.contains("\"chunkIndex\":0"), "manifest should include chunk 0")
        try require(manifest.contains("\"chunkIndex\":1"), "manifest should include chunk 1")
        try require(!manifest.contains("notes.txt"), "manifest should ignore non-image files")

        let prompt = ImageReviewBatchStore.buildReviewPrompt(batch: batch, userMessage: "请审核这些图片是否合规")
        try require(prompt.contains(batch.manifestURL.path), "prompt should point the agent at manifest.jsonl")
        try require(prompt.contains("image-review-\(batch.id)-0000"), "prompt should define unique chunk session ids")
        try require(!prompt.lowercased().contains("base64"), "prompt should not ask for inline base64 transfer")

        let originalFile = personA.appendingPathComponent("image-0.png")
        try require(fm.fileExists(atPath: originalFile.path), "original image should exist before cleanup")
        try markBatchCompletedAndOld(batch: batch, fileManager: fm)

        let summary = try store.cleanupImageCache(now: Date())
        try require(summary.removedBatchCount == 1, "cleanup should remove one completed cached input directory")
        try require(summary.removedBytes > 0, "cleanup should report removed bytes")
        try require(!fm.fileExists(atPath: batch.inputDirectory.path), "cleanup should remove cached input directory")
        try require(fm.fileExists(atPath: originalFile.path), "cleanup must not delete the user's original image")
        try require(fm.fileExists(atPath: batch.manifestURL.path), "cleanup should retain manifest")

        print("Local image review batch store verification passed")
    }

    private static func markBatchCompletedAndOld(batch: ImageReviewBatchStore.Batch, fileManager: FileManager) throws {
        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        let metadata = ImageReviewBatchStore.BatchMetadata(
            id: batch.id,
            status: .completed,
            createdAt: oldDate,
            completedAt: oldDate,
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
        try encoder.encode(metadata).write(to: batch.batchMetadataURL)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: batch.rootDirectory.path)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw VerificationError(message) }
    }
}

struct VerificationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_local_image_review_batch_store-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let driverURL = workDir.appendingPathComponent("driver.swift")
try! driverSource.write(to: driverURL, atomically: true, encoding: .utf8)
let binaryURL = workDir.appendingPathComponent("verify")

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fputs("FAIL: could not launch \(arguments[0]): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

var compileArgs = ["swiftc"]
compileArgs += appSources.map { repoRoot.appendingPathComponent($0).path }
compileArgs += [driverURL.path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: ImageReviewBatchStore app source + verification driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
