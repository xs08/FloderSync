# FloderSync Agent 开发指南

本文件适用于仓库根目录及全部子目录。它将产品约束、架构边界、UI 基线、测试要求和 Git 工作流转化为后续 Agent 必须遵守的开发规则。

## 1. 开始工作前

1. 先执行 `git status --short --branch`，识别用户已有的未提交改动；不得覆盖、回退、格式化或顺带提交与当前任务无关的内容。
2. 阅读与任务直接相关的文档。任何行为变更都按以下链路推进：
   - `docs/01-requirements.md`：产品行为、边界和验收标准。
   - `docs/02-architecture.md`：分层、数据流和技术决策。
   - `docs/03-test-plan.md`：对应的自动化与人工测试。
   - `docs/04-implementation-roadmap.md`：实现阶段和剩余工作。
   - 核心实现与验证记录。
3. UI、窗口、主题、本地化、仓库接入、错误状态或图标变更，必须同时阅读 `PRODUCT.md` 与 `docs/06-ui-window-and-troubleshooting-design.md`。
4. 自动化规则、调度、自动提交或 Git 整合策略变更，必须同时阅读 `docs/07-automation-rule-library-design.md`。
5. 需求发生变化时，先更新需求文档，再检查架构文档和测试方案，最后修改实现。不要让代码成为唯一的需求记录。

## 2. 产品身份与范围

- 产品名是 **FloderSync**。这是当前正式拼写，不要擅自改成 `FolderSync`。
- XcodeGen 工程名、scheme 与 Swift 模块名是 `floderSync`；App 产物是 `FloderSync.app`。
- 最低系统版本为 macOS 14；技术栈为 Swift 6、SwiftUI、少量 AppKit 与 Swift Concurrency。
- 应用是 `LSUIElement` 菜单栏工具，不显示 Dock 图标；设置使用独立窗口。
- 开发期 Bundle Identifier 是 `dev.flodersync.app`，配置与历史位于 `~/Library/Application Support/dev.flodersync.app/`。修改标识符前必须设计数据迁移与登录项迁移。
- 首版语言为英文和简体中文；支持跟随系统、英文、简体中文并即时切换。
- 支持跟随系统、浅色、深色主题并即时切换和持久化。
- MVP 只管理已经存在、已配置远端和系统认证的本地 Git 仓库，不提供 clone、init、远端创建、账号、Token 或 SSH Key 管理。

## 3. 不可破坏的安全规则

FloderSync 的第一原则是保护用户工作区。任何实现和测试都必须维持以下不变量：

- 不自动执行 `git reset --hard`、强制推送、自动丢弃修改、自动解决冲突或其他历史破坏操作。
- 冲突、detached HEAD、merge/rebase 进行中、认证失败、远端缺失和非 fast-forward 等状态必须停止流程并提示用户手动处理。
- 自动任务必须设置 `GIT_TERMINAL_PROMPT=0`，不得在后台无限等待认证输入。
- 不读取或持久化密码、PAT、SSH 私钥等秘密；复用系统 Git、SSH、Keychain 与 credential helper 配置。
- 日志、错误和历史中的远端 URL、命令输出与参数必须统一脱敏。
- Git 命令必须通过 `Foundation.Process` 的可执行文件与参数数组调用；禁止 `/bin/sh -c`、字符串拼接 shell 命令和任意用户命令输入。
- 每个 Git 子进程必须有超时与取消路径。取消或超时时先 TERM，有限等待后才能 KILL，并记录明确结果。
- 删除仓库只删除 FloderSync 配置和关联记录，不删除本地目录或 `.git` 数据。
- 添加仓库先做只读预检；用户确认“立即同步”之前不得修改所选仓库。
- 集成测试只能操作测试创建的临时目录和本地 bare remote，禁止使用真实用户仓库或公网远端。

## 4. 同步语义

所有触发源必须进入同一个 `SyncCoordinator` / `SyncEngine` 流程，不得为菜单栏、定时或文件事件分别实现 Git 流程。

标准顺序：

1. 校验 Git 可执行文件、工作区、当前分支和远端。
2. 读取工作区状态，并拒绝未解决冲突或进行中的 Git 操作。
3. 有本地变化且自动提交开启时执行 `git add --all` 和提交；自动提交关闭时在写操作前停止并要求用户处理。
4. 按有效配置执行远端整合：默认 Rebase，或显式 Merge。
5. 仅在前述步骤成功后 push 当前分支。
6. 保存触发来源、规则名称、整合策略、步骤、耗时、结果和脱敏错误。

