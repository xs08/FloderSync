# FloderSync 架构设计（草案）

状态：MVP 架构基线已确认（2026-09-02）

## 1. 技术方向

- 原生 macOS 应用：Swift + SwiftUI，必要时以少量 AppKit 适配平台能力。
- 菜单栏：SwiftUI `MenuBarExtra` 的 window 样式，用于状态与快捷操作。
- 设置窗口：AppKit `NSWindowController` 在首帧前配置窗口 chrome，再用 `NSHostingController` 承载 SwiftUI 内容。
- Git：通过 Foundation `Process` 调用系统 Git CLI，不链接或实现 Git 协议。
- 登录启动：macOS 13+ 的 `SMAppService`；MVP 注册主应用为 login item，不引入特权 helper。
- Commit 监听：FSEvents 只用于唤醒 Git 引用检查，实际触发由 `HEAD` revision 变化确认。
- 并发：Swift Concurrency；每个仓库由 actor 串行化，调度器只发出意图。
- 发布：默认按 Developer ID 签名、公证、直接分发设计。若要求 Mac App Store，需要重新评估 sandbox、目录授权和 Git/SSH 访问。

建议最低版本为 macOS 14，既保留合理覆盖面，也能使用成熟的 SwiftUI scene 能力。最新系统视觉通过系统组件自然获得；仅在有明确交互收益时使用 macOS 26 专属 API，并用 availability gate 降级。

## 2. 分层与职责

```text
Presentation
  MenuBar / Settings / History / Diagnostics
          ↓ user intents + view state
Application
  ProfileService / SyncCoordinator / Scheduler / StatusProjection
          ↓ ports
Domain
  SyncProfile / SyncPolicy / SyncRun / SyncStateMachine / DomainErrors
          ↑ adapters
Infrastructure
  ProcessGitClient / GitMetadataWatcher / ConfigStore / HistoryStore
  LoginItemService / NotificationService / Clock / OSLog
```

### Presentation

只负责展示、输入校验和用户意图，不直接拼接 Git 命令、读写配置或管理计时器。

### Application

- `ProfileService`：配置的增删改查、预检与启停。
- `SyncCoordinator`：合并触发、控制并发、创建 run、驱动同步用例。
- `Scheduler`：把时间、间隔、新增 commit、唤醒补偿统一转换为 `SyncTrigger`。
- `StatusProjection`：把领域状态投影为菜单栏和设置窗口可消费的只读状态。

### Domain

- 不依赖 SwiftUI、Foundation `Process`、FSEvents 或持久化框架。
- 定义同步状态机、策略值对象、标准化错误和安全不变量。
- 通过协议描述 Git、时钟、配置、历史等端口。

### Infrastructure

- `ProcessGitClient`：安全构造参数数组、设置工作目录与非交互环境、捕获 stdout/stderr、超时与退出码；取消/超时使用 TERM 后有限等待并升级到 KILL；不通过 shell 拼接命令。
- `GitMetadataWatcher`：监听 `HEAD`、当前分支 ref 与 reflog 事件，去抖后比较 revision；普通工作区文件变化不会触发。
- `ConfigStore`：在 Application Support 中原子保存版本化配置；不保存认证秘密。
- `HistoryStore`：保存有限数量的同步摘要和脱敏步骤日志。
- `LoginItemService`：注册、注销并读取 `SMAppService` 状态。
- `NotificationService`：只根据用户偏好发送成功、失败或冲突通知。

## 3. 核心数据模型

```text
SyncProfile
  id, name, localPath, remoteName, branchPolicy,
  customAutomationConfiguration,
  automationRuleID?, isEnabled

AutomationRule
  id, name, configuration

AutomationConfiguration
  policies[], integrationStrategy(rebase | merge), automaticCommit

AutomaticCommitConfiguration
  isEnabled, authorName?, authorEmail?, messageTemplate

SyncPolicy
  daily(times) | interval(duration) | newCommits

SyncTrigger
  manual | scheduled | interval | newCommit | wakeCatchUp

SyncRun
  id, profileID, trigger, startedAt, finishedAt,
  state, steps[], errorCategory?

SyncState
  queued → validating → staging → committing → pulling
  → pushing → succeeded
  ↘ skipped / cancelled / failed / needsUserAction
```

路径持久化不能只保存字符串。若启用 App Sandbox，需要 security-scoped bookmark；即使直接分发，也建议把路径标识与可访问性恢复抽象在 `FolderAccessStore` 后，避免未来迁移牵动领域层。

