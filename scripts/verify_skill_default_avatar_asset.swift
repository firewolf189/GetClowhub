import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetSet = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("SkillAvatarUnifiedDark.imageset")
let lightImage = assetSet.appendingPathComponent("skill-day.svg")
let darkImage = assetSet.appendingPathComponent("skill-night.svg")
let contents = assetSet.appendingPathComponent("Contents.json")
let agentAssetSet = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AgentAvatar.imageset")
let agentLightImage = agentAssetSet.appendingPathComponent("agent-day.svg")
let agentDarkImage = agentAssetSet.appendingPathComponent("agent-night.svg")
let skillsView = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("SkillsTabView.swift")

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(FileManager.default.fileExists(atPath: lightImage.path), "SkillAvatarUnifiedDark light SVG asset is missing")
expect(FileManager.default.fileExists(atPath: darkImage.path), "SkillAvatarUnifiedDark dark SVG asset is missing")

let contentsText = (try? String(contentsOf: contents, encoding: .utf8)) ?? ""
expect(contentsText.contains("skill-day.svg"), "asset catalog does not reference skill-day.svg")
expect(contentsText.contains("skill-night.svg"), "asset catalog does not reference skill-night.svg")
expect(contentsText.contains(#""appearance" : "luminosity""#), "asset catalog does not use luminosity appearance variants")
expect(!contentsText.contains("skill-avatar-unified-dark.png"), "asset catalog still references the replaced PNG")

let lightSVG = (try? String(contentsOf: lightImage, encoding: .utf8)) ?? ""
let darkSVG = (try? String(contentsOf: darkImage, encoding: .utf8)) ?? ""
let agentLightSVG = (try? String(contentsOf: agentLightImage, encoding: .utf8)) ?? ""
let agentDarkSVG = (try? String(contentsOf: agentDarkImage, encoding: .utf8)) ?? ""
expect(lightSVG.contains(#"viewBox="0 0 24 24""#), "skill light SVG should match the agent 24x24 viewBox")
expect(darkSVG.contains(#"viewBox="0 0 24 24""#), "skill dark SVG should match the agent 24x24 viewBox")
expect(lightSVG.contains(#"stroke-width="2.1""#), "skill light SVG stroke should match the agent icon")
expect(darkSVG.contains(#"stroke-width="2.1""#), "skill dark SVG stroke should match the agent icon")
expect(lightSVG.contains(#"r="8""#), "skill light SVG outer ring should match the agent icon")
expect(darkSVG.contains(#"r="8""#), "skill dark SVG outer ring should match the agent icon")
expect(lightSVG.contains(#"r="5""#), "skill light SVG middle ring should match the agent icon")
expect(darkSVG.contains(#"r="5""#), "skill dark SVG middle ring should match the agent icon")
expect(lightSVG.contains(#"r="2.2""#), "skill light SVG inner ring should match the agent icon")
expect(darkSVG.contains(#"r="2.2""#), "skill dark SVG inner ring should match the agent icon")
expect(!lightSVG.contains(#"r="4.5""#), "skill light SVG must not include a center dot")
expect(!darkSVG.contains(#"r="4.5""#), "skill dark SVG must not include a center dot")
expect(agentLightSVG.contains(#"stroke-width="2.1""#), "agent light SVG baseline stroke changed unexpectedly")
expect(agentDarkSVG.contains(#"stroke-width="2.1""#), "agent dark SVG baseline stroke changed unexpectedly")
expect(!lightSVG.contains(#"width="1254""#), "skill light SVG still uses the oversized generated canvas")
expect(!darkSVG.contains(#"width="1254""#), "skill dark SVG still uses the oversized generated canvas")

let viewText = (try? String(contentsOf: skillsView, encoding: .utf8)) ?? ""
expect(viewText.contains(#"Image("SkillAvatarUnifiedDark")"#), "SkillsTabView does not use SkillAvatarUnifiedDark as fallback")
expect(viewText.contains("isUsingDefaultIcon"), "SkillCatalogIcon should distinguish default icons from custom icons")
expect(viewText.contains("skillDefaultIconBackground"), "SkillCatalogIcon should give the default icon its own contrast background")

print("Skill default avatar matches the agent icon")
