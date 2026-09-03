import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
private enum OpenClawMissingPluginInstallRecordsTests {
    static func main() throws {
        try dropsRecordsWhoseInstallPathIsGone()
        try keepsRecordsWhoseInstallPathExists()
        try keepsEntriesWithoutInstallPath()
        try sortsDroppedIds()
        print("PASS: missing plugin install records")
    }

    private static func dropsRecordsWhoseInstallPathIsGone() throws {
        let records: [String: Any] = [
            "deepseek": ["installPath": "/missing/deepseek", "version": "2026.8.2"],
            "dingtalk": ["installPath": "/present/dingtalk", "version": "2026.4.24"]
        ]
        let result = OpenClawUpgradeReadiness.dropMissingInstallRecords(records) { path in
            path.hasPrefix("/present/")
        }
        try expect(result.dropped == ["deepseek"], "gone path must be dropped, got \(result.dropped)")
        try expect(result.records["deepseek"] == nil, "deepseek record must be removed")
        try expect(result.records["dingtalk"] != nil, "present dingtalk record must be kept")
    }

    private static func keepsRecordsWhoseInstallPathExists() throws {
        let records: [String: Any] = [
            "feishu": ["installPath": "/present/feishu", "version": "2026.7.1"]
        ]
        let result = OpenClawUpgradeReadiness.dropMissingInstallRecords(records) { _ in true }
        try expect(result.dropped.isEmpty, "existing paths must not be dropped, got \(result.dropped)")
        try expect(result.records["feishu"] != nil, "feishu must remain")
    }

    private static func keepsEntriesWithoutInstallPath() throws {
        let records: [String: Any] = [
            "memory-core": ["version": "bundled"],
            "odd": "not-an-object"
        ]
        let result = OpenClawUpgradeReadiness.dropMissingInstallRecords(records) { _ in false }
        try expect(result.dropped.isEmpty, "entries without installPath must be kept")
        try expect(result.records.count == 2, "both entries without a missing path must remain")
    }

    private static func sortsDroppedIds() throws {
        let records: [String: Any] = [
            "msteams": ["installPath": "/gone/msteams"],
            "deepseek": ["installPath": "/gone/deepseek"],
            "slack": ["installPath": "/gone/slack"]
        ]
        let result = OpenClawUpgradeReadiness.dropMissingInstallRecords(records) { _ in false }
        try expect(
            result.dropped == ["deepseek", "msteams", "slack"],
            "dropped ids must be sorted, got \(result.dropped)"
        )
    }
}
