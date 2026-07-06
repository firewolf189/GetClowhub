import Foundation

enum SkillsParser {
    static func parseSkillsList(output: String?) -> ([SkillInfo], SkillsSummary) {
        guard let output = output else { return ([], SkillsSummary()) }

        var results: [SkillInfo] = []
        var summary = SkillsSummary()

        for line in output.components(separatedBy: .newlines) {
            if line.contains("Skills (") && line.contains("ready)") {
                if let range = line.range(of: "\\((\\d+)/(\\d+)\\s+ready\\)", options: .regularExpression) {
                    let match = String(line[range])
                    let nums = match.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if nums.count >= 2 {
                        summary.ready = Int(nums[0]) ?? 0
                        summary.total = Int(nums[1]) ?? 0
                    }
                }
                break
            }
        }

        var currentStatus: String?
        var currentName: String?
        var currentDesc: String?
        var currentSource: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed.hasPrefix("│") else { continue }

            if trimmed.contains("Status") && trimmed.contains("Skill") && trimmed.contains("Description") && trimmed.contains("Source") {
                continue
            }

            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5 else { continue }

            let status = cells[1]
            let skill = cells[2].drop(while: { !$0.isASCII })
                .trimmingCharacters(in: .whitespaces)
            let desc = cells[3]
            let source = cells[4]

            if !status.isEmpty {
                if let prevName = currentName, !prevName.isEmpty {
                    results.append(SkillInfo(
                        name: prevName,
                        status: currentStatus?.contains("ready") == true ? .ready : .missing,
                        description: currentDesc ?? "",
                        source: currentSource ?? ""
                    ))
                }
                currentStatus = status
                currentName = skill
                currentDesc = desc
                currentSource = source
            } else {
                if !skill.isEmpty {
                    currentName = (currentName ?? "") + skill
                }
                if !desc.isEmpty {
                    currentDesc = ((currentDesc ?? "") + " " + desc).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let prevName = currentName, !prevName.isEmpty {
            results.append(SkillInfo(
                name: prevName,
                status: currentStatus?.contains("ready") == true ? .ready : .missing,
                description: currentDesc ?? "",
                source: currentSource ?? ""
            ))
        }

        return (results, summary)
    }

    static func parseSkillInfo(output: String?, skillName: String) -> SkillDetailInfo? {
        guard let output = output else { return nil }

        var status = ""
        var description = ""
        var source = ""
        var path = ""
        var requirements: [String] = []
        var isReady = false

        var inRequirements = false
        var inDescription = true

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[agent-scope]") || trimmed.hasPrefix("Config warnings:")
                || trimmed.hasPrefix("- plugins.") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("│") || trimmed.hasPrefix("◇") || trimmed.hasPrefix("├") { continue }

            if trimmed.contains("Ready") || trimmed.contains("Missing") {
                if trimmed.contains("Ready") {
                    status = "Ready"
                    isReady = true
                } else {
                    status = "Missing requirements"
                    isReady = false
                }
                inDescription = true
                continue
            }

            if trimmed.hasPrefix("Details:") {
                inDescription = false
                inRequirements = false
                continue
            }

            if trimmed.hasPrefix("Requirements:") {
                inDescription = false
                inRequirements = true
                continue
            }

            if trimmed.hasPrefix("Tip:") {
                break
            }

            if trimmed.hasPrefix("Source:") {
                source = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.hasPrefix("Path:") {
                path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if inRequirements && trimmed.hasPrefix("-") {
                requirements.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if inDescription && !trimmed.isEmpty && !trimmed.contains("Ready") && !trimmed.contains("Missing") {
                if description.isEmpty {
                    description = trimmed
                } else {
                    description += " " + trimmed
                }
            }
        }

        return SkillDetailInfo(
            name: skillName,
            status: status,
            isReady: isReady,
            description: description,
            source: source,
            path: path,
            requirements: requirements
        )
    }
}
