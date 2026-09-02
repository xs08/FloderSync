# FloderSync 实现路线图

状态：MVP 实现基线完成；发布工程待最终身份与证书（2026-09-02）

## Phase 0：技术探针

只验证高风险假设，不实现产品功能：

- GUI/登录启动环境中的系统 Git 路径、PATH、SSH_AUTH_SOCK 与 credential helper。
- `MenuBarExtra` + 设置窗口生命周期。
- `SMAppService.mainApp` 的注册与状态同步。
- FSEvents 监听、去抖和 `.git` 排除。
- Developer ID + Hardened Runtime 下启动 Git/SSH 的行为。

退出条件：发布方式、最低系统、认证兼容矩阵和后台模型有证据支持。

进度：系统 Git、菜单栏 scene、登录项 API、FSEvents 和非沙盒构建已完成代码/编译探针；Developer ID 与真实认证矩阵留到发布阶段。

## Phase 1：领域核心与测试夹具

- 建立 Swift Package/Xcode 工程边界。
- 实现领域模型、同步状态机、触发合并与错误分类。
- 建立 fake adapters 和本地 bare remote 集成测试夹具。

退出条件：无需 UI 即可通过自动化测试验证同步行为。

进度：已完成。

## Phase 2：Git 与持久化基础设施

- `ProcessGitClient`、Git 环境检查、超时取消和日志脱敏。
- 配置原子存储、schema 迁移和历史记录。
- 真实临时仓库集成测试。

退出条件：CLI 级测试覆盖无变化、本地变化、远端变化、冲突和失败路径。

进度：已完成 MVP 范围；配置存储已升级到 schema v2，并覆盖自动化规则库与 schema v1 迁移。本地 bare remote 集成测试通过。

## Phase 3：调度与系统集成

- 时间、间隔、文件变化和唤醒补偿。
- 登录启动、通知、网络/睡眠生命周期。
- 并发限制与状态投影。

退出条件：自动触发稳定且不重复、不并发破坏同一仓库。

进度：实现与确定性测试已完成；共享规则解析、可配置文件静默延迟、Rebase/Merge 调度已接入，睡眠和真实登录启动系统测试留到发布验证。

## Phase 4：UI 实现

- 菜单栏弹窗、仓库列表、快捷同步。
- 设置窗口、配置表单、历史与诊断。
- Accessibility、键盘、深浅色与最新系统视觉适配。

退出条件：UI 测试和人工 HIG 审查通过。

进度：菜单栏、仓库、自动化规则库、仓库自定义配置、通用、历史诊断及中英本地化已实现；真实签名 App 的完整视觉/辅助功能验收待办。

## Phase 5：发布工程

- Developer ID 签名、公证、更新策略、崩溃与诊断方案。
- 安装、升级、登录启动、卸载和回滚验证。

## 编码启动条件

需求文档第 6 节中的 12 项决策已确认。应用名称为 `FloderSync`，开发期 Bundle Identifier 继续使用 `dev.obssync.app` 以兼容现有本地配置，发布前允许迁移为用户最终持有的反向域名标识。
