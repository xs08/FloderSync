# FloderSync macOS UI、窗口与故障复盘设计

状态：已落地，作为后续 UI 迭代与回归验证基线
最后更新：2026-09-03

## 1. 文档目的

本文提炼 FloderSync 从首版到当前版本中已经出现并解决的关键问题，记录最终方案、技术原因与不可破坏的设计约束。需求范围仍以[需求规格](./01-requirements.md)为准，整体分层仍以[架构设计](./02-architecture.md)为准；本文专注于 macOS 窗口、导航、主题、本地化、仓库接入、错误反馈和品牌图标。

核心目标：

- 菜单栏承担状态查看和高频操作，设置窗口承担完整配置。
- 视觉选中态、键盘焦点、业务状态分别只有一个明确来源。
- 所有可能阻塞用户的系统面板都由应用统一协调。
- 仓库写操作必须发生在只读校验和用户确认之后。
- 同步失败必须同时投影到仓库、菜单栏和通知入口，不能只写日志。
- 设置窗口的外观在首帧展示前确定，避免原生标题栏残留和主题闪烁。

## 2. 问题、根因与最终方案

| 问题表现 | 根因 | 最终方案 | 防回归约束 |
| --- | --- | --- | --- |
| 应用名称不统一 | Target、Bundle Display Name 和 UI 文案分别维护 | 用户可见名称统一为 `FloderSync`，Swift 模块名继续使用 `floderSync` | 构建设置、String Catalog、README 和窗口文案必须同步检查 |
| 菜单栏空状态重复展示“打开设置” | 空状态和固定底栏都提供同一入口 | 空状态只说明暂无仓库；底栏固定保留设置与添加仓库 | 同一视图层级不重复主操作 |
| 菜单栏有仓库但列表区域消失 | 非空 `ScrollView` 只有最大高度，`MenuBarExtra` 首次测量时将其压缩为零；懒容器随后也没有稳定视口 | 按仓库行数计算明确高度并限制为 360pt，使用普通 `VStack` 确保首帧创建行内容 | 0、1、3 和大量仓库的高度边界必须由测试覆盖 |
| 调整每日时间会让后续行被排序或删除 | 每次 `DatePicker` 变化都即时执行集合去重和排序，索引在编辑中发生漂移 | 编辑草稿保持原顺序；新增从 `00:00` 起按末项加一小时并封顶 `23:00`；保存规则时才排序和校验唯一性 | 编辑单项不得改变其他行；重复时间必须阻止保存并显示中英文提示 |
| 文件编辑频繁触发无效同步 | 自动化 UI 暴露文件变化与静默延迟，触发语义和 Git commit 工作流不一致 | 移除文件变化与延迟配置，改为单一“新增 Commit 后同步”开关 | 普通文件编辑不触发，应用自身同步产生的 revision 变化不重触发 |
| 菜单栏“退出”占用高频入口 | 退出不是同步工作流的常用动作 | 菜单栏底栏改为“打开设置 + 添加仓库”；退出只保留在设置侧栏底部 | 菜单栏只放高频操作 |
| 设置页顶部标签与多层侧栏挤压、仓库页遮挡 | SwiftUI 系统分栏嵌套仓库主从分栏，尺寸协商互相影响 | 一级模块改为固定 220pt 的自定义侧栏；仓库列表只存在于仓库模块内部 | 一级导航不可折叠，不使用嵌套 `NavigationSplitView` 承担两级结构 |
| 无仓库时仍显示空列表列 | 主从布局无条件创建 | 直接展示居中的空状态和“添加仓库”按钮 | `profiles.isEmpty` 时不构造仓库列表 |
| 文件夹选择器打开后无法切换其他操作 | 多处各自创建 `NSOpenPanel`，旧面板生命周期未被统一管理 | `RepositoryPicker.shared` 单例持有面板与 continuation；任何新导航或选择动作先 `cancel()` | 同一时刻最多存在一个仓库选择面板，取消必须恢复挂起任务 |
| 非 Git 目录或未同步仓库直接进入配置 | 添加流程缺少只读预检 | 先验证 Git 根目录、当前分支和远端；再比较本地 `HEAD` 与远端分支哈希 | 用户确认前不执行 commit、pull 或 push |
| 冲突、pull/push 失败不醒目 | 错误只停留在一次运行记录 | `AppModel` 将失败和 `needsUserAction` 聚合为全局问题态，并投影到菜单栏图标、仓库行、仓库列表和通知 | 失败状态不能只依赖颜色，必须包含图标、文字和可访问性标签 |
| 界面出现本地化 key | 字符串资源不完整，动态切换仍走系统 bundle 默认语言 | 使用 String Catalog 覆盖英文与简体中文；运行时按用户偏好选择 bundle 并注入 `Locale` | 新增用户可见字符串必须同时提供 `en` 和 `zh-Hans` |
| 鼠标已切换模块，旧项目仍有蓝色外框 | 系统键盘 focus ring 与自定义蓝色选中背景是两个状态 | 导航使用 `FocusState`；焦点变化同步选中模块，按钮关闭系统 focus effect | 蓝色填充是唯一可见选中态，Tab 和鼠标必须得到同一结果 |
| 设置窗口仍有原生标题栏，标题被挡住 | SwiftUI `Settings` 先显示窗口，嵌入内容再异步修改 `NSWindow`，首帧已经生成 titlebar 与安全区 | 由 `SettingsWindowController` 在显示前创建 `NSWindow`，同步配置 full-size content、透明标题栏和隐藏标题，再挂载 SwiftUI | 禁止回退为在 `NSViewRepresentable` 中异步查找并修改窗口 |
| 深色切到浅色时标题栏先变白 | 原生标题栏和 SwiftUI 内容由不同渲染层、不同时间更新 | 窗口背景透明，SwiftUI 根视图绘制完整背景；标题栏不再拥有独立材质 | 主题只从 `AppTheme` 注入根视图，不维护第二套窗口主题状态 |
| 菜单栏图标纯白、线条粗、比例偏宽 | 模板图标被系统单色渲染，初版几何横向外扩过多 | 使用 original rendering 的蓝青渐变 SVG；收紧为接近 1:1 的光学边界，文件夹细描边、同步箭头略加粗 | 18pt 必须清晰，资源源文件保留矢量，README 使用同结构透明 PNG |
| Xcode 提示 Update to Recommended Settings | XcodeGen 配置未显式固化新版推荐项 | 推荐构建项写入 `project.yml` 并重新生成工程 | 不在生成后的 `.xcodeproj` 中手工维护易丢失设置 |
| `linkd.autoShortcut`、task port、`FSFindFolder -43` 日志疑似与标题栏相关 | Xcode/macOS 调试服务噪声与 UI 问题同时出现，造成时间相关性误判 | 用链接依赖、构建日志和功能测试拆分判断；当前均无证据指向窗口布局 | 只有伴随可复现业务失败时才升级为产品缺陷 |

