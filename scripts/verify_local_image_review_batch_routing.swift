import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let viewModelURL = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let storeURL = root.appendingPathComponent("OpenClawInstaller/Services/ImageReviewBatchStore.swift")
let projectURL = root.appendingPathComponent("OpenClawInstaller.xcodeproj/project.pbxproj")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func read(_ url: URL) -> String {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        fail("Could not read \(url.path)")
    }
    return source
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

let viewModel = read(viewModelURL)
let store = read(storeURL)
let project = read(projectURL)

require(store.contains("ImageReviewBatches"), "batch store should use the local ImageReviewBatches cache root")
require(store.contains("manifest.jsonl"), "batch store should write manifest.jsonl")
require(store.contains("cleanupImageCache"), "batch store should expose image cache cleanup")
require(store.contains("maxCacheBytes"), "batch store should enforce a maximum local cache size")
require(store.contains("successfulImageRetentionDays"), "batch store should enforce retention by age")

require(viewModel.contains("ImageReviewBatchStore.isImageReviewBatchCandidate"), "upload flow should detect local image review batches")
require(viewModel.contains("runLocalImageReviewBatch"), "DashboardViewModel should run local image review batches")
require(viewModel.contains("ImageReviewBatchStore.chunkSessionKey"), "local batch worker should use unique chunk session keys")
require(viewModel.contains("buildChunkReviewPrompt"), "local batch worker should send chunk-scoped prompts")
require(viewModel.contains("appendChunkResult"), "local batch worker should persist chunk results incrementally")
require(viewModel.contains("cleanupImageCache"), "upload flow should trigger local cache cleanup")

require(project.contains("ImageReviewBatchStore.swift in Sources"), "ImageReviewBatchStore.swift should be compiled in the app target")

print("Local image review batch routing verification passed")
