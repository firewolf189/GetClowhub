## ADDED Requirements

### Requirement: Domain-Scoped Dashboard ViewModels

Dashboard 模块 SHALL 按业务领域将状态与行为拆分到独立的 ViewModel 中。每个领域 ViewModel SHALL：
- 标注 `@MainActor` 并遵循 `ObservableObject` 协议；
- 仅持有该领域相关的 `@Published` 状态；
- 通过 `AppServices` 注入共享依赖（`OpenClawService`、`AppSettings`、`SystemEnvironment`），不直接持有其他领域 ViewModel 的引用；
- 在源文件命名上与领域一一对应（例：`ChatViewModel.swift`、`PluginsViewModel.swift`）。

`DashboardViewModel` 自身 SHALL 仅承担 Tab 切换、统一错误/成功提示、生命周期协调三类跨领域职责。

#### Scenario: 七个领域 VM 拆分到位

- **WHEN** 开发者打开 `OpenClawInstaller/ViewModels/`
- **THEN** 该目录下存在 `ChatViewModel.swift`、`PluginsViewModel.swift`、`ChannelsViewModel.swift`、`ModelsViewModel.swift`、`CronViewModel.swift`、`SkillsViewModel.swift`、`LogsViewModel.swift`
- **AND** 每个文件中定义的 class 标注 `@MainActor` 并遵循 `ObservableObject`
- **AND** `DashboardViewModel.swift` 中不再含有任何 `// MARK: - Plugin Management`、`// MARK: - Chat`、`// MARK: - Channel Management`、`// MARK: - Cron Job Management`、`// MARK: - Model Management`、`// MARK: - Skills Management`、`// MARK: - Logs Management` 段落

#### Scenario: 跨 VM 不存在直接引用

- **WHEN** 在 `OpenClawInstaller/ViewModels/` 下执行 `grep -l 'ChatViewModel\|PluginsViewModel\|ChannelsViewModel\|ModelsViewModel\|CronViewModel\|SkillsViewModel\|LogsViewModel' *.swift`
- **THEN** 任何一个领域 VM 文件都不出现其他领域 VM 类型名（`DashboardViewModel.swift` 协调容器除外）

#### Scenario: 共享 UI 状态保留在 DashboardViewModel

- **WHEN** 任一领域操作触发错误或成功
- **THEN** 通过回调或闭包通知 `DashboardViewModel` 更新 `errorMessage` / `successMessage` / `showError` / `showSuccess`
- **AND** 领域 VM 自身不再各自定义这些跨领域 UI 状态属性

### Requirement: Dashboard View File Decomposition

`Views/Dashboard/DashboardView.swift` SHALL 仅保留顶层组合（侧边栏 + Detail 路由），所有内嵌的子 View struct SHALL 抽取到独立文件。聊天相关子 View SHALL 进一步按"对话/媒体/附件"分组到子目录。

#### Scenario: 聊天子视图独立成文件

- **WHEN** 开发者查看 `Views/Dashboard/Chat/`
- **THEN** 该目录下至少存在 `ChatView.swift`、`ChatBubble.swift`、`ChatWelcomeView.swift`、`ThinkingIndicator.swift`、`BackgroundTaskNotification.swift`
- **AND** `Views/Dashboard/Chat/Media/` 下存在 `InlineVideoPlayer.swift`、`NativeVideoPlayerView.swift`、`InlineAudioPlayer.swift`
- **AND** `Views/Dashboard/Chat/Attachments/` 下存在 `AttachmentThumbnail.swift`、`AttachmentPreview.swift`

#### Scenario: 顶层组合视图保持精简

- **WHEN** 开发者运行 `wc -l Views/Dashboard/DashboardView.swift`
- **THEN** 行数 ≤ 500
- **AND** 该文件中除 `DashboardView`、`SidebarView`、`ServiceStatusBadge`、`DetailContentView` 与必要的局部辅助类型外，不再含有 Chat、媒体、附件、提示器等子组件 struct

### Requirement: Zero Behavior Change Guarantee

Dashboard 重构 MUST NOT 引入任何用户可见的行为差异，包括但不限于：UI 表现、动画、滚动定位、消息渲染顺序、流式输出、i18n 文本、键盘快捷键、附件上传流、`@` 提及与 `/skills` 面板交互、后台任务转后台/超时阈值。

#### Scenario: Dashboard 全 Tab 视觉与交互对齐

- **WHEN** 开发者在重构前后分别构建并启动应用
- **AND** 依次访问 Status / Chat / Models / Channels / Plugins / Skills / Cron / Logs / Config 等所有 Dashboard Tab
- **THEN** 每个 Tab 的视觉布局、按钮位置、状态文案、操作反馈与重构前完全一致
- **AND** Chat Tab 中输入历史回溯、`@` 提及、`/skills` 弹层、附件上传、后台任务通知功能均工作正常

#### Scenario: 国际化与流式渲染未受影响

- **WHEN** 用户在系统中切换应用语言（覆盖中、英、日三种典型）
- **AND** 与 AI 进行一次包含长流式输出的对话
- **THEN** 所有 UI 文案随语言切换而即时刷新
- **AND** 流式消息无 CPU 占满、无内容覆盖、无滚动错位