## 3. UI 信息架构

### 3.1 菜单栏操作面板

菜单栏面板固定宽度约 360pt，由三层组成：

1. 顶部展示全局同步状态、正在同步数量和“同步全部”。
2. 中部展示仓库列表，列表高度受限；每行包含仓库名、状态、最近结果和单仓库同步入口。
3. 底部只保留“打开设置”和“添加仓库”两个高频入口。

状态规则：

- 无仓库：中部仅展示说明，不重复出现设置按钮。
- 同步中：菜单栏图标与仓库行同时表达进行中状态，并禁止同仓库重复执行。
- 失败或需人工处理：菜单栏图标显示问题标记，仓库行展示错误摘要；详情进入设置窗口查看。
- 面板与设置窗口共享同一个 `AppModel`，禁止各自推导一套状态。

### 3.2 设置窗口

设置窗口默认 960×640pt，最小 900×560pt，外观使用 28pt continuous 圆角。布局分为固定侧栏与内容区：

- 一级侧栏宽 220pt，常驻且不可折叠。
- 主模块纵向排列：仓库、自动化、历史与诊断。
- 底部工具横向使用 space-between：左侧设置，右侧退出；只显示图标并提供 tooltip 与可访问性标签。
- 设置页在启动、通知、语言和外观之后提供“配置导入与导出”分组。导入和导出使用原生文件面板；导入文件通过校验后以确认对话框显示仓库与规则数量，用户确认前不替换配置。
- 内容区只展示当前模块，不保留顶部横向标签栏，也不重复展示 `FloderSync 设置` 标题。