额外约束：

- Git 元数据事件只代表“revision 可能变化”；必须比较当前 `HEAD` 与已记录 revision，确认变化后才触发同步。
- 同步任务开始时暂停对应仓库的 commit 检测，完全空闲后以最新 `HEAD` 刷新基线；自动 commit、pull、rebase 或 merge 不得重触发同步。
- 同一仓库始终串行；运行中的重复触发最多合并成一个后续运行。手动触发优先级最高，其次为唤醒补偿。
- 不同仓库默认最多并发 2 个。
- 自动提交作者覆盖仅通过本次 `git -c user.name=... -c user.email=...` 生效，不得修改仓库或全局 Git 配置。
- 提交模板支持 `${user}`、`${email}`、`${time}`；持久化稳定模板，不持久化已渲染文案。

## 5. 自动化与配置

- `SyncProfile` 保存仓库属性以及“共享规则 ID 或仓库自定义配置”。运行前通过规则库解析为有效配置。
- 一条 `AutomationRule` 包含触发条件、自动提交配置和远端整合策略；多个仓库可通过 UUID 引用同一规则。
- 从共享规则切换到自定义配置时，先复制当前有效配置，避免行为突变。
- 删除被引用规则时不能留下悬空引用；如用户确认解绑，应把规则配置复制到引用仓库后再删除。
- 规则缺失或配置损坏时，停止该仓库的自动调度并显示配置错误；不要静默套用默认值掩盖问题。
- 同类型策略最多一项：新增 commit、固定间隔、每日指定时间。每日时间保存后必须唯一且排序。
- 固定间隔范围 1 分钟至 24 小时。
- 配置当前使用 schema v4。模型变化必须：
  1. 增加向后兼容解码或显式迁移；
  2. 保留 v1/v2 迁移测试；
  3. 原子写入并保留可恢复备份；
  4. 更新架构、测试方案和验证记录。

## 6. 架构边界

依赖方向只能是：

```text
Presentation → Application → Domain ← Infrastructure
App 负责组合依赖和 macOS scene/window 生命周期
```

### Domain

- `Sources/Domain/SyncModels.swift`：值对象、策略、运行记录和标准化错误。
- `Sources/Domain/GitClient.swift`：Git 端口。
- 不依赖 SwiftUI、AppKit、`Process`、FSEvents 或具体存储。
- 领域模型跨并发边界时保持 `Sendable`；稳定持久化值优先使用显式 raw value。

### Application

- `SyncEngine`：单次同步用例和步骤顺序。
- `SyncCoordinator`：同仓库串行、重复触发合并和跨仓库并发限制。
- `AutomationScheduler`、`CommitChangeScheduler`、`CatchUpCalculator`：只生成同步意图，不执行 Git。
- 配置和历史通过协议注入，时间敏感逻辑应允许注入 clock/`now` 以便确定性测试。

### Infrastructure

- `ProcessGitClient`：系统 Git 发现、非交互执行、超时取消、错误分类和脱敏。
- `JSONProfileStore` / `JSONRunHistoryStore`：版本化、原子持久化与迁移。
- FSEvents、登录项、系统唤醒和通知均通过小型适配器隔离。
- 基础设施错误在进入 UI 前映射为领域错误或可理解信息。

### Presentation / App

- `AppModel` 是菜单栏和设置窗口共享的 `@MainActor` 状态源；不要让两个界面各自推导另一套同步状态。
- SwiftUI View 只负责展示、轻量输入校验和转发用户意图，不直接执行 Git、持久化或管理长期调度任务。
- `Sources/App/FloderSyncApp.swift` 只组合 scene、命令与根依赖。
- 需要平台生命周期控制时使用小型 AppKit bridge，不把 AppKit 细节扩散到 Domain/Application。

新增功能时优先扩展现有端口和用例，不从 View 直接越层访问 Infrastructure。

## 7. macOS UI 与窗口基线

整体风格以 `PRODUCT.md` 为准：原生、克制、专业、清晰；视觉层级服务于状态与操作，不使用装饰性玻璃、过度透明或无语义高饱和色。使用 Apple HIG、系统字体、语义色和原生控件。

