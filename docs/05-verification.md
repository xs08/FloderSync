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
  - 冲突后的自动重试在任何写操作前停止。
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