仓库模块有两种互斥形态：

- 无仓库：内容区直接显示空状态及添加按钮。
- 有仓库：模块内部显示任务列表和详情；新增、删除属于仓库模块操作，不进入一级侧栏。

这种结构将“应用模块导航”和“仓库对象选择”分开，避免两级选择混入同一个系统侧栏造成压缩与语义混乱。

## 4. 设置窗口技术方案

### 4.1 必须保留 `.titled`

完全移除 `.titled` 会一并失去标准红黄绿窗口按钮及部分原生窗口行为。最终窗口保留 `.titled`，但通过以下组合让内容延伸至标题栏区域：

```swift
let styleMask: NSWindow.StyleMask = [
    .titled,
    .closable,
    .miniaturizable,
    .resizable,
    .fullSizeContentView
]

window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
window.titlebarSeparatorStyle = .none
window.toolbar = nil
window.isOpaque = false
window.backgroundColor = .clear
```

`.titled` 负责标准窗口能力，`.fullSizeContentView` 让 SwiftUI 内容进入标题栏区域；隐藏标题、透明标题栏、移除 toolbar 与 separator 则消除独立的顶部模块。

### 4.2 首帧顺序是不变量

正确顺序必须是：

```text
创建 NSWindow
  → 配置 styleMask / titlebar / background
  → 挂载 NSHostingController
  → center
  → makeKeyAndOrderFront
```

旧方案在 SwiftUI `Settings` 已经显示后，通过 `NSViewRepresentable` 获取 `view.window` 再修改。该回调天然晚于窗口创建和部分首帧布局，因此即使最终属性值正确，也会看到标题栏残留、安全区偏移或主题切换闪白。这个问题不是某一个 titlebar flag 缺失，而是生命周期顺序错误。

当前设置入口统一调用 `SettingsWindowController.shared.show(model:)`；应用菜单中的 `⌘,` 通过 `.appSettings` command group 接入同一入口。不得再创建并行的 SwiftUI `Settings` scene。

### 4.3 圆角与背景所有权

- `NSWindow` 设为透明、非 opaque，并保留系统阴影。
- SwiftUI 根视图绘制整个窗口背景，并按统一圆角裁剪。
- 标题栏不单独拥有材质或主题颜色。
- 侧栏浅色背景、选中蓝色和内容背景全部使用语义色，适配浅色、深色与高对比度环境。

这样主题变化只有一条渲染链路，避免 AppKit chrome 与 SwiftUI content 分阶段变色。

## 5. 导航、键盘焦点与主题

### 5.1 导航状态

导航按钮使用语义 `Button` 栈而不是 `List`：

- `selectedSection` 是当前模块的唯一业务状态。
- `FocusState` 只承载键盘焦点；焦点移动到某导航项时同步更新 `selectedSection`。
- 点击导航项时同时更新二者。
- `.focusEffectDisabled()` 去除系统蓝色 focus ring，保留自定义蓝色填充。
- 切换离开仓库页时先取消可能存在的文件夹选择器。

Tab 导航仍然可用，但不会产生“蓝色填充在新模块、蓝色外框留在旧模块”的双重选择。

### 5.2 主题

`AppTheme` 只包含 `system`、`light`、`dark` 三种稳定值：

- 设置变化立即写入 `AppModel` 和 `UserDefaults`。
- 设置窗口及菜单栏根视图统一注入 `preferredColorScheme`。
- `system` 映射为 `nil`，交回系统外观决定。
- 缺失或非法持久化值回退为 `system`。

主题选项本地化，但持久化使用稳定枚举原始值，不能保存显示文案。

深色设置窗口使用 `SettingsPalette` 的不透明冷调炭灰色阶。深度依靠表面明度而不是黑色阴影或大面积透明材质表达：

| 角色 | 深色值 | 用途 |
| --- | --- | --- |
| 窗口底色 | `#21282D` | 侧栏外边距与窗口统一底层 |
| 内容背景 | `#252C31` | 设置详情主工作面 |
| 侧栏背景 | `#1A2024` | 与内容区形成稳定的一阶深度 |
| 抬升表面 | `#2B3338` | 仓库列表、底栏与自动化配置组 |
| 窗口 / 侧栏边框 | `#4F5B62` / `#3D4950` | 克制的轮廓分离，不使用高透明白边 |
| 主 / 次 / 弱文字 | `#F2F5F7` / `#B6BFC4` / `#8A969D` | 标题、说明与辅助图标的稳定层级 |
| 选中背景 | `#176BC9` | 仅用于当前导航与主要交互 |

