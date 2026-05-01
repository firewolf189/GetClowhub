# GetClawHub 客服助手 — 设计文档

> 日期：2026-03-14 | 版本：1.1.11

---

## 功能定位

在 GetClawHub 任何页面都能点击「?」按钮弹出独立小窗口，向客服助手提问 GetClawHub 的使用问题。AI 根据用户指南 + 当前应用上下文给出针对性回答；服务不可用时降级为本地 FAQ 关键词匹配。

---

## 核心架构

```
用户提问
   ↓
HelpAssistantViewModel
   ↓
检测服务状态（viewModel.isServiceRunning）
   ├── 在线 → openclaw agent -m "[system prompt + 问题]"
   │         system prompt = 角色设定 + 用户指南全文 + 当前上下文
   │         返回 AI 回答
   │
   └── 离线 → 本地 FAQ 关键词匹配
              命中 → 返回预写答案
              未命中 → 返回兜底文案
```

---

## 入口

侧边栏底部（和外观切换、版本号同一行），增加一个 `questionmark.circle` 图标按钮。

- 点击打开独立小窗口
- 窗口已打开时点击则聚焦
- 关闭窗口后再点击重新显示，对话记录保留（窗口隐藏而非销毁）

---

## 窗口规格

| 属性 | 值 |
|------|------|
| 大小 | 380 x 520，固定不可调 |
| 层级 | `NSWindow.Level.floating`，浮于主窗口之上 |
| 样式 | `titled + closable`，无最小化/最大化 |
| 标题 | "GetClawHub Help" |
| 状态指示 | 标题栏右侧小圆点：绿色 = 在线，橙色 = 离线 |

---

## 窗口 UI 布局

```
┌─── GetClawHub Help ─────── 🟢 ✕ ┐
│                                   │
│  ┌─ 消息区域（ScrollView）──────┐  │
│  │                              │  │
│  │  🤖 Hi! 我是 GetClawHub 助手   │  │
│  │  有任何使用问题都可以问我。    │  │
│  │                              │  │
│  │  ┌ 快捷问题按钮 ───────────┐ │  │
│  │  │ 服务启动不了怎么办？     │ │  │
│  │  │ 如何配置模型？           │ │  │
│  │  │ 如何创建定时任务？       │ │  │
│  │  └─────────────────────────┘ │  │
│  │                              │  │
│  │         用户: 服务启动不了    │  │
│  │                              │  │
│  │  🤖 请按以下步骤排查：        │  │
│  │  1. 进入 Status 页面...      │  │
│  │                              │  │
│  └──────────────────────────────┘  │
│                                   │
│  ┌──────────────────────┐  ┌───┐  │
│  │ 请输入问题...         │  │ ↑ │  │
│  └──────────────────────┘  └───┘  │
│  离线模式 — 仅提供常见问题解答 🟠   │
└───────────────────────────────────┘
```

### 消息区域

- `ScrollView` + `LazyVStack`
- 助手消息：左对齐，🤖 图标前缀，系统背景色气泡
- 用户消息：右对齐，强调色气泡
- 自动滚动到最新消息
- AI 回复中显示 "Typing..." 加载动画

### 欢迎状态

无消息时显示：
- 欢迎语："Hi! 我是 GetClawHub 助手，有任何使用问题都可以问我。"
- 3 个快捷问题按钮（圆角边框文字按钮），根据当前页面动态选择：

| 当前页面 | 快捷问题 |
|---------|---------|
| Status | 服务启动不了怎么办？/ 如何重启服务？/ 如何查看系统信息？ |
| Configuration | 如何配置模型？/ 如何修改端口？/ Provider 怎么切换？ |
| Chat | 如何使用斜杠命令？/ 如何切换 AI 助手？/ 历史消息怎么查看？ |
| Cron | 如何创建定时任务？/ Cron 表达式怎么写？/ 如何暂停任务？ |
| Persona | 如何编辑 AI 性格？/ 四个文件分别是什么？/ 如何预览效果？ |
| Multi-Agent | 如何创建子代理？/ 如何在 Chat 中切换 AI？/ 如何删除子代理？ |
| Skills | 如何安装新技能？/ 技能状态含义？/ 去哪找更多技能？ |
| Models | 如何设置默认模型？/ 什么是 Fallback？/ 如何添加图像模型？ |
| Channels | 如何连接 Telegram？/ 渠道状态灯含义？/ 如何删除渠道？ |
| Plugins | 如何启用插件？/ 有哪些可用插件？/ 插件状态含义？ |
| Logs | 如何搜索日志？/ 日志颜色含义？/ 如何导出日志？ |
| 其他/默认 | 服务启动不了怎么办？/ 如何配置模型？/ 如何创建定时任务？ |

点击快捷问题等同于直接发送该文本。

### 底部输入栏

- 输入框 + 发送按钮（精简版，无工具行、无 Agent 选择器）
- Placeholder："请输入问题..."
- 回车发送，Shift+回车换行
- 发送中禁用输入框和按钮

### 底部状态条

- 仅离线时显示：一行小字 + 橙色圆点 "离线模式 — 仅提供常见问题解答"
- 在线时隐藏

---

## System Prompt 设计

由三段拼接，每次发送消息时实时组装：

### 第一段：角色设定与边界

```
You are the GetClawHub Help Assistant, a customer support bot
exclusively for the GetClawHub macOS application.

Rules:
1. ONLY answer questions related to GetClawHub usage, features,
   configuration, and troubleshooting.
2. If the user asks anything unrelated to GetClawHub (coding help,
   general knowledge, casual chat, etc.), politely decline and say:
   "This question is beyond my scope. Please use the Chat page to
   ask your AI assistant."
   (Use the user's language for this response.)
3. ALWAYS reply in the same language the user uses. If the user
   writes in Chinese, reply in Chinese. If in English, reply in
   English. Match the user's language exactly.
4. Keep answers concise, practical, and step-by-step.
5. When referencing app pages, use their exact names: Chat, Status,
   Persona, Multi-Agent, Configuration, Skills, Models, Channels,
   Plugins, Cron, Logs, Doctor.
```

### 第二段：用户指南全文

```
Below is the complete GetClawHub User Guide. Base all your answers
on this document:

---
[用户指南.md 全文内容，运行时从 Bundle 读取]
---
```

### 第三段：当前上下文（动态注入）

```
Current app context:
- Active page: [当前页面名称]
- Service status: [Running / Stopped]
- OpenClaw version: [版本号]
- Configured provider: [供应商名称]
- Port: [端口号]
```

从 `DashboardViewModel` 读取以下属性：
- `selectedTab` → 当前页面
- `isServiceRunning` → 服务状态
- `openClawVersion` → 版本号
- `selectedProvider` → 模型供应商
- `port` → 网关端口

---

## 离线 FAQ 方案

### 数据结构

```swift
struct FAQItem {
    let keywords: [String]
    let question: String
    let answerZh: String
    let answerEn: String
}
```

### 匹配逻辑

1. 用户输入转小写
2. 遍历所有 FAQItem，计算每条的关键词命中数
3. 取命中数最高的条目（最少命中 1 个关键词）
4. 根据用户输入语言（简单检测：是否包含中文字符）选择 `answerZh` 或 `answerEn`
5. 无任何命中时返回兜底文案

### 兜底文案

中文：
> 抱歉，离线模式下无法回答此问题。请先到 Status 页面启动服务后重试，或直接在 Chat 页面向 AI 提问。

英文：
> Sorry, this question cannot be answered in offline mode. Please start the service on the Status page and try again, or ask your AI assistant on the Chat page.

### 预置 FAQ 列表（约 15-20 条）

| 关键词 | 问题 |
|--------|------|
| 启动, start, 服务, service, 运行, run | 服务启动不了怎么办？ |
| 停止, stop, 关闭 | 如何停止服务？ |
| 重启, restart | 如何重启服务？ |
| 模型, model, 配置, config, provider | 如何配置模型？ |
| api, key, 密钥 | 如何设置 API Key？ |
| 端口, port | 如何修改端口？ |
| agent, 代理, 子代理, 创建 | 如何创建子代理？ |
| persona, 人设, 性格, identity | 如何编辑 AI 性格？ |
| 定时, cron, 自动, 任务, schedule | 如何创建定时任务？ |
| 技能, skill, 安装, install | 如何安装技能？ |
| 渠道, channel, telegram, discord, 连接 | 如何连接聊天平台？ |
| 插件, plugin, 启用, enable | 如何启用插件？ |
| 日志, log, 错误, error | 如何查看日志？ |
| 更新, update, 版本, version | 如何更新应用？ |
| 登录, login, 认证, auth | 如何登录？ |
| 诊断, doctor, 检查 | 如何运行诊断？ |
| 斜杠, 命令, slash, command | 如何使用斜杠命令？ |
| 历史, history, 记录 | 如何查看历史消息？ |
| 语言, language, 切换 | 如何切换界面语言？ |
| 主题, theme, 深色, dark, 浅色, light | 如何切换外观模式？ |

---

## 需要改动的文件

### 新建（3 个文件）

| 文件 | 职责 |
|------|------|
| `Models/HelpFAQ.swift` | FAQItem 数据模型 + 预置 FAQ 数组 + 匹配函数 |
| `ViewModels/HelpAssistantViewModel.swift` | 对话逻辑、在线/离线判断、prompt 拼接、消息管理 |
| `Views/HelpAssistantWindow.swift` | NSWindow 控制器 + SwiftUI 视图（消息列表、欢迎页、输入栏） |

### 修改（2 处）

| 文件 | 改动 |
|------|------|
| `Views/Dashboard/DashboardView.swift` | SidebarView 底部加 `questionmark.circle` 按钮 |
| Xcode 项目配置 | 将 `用户指南.md` 加入 Bundle Resources |

### 不改动

- `DashboardViewModel.swift` — 只读取属性
- `OpenClawService.swift` — 复用 `runCommand`
- 所有 Tab 视图 — 无改动
