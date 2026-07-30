## Why

macOS 客户端当前的“强制修复”会直接清理 Gateway 进程。一次钉钉故障表明，
缺少 `session.dmScope` 还会导致多个私聊用户共用同一个会话，使回复阻塞在残留的
处理中状态之后。当 Gateway 仍然健康时，修复入口应在不打断真实任务的前提下
修正该配置。

## What Changes

- 检查 `session.dmScope` 是否严格等于 `per-channel-peer`。
- 在保留其他配置的前提下修复缺失或错误的取值。
- 修改配置或重启之前，检查 Gateway 全局活动任务数。
- 存在活动任务时拒绝执行安全修复。
- 先校验临时候选配置，再原子替换正式配置。
- Gateway 可访问且空闲时执行优雅重启；即使配置已经正确，也通过重启清理内存中
  残留的会话状态。
- 无法确认任务状态时，将现有进程清理流程保留为需要单独危险确认的应急修复。
- 重启后验证 Gateway 健康状态、生效配置以及钉钉连接状态。

## Capabilities

### New Capabilities

- `gateway-safe-force-repair`：定义钉钉私聊隔离安全修复、活动任务保护、优雅重启、
  应急兜底和恢复验证。

### Modified Capabilities

无。

## Impact

- 影响 macOS 修复流程中的 `OpenClawServiceForceRepair`、`OpenClawService`、
  `DashboardViewModel` 和 `StatusTabView`。
- 需要 Gateway 提供一个最小的只读能力，返回所有渠道的真实活动任务数量。
- 增加修复状态的本地化文案和针对性自动测试。
- 不新增 Gateway 管理页面或会话管理界面。
- 不删除或重写历史会话记录。
