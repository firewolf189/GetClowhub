# Marketplace Agent 能力描述增强设计

> 日期: 2026-03-29
> 目标: 让 Commander 在多智能体协作时能准确匹配 agent 能力

## 问题

1. `marketplace_agents.json` 没有结构化的 specialty / when_to_use 字段
2. `MarketplaceContentConverter` 把整个 content 塞进 SOUL.md，没有拆分 AGENTS.md
3. `extractAgentDescription()` 只认 `## You Are`，但 marketplace agent 用 `## 🧠 Your Identity & Memory`，提取不到
4. README 中的 Specialty + When to Use 信息完全没有进入系统

## 方案

### 1. 数据层 — marketplace_agents.json 增加字段

从 agency-agents README 表格中提取 Specialty 和 When to Use 列，按 agent name 匹配合并到 JSON。

新增字段（可选，向后兼容）:
```json
{
  "specialty": "React/Vue/Angular, UI implementation, performance",
  "whenToUse": "Modern web apps, pixel-perfect UIs, Core Web Vitals optimization"
}
```

工具: Python 脚本 `scripts/enrich_marketplace.py`

### 2. 文件层 — 重写 MarketplaceContentConverter

按照官方 `convert.sh` 的拆分逻辑，将 content 按 `##` heading 关键词分类:

**SOUL.md（人格层）** — heading 命中以下关键词:
- identity, communication, style, critical rule, rules you must follow

**AGENTS.md（能力层）** — 其他所有 heading:
- mission, deliverables, workflow, capabilities, success metrics, learning 等
- 追加从 JSON 字段生成的结构化段落:
  ```
  ## When to Use
  Modern web apps, pixel-perfect UIs, Core Web Vitals optimization

  ## Specialty
  React/Vue/Angular, UI implementation, performance
  ```

**IDENTITY.md** — 改为:
```markdown
# 🎨 Frontend Developer
React/Vue/Angular, UI implementation, performance

---

Expert in React/Vue/Angular with focus on UI implementation and performance optimization.
```

`---` 之后的文本 = specialty 字段（有则用，否则 fallback 到 description）。

**MEMORY.md** — 保持空模板不变。

### 3. 提取层 — 改进 extractAgentDescription()

在现有逻辑后追加 fallback:

```
1. IDENTITY.md: --- 后文本（已有，现在覆盖 specialty）        ✅
2. SOUL.md: "## You Are"（已有，覆盖手动创建的 agent）          ✅
3. 【新增】SOUL.md: "## 🧠 Your Identity & Memory" 的 Role 行
4. 【新增】AGENTS.md: "## When to Use" 段落
```

最终 Commander 收到的格式:
```
- frontend-developer: Frontend Developer — React/Vue/Angular, UI implementation, performance | When: Modern web apps, pixel-perfect UIs
```

### 4. 安装流程 — MarketplaceDetailView.installAgent()

增加 AGENTS.md 文件的写入（步骤 4 中增加一个文件）。

## 改动文件

| 文件 | 改动 |
|------|------|
| `scripts/enrich_marketplace.py` | 新建，从 README 提取数据合并到 JSON |
| `marketplace_agents.json` | 脚本运行后更新，增加 specialty/whenToUse |
| `MarketplaceAgent.swift` | 增加 specialty/whenToUse 可选字段 + 重写 ContentConverter |
| `MarketplaceDetailView.swift` | installAgent() 增加 AGENTS.md 写入 |
| `DashboardViewModel.swift` | extractAgentDescription() 增加 fallback |

## 向后兼容

- specialty / whenToUse 为可选字段（String?），缺失时 fallback 到 description
- 已安装的 agent 不受影响（只影响新安装的）
- extractAgentDescription() 保留原有逻辑，新增为 fallback
