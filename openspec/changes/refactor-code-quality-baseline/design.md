## Context

GetClawHub 进入 v1.1.34 后，Dashboard 模块已积累显著结构性负担：单文件 2000+ 行、零自动测试、资源散落、日志手段不一致。这些都属于"工程内务"——对终端用户不可见，但每次新增功能都在加重利息。

约束：
- **macOS 13+ 部署目标**——`os.Logger` 在 14+ 才完整稳定，13 上需走 `OSLog` 兼容写法。
- **零行为变化承诺**——重构不应触发任何 UI 或数据流差异。CHANGELOG 已明确标注的若干 i18n / 滚动 / streaming bug 均不能复发。
- **`@MainActor` 与 `objectWillChange` 转发约定**（见 `project.md`）必须保留——`AppServices` 是单一服务容器。
- **不引入新外部依赖**——保持 SPM 依赖列表稳定（仅 Sparkle）。

## Goals / Non-Goals

**Goals**
- 大幅降低 Dashboard 文件复杂度（目标：单文件 ≤500 行）。
- 建立可执行的单元测试基线（首批至少 1 个 service 完整覆盖）。
- 安装包体积下降 ≥1.5MB（来自图片压缩）。
- 日志可在 Console.app 按子系统/category 过滤。

**Non-Goals**
- 不引入新功能、不调整 UI、不改 i18n 键。
- 不引入 SwiftFormat / SwiftLint 等校验工具（轻量优先）。
- 不重写聊天流式渲染逻辑（已在 v1.1.25 修复，零碰）。
- 不调整 OpenClaw CLI 交互协议、不动 `CommandExecutor` 的对外签名（仅围绕它写测试）。
- 不迁移到 Swift Testing —— 与 macOS 13 兼容性优先，沿用 XCTest。
- 不将 `Localizable.xcstrings` 拆分（Xcode 工具链工作良好，拆分成本高于收益）。

## Decisions

### D1：VM 拆分粒度按"领域"而非"Tab"
- **Decision**：按业务领域拆分（Chat/Plugins/Channels/Models/Cron/Skills/Logs），而非按 UI Tab。
- **Why**：现有 `// MARK:` 边界已经按领域划分；若按 Tab 拆，`StatusTab` 与 `ConfigTab` 会混入 service control 与 provider 配置等多个领域。
- **Alternatives considered**：
  - 按 Tab 拆 —— 否决（领域耦合重新出现）。
  - 不拆 VM 只拆 View —— 否决（VM 1799 行才是编译瓶颈）。

### D2：拆出的 VM 通过 `AppServices` 注入，不互相直接持有
- **Decision**：每个领域 VM 独立从 `AppServices` 取依赖（`OpenClawService`、`AppSettings`、`SystemEnvironment`），互不感知彼此存在。
- **Why**：保持 `objectWillChange` 转发链路简单——单层订阅，避免 VM 之间循环引用。
- **共享的 UI 状态**（如 `errorMessage`、`successMessage`、`isPerformingAction`）继续留在 `DashboardViewModel`，由各子 VM 通过回调触发。

### D3：日志统一使用 `os.Logger`，包装为 `AppLogger.swift`
- **Decision**：建立 `OpenClawInstaller/Services/AppLogger.swift`，按 category 暴露静态实例：
  ```swift
  enum AppLogger {
      static let installer = Logger(subsystem: "com.cc.OpenClawInstaller", category: "installer")
      static let service   = Logger(subsystem: "com.cc.OpenClawInstaller", category: "service")
      static let ui        = Logger(subsystem: "com.cc.OpenClawInstaller", category: "ui")
      static let auth      = Logger(subsystem: "com.cc.OpenClawInstaller", category: "auth")
  }
  ```
- **Why**：`Logger` 在 macOS 11+ 可用，与 13+ 部署目标兼容；零外部依赖；Console.app 原生支持 subsystem 过滤；Release 构建自动剔除 `.debug` 输出。
- **Alternatives considered**：
  - swift-log —— 否决（外部依赖、对纯原生应用过重）。
  - 保留 `print()` —— 否决（无法过滤、无法分级）。