主文字与内容背景对比度为 `12.93:1`，次文字为 `7.58:1`；白色选中文字与蓝色背景为 `5.27:1`，选中背景与侧栏为 `3.12:1`。这些组合分别满足 WCAG AA 文字与关键 UI 组件对比度要求。浅色主题继续使用 macOS 语义色，避免破坏系统适配与高对比度行为。

### 5.3 运行时语言切换

首版支持英文与简体中文，并提供“跟随系统”：

- `AppLanguage` 偏好保存在 `UserDefaults`。
- SwiftUI 根视图注入对应 `Locale`，保证系统控件与格式化内容跟随变化。
- 动态字符串由本地化入口从指定语言 bundle 查找，切换后直接刷新，不要求重启。
- 语言选择器使用语言自身名称（`English`、`简体中文`），不随当前界面语言互译。
- 侧栏标签显式依赖当前语言，禁止仅通过全局偏好隐式读取后让 SwiftUI 复用旧子视图。
- String Catalog 中每个 key 都必须同时存在开发语言英文与简体中文翻译。

## 6. 添加仓库与首次同步状态机

### 6.1 面板协调

`RepositoryPicker` 是应用级单例，内部只允许一个 `NSOpenPanel`：

```text
新建选择请求 / 打开设置 / 切换模块
  → 取消现有 panel
  → 恢复旧 continuation(nil)
  → 执行新操作
```

这保证用户无需先手动关闭文件夹选择器，就能从菜单栏打开设置，或在设置页切换其他操作。

### 6.2 只读校验顺序

选择文件夹后的添加流程：

```text
选择目录
  → 定位可执行 Git
  → git rev-parse --show-toplevel
  → 检查是否处于 merge/rebase 等进行中状态
  → 读取当前 symbolic branch
  → 读取远端 URL
  → 检查重复配置
  → 比较本地 HEAD 与 ls-remote 远端分支哈希
  → 保存有效配置
  → 如不同步，询问是否立即同步
```

关键语义：

- 非 Git 目录直接拒绝，不创建残缺任务。
- 没有配置目标远端时校验失败并不创建同步任务；用户需要先用系统 Git 配置远端，再重新添加。
- 本地未提交改动或哈希不一致只说明“需要同步”，不代表可以无条件覆盖远端。
- 选择“立即同步”才进入统一的同步引擎；选择稍后则交给手动或自动策略。
- 所有 Git 调用使用 `Process` 参数数组和明确工作目录，不通过 shell 拼接，也不保存认证信息。

### 6.3 同步失败投影

| 领域结果 | 菜单栏图标 | 菜单栏仓库行 | 设置仓库列表 | 通知 |
| --- | --- | --- | --- | --- |
| idle / success | 正常品牌图标 | 正常或最近成功 | 成功状态与时间 | 按用户偏好 |
| syncing | 进行中状态点 | 进度状态，禁用重复同步 | 进行中 | 通常不通知 |
| failed | 问题状态点 | 错误摘要 | 错误图标、摘要、诊断入口 | 默认通知 |
| needsUserAction | 问题状态点 | 明确提示需手动处理 | 展示冲突或 Git 错误，要求用户在仓库中解决 | 默认通知 |

同步冲突、pull/push 失败时不进行破坏性自动恢复；应用停止后续写操作并提示用户手动解决。下一次自动运行也必须先预检，不能绕过未解决状态。

## 7. 菜单栏与 README 品牌图标

品牌图标遵循以下结构约束：

- 语义：文件夹代表本地内容，双向轨道箭头代表 Git 同步。
- 色彩：深蓝到亮青渐变，使用 original rendering mode，避免被菜单栏强制为单色模板。
- 比例：光学边界接近 1:1；文件夹主体略窄、略高，轨道箭头只做轻微外扩。
- 线宽：文件夹轮廓更细，箭头略粗以保证 18pt 尺寸下仍能识别方向。
- 状态：同步与错误状态点是额外的状态层，不应通过替换品牌主体颜色表达全部状态。
- 资源：菜单栏使用 Asset Catalog 内 SVG；README 使用同结构透明 PNG，并在英文与中文入口同时展示。

