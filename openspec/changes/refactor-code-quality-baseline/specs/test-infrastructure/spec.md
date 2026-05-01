## ADDED Requirements

### Requirement: Unit Test Target

项目 SHALL 提供一个独立的 `OpenClawInstallerTests` Xcode unit test target，使用 XCTest 框架，与应用部署目标（macOS 13+）兼容。该 target SHALL 拥有独立的 Xcode scheme，使开发者可通过 `xcodebuild test -scheme OpenClawInstaller` 命令运行全部测试。

#### Scenario: 测试 target 存在并可独立运行

- **WHEN** 开发者在仓库根目录执行 `xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS'`
- **THEN** 命令成功编译测试 target 并执行所有测试
- **AND** 至少有一个测试用例被发现并执行
- **AND** 退出码为 0（所有测试通过）

#### Scenario: 发布构建不依赖测试

- **WHEN** 开发者执行 `./build_dmg.sh`
- **THEN** DMG 构建流程不调用 `xcodebuild test`
- **AND** 测试 target 失败不阻塞 DMG 产出

#### Scenario: 测试在 macOS 13 与 14 双 SDK 均通过

- **WHEN** 开发者分别执行 `xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS,OS=13.x'` 与 `xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS,OS=14.x'`
- **THEN** 两次执行均成功完成且退出码为 0
- **AND** 全部测试用例在两套 SDK 下行为一致

### Requirement: CommandExecutor Output Parsing Coverage

`CommandExecutor` 的输出解析行为 SHALL 由单元测试覆盖，包括 stdout/stderr 分离、退出码到 `AppError` 的映射、以及超时分支处理。

#### Scenario: stdout 与 stderr 正确分离

- **WHEN** 测试以一个同时输出 stdout 与 stderr 的命令调用 `CommandExecutor`
- **THEN** 返回结果中 stdout 与 stderr 文本分别归属正确字段
- **AND** 顺序保持原始命令的输出顺序

#### Scenario: 非零退出码触发 AppError

- **WHEN** 测试以一个返回非零退出码的命令调用 `CommandExecutor`
- **THEN** 调用方收到对应的 `AppError`，且 `errorDescription` 非空

#### Scenario: 超时被识别为独立错误

- **WHEN** 测试以一个超过指定超时时间的命令调用 `CommandExecutor`
- **THEN** 调用方收到 timeout 类别的 `AppError`，而非 stdout 截断或退出码错误

### Requirement: AppError Localization Coverage

`AppError` 的所有 case SHALL 由测试覆盖以保证 `errorDescription` 不返回 `nil` 或空字符串。

#### Scenario: 全部 case 都有可读描述

- **WHEN** 测试遍历 `AppError` 的所有 case
- **THEN** 每个 case 的 `errorDescription` 都返回非空、长度 > 0 的字符串
