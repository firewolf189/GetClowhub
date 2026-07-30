## ADDED Requirements

### Requirement: 修复流程强制启用私聊会话隔离
成功修复后，系统 SHALL 确保生效的 OpenClaw 配置中 `session.dmScope` 为
`per-channel-peer`。

#### Scenario: DM Scope 缺失或取值错误
- **WHEN** Gateway 可访问且空闲时执行安全修复
- **THEN** 客户端构建候选配置，将 `session.dmScope` 设置为
  `per-channel-peer`
- **AND** 保留所有无关配置字段

#### Scenario: DM Scope 已正确
- **WHEN** 执行安全修复时，生效值已经是 `per-channel-peer`
- **THEN** 客户端不重复写入配置
- **AND** 仍然优雅重启空闲的 Gateway，以清理内存中的残留状态

### Requirement: 安全修复保护活动任务
存在真实活动任务时，系统 SHALL NOT 修改配置或重启可访问的 Gateway。

#### Scenario: 存在一个或多个活动任务
- **WHEN** Gateway 返回的活动任务数大于零
- **THEN** 修复流程停止且不修改配置
- **AND** 不重启或强制结束 Gateway
- **AND** 客户端显示活动任务数量

#### Scenario: 处理中标记没有对应的真实任务
- **WHEN** Gateway 计算活动任务数量
- **THEN** 不将该残留标记计为活动任务

### Requirement: 替换正式配置前校验候选配置
替换 OpenClaw 正式配置之前，系统 SHALL 校验完整的候选配置。

#### Scenario: 候选配置校验成功
- **WHEN** 修复后的候选配置通过校验
- **THEN** 客户端创建带时间戳的备份
- **AND** 原子替换正式配置

#### Scenario: 候选配置校验失败
- **WHEN** 修复后的候选配置未通过校验
- **THEN** 正式配置保持不变
- **AND** 不重启 Gateway

### Requirement: 空闲修复使用优雅重启
对于没有活动任务且可访问的 Gateway，系统 SHALL 使用优雅重启。

#### Scenario: 可访问的 Gateway 处于空闲状态
- **WHEN** 预检返回零个活动任务且候选配置校验成功
- **THEN** 客户端请求优雅重启 Gateway
- **AND** 安全流程不调用进程清理

### Requirement: 无法确认活动状态时需要应急确认
系统 SHALL 将未经验证的应急修复与安全修复流程分离。

#### Scenario: 无法确认 Gateway 活动状态
- **WHEN** Gateway 不可访问或不支持活动状态查询
- **THEN** 客户端不自动修改配置或重启
- **AND** 仅在单独的危险确认后提供现有强制修复

#### Scenario: 用户取消应急修复
- **WHEN** 用户取消应急确认
- **THEN** 不执行进程清理或冷启动

### Requirement: 验证成功修复后的运行状态
重启后，系统 SHALL 验证修复后的运行状态。

#### Scenario: Gateway 重启成功
- **WHEN** 修复后 Gateway 恢复健康
- **THEN** 验证生效的 `session.dmScope` 为 `per-channel-peer`
- **AND** 检查钉钉渠道连接状态

#### Scenario: 钉钉尚未重新连接
- **WHEN** Gateway 健康且配置正确，但钉钉未连接
- **THEN** 客户端报告部分修复成功
- **AND** 保留已修复的有效配置

### Requirement: 修复过程保护用户数据和密钥
修复期间，系统 SHALL 保留历史会话且不暴露密钥。

#### Scenario: 修复完成
- **WHEN** 安全修复或应急修复报告执行步骤
- **THEN** 不删除现有会话记录
- **AND** 日志和用户提示中不包含令牌、API Key 或完整配置
