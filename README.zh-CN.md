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
- 可让多个仓库复用同一条自动化规则，也可以为单个仓库保留独立配置。
- 支持手动同步、每日多个时间点、固定间隔，以及检测到本地新增 commit 后自动同步。
- 可自动提交检测到的变更，提交信息支持固定文本或 `${user}`、`${email}`、`${time}` 动态变量；提交者留空时沿用仓库或 Git 全局配置。
- 远端整合支持 Rebase 或 Merge；FloderSync 会先获取不可变的远端 revision 再执行整合，默认使用 Rebase。
- 对短暂网络故障和 push 竞态进行严格限次重试；若 FloderSync 本次启动的整合发生冲突，会安全中止整合且保留双方提交，不会中止用户已有的 Git 操作。
- 识别冲突、进行中的 rebase 或 merge、detached HEAD、认证错误和网络故障。
- 同一仓库串行执行、合并重复触发，不同仓库最多并发同步两个。
- 在菜单栏查看状态、快捷同步和添加仓库，并提供历史诊断与登录启动设置。
- 在同步失败或发生冲突时发送通知。
- 无需重启即可切换英文与简体中文。
- 支持跟随系统、浅色和深色主题。
- 可将全部仓库、自动化规则和应用偏好统一导出为带版本的 JSON，并在校验与确认后导入。

## 开发环境

- macOS 14 或更高版本
- Xcode 16 或更高版本（当前验证环境：Xcode 26.6、Swift 6.3.3）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 系统中可正常执行的 Git

## 构建与测试

```bash
xcodegen generate
xcodebuild build \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS'
xcodebuild test \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS'
```

也可以打开 `floderSync.xcodeproj` 后直接运行 `floderSync` scheme。FloderSync 使用 `LSUIElement`，启动后只显示在系统菜单栏，不显示 Dock 图标。

### 安装到 Applications

先退出正在运行的 FloderSync，然后执行：

```bash
./scripts/install-local.sh
```

脚本会执行 Release 构建，将 `FloderSync.app` 安装到 `/Applications`，然后启动安装后的应用。首次安装或替换开发构建后，请在安装后的应用中关闭并重新开启“登录时启动”，确保 macOS 登录项指向 `/Applications/FloderSync.app`，而不是 Xcode 的 DerivedData 目录。

若希望重建后的登录项在不同版本间保持稳定，请在 Xcode 的 FloderSync target 中打开 **Signing & Capabilities**，启用自动签名并选择自己的 Team。

### 无 Developer ID 的测试分发

可以生成供可信测试用户使用的未公证 ZIP：

```bash
./scripts/package-unsigned.sh
```

产物位于 `dist/FloderSync-<版本>-macOS-universal-unsigned.zip`，包含 Apple Silicon 与 Intel 两种架构，并使用 ad-hoc 签名保证 App 在传输后可进行完整性校验。这不是 Developer ID 签名，也无法通过 Apple 公证或 Gatekeeper 的首次下载检查。

用户应先解压并将 `FloderSync.app` 移到 `/Applications`，然后只移除隔离属性并启动：

```bash
xattr -dr com.apple.quarantine /Applications/FloderSync.app
open /Applications/FloderSync.app
```

也可以使用 `xattr -cr /Applications/FloderSync.app`，但它会递归清除所有扩展属性，范围比删除 `com.apple.quarantine` 更大。不要对 `/Applications` 或其他宽泛目录执行这类命令。

由于 ad-hoc 签名的应用身份会随每次构建变化，用户升级后可能需要关闭并重新开启“登录时启动”，系统权限也可能再次询问。要获得无终端命令、可公证且升级身份稳定的正式分发体验，仍然需要 Apple Developer Program 提供的 Developer ID Application 证书。

## Git 与认证

FloderSync 按顺序查找 `/usr/bin/git`、Apple Silicon Homebrew Git 和 Intel Homebrew Git，并复用现有的 Git、SSH 与 credential helper 配置。

自动同步设置 `GIT_TERMINAL_PROMPT=0`。认证无法非交互完成时，操作会停止并展示错误，而不会索取或保存凭据。设置中的“检查连接”使用 `git ls-remote --heads`，在相同的后台认证环境下验证所选仓库的远端。

## 数据位置

运行配置和最近 100 条同步摘要保存在：

```text
~/Library/Application Support/dev.flodersync.app/
```

从 FloderSync 移除仓库时只会删除应用配置，不会删除本地工作区或任何 `.git` 数据。

“设置”页可将仓库、共享自动化规则、通知、语言、外观和登录启动意图导出为 JSON。导入文件通过校验并显示仓库与规则数量后，只有经用户确认才整体替换当前配置；同步历史和 Git 凭据不会进入导出文件。

## 发布前待办

- 将开发期 Bundle Identifier `dev.flodersync.app` 替换为最终反向域名标识。
- 配置 Developer ID、Hardened Runtime、公证与更新渠道。
- 在已签名 App 中验证真实 SSH、HTTPS Keychain、登录启动和完整窗口外观矩阵。

产品需求、架构设计、测试方案和实现路线见 [docs/README.md](./docs/README.md)。
