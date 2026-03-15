import Foundation

// MARK: - FAQ Data Model

struct FAQItem {
    let keywords: [String]
    let question: String
    let answerZh: String
    let answerEn: String
}

// MARK: - FAQ Matching

struct HelpFAQMatcher {
    static let shared = HelpFAQMatcher()

    /// Returns the best matching FAQ item, or nil if no keyword matches.
    func match(_ input: String) -> FAQItem? {
        let lower = input.lowercased()
        var bestMatch: FAQItem?
        var bestScore = 0

        for item in Self.faqItems {
            let score = item.keywords.reduce(0) { count, kw in
                lower.contains(kw) ? count + 1 : count
            }
            if score > bestScore {
                bestScore = score
                bestMatch = item
            }
        }

        return bestScore > 0 ? bestMatch : nil
    }

    /// Detect whether the input contains Chinese characters.
    func isChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    /// Get the answer in the appropriate language.
    func answer(for item: FAQItem, input: String) -> String {
        isChinese(input) ? item.answerZh : item.answerEn
    }

    // MARK: - Fallback Messages

    static let fallbackZh = "抱歉，离线模式下无法回答此问题。请先到 Status 页面启动服务后重试，或直接在 Chat 页面向 AI 提问。"
    static let fallbackEn = "Sorry, this question cannot be answered in offline mode. Please start the service on the Status page and try again, or ask your AI assistant on the Chat page."

    func fallbackAnswer(for input: String) -> String {
        isChinese(input) ? Self.fallbackZh : Self.fallbackEn
    }

    // MARK: - Preset FAQ Items

