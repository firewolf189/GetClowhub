# Change: 代码质量基线重构（Dashboard 拆分 + 资源/测试/日志统一）

## Why

当前主仓存在四类可量化的代码质量负担，影响后续迭代速度与质量：

1. **巨型文件难以维护**：`Views/Dashboard/DashboardView.swift` 2483 行（含 14+ 个 View struct），`ViewModels/DashboardViewModel.swift` 1799 行（含 50+ 个 `@Published`，覆盖 7 个领域）。Xcode 增量编译慢、PR diff 噪声大、合并冲突频发。
2. **静态资源散落仓库根目录**：5 张 logo 共 ~3MB（`logo1.png` 1.2M、`logo_black_touxiang.png` 759K、`logo_white_touxiang.png` 727K、`logo_white.png` 253K、`logo_dark.jpg` 73K），不在 `Assets.xcassets` 中，未参与 App Slicing，构建产物体积偏大。
3. **零自动化测试**：纯手工验证（见 `project.md` 测试策略一节）。`CommandExecutor` 等关键服务的输出解析无回归保护，每次重构都靠"手跑安装向导"。
4. **日志手段不统一**：代码中 6 处裸 `print()` 调用，发布版无法静默/归档，也无法通过 Console.app 按子系统筛选。

这些问题相互独立但都属于"不影响用户行为、改善工程基线"的内务工作，适合打包成一个 refactor 提案统一推进，避免后续每项单独走流程造成的开销。

## What Changes

### 1. 拆分 `DashboardViewModel`（无行为变化）
按已有 `// MARK:` 边界拆分为 7 个领域 ViewModel：
- `ChatViewModel`（行 654-888）
- `PluginsViewModel`（行 916-1046）
- `ChannelsViewModel`（行 1047-1197）
- `ModelsViewModel`（行 1395-1662）
- `CronViewModel`（行 1198-1394）
- `SkillsViewModel`（行 442-653）
- `LogsViewModel`（行 333-373）

`DashboardViewModel` 仅保留 Tab 切换、错误/成功提示、生命周期协调（约 300 行）。新 VM 沿用 `@MainActor` 与 `ObservableObject`，通过 `AppServices` 注入共享依赖。

### 2. 拆分 `DashboardView`（无行为变化）
按职责拆出独立文件：
- `Chat/ChatView.swift`、`Chat/ChatBubble.swift`、`Chat/ChatWelcomeView.swift`、`Chat/ThinkingIndicator.swift`、`Chat/BackgroundTaskNotification.swift`
- `Chat/Media/InlineVideoPlayer.swift`、`Chat/Media/NativeVideoPlayerView.swift`、`Chat/Media/InlineAudioPlayer.swift`
- `Chat/Attachments/AttachmentThumbnail.swift`、`Chat/Attachments/AttachmentPreview.swift`
- `SidebarView.swift`、`ServiceStatusBadge.swift`、`DetailContentView.swift`、`SlashCommand.swift`

`DashboardView.swift` 仅保留顶层组合（约 200 行）。

### 3. 图片资源迁移到 `Assets.xcassets`
将 5 张根目录 logo 迁入 `Assets.xcassets`，使用 pngquant 做有损压缩（目标体积 ≤30% 原始）。所有引用点切换到 `Image("LogoBlack")` 等命名查询。仓库根目录的 PNG/JPG 删除。

### 4. 新建 `OpenClawInstallerTests` target
- 新增 Xcode Test target，使用 XCTest（与 macOS 13+ 部署目标兼容）。
- 首批用例覆盖 `CommandExecutor` 的输出解析（stdout/stderr 拆分、退出码处理、超时分支）以及 `AppError` 的 `LocalizedError` 描述。
- `build_dmg.sh` 不变（不强制跑测试），但提供独立命令 `xcodebuild test -scheme OpenClawInstaller`。

### 5. 统一日志：`print()` → `os.Logger`
- 引入 `Logging.swift`，按子系统（`com.cc.OpenClawInstaller`）和 category（`installer`、`service`、`ui`、`auth` 等）建立 `Logger` 实例。
- 替换现有 6 处 `print()` 为对应 category 的 `Logger.info/.debug/.error`。
- 后续禁止裸 `print()`（通过 PR review 把关，不引入工具校验以保持轻量）。

## Impact

- **Affected specs**（首次创建）：
  - `dashboard-architecture`（新增）
  - `app-assets`（新增）
  - `test-infrastructure`（新增）
  - `app-logging`（新增）

- **Affected code**：
  - `OpenClawInstaller/ViewModels/DashboardViewModel.swift`（拆分）
  - `OpenClawInstaller/Views/Dashboard/DashboardView.swift`（拆分）
  - `OpenClawInstaller/Views/Dashboard/*.swift`（消费方更新）
  - `OpenClawInstaller/Assets.xcassets/`（新增 image set）
  - `OpenClawInstaller.xcodeproj/project.pbxproj`（新增文件引用 + Test target）
  - 仓库根目录 `logo*.png`、`logo*.jpg`（删除）
  - `OpenClawInstaller/OpenClawInstallerApp.swift`（`AppServices` 暴露新 VM 工厂）
  - 6 处含 `print()` 的源文件（替换为 `Logger`）

- **风险**：
  - **零行为变化目标**——任何 UI 表现/数据流差异均视为回归。需手测 Dashboard 全部 8 个 Tab + 安装向导端到端。
  - VM 拆分会影响 Combine 链路（`objectWillChange` 转发），需特别注意 `AppServices` 容器的订阅传递。
  - PR 体积大、diff 多——见 `design.md` 的分阶段实施计划。

- **非影响**：
  - 用户可见行为、i18n key、Localizable.xcstrings、Sparkle appcast、签名/公证流程、Node tarball 资源 —— 均不变。
