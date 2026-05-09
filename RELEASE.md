# GetClawHub 客户端发版流程

> 本文档固化客户端发版的完整流程、前置依赖、常见故障和应急处理。
> 维护者：每次发版按本文操作；遇到本文未覆盖的新问题，发版完成后**回填**到这里。

---

## 目录

- [一、发版前一次性配置](#一发版前一次性配置)
- [二、每次发版前置检查](#二每次发版前置检查)
- [三、发版执行](#三发版执行)
- [四、发版后验收](#四发版后验收)
- [五、常见故障与处理](#五常见故障与处理)
- [六、回滚 / 紧急处理](#六回滚--紧急处理)
- [七、维护任务](#七维护任务)
- [附录：架构与设计要点](#附录架构与设计要点)

---

## 一、发版前一次性配置

每台发版机器只需配置一次。新机器接手发版前必须完成全部 6 项。

### 1.1 macOS 与 Xcode

- macOS 13 (Ventura) 或更高
- Xcode 命令行工具：`xcode-select --install`
- 完整 Xcode（用于 `xcodebuild` 与 codesign 工具链）

### 1.2 Apple Developer ID Application 证书

发版机必须能签名为 `Developer ID Application: Zhejiang Hecheng Smart Electric Co., Ltd. (LJQJ5BHW7G)`。

操作：
1. 拿到 `.p12` 证书包（密码已通过安全渠道分发）
2. 双击导入到 **login keychain**（**不要**导入到 System keychain）
3. **关键步骤**：解锁 partition list，否则 codesign 会反复弹密码框：
   ```bash
   security set-key-partition-list \
     -S apple-tool:,apple:,codesign:,productbuild:,security: \
     -s -k <你的-macOS-登录密码> \
     ~/Library/Keychains/login.keychain-db
   ```

验证：
```bash
security find-identity -v -p codesigning
# 应能看到 "Developer ID Application: Zhejiang Hecheng Smart Electric Co., Ltd. (LJQJ5BHW7G)"
```

### 1.3 Apple 公证凭据（notary profile）

配置一次，长期复用：
```bash
xcrun notarytool store-credentials "notary-profile" \
  --apple-id <your-apple-id@email> \
  --team-id LJQJ5BHW7G \
  --password <App-Specific-Password>
```

App Specific Password 在 https://appleid.apple.com 生成，**不是 Apple ID 的登录密码**。

验证：
```bash
xcrun notarytool history --keychain-profile "notary-profile"
# 应能列出最近的提交记录
```

### 1.4 Sparkle EdDSA 私钥

Sparkle 自动更新需要用 ed25519 签 appcast.xml。私钥**只产生一次**，写入 keychain。

⚠️ 这个私钥**绝对不能丢**。app 的 `Info.plist` 里 `SUPublicEDKey` 字段写了配对的公钥；私钥丢了就只能让所有用户重装 app（自动更新会签名校验失败）。

新机器接手发版（从已有发版机迁移）：
```bash
# 旧发版机导出
security find-generic-password -a "ed25519" -s "https://sparkle-project.org" -w
# 输出形如：j9q6SPZP2FOJyixqtNjdqczn74osHY5o7HAXjGfc8EI=

# 新发版机导入
security add-generic-password -a "ed25519" -s "https://sparkle-project.org" \
  -w "j9q6SPZP2FOJyixqtNjdqczn74osHY5o7HAXjGfc8EI="
```

验证（确认本地私钥与 app 内置公钥配对）：
```bash
SIGN_UPDATE=$(find build -path "*/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)
PUB=$($SIGN_UPDATE -p)
EMBEDDED=$(plutil -extract SUPublicEDKey raw OpenClawInstaller/Info.plist)
[ "$PUB" = "$EMBEDDED" ] && echo "✅ 配对" || echo "❌ 不配对"
```

### 1.5 GitHub CLI

```bash
brew install gh
gh auth login    # 选 GitHub.com → HTTPS → Y → Login with web browser
gh auth status   # 应显示 "Logged in to github.com account <你>"
```

需要的权限：`repo` 写权限（用于创建 release、上传资源）。

### 1.6 必需的 bundled tar.gz 资源（**最容易翻车的一项**）

`OpenClawInstaller/Resources/` 下必须有这三个文件，**它们被 .gitignore 屏蔽**（GitHub 单文件 100 MB 限制），新发版机要么从老机器拷贝，要么按 [§ 7.2](#72-重建-openclaw-bundletargz) 重建。

| 文件 | 大小 | 用途 |
|---|---|---|
| `openclaw-bundle.tar.gz` | ~152 MB | openclaw npm 包 + 所有 deps（包含原生模块） |
| `node-v24.14.0-darwin-arm64.tar.gz` | ~49 MB | bundled Node.js（Apple Silicon） |
| `node-v24.14.0-darwin-x64.tar.gz` | ~50 MB | bundled Node.js（Intel） |

```bash
ls -lh OpenClawInstaller/Resources/*.tar.gz
# 三个文件都应存在，每个都 > 1 MB
```

**v1.1.38 的事故就是这三个文件没放对位置导致空壳 DMG 上传，全公司用户安装直接卡死。** `build_dmg.sh` 现在有 preflight 校验缺失会立即 fail，但**仍然推荐每次发版前手动 `ls -lh` 一眼**。

---

## 二、每次发版前置检查

每次开发版前跑一遍：

```bash
# 1. 资源齐全
ls -lh OpenClawInstaller/Resources/*.tar.gz
# 期望：3 个文件，分别约 49M / 50M / 152M

# 2. 工作树干净
git status
# 期望："nothing to commit, working tree clean"，且在 main 分支

# 3. main 与 origin/main 同步
git pull --ff-only

# 4. develop 已合到 main（如果有未发的 fix）
git log --oneline main..develop  # 应为空，否则按 §3.1 合并
```

发版机器同时确认：
```bash
gh auth status                                        # ✅ Logged in
xcrun notarytool history --keychain-profile notary-profile | head -3  # 不报错
security find-identity -v -p codesigning | grep "Developer ID"        # 有匹配
security find-generic-password -a ed25519 -s "https://sparkle-project.org" >/dev/null && echo "✅ EdDSA"
```

---

## 三、发版执行

### 3.1 合并 develop 到 main

正常开发流：fixes 在 `develop`，发版时 fast-forward 合到 `main`。

```bash
# 在 develop 上：commit + push fix
git checkout develop
# ... 改代码、commit、push ...

# 切到 main 合并
git checkout main
git merge develop --ff-only        # 必须 ff-only，禁止 merge commit
git push origin main
```

> ⚠️ 不能在 main 上直接改代码。develop → main 始终保持 ff-only 关系。

### 3.2 跑一键发版脚本

```bash
bash release.sh <新版本号>
# 例如
bash release.sh 1.1.42
```

脚本会问：
1. **`确认发版? (y/n)`** —— 输 `y`
2. **`请输入更新说明`** —— 输入一句话（appcast.xml 和 GitHub Release 都用它），例如：
   > `修复 ABC 模块 XX bug；新增 YY 功能`

之后无人工干预，依次跑 7 步：

| 步 | 内容 | 大致耗时 |
|---|---|---|
| 1/7 | 更新 Info.plist + project.pbxproj 版本号 | <1s |
| 2/7 | 写入 release notes | <1s |
| 3/7 | `build_dmg.sh`：xcodebuild → preflight → 签名 → DMG | 2-5 min |
| 4/7 | Apple 公证（提交 + 轮询，每 30s 查一次，最长 15 min） | **5-15 min** |
| 5/7 | EdDSA 重签 DMG（公证 staple 改了 DMG，必须重签）+ 写 appcast.xml | <5s |
| 6/7 | git commit + push（appcast.xml + 版本号） | <5s |
| 7/7 | 创建 GitHub Release + 上传 DMG（带 3 次重试） | 1-3 min |

预期总耗时：**10-25 分钟**，主要看 Apple 公证排队速度。

### 3.3 同步 develop = main

发版后立即同步：

```bash
git checkout develop
git merge main --ff-only
git push origin develop
git checkout main
```

---

## 四、发版后验收

`release.sh` 跑完后**必须**手动验收，3 项缺一不可：

### 4.1 GitHub Release 状态

```bash
gh release view v<version> --repo firewolf189/GetClowhub --json tagName,assets,isPrerelease,url
```

检查：
- `prerelease: false`（这次是正式版）
- `assets[0].size` 约 `264 MB`（**这是关键** —— 如果只有 15-20 MB，说明 bundle 没进 DMG，参考 [§5.1](#51-dmg-体积异常小15-20-mb-没装-bundle)）
- `url` 在浏览器打开能看到 "Latest" 标记

### 4.2 本地 DMG 完整性

```bash
DMG=GetClawHub.dmg
xcrun stapler validate $DMG          # ✅ The validate action worked!
codesign -v --deep --strict $DMG     # 无输出 = 通过

# 挂载验证 bundle 进去了
hdiutil attach $DMG -readonly -mountpoint /tmp/dmg-check -nobrowse
ls -lh /tmp/dmg-check/*.app/Contents/Resources/*.tar.gz
# 必须看到 3 个文件，分别约 49M / 50M / 152M
hdiutil detach /tmp/dmg-check -force
```

### 4.3 appcast.xml 已推送

```bash
git log -1 docs/appcast.xml         # 应为本次发版 commit
curl -s https://firewolf189.github.io/GetClowhub/appcast.xml | grep -E "(version|enclosure)" | head -5
# 应能看到新版本号（GitHub Pages 缓存最多 5 min 才生效）
```

### 4.4 端到端冒烟（推荐但非必须）

在另一台 mac 上：
1. 下载 GitHub Release 里的 DMG
2. 双击挂载 → 拖到 Applications
3. 启动 → 检查环境检查页（应无红色阻断）
4. 走完 OpenClaw 安装

---

## 五、常见故障与处理

按出现频率排序。

### 5.1 DMG 体积异常小（15-20 MB，没装 bundle）

**症状**：DMG 大小只有 15 MB 左右（正常 ~264 MB），用户装完点"安装 OpenClaw"立即报 `bundleNotFound` 错。

**根因**：`OpenClawInstaller/Resources/` 缺少三个 tar.gz 中的至少一个。

**预防**：`build_dmg.sh` 现在有 preflight，缺文件会 `exit 1`，不会再静默打空壳。

**处理**：
1. 立即把这次坏的 release 改成 pre-release：
   ```bash
   gh release edit v<version> --repo firewolf189/GetClowhub --prerelease \
     --notes "⚠️ 此版本 DMG 缺失 bundled openclaw 资源，请使用下个版本。"
   ```
2. 把三个 tar.gz 补回 `OpenClawInstaller/Resources/`（按 [§7.2](#72-重建-openclaw-bundletargz)）
3. 跳号发新版本（v1.1.38 坏了，v1.1.39 是修补版 —— 不要复用同一个版本号）

### 5.2 Codesign 反复弹 keychain 密码框

**症状**：`build_dmg.sh` 跑到签名步骤，疯狂弹"想要使用 login 钥匙串中私钥..."的弹窗，点 Always Allow 也没用，循环到天荒地老。

**根因**：macOS 10.12+ 的 keychain partition list 与 ACL 是独立机制。`-T /usr/bin/codesign` 设了 ACL 还需要单独解 partition list。

**修复**：
```bash
security set-key-partition-list \
  -S apple-tool:,apple:,codesign:,productbuild:,security: \
  -s -k <你的登录密码> \
  ~/Library/Keychains/login.keychain-db
```

跑完再发版，弹窗消失。

### 5.3 Apple 公证排队特别慢（>15 min）

**症状**：`release.sh` 卡在 `[N/30] 状态: In Progress...`，超过 15 分钟撞 release.sh 的硬超时（30 次 × 30s）。

**根因**：Apple notary 服务排队，跟时段/全球流量有关，无法预测。我们见过最长 ≈ 13 min 才出结果（v1.1.41 那次）。

**处理（如果撞超时）**：
1. 公证 ID 已经提交，不用重交。手动等：
   ```bash
   xcrun notarytool wait <submission-id> --keychain-profile notary-profile --timeout 30m
   xcrun notarytool log  <submission-id> --keychain-profile notary-profile
   ```
2. 通过后手动 staple：
   ```bash
   xcrun stapler staple GetClawHub.dmg
   ```
3. 然后手动跑 release.sh 后续步骤（EdDSA 签名 → push appcast → 创建 release）：
   - 参考 release.sh 的 `[5/7]` `[6/7]` `[7/7]` 段落直接复制命令

**预防**：避开 Apple 工作日深夜（PST）发版高峰；急的时候开两台机并行做公证回退。

### 5.4 hdiutil "Operation not permitted"

**症状**：`build_dmg.sh` 跑到 DMG 制作时报 `hdiutil: create failed - Operation not permitted`。

**根因**：`/Applications/GetClawHub.app` 已经装在本机，hdiutil 的 copy-helper 因 macOS TCC 拒绝写"同名 mounted volume"。

**修复**：build_dmg.sh 已经把 volname 改成 `GetClawHub Installer` 避开冲突。如果还撞到，临时方案：
```bash
sudo rm -rf /Applications/GetClawHub.app   # 卸载已装的
# 然后重跑 build_dmg.sh
```

### 5.5 sign_update 找不到（EdDSA 签名失败）

**症状**：release.sh 第 5 步报 `❌ 未找到 sign_update 工具，无法签名`。

**根因**：Sparkle 通过 SPM 集成，sign_update 在构建产物里 `build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`。如果 SPM 缓存被清了，找不到。

**修复**：
```bash
# 方案 1：重跑 build（重新拉 SPM 包）
xcodebuild -resolvePackageDependencies

# 方案 2：装系统级 sign_update
brew install sparkle    # 提供 /usr/local/bin/sign_update
```

### 5.6 gh release 上传失败

**症状**：第 7 步 `gh release upload` 报 `connection reset` 或 `502`。

**根因**：网络抖动 / GitHub API 临时不稳。

**处理**：release.sh 已带 3 次重试。如果都失败，手动补：
```bash
gh release upload v<version> GetClawHub.dmg --clobber --repo firewolf189/GetClowhub
```

---

## 六、回滚 / 紧急处理

### 6.1 已发布的版本里有严重 bug

发布 GitHub Release **不能撤回**（用户已下载的 DMG 依然能用）。能做的：

1. **立即把当前 release 改成 pre-release** —— GitHub Latest 标记会让位给上一个正常 release：
   ```bash
   gh release edit v<bad-version> --repo firewolf189/GetClowhub --prerelease \
     --notes "⚠️ 此版本存在严重问题（描述），请使用 v<next> 及以上。"
   ```

2. **修复后跳号发新版**（不要复用同一个版本号 —— Sparkle 用 `sparkle:version`/`shortVersionString` 比较，相同版本号不会推送）：
   ```bash
   bash release.sh <bumped-version>
   ```

3. **新 release 的 appcast.xml 推送后**，已装坏版本的用户在下次 Sparkle 检查时（默认每天）会自动收到新版提示。

### 6.2 EdDSA 私钥意外丢失

灾难场景。如果发版机的 keychain 损坏，**且**没有备份私钥：

- 已装在用户机器上的 app 自动更新会**永久失效**（签名校验失败）
- 只能重新生成密钥对、改 `Info.plist` 的 `SUPublicEDKey`、重新发版，**所有用户必须手动下载新 DMG 装一次**

**预防**：把 [§1.4](#14-sparkle-eddsa-私钥) 的私钥**离线备份**到至少两个安全位置（密码管理器 + 加密 U 盘 / HSM）。

---

## 七、维护任务

### 7.1 升级 bundled Node.js 版本

要把 v24.14.0 升到 v25.x.x，按以下顺序改：

```bash
NEW_VERSION="v25.0.0"     # 想升的版本

# 1. 下载新 tarball（macOS 双架构都要）
cd OpenClawInstaller/Resources
for ARCH in arm64 x64; do
  curl -fL -o "node-${NEW_VERSION}-darwin-${ARCH}.tar.gz" \
    "https://registry.npmmirror.com/-/binary/node/${NEW_VERSION}/node-${NEW_VERSION}-darwin-${ARCH}.tar.gz"
done

# 2. 删旧版本
rm node-v24.14.0-darwin-*.tar.gz

# 3. 改 Swift 代码里的版本字符串
# OpenClawInstaller/Services/NodeInstaller.swift:47
#     private let bundledNodeVersion = "v25.0.0"

# 4. 同步改文案（提到 v24.14.0 的地方）
grep -rn "v24.14.0" OpenClawInstaller --include="*.swift"
# EnvironmentCheckView.swift, DiagnosticService.swift 至少有 2 处硬编码

# 5. 改 build_dmg.sh preflight 里期望的文件名
grep -n "node-v24" build_dmg.sh

# 6. 改本文档 §1.6 的版本号
```

升完先在 dev 机本地装一遍，启动 OpenClaw 跑通业务再发版。

### 7.2 重建 openclaw-bundle.tar.gz

如果 `openclaw-bundle.tar.gz` 丢了或要更新到最新 openclaw npm 包：

```bash
# 1. 全局装 openclaw 最新版（或指定版本）
npm install -g openclaw                # 最新
# 或：npm install -g openclaw@2026.3.2

# 2. 验证装在哪
ls ~/.npm-global/lib/node_modules/openclaw/openclaw.mjs   # 应存在

# 3. 重打 bundle
cd ~/.npm-global
tar -czf /tmp/openclaw-bundle.tar.gz \
  bin/openclaw \
  lib/node_modules/openclaw

# 4. 验证 bundle 内容
tar -tzf /tmp/openclaw-bundle.tar.gz | head -5
# 应看到 bin/openclaw, lib/node_modules/openclaw/...

# 5. 替换到仓库
mv /tmp/openclaw-bundle.tar.gz <repo>/OpenClawInstaller/Resources/

# 6. 体积 sanity check
ls -lh <repo>/OpenClawInstaller/Resources/openclaw-bundle.tar.gz
# 应在 100-200 MB 范围
```

### 7.3 查看历史版本与变化

```bash
gh release list --repo firewolf189/GetClowhub --limit 20

# 对比两个版本的代码差异
git log --oneline v1.1.40..v1.1.41
```

---

## 附录：架构与设计要点

### A.1 三个 tar.gz 的来源与用途

| 文件 | 内置在哪 | 安装时干什么 | 运行时谁用 |
|---|---|---|---|
| `node-v24.14.0-darwin-arm64.tar.gz` | app bundle Resources/ | 解压到 `~/.openclaw/node/` | bundled Node 进程 |
| `node-v24.14.0-darwin-x64.tar.gz` | 同上 | 同上（Intel 架构） | 同上 |
| `openclaw-bundle.tar.gz` | 同上 | 解压到 `~/.npm-global/` | openclaw CLI 进程 |

⚠️ **`installDir = ~/.npm-global` 是历史决定**，听起来像系统级 npm 全局目录，但其实是用户家目录下的（不是 `/usr/local/lib/node_modules`），不需要 sudo。

### A.2 Sparkle 自动更新链路

```
[发版]
  release.sh → DMG → EdDSA 签名 → 写 docs/appcast.xml → push to main
                                                              ↓
                                              GitHub Pages 服务化 appcast.xml
                                                              ↓
[用户端]
  GetClawHub 启动 → Sparkle 拉 https://firewolf189.github.io/GetClowhub/appcast.xml
                  → 比较 sparkle:shortVersionString 与本地
                  → 新版本 → 弹窗 "可用更新"
                  → 用户点 Install Update → 下载 DMG → EdDSA 校验签名
                  → 校验通过 → 替换 .app → 重启
```

发版机的 EdDSA 私钥与 app 内置的 `SUPublicEDKey` **必须永远配对**，否则 Sparkle 校验失败。

### A.3 发版相关文件位置

```
GetClowhub/
├── release.sh                  # 一键发版入口
├── build_dmg.sh                # 构建 + 签名 + 打包 DMG（被 release.sh 调用）
├── notarize_dmg.sh             # Apple 公证（被 release.sh 调用）
├── docs/
│   └── appcast.xml             # Sparkle 用的版本清单（GitHub Pages 服务化）
├── OpenClawInstaller/
│   ├── Info.plist              # 版本号 + SUPublicEDKey
│   ├── Resources/              # bundled tar.gz（gitignored）
│   └── Services/
│       ├── NodeInstaller.swift # bundledNodeVersion 常量
│       └── OpenClawInstaller.swift
├── BUNDLED_NODEJS.md           # bundled Node 子模块详细说明
└── RELEASE.md                  # 本文档
```

---

## 修订记录

记录本文档自身的演进，便于追溯流程变更。

| 日期 | 版本 | 更新 |
|---|---|---|
| 2026-05-09 | 1.0 | 初版。从 v1.1.38 → v1.1.41 的连续 4 次发版经验固化。 |
