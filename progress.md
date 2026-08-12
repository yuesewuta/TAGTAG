# 进度日志

## 会话：2026-08-10（SQLite 标签元数据统一）

- 用户要求继续开发。按本地 issue tracker 与领域文档复核后，阶段 9 尚余两项：标签状态从应用数据 JSON 迁入资料库 SQLite，以及里程碑 2 的系统入口。
- 本轮先处理 SQLite 元数据统一：它收敛受管资源、标签、空间和操作日志的持久化边界，但不存储资源文件字节，也不改变存储根中的普通文件和文件夹。
- 已恢复规划上下文；上一轮 `v0.1.0` 标签发布和双 Windows 产物已记录在版本库，当前 `main` 工作区干净。
- 已建立 `.scratch/metadata-persistence/` 本地任务，并按测试 seam 先验证 SQLite 文档重开、旧状态一次迁移和 SQLite 权威性；初始红灯为缺少 `ManagedLibrary` 标签元数据接口。
- 实现 schema v6 的成对标签状态/偏好文档事务，控制器在 SQLite 文档不存在时才校验并导入旧 JSON，之后所有状态、偏好和资源同步均写入资料库。全局恢复协调器不再读取或回写旧状态作为回滚来源。
- 首次恢复协调器调整误删了构造恢复后控制器所需的 `LocalStore` 注入，定向测试在编译期准确报错；恢复该依赖但不恢复旧 JSON 读写后，定向标签领域测试 25/25 通过。
- 全量测试第一次运行发现主应用恢复调用写成不存在的 `widget.loc`；改为 `widget.locator` 后，完整套件 64/64 通过，`flutter analyze --no-pub` 0 问题，Windows Release 构建与插件打包冒烟均为 GREEN。
- 阶段 9 的 SQLite 标签元数据统一已完成；本地任务 `.scratch/metadata-persistence/` 已解决，下一项进入里程碑 2 的 Windows 系统入口。
- 里程碑 2 已创建 `.scratch/windows-system-entrypoints/`，首个 `Ctrl+Shift+T` 全局 Quick Tag 切片在 Windows runner 以 `RegisterHotKey` 注册，激活时恢复窗口并向 Flutter 发送事件；C++ 不承担资源或标签业务。
- Flutter 通道适配器查询原生注册状态、转发激活事件并在页面销毁时取消监听。已选受管资源复用既有标签对话框；没有选择时打开原有文件选择，后续仍进入统一导入并标注流程。
- 通道测试先因适配器文件缺失转红；首次实现又因当前 Flutter 的 `setMethodCallHandler` 为同步 API 报错，移除多余 `await` 后通过。主页测试夹具随后修正了 `tester.runAsync` 的可空返回值；通道和主页定向测试均通过，Windows Release 已成功编译链接全局热键桥接。
- 随后在原工作区完成完整 Flutter 测试、`flutter analyze --no-pub`、Windows Release 构建和插件打包冒烟；此前 SQLite 原生资产文件锁已解除。全局 Quick Tag 任务已关闭，下一张任务卡为 Win32 托盘常驻生命周期。
- 托盘常驻生命周期随后以 Win32 `Shell_NotifyIconW` 实现：普通关闭隐藏窗口，菜单提供显示、Quick Tag 和明确退出。热键注册句柄被显式保留，避免基类在 `WM_DESTROY` 后清空窗口句柄导致注销失败。新增原生生命周期回归测试；完整测试、静态检查、Windows Release 构建和插件冒烟均通过。Explorer 右键桥接为下一项。
- Explorer 右键采用独立 `tagtag_explorer_bridge.exe`：它只转发选中路径或启动既有应用，不加载 Flutter、SQLite 或领域逻辑；安装器按当前用户注册文件和文件夹命令。已有受管路径进入标签选择，外部路径进入导入并标注对话框。可选悬浮接收目标以置顶 Win32 小窗口实现，设置随资料库元数据持久化，拖放同样复用该路径事件。至此里程碑 2 的四个系统入口全部完成。完整 Flutter 测试、静态检查、Windows Release 与产物检查均通过；本机未安装 Inno Setup，安装器编译由 GitHub Actions 的既有步骤验证。

## 会话：2026-08-09（阶段 13：一致性告警处理）

- 用户要求继续后续开发；Git 分支 `codex/managed-storage-core` 与远端同步，HEAD `f728aae`，工作区干净。
- 现有扫描器已可靠区分孤立内容 `untracked` 与缺失资源 `missing`，但告警 UI 只有查看和刷新，没有处理动作。
- 阶段 13 将在已确认的 `ManagedLibrary` 公共 seam 按 TDD 实现：孤立内容接管、移出存储根，以及由用户显式配对缺失记录与孤立路径后的接受新路径/恢复记录路径。

## 会话：2026-08-09（阶段 12：补全资源退出管理）

- 使用当前 `C:\Python314\python.exe` 运行 session-catchup；恢复报告只包含上一轮已完成的 UI 重构、本轮启动记录和 22 条未同步工具/消息，未显示新的业务代码变更。
- Git 实际状态确认：分支 `codex/managed-storage-core`，HEAD `97df033`，工作区干净。
- 将当前阶段从已完成的阶段 11 推进到阶段 12；先在既已确认的 `ManagedLibrary` 公共 seam 按 TDD 实现“移动到指定位置并退出管理”，再实现 Windows 回收站退出。
- `ManagedLibrary` 指定位置退出已完成前三个纵向测试切片：文件退出并记录 `exitMove`、同名目标绝不覆盖、撤销回到原受管路径；文件夹完整层级退出与撤销也已通过。
- 元数据 schema 从 v2 升至 v3，为 `operations.type` 增加 `exit_move`，并提供已有 v2 操作日志的迁移路径。
- 退出日志上下文增加内部资源快照，保留最初导入路径和资源创建时间；现有域关系 JSON 字段保持顶层结构不变。
- 直接调用 `flutter.bat` 再次停在批处理启动层且没有 Dart 子进程；终止空会话后按既有方案运行 `dart.exe flutter_tools.snapshot test --no-pub`。沙箱首次阻止写 SDK lockfile，获得受控权限后测试正常运行。
- 控制器与资源行 UI 已接入指定位置退出；同名冲突提供“重命名后放入 / 改到其他位置 / 取消”，操作日志显示新类型并可撤销。
- 验证结果：`flutter analyze --no-pub` 0 问题，全量测试 43/43 通过。
- Windows Release 构建成功；冒烟中的插件打包检查通过。目录选择器检查被一个 20:28 启动、无主窗口但仍持有单实例 Mutex 的既有 `tagtag.exe`（PID 22084）拦截；为避免关闭用户可能仍在使用的进程，本轮暂未强制结束。
- 经用户批准结束无窗口的旧 TAGTAG PID 22084 后，最新 Windows Release 构建成功，插件打包、存储根目录对话框和单实例三项应用冒烟全部通过。
- Windows 回收站退出已完成：Dart 网关通过 MethodChannel 调用原生 `IFileOperation`，删除回调把实际回收站 Shell item 的绝对 PIDL 序列化为持久 token，撤销时反序列化同一 token 并移回原受管路径。
- 回收站核心事务覆盖完整关系清理、`exit_recycle` 日志、schema v3→v4 迁移、受管路径冲突保护与撤销；原生 smoke 真实验证文件和含嵌套内容文件夹的回收/恢复 round trip。
- 最终验证：`flutter analyze --no-pub` 0 问题，48/48 测试通过，Windows Debug/Release 构建成功；1280×720 与 960×720 `PrintWindow` 检查确认 7 个资源动作图标无重叠、截断或布局漂移。

## 会话：2026-08-09（Windows 运行时修复与阶段 9 启动）

- 修复 Windows Release 未注册 `file_selector_windows` 与 `desktop_drop` 的问题；正常执行插件生成并重新构建 Release。
- 初始化页现在捕获目录选择器异常并显示错误；新增对应 Widget 回归测试。
- Windows Runner 通过命名 Mutex 实现单实例，重复启动会恢复并激活已有窗口。
- 新增 `tool/windows_release_smoke.ps1`，真实验证插件 DLL、存储根目录对话框和单实例恢复；GitHub Release 构建增加插件打包检查。
- 验证结果：Flutter analyze 0 问题，26/26 测试通过，Windows Release 构建和三项真实 EXE 冒烟检查通过。
- 阶段 9 开始：下一纵向切片为资源退出管理，先实现恢复原路径、冲突保护、日志与撤销，再扩展指定位置和 Windows 回收站。

## 会话：2026-08-09

