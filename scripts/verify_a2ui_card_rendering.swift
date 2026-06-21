#!/usr/bin/env swift

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func read(_ path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8) else {
        fail("Missing or unreadable file: \(path)")
    }
    return text
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let payload = read("OpenClawInstaller/Models/A2UICardPayload.swift")
let renderer = read("OpenClawInstaller/Views/Dashboard/A2UICardView.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

expect(payload.contains("struct A2UICardPayload"), "A2UI payload model should be defined")
expect(payload.contains("enum A2UIComponentType"), "A2UI component allowlist should be explicit")
expect(payload.contains("A2UICardParser.parse"), "A2UI parser entry point should exist")
expect(payload.contains("```a2ui"), "A2UI parser should target fenced a2ui blocks")
expect(payload.contains("maxPayloadBytes"), "A2UI parser should cap payload size")
expect(payload.contains("maxComponentDepth"), "A2UI parser should cap component depth")
expect(payload.contains("maxComponentCount"), "A2UI parser should cap component count")
expect(payload.contains("sanitizedURL"), "A2UI URL handling should be constrained")

for component in ["Card", "Text", "Image", "Icon", "List", "Row", "Column", "Divider"] {
    expect(payload.contains("case \(component.lowercased())"), "A2UI allowlist should include \(component)")
}

expect(renderer.contains("struct A2UICardView"), "A2UI card SwiftUI renderer should be defined")
expect(renderer.contains("struct A2UIComponentView"), "A2UI component renderer should be defined")
expect(renderer.contains("Unsupported component"), "Unknown components should render a fallback")
expect(renderer.contains("AsyncImage"), "Image components should use SwiftUI image loading")
expect(renderer.contains("A2UIComponentView(component:"), "Renderer should recurse through component children")
expect(renderer.contains("A2UICardPalette"), "A2UI cards should use a dedicated color palette")
expect(renderer.contains("morandiKhakiBackground"), "Outer card should use a Morandi khaki background")
expect(renderer.contains("morandiKhakiBorder"), "Outer card should use a stronger khaki border")
expect(renderer.contains("innerCardBackground"), "Nested card panels should use a coordinated warm inner background")
expect(!renderer.contains("controlBackgroundColor"), "Outer A2UI card should not use the default control background")
expect(!renderer.contains("textBackgroundColor"), "Nested A2UI cards should not use the default text background")

expect(dashboard.contains("A2UICardParser.parse(content)"), "Assistant messages should try A2UI parsing before Markdown")
expect(dashboard.contains("A2UICardView(payload:"), "Assistant messages should render A2UI cards")
expect(dashboard.contains("MarkdownRenderPolicy.mode"), "Existing Markdown render policy should remain available")

expect(project.contains("A2UICardPayload.swift in Sources"), "A2UI payload file should be in Xcode sources")
expect(project.contains("A2UICardView.swift in Sources"), "A2UI renderer file should be in Xcode sources")

print("PASS: A2UI card rendering integration checks passed")