### D4：图片资源使用有损压缩（pngquant），原始文件不保留
- **Decision**：用 `pngquant --quality 70-85` 处理 `Logo1.imageset/` 内被 `Contents.json` 引用的活跃图；根目录 logo 副本与 imageset 内未被引用的死文件直接删除。
- **现状校准（2026-05-01）**：进入实施阶段前实测发现：
  - 根目录 5 张 logo（`logo1.png`、`logo_black_touxiang.png`、`logo_white_touxiang.png`、`logo_white.png`、`logo_dark.jpg`）经 MD5 校验，均为 `Logo1.imageset/` 内文件的精确复本——属于纯仓库冗余。
  - `Logo1.imageset/Contents.json` 仅引用 `logo_white_touxiang.png`（light）+ `logo_dark_touxiang.png`（dark）；imageset 内另存 4 张 PNG（`logo1.png`、`logo_black_touxiang.png`、`logo_white.png`、`logo_dark.jpg`）属于 imageset 内死文件，会被 Xcode 打入 bundle 但永不被引用。
  - Swift 代码仅引用 `Image("Logo1")`（8 处），无任何 `LogoBlack` / `LogoWhite` / `LogoDark` 命名引用。
- **修订后实施动作**：
  1. 删根目录 5 张 logo 副本（≈3.1MB）。
  2. 删 imageset 内 4 张未被引用的死文件（≈2.37MB）。
  3. pngquant 压缩剩下的 2 张活跃图（≈1.55MB → 预计 ~500KB）。
  4. **不**新建 `LogoBlack` / `LogoWhite` / `LogoBlackAvatar` / `LogoWhiteAvatar` / `LogoDark` 等新 image set——它们在代码中无引用，建出来也是死资产。
- **Why**：Logo 是 UI 装饰用途，70-85 质量肉眼无差；保留原始文件意义不大（git 历史可追）；不创造无引用的新 image set 符合"don't add features beyond what task requires"。
- **Alternatives considered**：
  - oxipng（无损）—— 否决（压缩比远低于目标，仅 ~10-20%）。
  - 同时保留原始 + Assets —— 否决（仓库继续臃肿）。
  - 严格按原 spec 建 5 个新 image set —— 否决（代码无引用 = 死资产）。
- **回滚预案**：如需恢复原始文件，从 git 历史 `git show <sha>:logo1.png > logo1.png`。

### D5：测试 target 命名 `OpenClawInstallerTests`，独立 scheme
- **Decision**：新建 unit test target，与主 target 分离的 scheme，CI 友好但不阻塞 DMG 构建。
- **Why**：`build_dmg.sh` 是发布关键路径，不应被测试失败阻塞（手测仍是发布前 gate）。后续若上 CI，可独立跑 `xcodebuild test -scheme OpenClawInstaller`。
- **首批测试范围**：
  - `CommandExecutor` 输出解析（stdout/stderr 分离、exit code 映射、timeout 处理）
  - `AppError.errorDescription` 在所有 case 下不为空
- **不在首批**：`NodeInstaller`、`OpenClawService` —— 涉及网络与 shell 副作用，需先抽 protocol，留给后续 PR。

### D6：8 Tab 视觉回归清单作为 PR 3/4 验收依据
- **Decision**：在 PR 3/4 实施前，先建立一份覆盖 Dashboard 全部 8 个 Tab 的视觉回归清单（以 main 分支当前状态为基线截图），作为拆分前后对比的硬验收物。
- **Why**：纯文字描述"视觉无差异"难落地；截图比对是低成本高保真的方式。
- **清单格式**：每 Tab 一份 markdown 段落，列出"截图文件名 + 关键交互点（按钮/状态/弹层）"，存放于 PR 描述或 `openspec/changes/refactor-code-quality-baseline/regression/`（仅 PR 期间使用，归档前删除）。