### 阶段 7：现状审计与需求校对
- **状态：** in_progress
- 用户要求先分析当前开发现状并整理、校对需求，确认后再开发。
- 已读取 `setup-matt-pocock-skills` 与 `planning-with-files-zh` 的完整说明。
- 本轮重新读取并执行用户指定的 setup 技能探索流程；确认其写入前必须先由用户选择 issue tracker，并在 `AGENTS.md` / `CLAUDE.md` 均不存在时选择要创建的文件。
- 已恢复既有规划上下文，确认此前已完成竞品研究、产品方案和 Flutter Windows MVP；本轮尚未修改业务代码。
- session-catchup 报告上一轮规划日志之后存在 19 条未同步上下文；已复核 `git diff --stat`、三份规划文件和当前仓库状态，未发现已跟踪文件差异，仓库仍无首个 commit。
- setup 技能探索初步发现：仓库没有远程地址、没有 `AGENTS.md`/`CLAUDE.md`、没有既有 agent/domain 文档，也未安装 `triage` 技能；仓库为单包 Flutter 项目。
- 已用当前 `python` 成功运行 session-catchup；它报告 1 条未同步工具记录，已通过 `git diff --stat` 和规划文件复核恢复。
- 已初步核对 README、依赖、模型、控制器、存储、UI、测试与产品方案索引，确认当前产物定位应为“标签语义与桌面交互原型”，而非方案中定义的完整 Windows 核心 MVP。
- 已完成控制器、存储与现有测试的逐项能力盘点，并记录搜索、最近/常用、备份可靠性和测试覆盖缺口。
- 已再次从代码核对需求草案：`pubspec.yaml` 无业务依赖，`LocalStore` 直接覆盖 JSON，首次启动加载 demo 数据，Quick Tag 仅为窗口内快捷键，UI 的“打开”只记录事件，恢复前备份仅封装在 UI 调用链中。
- 已确认“最近”顺序偏差的具体调用链：事件先按 `occurredAt` 形成资源集合，`visibleResources` 随后仍按资源 `modifiedAt` 排序。
- 读取 `domain-modeling` 技能并据此区分资源、空间、标签实体、标签位置、直接标注、有效标签、原地索引和物理整理；术语尚待用户确认，因此未创建 `CONTEXT.md`。
- 创建 `docs/TAGTAG-requirements-audit-draft.md`，逐条审计 15 项需求，提出 P0/P1 基线和 9 个高影响确认问题。
- 本轮基线复验：通过 Flutter 工具快照运行 `analyze --no-pub`，0 个问题；运行 `test --no-pub`，4/4 测试通过。
- 用户确认当前 issue tracker 采用本地 Markdown；后期目标是通过 GitHub Actions 编译版本化产物并发布 GitHub Releases，具体发布规则留待 CI/CD 实施前确认。
- 用户确认创建 `AGENTS.md`；已完成 setup 配置，创建 `AGENTS.md`、`docs/agents/issue-tracker.md` 和 `docs/agents/domain.md`。当前未安装 `triage` 技能，因此未创建 triage 标签配置。
- 用户校正核心存储需求：必须初始化存储根；资源包含文件和文件夹；默认复制、可选移动；管理范围内只维护一个物理实体，其余位置用虚拟引用；文件名按设置/业务规则决定；不需要预览和独立物理整理，需要操作日志与撤销。
- 根据已确认术语创建 `CONTEXT.md`，并改写需求审计中的存储模型、P0/P1、排除项和待确认问题；本轮未修改业务代码。
- 用户确认全局存储根模型：应用只有一个物理存储根，多个标签空间为可共享受管实体的逻辑视图；已同步领域词汇和需求矩阵。
- 用户确认资源生命周期：合法未标注资源进入独立待整理区；清标签不移动资源；退出管理可恢复先前路径、移动到指定位置或按平台规则删除（Windows 回收站）；全部记录日志并支持撤销。已同步 `CONTEXT.md` 和需求草案。
- 用户确认恢复路径冲突绝不覆盖，并要求持续监控存储根的非 TAGTAG 结构变更：新增内容告警后接管或移出，外部删除告知异常。已加入一致性告警、接管和缺失资源语义。
- 用户确认监控处理策略：内容修改不告警；外部改名/移动可接受新路径或恢复记录路径；异常删除保留缺失资源记录直至重新定位或清除。
- 用户确认复制导入后不再跟踪或同步外部源资源，存储根内版本是唯一受管版本；已更新领域词汇和 P0 基线。
- 用户确认文件名规则：默认保留、标签不改名、显式操作或命名规则才改名；冲突按操作系统父目录作用域处理，不同文件夹允许同名。
- 用户确认备份语义：全局备份用于完整恢复；空间导出包包含空间元数据及引用资源并支持去重导入；仅标签配置为“空间模板”。
- 用户校正标签多路径语义：唯一标签的全部位置共享资源集合，独立同名标签仅名称相同、身份和资源隔离；已记录当前 `placementId` 筛选与该规则的实现偏差。
- 用户确认标签创建默认不唯一；唯一标签只能通过显式复用形成，后续身份变化使用可预览、可撤销的合并/拆分操作。
- 用户确认文件夹标签继承规则：默认不继承；显式继承为动态有效标签并显示来源；批量直接标注作为固定结果的独立命令。
- 用户确认统一导入并标注交互：Quick Tag、Explorer 右键、主窗口拖入和可选悬浮球拖入共用单窗口流程，复制/移动与标签一次确认，取消不产生导入。
- 用户确认零标签导入合法：确认后资源进入待整理区，取消才表示整体不导入；已新增待整理区空间范围等后续校对问题。
- 用户确认未标注按空间计算，并提供所有空间均无有效标签的全局待整理视图；已将空间成员关系与标签关系分离。
- 用户确认导入目标目录规则：在同一窗口选择存储根内目录，允许新建，文件夹保留完整层级，标签层级与物理目录独立。
- 用户要求初期考虑全局内容寻址/透明去重，并确认同内容的不同来源仍可作为独立逻辑资源；已用 `codebase-design` 将存储模块的核心分界调整为“逻辑资源 / 内容对象”，具体写时复制与物理投影待确认。
- 用户确认首个核心可用版本实际启用内容寻址与透明去重，不只预留能力；已提升为 P0 存储约束。
- 本轮按 `planning-with-files-zh` 执行会话恢复；`git diff --stat` 仍为空，`git status --short` 显示仓库文件全部未跟踪，没有需要合并的已跟踪改动。
- 用户再次确认首个核心可用版本启用全局内容寻址与透明去重；下一项校对转向共享内容对象被编辑时的隔离语义。
- 用户确认共享内容采用写时复制：编辑一个逻辑资源不得改变其他共享者；新内容继续去重，旧内容按逻辑引用、撤销和备份保留状态决定是否回收。已同步领域词汇和 P0 验收约束。
- 用户选择首版保留存储根内可直接编辑的 Windows 普通文件，不做临时工作副本或虚拟文件系统；其他组织位置采用索引，必要时为快捷方式或链接。已记录其与共享内容写时复制之间的待决冲突。
- 用户撤销此前的全局内容寻址、透明去重、内容对象共享和写时复制要求。新基线为一个受管实体对应存储根中的一个具体路径，直接编辑该文件；相同内容的不同路径不合并，多标签/多空间仅共享受管实体记录。此前本日志第 39、40、42、43、44 条中的去重与冲突结论均由本条替代。
- 用户确认首版检索仅覆盖名称、受管路径、标签和基础元数据，不读取或索引文件正文；已同步领域词汇和 P0 验收范围。
- 用户确认删除标签位置时默认提升子位置，保留其他位置与资源标注；最后一个位置转入标签实体删除确认，删除子树作为独立高影响命令。已同步领域词汇和验收约束。
- 用户确认删除标签实体会移除当前空间内该实体的全部位置、标注与继承规则并提升子位置，但不触碰资源文件或空间成员关系；无有效标签的资源进入空间待整理区。已同步领域词汇和验收约束。
- 用户确认继续 Flutter 技术路线，Windows 系统能力采用最小原生桥接，Explorer Shell 扩展保持为独立小组件，不迁移到 .NET UI 技术栈。已同步技术约束。
- 用户确认里程碑 1 先交付受管存储核心，里程碑 2 再交付系统 Quick Tag、Explorer 右键、悬浮球和托盘；随后明确授权开始开发，并要求尝试推送到 `git@github.com:yuesewuta/TAGTAG.git`。
- 阶段 7 需求校对已完成，阶段 8 开发进入进行中；当前仓库无 commit、无 remote，分支为 `master`，全部文件未跟踪。推送前将先检查远程历史，不使用强制推送。
- 本轮开发采用 `planning-with-files-zh`、`tdd`、`karpathy-guidelines` 和 `codebase-design`；TDD 要求先由用户确认公共测试 seam，因此确认前只进行只读代码审计和远程检查。
- 用户先表示不需要 SQLite，随即澄清数据库可用于索引和元数据建表；最终约束为 SQLite 不接管资源文件本体。受管文件必须在存储根中保持原始、未加密且可直接编辑，严禁数据库 BLOB 或应用容器。文档按最终表述更新。
- 首次开发代码清单确认实际文件为 `lib/models/tag_models.dart`、`lib/state/tagtag_controller.dart`、`lib/data/local_store.dart` 和 `test/tag_models_test.dart`；按摘要猜测的 5 个扁平路径读取失败，已记录且不再重复。
- 代码审计确认 `LocalStore` 自动加载 demo、非原子 JSON 与控制器“先通知后保存”是存储 seam 的主要替换点，`TagResource.spaceId` 也不满足已确认的跨空间成员关系。
- 已将用户指定地址添加为 `origin` 并只读获取 `origin/main`；远程 HEAD 为 `b7b8490`，本地尚未合并或推送。
- 用户确认 TDD 公共 seam：核心测试通过 `ManagedLibrary`，使用真实临时文件系统与正式 SQLite 元数据适配器；标签领域和 Windows 平台适配器分别测试。开始第一个初始化/重启红绿切片。
- TDD 切片 1 完成：`ManagedLibrary.initialize/open/listResources/close` 在真实临时存储根与正式 SQLite 上通过；新库为空且可重开，元数据位于 `.tagtag/tagtag.sqlite`，未引入资源内容列。
- TDD 切片 2 完成：默认复制导入保留源文件，在存储根写入字节完全一致的普通文件，并只将相对路径和基础元数据写入 SQLite；目标目录逃逸与同名覆盖由模块拒绝。
- 移动导入首次绿灯验证时，文件行为正确但测试期望保留了混合路径分隔符；正式模块存储规范化 Windows 原路径以支持可靠恢复，测试已改为验证规范化等价路径。
- TDD 切片 3 完成：移动导入使用复制、事务登记、删除源与失败补偿流程；成功后源消失、目标仍是原始普通文件，规范化原路径保存在元数据中。
- TDD 切片 4 完成：文件夹复制导入保留文件夹本身、空目录和完整内部层级；符号链接首版明确拒绝，避免无意导入存储根外内容。
- TDD 切片 5 完成：复制导入写入持久操作记录；撤销先把受管内容移入元数据暂存区，再提交资源删除和 `undoneAt`，失败可原位恢复，外部源文件不受影响。
- TDD 切片 6 完成：移动导入撤销在原路径存在任意同名内容时先行失败，不改变冲突文件、受管文件、资源记录或操作状态，绝不自动覆盖。
- TDD 切片 7 完成：移动导入在原路径空闲时可安全撤销；受管内容经暂存恢复到原路径，资源记录移除、日志标记已撤销，失败时具备双向文件补偿。
- TDD 切片 8 完成：一致性扫描忽略正常内容编辑和内部 `.tagtag`，将外部新增与受管缺失分别写入持久告警；受管文件夹内部内容作为同一资源处理。
- TDD 切片 9 完成：基础备份通过 SQLite 在线备份生成一致性元数据快照，复制原始资源层级并写 manifest；仅在全部成功后原子改名为正式备份，缺失资源会使备份失败。
- UI 接入前的生产启动红灯确认旧 `LocalStore` 会注入 demo；测试 fixture 已改为显式保存 demo，生产缺省行为开始切换为空资料库。

