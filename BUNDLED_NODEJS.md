# Node.js 内置集成说明

## 概述

OpenClawInstaller 现在已经集成了 Node.js v24.14.0 (LTS Krypton) 安装包，可以**无需下载**直接安装。

## 优势

### 🚀 大幅提升安装速度
- **之前**: 需要从网络下载 ~50MB Node.js 包，耗时 15-35 秒
- **现在**: 直接使用内置包，**0 秒下载时间**，立即开始安装

### 📦 离线安装支持
- 无需网络连接即可安装 Node.js
- 适合企业内网环境或网络受限场景

### 🎯 用户体验提升
- 安装过程更流畅
- 减少网络问题导致的安装失败
- 提供一致的安装体验

## 技术实现

### 1. 资源文件位置
```
OpenClawInstaller/Resources/
└── node-v24.14.0-darwin-arm64.tar.gz (49MB)
```

### 2. 构建过程
构建脚本 `build_dmg.sh` 会自动：
1. 编译 Swift 应用
2. 将 Resources 目录中的 Node.js 包复制到 app bundle
3. 创建包含所有资源的 DMG 安装包

### 3. 安装逻辑
`NodeInstaller.swift` 的安装流程：

```swift
func installNodeJS() async throws {
    // 1. 优先检查是否有内置的 Node.js 包
    if let bundledPath = getBundledNodePath() {
        // 使用内置包，直接安装 ✅
        try await installNodeFromTarGz(from: bundledPath)
    } else {
        // 2. 如果没有内置包，才从网络下载
        // - 检测用户所在地区
        // - 中国用户使用阿里云镜像
        // - 国际用户使用官方源
        let version = try await getLatestNodeVersion()
        let pkgPath = try await downloadNodePkg(version: version)
        try await installNode(from: pkgPath)
    }

    // 3. 验证安装
    try await verifyInstallation()
}
```

## 文件说明

### Node.js 包信息
- **版本**: v24.14.0 (LTS Krypton)
- **架构**: darwin-arm64 (Apple Silicon)
- **格式**: tar.gz
- **大小**: 约 49MB
- **来源**: 阿里云镜像 (registry.npmmirror.com)

### DMG 大小影响
- **不含 Node.js**: ~5MB
- **含 Node.js**: ~54MB
- **增加**: +49MB

虽然 DMG 文件变大了，但用户下载一次 DMG 后，可以**反复安装**而无需再次下载 Node.js。

## 更新 Node.js 版本

如果需要更新内置的 Node.js 版本：

### 1. 下载新版本
```bash
VERSION="v24.15.0"  # 更新版本号
ARCH="arm64"
curl -L -o "node-${VERSION}-darwin-${ARCH}.tar.gz" \
  "https://registry.npmmirror.com/-/binary/node/${VERSION}/node-${VERSION}-darwin-${ARCH}.tar.gz"
```

### 2. 替换文件
```bash
mv node-${VERSION}-darwin-${ARCH}.tar.gz OpenClawInstaller/Resources/
```

### 3. 更新代码
编辑 `OpenClawInstaller/Services/NodeInstaller.swift`:
```swift
private let bundledNodeVersion = "v24.15.0"  // 更新版本号
```

### 4. 重新构建
```bash
./build_dmg.sh
```

## 降级方案

如果想要移除内置的 Node.js，恢复为在线下载模式：

### 方法 1: 删除资源文件
```bash
rm -rf OpenClawInstaller/Resources/node-*.tar.gz
./build_dmg.sh  # 重新构建
```

应用会自动检测到没有内置包，切换到在线下载模式。

### 方法 2: 构建精简版
创建一个不包含 Node.js 的轻量级版本：
```bash
# 临时重命名 Resources 目录
mv OpenClawInstaller/Resources OpenClawInstaller/Resources.backup
./build_dmg.sh
mv OpenClawInstaller/Resources.backup OpenClawInstaller/Resources
```

## 性能对比

### 完整安装时间对比

| 场景 | 之前 | 现在 | 提升 |
|------|------|------|------|
| 中国用户（阿里云镜像） | ~15 秒下载 + 5 秒安装 | 0 秒下载 + 5 秒安装 | **节省 15 秒** (75%) |
| 国际用户（官方源） | ~35 秒下载 + 5 秒安装 | 0 秒下载 + 5 秒安装 | **节省 35 秒** (87%) |
| 离线环境 | ❌ 无法安装 | ✅ 正常安装 | **从不可用到可用** |

### 下载大小对比

| 方式 | 总下载量 | 说明 |
|------|---------|------|
| 旧方案 | DMG 5MB + Node.js 50MB = **55MB** | 每次安装都需要下载 Node.js |
| 新方案 | DMG 54MB = **54MB** | 一次下载，反复使用 |

实际上新方案的总下载量还**更小**！

## 验证集成

检查构建的 DMG 是否包含 Node.js：

```bash
# 挂载 DMG
hdiutil attach OpenClawInstaller.dmg -readonly -mountpoint /tmp/check

# 检查资源
ls -lh /tmp/check/OpenClawInstaller.app/Contents/Resources/node*.tar.gz

# 卸载
hdiutil detach /tmp/check
```

应该能看到 49MB 的 tar.gz 文件。

## 总结

✅ **优点**:
- 安装速度大幅提升（节省 15-35 秒）
- 支持离线安装
- 减少网络问题导致的失败
- 用户体验更好

⚠️ **权衡**:
- DMG 文件增大 49MB
- 需要手动更新内置的 Node.js 版本

📝 **建议**:
- 对于大多数用户，内置 Node.js 是更好的选择
- 如果需要发布轻量级版本，可以构建两个版本：
  - `OpenClawInstaller-Full.dmg` (含 Node.js)
  - `OpenClawInstaller-Lite.dmg` (不含 Node.js)
