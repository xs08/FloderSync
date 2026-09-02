<p align="center">
  <img src="./docs/assets/flodersync-icon.png" width="152" alt="FloderSync 图标">
</p>

<h1 align="center">FloderSync</h1>

<p align="center">
  一个原生 macOS 菜单栏 Git 自动同步工具。
</p>

<p align="center">
  <a href="./README.md">English</a> · <strong>简体中文</strong>
</p>

FloderSync 使用 Mac 中已经安装和认证的 Git，不保存 Git 密码、访问令牌或 SSH 私钥。

## 功能亮点

- 管理多个已有本地 Git 仓库，并检查远端连接。
- 支持手动同步、每日多个时间点、固定间隔，以及文件变化后五秒去抖同步。
- 使用保守的 `add/commit -> pull --rebase -> push` 同步流程。
- 识别冲突、进行中的 rebase 或 merge、detached HEAD、认证错误和网络故障。
- 同一仓库串行执行、合并重复触发，不同仓库最多并发同步两个。
- 在菜单栏查看状态、快捷同步和添加仓库，并提供历史诊断与登录启动设置。
- 在同步失败或发生冲突时发送通知。
- 无需重启即可切换英文与简体中文。
- 支持跟随系统、浅色和深色主题。

## 开发环境

- macOS 14 或更高版本
- Xcode 16 或更高版本（当前验证环境：Xcode 26.6、Swift 6.3.3）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 系统中可正常执行的 Git

## 构建与测试

```bash
xcodegen generate
xcodebuild build \
  -project obsSync.xcodeproj \
  -scheme obsSync \
  -destination 'platform=macOS'
xcodebuild test \
  -project obsSync.xcodeproj \
  -scheme obsSync \
  -destination 'platform=macOS'
```

也可以打开 `obsSync.xcodeproj` 后直接运行 `obsSync` scheme。FloderSync 使用 `LSUIElement`，启动后只显示在系统菜单栏，不显示 Dock 图标。

## Git 与认证

FloderSync 按顺序查找 `/usr/bin/git`、Apple Silicon Homebrew Git 和 Intel Homebrew Git，并复用现有的 Git、SSH 与 credential helper 配置。

自动同步设置 `GIT_TERMINAL_PROMPT=0`。认证无法非交互完成时，操作会停止并展示错误，而不会索取或保存凭据。设置中的“检查连接”使用 `git ls-remote --heads`，在相同的后台认证环境下验证所选仓库的远端。

## 数据位置

运行配置和最近 100 条同步摘要保存在：

```text
~/Library/Application Support/dev.obssync.app/
```

从 FloderSync 移除仓库时只会删除应用配置，不会删除本地工作区或任何 `.git` 数据。

## 发布前待办

- 将开发期 Bundle Identifier `dev.obssync.app` 替换为最终反向域名标识。
- 配置 Developer ID、Hardened Runtime、公证与更新渠道。
- 在已签名 App 中验证真实 SSH、HTTPS Keychain、登录启动和完整窗口外观矩阵。

产品需求、架构设计、测试方案和实现路线见 [docs/README.md](./docs/README.md)。