## 会话：2026-08-07

### 阶段 1：范围与证据收集
- **状态：** complete
- **开始时间：** 2026-08-07
- 执行的操作：
  - 完整读取 planning-with-files-zh 技能和三个模板。
  - 检查工作区、规划文件与 Git 状态，确认目录为空且不是 Git 仓库。
  - 固化用户的 15 项需求、关键问题、证据标准和初始模型判断。
  - 通过卸载注册表、快捷方式和进程确认本机 tagLyst Next V4.752。
  - 使用 Playwright 浏览 localtags 官方 GitHub 仓库并提取 README、活跃度和技术信息。
  - 浏览 TagSpaces 官方仓库，确认当前活跃度、跨平台架构、规模限制与许可边界。
  - 定位 TagSpaces 官方标签文档，准备核对文件/文件夹标签、存储方式和标签组语义。
  - 核对 TagSpaces 文件名/sidecar 两种标签存储、文件夹 sidecar、批量与拖放标注能力。
  - 核对 TagSpaces 标签组、颜色、JSON 导入导出、名称限制和 location tags；确认标签组是单层分类而非无限嵌套。
  - 核对 TagSpaces 搜索权重、标签布尔查询、范围过滤、搜索历史和保存查询。
  - 启动 DeClutter 同名 GitHub 仓库定位。
  - 依据 GitHub 搜索结果将 midnightdim/declutter 暂定为用户所指 DeClutter，并排除语义不符的 DesktopShelves 结果。
  - 核对 DeClutter 的规则引擎、文件/文件夹标签器、互斥标签组、预览、拖放、技术栈和维护状态。
  - 查看 DeClutter 完整源码树，确认 SQLite、sidecar、规则模块与测试布局。
  - 阅读 DeClutter sidecar 实现，确认 `.dc` JSON 按名称保存标签、外部移动失配和损坏元数据被直接删除的风险。
  - 阅读 DeClutter schema v2，确认规则使用 tag_id，但旧数据导入仍按标签名全局合并，并记录其 dry-run/保留目录等规则选项。
  - 阅读 DeClutter tags API，确认名称仍是主要语义键、同名改名会合并、对象用路径+快速指纹重定位。
  - 检查本机 tagLyst 安装树与示例库，确认 Electron、文件名 `#标签`、`$$TGL.DATA` 空间元数据、`.tglnk` 和多种视图资源。
  - 读取 tagLyst 自带 readme、tagDB、superTagDB 和资料库配置，分析其嵌套、互斥组、最近使用、样式、别名与名称键限制。
  - 从示例目录确认 tagLyst 支持给文件夹添加多个 `#标签`。
  - 使用结构化 JSON 解析统计 tagLyst 示例标签/组，并检查 app.asar 文件清单、托盘/启动/Windows 集成与预览相关依赖。
  - 检查 Windows 常见 shell 注册表位置，未发现 tagLyst 文件/目录右键菜单注册。
  - 选择性提取并搜索 tagLyst 主进程/托盘/设置文件，确认全局快捷键、clipAgent 快速窗口、后台隐藏和旧 Electron 安全配置。
  - 打开 tagLyst 官方语雀上手指南。
  - 枚举 tagLyst 官方指南的 12 个主题并进入“文件标签维护”。
  - 核对 tagLyst 预设/自动/批量标签、同义词/正则/屏蔽标签、互斥组、多级标签、继承、多分组和跨资料库引用语义。
  - 进入 tagLyst 官方“文件筛选检索”文档。
  - 核对 tagLyst 组合筛选、Exact/AND/OR/NOT 语义、系统标志和文件夹标签向下继承规则。
  - 进入 tagLyst 官方“辅助及便捷功能”文档。
  - 核对 tagLyst 便捷功能中的快捷键、暗色模式、单实例/多开，并进入“资料库管理”。
  - 核对 tagLyst 多资料库、原地挂载/移除、文件名标签警告、空间级分隔符与防误触锁。
  - 进入 tagLyst 官方同步与协作文档。
  - 核对 tagLyst 基于 SMB/云盘/文件同步工具的协作方式、UNC 支持及并发一致性文档缺口。
  - 进入 tagLyst 官方“文件基本操作”文档。
  - 核对 tagLyst 实体移动/复制、引用/URL、五种视图、子目录、多选排序、文件操作和大幅预览。
  - 进入 tagLyst FAQ，准备核对备份恢复与路径问题。
  - 从会话恢复记录补齐 tagLyst FAQ 的单库 5,000 至 10,000 文件建议、整库迁移保留元数据和 `.bak` 保护边界。
- 创建/修改的文件：
  - task_plan.md
  - findings.md
  - progress.md
  - docs/TAGTAG-research-and-product-design.md

### 阶段 2：竞品功能分析
- **状态：** complete
- 已开始按用户 15 项需求整理四款产品能力矩阵，并区分“已验证、部分支持、未见官方证据、明确冲突”。
- 完成四款产品的定位、优点、限制和可借鉴点分析。
- 完成逐项 15 项能力矩阵，未知能力均保留“未见证据”口径。

### 阶段 3：TAGTAG 逻辑与数据模型
- **状态：** complete
- 形成“标签实体 + 标签位置 + 直接标注 + 有效标注”四层语义。
- 设计空间、资源、路径历史、标签位置、标注、查询、使用事件、操作日志和备份记录模型。

### 阶段 4：技术架构与交互方案
- **状态：** complete
- 形成 Explorer 式主界面、Quick Tag、全局快捷键和 Explorer 右键流程。
- 形成 Agent 单写者、WinUI App、Shell Bridge、SQLite、索引 Worker 和命名管道架构。
- 定义默认不移动文件、显式物理整理、崩溃恢复、一致性备份和迁移规则。

### 阶段 5：验证与交付
- **状态：** complete
- 输出 `docs/TAGTAG-research-and-product-design.md`，包含竞品分析、15 项矩阵、无冲突标签模型、UI、数据表、Windows 架构、恢复、备份迁移和实现路线。
- 结构复核结果：15 个矩阵需求行齐全；Markdown 围栏为偶数；2 个 Mermaid 图存在；关键身份、Windows 集成、恢复和备份术语均已覆盖。

