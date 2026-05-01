# OpenSpec 使用说明

面向使用 OpenSpec 进行规格驱动开发（spec-driven development）的 AI 编码助手的指南。

## 速查清单（TL;DR）

- 检索已有内容：`openspec spec list --long`、`openspec list`（仅在做全文搜索时使用 `rg`）
- 决定范围：是新增能力（capability），还是修改已有能力
- 选一个唯一的 `change-id`：kebab-case，动词开头（`add-`、`update-`、`remove-`、`refactor-`）
- 搭建脚手架：`proposal.md`、`tasks.md`、`design.md`（仅在需要时），以及每个受影响 capability 对应的 spec delta
- 编写 deltas：使用 `## ADDED|MODIFIED|REMOVED|RENAMED Requirements`；每条需求至少包含一个 `#### Scenario:`
- 校验：`openspec validate [change-id] --strict` 并修复问题
- 请求审批：在提案被批准之前不要开始实现

## 三阶段工作流

### 阶段 1：创建变更（Creating Changes）
当你需要做以下事情时，应创建提案：
- 新增功能或能力
- 引入破坏性变更（API、schema）
- 改变架构或模式
- 优化性能（行为有变化时）
- 更新安全模式

触发关键词（示例）：
- "Help me create a change proposal"
- "Help me plan a change"
- "Help me create a proposal"
- "I want to create a spec proposal"
- "I want to create a spec"

宽松匹配指南：
- 包含其中之一：`proposal`、`change`、`spec`
- 同时包含其中之一：`create`、`plan`、`make`、`start`、`help`

以下情况**不需要**写提案：
- Bug 修复（恢复预期行为）
- 错别字、格式调整、注释改动
- 依赖更新（非破坏性）
- 配置变更
- 为已有行为补充测试

**工作流**
1. 查看 `openspec/project.md`、`openspec list` 和 `openspec list --specs`，了解当前上下文。
2. 选一个唯一、动词开头的 `change-id`，在 `openspec/changes/<id>/` 下搭建 `proposal.md`、`tasks.md`、可选的 `design.md` 以及 spec deltas。
3. 使用 `## ADDED|MODIFIED|REMOVED Requirements` 起草 spec deltas，每条需求至少包含一个 `#### Scenario:`。
4. 运行 `openspec validate <id> --strict`，在分享提案前修复所有问题。

### 阶段 2：实现变更（Implementing Changes）
将以下步骤作为 TODO 跟踪，逐项完成。
1. **阅读 proposal.md** —— 理解要构建什么
2. **阅读 design.md**（如果存在）—— 回顾技术决策
3. **阅读 tasks.md** —— 获取实现清单
4. **按顺序实现任务** —— 依次完成
5. **确认完成度** —— 在更新状态前，确保 `tasks.md` 中每一项都已完成
6. **更新清单** —— 全部完成后，将每个任务标记为 `- [x]`，使清单与现实一致
7. **审批关卡** —— 在提案被审阅并批准之前，不要开始实现

### 阶段 3：归档变更（Archiving Changes）
部署后，单独提一个 PR 用于：
- 将 `changes/[name]/` → `changes/archive/YYYY-MM-DD-[name]/`
- 如果 capability 有变化，更新 `specs/`
- 对仅涉及工具的变更，使用 `openspec archive <change-id> --skip-specs --yes`（始终显式传入 change ID）
- 运行 `openspec validate --strict` 确认归档后的变更通过校验

## 任何任务前

**上下文清单：**
- [ ] 阅读 `specs/[capability]/spec.md` 中的相关规格
- [ ] 检查 `changes/` 中是否有冲突的待处理变更
- [ ] 阅读 `openspec/project.md` 了解项目约定
- [ ] 运行 `openspec list` 查看活跃的变更
- [ ] 运行 `openspec list --specs` 查看已有的能力

**创建规格前：**
- 始终先检查能力是否已存在
- 优先修改已有规格，而非创建重复
- 用 `openspec show [spec]` 查看当前状态
- 如果请求含糊，先问 1–2 个澄清问题再搭建脚手架

