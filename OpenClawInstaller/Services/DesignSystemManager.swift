import Foundation

@MainActor
class DesignSystemManager: ObservableObject {
    static let shared = DesignSystemManager()
    
    @Published var designSystems: [String: String] = [:]
    @Published var allBrands: [String] = []
    @Published var isLoading = false
    
    private init() {
        loadDesignSystems()
    }
    
    /// 从 Bundle 资源加载所有 DESIGN.md 文件
    func loadDesignSystems() {
        isLoading = true
        
        // 获取 DesignSystems 文件夹的路径
        guard let resourcePath = Bundle.main.resourcePath else {
            print("❌ 无法获取 Bundle 资源路径")
            isLoading = false
            return
        }
        
        let designSystemsPath = resourcePath + "/DesignSystems"
        let fileManager = FileManager.default
        
        do {
            // 列出所有品牌目录
            let brands = try fileManager.contentsOfDirectory(atPath: designSystemsPath)
            
            var loadedCount = 0
            for brand in brands {
                let brandPath = designSystemsPath + "/" + brand
                let mdPath = brandPath + "/DESIGN.md"
                
                // 检查是否是目录且包含 DESIGN.md
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: brandPath, isDirectory: &isDir),
                   isDir.boolValue,
                   fileManager.fileExists(atPath: mdPath) {
                    
                    // 读取 DESIGN.md 内容
                    if let content = try? String(contentsOfFile: mdPath, encoding: .utf8) {
                        designSystems[brand] = content
                        loadedCount += 1
                        print("✅ Loaded: \(brand)")
                    }
                }
            }
            
            // 更新品牌列表（排序）
            allBrands = Array(designSystems.keys).sorted()
            
            print("✅ 成功加载 \(loadedCount) 个设计系统")
            print("📋 可用品牌: \(allBrands.joined(separator: ", "))")
            
        } catch {
            print("❌ 加载设计系统失败: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// 获取特定品牌的设计系统
    func getDesignSystem(forBrand brand: String) -> String? {
        return designSystems[brand]
    }
    
    /// 获取所有可用的品牌列表
    func getAllBrands() -> [String] {
        return allBrands
    }
    
    /// 获取品牌的友好名称
    func getBrandDisplayName(_ brand: String) -> String {
        // 将 "elevenLabs" 转为 "ElevenLabs", "cal-com" 转为 "Cal.com"
        let map: [String: String] = [
            "elevenLabs": "ElevenLabs",
            "mistralai": "Mistral AI",
            "opencode-ai": "OpenCode AI",
            "runwayml": "RunwayML",
            "together-ai": "Together AI",
            "voltagent": "VoltAgent",
            "xai": "xAI",
            "posthog": "PostHog",
            "cal-com": "Cal.com",
            "the-verge": "The Verge"
        ]
        
        if let displayName = map[brand] {
            return displayName
        }
        
        // 默认：首字母大写
        return brand.prefix(1).uppercased() + brand.dropFirst()
    }
    
    /// 按类别返回品牌
    func getBrandsByCategory() -> [String: [String]] {
        let categories: [String: [String]] = [
            "AI & LLM Platforms": [
                "claude", "cohere", "elevenLabs", "minimax", "mistralai", "ollama",
                "opencode-ai", "replicate", "runwayml", "together-ai", "voltagent", "xai"
            ],
            "Developer Tools": [
                "cursor", "expo", "lovable", "raycast", "superhuman", "vercel", "warp"
            ],
            "Backend & Database": [
                "clickhouse", "composio", "hashicorp", "mongodb", "posthog", "sanity", "sentry", "supabase"
            ],
            "Productivity & SaaS": [
                "cal-com", "intercom", "linear", "mintlify", "notion", "resend", "zapier"
            ],
            "Design Tools": [
                "airtable", "clay", "figma", "framer", "miro", "webflow"
            ],
            "Fintech & Crypto": [
                "binance", "coinbase", "kraken", "revolut", "stripe", "wise"
            ],
            "E-commerce": [
                "airbnb", "meta", "nike", "shopify"
            ],
            "Media & Tech": [
                "apple", "ibm", "nvidia", "pinterest", "playstation", "spacex", "spotify",
                "the-verge", "uber", "wired", "verge", "dribbble"
            ],
            "Automotive": [
                "bmw", "bugatti", "ferrari", "lamborghini", "renault", "tesla"
            ]
        ]
        
        // 过滤只保留已加载的品牌
        var result: [String: [String]] = [:]
        for (category, brands) in categories {
            let availableBrands = brands.filter { designSystems[$0] != nil }
            if !availableBrands.isEmpty {
                result[category] = availableBrands
            }
        }
        
        return result
    }
}
