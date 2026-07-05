import Foundation

// This guard exercises AttachmentProcessor's real inline-budget behavior.
// Because `swift scripts/<name>.swift` interprets only this single file, we
// bootstrap: compile the app's AttachmentProcessor.swift together with an
// embedded test harness via swiftc, run the binary, and propagate its status.

let repoRoot = FileManager.default.currentDirectoryPath
let processorSource = "\(repoRoot)/OpenClawInstaller/Services/AttachmentProcessor.swift"

guard FileManager.default.fileExists(atPath: processorSource) else {
    fputs("FAIL: AttachmentProcessor.swift not found at \(processorSource)\n", stderr)
    exit(1)
}

// Static checks on the view model wiring first (cheap).
let dashboardSource = try String(contentsOfFile: "\(repoRoot)/OpenClawInstaller/ViewModels/DashboardViewModel.swift", encoding: .utf8)
guard dashboardSource.contains("AttachmentProcessor") else {
    fputs("FAIL: DashboardViewModel should delegate attachment processing\n", stderr)
    exit(1)
}
guard !dashboardSource.contains("maxInlineImageAttachmentCount") else {
    fputs("FAIL: old count-based inline threshold should be removed\n", stderr)
    exit(1)
}

let harness = #"""
import Foundation

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("attachment-processor-budget-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

func makeFile(_ name: String, bytes: Int) throws -> URL {
    let url = root.appendingPathComponent(name)
    let data = Data(repeating: 0x2A, count: bytes)
    try data.write(to: url)
    return url
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let processor = AttachmentProcessor(
    imageMetadataReader: { url in
        switch url.lastPathComponent {
        case "huge-pixels.png":
            return AttachmentProcessor.ImageMetadata(width: 5_000, height: 4_000)
        case let name where name.hasSuffix(".png") || name.hasSuffix(".jpg"):
            return AttachmentProcessor.ImageMetadata(width: 1_000, height: 1_000)
        default:
            return nil
        }
    }
)

let tinyImages = try (0..<5).map { try makeFile("tiny-\($0).png", bytes: 100 * 1024) }
let tinyResult = processor.process(tinyImages)
check(tinyResult.inlineAttachments.count == 5, "five 100KB images should all be inline")
check(tinyResult.manifestText.contains("inline-image"), "manifest should label inline images")

let oversizedImages = try (0..<5).map { try makeFile("oversized-\($0).png", bytes: 3 * 1024 * 1024) }
let oversizedResult = processor.process(oversizedImages)
check(oversizedResult.inlineAttachments.isEmpty, "3MB images should exceed the per-image inline budget")
check(oversizedResult.manifestText.contains("image-path"), "oversized images should remain in manifest path mode")

let partialImages = try (0..<6).map { try makeFile("partial-\($0).jpg", bytes: 1_500_000) }
let partialResult = processor.process(partialImages)
check(partialResult.inlineAttachments.count > 0, "budget selection should inline eligible images before budget is exhausted")
check(partialResult.inlineAttachments.count < partialImages.count, "budget selection should leave remaining images in manifest")

let hugePixels = try makeFile("huge-pixels.png", bytes: 1024 * 1024)
let hugePixelsResult = processor.process([hugePixels])
check(hugePixelsResult.inlineAttachments.isEmpty, "20MP image should exceed the pixel budget")
check(hugePixelsResult.manifestText.contains("pixel budget"), "manifest should explain pixel-budget path mode")

let pdf = try makeFile("large.pdf", bytes: 4 * 1024 * 1024)
let txt = try makeFile("large.log", bytes: 4 * 1024 * 1024)
let audio = try makeFile("clip.mp3", bytes: 512 * 1024)
let video = try makeFile("clip.mp4", bytes: 512 * 1024)
let folder = root.appendingPathComponent("folder")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
_ = try makeFile("folder/hidden-child.txt", bytes: 16)

let nonImageResult = processor.process([pdf, txt, audio, video, folder])
check(nonImageResult.inlineAttachments.isEmpty, "non-images and folders should never inline content")
check(nonImageResult.manifestText.contains("read selected pages"), "PDF manifest should suggest page-selective reading")
check(nonImageResult.manifestText.contains("read selected ranges"), "log/text manifest should suggest range-selective reading")
check(nonImageResult.manifestText.contains("transcribe/extract only if needed"), "media manifest should not eagerly transcribe")
check(nonImageResult.manifestText.contains("list/glob first"), "folder manifest should not recurse")
check(!nonImageResult.manifestText.contains("hidden-child.txt"), "folder manifest should not recursively enumerate children")

print("attachment processor budget checks passed")
"""#

let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("verify-attachment-processor-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDir) }

let mainURL = workDir.appendingPathComponent("main.swift")
try harness.write(to: mainURL, atomically: true, encoding: .utf8)
let binaryURL = workDir.appendingPathComponent("verify_attachment_budget")

func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    do {
        try process.run()
    } catch {
        fputs("FAIL: could not launch \(launchPath): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

let compileStatus = run("/usr/bin/xcrun", [
    "swiftc",
    processorSource,
    mainURL.path,
    "-o", binaryURL.path
])
guard compileStatus == 0 else {
    fputs("FAIL: could not compile AttachmentProcessor test harness (status \(compileStatus))\n", stderr)
    exit(1)
}

let runStatus = run(binaryURL.path, [])
guard runStatus == 0 else {
    exit(runStatus)
}
