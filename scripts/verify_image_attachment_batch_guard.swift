import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let viewModelURL = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard let source = try? String(contentsOf: viewModelURL, encoding: .utf8) else {
    fail("Could not read DashboardViewModel.swift")
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

require(source.contains("maxInlineImageAttachmentCount"), "missing image attachment count guard")
require(source.contains("maxInlineImageAttachmentBytes"), "missing image attachment byte guard")
require(source.contains("shouldInlineImageAttachments"), "missing large-batch inline decision")
require(source.contains("Image batch passed by file path"), "missing path-mode note for oversized image batches")
require(source.contains("imageBatchUsesPathMode"), "missing path-mode branch for image batches")

print("Image attachment batch guard verification passed")