### 检索指南
- 列出规格：`openspec spec list --long`（脚本场景可加 `--json`）
- 列出变更：`openspec list`（或 `openspec change list --json`，已弃用但仍可用）
- 显示详情：
  - 规格：`openspec show <spec-id> --type spec`（过滤可加 `--json`）
  - 变更：`openspec show <change-id> --json --deltas-only`
- 全文搜索（使用 ripgrep）：`rg -n "Requirement:|Scenario:" openspec/specs`

## 快速开始

### CLI 命令

```bash
# 核心命令
openspec list                  # 列出活跃的变更
openspec list --specs          # 列出规格
openspec show [item]           # 显示变更或规格详情
openspec validate [item]       # 校验变更或规格
openspec archive <change-id> [--yes|-y]   # 部署后归档（自动化场景加 --yes）

# 项目管理
openspec init [path]           # 初始化 OpenSpec
openspec update [path]         # 更新指引文件

# 交互模式
openspec show                  # 提示选择项
openspec validate              # 批量校验模式

# 调试
openspec show [change] --json --deltas-only
openspec validate [change] --strict
```

### 命令选项

- `--json` —— 机器可读输出
- `--type change|spec` —— 区分类型
- `--strict` —— 全面校验
- `--no-interactive` —— 关闭交互提示
- `--skip-specs` —— 归档时不更新规格
- `--yes`/`-y` —— 跳过确认提示（非交互归档）

## 目录结构

```
openspec/
├── project.md              # 项目约定
├── specs/                  # 当前事实——已构建的内容
│   └── [capability]/       # 单一聚焦的能力
│       ├── spec.md         # 需求与场景
│       └── design.md       # 技术模式
├── changes/                # 提案——计划要变更的内容
│   ├── [change-name]/
│   │   ├── proposal.md     # 为什么、做什么、影响
│   │   ├── tasks.md        # 实现清单
│   │   ├── design.md       # 技术决策（可选；见判定标准）
│   │   └── specs/          # delta 变更
│   │       └── [capability]/
│   │           └── spec.md # ADDED/MODIFIED/REMOVED
│   └── archive/            # 已完成的变更
```

## 创建变更提案

### 决策树

```
新请求？
├─ 修复 Bug 以恢复 spec 行为？ → 直接修复
├─ 错别字/格式/注释？ → 直接修复
├─ 新功能/新能力？ → 创建提案
├─ 破坏性变更？ → 创建提案
├─ 架构变更？ → 创建提案
└─ 不确定？ → 创建提案（更稳妥）
```

### 提案结构

1. **创建目录：** `changes/[change-id]/`（kebab-case，动词开头，唯一）

2. **编写 proposal.md：**
```markdown
# Change: [变更的简要描述]

## Why
[1-2 句话说明问题/机会]

## What Changes
- [变更项的列表]
- [破坏性变更标注 **BREAKING**]

## Impact
- Affected specs: [受影响的能力清单]
- Affected code: [关键文件/系统]
```

3. **创建 spec deltas：** `specs/[capability]/spec.md`
```markdown
## ADDED Requirements
### Requirement: New Feature
The system SHALL provide...

#### Scenario: Success case
- **WHEN** user performs action
- **THEN** expected result

## MODIFIED Requirements
### Requirement: Existing Feature
[完整修改后的需求]

## REMOVED Requirements
### Requirement: Old Feature
**Reason**: [移除原因]
**Migration**: [迁移方式]
```
若涉及多个能力，请在 `changes/[change-id]/specs/<capability>/spec.md` 下创建多个 delta 文件——每个能力一个。

4. **创建 tasks.md：**
```markdown
## 1. Implementation
- [ ] 1.1 Create database schema
- [ ] 1.2 Implement API endpoint
- [ ] 1.3 Add frontend component
- [ ] 1.4 Write tests
```

