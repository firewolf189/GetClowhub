# Tasks

按 design.md 的 D6 顺序，分 4 个独立 PR 推进。每个 PR 自包含、可独立 review、可独立回滚。

## 1. PR 1：图片资源清理 + 日志统一（最低风险）

> 现状校准（2026-05-01）：根目录 5 张 logo 经 MD5 验证均为 `Logo1.imageset/` 内文件的精确复本；Swift 代码仅引用 `Image("Logo1")`；`Logo1.imageset/Contents.json` 仅引用 `logo_white_touxiang.png`（light）+ `logo_dark_touxiang.png`（dark）。无需新建额外 image set。

- [ ] 1.1 安装/确认 `pngquant` 可用（`brew install pngquant`）
- [ ] 1.2 删除根目录 5 张 logo 副本：`logo1.png`、`logo_black_touxiang.png`、`logo_white_touxiang.png`、`logo_white.png`、`logo_dark.jpg`
- [ ] 1.3 删除 `Logo1.imageset/` 内未被 `Contents.json` 引用的死文件：`logo1.png`、`logo_black_touxiang.png`、`logo_white.png`、`logo_dark.jpg`
- [ ] 1.4 用 pngquant 压缩 `Logo1.imageset/` 内活跃图（`logo_white_touxiang.png`、`logo_dark_touxiang.png`），目标 quality 70-85，单张体积下降 ≥ 60%
- [ ] 1.5 校验：`ls *.png *.jpg` 在仓库根目录应无 logo 输出；`ls Logo1.imageset/` 应仅含 `Contents.json` + 2 张被引用的 PNG
- [ ] 1.6 新建 `OpenClawInstaller/Services/AppLogger.swift`，按 design D3 暴露 `installer`/`service`/`ui`/`auth` 四个 `Logger`
- [ ] 1.7 替换 6 处 `print()` 调用：`SparkleUpdater.swift`（3 处，category=`service`）、`NodeInstaller.swift`（1 处，category=`installer`）、`AuthManager.swift`（2 处，category=`auth`）
- [ ] 1.8 校验：`grep -rn "^[[:space:]]*print(" OpenClawInstaller/ --include="*.swift"` 应无匹配
- [ ] 1.9 Build Debug：检查所有界面 `Image("Logo1")` 显示正常、Console.app 可按 subsystem `com.cc.OpenClawInstaller` 过滤到日志
- [ ] 1.10 PR 提交，等待 review 与合并

## 2. PR 2：单元测试基线（中风险）

- [ ] 2.1 在 Xcode 中新建 unit test target `OpenClawInstallerTests`（XCTest 模板，macOS 13+）
- [ ] 2.2 配置 scheme：勾选 Test action 包含新 target；保持 Build action 不依赖
- [ ] 2.3 验证 `xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS'` 至少能跑通空模板
- [ ] 2.4 编写 `CommandExecutorTests.swift`：覆盖 stdout/stderr 分离、非零退出码映射、超时分支
- [ ] 2.5 编写 `AppErrorTests.swift`：遍历所有 case，断言 `errorDescription` 非空
- [ ] 2.6 本地在 macOS 13 SDK 上运行测试，确保全绿（`xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS,OS=13.x'`）
- [ ] 2.7 本地在 macOS 14 SDK 上运行测试，确保全绿（`xcodebuild test -scheme OpenClawInstaller -destination 'platform=macOS,OS=14.x'`）
- [ ] 2.8 验证 `./build_dmg.sh` 仍正常产出 DMG，未受测试 target 影响
- [ ] 2.9 PR 提交，等待 review 与合并

## 3. PR 3：DashboardView 文件拆分（高风险）