## 4. 同步用例与并发

```text
Trigger Source ──→ Scheduler ──→ SyncCoordinator
                                      │
                         dedupe/coalesce per profile
                                      │
                               Repository Actor
                                      │
                     Sync Use Case ──→ GitClient ──→ git
                                      │
                              History + UI state
```

约束：

- 同一 profile 永远最多一个活跃 run。
- 运行期间的新触发被合并为一个 pending run，避免事件风暴。
- 不同仓库可以有限并发；MVP 默认全局并发 2，后续可配置。
- 应用退出时不强杀正在写入 Git 的子进程；先请求取消并等待安全边界，超时后明确记录中止状态。
- Git 元数据事件只表示“revision 可能变化”；比较当前 `HEAD` 与已记录 revision 后才生成新增 commit 触发。
- 同步协调器开始处理仓库前暂停其 commit 检测，任务完全空闲后读取最新 `HEAD` 作为新基线，再恢复检测，避免自动 commit、pull、rebase 或 merge 造成重触发。

## 5. Git 适配器边界

### 可执行文件

GUI 应用通常不继承交互式 shell 的环境。架构中应显式解析 Git：

1. 优先使用用户已验证的 Git 路径。
2. 检查常见位置与受控的 PATH，不执行 shell profile。
3. 设置页提供“Git 环境检查”，展示版本、路径和认证预检结果。

### 认证

- 不读取或保存凭据，只允许 Git、SSH、credential helper 使用用户现有配置。
- 自动同步设置 `GIT_TERMINAL_PROMPT=0`，避免后台挂起等待输入。
- 对 HTTPS credential helper、macOS Keychain、标准 SSH 配置提供诊断。
- 自定义 ssh-agent 依赖 `SSH_AUTH_SOCK`，登录启动环境可能不可用；应允许用户配置安全的环境覆盖，或明确要求使用 Keychain/稳定 agent。具体产品方案待原型验证。

### 命令安全

- 始终使用参数数组调用 `Process`，不使用 `/bin/sh -c`。
- 远端 URL、stderr 和 trace 日志经过统一脱敏器。
- 所有命令有超时、退出码解释和可取消性。
- 只允许白名单 Git 操作；MVP 不暴露任意命令输入。

## 6. 配置与迁移

- 配置文件采用带 `schemaVersion` 的 Codable JSON，使用临时文件 + 原子替换。
- 历史记录可以先采用 JSON Lines/轻量 store；若查询需求扩大，再切换 SQLite。领域层不感知存储类型。
- 写入前验证配置，保留最近一个可恢复备份。
- 仓库移除只删除应用配置与历史引用，不删除本地目录或 `.git` 数据。

## 7. UI 信息架构

### 菜单栏弹窗

- 顶部：全局状态、正在同步数量、`同步全部` 主操作。
- 中部：仓库列表；每行显示名称、状态、最近成功时间与单仓库同步按钮。
- 底部：打开设置、快速添加仓库；空状态不重复展示设置按钮。
- 仅展示高频信息，不把完整配置表单塞入弹窗。

### 设置窗口

设置窗口使用固定宽度、不可折叠的一级侧栏，避免系统分栏与仓库详情分栏嵌套后互相挤压。一级侧栏结构：

- 仓库
- 自动化
- 历史与诊断
- 底部固定通用与退出

仓库模块内部采用主从布局：左侧同步任务列表及底部新增/删除操作，右侧展示详情。状态不能只依赖颜色，必须同时使用 SF Symbol、文字和可访问性标签。

仓库为空时不构造任务列表列，直接展示带“添加仓库”操作的空状态。文件选择器由应用级单例协调器异步管理；打开设置、切换侧边栏模块或再次发起选择前先取消旧面板，避免模态面板锁住其他操作。

添加仓库的只读预检先调用 `rev-parse` 验证工作区、当前分支与远端，再用本地 `HEAD` 和 `ls-remote` 返回的远端分支哈希判断是否同步。哈希不一致只触发确认，不自动修改仓库；仅在用户确认后进入正常同步引擎。

语言偏好存入 `UserDefaults`。视图注入对应 `Locale`，动态字符串查找器按用户选择加载 `en.lproj`、`zh-Hans.lproj` 或系统首选资源，因此不需要重启应用。

