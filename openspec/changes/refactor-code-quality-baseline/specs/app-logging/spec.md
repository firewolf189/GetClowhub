## ADDED Requirements

### Requirement: Unified Logging via os.Logger

应用代码 SHALL 通过 `os.Logger`（Apple 统一日志系统）输出运行时日志，并通过单一的 `AppLogger` 入口暴露按 category 区分的 `Logger` 实例。`AppLogger` 中所有 `Logger` 实例 SHALL 使用 subsystem `com.cc.OpenClawInstaller`，category 至少覆盖 `installer`、`service`、`ui`、`auth` 四类。

#### Scenario: AppLogger 提供分类入口

- **WHEN** 开发者打开 `OpenClawInstaller/Services/AppLogger.swift`
- **THEN** 文件中定义 `enum AppLogger`（或等价 namespace），并暴露 `installer`、`service`、`ui`、`auth` 四个 `static let` 形式的 `Logger` 属性
- **AND** 每个 `Logger` 的 subsystem 均为 `com.cc.OpenClawInstaller`

#### Scenario: Console.app 可按子系统过滤

- **WHEN** 用户在 macOS Console.app 中以 subsystem `com.cc.OpenClawInstaller` 过滤
- **AND** 应用执行任意有日志输出的操作
- **THEN** Console.app 显示对应日志条目并按 category 正确分类

### Requirement: No Bare print() in Application Sources

`OpenClawInstaller/` 目录下的 Swift 源代码 SHALL NOT 使用裸 `print()` 调用作为日志手段。所有诊断输出 SHALL 通过 `AppLogger` 的对应 category 实例完成。

#### Scenario: 仓库扫描无 print 残留

- **WHEN** 开发者执行 `grep -rn "^[[:space:]]*print(" OpenClawInstaller/ --include="*.swift"`
- **THEN** 无任何匹配结果
- **AND** 此前文档中标记的 6 处 `print()` 调用全部已替换为 `AppLogger.<category>.<level>("...")`

#### Scenario: 测试代码不受限

- **WHEN** 测试 target（`OpenClawInstallerTests`）需要在测试中输出诊断信息
- **THEN** 允许在测试代码中使用 `print()`（不在本约束范围内）