5. **必要时创建 design.md：**
满足以下任一条件时创建 `design.md`，否则省略：
- 跨切面变更（多个服务/模块）或新的架构模式
- 引入新的外部依赖或重大的数据模型变更
- 安全、性能或迁移复杂度
- 存在歧义，需要先做技术决策再编码

最简 `design.md` 骨架：
```markdown
## Context
[背景、约束、相关方]

## Goals / Non-Goals
- Goals: [...]
- Non-Goals: [...]

## Decisions
- Decision: [做了什么、为什么]
- Alternatives considered: [备选方案 + 理由]

## Risks / Trade-offs
- [风险] → 缓解措施

## Migration Plan
[步骤、回滚]

## Open Questions
- [...]
```

## Spec 文件格式

### 关键：场景（Scenario）的格式

**正确**（使用 `####` 标题）：
```markdown
#### Scenario: User login success
- **WHEN** valid credentials provided
- **THEN** return JWT token
```

**错误**（不要用 bullet 或加粗）：
```markdown
- **Scenario: User login**  ❌
**Scenario**: User login     ❌
### Scenario: User login      ❌
```

每条需求**必须**至少有一个场景。

### 需求措辞
- 规范性需求使用 SHALL/MUST（除非有意写成非规范性，否则避免 should/may）

### Delta 操作

- `## ADDED Requirements` —— 新能力
- `## MODIFIED Requirements` —— 行为变更
- `## REMOVED Requirements` —— 废弃功能
- `## RENAMED Requirements` —— 名称变更

标题匹配会进行 `trim(header)` —— 忽略首尾空白。

#### 何时使用 ADDED 还是 MODIFIED
- ADDED：引入一个可以独立成立的新能力或子能力。当变更与已有需求正交时（例如新增 "Slash Command Configuration"，而不是修改已有需求的语义），优先使用 ADDED。
- MODIFIED：变更已有需求的行为、范围或验收标准。**始终粘贴完整的、更新后的需求内容（标题 + 所有场景）**。归档器会用你提供的内容**整体替换**该需求；如果只写部分 delta，原来的细节会丢失。
- RENAMED：仅在改名时使用。如果同时改了行为，使用 RENAMED（改名）外加引用新名称的 MODIFIED（改内容）。

常见陷阱：用 MODIFIED 添加新关注点却没有包含原始文本。这会在归档时丢失细节。如果你并不是要修改已有需求，请改用 ADDED 新增需求。

正确撰写 MODIFIED 需求的方法：
1) 在 `openspec/specs/<capability>/spec.md` 中定位已有需求。
2) 复制整个需求块（从 `### Requirement: ...` 到所有场景）。
3) 粘贴到 `## MODIFIED Requirements` 下，编辑以反映新行为。
4) 确保标题文本完全一致（忽略空白），并保留至少一个 `#### Scenario:`。

RENAMED 示例：
```markdown
## RENAMED Requirements
- FROM: `### Requirement: Login`
- TO: `### Requirement: User Authentication`
```

## 故障排查

### 常见错误

**"Change must have at least one delta"**
- 检查 `changes/[name]/specs/` 是否存在并包含 .md 文件
- 检查文件是否有操作前缀（如 `## ADDED Requirements`）

**"Requirement must have at least one scenario"**
- 检查场景是否使用 `#### Scenario:` 格式（4 个井号）
- 不要用 bullet 或加粗作为场景标题

**场景静默解析失败**
- 必须严格使用：`#### Scenario: Name`
- 调试命令：`openspec show [change] --json --deltas-only`

### 校验技巧

```bash
# 始终使用 strict 模式做全面检查
openspec validate [change] --strict

# 调试 delta 解析
openspec show [change] --json | jq '.deltas'

# 检查特定需求
openspec show [spec] --json -r 1
```

## Happy Path 脚本