    static let faqItems: [FAQItem] = [
        FAQItem(
            keywords: ["启动", "start", "服务", "service", "运行", "run", "启动不了"],
            question: "服务启动不了怎么办？",
            answerZh: """
            请按以下步骤排查：
            1. 打开 Status 页面，查看错误信息
            2. 打开 Logs 页面，搜索 "error" 查找报错原因
            3. 检查端口是否被其他程序占用（默认 18789）
            4. 点击侧边栏 Tools 区域的 Doctor 按钮，生成诊断报告
            5. 尝试点击 Restart 重启服务
            """,
            answerEn: """
            Please follow these steps:
            1. Open the Status page and check for error messages
            2. Open the Logs page and search for "error" to find the cause
            3. Check if the port (default 18789) is occupied by another program
            4. Click the Doctor button in the sidebar Tools section for diagnostics
            5. Try clicking Restart to restart the service
            """
        ),
        FAQItem(
            keywords: ["停止", "stop", "关闭", "关"],
            question: "如何停止服务？",
            answerZh: "进入 Status 页面，点击红色的 Stop 按钮即可停止服务。",
            answerEn: "Go to the Status page and click the red Stop button to stop the service."
        ),
        FAQItem(
            keywords: ["重启", "restart"],
            question: "如何重启服务？",
            answerZh: "进入 Status 页面，点击 Restart 按钮。修改配置后也可以在 Configuration 页面点击 Save & Restart 一步完成。",
            answerEn: "Go to the Status page and click the Restart button. After changing configuration, you can also use Save & Restart on the Configuration page."
        ),
        FAQItem(
            keywords: ["模型", "model", "配置", "config", "provider", "供应商"],
            question: "如何配置模型？",
            answerZh: """
            1. 进入 Configuration 页面
            2. 在 Provider 下拉框选择模型供应商（如 OpenAI、Claude）
            3. 填写 API Base URL（一般自动填充）
            4. 填写 API Key
            5. 在模型列表中添加需要的模型
            6. 点击 Save & Restart 保存并重启服务
            """,
            answerEn: """
            1. Go to the Configuration page
            2. Select a provider from the Provider dropdown (e.g., OpenAI, Claude)
            3. Fill in the API Base URL (usually auto-filled)
            4. Enter your API Key
            5. Add the models you need to the model list
            6. Click Save & Restart to save and restart the service
            """
        ),
        FAQItem(
            keywords: ["api", "key", "密钥", "apikey"],
            question: "如何设置 API Key？",
            answerZh: "进入 Configuration 页面，在 API Key 输入框中填写你的密钥。点击眼睛图标可以查看/隐藏内容。填写后点击 Save 保存。",
            answerEn: "Go to the Configuration page and enter your key in the API Key field. Click the eye icon to show/hide the value. Click Save when done."
        ),
        FAQItem(
            keywords: ["端口", "port"],
            question: "如何修改端口？",
            answerZh: "进入 Configuration 页面，修改 Port 字段（默认 18789，范围 1-65535），然后点击 Save & Restart。",
            answerEn: "Go to the Configuration page, change the Port field (default 18789, range 1-65535), then click Save & Restart."
        ),
        FAQItem(
            keywords: ["agent", "代理", "子代理", "创建", "新建"],
            question: "如何创建子代理？",
            answerZh: """
            1. 进入 Multi-Agent 页面
            2. 点击 New Agent 按钮
            3. 填写 Agent ID（英文小写 + 数字 + 连字符）
            4. 可选填写显示名称和专用模型
            5. 创建完成后，可在 Chat 页面的下拉菜单切换到该 AI 对话
            """,
            answerEn: """
            1. Go to the Multi-Agent page
            2. Click the New Agent button
            3. Enter an Agent ID (lowercase letters, numbers, hyphens)
            4. Optionally set a display name and dedicated model
            5. Once created, switch to this AI in the Chat page dropdown
            """
        ),
        FAQItem(
            keywords: ["persona", "人设", "性格", "identity", "编辑"],
            question: "如何编辑 AI 性格？",
            answerZh: """
            进入 Persona 页面，展开你想编辑的文件：
            - IDENTITY：定义名字、头像、物种
            - SOUL：定义性格、行为风格
            - USER：告诉 AI 你的偏好
            - MEMORY：AI 的长期记忆
            点击铅笔图标进入编辑，修改后点击 Save 保存。
            """,
            answerEn: """
            Go to the Persona page and expand the file you want to edit:
            - IDENTITY: Define name, avatar, species
            - SOUL: Define personality and behavior
            - USER: Tell the AI your preferences
            - MEMORY: AI's long-term memory
            Click the pencil icon to edit, then click Save when done.
            """
        ),
        FAQItem(
            keywords: ["定时", "cron", "自动", "任务", "schedule", "计划"],
            question: "如何创建定时任务？",
            answerZh: """
            1. 进入 Cron 页面
            2. 点击 Add Job 按钮
            3. 填写任务名称和 Cron 表达式（如 "0 9 * * *" = 每天 9:00）
            4. 选择时区和执行的 AI
            5. 选择会话模式（Isolated 推荐）
            6. 填写要执行的指令内容
            7. 点击创建
            """,
            answerEn: """
            1. Go to the Cron page
            2. Click the Add Job button
            3. Enter a name and cron expression (e.g., "0 9 * * *" = daily at 9:00)
            4. Select timezone and which AI to use
            5. Choose session mode (Isolated recommended)
            6. Enter the instruction to execute
            7. Click Create
            """
        ),
        FAQItem(
            keywords: ["技能", "skill", "安装", "install"],
            question: "如何安装技能？",
            answerZh: "进入 Skills 页面，点击 Install 按钮，粘贴安装命令（格式：npx skills add <url> --skill <name>），等待安装完成。也可以点击 Market 按钮浏览技能市场。",
            answerEn: "Go to the Skills page, click Install, paste the install command (format: npx skills add <url> --skill <name>), and wait for completion. You can also click Market to browse available skills."
        ),
        FAQItem(
            keywords: ["渠道", "channel", "telegram", "discord", "连接", "平台", "slack", "微信", "wechat"],
            question: "如何连接聊天平台？",
            answerZh: "进入 Channels 页面，点击 Add Channel，选择平台类型（如 Telegram），填入 Bot Token 或 API Key，点击添加。添加后查看状态灯：绿色表示连接正常。",
            answerEn: "Go to the Channels page, click Add Channel, select the platform (e.g., Telegram), enter the Bot Token or API Key, and click Add. Check the status indicator: green means connected."
        ),
        FAQItem(
            keywords: ["插件", "plugin", "启用", "enable", "禁用", "disable"],
            question: "如何启用/禁用插件？",
            answerZh: "进入 Plugins 页面，每个插件右侧有 Enable 或 Disable 按钮，点击即可切换状态。绿色勾号表示已加载，灰色减号表示已禁用。",
            answerEn: "Go to the Plugins page. Each plugin has an Enable or Disable button on the right. Click to toggle. Green checkmark means loaded, gray minus means disabled."
        ),
        FAQItem(
            keywords: ["日志", "log", "错误", "error", "查看"],
            question: "如何查看日志？",
            answerZh: "进入 Logs 页面，可以搜索关键字过滤日志，打开 Auto 开关自动刷新。日志颜色：红色 = 错误，橙色 = 警告，蓝色 = 信息。点击 Export 可导出为 .txt 文件。",
            answerEn: "Go to the Logs page. Search by keyword to filter, toggle Auto for live refresh. Log colors: red = error, orange = warning, blue = info. Click Export to save as .txt file."
        ),
        FAQItem(
            keywords: ["更新", "update", "版本", "version", "升级"],
            question: "如何更新应用？",
            answerZh: "应用每天自动检查更新。侧边栏底部如果显示绿色 Update 字样，点击即可下载安装。也可以点击版本号旁的刷新按钮手动检查。",
            answerEn: "The app checks for updates daily. If the sidebar bottom shows a green Update link, click to download and install. You can also click the refresh button next to the version number to check manually."
        ),
        FAQItem(
            keywords: ["登录", "login", "认证", "auth", "登入"],
            question: "如何登录？",
            answerZh: "点击侧边栏顶部的 Log In 按钮，浏览器会自动打开登录页面。完成登录后回到 GetClawHub，应用会自动跳转到主界面。",
            answerEn: "Click the Log In button at the top of the sidebar. Your browser will open the login page automatically. After logging in, return to GetClawHub and it will redirect to the main interface."
        ),
        FAQItem(
            keywords: ["诊断", "doctor", "检查", "排查"],
            question: "如何运行系统诊断？",
            answerZh: "点击侧边栏 Tools 区域的 Doctor 按钮，会弹出一份完整的诊断报告，包含系统信息、服务状态、配置情况。可以复制报告内容发给技术支持。",
            answerEn: "Click the Doctor button in the sidebar Tools section. A full diagnostic report will appear showing system info, service status, and configuration. You can copy the report for technical support."
        ),
        FAQItem(
            keywords: ["斜杠", "命令", "slash", "command", "/"],
            question: "如何使用斜杠命令？",
            answerZh: "在 Chat 输入框中输入 /，会弹出命令补全列表。用 ↑↓ 键选择，按 Enter 或 Tab 确认。常用命令：/help 查看帮助、/new 重置会话、/agents 查看 AI 列表。",
            answerEn: "Type / in the Chat input box to open the command list. Use ↑↓ to navigate, Enter or Tab to confirm. Common commands: /help for help, /new to reset session, /agents to list AIs."
        ),
        FAQItem(
            keywords: ["历史", "history", "记录", "之前", "上一条"],
            question: "如何查看历史消息？",
            answerZh: "在 Chat 输入框为空时，按 ↑ 键可以逐条查看之前发过的消息，按 ↓ 键反向翻阅。历史最多保留 20 条，关闭应用后依然保留。",
            answerEn: "When the Chat input is empty, press ↑ to browse previous messages, ↓ to go forward. Up to 20 messages are saved and persist across app restarts."
        ),
        FAQItem(
            keywords: ["语言", "language", "切换", "中文", "英文", "chinese", "english"],
            question: "如何切换界面语言？",
            answerZh: "点击侧边栏顶部的地球图标，在下拉菜单中选择想要的语言。支持中文、英文、日文等 26 种语言。选择 System 跟随系统语言。",
            answerEn: "Click the globe icon at the top of the sidebar and select your preferred language from the dropdown. 26 languages are supported. Select System to follow your OS language."
        ),
        FAQItem(
            keywords: ["主题", "theme", "深色", "dark", "浅色", "light", "外观", "暗黑"],
            question: "如何切换外观模式？",
            answerZh: "点击侧边栏底部的太阳/月亮图标，可在浅色和深色模式之间切换。",
            answerEn: "Click the sun/moon icon at the bottom of the sidebar to toggle between light and dark mode."
        ),
    ]
}