- [ ] 3.0 在 main HEAD 上采集视觉回归基线：`mkdir -p openspec/changes/refactor-code-quality-baseline/regression/baseline/`，对 Status / Chat / Models / Channels / Plugins / Skills / Cron / Logs / Config 全部 Tab 截图归档；为每个 Tab 写一份 markdown 段落记录"截图文件名 + 关键交互点（按钮/状态/弹层）"
- [ ] 3.1 创建目录：`Views/Dashboard/Chat/`、`Views/Dashboard/Chat/Media/`、`Views/Dashboard/Chat/Attachments/`
- [ ] 3.2 抽出 `Chat/ChatView.swift`（含 ChatMessageList 与 ChatView 主体）
- [ ] 3.3 抽出 `Chat/ChatBubble.swift`
- [ ] 3.4 抽出 `Chat/ChatWelcomeView.swift`
- [ ] 3.5 抽出 `Chat/ThinkingIndicator.swift`
- [ ] 3.6 抽出 `Chat/BackgroundTaskNotification.swift`
- [ ] 3.7 抽出 `Chat/Media/InlineVideoPlayer.swift` + `NativeVideoPlayerView.swift` + `InlineAudioPlayer.swift`
- [ ] 3.8 抽出 `Chat/Attachments/AttachmentThumbnail.swift` + `AttachmentPreview.swift`
- [ ] 3.9 抽出 `SidebarView.swift`、`ServiceStatusBadge.swift`、`DetailContentView.swift`、`SlashCommand.swift`
- [ ] 3.10 `DashboardView.swift` 仅保留顶层 `DashboardView` 主体；行数 ≤ 500
- [ ] 3.11 每抽一个 struct 后跑一次 Build，确保不破坏编译
- [ ] 3.12 视觉回归测试：依次访问 Status / Chat / Models / Channels / Plugins / Skills / Cron / Logs / Config 全部 Tab，逐张对照 3.0 采集的基线截图核对，差异点写入 PR 描述
- [ ] 3.13 Chat 功能回归：发文本、发附件、`@` 提及切 Agent、`/skills` 弹层、长流式响应、后台任务转后台/超时通知
- [ ] 3.14 i18n 回归：切换中/英/日，确认所有抽出文件中的文案均跟随刷新
- [ ] 3.15 PR 提交，等待 review 与合并

## 4. PR 4：DashboardViewModel 拆分（最高风险）

- [ ] 4.1 在 `ViewModels/` 下创建 7 个空 VM 文件：`ChatViewModel.swift`、`PluginsViewModel.swift`、`ChannelsViewModel.swift`、`ModelsViewModel.swift`、`CronViewModel.swift`、`SkillsViewModel.swift`、`LogsViewModel.swift`，每个含空 `@MainActor class XxxViewModel: ObservableObject {}` 骨架
- [ ] 4.2 在 `AppServices`（`OpenClawInstallerApp.swift`）中暴露 7 个新 VM 的工厂方法或单例
- [ ] 4.3 按 design D6 顺序，逐个领域迁移：
  - [ ] 4.3.1 LogsViewModel（最简单，约 40 行）
  - [ ] 4.3.2 SkillsViewModel
  - [ ] 4.3.3 PluginsViewModel
  - [ ] 4.3.4 ChannelsViewModel
  - [ ] 4.3.5 CronViewModel
  - [ ] 4.3.6 ModelsViewModel
  - [ ] 4.3.7 ChatViewModel（最复杂，最后做）
- [ ] 4.4 每迁移完一个领域：
  - [ ] 4.4.1 从 `DashboardViewModel.swift` 移除对应 `// MARK:` 段落与属性
  - [ ] 4.4.2 对应 Tab View 的 `@ObservedObject` 切换到新 VM
  - [ ] 4.4.3 跑一次 Build
  - [ ] 4.4.4 启动应用，专项验证该 Tab 的所有交互
- [ ] 4.5 实现共享 UI 状态回调：领域 VM 通过闭包/protocol 通知 `DashboardViewModel` 更新 `errorMessage` / `successMessage` / `showError` / `showSuccess` / `isPerformingAction`
- [ ] 4.6 移除领域 VM 中冗余的 UI 状态属性
- [ ] 4.7 验证 `objectWillChange` 转发链路：触发 `OpenClawService` 状态变化，观察各 VM 订阅的 View 是否正确刷新
- [ ] 4.8 全量回归：Dashboard 8 个 Tab + 安装向导端到端，再次对照 3.0 的基线截图核对，差异点写入 PR 描述
- [ ] 4.9 验证 `wc -l ViewModels/DashboardViewModel.swift` ≤ 500
- [ ] 4.10 PR 提交，等待 review 与合并

## 5. 收尾

- [ ] 5.1 4 个 PR 全部合并后，发布一次 Sparkle 增量版本（patch 版本号递增）
- [ ] 5.2 收集 1 周内用户反馈，确认无回归
- [ ] 5.3 删除 PR 期间的临时回归基线目录 `openspec/changes/refactor-code-quality-baseline/regression/`
- [ ] 5.4 按 OpenSpec 流程归档本 change：`openspec archive refactor-code-quality-baseline --yes`
- [ ] 5.5 归档后运行 `openspec validate --strict` 确认 specs/ 一致