```bash
# 1) 探索当前状态
openspec spec list --long
openspec list
# 可选的全文搜索：
# rg -n "Requirement:|Scenario:" openspec/specs
# rg -n "^#|Requirement:" openspec/changes

# 2) 选定 change id 并搭建脚手架
CHANGE=add-two-factor-auth
mkdir -p openspec/changes/$CHANGE/{specs/auth}
printf "## Why\n...\n\n## What Changes\n- ...\n\n## Impact\n- ...\n" > openspec/changes/$CHANGE/proposal.md
printf "## 1. Implementation\n- [ ] 1.1 ...\n" > openspec/changes/$CHANGE/tasks.md

# 3) 添加 deltas（示例）
cat > openspec/changes/$CHANGE/specs/auth/spec.md << 'EOF'
## ADDED Requirements
### Requirement: Two-Factor Authentication
Users MUST provide a second factor during login.

#### Scenario: OTP required
- **WHEN** valid credentials are provided
- **THEN** an OTP challenge is required
EOF

# 4) 校验
openspec validate $CHANGE --strict
```

## 多能力示例

```
openspec/changes/add-2fa-notify/
├── proposal.md
├── tasks.md
└── specs/
    ├── auth/
    │   └── spec.md   # ADDED: Two-Factor Authentication
    └── notifications/
        └── spec.md   # ADDED: OTP email notification
```

auth/spec.md
```markdown
## ADDED Requirements
### Requirement: Two-Factor Authentication
...
```

notifications/spec.md
```markdown
## ADDED Requirements
### Requirement: OTP Email Notification
...
```

## 最佳实践

### 简单优先
- 默认新增代码 <100 行
- 在被证明不够之前优先单文件实现
- 没有清晰理由就不引入框架
- 选择无聊但成熟的模式

### 增加复杂度的触发条件
仅在以下情况下增加复杂度：
- 性能数据证明现有方案太慢
- 具体规模要求（>1000 用户、>100MB 数据）
- 多个已验证的用例需要抽象

### 清晰的引用
- 代码位置使用 `file.ts:42` 格式
- 引用规格使用 `specs/auth/spec.md`
- 关联相关变更与 PR

### 能力命名
- 使用动词-名词：`user-auth`、`payment-capture`
- 单一能力单一目的
- 10 分钟可理解原则
- 描述需要 "AND" 时应拆分

### Change ID 命名
- 使用 kebab-case，简短而具描述性：`add-two-factor-auth`
- 优先动词开头：`add-`、`update-`、`remove-`、`refactor-`
- 保证唯一；若已被占用，追加 `-2`、`-3` 等

## 工具选择指南

| 任务 | 工具 | 原因 |
|------|------|-----|
| 按 pattern 找文件 | Glob | 快速模式匹配 |
| 搜索代码内容 | Grep | 优化的正则搜索 |
| 读取特定文件 | Read | 直接文件访问 |
| 探索未知范围 | Task | 多步调研 |

## 错误恢复

### 变更冲突
1. 运行 `openspec list` 查看活跃变更
2. 检查 spec 是否重叠
3. 与变更负责人协调
4. 考虑合并提案

### 校验失败
1. 加 `--strict` 标志运行
2. 查看 JSON 输出获取详情
3. 核对 spec 文件格式
4. 确保场景格式正确

### 上下文缺失
1. 先读 `project.md`
2. 查看相关规格
3. 浏览近期归档
4. 请求澄清

## 速查参考

### 阶段标识
- `changes/` —— 已提案，尚未构建
- `specs/` —— 已构建并部署
- `archive/` —— 已完成的变更

### 文件用途
- `proposal.md` —— 为什么、做什么
- `tasks.md` —— 实现步骤
- `design.md` —— 技术决策
- `spec.md` —— 需求与行为

### CLI 必备
```bash
openspec list              # 进行中的有什么？
openspec show [item]       # 查看详情
openspec validate --strict # 是否合规？
openspec archive <change-id> [--yes|-y]  # 标记完成（自动化加 --yes）
```

记住：Specs 是事实。Changes 是提案。保持两者一致。