### D7：`AppLogger` 不在 Debug 构建写文件
- **Decision**：本次仅做 `print()` → `os.Logger` 替换，不实现日志落盘到文件。
- **Why**：保持本次范围聚焦。Console.app 已能满足开发期诊断与用户报问题时的取证需求（用户可导出 sysdiagnose）。
- **后续**：若用户反馈"附日志难"成为高频痛点，再单独提案 `AppLogger.fileSink` 能力。

### D8：测试在 macOS 13 与 14 双 SDK 均跑通
- **Decision**：`xcodebuild test` 必须在 `-destination 'platform=macOS,OS=13.x'` 与 `'platform=macOS,OS=14.x'` 两套 SDK 下均通过。
- **Why**：项目最低部署目标 13，但用户主流在 14+；任何只在新 SDK 下通过的测试都可能掩盖旧系统的运行时回归。
- **如何落地**：本地通过 Xcode 安装两个 macOS Simulator runtime（或在物理机上分别跑），CI 化暂不考虑。
- **代价**：单次回归执行时间翻倍，但首批测试用例量小（<50 条），可接受。

### D9：分阶段实施 —— 4 个 PR，按风险递增
1. **PR 1（最低风险）**：图片资源迁移 + `print()` → `Logger`（item 3 + 5）
2. **PR 2（中风险）**：新建 Test target + `CommandExecutor` 单测（item 4）
3. **PR 3（高风险）**：`DashboardView` 文件拆分（item 2）
4. **PR 4（最高风险）**：`DashboardViewModel` 拆分（item 1）

每个 PR 独立可发布、独立可回滚。PR 3、4 顺序不可调换（VM 引用变化会让 View 拆分 diff 难审）。

PR 3 启动前 SHALL 先完成 D6 视觉回归清单的基线截图采集（在 main HEAD 上执行）。

## Risks / Trade-offs

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| VM 拆分破坏 `@Published` 订阅链路，UI 不刷新 | 高 | 每个 VM 拆完后单步骤验证 Tab 表现；保留 `AppServices` 转发模式 |
| 图片命名查询失败导致空白 logo | 中 | 迁移后 grep 所有 `Image(` 调用点；DMG 自检 |
| `Logger` 在 macOS 13 上某些 API 不可用 | 低 | 仅使用 `Logger(subsystem:category:)` + `.info/.debug/.error/.notice` 这套 11+ 已稳定的 API |
| 测试 target 引入导致 `xcodebuild` 命令变更 | 低 | `build_dmg.sh` 显式指定 `-scheme OpenClawInstaller`，不受影响 |
| 4 个 PR 拉长时间窗口期间出现合并冲突 | 中 | 单分支 main 工作流（见 project.md），PR 串行合入，每次 rebase |

## Migration Plan

1. **准备**：在 main 上创建追踪 issue，列出 4 个 PR。
2. **PR 1（资源 + 日志，1-2 小时）**：
   - 用 pngquant 压缩 logo，迁入 Assets.xcassets
   - grep `Image\(` / `NSImage\(named:` 切到 catalog 名
   - 删除根目录 logo*.png / logo*.jpg
   - 新建 `AppLogger.swift`
   - 替换 6 处 `print()`
   - 手测 DMG 启动 + Dashboard logo 显示
3. **PR 2（测试，2-3 小时）**：
   - Xcode 新建 unit test target
   - 写 `CommandExecutorTests` 与 `AppErrorTests`
   - `xcodebuild test` 通过
4. **PR 3（View 拆分，3-4 小时）**：
   - 按 D6 列表逐个抽出 struct
   - 每抽一个跑一次 Build + Tab 视觉测
5. **PR 4（VM 拆分，4-6 小时）**：
   - 先建立 7 个空 VM 文件
   - 按 MARK 顺序逐块迁移属性 + 方法
   - DashboardView 引用切换为新 VM
   - 手测全部 Tab 行为对齐
6. **归档**：4 个 PR 全部合并并发布一个 Sparkle 增量版本后，按 OpenSpec 流程将本 change archive。

回滚：每个 PR 独立 revert 即可恢复；图片可从 git 历史恢复；VM 拆分回滚需注意 `AppServices` 同步还原。

## Open Questions

无（D6/D7/D8 已确定）。
