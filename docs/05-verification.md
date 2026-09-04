# FloderSync MVP 验证记录

状态：实现基线验证通过，发布验证待办  
日期：2026-09-03

## 已验证

- Xcode 26.6 / Swift 6.3.3 下 macOS 14 deployment target 构建成功。
- 全量 XCTest 单元、集成、本地化目录、Asset Catalog、窗口样式与离屏渲染测试已通过。
- 本地 bare remote 集成测试覆盖：
  - 添加仓库前拒绝非 Git 文件夹。
  - 初次同步预检可区分远端一致、本地未提交改动与远端提交领先。
  - 手动或定时同步遇到本地文件变化时自动暂存、提交并推送。
  - 自动提交支持仓库/共享规则两级开关、Git 身份回退和动态信息模板，临时作者不会改写仓库 Git 配置。
  - 干净工作区拉取远端提交。
  - 双端冲突停止在 push 之前，远端引用保持不变。
  - 冲突后回滚本次整合操作；自动重试可安全重新获取同一远端状态，不会被残留 operation marker 阻断，也不会执行 push。
  - Rebase 与 Merge 均进入统一同步引擎；Merge 在分叉历史中创建 merge commit 后正常推送。
- 调度测试覆盖每日时间点、跨日计算、间隔补偿与从未运行时不补偿。
- 每日时间编辑测试覆盖首项 `00:00`、逐小时追加、`23:00` 封顶、编辑期不排序，以及保存时排序和重复值拒绝。
- Commit 检测测试覆盖 Git 元数据路径过滤、首次 revision 基线、外部 revision 变化触发，以及同步期 revision 变化抑制；`ProcessGitClient` 可读取真实临时仓库的当前 `HEAD`。
- 并发测试覆盖同仓库不并行、事件风暴合并为当前运行加一次待处理运行。
- 配置与历史记录具备版本字段、原子写入和数量上限测试；schema v1/v2/v3 会迁移原提交模板与自动化配置到 schema v4，旧文件变化策略迁移为新增 commit 检测。
- 登录项状态在应用启动、设置页显示、应用重新激活及开关操作后回读系统权威状态。
- Git 子进程在取消或超时时先请求终止，忽略 TERM 时升级为 KILL，且不会永久阻塞等待。
- 自动化规则解析测试覆盖共享规则覆盖仓库自定义值、自定义配置隔离和缺失规则时停止自动调度。
- 英文浅色与简体中文深色菜单栏空状态完成离屏渲染检查，无文案截断。
- 菜单栏非空仓库列表具备按行数计算的可见高度与 360pt 上限，不会在弹层首帧被压缩，也不会随仓库数量无限增高。
- 设置窗口空状态完成 960×640 的中英文、浅色与深色离屏检查；固定圆角侧栏、选中态、内容标题和底部图标均无溢出。
- 设置窗口样式测试确认文字标题隐藏、标题栏透明、分隔线移除、内容延伸到标题栏且窗口背景支持圆角透明裁剪。
- 主题偏好测试确认深浅色选择可即时写入模型并持久化，非法或缺失配置回退为跟随系统。
- 深色设置窗口完成侧栏、内容、抬升表面、边框、主次文字和选中态离屏渲染检查；自动化对比度测试覆盖 WCAG AA 文字与关键 UI 组件阈值。
- 编译产物已经包含 `en.lproj` 和 `zh-Hans.lproj` 的全部 String Catalog 输出。
- `MenuBarIcon` 已由 Asset Catalog 成功编译并以 original color artwork 加载；README 品牌 PNG 为带透明通道的 1254×1254 图像，英文与简体中文入口互链。

## Xcode 环境诊断

- Xcode 26.6 的 Recommended Settings 已写入 `project.yml` 并通过 XcodeGen 固化，包括 Asset Symbol Extensions、Dead Code Stripping、Missing Localizability、User Script Sandboxing 与 String Catalog Symbols；这些设置影响构建分析、资源符号生成和产物优化，不参与 `NSWindow` 标题栏布局。
- 构建日志确认目标没有链接 `AppIntents.framework`，元数据处理器也明确跳过 App Intents 提取。`com.apple.linkd.autoShortcut` 连接失败来自 Xcode/macOS 在调试启动期间进行的系统快捷指令注册，不是 FloderSync 发起的同步或窗口调用，也不会生成顶部标题栏。
- `Unable to obtain a task name port right` 属于调试器附加或目标进程退出时的进程权限日志；应用可正常启动和测试时不视为功能错误，与窗口层级无关。
- `FSFindFolder error=-43` 表示系统文件夹查询返回“文件不存在”。当前配置存储、历史存储和仓库选择测试均通过，未发现对应的业务路径失败；保留为环境日志观察项，若后续伴随具体文件功能失败，再按当时路径单独定位。

## 发布前必须验证