### 菜单栏

- 使用 `MenuBarExtra` 的 `.window` 样式，宽度与列表高度保持可预测。
- 顶部展示全局状态与“同步全部”；中部展示仓库状态和单仓库同步；底部只保留打开设置与添加仓库。
- 空仓库状态不重复展示打开设置按钮。
- 失败、需处理和同步中状态必须同时投影到品牌图标、仓库行和设置列表，不能只依赖颜色。
- 菜单栏品牌图标使用 Asset Catalog 中的 `MenuBarIcon.svg`、original rendering、接近 1:1 的光学边界；不要退回通用 SF Symbol 或模板单色图。

### 设置窗口

- 设置窗口必须由 `SettingsWindowController` 在首个可见帧之前同步创建和配置，禁止重新引入 SwiftUI `Settings` scene 或显示后再用 `NSViewRepresentable` 修补 window chrome。
- 必须保留 `.titled` 以维持红黄绿按钮，同时使用 `.fullSizeContentView`、隐藏标题、透明 titlebar、无 separator、无 toolbar、透明 `NSWindow` 背景。
- 顺序是不变量：创建窗口 → 配置 style/titlebar/background → 挂载 `NSHostingController` → center → 显示。
- SwiftUI 根视图独占整窗背景和 28pt continuous 圆角，避免主题切换时 AppKit 标题栏与内容分帧变色。
- 默认尺寸 960×640pt，最小 900×560pt。
- 一级侧栏固定约 220pt、常驻且不可折叠；仓库、自动化、历史与诊断纵向排列，通用与退出在底部横向分布且只显示图标。
- 一级导航使用语义 Button 栈，不使用会引入系统分栏行为的 `List`。`selectedSection` 是唯一选择状态；键盘焦点变化同步选择，并通过 `.focusEffectDisabled()` 避免残留双重蓝色边框。
- 仓库为空时直接显示空状态与“添加仓库”，不要创建空的第二级列表列。
- `RepositoryPicker` 始终只保留一个 `NSOpenPanel`；打开设置、切换模块或再次选择前先取消旧 panel 并恢复 continuation。
- 深色主题沿用 `SettingsPalette` 已定义的不透明冷调炭灰层级，不用大面积纯黑、白色透明描边或装饰性阴影重塑层级。

UI 变更不能仅凭编译通过。至少验证首次打开、最小窗口、中英文、浅/深色、键盘 Tab、空状态、失败状态和主题切换无标题栏闪白。

## 8. 本地化、主题与无障碍

- 所有用户可见文案必须进入对应 String Catalog；不得在 SwiftUI、AppKit alert、通知或错误信息中硬编码仅一种语言。
- 每个 key 必须同时有非空英文和简体中文翻译，缺失时以英文为回退。
- 使用已有表分类：`Localizable`、`Settings`、`Automation`、`Errors`、`History`、`Notifications`、`RepositoryActions`。
- 动态文案通过 `L10n.string/format` 和明确 table 获取；SwiftUI 静态 key 保持可被 String Catalog 提取。
- `AppLanguage`、`AppTheme` 以稳定 raw value 写入 `UserDefaults`，不能保存本地化显示文本。
- 语言与主题变化必须同时刷新菜单栏和设置窗口且无需重启；非法持久化值回退为跟随系统。
- 每个图标按钮都必须有 tooltip、键盘焦点和 VoiceOver 标签。
- 状态表达使用“图标 + 文字 + 颜色”，颜色不能是唯一信号。
- 保持 WCAG AA 对比度，检查长仓库名、英文和简体中文布局；尊重增大对比度、减少透明度和减少动态效果。

## 9. 工程与代码约定

