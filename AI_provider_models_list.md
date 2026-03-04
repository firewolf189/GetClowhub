# AI模型供应商 Base URL 及模型列表

> 更新时间：2026-03-07

---

## 常用模型供应商

| # | Provider | Base URL | 默认 Model 列表 |
|---|----------|----------|-----------------|
| 1 | **OpenAI** | https://api.openai.com/v1 | gpt-4o, gpt-4o-mini, o1, o3-mini |
| 2 | **Anthropic** | https://api.anthropic.com/v1 | claude-sonnet-4-20250514, claude-opus-4-6, claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022 |
| 3 | **阿里云百炼 (bailian)** | https://dashscope.aliyuncs.com/compatible-mode/v1 | qwen3.5-plus, qwen3-max-2026-01-23, qwen3-coder-next, qwen3-coder-plus, MiniMax-M2.5, glm-5, glm-4.7, kimi-k2.5 |
| 4 | **DeepSeek** | https://api.deepseek.com/v1 | deepseek-chat, deepseek-reasoner |
| 5 | **Moonshot (月之暗面)** | https://api.moonshot.cn/v1 | kimi-k2.5 |
| 6 | **Google Gemini** | https://generativelanguage.googleapis.com/v1 | gemini-2.0-flash, gemini-2.0-flash-lite, gemini-1.5-pro, gemini-1.5-flash |
| 7 | **MiniMax** | https://api.minimax.io/v1 | MiniMax-M2.5 |
| 8 | **GLM (智谱)** | https://open.bigmodel.cn/api/paas/v4 | glm-5, glm-4.7 |

---

## 详细模型列表

### 1. OpenAI

- **Base URL**: `https://api.openai.com/v1`
- **API Key**: `sk-...`
- **模型列表**:
  - `gpt-4o` - 最新旗舰多模态模型
  - `gpt-4o-mini` - 轻量级快速模型
  - `o1` - 推理模型
  - `o3-mini` - 轻量级推理模型

---

### 2. Anthropic

- **Base URL**: `https://api.anthropic.com/v1`
- **API Key**: `sk-ant-...`
- **模型列表**:
  - `claude-sonnet-4-20250514` - Claude 4 最新版
  - `claude-opus-4-6` - Opus 4.6
  - `claude-3-5-sonnet-20241022` - Sonnet 3.5
  - `claude-3-5-haiku-20241022` - Haiku 3.5

---

### 3. 阿里云百炼 (bailian)

- **Base URL**: `https://dashscope.aliyuncs.com/compatible-mode/v1`
- **API Key**: `sk-sp-...`
- **模型列表**:

| 模型 ID | 上下文窗口 | 最大输出 |
|---------|------------|----------|
| `qwen3.5-plus` | 1,000,000 | 65,536 |
| `qwen3-max-2026-01-23` | 262,144 | 65,536 |
| `qwen3-coder-next` | 262,144 | 65,536 |
| `qwen3-coder-plus` | 1,000,000 | 65,536 |
| `MiniMax-M2.5` | 1,000,000 | 65,536 |
| `glm-5` | 202,752 | 16,384 |
| `glm-4.7` | 202,752 | 16,384 |
| `kimi-k2.5` | 262,144 | 32,768 |

---

### 4. DeepSeek

- **Base URL**: `https://api.deepseek.com/v1`
- **API Key**: `sk-...`
- **模型列表**:
  - `deepseek-chat` - 对话模型
  - `deepseek-reasoner` - 推理模型

---

### 5. Moonshot (月之暗面)

- **Base URL**: `https://api.moonshot.cn/v1`
- **API Key**: `sk-...`
- **模型列表**:
  - `kimi-k2.5` - Kimi K2.5 最新版

---

### 6. Google Gemini

- **Base URL**: `https://generativelanguage.googleapis.com/v1`
- **API Key**: `AIza...`
- **模型列表**:
  - `gemini-2.0-flash` - Gemini 2.0 快速版
  - `gemini-2.0-flash-lite` - Gemini 2.0 轻量版
  - `gemini-1.5-pro` - Gemini 1.5 专业版
  - `gemini-1.5-flash` - Gemini 1.5 快速版

---

### 7. MiniMax

- **Base URL**: `https://api.minimax.io/v1`
- **API Key**: `sk-...`
- **模型列表**:
  - `MiniMax-M2.5` - MiniMax M2.5

---

### 8. GLM (智谱)

- **Base URL**: `https://open.bigmodel.cn/api/paas/v4`
- **API Key**: `sk-...`
- **模型列表**:
  - `glm-5` - GLM 5 最新版
  - `glm-4.7` - GLM 4.7

---

## OpenClaw 配置示例

```json5
{
  "models": {
    "mode": "merge",
    "providers": {
      "openai": {
        "baseUrl": "https://api.openai.com/v1",
        "apiKey": "${OPENAI_API_KEY}",
        "api": "openai-completions"
      },
      "anthropic": {
        "baseUrl": "https://api.anthropic.com/v1",
        "apiKey": "${ANTHROPIC_API_KEY}",
        "api": "anthropic-messages"
      },
      "bailian": {
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "apiKey": "${DASHSCOPE_API_KEY}",
        "api": "openai-completions"
      },
      "deepseek": {
        "baseUrl": "https://api.deepseek.com/v1",
        "apiKey": "${DEEPSEEK_API_KEY}",
        "api": "openai-completions"
      },
      "moonshot": {
        "baseUrl": "https://api.moonshot.cn/v1",
        "apiKey": "${MOONSHOT_API_KEY}",
        "api": "openai-completions"
      },
      "google-genai": {
        "baseUrl": "https://generativelanguage.googleapis.com/v1",
        "apiKey": "${GOOGLE_API_KEY}",
        "api": "google-genai"
      },
      "minimax": {
        "baseUrl": "https://api.minimax.io/v1",
        "apiKey": "${MINIMAX_API_KEY}",
        "api": "anthropic"
      },
      "glm": {
        "baseUrl": "https://open.bigmodel.cn/api/paas/v4",
        "apiKey": "${GLM_API_KEY}",
        "api": "openai-completions"
      }
    }
  }
}
```