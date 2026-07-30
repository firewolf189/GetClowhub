## ADDED Requirements

### Requirement: 修复流程强制启用私聊会话隔离
成功修复后，系统 SHALL 确保生效的 OpenClaw 配置中 `session.dmScope` 为
`per-channel-peer`。

#### Scenario: 新安装生成默认配置
- **WHEN** 客户端首次保存 OpenClaw 配置
- **THEN** 默认写入 `session.dmScope=per-channel-peer`
- **AND** 默认写入 `gateway.reload.deferralTimeoutMs=0`
- **AND** 保留现有的 Gateway、工具和其他配置字段

#### Scenario: DM Scope 缺失或取值错误
- **WHEN** 执行安全修复
- **THEN** 客户端通过 OpenClaw 官方配置命令将 `session.dmScope` 设置为
  `per-channel-peer`
- **AND** 保留所有无关配置字段

#### Scenario: DM Scope 已正确
- **WHEN** 执行安全修复时，生效值已经是 `per-channel-peer`
- **THEN** 客户端不重复写入配置
- **AND** 仍然请求安全重启 Gateway，以清理内存中的残留状态

### Requirement: 安全修复使用受支持的 OpenClaw 核心
系统 SHALL 复用 OpenClaw 已有安全重启能力，不在客户端或 OpenClaw 核心仓库
实现平行的任务调度逻辑。

#### Scenario: 已安装核心支持安全重启
- **WHEN** 已安装 OpenClaw 满足安全重启能力门槛
- **THEN** 客户端继续执行官方安全修复流程
- **AND** 不修改 OpenClaw 核心

#### Scenario: 已安装核心版本过旧
- **WHEN** 已安装 OpenClaw 不支持安全重启
- **THEN** 客户端返回“需要升级”结果
- **AND** 使用客户端内置核心升级路径，而不是修改核心或直接强制重启

### Requirement: 安全重启无限期等待活动任务
系统 SHALL 将 `gateway.reload.deferralTimeoutMs` 修复为 `0`，并使用
`openclaw gateway restart --safe --json` 请求重启。

#### Scenario: 当前没有活动任务
- **WHEN** 官方安全重启返回 `scheduled`
- **THEN** Gateway 安排受控重启
- **AND** 安全流程不调用进程清理

#### Scenario: 存在一个或多个活动任务
- **WHEN** 官方安全重启返回 `deferred`
- **THEN** Gateway 等待活动任务全部结束后再重启
- **AND** 客户端显示官方预检返回的活动任务数量
- **AND** 客户端不强制结束 Gateway

#### Scenario: 已存在安全重启请求
- **WHEN** 官方安全重启返回 `coalesced`
- **THEN** 客户端不重复提交强制操作
- **AND** 显示已有重启请求正在等待或执行

### Requirement: 配置写入后必须复核
请求安全重启前，系统 SHALL 使用 OpenClaw 官方配置能力写入并复核修复值。

#### Scenario: 两项配置复核成功
- **WHEN** `session.dmScope` 为 `per-channel-peer`
- **AND** `gateway.reload.deferralTimeoutMs` 为 `0`
- **THEN** 客户端请求官方安全重启

#### Scenario: 配置写入或复核失败
- **WHEN** 任一配置命令失败或生效值不匹配
- **THEN** 客户端不请求重启
- **AND** 返回不包含密钥和完整配置的错误

### Requirement: 无法完成安全重启时需要应急确认
系统 SHALL 将未经验证的应急修复与安全修复流程分离。

#### Scenario: 无法请求安全重启
- **WHEN** Gateway 不可访问或安全重启命令失败
- **THEN** 客户端不自动强制结束进程
- **AND** 仅在单独的危险确认后提供现有强制修复

#### Scenario: 用户取消应急修复
- **WHEN** 用户取消应急确认
- **THEN** 不执行进程清理或冷启动

### Requirement: 验证成功修复后的运行状态
立即安排重启后，系统 SHALL 验证修复后的运行状态。

#### Scenario: Gateway 重启成功
- **WHEN** 修复后 Gateway 恢复健康
- **THEN** 验证生效的 `session.dmScope` 为 `per-channel-peer`
- **AND** 检查钉钉渠道连接状态

#### Scenario: 钉钉尚未重新连接
- **WHEN** Gateway 健康且配置正确，但钉钉未连接
- **THEN** 客户端报告部分修复成功
- **AND** 保留已修复的有效配置

#### Scenario: 重启正在等待活动任务
- **WHEN** 官方安全重启返回 `deferred`
- **THEN** 客户端报告任务结束后将自动重启
- **AND** 不将尚未重启视为修复失败

### Requirement: 修复过程保护用户数据和密钥
修复期间，系统 SHALL 保留历史会话且不暴露密钥。

#### Scenario: 修复完成
- **WHEN** 安全修复或应急修复报告执行步骤
- **THEN** 不删除现有会话记录
- **AND** 日志和用户提示中不包含令牌、API Key 或完整配置
