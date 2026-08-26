# GetClawHub Mac 客户端 · 更新说明（v1.1.89）

一句话：**打开新版即可把本机 OpenClaw 安全升到内置核心；旧配置先迁移，过不了门禁就不停现网网关。**

---

## 这一版改的是什么

升级 GetClawHub 时，客户端会把本机 OpenClaw 升到 App 内置的 `2026.7.1-2`。旧版会先停网关再换核，遇到遗留的 `update-check.json`、缺编译产物的插件、或 LaunchAgent 已加载未运行，就会停在 Stop。

这一版把「升级优化 / 旧配置迁移 / 启动拉起」做进客户端：

1. **停网关之前**先可逆迁移已知阻断（冲突的 `update-check.json`、TypeScript-only 插件、陈旧插件项、钉钉多余键、错误的旧 CLI 入口）。
2. 用暂存的新核心做门禁。迁移级失败或预检跑不起来，**禁止换核**，现网继续跑。
3. 门禁通过后才换核。Node 改为全新解压再原子替换，避免覆盖旧 `node_modules`。
4. 「启动服务」与升级后拉起共用：已在服务则不重装；`already loaded` 时 `restart` / kickstart。

用户只需安装或更新 GetClawHub。正式包仍须带齐 `openclaw-bundle.tar.gz` 和两个 Node 压缩包。

---

## 升级方式

菜单栏 **GetClawHub → 检查更新**，或安装新的 DMG。