实际窗口验证表明，SwiftUI 管理的 `Settings` 场景会先创建并显示原生 titlebar backing view，再由嵌入内容中的 `NSViewRepresentable` 异步修改 `NSWindow`；这会保留顶部安全区，并在强制主题切换时产生独立的标题栏首帧。设置窗口因此改由 `SettingsWindowController` 在展示前同步创建：初始化时一次性组合 `.titled` 与 `.fullSizeContentView`，关闭标题和标题栏背景、移除 toolbar，再挂载 `NSHostingController`。`.titled` 只用于保留标准窗口按钮，SwiftUI 内容负责绘制完整窗口背景和 28pt continuous 外观裁剪。应用菜单通过 `.appSettings` command group 保留 `⌘,` 入口。

侧边栏不使用 `List`，改为固定宽度的语义按钮栈，以精确控制圆角选中态，并避免系统分栏背景侵入内容区。侧边栏以 `FocusState` 作为键盘焦点来源：焦点移动到导航项时写回当前模块，按钮关闭系统 focus effect，使鼠标与 Tab 始终共享同一个蓝色填充选中态。主题偏好使用版本稳定的 `AppTheme` 枚举和 `UserDefaults` 持久化，在菜单栏和设置窗口的 SwiftUI 根视图注入对应 `preferredColorScheme`。

UI 以 Apple Human Interface Guidelines、系统字体、语义色、系统间距和原生控件为准；支持键盘快捷键（至少 `⌘,` 设置、手动同步命令）和所有关键状态（空、加载、同步中、失败、权限不足、路径失效）。

上述方案的问题根因、取舍、实现落点与回归约束统一记录在[UI、窗口与故障复盘设计](./06-ui-window-and-troubleshooting-design.md)，后续修改窗口或交互时必须同步检查该基线。

菜单栏品牌符号存放于 Asset Catalog，源文件为保留矢量数据和原始色彩的 SVG。SVG 使用深蓝到亮青的横向渐变，并将整体边界控制为接近 1:1：文件夹略窄、略高，轨道箭头只轻微越界；文件夹轮廓采用较细描边，双向箭头略加粗以维持 18pt 下的方向辨识度。SwiftUI 以 original rendering mode 加载，只负责尺寸与状态点组合。README 品牌展示图使用同一结构的透明 PNG；根 `README.md` 为英文入口，`README.zh-CN.md` 为简体中文入口，两者顶部互链并保持章节、命令与事实一致。

## 8. 关键架构决策记录（ADR）

| ADR | 建议 | 状态 |
| --- | --- | --- |
| 001 Git 集成 | 调用系统 Git CLI，不内置 Git | 已由需求确定 |
| 002 应用形态 | 原生 SwiftUI 菜单栏应用 + 独立设置窗口 | 已确认 |
| 003 后台模型 | 登录会话内运行，`SMAppService.mainApp` | 已确认 |
| 004 发布模型 | Developer ID 签名公证、直接分发 | 已确认 |
| 005 同步整合 | 自动提交后按有效配置执行 Rebase 或 Merge；默认 Rebase，冲突即停 | 已确认 |
| 006 自动化复用 | 规则库保存完整自动化配置；仓库按 ID 引用规则或保存自定义配置 | 已确认 |
| 006 数据存储 | 版本化 JSON 配置 + 有界历史存储 | 已确认 |
| 007 最低系统 | macOS 14+，新版视觉按可用性渐进增强 | 已确认 |
| 008 本地化 | String Catalog 管理简体中文与英文，英文为开发语言 | 已确认 |
| 009 设置窗口 | AppKit 展示前配置 full-size content，再嵌入 SwiftUI | 已确认 |
| 010 品牌资源 | README 渐变 PNG + 菜单栏原色渐变 SVG | 已确认 |

## 9. 官方设计与 API 基线

- Apple HIG — Designing for macOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
- Apple HIG — Settings: https://developer.apple.com/design/human-interface-guidelines/settings
- SwiftUI `MenuBarExtra`: https://developer.apple.com/documentation/swiftui/menubarextra
- AppKit `NSWindow`: https://developer.apple.com/documentation/appkit/nswindow
- AppKit `NSHostingController`: https://developer.apple.com/documentation/swiftui/nshostingcontroller
- SwiftUI `CommandGroupPlacement.appSettings`: https://developer.apple.com/documentation/swiftui/commandgroupplacement/appsettings
- Service Management `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice
