# GetClawHub 使用与集成指南

> 适用版本：1.1.54+ ｜ 系统要求：macOS 13.0 及以上
>
> 本文是面向使用者的完整说明，重点覆盖三块：
> 1. **客户端的安装与日常使用**
> 2. **钉钉 Channel 配置**（让 AI 出现在钉钉里，可被 @ 对话）
> 3. **DWS 安装与使用**（让 AI 能操作钉钉的表格 / 日历 / 审批 / 文档等全套产品）
>
> 应用内「帮助助手」里还内置了一份基础《用户指南》，本文是它的进阶补充。

---

## 目录

- [一、产品是什么](#一产品是什么)
- [二、安装与首次配置](#二安装与首次配置)
- [三、主界面速览](#三主界面速览)
- [四、Chat：和 AI 对话](#四chat和-ai-对话)
- [五、钉钉 Channel 配置](#五钉钉-channel-配置)
- [六、DWS 安装与使用](#六dws-安装与使用)
- [七、钉钉 Channel 与 DWS 的关系](#七钉钉-channel-与-dws-的关系)
- [八、常见问题](#八常见问题)
- [附录：链接与路径速查](#附录链接与路径速查)

---

## 一、产品是什么

GetClawHub 是一个跑在你 Mac 上的 **AI 助手客户端**。它由四部分组成：

| 组成 | 作用 |
|---|---|
| **GetClawHub 客户端** | 你看到的 macOS 应用，负责界面、对话、配置 |
| **OpenClaw 网关（Gateway）** | 客户端在本地启动的后台服务，真正驱动 AI、管理会话、连接外部平台 |
| **模型服务** | 默认走 GetClawHub 官方服务（LiteLLM），也可换成自定义 API 供应商 |
| **Channels / Skills / Plugins** | 把 AI 接到钉钉、Telegram 等平台，并扩展它的能力 |

简单说：**客户端是遥控器，网关是发动机**。钉钉 Channel 和 DWS 都是装在「网关」这一侧的能力。

---

## 二、安装与首次配置

### 2.1 下载

| 地区 | 下载入口 |
|---|---|
| 国内 | `https://www.getclawhub.com/download/mac`（自动跳转阿里云杭州镜像，速度快） |
| 海外 | 同一链接，自动跳转 GitHub Releases |

> 下载链接会按你的地区 / 浏览器语言自动选源，无需手动切换。中文页面点下载按钮即走国内镜像。

### 2.2 安装向导（首次）

打开应用后，向导分 6 步：

1. 点击 **开始安装**
2. 等待环境检测（系统版本、磁盘空间等）
3. 安装 Node.js 运行时（优先用内置 Node.js，无需联网）
4. 安装 OpenClaw 核心服务（自动）
5. 设置网关：**端口**（默认 `18789`）+ **Auth Token**（自定义一个密码，保护本地接口）
6. 点击 **完成**，进入主界面

### 2.3 登录

部分功能（官方模型服务、账单、API Key 管理）需要登录：

1. 启动后点 **Log In**，浏览器自动打开登录页
2. 在浏览器完成登录，应用自动识别状态

### 2.4 自动更新

内置 Sparkle 自动更新：启动时检查新版本，发现后弹更新提示；也可点侧边栏底部版本号手动检查。国内用户的更新包同样走阿里云镜像。

---

## 三、主界面速览

左侧边栏顶部三个模式：

- **Config** — 功能配置菜单（默认）
- **My Team** — 你的 AI 团队（所有已安装 Agent）
- **Market** — 专家市场（招募预置 AI 专家）

Config 模式下的核心入口：

| 入口 | 用途 |
|---|---|
| **Chat** | 和 AI 对话（最常用） |
| **Status** | 启动 / 停止 / 重启服务，看运行状态 |
| **Configuration** | 配置网关、模型供应商 |
| **Multi-Agent** | 创建管理多个子 AI |
| **Models** | 管理可用模型 |
| **Skills** | 管理 AI 技能（**DWS 技能在这里装**） |
| **Channels** | 连接钉钉 / Telegram / 飞书等平台（**钉钉 Channel 在这里配**） |
| **Plugins** | 启用 / 禁用插件 |
| **Cron** | 定时自动任务 |
| **Logs** | 运行日志 |

> 完整的逐功能说明见应用内「帮助助手」→《用户指南》。本文以下只展开和钉钉集成强相关的部分。

---

## 四、Chat：和 AI 对话

### 发送与附件

- 输入框输入内容，**回车**发送，**Shift+回车**换行。
- 左下角 **📎** 可选附件；也可直接把文件 / **文件夹**拖进输入区（1.1.54 起支持选整个文件夹，AI 会自行探索目录）。
- 支持图片、PDF、Office、代码、Markdown 等；附件以缩略图展示，文件夹显示为蓝色 📁 图标。

### 切换 AI 与命令

- 输入框上方下拉菜单切换 Agent；或输入 `@` 弹出 Agent 列表快速选。
- 输入 `/` 弹出斜杠命令（`/new` 重置、`/agents`、`/model 名称`、`/skills`、`/think high` 等）。

### 长任务后台运行

任务超过 60 秒出现 **转后台** 按钮，点了之后任务后台跑、输入框解锁；完成后底部出现 ✅ 通知。最长运行 30 分钟。

---

## 五、钉钉 Channel 配置

> **目标**：把你的 AI 变成一个钉钉机器人，团队成员在钉钉群里 @ 它就能对话。
>
> 这一步配置的是「**入站**」：钉钉消息 → 你的 AI。

### 5.1 前置条件

- 一个钉钉组织（企业 / 团队），且你有该组织的**开发者权限**。
- 在钉钉开放平台创建一个「企业内部应用」。

### 5.2 在钉钉开放平台创建应用

1. 打开钉钉开放平台 `https://open-dev.dingtalk.com`，用组织管理员账号登录。
2. **应用开发 → 企业内部应用 → 创建应用**，填名称、Logo。
3. 进入应用详情，记下 **AppKey** 和 **AppSecret**（后面要填进客户端）。
4. **添加机器人能力**：
   - 在「机器人」配置里启用机器人。
   - 消息接收模式选 **Stream 模式**（长连接，无需公网回调地址，本地网关即可收消息）。
5. **授权权限**（按需）：通讯录只读、消息收发等。最少需要「机器人发送消息」「接收群 / 单聊消息」相关权限。
6. 发布 / 上线应用版本，使配置生效。

> Stream 模式是关键：它让本地运行的网关用长连接接收钉钉消息，不需要你的 Mac 有公网 IP 或反向代理。

### 5.3 在客户端添加渠道

1. 左侧 **Channels** → **Add Channel**。
2. 平台类型选 **DingTalk（钉钉）**。
3. 填入上一步拿到的 **App Key** 和 **App Secret**。
4. 点击添加。

客户端会把配置写进网关配置文件 `~/.openclaw/openclaw.json` 的 `channels.dingtalk`：

```json
{
  "channels": {
    "dingtalk": {
      "clientId": "<你的 AppKey>",
      "clientSecret": "<你的 AppSecret>",
      "enabled": true,
      "requireMention": true,
      "dmPolicy": "open",
      "groupPolicy": "open",
      "allowFrom": ["*"],
      "enableAICard": false
    }
  }
}
```

字段含义：

| 字段 | 含义 | 默认 |
|---|---|---|
| `clientId` / `clientSecret` | 钉钉应用的 AppKey / AppSecret | 你填的值 |
| `enabled` | 是否启用该渠道 | `true` |
| `requireMention` | 群里是否必须 @ 机器人才响应 | `true`（建议保留，避免机器人抢话） |
| `dmPolicy` | 单聊策略，`open` = 允许任何人私聊 | `open` |
| `groupPolicy` | 群聊策略，`open` = 允许任何群 | `open` |
| `allowFrom` | 允许的来源白名单，`["*"]` = 不限制 | `["*"]` |
| `enableAICard` | 是否用钉钉 AI 卡片样式回复 | `false` |

> 想收紧权限：把 `allowFrom` 改成具体的用户 / 群 ID 列表；或把 `dmPolicy` / `groupPolicy` 改成更严格的策略。改完保存并重启网关。

### 5.4 生效与测试

1. 进入 **Status** 页，点击 **Restart** 重启网关（让新渠道加载）。
2. 渠道列表里 DingTalk 的指示灯应变 **绿色**（已连接）。
3. 在钉钉里把机器人加进一个群，@ 它发一句话，应能收到 AI 回复。

指示灯含义：绿色=已连接 / 黄色=已配置未绑定 / 橙色=未配置 / 红色=出错。

### 5.5 排查

- **指示灯红色 / 收不到消息**：
  - 确认钉钉应用用的是 **Stream 模式**，且已发布上线。
  - 确认 AppKey / AppSecret 没填错（重新在 Channels 里删掉重加）。
  - 看 **Logs** 页搜 `dingtalk`，看握手 / 鉴权报错。
  - 如果渠道添加后始终不生效，去 **Plugins** 页确认钉钉相关插件已启用（钉钉渠道由对应插件提供 handler）。
- **@ 了不回**：确认机器人确实被加进群、且有「接收消息」权限；`requireMention: true` 时必须 @ 才触发。
- **改了配置不生效**：任何 `openclaw.json` 改动后都要 **Restart** 网关。

---

## 六、DWS 安装与使用

> **DWS = 钉钉全产品操作能力**。装上之后，你的 AI 能直接操作钉钉的 AI 表格、日历、通讯录、群聊机器人、待办、审批、考勤、日志、钉钉文档、云盘、AI 听记、邮箱、在线表格、知识库等。
>
> 这一步配置的是「**出站**」：你的 AI → 钉钉产品 API。

DWS 由两部分组成，缺一不可：

1. **`dws` 命令行工具**（CLI）—— 真正调用钉钉 API 的程序。
2. **dws 技能（Skill）**—— 告诉 AI「该用 `dws` 命令、怎么用」的说明书，装进 Skills 里。

### 6.1 安装 `dws` CLI

`dws` 是一个独立的命令行程序，通过 GitHub Releases 分发，安装到 `~/.local/bin/dws`。

```bash
# 验证是否已安装 / 查看版本
dws --version
# 期望输出类似：dws version v1.0.32 (...)

# 确认在 PATH 里（网关 / AI 需要能直接调用到 dws）
which dws        # 期望：/Users/<你>/.local/bin/dws
```

如果 `dws` 不存在，按你拿到的分发渠道安装（GitHub Release 安装脚本 / 下载二进制），装完确保 `~/.local/bin` 在 `PATH` 中：

```bash
# 若 which dws 找不到，把 ~/.local/bin 加入 PATH（zsh 示例）
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

> 要求 CLI 版本 **≥ 1.0.15**（dws 技能的 `cli_version` 约束）。低于此版本请升级。

### 6.2 登录钉钉（授权）

`dws` 自带内置的 OAuth 应用凭证，**多数情况下直接扫码登录即可，无需自建应用**：

```bash
# 本机：OAuth 设备流，终端会显示二维码 / 链接，用钉钉扫码授权
dws auth login

# 查看登录状态
dws auth status

# 退出 / 重置（Token 解密失败时用 reset）
dws auth logout
dws auth reset
```

登录后自动管理 Token：

| Token | 有效期 | 说明 |
|---|---|---|
| Access Token | 2 小时 | 调 API 用，过期自动刷新 |
| Refresh Token | 30 天 | 换新 Access Token，30 天内用一次即自动续期 |

**远程服务器 / Docker（无桌面）**：

```bash
dws auth login --device     # 设备流，在另一台有钉钉的设备上扫码
```

> `refresh_token` 单设备独占：在远程刷新后，源设备的凭证会失效。不要在多台机器同时长期使用同一账号。

**用自己的钉钉应用（可选）**：如果你想用自建应用的凭证（例如要绑定特定组织 / 权限），用环境变量覆盖内置凭证：

```bash
export DWS_CLIENT_ID=<你的 AppKey>
export DWS_CLIENT_SECRET=<你的 AppSecret>
dws auth login
```

凭证优先级：`--token` > `DWS_CLIENT_ID`/`DWS_CLIENT_SECRET` > 内置加密存储。

### 6.3 把 dws 技能装进 AI

光有 CLI 还不够，得让 AI 知道怎么用它。进 **Skills** 页安装 dws 技能：

1. **Skills** → **Install**。
2. 粘贴技能安装命令（格式：`npx skills add <仓库地址> --skill dws`，从你的技能分发渠道获取）。
3. 等待安装完成，技能列表里出现 `dws`。

安装后在 Skills 列表能看到它；点 **i** 可查看详情。技能会指导 AI：所有命令加 `--format json`、危险操作先确认、批量不超过 30 条等。

> 也可以在对话里用 `/skills` 浏览、`/skills dws` 直接启用。

### 6.4 它能干什么（产品总览）

| 产品 | 能力 |
|---|---|
| `aitable` | AI 表格：Base / 数据表 / 字段 / 记录 / 视图 / 图表 / 仪表盘 / 导入导出 |
| `calendar` | 日历：日程 / 参与者 / 会议室 / 闲忙查询 / 时间建议 |
| `contact` | 通讯录：用户 / 部门 / 组织架构查询 |
| `chat` | 群聊与机器人：建群 / 群成员管理 / 机器人群发 / 单聊 / Webhook |
| `todo` | 待办：创建（优先级 / 截止 / 循环）/ 查询 / 完成 / 删除 |
| `oa` | 审批：待办 / 发起 / 同意 / 拒绝 / 撤销 |
| `attendance` | 考勤：打卡记录 / 排班 / 汇总统计 |
| `report` | 日志：按模版写日报周报 / 收发 / 已读统计 |
| `doc` | 钉钉文档：搜索 / 读写 / 块级编辑 / 评论 |
| `drive` | 云盘：文件列表 / 上传 / 下载 / 文件夹 |
| `sheet` | 在线电子表格：工作表 / 区域读写 / 筛选 / 导出 |
| `minutes` | AI 听记：列表 / 摘要 / 转写 / 待办 / 思维导图 |
| `mail` | 邮箱：搜索（KQL）/ 详情 / 发送 |
| `ding` | DING 消息：应用内 / 短信 / 电话提醒 |
| `wiki` | 知识库：空间 / 成员 / 搜索 |
| `aisearch` | AI 搜问：按姓名 / 工号 / 部门 / 上下级搜人 |

### 6.5 怎么用（在对话里）

装好之后，直接用自然语言指挥 AI 即可，它会在后台调 `dws`：

- 「在钉钉建一个叫『项目管理』的 AI 表格，加上 任务名 / 负责人 / 截止日期 三个字段」
- 「查一下我明天的钉钉日程，有冲突的话提醒我」
- 「给研发群发个通知：今晚 10 点发版」
- 「把这周的周报按模版填好并提交」
- 「搜一下通讯录里市场部的同事」

> AI 执行**危险 / 写操作**（建表、发消息、提交审批等）前会先和你确认，确认后才真正执行。

### 6.6 健康检查与排查

```bash
dws doctor              # 检查登录状态、网络连通性、缓存、版本
dws auth status         # 只看登录态
dws config list         # 看所有可配置项及默认值
```

- 命令返回 `AUTH_TOKEN_EXPIRED` / `USER_TOKEN_ILLEGAL` / “Token验证失败” → 重新 `dws auth login`。
- 网络检查失败 → 确认能访问 `mcp.dingtalk.com`（DWS 的 Skill API 地址）。
- AI 说「找不到 dws 命令」→ `dws` 不在网关进程的 `PATH` 里：确认 `~/.local/bin` 在 PATH，必要时重启网关。
- 版本检查报 GitHub 限频 → 设 `GITHUB_TOKEN` 环境变量可提额（不影响日常使用）。

常用配置（环境变量）：

| 变量 | 说明 | 默认 |
|---|---|---|
| `DWS_CONFIG_DIR` | 配置目录 | `~/.dws` |
| `DWS_CACHE_DIR` | 缓存目录 | `~/.dws/cache` |
| `DWS_LANG` | 界面语言 `en`/`zh` | 跟随 `LANG` |
| `DWS_CLIENT_ID` / `DWS_CLIENT_SECRET` | 覆盖内置应用凭证 | 内置 |

---

## 七、钉钉 Channel 与 DWS 的关系

这两个都是钉钉集成，但方向相反、互补：

| | 钉钉 Channel | DWS |
|---|---|---|
| 方向 | **入站**：钉钉 → AI | **出站**：AI → 钉钉产品 |
| 解决什么 | 让人在钉钉里 @ 机器人对话 | 让 AI 去操作钉钉的表格 / 审批 / 日历等 |
| 配在哪 | 客户端 **Channels** 页 | `dws` CLI + **Skills** 页 |
| 凭证 | 钉钉应用 AppKey/AppSecret（写入 openclaw.json） | `dws auth login`（内置应用）或自建应用 env |
| 是否依赖对方 | 否 | 否 |

典型组合用法：在钉钉群里 @ 机器人「帮我把今天的考勤异常整理成一张表发到群里」——
**Channel** 负责把这句话送进 AI，**DWS** 负责查考勤（`attendance`）、建表（`aitable`）、群发（`chat`）。两者一起才完成闭环。

> 两者可以共用同一个钉钉应用，也可以各用各的应用（Channel 用一个、DWS 用内置或另一个）。共用时注意该应用要同时具备「机器人收发消息」和你要操作的产品权限。

---

## 八、常见问题

**Q：钉钉 Channel 和 DWS 必须都配吗？**
不必。只想在钉钉里和 AI 聊天 → 只配 Channel。只想让 AI 操作钉钉产品（哪怕你在客户端里指挥它）→ 只装 DWS。要完整闭环就两个都配。

**Q：配了钉钉 Channel，机器人不回消息？**
①确认钉钉应用是 Stream 模式且已上线；②确认 AppKey/AppSecret 正确；③Status 页 Restart 网关；④群里要 @ 机器人（`requireMention: true`）；⑤Logs 搜 `dingtalk` 看报错。

**Q：AI 提示「找不到 dws」或不会用钉钉能力？**
①`which dws` 确认已安装且在 PATH；②`dws auth status` 确认已登录；③Skills 页确认 dws 技能已安装；④重启网关让它重新加载 PATH 和技能。

**Q：`dws` 要不要自己去钉钉建应用？**
一般不用，`dws auth login` 用内置凭证扫码即可。只有需要绑定特定组织 / 自定权限时，才用 `DWS_CLIENT_ID`/`DWS_CLIENT_SECRET` 换成自建应用。

**Q：服务起不来 / AI 不回复（与钉钉无关）？**
进 Status 看状态、Logs 搜 `error`、点 Doctor 出诊断报告，再试 Restart。

---

## 附录：链接与路径速查

**链接**

| 用途 | 地址 |
|---|---|
| 客户端下载 | `https://www.getclawhub.com/download/mac` |
| 钉钉开放平台 | `https://open-dev.dingtalk.com` |
| 技能市场 | `https://skills.sh/` |
| 账号 / 账单 / API Key | `https://www.getclawhub.com/member/billing/` |

**本地路径**

| 内容 | 路径 |
|---|---|
| 网关配置（含 channels.dingtalk） | `~/.openclaw/openclaw.json` |
| 会话日志 | `~/.openclaw/agents/<agentId>/sessions/*.jsonl` |
| dws CLI | `~/.local/bin/dws` |
| dws 配置 / 缓存 | `~/.dws/` 、`~/.dws/cache/` |

**关键命令**

```bash
# 网关 / 客户端侧
openclaw --version
# 钉钉渠道：客户端 Channels 页直接写 ~/.openclaw/openclaw.json 的 channels.dingtalk，
# 不走 CLI；token 型渠道（如 Telegram）才用：openclaw channels add --channel <type> --token <token>

# DWS 侧
dws --version
dws auth login        # 扫码登录钉钉
dws auth status       # 看登录态
dws doctor            # 健康检查
dws <产品> --help     # 看某个产品的子命令，如 dws aitable --help
```

---

> 维护提示：钉钉 Channel 的字段以客户端 `addChannel` 实际写入 `openclaw.json` 的结构为准；DWS 行为以 `dws` CLI 自带的参考文档（`dws schema` / 各产品 `--help`）为准。版本升级后如有出入，以工具实际输出为准。