- 在 Developer ID 签名与 Hardened Runtime 下运行 Git、SSH 和 credential helper。
- 真实 HTTPS + macOS Keychain、标准 SSH Keychain、自定义 ssh-agent 环境矩阵。
- `SMAppService.mainApp` 首次注册、用户拒绝、系统设置撤销和升级后的状态。
- 真实菜单栏 window、设置侧边栏各模块、长仓库名、VoiceOver、键盘和高对比度视觉检查。
- 睡眠/唤醒、网络断开、外接磁盘断开和应用退出过程。
- 在真实仓库中确认普通文件编辑不触发、外部 commit 只触发一次，并确认应用自动 commit/pull/rebase/merge 不产生重触发。
- 公证、首次安装、升级与卸载流程。

## 已知环境限制

SwiftUI 离屏渲染已验证菜单栏与设置空状态布局；原生窗口控制按钮及不同系统版本的阴影细节仍需在真实窗口与签名安装包阶段完成最终视觉验收。

## 2026-09-03 配置导入导出变更

- “通用”入口已改名为“设置”，设置页新增统一 JSON 配置导入导出入口。
- 代码已实现版本化归档、10 MB 文件限制、完整配置校验、覆盖确认、原子导出、登录项应用与调度重建。
- 已补充 JSON 往返、每日时间规范化和悬空规则引用拒绝的自动化用例，但按本次测试安排未启动自动化测试或构建；仅执行 Swift 语法解析、String Catalog JSON 解析、`git diff --check` 与工作区产物检查。导入导出的真实文件面板、覆盖确认、登录项状态及中英文布局交由同步后的人工测试验证。

## 2026-09-03 侧栏与 AppIcon 优化

- 设置侧栏使用现有原色 `MenuBarIcon` 在顶部居中展示 48pt 品牌图标，顶部纯留白从 72pt 调整为 30pt。
- AppIcon 的 10 个 macOS 尺寸槽位由同一 1024px 母版派生，原有蓝青图形保持不变，透明区域统一合成为不透明纯白背景；静态像素检查确认全部资源最小 alpha 为 1，角点为白色。
- 已补充 AppIcon 槽位白底回归用例，但按本次安排未启动自动化测试或构建；侧栏真实窗口布局、Applications 中的图标显示和系统图标缓存刷新交由同步后的人工测试确认。

## 2026-09-04 同步整合可靠性增强

- 同步流程已从不透明的 `git pull` 拆分为 fetch、不可变远端 revision、领先/落后分析、Rebase/Merge 和 push；只有远端 revision 含本地尚未拥有的提交时才执行整合。
- fetch 与 push 的短暂网络错误默认最多尝试 3 次并线性退避；push 遇到 non-fast-forward 时最多重新 fetch、整合并重试 2 轮，不执行强制推送。
- Rebase/Merge 冲突后会自动 abort 本次运行启动的操作，保留本地自动提交和远端提交，并恢复当前分支及干净工作区；用户在运行前已经启动的冲突操作仍保持原状。
- SSH `connect to host` 错误会归类为网络故障，push 拒绝会归类为 non-fast-forward，避免原先笼统的 command-failed 结果。
- 定向 XCTest 31 项通过，覆盖 Rebase/Merge 冲突回滚、重复尝试、用户已有冲突保护、远端快照与分叉计数、网络错误分类、fetch/push 网络重试和 non-fast-forward 竞态重试。
- 独立 Debug 构建成功；完整 XCTest 72 项通过，包含 Domain/Application、真实临时 bare remote、调度与并发、配置迁移、本地化和 UI 离屏渲染。测试只操作任务创建的临时仓库；没有修改报错的真实 Obsidian 仓库。
- 仍需在真实网络环境验证 SSH 断开后恢复、同步途中睡眠/唤醒，以及全局 Git hook 超时后的回滚表现。路径级同步排除和结构化文件语义合并保留为后续独立 schema/UI 变更。

## 2026-09-04 应用版本基线

- `Config/Version.xcconfig` 已作为版本单一真源接入 Debug 与 Release 配置；构建产物的 `CFBundleShortVersionString` 已核对为 `0.1.0`，与设置页读取值一致。
- 版本脚本只读检查与计算已通过：`0.1.0` 的下一 minor 版本为 `0.2.0`，`1.9.7` 为 `1.10.0`，非法两段格式会失败且不修改版本源。
- 本地化与 UI 定向 XCTest 通过；设置页中英文 960×640 离屏渲染已人工检查，浅色和深色下均直接显示 `0.1.0`，无截断或颜色依赖。
- 完整 XCTest 通过，普通测试构建后版本源仍为 `0.1.0`；未执行会安装到 `/Applications` 的脚本或生成分发 ZIP，因此实际安装、签名包及脚本默认递增后的完整产物流程仍需在发布构建时确认。
