## Why

macOS 客户端当前的“强制修复”会直接清理 Gateway 进程。一次钉钉故障表明，
缺少 `session.dmScope` 还会导致多个私聊用户共用同一个会话，使回复阻塞在残留的
处理中状态之后。客户端内置的 OpenClaw `2026.7.1-2` 已提供官方安全重启能力，
因此修复入口应复用该能力，在不打断真实任务的前提下修正配置，而不是修改 Gateway
核心或自行实现活动任务调度。

## What Changes

- 检查 `session.dmScope` 是否严格等于 `per-channel-peer`。
- 新安装生成默认配置时直接写入 `session.dmScope=per-channel-peer` 和
  `gateway.reload.deferralTimeoutMs=0`。
- 通过 OpenClaw 官方配置命令将 `session.dmScope` 修复为 `per-channel-peer`，并将
  `gateway.reload.deferralTimeoutMs` 设置为 `0`，保留其他配置。
- 检查已安装 OpenClaw 是否具备安全重启能力；版本过旧时要求先升级到客户端内置核心，
  不修改 OpenClaw 核心仓库。
- 调用 `openclaw gateway restart --safe --json`。无活动任务时立即安排重启；存在活动
  任务时由 Gateway 等待任务全部结束后再重启，并向用户展示活动任务数量。
- 即使配置已经正确，也请求安全重启以清理内存中残留的旧会话状态。
- Gateway 不可访问或安全能力不可用时，将现有进程清理流程保留为需要单独危险确认的
  应急修复。
- 重启后验证 Gateway 健康状态、生效配置以及钉钉连接状态。

## Capabilities

### New Capabilities

- `gateway-safe-force-repair`：定义钉钉私聊隔离安全修复、活动任务保护、优雅重启、
  核心版本门槛、应急兜底和恢复验证。

### Modified Capabilities

无。

## Impact

- 影响 macOS 安装和修复流程中的 `InstallationViewModel`、
  `OpenClawServiceForceRepair`、`OpenClawService`、`DashboardViewModel` 和
  `StatusTabView`。
- 复用客户端内置 OpenClaw `2026.7.1-2` 已有的配置和安全重启接口，不修改
  OpenClaw 核心仓库。
- 旧版 OpenClaw 不满足能力门槛时，复用现有内置核心升级路径。
- 增加修复状态的本地化文案和针对性自动测试。
- 不新增 Gateway 管理页面或会话管理界面。
- 不删除或重写历史会话记录。
