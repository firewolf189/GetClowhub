## ADDED Requirements

### Requirement: Centralized Image Assets

应用所有静态图片资源 SHALL 通过 `OpenClawInstaller/Assets.xcassets` 进行管理，以便享受 App Slicing、暗黑模式 variant、按需加载等系统能力。仓库根目录 SHALL NOT 保留任何 logo / UI 图片副本。

#### Scenario: 根目录无 logo 资源

- **WHEN** 开发者在仓库根目录执行 `ls *.png *.jpg 2>/dev/null`
- **THEN** 输出为空（不存在 `logo1.png`、`logo_black_touxiang.png`、`logo_white_touxiang.png`、`logo_white.png`、`logo_dark.jpg` 等任何 logo 副本）

#### Scenario: Logo 通过 Assets catalog 命名查询访问

- **WHEN** 应用代码需要展示 logo
- **THEN** 使用 SwiftUI `Image("Logo1")` 从 Assets catalog 读取
- **AND** Assets catalog 中存在 `Logo1` image set，包含 light 与 dark 两套 luminosity variant

### Requirement: Asset Catalog Cleanliness

`Logo1.imageset/` 目录 SHALL 只保留被 `Contents.json` 引用的图片文件，未被引用的历史副本 SHALL 被删除以避免随 app bundle 携带死资产。

#### Scenario: imageset 内无死文件

- **WHEN** 开发者执行 `ls OpenClawInstaller/Assets.xcassets/Logo1.imageset/`
- **THEN** 输出仅包含 `Contents.json` 与 `Contents.json` 中 `filename` 字段引用的 PNG 文件
- **AND** 不存在 `logo1.png`、`logo_black_touxiang.png`、`logo_white.png`、`logo_dark.jpg` 等历史死文件

### Requirement: Image Compression Budget

`Logo1.imageset/` 中被 `Contents.json` 引用的图片 SHALL 使用 pngquant（或同等有损压缩）处理，单张文件大小相对原始版本下降 ≥ 60%。视觉差异在常见显示密度下应不被肉眼察觉。

#### Scenario: 压缩后体积达标

- **WHEN** 开发者比较 `Logo1.imageset/` 中各活跃 logo 文件与历史 commit 中的原始版本
- **THEN** 每张图片的字节数 ≤ 原始版本的 40%
- **AND** `Logo1.imageset/` 内全部活跃文件总体积 ≤ 700KB

#### Scenario: 视觉抽检无明显失真

- **WHEN** 在 Retina 显示器上启动应用并观察任何展示 logo 的界面
- **THEN** logo 边缘清晰、无马赛克、无明显色带