### 阶段 6：Flutter MVP 设计与实现
- **状态：** in_progress
- 用户提供 Flutter SDK：`D:\Documents\codeSpace\calto\flutterSDK\flutter`。
- 已验证 Flutter 3.44.6 stable、Dart 3.12.2 可运行。
- MVP 范围：JSON 持久化的标签空间、资源、标签实体/位置、标注、筛选、最近/常用和备份；Windows 全局热键与 Explorer 右键保留为原生桥接阶段，避免不真实的跨平台占位实现。
- 已实现 Flutter MVP 的模型、控制器、本地 JSON 存储和 Explorer 式三栏界面；测试将覆盖核心标签语义和备份往返。
- `flutter analyze`：通过，0 个问题。
- 直接调用 Flutter 工具快照运行 `flutter test`：4/4 通过，覆盖同一实体多路径、独立同名、父/子直接标注去重、清标签不改路径和备份往返。
- 最终复检：`dart format --output=none --set-exit-if-changed lib test` 为 0 处改动；`flutter analyze` 退出码 0；`flutter test` 退出码 0、4/4 通过。
- Windows 调试构建启动到 `windows-x64-debug/windows-x64-flutter` 引擎准备步骤；进程与 Google CDN 建立连接但未下载任何引擎文件，未生成 `tagtag.exe`，已停止该外部依赖受阻的构建进程。
- 将生成的 README 更新为当前功能、数据目录、运行命令、真实边界和后续原生集成说明。
- Flutter 预缓存改用 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`，Windows debug、profile、release 引擎和 C++ wrapper 均下载成功，命令退出码 0。
- Windows debug 构建完成：CMake/MSBuild 0 警告、0 错误；产物 `build\windows\x64\runner\Debug\tagtag.exe`（1,267,200 bytes）及 `flutter_windows.dll` 已验证存在。

## 测试结果
| 测试 | 输入 | 预期结果 | 实际结果 | 状态 |
|------|------|---------|---------|------|
| 工作区检查 | 根目录 | 识别现有项目状态 | 空目录、非 Git 仓库 | 通过 |
| 需求矩阵完整性 | 报告第 4 节 | 覆盖用户 15 项需求 | 正好 15 行 | 通过 |
| Markdown 结构 | 最终报告 | 围栏成对、章节完整 | 8 个围栏、15 个一级编号章节 | 通过 |
| 关键语义覆盖 | 最终报告 | 同一/不同 C、直接/有效标注、恢复和 Windows 集成均有定义 | 关键术语检索全部命中 | 通过 |

## 错误日志
| 时间戳 | 错误 | 尝试次数 | 解决方案 |
|--------|------|---------|---------|
| 2026-08-07 | session-catchup 自动权限审核超时 | 1 | 改用已配置 Python 路径重试 |
| 2026-08-07 | 原规划环境中的 conda Python 路径失效 | 2 | 使用 D:\miniconda3\python.exe 成功运行恢复脚本；后续不再使用旧路径 |
| 2026-08-07 | session-catchup 中文输出乱码 | 1 | 读取可辨识结构并将结论以 UTF-8 记录 |
| 2026-08-07 | git status：非 Git 仓库 | 1 | 记录环境事实并继续 |
| 2026-08-07 | 追加 TagSpaces 发现时补丁上下文不存在 | 1 | 读取当前文件并按实际上下文应用新补丁 |
| 2026-08-07 | 当前 PowerShell 不支持 ConvertFrom-Json -AsHashtable | 1 | 改用 PSObject.Properties 做结构化解析 |
| 2026-08-07 | 规划技能 `check-complete.ps1` 因自身编码损坏无法解析 | 1 | 不重复执行；改用状态检索、矩阵计数和围栏计数验证 |
| 2026-08-07 | 当前无界面环境中的 Windows `flutter_tester` 在 widget 首帧后不退出 | 1 | 停止本工作区残留测试进程；移除不可靠的 widget 用例，保留可重复通过的模型/持久化测试，并使用 Windows 调试构建验证 UI 编译链接 |
| 2026-08-09 | `flutter.bat analyze` 在批处理启动层持续无输出，且无 Dart/Flutter 子进程 | 1 | 终止该会话；改用 SDK 内 `dart.exe flutter_tools.snapshot analyze --no-pub`，分析成功 |
| 2026-08-09 | 沙箱内 Flutter 工具无法写 SDK `bin/cache/lockfile` | 1 | 经受控权限批准后重跑同一工具快照命令，分析和测试均成功 |

## 五问重启检查
| 问题 | 答案 |
|------|------|
| 我在哪里？ | 阶段 5 已完成，准备交付 |
| 我要去哪里？ | 用户确认方向后可进入语义原型和项目脚手架实现 |
| 目标是什么？ | 形成可核验、无显著逻辑冲突的 TAGTAG 产品与技术方案 |
| 我学到了什么？ | 见 findings.md |
| 我做了什么？ | 已完成调研、矩阵、模型、架构、路线与验证文档 |

---
*每个阶段完成后或遇到错误时更新。*

## 会话：2026-08-09（受管存储 UI 接入）

- 用户确认公共测试 seam：`ManagedLibrary`、标签领域接口、独立 Windows 平台适配器。
- `ManagedLibrary` 当前 10 个测试通过，覆盖初始化、复制/移动导入、文件夹层级、导入撤销、冲突保护、一致性扫描、备份和存储根配置恢复。
- 已安装 `file_selector 1.1.0` 与 `desktop_drop 0.7.1`，用于存储根选择、文件/文件夹选择和主窗口拖入。
- Flutter 依赖解析提示 Windows 插件构建可能需要启用 Developer Mode；将在 Windows 构建阶段实测并记录结果。
- 当前工作进入控制器资源同步、初始化门禁和真实导入的 TDD 纵向切片。
- 标签领域新增 4 个行为测试：受管资源跨启动恢复、唯一标签多路径共享资源集合、删除单个标签位置提升子项并保留标注、导入并标注按标签实体去重；标签领域测试增至 9 个。
- 启动层已接入 `LibraryLocator`：未配置或无法打开存储根时只能进入初始化页面，初始化成功后才创建 `ManagedLibrary` 与主控制器。
- 主窗口旧的任意路径登记入口已移除；文件选择、文件夹选择和 `desktop_drop` 拖入共用单窗口导入流程，可同时确认复制/移动、存储根内目录和可为空的标签集合。
- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub`：通过，19/19。
- Windows debug 构建首次因 Developer Mode 未开启而无法创建插件符号链接；在工作区生成目录使用两个目录联接指向 Pub 缓存后构建通过，产物为 `build/windows/x64/runner/Debug/tagtag.exe`。
- 使用隔离 `APPDATA` 和真实窗口句柄验证 1280x720 首次初始化页及已初始化主窗口，均无空白、重叠或文本截断；截图位于 `build/ui-initialization-window.png` 和 `build/ui-main-window.png`。
- 新增待整理视图、操作日志与导入撤销 UI、15 秒一致性扫描告警、完整备份目标选择、Windows 打开/定位适配器。
- 资源空间关系从单一 `TagResource.spaceId` 迁移为独立 `SpaceMembership`，状态格式升级为 version 2，并兼容迁移 version 1 JSON。
- 删除标签位置与删除标签实体已分流：多位置只删当前位置并提升子项；最后一个位置删除实体但保留资源和空间成员。
- 新增 `.github/workflows/release.yml`：手动构建上传 artifact，`vMAJOR.MINOR.PATCH` 标签构建对应 Windows 版本并发布 GitHub Release。
- 发布前最终结果：`flutter analyze --no-pub` 0 问题，`flutter test --no-pub` 25/25，Windows Release 构建成功，Release 主窗口 1280x720 视觉验证通过。
- Git 基线已建立：功能提交 `717c124`，合并远程初始历史提交 `50e3014`；`origin/main` 是当前分支祖先。
- 已非强制推送 `codex/managed-storage-core` 到 `git@github.com:yuesewuta/TAGTAG.git` 并建立上游跟踪。

## 会话：2026-08-09（资源退出管理）

- 继续阶段 9，首个纵向切片限定为“恢复到先前路径退出管理”。
- 已在 `ManagedLibrary` seam 添加首个行为测试：成功恢复后资源离开存储根、受管记录删除，并写入 `exitRestore` 操作日志。
- 首次运行单测被沙箱阻止写入 Flutter SDK `bin/cache/lockfile`；这是环境权限限制，需用受控权限重跑同一命令后再判断红灯原因。
- 红灯确认缺少 `restoreToOriginalPath` 和 `ManagedOperationType.exitRestore`；已实现 schema v2、v1 操作表迁移和带文件补偿的恢复退出流程，单个行为测试通过。
- 原路径同名冲突保护测试通过：冲突内容、受管内容、资源记录和操作日志均保持不变。
- 添加撤销退出测试时首次补丁因 Dart 格式化后的多行测试声明与旧上下文不匹配而失败；没有产生部分修改，已按当前文件上下文重试。
- 撤销 `exitRestore` 的红灯为“受管资源记录已不存在”；新增独立撤销分支后测试通过，资源恢复到原受管路径并保留资源 ID，外部恢复项被移除。
- 检查持久化实现时误读不存在的 `lib/data/app_state_store.dart`；实际存储类位于 `lib/data/local_store.dart`，后续只使用实际路径。
- 首次编译控制器退出测试时遗漏 `toggleResourceSelection` 的布尔参数；已按公开接口补为 `true` 后重跑，不把测试代码错误当作产品红灯。
- 控制器退出管理测试先因缺少公开命令变红；实现 `restoreResourceToOriginalPath` 并让资源同步同时清理资源使用记录后变绿，标签、空间成员、选择和资源历史均不再留下悬空引用。
- 撤销退出关系测试按预期因直接标签缺失变红；操作日志新增 `context_json` 元数据快照后变绿，应用重启后仍具备恢复标签、空间成员和资源使用记录所需的信息。
- 插入文件夹与 v1 迁移回归测试时再次使用了被 formatter 改写的长测试声明作补丁锚点，匹配失败且无部分修改；已改用稳定的下一测试标题作为锚点。
- 检查器已接入单资源“恢复先前路径并退出管理”确认命令；操作日志用完整类型分支区分复制导入、移动导入和恢复原路径退出。
- `ManagedLibrary` 测试 15/15 通过，新增覆盖文件夹完整层级的退出/撤销与 schema v1→v2 迁移。
- 全套 Flutter 测试 33/33 通过；Windows Release 构建成功，插件打包、目录选择器和单实例恢复冒烟检查全部通过。
- 首次用 `CopyFromScreen` 捕获 Release 窗口时，前台游戏阻止 `SetForegroundWindow`，截图实际是被遮挡的桌面内容，不能用于布局结论；改用按 TAGTAG 窗口句柄执行 `PrintWindow`。
- `PrintWindow` 捕获的 1280×720 主窗口及选中资源检查器验证通过；“恢复先前路径并退出管理”按钮完整可见，无文字截断、布局重叠或动态位移。
- 已创建 `d4d8616`（Windows 插件、目录选择与单实例修复）和 `931ba63`（恢复原路径退出管理）两个提交，并非强制推送到 `origin/codex/managed-storage-core`。

