# obsSync

obsSync 是一个原生 macOS 菜单栏 Git 自动同步工具。它复用系统 Git 与现有认证，不保存 Git 密码、Token 或 SSH 私钥。

当前 MVP 基线包括：

- 多个已有本地 Git 仓库配置与远端连接检查。
- 手动同步、每日多个时间点、固定间隔、文件变化 5 秒去抖同步。
- `add/commit -> pull --rebase -> push` 的保守同步流程。
- 冲突、进行中的 rebase/merge、detached HEAD、认证和网络错误分类。
- 同仓库串行、重复触发合并、不同仓库最多并发 2。
- 菜单栏状态、快捷同步、独立设置、历史诊断和登录启动。
- 失败/冲突通知，简体中文与英文 String Catalog。

## 开发环境

- macOS 14+
- Xcode 16+（当前验证环境：Xcode 26.6、Swift 6.3.3）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 系统可执行的 Git

## 生成与验证

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

也可以打开 `obsSync.xcodeproj` 后直接运行 `obsSync` scheme。应用使用 `LSUIElement`，启动后只显示在系统菜单栏，不显示 Dock 图标。

## Git 与认证

应用按顺序查找 `/usr/bin/git`、Apple Silicon Homebrew Git 和 Intel Homebrew Git，并使用 Git/SSH/credential helper 的现有用户配置。自动同步设置 `GIT_TERMINAL_PROMPT=0`，认证无法非交互完成时会停止并提示，不会在应用内索取或保存凭据。

设置中的“检查连接”使用 `git ls-remote --heads` 验证所选仓库的远端与当前后台认证环境。

## 数据位置

运行配置和最近 100 条同步摘要保存在：

```text
~/Library/Application Support/dev.obssync.app/
```

移除仓库只删除 obsSync 的配置，不删除本地工作区或 `.git` 数据。

## 发布前待办

- 将开发期 Bundle Identifier `dev.obssync.app` 替换为最终反向域名标识。
- 配置 Developer ID、Hardened Runtime、公证与更新渠道。
- 在已签名 App 中完成真实 SSH、HTTPS Keychain、登录启动和完整窗口视觉矩阵验证。

设计、需求和测试文档见 [docs/README.md](./docs/README.md)。