- `project.yml` 是 Xcode 工程配置的唯一真源。新增源码、资源、Build Setting、target 或 scheme 时先改 `project.yml`，再执行 `xcodegen generate`；不要手工编辑 `project.pbxproj`，生成后的工程文件应与配置一同提交。
- 不改变当前 macOS 14 deployment target、Swift 6 配置、非沙盒模型或 `LSUIElement`，除非先完成架构与发布影响评审。
- 遵循现有 Swift 风格：4 空格缩进、小型值类型、显式依赖注入、尽量不可变、`async/await` 与 actor 隔离。
- UI 状态对象保持 `@MainActor`；共享可变后台状态优先放入 actor。不要用 `@unchecked Sendable` 绕过问题，除非封装的是系统 API 且内部同步有清楚说明和测试。
- 不吞掉会影响用户决策的错误。只在通知等明确 best-effort 的边界使用 `try?`。
- 不为顺手重构扩大任务范围。命名或文件移动需要同步更新 `project.yml`、脚本、README、文档链接和测试。
- 构建产物放在 `build/`、`dist/` 或任务专用 `/private/tmp` DerivedData；不要提交 DerivedData、临时仓库、签名产物或本机配置。

## 10. 构建与测试

标准命令：

```bash
xcodegen generate

xcodebuild build \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/FloderSyncDerivedData

xcodebuild test \
  -project floderSync.xcodeproj \
  -scheme floderSync \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/FloderSyncDerivedData
```

验证要求按变更风险递增：

- 纯文档：检查链接、命令、名称与当前实现一致，并执行 `git diff --check`。
- Domain/Application/Infrastructure：运行受影响测试；Git 流程、配置 schema、调度或并发变化必须运行完整 XCTest。
- String Catalog：运行 `LocalizationCatalogTests`；确保构建产物包含 `en.lproj` 与 `zh-Hans.lproj`。
- 窗口、菜单栏、主题、导航或布局：运行 `UIRenderTests` 和完整 XCTest，并记录仍需真实 macOS 窗口人工确认的项目。
- Git 命令行为：运行 `ProcessGitClientIntegrationTests` 与 `SyncEngineTests`，确认测试只使用临时 bare remote。
- 登录项、通知、签名、打包：除自动测试外，明确列出需要已签名 App 或真实系统设置验证的部分；不要把离屏渲染结果描述为真实窗口验收。
- 提交前始终执行 `git diff --check`，并确认 `git status --short` 中没有意外产物。

如环境缺少 Xcode、XcodeGen、签名身份或系统权限，应报告未验证项目和具体原因，不得声称已通过。

## 11. 文档同步规则

下列变更必须在同一任务中更新相应文档：

- 产品范围、默认行为、错误处理或验收变化：`docs/01-requirements.md`。
- 模块职责、数据流、模型、持久化、并发或系统 API 变化：`docs/02-architecture.md`。
- 新功能与回归风险：`docs/03-test-plan.md`。
- 实现阶段或剩余项变化：`docs/04-implementation-roadmap.md`。
- 实际执行的验证、环境限制和待测矩阵：`docs/05-verification.md`。
- UI、窗口、主题、本地化、图标、Xcode 警告结论：`docs/06-ui-window-and-troubleshooting-design.md`。
- 自动化规则与迁移：`docs/07-automation-rule-library-design.md`。
- 用户可见能力、安装、打包、路径或命令变化：英文 `README.md` 与中文 `README.zh-CN.md` 必须保持内容等价和互链。

## 12. Git 工作流与交付

- 编码任务完成后必须提交代码；只进行分析、评审或规划时不要创建提交。
- 默认只提交，不推送。只有用户明确要求时才 push、创建/关闭 PR 或合并远端分支。
- 提交前检查工作区，确保不把用户原有或无关改动混入当前提交。若当前任务必须修改一个已被用户改动的文件，先确认 diff，只暂存本任务对应内容。
- 提交信息沿用现有约定：`feat:`、`fix:`、`refactor:`、`test:`、`docs:`、`chore:`，描述具体结果。
- 不使用 `git reset --hard`、`git checkout --`、强制推送或删除分支，除非用户明确授权且已经创建可恢复路径。
- 最终交付需说明：完成内容、主要文件、执行的测试及结果、未验证风险、提交 hash，以及是否推送。

## 13. 完成定义

一项开发任务只有在以下条件同时满足时才算完成：

1. 行为符合需求文档与安全不变量。
2. 分层职责清楚，没有从 View 越层执行 Git 或持久化。
3. 中英文、主题、错误状态和无障碍覆盖与改动匹配。
4. 相关自动化测试通过，并记录真实系统仍需验证的部分。
5. 文档已同步，`git diff --check` 无问题。
6. 只提交了本任务的变更，提交 hash 已交付；未获授权时没有推送。