## 会话：2026-08-09（文件打开修复与主界面重构）

- 用户报告三个真实 TXT 中只有 `test.txt` 可双击打开，并确认操作日志正常；同时要求展开资源行操作、增加设置、降低清标签按钮显著性，以及重构可折叠左侧主导航。
- 已按 `diagnosing-bugs` 建立真实路径反馈环：三个资源都存在、可读取且同为 Nextcloud reparse point；现有 ASCII 假启动单测不足以捕获真实文件名模式。
- 当前实现的真实命令反馈环已复现：`test.txt` 创建 `test.txt - Notepad` 窗口，两个包含中文的文件 URI 均未产生新进程或窗口。
- 最小文件名矩阵首次因当前 PowerShell `New-Item` 不接受 `-LiteralPath` 而未创建临时目录；未执行产品调用，改用 .NET `Directory.CreateDirectory` 后重跑。
- 修正后的最小矩阵稳定复现：ASCII+空格成功，中文无空格和中文+空格均失败；已排除参数空格和 Nextcloud reparse point。
- 只将启动通道改为 `explorer.exe` 原始绝对路径后，三个真实 TXT 均打开名称匹配的 Notepad 窗口，根因与替代方案均已验证。
- 中文路径回归测试先红于 `rundll32.exe`，将 `open()` 改为 `explorer.exe` 原始规范化路径后，Windows 文件操作测试 3/3 通过；定位行为保持 `/select,` 不变。
- 主界面重构方案确定：64/276px 可折叠导航、六个固定入口、持久化默认导入方式、资源行直接操作，以及降级后的清标签入口。
- 设置持久化测试先红于缺少偏好接口；新增独立 `preferences.json` 后变绿，控制器已加载并保存默认导入方式与导航折叠状态。
- 首次合并修改资源行和检查器的补丁因远距离枚举上下文不匹配而失败，无部分修改；改为按表头、资源行、检查器三个稳定锚点分别应用。
- 主界面首轮静态分析仅报告导航重构后 `_CommonTags` 成为未引用组件；已删除该死代码后重跑。
- 文件打开修复、偏好持久化与主界面重构完成后，`flutter analyze --no-pub` 为 0 问题，全套测试 35/35 通过。
- Windows Release 重新构建成功；插件打包、存储根选择弹窗和单实例恢复三项冒烟检查全部为 GREEN。
- 在实际 1280×720 Release 资源列表中逐行双击三个受管 TXT，均打开名称完全匹配的 Notepad 窗口，确认真实 UI 调用链不再受中文文件名影响。
- `PrintWindow` 验证了 1280×720 展开导航、折叠导航、设置弹窗、选中资源检查器，以及 960×720 展开/折叠布局；未发现按钮遮挡、文本溢出或不连贯重叠。
- 设置中的导航折叠选项经保存、关闭和重启后仍生效；随后通过导航展开按钮恢复 `navigationCollapsed: false`，未改变用户原有默认导入方式。
- 清除全部直接标签入口已在选中带标签资源时确认：仅显示为“直接标签”标题旁的次要图标，确认流程和不移动文件的语义保持不变。

## 会话：2026-08-09（导航与资源视图语义校正）

- 用户确认上一轮文件打开修复有效，但校正导航、搜索、导入、标签层级、选择和检查器的交互语义。
- 本轮使用 `diagnosing-bugs` 为连续单击错误累积多选建立行为反馈环，并用 `planning-with-files-zh` 跟踪完整 UI 重构。
- 首次运行 session-catchup 仍引用已删除的旧 Python 路径而失败；已记录并将改用 `Get-Command python` 解析当前解释器。
- 实现边界确定：左栏只负责页面导航和宽度切换；标签空间与导入移到全局右上角；标签层级成为主内容树状资源页；检查器移除；批量选择由显式模式进入。
- 已用 `Get-Command python` 解析到 `C:\Python314\python.exe` 并成功运行 session-catchup；只报告本轮 2 条未同步工具记录，中文输出乱码已记录但不影响结论。
- 代码初查确认普通资源行点击直接调用 `toggleResourceSelection`，该接口按集合增删，因而连续单击天然累积选择；修复需要把单选与显式多选模式拆成不同命令。
- 已列出四个可证伪假设；代码调用链排除点击间隔和仅复选框冒泡，首要根因为普通行点击复用了集合 toggle。下一步先添加“单选替换、显式多选累积”的控制器回归测试。
- 单选回归测试已在修复前按预期红灯：`TagTagController` 不存在 `selectResource`，证明当前没有普通单选接口；测试命令可快速、确定性捕获该缺口。
- 完成 UI 结构核对：展开侧栏目前混入空间切换和标签树，顶部命令栏混入重复搜索与折叠导入，检查器承载资源动作；这些正是本轮需要重新划分的三个责任边界。
- 新增 `ResourceView` 主内容视图枚举、`selectResource` 普通单选命令和 `resourcesForPlacement` 标签实体资源查询；旧偏好文件可继续读取，但导航折叠字段已从偏好模型移除。
- 单选替换/显式多选累积测试与唯一标签多路径资源集合测试均已转绿，领域层反馈环完成。
- 首个同时覆盖窗口骨架、AppBar 和内容页的大补丁因 AppBar 上下文锚点不匹配而失败，没有产生部分修改；后续改为按四个稳定区块分别编辑，不重复原补丁。
- AppBar 子补丁首次仍误用了 `], actions:` 闭合锚点而失败；读取实际 `Row` 闭合后改为 `), actions:`，随后成功迁入空间切换、文件导入和文件夹导入命令。
- 主窗口已改为 64/220px 本地折叠导航加单一主内容区，移除常驻搜索命令栏和检查器布局；资源页已接入独立搜索、多选模式和五个行内动作，标签层级页已接入递归节点骨架。
- 展开导航现只显示六个入口的文字，不再包含空间下拉或标签树；标签空间切换和文件/文件夹导入已作为右上角直接命令。
- 标签层级页按标签实体显示资源数量，根节点默认展开，子节点可动态展开；普通列表与层级资源行均直接显示打开、定位、添加标签、清标签、恢复退出五个动作。
- 已删除检查器及紧凑模式底部检查器；设置弹窗只保留存储根与默认导入方式。
- Dart 格式化完成，`flutter analyze --no-pub` 为 0 问题。
- 全量 Flutter 测试 37/37 通过；Windows Release 构建成功，插件打包、目录选择和单实例三项冒烟检查均为 GREEN。
- `PrintWindow` 验证了 1280×720 折叠/展开全部资源、标签层级页和 960×720 紧凑全部资源；未发现右上角溢出、资源动作遮挡或文字重叠。
- 明确顺序验证“全部资源 → 折叠 → 展开”后仍停留在全部资源页面，导航宽度与页面状态已解耦。
- 真实 UI 连续点击回归通过：普通模式只保留后一项选择；显式多选模式显示复选框并同时选中两项，顶部正确显示已选数量与批量标签命令。
- 独立搜索页在 960×720 下通过视觉检查，搜索框不再常驻品牌下方；设置弹窗确认只保留存储根和默认导入方式。

## 会话：2026-08-09（一致性告警处理）

