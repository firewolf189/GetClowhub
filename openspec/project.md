# 项目背景

## 目的
GetClawHub 是一个原生 macOS 安装器和管理仪表板，服务于 **OpenClaw**——一个通过插件将 AI 模型提供商桥接到消息平台的 CLI 工具。本应用通过 SwiftUI 界面处理环境检测、Node.js 引导、OpenClaw 安装、配置以及日常运维（状态、日志、频道、模型、插件、技能、Agent、定时任务）。

终端用户可以一键完成从"无 Node、无 OpenClaw"到"已配置好 AI 提供商密钥和聊天频道的完整 CLI"的全过程。

## 技术栈
- **语言**：Swift 5.0（工具链 Swift 5.9+，Xcode 26.3）
- **UI**：SwiftUI（macOS），`@StateObject` / `ObservableObject` MVVM 架构
- **并发**：Swift Concurrency（`async/await`、`@MainActor`），Combine 用于变更转发
- **最低系统**：macOS 13.0（Ventura）
- **架构**：Apple Silicon + Intel x86_64（通用二进制）
- **自动更新**：Sparkle（appcast 托管于 `firewolf189.github.io/GetClowhub/appcast.xml`）
- **本地化**：通过自定义的 `LanguageManager` 使用 `Localizable.xcstrings`（25 种语言）
- **构建/发布**：由 `build_dmg.sh` 驱动 `xcodebuild` → `notarize_dmg.sh`
- **由应用管理的外部运行时**：Node.js（打包 tarball 位于 `OpenClawInstaller/Resources/*.tar.gz`，因 GitHub 100MB 限制被 gitignore），`openclaw`（通过 `npm i -g` 安装）

## 项目约定

### 代码风格
- Swift 习惯用法：UI 相关类使用 `@MainActor`，服务使用 `ObservableObject` 配合 `@Published` 状态。
- 服务位于 `OpenClawInstaller/Services/`，视图模型位于 `ViewModels/`，模型位于 `Models/`，视图按功能分组在 `Views/{Agent,Dashboard,Installation,Shared}/` 下。
- 单一的 `AppServices` 容器（`OpenClawInstallerApp.swift`）持有共享服务并注入到视图中——不要在视图中临时实例化服务。
- **视图**中的本地化文本使用 `Text(LocalizedStringKey)`；**视图模型**中使用 `LanguageManager.localizedBundle`。避免使用 `String(localized:)`——它不会跟随应用内语言切换（见 CHANGELOG v1.1.12 i18n 修复）。
- 参数化字符串：保持 `%@` 风格的键与 `Localizable.xcstrings` 一致；不要对使用 `%@` 定义的键使用 Swift 的 `\()` 字符串插值。

### 架构模式
- **单一服务容器**（`AppServices`）在应用启动时构造一次；子级的 `objectWillChange` 会被转发，以便嵌套服务更新时 SwiftUI 重新渲染。
- **三个顶层视图模式**：`initial`（落地页）→ `installation`（向导）→ `dashboard`（安装后管理）。由 `MainContentView` 路由。
- **条件编译标志** `REQUIRE_LOGIN` 切换登录遮罩（`AuthManager`）。Release 构建默认要求登录；`build_dmg.sh` 中的 `--no-login` 构建开放版。
- **CommandExecutor** 集中管理 shell 调用，配合 `PermissionManager` 处理特权操作；切勿在视图或视图模型中直接 spawn `Process`——必须通过它。
- **SystemEnvironment** 是"Node 是否已安装 / OpenClaw 是否已安装 / 使用哪个镜像"的唯一可信来源；视图应观察它而不是重新检测。

### 测试策略
当前没有自动化测试目标。验证方式为手动：通过 `build_dmg.sh` 构建，在干净的 macOS 用户上端到端运行向导，依次操作每个 Dashboard 标签。修改安装流程时，需同时测试国内镜像和国际路径（应用通过 IP 服务自动检测）。

### Git 工作流
- 单一 `main` 分支；近期历史中没有功能分支。
- 提交信息遵循 `release vX.Y.Z: <短描述>`（中文可以，中英混用也可以）。每次发布提交需在 Xcode 项目中递增 `MARKETING_VERSION` 和 `CFBundleVersion`。
- 发布：目前不打 tag——版本号在 `Info.plist` / pbxproj 中跟踪，通过 Sparkle appcast 暴露。

## 领域背景
- **OpenClaw** = 一个 Node.js CLI（`openclaw`），用于将 AI 提供商桥接到聊天平台。本应用不实现 OpenClaw；只负责安装和配置它。
- **支持的 AI 提供商**（见 `AI_provider_models_list.md`）：OpenAI、Anthropic、阿里云百炼（Bailian / DashScope）、DeepSeek、Moonshot、Google Gemini、MiniMax、GLM（智谱）。通过向导写入的 `openclaw_config_tmp.json` 进行配置。
- **频道插件**（见 `plugin_readme.md`）：WhatsApp、Telegram、Discord、iMessage、Slack、Signal、Mattermost、Google Chat、MS Teams、IRC、Matrix、LINE、Nextcloud Talk、Synology Chat、Zalo、钉钉（DingTalk）、飞书（Feishu）。大多数已打包；通过 `openclaw plugins enable <id>` 激活。
- **镜像逻辑**：检测为中国的用户，npm 使用 `registry.npmmirror.com`（阿里云），Node.js tarball 使用 CN 镜像；其他用户使用官方源。

## 重要约束
- **大于 100MB 的打包资源被 gitignore**（`OpenClawInstaller/Resources/*.tar.gz`）。Node.js tarball 必须本地存在才能构建可用的 DMG——它们不在仓库里。它们的缺失应视为环境配置步骤，不是 bug。
- **代码签名**使用 Developer ID `LJQJ5BHW7G`（浙江赫成智能电气有限公司）。公证（Notarization）是单独的步骤（`notarize_dmg.sh`）；发布时不要跳过。
- **Sparkle EdDSA 公钥**固定在 `Info.plist`（`SUPublicEDKey`）中。使用其他私钥签名的更新会被拒绝——更换密钥前请协调密钥管理。
- **`NSAllowsArbitraryLoads`** 设置为 true 以支持任意镜像端点。在审计所有下载路径（Node 镜像、OpenClaw npm registry、IP 检测服务）之前，不要收紧此设置。

## 外部依赖
- **Sparkle**（二进制框架，已嵌入）——自动更新。
- **GitHub Pages**（`firewolf189.github.io/GetClowhub/`）——托管 `appcast.xml` 和发布 DMG（见 `docs/appcast.xml`）。
- **GitHub 仓库** `firewolf189/GetClowhub`——appcast 引用的发布产物。
- **公共 IP 地理定位服务**——`NodeInstaller` / `SystemEnvironment` 使用它来选择中国还是国际镜像。多服务并查以提升可用性。
- **npm registry**（或 `registry.npmmirror.com` 镜像）——`openclaw` 和频道插件均从 npm 安装。
- **Apple 公证服务**——由 `notarize_dmg.sh` 在发布 DMG 时调用。
