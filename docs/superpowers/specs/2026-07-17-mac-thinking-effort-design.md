# Mac 客户端「思考力度(reasoning effort)」设计方案

- 日期:2026-07-17
- 目标:对齐 Windows 端(v0.6.32/0.6.33/0.6.36)已上线的思考力度控件——per-request 档位 + 按模型自适应 + 「自动」安全档
- 状态:设计,待实现

---

## 一、Windows 已有(对齐目标)

- chat.send 原生 `thinking` per-request 字段
- Composer 档位徽章 + 可拖胶囊滑块弹窗(对齐 Claude)
- Models 页 `thinkingDefault`(每模型默认档)
- **按模型自适应档**:各模型支持档不同(实测:deepseek none/med/high、gpt 全档、gemini low/high、grok 拒);滑块档数随模型变 + clamp 吸附 + 存量迁移
- **「自动」安全档必须保留**:网关拒不支持档,gemini 实证 → 自动 = 不发显式 effort,让网关/模型自决
- 判档不可靠靠数 token → 靠**报错 + 家族规则**
- `/think <level>` 指令已可用(网关侧会话命令)

## 二、Mac 现状(已勘查)

- **已有**:`/think`(hasParam)、`/reasoning`、`ThinkingIndicator`(仅展示"思考中")——**无 effort 输入控件、chat.send 不带 thinking**
- **chat.send** 在 `Core/Gateway/GatewayClient.swift:333` `chatSend()`,params = `{sessionKey, idempotencyKey, message, attachments?}` —— **加 `thinking` 字段即可**
- **模型能力**:`Resources/providers_preset.json` 每模型已带 **`reasoning: true/false`**;getclawhub 31 模型中 10 个 true(deepseek-v4-pro/flash、qwen3.6-plus/flash、minimax-m2.7[-highspeed]、glm-5.1/5v-turbo、kimi-k2.6、doubao-seed-2.0-lite)
- **Composer UI**:`Features/Chat/Views/ChatComposerView.swift` 的 `toolbar`,布局 = 文件按钮 → `ComposerModelSelector` → 发送按钮 —— **effort 控件插在 ComposerModelSelector 旁**
- **组合模型状态**:`activeComposerModel`(每会话覆盖)—— effort 照此新增 `activeComposerEffort`

## 三、网关线格式(openclaw 2026.6.10 实证)

chat.send `params.thinking` 收富对象:
- `{ type: "disabled" }` 或 `{ effort: "none" }` —— 关思考
- `{ type: "adaptive" }` 或**省略字段** —— 自动
- `{ effort: "minimal" | "low" | "medium" | "high" }` —— 显式档
- (另有 `level` / `budgetTokens` 高级形态,本期不用)

> 实现时以 Windows 端 chat.send 的确切编码为准(对齐 `{effort}` vs `{type}`);openclaw 把 `thought_level`/`reasoning_effort` 归一到 validated thinking。

## 四、设计

### 4.1 数据/能力层
- 新增 `ThinkingEffort` 枚举:`.auto / .off / .minimal / .low / .medium / .high`(`.auto` 恒在)
- **每模型支持档 = 家族规则**(代码内按 model id 前缀映射,非硬编码进 preset,便于随网关调):
  - `reasoning:false` → 仅 `.auto`(控件禁用/隐藏)
  - deepseek* → `.auto/.off/.medium/.high`
  - qwen*/glm*/minimax*/kimi*/doubao* → `.auto/.off/.low/.medium/.high`(保守全档,遇拒降级)
  - 未知 reasoning:true → `.auto/.off/.low/.medium/.high`
- 兜底真相源永远是**网关报错**:发显式档被拒 → 自动回退 `.auto` + 记该 (model,tier) 不支持,后续 clamp

### 4.2 状态/持久化
- `DashboardViewModel.activeComposerEffort: ThinkingEffort`(仿 `activeComposerModel`)
- 每模型默认 `thinkingDefaultByModel: [String: ThinkingEffort]`(仿 Windows Models 页,存 UserDefaults/config)
- **切模型时 clamp**:新模型不支持当前档 → 吸附到最近支持档或 `.auto`(存量迁移同理)

### 4.3 发送链
- `ChatHelpers.sendChatMessage` → `chatSend(..., thinking:)`:把 `activeComposerEffort` 映射成 `thinking` 对象;`.auto` → **不传该字段**
- `GatewayClient.chatSend` 新增 `thinking: [String:Any]?` 参数,非空则 `params["thinking"] = thinking`
- **降级**:chat.send res 报 thinking 不支持 → 本次按 `.auto` 重发一次 + 轻提示(仿 model-patch 失败降级),不硬失败

### 4.4 Composer UI
- `ChatComposerView.toolbar` 加 `ComposerEffortSelector`(紧邻 ComposerModelSelector):
  - reasoning:false 模型 → 隐藏或灰显"自动"
  - reasoning:true → 紧凑徽章(显示当前档,如「中」),点开弹出档位选择(先做 Menu/分段,MVP;后续可做 Claude 式胶囊滑块对齐 Windows)
- 图标/文案走 i18n(zh-Hans/Hant/ja/ko/en)

### 4.5 /think 指令
- 保留(网关会话级命令);新 UI 是 per-request 持久等价物。可选:UI 改档时同步刷新,避免两处状态打架(本期可不做,UI 优先)

## 五、落地顺序(建议)
1. **MVP**:`ThinkingEffort` 枚举 + 家族规则 + `activeComposerEffort` + chatSend 带 thinking + Composer Menu 式档位选择 + 自动降级 + i18n。真机验证各家族(deepseek/qwen/glm)发不同档能生效、reasoning:false 只给自动、拒档能降级
2. **增强**:每模型 thinkingDefault 持久化 + 切模型 clamp/迁移 + Claude 式胶囊滑块(对齐 Windows 观感)
3. 单测:枚举↔wire 映射、家族 clamp、降级路径

## 六、风险/注意
- **不能数 token 判档**,唯一真相是网关报错——务必实现降级+记忆不支持档(否则 gemini 类拒档会让发送失败,重蹈 Windows 早期坑)
- effort 是 **per-request**(chat.send 参数),与刚修的 sessionKey 小写化正交,互不影响
- getclawhub 走 LiteLLM,deepseek 关思考需 `deepseek/` 前缀(Windows v0.6.33 踩过)——若做 `.off` 要验证 deepseek 真能关
- 展示思考过程(ThinkingIndicator/history 提取)是**另一功能**,与本"输入力度"正交,Windows 是分开的两块([[windows-show-thinking-feature]] vs 力度档)