- 阶段 13 已进入未跟踪内容处理；接管操作保留原始字节位置，只新增受管记录与持久操作日志，撤销后重新成为未跟踪内容。
- “移出未跟踪内容”定向测试按预期红灯：缺少 `moveUntrackedOutside` 公共接口和 `untrackedMoveOut` 操作类型；未出现其他编译错误。
- 首次组合补丁因 `progress.md` 锚点与实际文件末尾不一致而整体未应用；拆分为存储层与进度日志两个补丁后继续，未产生部分代码修改。
- 首次绿灯运行发现夹具移动 `incoming/folder` 后仍保留合法空父目录 `incoming`，一致性扫描正确将父目录报告为未跟踪；产品不应静默删除用户文件夹，测试改为移动存储根直属目录后继续。
- 未跟踪文件夹移出存储根、写入持久日志和撤销回原路径的定向测试已通过；撤销后不创建受管记录，内容重新进入一致性告警。
- “接受外部移动”测试按预期红灯：缺少 `acceptExternalMove` 公共接口和 `externalMoveAccept` 操作类型；下一步只接受用户显式给出的缺失记录与未跟踪路径配对。
- 接受新路径首轮实现已运行；原夹具留下旧空目录并被扫描正确告警，因此将原资源改为存储根直属文件，隔离验证资源身份和路径记录更新，不引入隐式空目录删除。
- 显式配对后接受外部移动的定向测试已通过：只更新记录路径与元数据，保留稳定资源 ID；撤销恢复旧缺失记录，新路径内容不移动且重新成为未跟踪。
- “恢复记录路径”测试按预期红灯：缺少 `restoreExternalMove` 公共接口和 `externalMoveRestore` 操作类型；实现需搬回原记录路径并支持完整反向撤销。
- 恢复外部移动的大补丁首次因 formatter 改写了操作类型映射的换行锚点而整体未应用；改用枚举、公共方法、撤销方法三个小补丁按实际上下文落地。
- 恢复记录路径与反向撤销的存储层定向测试已通过；操作保持资源 ID，成功恢复后记录转为受管，撤销后再次标记缺失。
- 控制器一致性动作测试按预期红灯：缺少接管与接受新路径的公开接口；存储层行为本身已通过。
- 控制器一致性动作集成测试已通过：接管内容加入当前空间，接受外部移动后标签关系和稳定资源 ID 均保留。
- UI 已接入未跟踪内容“接管 / 移出”和缺失资源显式候选配对后的“接受新路径 / 恢复记录路径”，操作成功后在原对话框内重新扫描；操作日志已覆盖四种新类型。
- 扫描元数据回归测试复现旧实现未刷新正常编辑后的文件大小：预期 `11`，实际仍为导入时的 `7`；同时需持久更新资源 `managed / missing` 状态。
- 扫描现已在同一事务中刷新正常资源的大小、修改时间和 `managed` 状态，并把异常缺失记录持久标记为 `missing`；定向回归已通过。
- Windows Release 构建成功；因桌面上已有一个正在运行的 TAGTAG 实例，视觉验证改用隔离临时资料库的 960×720 widget 布局测试，不终止或复用用户进程。
- 隔离 UI 测试首次编译缺少 `flutter/material.dart`，导致 `Size / MaterialApp / SizedBox` 无法解析；已确认是测试代码导入问题并补齐后重跑。
- 960×720 隔离一致性对话框测试通过，两类告警与“接管 / 移出 / 接受新路径 / 恢复记录路径”全部可见，无 Flutter 布局异常。
- 新增两条覆盖保护回归：移出未跟踪内容不会覆盖外部目标，恢复记录路径不会覆盖后来占用的原路径；冲突双方内容和操作日志均保持不变。
- 阶段 13 最终验证：Dart 格式检查 0 改动，`flutter analyze --no-pub` 0 问题，全量测试 55/55，通过最终 Windows Release 构建，原生插件打包检查为 GREEN。
- 首次 `git add` 因沙箱禁止创建 `.git/index.lock` 而失败，工作区内容未受影响；改用受控 Git 写权限完成提交。

## 会话：2026-08-09（全局备份恢复）

- 用户要求继续功能开发，并明确后续 GitHub Release 需要提供 Windows 安装版；阶段 15 已记录安装版与便携版双产物要求。
- 阶段 14 先完成全局备份恢复闭环。恢复目标限定为新的空目录，先校验清单、SHA-256、SQLite 和标签状态，再通过临时目录恢复并切换应用存储根，不覆盖正在使用的资料库。
- 备份 v2 校验测试按预期红灯：缺少 `ManagedLibrary.validateBackup`；现有 v1 manifest 无法检测资源字节篡改。
- v2 manifest、路径安全、精确条目、SHA-256、SQLite `integrity_check` 和标签状态解析已实现；原始备份通过且篡改资源测试转绿。
- 全局恢复测试按预期红灯：缺少 `ManagedLibrary.restoreBackup`；下一步恢复到已验证为空的新目标根。
- 恢复实现首次编译误用了不存在的 `Stream.isNotEmpty`；测试未进入文件操作，改为对 `Stream.isEmpty` 结果取反后重跑。
- 全局备份恢复到新空根和非空目标拒绝测试均已通过；恢复后的 SQLite 可重新打开，资源 ID、目录层级和字节完整，一致性扫描为空。
- 控制器恢复元数据测试按预期红灯：缺少 `persistRestoredBackupMetadata`；完整备份还需加入用户设置文档。
- 完整备份现包含 `preferences.json`；恢复后的标签状态、空间关系、资源 ID 和默认导入设置持久化测试已通过。
- 恢复协调器和 UI 首轮静态分析仅报告一个未使用的 Windows 文件操作导入；接口类型实际由 `managed_library.dart` 提供，删除后重跑。
- 应用级恢复协调器测试已通过：成功恢复后全局根配置切换到新目录，控制器直接加载恢复的资源、标签关系和设置。
- 一次组合格式/分析工具调用因结果变量名写错未返回输出；改正编排变量后重跑，格式 0 改动、静态分析 0 问题。
- 960×720 UI 测试通过，顶部“备份与恢复”菜单同时显示创建和恢复入口；全量测试 58/58 通过。
- 阶段 14 Windows Release 构建完成，`data/app.so` 已更新，原生插件打包检查为 GREEN。

## 会话：2026-08-09（GitHub 安装版与便携版）

