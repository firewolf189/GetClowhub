审核规范：

1：logo规范：图一的logo（带英文slogan）只能使用在英文为文案的设计中，图二是英文和其他语言做设计时都可以使用的，图片中除了公司的logo，不允许出现其他任何logo，例如：caterpillar，john deere等。

2：文案规范：
（1）审核文案中是否出现文案和语法错误，如果出现对应错误需要提出问题所在；
（2）涉及第三方品牌（如 Caterpillar、John Deere、Toyota、Suzuki 等）时，严禁使用第三方品牌名作为句子主语，也严禁使用品牌所有格（如 Suzuki's）。如果发现此类表达，算文案错误，需要指出并给出合规改法；
（3）涉及第三方品牌时，必须先进行场景配对，再根据对应场景审核品牌表达是否合规，不能只因为出现品牌名就直接判错。场景配对顺序如下：

场景 A：描述售卖的替换件（适配性描述）
当主语是我们销售的零件，需要表达它适用于某个品牌时，使用以下三种标准表达之一：
- [零件名] for [品牌名]
- [零件名] fit/fits [品牌名]
- [零件名] Compatible with [品牌名]
示例：
- Water Pump for Caterpillar
- Fuel Filter fits John Deere / Fuel Filters fit John Deere
- Starter Motor Compatible with Kubota

场景 B：描述技术应用、故障诊断或系统构造
当文案涉及特定的技术环境、系统说明或设备部位时，使用以下句式：
- on/in [品牌名] equipment / machines / models
- In [品牌名] Applications
示例：
- 5 Symptoms of a Bad Fan Clutch on Toyota Models
- Understanding Common Fault Codes in John Deere Systems
- Solving Overheating Issues In Caterpillar Applications

场景 C：横向评测与选购对比
允许直接使用 [品牌 A] VS [品牌 B] 格式，推荐使用：[品牌 A] VS [品牌 B] + [设备类型]。
示例：
- Kioti vs Kubota Tractors: Which Should I Choose?

品牌技术对象说明例外：
当文案是在解释某品牌设备自身的故障灯、故障代码、仪表盘、系统结构、操作说明或部件位置时，品牌名属于必要的技术对象限定词，原则上不视为侵权或文案错误。例如 “Mahindra Tractor Dashboard Warning Lights and Meanings” 属于讲解 Mahindra 设备仪表盘故障灯含义，不需要改成 For Mahindra。该类内容仍需检查是否存在第三方 logo、品牌所有格、官方/原厂/授权暗示，或把第三方品牌误导为我们销售产品来源方的表达。

多语言文案审核补充：
当图片文案不是英文时，先理解或翻译文案语义，再按同一套品牌场景规则判断，不要求必须逐字出现英文 for / fits / Compatible with / on/in 等词。
- 场景 A 中，只要语义明确表达“该零件适用于/兼容/匹配某品牌”，即可视为符合适配性描述。例如中文“适用于 Caterpillar 的水泵”，或其他语言中等同于 for / compatible with / fits 的表达。
- 场景 B 中，只要品牌名用于限定被讲解的设备、机型、系统或应用场景，即可接受。例如语义等同于“在某品牌设备上 / 某品牌机型中 / 某品牌系统中的故障说明”的表达。
- 场景 C 中，允许任何语言中语义等同于“品牌 A vs 品牌 B / 品牌 A 与品牌 B 对比”的表达。
- 所有语言中均禁止使用第三方品牌所有格或所属关系来暗示来源，例如 “Suzuki's”、中文“铃木的启动马达”等；禁止暗示官方、原厂、授权、正品来源，例如 Official、Genuine、OEM by [品牌]、官方、原厂、授权等，除非确有授权依据；禁止将第三方品牌作为我们销售产品的来源方或主语。
- 若无法确认外语文案语义或品牌关系，应标记为“需人工复核”，不要直接判合格。

3：市场雷区：是否出现明显的符合产品目标客户雷区的元素（例如不符合活动时节的元素，南北半球真实气候与图片展示冲突等）

导出格式要求：

1. 单批审核时，Markdown 文件固定写到 `review-output/stats/YYYY-MM-DD.md`，只展示不合格、需人工复核、审核错误的图片；合格图片不在 Markdown 明细中展示。
2. 每批必须同时保留 `review_results.json`，JSON 中需要包含全部图片，包括合格图片，供后续统计合格率使用。
3. 单批 Markdown 的问题明细按照下面格式输出：

人名
图片：图片名字
结果：不合格 / 需人工复核 / 审核错误
问题：
1. Logo规范：错误元素和证据
   修改方案：修改方案

4. 当需要统计某段时间每个人的合格率时，只从 `review_results.json` 汇总，不从 Markdown 反解析。需人工复核不算合格。
