# GetClawHub Mac 客户端 · 更新说明（v1.1.90）

一句话：**同一条桌面会话不会因为隔夜没说话就把网关历史清掉；打开或发送时会把界面气泡和模型侧 transcript 对齐。**

---

## 这一版改的是什么

OpenClaw 没有 `reset: never`。默认每天 04:00 或短空闲会把网关 `*.jsonl` 归档，Mac 界面仍显示整段对话，下一句 `chat.send` 却只带最新一句，模型就像失忆。钉钉等频道也会撞上同一套重置。

这一版只走官方配置钩子，不改 OpenClaw 核心：

1. **启动时写入会话策略**：全局 `session.reset` 改为约十年 idle（当作「不因沉默而忘」）；比这更短的 `resetByChannel`（含 webchat）一并抬上去，用户自己设得更长的窗口不动。`/new` 和删除会话仍会清空。`dmScope` 仍是 `per-channel-peer`。
2. **蛋蛋（`main`）工作区**：没有显式 `default` 时把 `main` 标成默认，并钉住 `workspace/main`。若 live 目录没有 `MEMORY.md`，从旧的 `workspace-main` **复制**过去，不覆盖、不建符号链接。
3. **双存储对账**：打开会话和发送前，对照本地气泡与网关 jsonl。有 `*.jsonl.reset.*` 就还原；没有归档且当前 transcript 是空的，再用本地用户/助手气泡重建。网关用户句带 `:user` 后缀或附件清单时按同一句匹配，**不会把已有对话的完整 jsonl 覆盖成短气泡**。
4. 每个 UI 会话会记住网关 `sessionId`，下次能绑回同一条 transcript。

新安装同样带上这条 idle 策略。跨会话长期记忆（新开聊天仍知道上次买过什么）仍靠 `MEMORY.md` 内容，这一版不自动写。

---

## 升级方式

菜单栏 **GetClawHub → 检查更新**，或安装新的 DMG。