- 阶段 15 使用 Inno Setup 生成当前用户级 Windows x64 安装器，默认安装到 `%LOCALAPPDATA%/Programs/TAGTAG`，不需要管理员权限，卸载不触碰存储根和应用数据。
- GitHub Actions 已调整为同时生成便携 ZIP 和 `setup.exe`；CI 会分别解压检查便携包，并静默安装、检查插件打包、静默卸载安装版后才上传产物。
- 阶段 15 已由待处理校正为进行中；当前代码和 workflow 尚未提交。
- 两次静态校验不能作为有效结论：本机 Python 未安装 `PyYAML`；将整份 YAML 交给 PowerShell parser 只会把 YAML 语法误报为 PowerShell 错误。后续改为真正解析 YAML，并只逐段解析 `pwsh` 脚本块。
- 本轮 session-catchup 首次仍引用已删除的旧 Python 路径而失败；将通过 `Get-Command python` 使用当前解释器重跑。
- 曾根据工具输出中的 JSON 转义误判 Inno Setup 文件含双反斜杠；字符计数确认 `AppMutex` 和各路径原本均为正确的单反斜杠，安装脚本保持不变。
- 两次安装脚本组合补丁分别因字符串转义和模板字符串语法在应用前失败，均未产生文件修改；确认原假设错误后不再尝试该修改。
- 首次发布配置定向测试在 Dart 解析阶段发现测试辅助代码使用了不合法的尾反斜杠字符串，尚未执行任何产品断言；改用 `String.fromCharCode(92)` 明确表达单反斜杠。
- `dart.bat` 包装器在组合命令和单文件格式检查中两次无输出等待，均已中止；改用同一 Flutter SDK 内的 `dart.exe` 后立即返回真实结果。
- 发布配置定向测试首次执行时，YAML 解析和 Inno Setup 边界断言已通过；PowerShell 块遍历因测试代码把 `if-case` 与 `&&` 组合而发生运行时类型错误，改为先读取值再做普通 `is String` 判断。
- Flutter 命令无输出的根因是沙箱不允许写工作区外 SDK 的 `bin/cache/lockfile`；获得受控权限后，离线 `flutter pub get` 成功并将 `yaml` 固化为直接开发依赖。
- 修正测试辅助条件后，发布配置定向测试 2/2 通过：YAML 结构、双产物引用、安装/升级/卸载步骤、全部 PowerShell AST、安装器 AppId/互斥锁/当前用户数据边界均通过。
- 首次全量测试执行到 60 个断言后持续两分钟未退出；最小反馈环确认 `app_initialization_test` 在 widget FakeAsync 区直接等待真实 `Directory.createTemp`，目录虽创建但 Future 不返回。
- 将完整文件系统/SQLite 测试夹具放入 `tester.runAsync` 后，挂起转为可见红灯，并暴露此前被掩盖的两个 960px 布局错误：七个 Material 3 图标按钮超出资源行动作区，以及一致性缺失行的无宽度操作列产生无限约束。
- 资源行动作区现按七个 40px 直接图标固定为 280px；一致性操作列固定为 168px。最小 widget 反馈环 1/1 通过，全部 `[DEBUG-a4f2]` 临时标记已清除。
- 原始全量反馈环恢复正常退出，61/61 测试通过。
- UI 修复后的首次静态分析只报告测试辅助函数使用已弃用的 `Finder.description`；改为固定超时说明后重跑。
- 最终本地验证：Dart 格式检查 14 个文件零改动，`flutter analyze --no-pub` 零问题，全量测试 61/61 通过，Windows Release 构建成功，必需插件 DLL 打包检查为 GREEN。
- 阶段 15 的便携 ZIP、Inno Setup 安装器和 GitHub Release 双资产配置已完成；安装/升级/卸载的真实执行仍等待 GitHub Windows runner，阶段保持进行中且不创建发布标签。
- 提交 `daab472` 已推送到 `origin/codex/managed-storage-core`；推送前 fetch 确认远程分支与本地基线一致。
- 已通过登录状态的 GitHub Actions 页面尝试手动触发，但默认分支 `main` 仍只有初始提交，页面尚不识别功能分支中的 workflow。当前分支领先 `main` 11 个提交；未擅自合并默认分支或创建 `v*` 发布标签。
- 用户确认后，`main` 已从初始提交安全快进到 `b1c4342`，随后手动触发 GitHub `Windows release #1`（run `31321052471`）。
- 第一次远程运行完成分析、61 项测试、Windows 构建、插件检查、便携打包和 Inno Setup 6.7.1 安装，但在编译安装器时因 runner 不包含 `Languages/ChineseSimplified.isl` 失败；后续步骤未执行。
- 已从 Inno Setup 官方仓库固定提交 `6054ca127cb6e4fa041350406287b997c4b54a9d` 将简体中文消息文件纳入 `installer/languages/`，并改为本地相对引用与回归校验。
- 修复提交 `9734117` 已同步到 `origin/codex/managed-storage-core` 和 `origin/main`，随后手动触发 GitHub `Windows release #2`（run `31321467268`）。
- 第二次远程运行成功，持续 4 分 54 秒；61 项测试、Windows Release、插件打包、便携包解压检查、安装器首次安装、同 AppId 原地升级和静默卸载全部通过。
- GitHub Actions 已上传 artifact `TAGTAG-windows-x64`（23.9 MB，SHA-256 `789e83073ea3293c7f875b96be95b51da09c4849c4b09ed824aea0b699e00c5f`）；上传步骤引用已验证的便携 ZIP 与 `setup.exe` 两个输出。手动运行未创建正式 Release，标签发布步骤按设计跳过。
- 阶段 15 完成；正式发布仍需用户明确创建 `vMAJOR.MINOR.PATCH` 标签，workflow 届时会把安装版和便携版同时附加到 GitHub Release。
- 用户确认首个正式版本为 `v0.1.0`；已在 `main` 提交 `5f38226` 上创建并推送带说明标签，触发 GitHub `Windows release` run `31322065544`。
- `v0.1.0` 远端构建和发布成功；分析、61 项测试、Windows 编译、插件检查、便携包检查、安装/升级/卸载全部通过。正式 Release 同时提供 `TAGTAG-v0.1.0-windows-x64-portable.zip` 和 `TAGTAG-v0.1.0-windows-x64-setup.exe`。
- 2026-08-11：恢复上一轮上下文，确认 `main` 位于 `9cb90e3`、最新成功发布为 `v0.6.1`，工作树起始状态干净。
- 2026-08-11：用户校正版本策略：缺陷修复递增 PATCH，向下兼容的新功能递增 MINOR，不兼容 API 或架构变更递增 MAJOR；项目明确稳定前保持 `0.y.z`。
- 2026-08-11：阶段 16 启动，先固化版本规则与自动校验，再审计遗留工单并继续真实功能开发；新增功能的下一发布版本为 `v0.7.0`。
- 2026-08-11：新增本地 release-versioning 规格，`pubspec.yaml` 校正到 `0.6.1+1`，GitHub 标签发布增加与项目版本一致性校验；发布配置定向测试 3/3 通过。
- 2026-08-11：完成 managed-storage-core 工单 01/03 验收审计并标记 resolved，整个 effort 状态同步为 resolved；未重复实现已有能力。
- 2026-08-11：当前代码与领域词汇交叉核对后确认文件夹标签继承是真实缺口：控制器、待整理和资源行目前只读取直接标注。已建立 folder-tag-inheritance 本地规格与两个实现工单。
- 2026-08-11：继承状态模型、动态有效标签计算、待整理/层级查询和 Quick Tag 单窗口开关已完成首轮实现；第一次静态检查仅报告两处新版 `Radio` 弃用提示，已按 SDK 的 `RadioGroup` API 修正。
- 2026-08-11：文件夹继承定向测试、Quick Tag widget 流程和全量测试通过；全量为 75/75，补强悬空规则防线后的关键测试为 12/12，静态分析零问题。
- 2026-08-11：本次属于新增功能，按已确认 SemVer 将项目版本提升为 `0.7.0+1`，README 与需求审计同步更新当前状态。
- 2026-08-11：发布前本地门禁完成：Dart 格式状态无 Git 额外差异，`flutter analyze --no-pub` 零问题，全量测试 76/76，Windows Release 构建成功，必需插件 DLL 打包检查为 GREEN。
- 2026-08-11：提交 `bda107d feat: add folder tag inheritance` 已推送到 `main`，带说明标签 `v0.7.0` 已推送并触发 GitHub Actions run `31490106702`。
- 2026-08-11：远端分析、76 项测试、版本一致性校验、Windows 构建、便携包、安装器安装/升级/卸载及 Release 发布全部成功。正式资产为 `TAGTAG-v0.7.0-windows-x64-portable.zip`（13,882,589 字节）和 `TAGTAG-v0.7.0-windows-x64-setup.exe`（11,788,621 字节）。
- 2026-08-11：阶段 17 启动并完成高级搜索域首轮实现：资源大小与创建时间向标签状态同步，旧状态缺少字段时保持可读；有效标签计算支持显式空间参数。
- 2026-08-11：搜索页已接入名称、路径、标签名、类型、大小、创建/修改时间及稳定标签实体 ID 的 AND/OR/NOT 组合条件；待整理页可直接切换当前空间和全局作用域。
- 2026-08-11：`v0.8.0` 发布前定向测试与全量回归通过，当前全量为 80/80，静态分析零问题；等待最终 Windows Release 构建和 GitHub 发布核验。
- 2026-08-11：`0.8.0+1` 本地 Windows Release 构建成功，必需插件 DLL 打包检查为 GREEN；高级搜索和待整理的实现工单已关闭，远程发布工单保持进行中。
- 2026-08-11：提交 `db76ba6 feat: add advanced search and global inbox` 已推送到 `main`，带说明标签 `v0.8.0` 已推送并触发 GitHub Actions run `31494152370`。
- 2026-08-11：`v0.8.0` 远程分析、80 项测试、Windows 构建、便携包、安装器安装/升级/卸载和 Release 发布全部成功。正式资产为便携 ZIP（14,012,648 字节）和安装器（11,879,082 字节）。阶段 17 完成，阶段 18 开始。
- 2026-08-11：阶段 18 完成标签实体合并、唯一标签位置拆分、继承规则转换、最小上下文日志与逆序撤销；直接标注始终保留原标签位置 ID。
- 2026-08-11：标签层级已接入合并/拆分命令和影响预览，操作日志分开呈现资源操作与标签操作；领域、UI 定向测试及全量 85/85 通过，静态分析零问题。
- 2026-08-11：提交 `128ae2c feat: add tag merge and split operations` 和标签 `v0.9.0` 已推送；GitHub Actions run `31496325767` 的分析、85 项测试、Windows 构建、安装/升级/卸载及 Release 发布全部成功。
- 2026-08-11：`v0.9.0` 正式资产为便携 ZIP（14,035,826 字节）和安装器（11,894,286 字节）。阶段 18 完成，阶段 19 开始。
- 2026-08-11：阶段 19 的空间可移植性服务首轮静态检查发现 `archive 3.6.1` 不支持 `zipDirectoryAsync(includeDirName:)` 且 `Archive` 无 `closeSync()`；移除无效参数和调用，保留输入流与临时目录清理。
- 2026-08-11：阶段 19 已完成空间包/模板服务与控制器首轮闭环，覆盖资源 ID、字节、空目录、复用/冲突、SHA-256 篡改、ZIP 路径穿越、持久化重开和模板隔离测试；模板实例化改为生成新的空间、标签与位置身份，资源包继续保留稳定资源 ID。
- 2026-08-11：`v0.10.0` 本地静态检查、93 项测试、Windows Release 构建和插件打包检查通过；GitHub Actions `31500151356` 完整成功，正式发布便携 ZIP（14,163,967 字节）和安装器 EXE（11,990,782 字节）。阶段 19 完成，按约定在 `v0.10.0` 暂停开发。
# UI Prototype Session (2026-08-11)

- Status: complete.
- Read repository agent instructions, issue-tracker conventions, domain-doc conventions, ui-ux-pro-max instructions, and planning-with-files instructions.
- Error: the previously approved Python path `D:\condaData\condaEnvs\site_safety_cv\python.exe` no longer exists. Resolution: use the interpreter discovered by `Get-Command python` for the recovery and design-system scripts.
- No production Flutter files have been modified.
- Audited `CONTEXT.md`, `README.md`, the Flutter application entry point, the main UI composition, controller/model surfaces, and active/future local specs for advanced search, global inbox, tag identity operations, and space portability.
- Generated and persisted the ui-ux-pro-max master design system, then rejected its misrouted landing-page pattern after a product-specific search.
- Added `design-system/tagtag/pages/workspace.md` as the evidence-based desktop workspace override.
- Implemented the isolated interactive prototype in `prototypes/ui-refresh/` with separate HTML, CSS, JavaScript, and usage notes; no production Flutter files were modified.
- Captured the design-system source of truth in `design-system/tagtag/MASTER.md` and the product-specific desktop workspace override in `design-system/tagtag/pages/workspace.md`.
- Verified the resource workspace, tag hierarchy, Quick Tag, import, settings, navigation drawer, dark mode, library health, operation log, keyboard dismissal, and reduced-motion behavior in a real browser.
- Verified 1440, 1024, 768, 375, and 812x375 landscape layouts with no horizontal overflow. Narrow Quick Tag and import flows collapse to one column; table columns reduce according to content priority.
- Final validation passed: browser console 0 errors / 0 warnings, JavaScript syntax check passed, and Git whitespace check passed. Screenshots are stored in `output/playwright/`.

## UI Prototype Iteration 2 (2026-08-11)

