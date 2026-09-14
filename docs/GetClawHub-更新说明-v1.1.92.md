# GetClawHub Mac 客户端 · 更新说明（v1.1.92）

一句话：**官方模型收窄为 DeepSeek 与 Qwen；Max 增加 kimi-k3。**

---

## 这一版改的是什么

客户端官方 GetClawHub 模型不再跟随 LiteLLM / 会员 Key 的完整清单。选择器只展示本版收过的官方目录，避免切到网关白名单里没有的模型导致发送失败。

这一版：

1. **Free / Pro**：只保留 DeepSeek（`deepseek-v4-pro`、`deepseek-v4-flash`）和 Qwen（`qwen3.6-flash`、`qwen3.6-plus`、`qwen3.7-plus`、`qwen3.7-max`）。
2. **Max**：上面 6 个之外增加 `kimi-k3`。
3. **写配置**：登录同步 Key 时按档位官方清单写入 `openclaw.json`，与选择器一致。
4. **不合并 CLI 多余模型**：`openclaw models list` 不再把旧模型塞进 GetClawHub 分组。

自定义供应商（OpenAI、Anthropic、百炼等）不受影响。

---

## 升级方式

菜单栏 **GetClawHub → 检查更新**，或安装新的 DMG。

发版一句话：官方模型收窄为 DeepSeek 与 Qwen，Max 增加 kimi-k3。