图标适配不是简单缩放。若原始几何过宽，缩到 18pt 后会同时显得矮、粗和模糊，因此应优先调整 SVG 的光学边界和路径，再由视图设置最终尺寸。

## 8. Xcode 配置与调试日志判定

### 8.1 Recommended Settings

当前推荐项在 `project.yml` 中固化，包括：

- Asset Symbol Extensions
- Dead Code Stripping
- Missing Localizability 分析
- User Script Sandboxing
- String Catalog Symbols

这些设置影响资源符号、静态分析、脚本隔离和产物优化，不控制 `NSWindow` 的标题栏布局。工程由 XcodeGen 生成，变更推荐设置时应修改 `project.yml` 后重新生成，避免下一次生成覆盖手工修改。

### 8.2 已观察日志

| 日志 | 当前判定 | 处理策略 |
| --- | --- | --- |
| `com.apple.linkd.autoShortcut` Code 4097 | 系统快捷指令/Intents 注册服务在调试环境中的 XPC 连接失败；目标未链接 AppIntents，和标题栏无关 | 应用功能正常时忽略；系统或 Xcode 更新后复查 |
| `Unable to obtain a task name port right` | 调试器附加、进程退出或权限上下文日志 | 仅在无法启动、附加或调试时单独处理 |
| `FSFindFolder failed with error=-43` | 系统目录查询返回文件不存在 | 若配置、历史或选择目录功能出现对应失败，再记录具体路径定位 |

故障分析原则：先建立可复现的用户行为，再核对调用链和构建依赖；日志与问题同时出现不等于存在因果关系。标题栏问题最终由窗口创建顺序解释并通过窗口样式测试验证，与上述日志无关。

## 9. 实现落点

- 应用入口、菜单栏和设置命令：[`Sources/App/FloderSyncApp.swift`](../Sources/App/FloderSyncApp.swift)
- AppKit 设置窗口生命周期：[`Sources/App/SettingsWindowController.swift`](../Sources/App/SettingsWindowController.swift)
- 设置侧栏、模块与主题 UI：[`Sources/Presentation/SettingsRootView.swift`](../Sources/Presentation/SettingsRootView.swift)
- 菜单栏状态与快捷操作：[`Sources/Presentation/MenuBarView.swift`](../Sources/Presentation/MenuBarView.swift)
- 文件夹选择器协调：[`Sources/Presentation/RepositoryPicker.swift`](../Sources/Presentation/RepositoryPicker.swift)
- UI 状态、语言、主题和首次同步提示：[`Sources/Presentation/AppModel.swift`](../Sources/Presentation/AppModel.swift)
- Git 仓库校验与远端状态：[`Sources/Infrastructure/ProcessGitClient.swift`](../Sources/Infrastructure/ProcessGitClient.swift)
- 菜单栏矢量资源：[`Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg`](../Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg)
- README 品牌图：[`docs/assets/flodersync-icon.png`](./assets/flodersync-icon.png)
- 工程生成配置：[`project.yml`](../project.yml)

## 10. 回归验收清单

每次修改设置窗口、主题或导航时至少验证：

- 设置窗口首次出现时没有独立标题栏背景，内容标题不被窗口按钮或安全区遮挡。
- 深色、浅色、跟随系统之间切换时，整个窗口同一帧更新且无顶部闪白。
- 鼠标点击和 Tab 切换只有一个蓝色选中条目，不出现残留 focus ring。
- 900×560 最小尺寸下侧栏不折叠、不挤压、不遮挡内容。
- 空仓库时不显示空列表列，添加按钮可用。
- 打开文件夹选择器后，可直接切换设置、导航和再次添加仓库。
- 非 Git 目录被拒绝；未同步仓库只提示，用户确认前没有写操作。
- 冲突、pull/push 失败同时出现在仓库列表与菜单栏问题状态中。
- 英文、简体中文切换立即生效，不显示 key，不截断主要操作。
- 菜单栏图标在 18pt 下接近方形、线条清晰、渐变可见；浅色和深色菜单栏均可辨识。

自动化覆盖与真实设备待验项目见[功能测试方案](./03-test-plan.md)和[验证记录](./05-verification.md)。