- Started the requested five-point refinement pass on the isolated browser prototype.
- Recovered planning context and confirmed unrelated Flutter `v0.10.0` work is already present; production files will be left untouched.
- Located the duplicate top actions, inert space switcher, static tag hierarchy, one-way status drawer handlers, and Windows integration settings panel.
- Confirmed the interaction design: a native parent selector with cycle prevention, a listbox-style two-space menu, a shared status toggle, and a modifier-required shortcut recorder with inline feedback.
- Removed the duplicate top status and settings actions so the header action cluster contains only Import.
- Added a two-space dropdown demo that updates the title bar, breadcrumb, navigation label, and Quick Tag context.
- Replaced the static tag tree with a data-driven hierarchy, selectable tags, a parent selector, descendant exclusion, immediate re-rendering, path feedback, and responsive scrolling.
- Changed the persistent library-health control to a true open/close toggle with synchronized `aria-expanded` state.
- Added a global Quick Tag shortcut recorder, modifier validation, reserved `Ctrl + K` feedback, restore-default behavior, and runtime matching of the selected combination.
- Next: verify the five interactions and responsive behavior with Playwright, then run final static checks.
- Playwright desktop pass: the top header contains only Import; the two-option space listbox opens, receives focus, and switches visible context to `团队共享`.
- Playwright desktop pass: activating `资料库正常` opens the status drawer and marks the trigger expanded; activating it again closes the drawer.
- Playwright desktop pass: the hierarchy editor is visible in the tag page, follows tree selection, and excludes the selected tag and its descendants from eligible parents.
- Playwright desktop pass: reassigned `品牌` under `运营`; the tree order, selected parent, success feedback, and right-side path all updated immediately. Captured `output/playwright/iteration-2-tag-hierarchy-1440.png`.
- Playwright desktop pass: opened Settings from the sole persistent navigation entry and switched to Windows integration for shortcut verification.
- Playwright desktop pass: recorded `Ctrl + Alt + Y`; the displayed global Quick Tag shortcut updated immediately and recording focus returned to the control.
- Playwright desktop pass: closed Settings and pressed the newly recorded shortcut; Quick Tag opened with the current `团队共享` context.
- Began the narrow-window pass at 375x812 after closing the Quick Tag modal.
- Verified 375px width with no horizontal overflow and captured `output/playwright/iteration-2-tag-hierarchy-375.png`.
- Visually inspected the desktop and narrow hierarchy screenshots; the editor, selected state, tree indentation, feedback, and top Import-only action remain coherent.
- Narrow navigation verification found and fixed one accessibility issue: the library-health trigger now has an explicit descriptive accessible name.
- Narrow settings verification found and fixed missing names on the five icon-only category buttons; explicit labels now survive responsive text hiding.
- Captured and visually reviewed `output/playwright/iteration-2-settings-hotkey-375.png`; the shortcut editor remains readable and task controls stay within the viewport.
- Reloaded the prototype at 375px to verify the newly added explicit accessibility labels from a clean state.
- Clean-state narrow verification passed: only Import remains in the header action cluster, all five settings tabs expose names, no horizontal overflow is present, and the browser console reports 0 errors / 0 warnings.
- Began the final 812x375 landscape verification required by the UI delivery checklist.
- First landscape navigation attempt exposed a retained drawer behind the Settings modal. Updated Settings and status-center entry handlers to close responsive navigation before opening; a clean reload and repeat verification is required.
- Reloaded at 812x375 after the fix; the mobile menu now opens normally without pointer interception.
- Landscape retry passed: the tag view closes navigation automatically, has no horizontal overflow at 812x375, and is captured in `output/playwright/iteration-2-tag-hierarchy-812x375.png`.
- UI Prototype Iteration 2 complete. All five requested changes are implemented in the isolated HTML/CSS/JavaScript prototype; final console, syntax, HTTP, whitespace, desktop, portrait, and landscape checks passed.

## Production UI Refresh (2026-08-11)

- Started the production Flutter UI refactor from the approved `prototypes/ui-refresh/` visual system.
- Added the local production UI specification and three implementation tickets under `.scratch/production-ui-refresh/`.
- Preserved the confirmed no-inspector, dedicated-search, direct-resource-action, and top-right-space-switching behaviors in the acceptance contract.
- Rechecked the requested logo source; `C:\Users\zcc\Desktop\LOGO.png` is still absent, so only logo integration is blocked while layout implementation continues.
- Added centralized production theme tokens using the approved blue/neutral/folder-accent palette and Windows system typography.
- Rebuilt the production shell with 232px expanded navigation, 72px compact navigation, a context app bar, and top-right space/import/operational commands.
- Reworked the resource workspace into a stable table surface with page context, direct action icons, tag chips, selection state, and a status bar.
- Reworked tag hierarchy into a recursive tree plus selected-tag resource pane with counts, descendant scope, and existing merge/split actions.
- Rebuilt Settings as a categorized desktop dialog for current general, storage, and Windows integration settings only.
- The first UI contract test run exposed hidden Material ink states under colored boxes; replaced those boxes with Material surfaces and reran successfully.
- Final local verification so far: static analysis zero issues, targeted application tests 8/8, UI contract tests 3/3, full suite 96/96, Windows Release build successful, and required plugin packaging GREEN.
- Visually inspected the actual Release application at 1440x900 and 960x720; no navigation, command, table, action, or text overlap was found. Screenshots are in `output/production-ui-refresh-1440.png` and `output/production-ui-refresh-960.png`.

## Exact Prototype Parity Pass (2026-08-11)

- User rejected the compatibility-conservative production refresh and clarified that the HTML prototype is the complete UI and interaction contract.
- Started a fresh local effort under `.scratch/prototype-parity-ui/` with research, primary workspace, secondary surface, and verification tickets.
- Production Flutter edits are paused until the HTML/CSS/JavaScript and browser-state audit is complete.
- Confirmed the prototype source sizes and Playwright prerequisites; began structural DOM inventory.
- The first DOM inventory command failed because PowerShell parsed the double-quoted regex incorrectly; recorded the failure and switched to a single-quoted pattern.
## Exact parity continuation (2026-08-11)

- Re-read repository agent rules, domain vocabulary, active planning files, and the UI/Playwright/planning skill instructions.
- Confirmed branch `main` and preserved the existing dirty worktree as the implementation baseline.
- Resumed phase 21 with source audit as the next required step before further Flutter edits.
- Audited `index.html` lines 820-1614 and captured the complete tag workbench, inspector, status drawer, Quick Tag, import, settings, drag overlay, and toast structure.
- Audited `index.html` lines 1-819 and captured the custom title bar, persistent navigation, main command hierarchy, resource table semantics, row variants, and empty state.
- Audited CSS root tokens and primary shell/navigation dimensions; captured exact colors, typography, icon sizing, radii, density behavior, and responsive-rule locations.
- Audited CSS for command bars, resource table, inspector, tag workbench, status drawer, and shared dialog scaffolding.
- Completed the CSS audit for import/settings internals, drag/drop and toast feedback, all four responsive breakpoints, dark mode, density, and reduced-motion behavior.
- Completed the JavaScript audit and captured all view, selection, inspector, space, hierarchy, modal, import, settings, shortcut, drawer, drag/drop, keyboard, and responsive state transitions.
- Filled the command-strip audit gap and inventoried the production Flutter UI surface, file size, existing component boundaries, dialogs, and business-action entry points.
- Re-read the parity acceptance spec/map, confirmed Playwright prerequisites, and inventoried all existing prototype reference screenshots.
- Visually inspected the authoritative main 1440/1024, Quick Tag 1440, and Settings 1440 screenshots and recorded alignment, density, surface, modal, and responsive behavior.
- Verified Playwright CLI execution. The first clean-state open failed only because `file://` is blocked; switched the replay plan to a local HTTP server and recorded the failure to avoid repeating it.
- Started a local prototype server on port 4173, opened it in a named Playwright session, and captured a clean desktop accessibility snapshot.
- Read the production home state/root build and first resource/search regions; identified reusable business callbacks and the exact root layout/search/multiselect structures to replace.
- Audited controller view/search/selection/effective-tag/hierarchy APIs and confirmed the parity state can be composed without changing the domain persistence model.
- Read the page-level workspace design override and current theme, then confirmed a dedicated window-frame dependency is needed for true custom-title-bar parity.
- Resolved prototype audit ticket 01 and unblocked primary workspace ticket 02. Identified obsolete UI tests that intentionally assert the opposite of the new inspector/search parity contract.
- Began implementation: added dark-token support, declared the minimal window manager dependency, and initialized a 1280x800 borderless Windows window with 320x520 minimum size.
- Ran dependency resolution successfully; recorded the Windows symlink warning for immediate build verification/fallback.
- Implemented the first production parity shell: custom title bar, 232/72/overlay navigation, responsive main workspace, persistent query/selection command bar, table, resource inspector, hierarchy editor, status drawer, drag overlay, and direct resource menus.
- Added safe tag-placement reparenting with self/descendant/cross-space validation and wired it to the hierarchy editor.
- Formatted the implementation and ran `flutter analyze`; compilation passed and only legacy unused/style lints remained for cleanup.

## Exact parity implementation resumed (2026-08-12)

- Recovered the active file plan and re-read the repository issue/domain rules plus the complete `ui-ux-pro-max` delivery checklist; prototype source remains the sole visual and interaction authority.
- Recorded the prior harmless tooling error: `findings.md` and `progress.md` were accidentally passed to `dart format`, which only reported parse errors and did not modify either Markdown file.
- Extended the existing version-1 preferences document with backwards-compatible optional values for close behavior, startup view, appearance, density, and the Quick Tag shortcut.
- Added runtime Windows Quick Tag re-registration with rollback to the previous binding when a requested key combination is unavailable.
- Formatted the changed Dart files and reran static analysis: zero issues.
