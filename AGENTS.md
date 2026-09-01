# AGENTS.md

本文件为本仓库内编码代理的项目级工作约定，适用于仓库根目录及其全部子目录。若子目录中存在更具体的 `AGENTS.md`，以离目标文件最近的说明为准；用户或系统的明确指令始终优先。

## 项目定位

本仓库是 NeriPlayer 从 Android 迁移到 HarmonyOS 的研究与实现工作区，不是已经完成并可发布的 HarmonyOS 成品。

- 主线实现：`NeriPlayer-HarmonyOS/`，ArkTS、ArkUI、Stage 模型。
- 行为参照：`NeriPlayer-master/`，Android/Kotlin 上游源码快照。
- 非主线实验：`NeriPlayer-ASCF/`，ASCF 元服务原型。
- 审计与规划：`docs/`。
- 本地工具或解包依赖：`ascf-support-plugin/`、`package/`，均不属于产品源码。

默认应修改 `NeriPlayer-HarmonyOS/`。除非任务明确要求，不要修改 Android 参照快照、ASCF 实验、第三方工具目录或解包依赖。

## 事实与文档优先级

开始工作前先阅读与任务相关的文件，并按以下顺序判断事实：

1. 当前源码、构建配置、可重复执行的测试结果。
2. 通过 `devecocli docs search` / `devecocli docs read` 获取的本机官方 HarmonyOS 文档；涉及 ArkTS、ArkUI、Kit、权限、系统能力、SDK 或 DevEco CLI 参数时，编码前必须先查。
3. `docs/hm.md`（HarmonyOS 开发与迁移指南：版本矩阵、构建命令、2026-08-13 验证记录）、`docs/PROJECT_AUDIT.md`、`docs/FEATURE_MATRIX.md`、`docs/HARMONYOS_PORTING_PLAN.md`、`docs/PORTING_EXECUTION_PLAN.md`（任务级执行计划与进度看板，开始移植任务前先读其 §1/§6）。
4. 根目录 `README.md`。
5. 各原型目录中的 `README.md`、`PORTING.md` 和历史日志。

历史文档中的“已完成”“已实测”只能视为历史记录。若当前环境不能从干净状态重现，不得将其描述为当前已验证能力。功能状态应使用“已静态确认”“有历史证据”“待复核”等准确措辞。

## DevEco CLI 强制工作流

本仓库包含 `build-profile.json5` 和 `oh-package.json5`。凡是 HarmonyOS、ArkTS、ArkUI、DevEco、设备、模拟器、日志、UI 检查、SDK/API 文档或兼容性任务，必须把 `devecocli` 作为首选入口。它统一调度 ohpm、hvigor、hdc、Emulator、hilog、本地官方文档、MCP 和 HarmonyOS Skills。

- 不要默认直接调用 `ohpm`、`hvigorw`、`hdc`、`Emulator`、`codelinter` 或手写等价脚本。只有 DevEco CLI 没有对应能力、已确认 CLI 缺陷/环境阻塞，或仓库专用测试/签名流程明确要求时才回退；交付时说明回退原因与实际命令。
- 所有 DevEco CLI 工程命令从目标工程根目录运行：主线为 `NeriPlayer-HarmonyOS/`，ASCF 为 `NeriPlayer-ASCF/`。先确认当前目录存在 `build-profile.json5`，不要从仓库聚合根目录猜测工程。
- 首次使用或环境异常时运行 `devecocli --version`；只有工具定位异常时才临时设置 `DEVECO_CLI_DEBUG=1` 查看底层映射，不要把调试输出作为常规噪声保留。
- 需要机器读取的列表、文档搜索、设备、UI 树和兼容性结果时优先请求 `--format json`，依据结构化字段判断，不要解析易变的人类可读表格。

### 开发前：知识与 Skills

生成或修改 HarmonyOS 代码前，先用本地官方知识库消除 API 猜测：

```powershell
devecocli docs search <精确关键词...> --format json --limit 10
devecocli docs read '<documentId>'
```

- 搜索结果只能用于选文档；命中后读取完整 `documentId`，不要仅凭 snippet 或模型记忆下结论。
- 对陌生 Kit、API 版本、权限、ArkUI 生命周期、后台能力和多设备行为，至少完成一次 `docs search` + `docs read`。查不到时再访问华为官方在线文档，并记录缺口。
- 任务涉及专门领域时先运行 `devecocli skills find <关键词>`，检查是否有匹配的 HarmonyOS Skill。仅安装与当前任务直接相关的 Skill；不要无差别 `--all`。当前智能体受支持且项目未配置时，可使用 `devecocli skills add --skill <name> --project <工程绝对路径>`；不受支持时使用当前代理环境已有的 Skill 机制，并说明限制。
- ArkTS/C++ 修改优先使用已配置的 Check MCP 做快速语法反馈，再执行 lint/build。仅在当前智能体受 `devecocli init` 支持、配置缺失且任务允许修改智能体配置时运行 `devecocli init --mcp --project <工程绝对路径>`；不要在无关任务中重写用户级配置。

### 实现后：检查、构建与部署

默认反馈顺序如下，按任务范围执行到足以证明结果的层级：

```powershell
cd NeriPlayer-HarmonyOS
devecocli check lint entry/src/main/ets --incremental --format json
devecocli build --modules entry@default --product default --build-mode debug
devecocli device list --format json
devecocli run --module entry --device <name-or-serial> --product default --build-mode debug
```

- lint 先限定到改动文件或最近目录；确认无误后再扩大范围。不要使用 `--fix` 批量改写未检查的文件。
- 初次部署、资源/权限/状态装饰器/native/feature/hsp 变更或增量失败时使用完整 `devecocli run`。多设备环境必须显式传 `--device`。
- 已成功完整运行且仅修改可增量更新的源码时，在 `.hvigor/changes.txt` 逐行记录本轮变更路径，然后使用 `devecocli run --apply changes.txt`。失败或效果未生效时立即回退完整 `run`，不要反复盲试。
- 热重载只用于单模块的非状态 ArkTS/TS UI 属性、字面量、表达式或方法体迭代。后台启动 `devecocli run --module entry --hotreload`，确认 watch ready 后才调用 `--hotreload-apply changes.txt`；结束时必须终止后台进程并执行 `devecocli run --hotreload stop`。`@State` 等状态装饰器、资源、native、非目标 feature/hsp 变更必须完整运行。

### 设备、模拟器、UI 与日志闭环

- 先 `devecocli device list --format json`，无可用目标时再 `devecocli emulator list --format json` 和 `devecocli emulator start '<name>'`。镜像下载耗时或失败时不要自动重试；协议未接受时让用户交互执行 `devecocli emulator license`，非交互环境经用户同意后可用 `license accept`。
- UI 任务在应用启动后至少执行 `devecocli ui layout --device <target> --format json --mode simplified`，用节点 id 驱动 `click`、`text` 等交互，并用 `devecocli ui screenshot --device <target> --path <new.png>` 留存视觉证据。截图目标不得已存在；节点不在树中时先滚动到可见区域再重新抓取。
- 页面流程应采用“抓 UI 树 → 操作 → 再抓 UI 树/截图”的短闭环；不要只凭安装成功或启动日志声称 UI 正确。
- 运行异常先用 `devecocli log --level E --from 5m --tail 200 --bundle-name moe.ouom.neriplayer`，崩溃使用 `devecocli log --crash --bundle-name moe.ouom.neriplayer`。需要实时观察时用 `--follow`，完成后及时终止流式进程。
- 涉及 SDK 升级或 API 迁移时，先运行 `devecocli check compat versions --format json`，再针对工程、模块或具体文件执行 `devecocli check compat`；不要凭版本名推断兼容性。

### 允许直接调用底层工具的例外

DevEco CLI 当前没有等价的 Hypium `test` 和设备侧 `aa test` 子命令；仓库的 `sign-local.ps1` 也包含项目专用本地签名约束。因此以下场景允许使用既有底层命令或脚本：

- `hvigorw.bat test`：运行 `entry/src/test/` 本地单元测试。
- `hdc ... aa test`：运行 `entry/src/ohosTest/` 指定设备测试；设备发现、常规安装启动、UI 和日志仍优先使用 `devecocli`。
- `sign-local.ps1`：使用本仓库既有本地调试签名。只有用户明确要求在线签名/重建签名配置时才使用 `devecocli auth login` 和 `devecocli signature generate`，因为它们会访问账号并修改 `build-profile.json5`。
- DevEco CLI 可重复失败且 `DEVECO_CLI_DEBUG=1` 已证明是工具链选择问题时，可临时使用已验证的 command-line-tools 路径完成诊断；不得把回退永久写成首选流程。

## 修改前检查

- 运行 `git status --short`，识别用户已有的修改；不要覆盖、回退或顺手整理无关改动。
- 阅读根目录 `README.md` 和上述相关审计/迁移文档。
- 在 Android 快照中定位对应行为、模型及测试，但不要机械逐行翻译 Kotlin。
- 检查目标目录中的相邻实现、资源命名和测试模式，保持局部一致。
- 将修改限制在完成任务所需的最小范围；避免无关格式化、目录重排或依赖升级。
- 仓库中的 `.ps1` 脚本必须保持纯 ASCII 内容（含注释）：Windows PowerShell 5.1 将无 BOM 的 UTF-8 脚本按 ANSI/GBK 解析，非 ASCII 字符的乱码可能破坏后续代码行的解析（2026-08-14 实证：中文注释导致参数绑定静默失效）。

## 目录职责

### `NeriPlayer-HarmonyOS/`

- `entry/src/main/ets/app/`：应用常量、日志与崩溃诊断。
- `entry/src/main/ets/model/`：歌曲、歌单、歌词、下载和队列模型。
- `entry/src/main/ets/data/`：设置、历史、统计、歌单和本地媒体数据访问。
- `entry/src/main/ets/download/`：下载引擎（任务状态机、传输、原子提交与恢复）。
- `entry/src/main/ets/network/`：HTTP 与第三方音乐平台适配器。
- `entry/src/main/ets/player/`：AVPlayer、AVSession 和后台播放。
- `entry/src/main/ets/lyrics/`：LRC/TTML 歌词解析与分发。
- `entry/src/main/ets/listentogether/`：一起听协议、会话与播放同步策略。
- `entry/src/main/ets/sync/`：GitHub/WebDAV 同步（传输、合并策略与协调器）。
- `entry/src/main/ets/util/`：QR 编码、断点与窗口度量等通用工具。
- `entry/src/main/ets/view/`：ArkUI 页面、路由、主题和共享组件。
- `entry/src/main/resources/`：字符串、颜色、图标、路由和网络配置。
- `entry/src/test/`：本地单元测试（hypium，2026-08-29 记录 874 用例全绿）。
- `entry/src/ohosTest/`：设备侧测试（`aa test` 执行，含播放/下载/同步/一起听/诊断等 Acts* 用例）。

新增代码应放入职责最接近的目录。不要继续把业务状态机堆入页面文件；较大的新能力优先按照 `docs/HARMONYOS_PORTING_PLAN.md` 中的领域、数据、播放和 feature 边界拆分，同时避免为小改动发起无关的全量重构。

### `NeriPlayer-master/`

该目录是已确认 commit 的文件快照，并非本仓库的 Android 主开发线。它用于查阅行为、协议、数据格式和测试用例。除非任务明确涉及同步或修复参照快照，否则保持只读。同步上游时必须记录 commit SHA、日期、许可证和子模块状态，禁止直接覆盖目录后声称完成同步。

### `NeriPlayer-ASCF/`

该目录只用于元服务能力对照。不要把其 JS/HXML 实现当作普通 HarmonyOS 应用主线，也不要为了让 ASCF 可用而降低主线架构或平台能力要求。

## ArkTS 与 ArkUI 约定

- 保持 ArkTS 严格模式兼容，优先使用明确的参数、返回值和集合类型；不要引入 `any`、无说明的类型绕过或依赖隐式转换。
- 复用现有命名风格：类型使用 `PascalCase`，变量和函数使用 `camelCase`，常量使用项目附近已有风格。
- 异步 I/O 使用 `Promise`/`async`/`await`，错误必须保留可诊断上下文；资源、HTTP 请求、文件句柄、监听器和计时器应在成功与失败路径都正确释放。
- 页面只负责渲染状态和派发用户意图。播放、下载、同步、解析和持久化逻辑不得依赖页面生命周期。
- 优先复用 `Theme.ets`、共享组件和资源文件。新增面向用户的文案或颜色时，优先放入对应资源，而不是在多个页面重复硬编码。
- 涉及 phone、tablet、2in1 的 UI 改动应考虑不同宽度、横竖屏、返回栈、文本缩放和触控目标，不要只适配单张截图。
- 平台 API、时间、随机数、网络和文件系统尽量通过小型适配层隔离，使纯逻辑可用 fake 或 fixture 测试。

## 兼容性关键点

- `SongIdentity.ets` 中稳定歌曲键格式为 `<id>|<album>|<mediaUri>`，与 Android/同步数据兼容。除非同时提供迁移方案、跨端 fixture 和回归测试，不得改变其语义。
- 持久化数据和跨端同步数据必须有明确 schema/版本策略。读取旧格式后再写新格式，禁止静默丢弃用户数据。
- 队列、随机/循环、播放恢复、下载恢复和冲突合并应实现为可确定测试的状态机，而不是分散的 UI 条件分支。
- 第三方音乐来源必须通过适配器封装，并区分网络、鉴权、限流、受限内容、解析和平台策略错误。
- HarmonyOS 6.x/7.x 能力不能凭目录名或记忆推断。使用新 Kit、权限或系统能力前，应核对目标 SDK 中的可用性，并提供兼容检测或降级路径。
- 权限或后台模式变更需同步检查 `entry/src/main/module.json5`、用户提示、拒绝授权路径和真机验证计划。

## 安全、隐私与合规

- 不得提交密钥、签名材料、口令、Cookie、Token、设备 UDID、账号数据或机器绝对路径。
- 不得提交 `local.properties`、`signing/`、`oh_modules/`、`.hvigor/`、`build/`、HAP/APK、日志和其他生成物。
- 日志不得输出完整请求头、Cookie、Token、签名口令、用户文件路径或第三方响应中的敏感数据；必要时进行脱敏。
- 在线媒体接口仅作为适配器实现，遵守第三方服务条款、账号授权、版权和应用市场审核要求。
- 本项目及其衍生移植遵循 GPL-3.0；复制或改写上游代码时保留适当的许可证和来源说明。

## 构建与验证

所有命令都从对应工程目录执行。不要把历史缓存或已有产物当作验证结果。

### HarmonyOS 主线

工程基线为 SDK `6.1.1(24)`（HarmonyOS 6.1.1 Release，API 24，官方 2026-05-26 发布，截至 2026-08 仍是最新稳定 Release）。HarmonyOS 7.0 对应开发套件 `26.0.0`（API 26，2026-07-28 处于 Beta2；版本号自 26.0.0 起改用 SemVer）。版本映射以官方[所有 HarmonyOS 开发套件版本](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)页为准，不得凭目录名推断。

本机工具链位于 `D:\HarmonyOS\Tools\`。日常开发从 PATH 直接调用 `devecocli`，只有上文列出的例外才使用底层工具：

- DevEco CLI 1.3.1（2026-09-01 实测）：`devecocli build --modules entry@default --product default --build-mode debug` 会自动执行所需的 ohpm 同步，并通过 Studio 工具链成功构建当前 API 24 工程。后续版本以 `devecocli --version` 的实时结果为准。
- 命令行工具 6.1.1.300：`D:\HarmonyOS\Tools\command-line-tools\bin\` 下的 `ohpm.bat`（6.1.2.285）、`hvigorw.bat`（6.24.4）、`codelinter.bat`、`Emulator.bat`；Node 18.20.1 在 `tool\node\`。这些路径主要保留给 Hypium test、本地签名和 DevEco CLI 故障诊断。
- 唯一完整的 API 24 SDK：`D:\HarmonyOS\Tools\command-line-tools\sdk\default`（6.1.1.125 Release）；`hdc.exe` 在其 `openharmony\toolchains\` 下。
- DevEco Studio 26.0.0.621（Beta2，自带 API 26 SDK）：`D:\HarmonyOS\Tools\devecostudio-windows-26.0.0.621\DevEco Studio\`，当前主力 IDE（含 `jbr`，其 Java 可运行 hap-sign-tool）。历史上直接调用该 Studio 的 hvigor 曾报 00303031；不要据此绕过 DevEco CLI，2026-09-01 已验证 DevEco CLI 1.3.1 选择同一 Studio 工具链仍可成功构建当前工程。
- 用户级环境变量（2026-08-14 已修正）：`DEVECO_SDK_HOME`/`HOS_SDK_HOME` → `D:\HarmonyOS\Tools\command-line-tools\sdk`，`DEVECO_STUDIO_HOME` → 26.0.0.621 Studio，`NERIPLAYER_SIGNING_PASSWORD` → 本地调试签名口令（33 位，供 sign-local.ps1 读取，勿写入仓库）。
- `NeriPlayer-HarmonyOS/local.properties`（gitignore 的本机文件）指向 `D:/HarmonyOS/Tools/command-line-tools/sdk/default`。
- 模拟器系统镜像（2026-08-31 复核在盘）：HarmonyOS-6.1.1（API 24，仅 `phone_all_x86`，位于 `%LOCALAPPDATA%\Huawei\Sdk\system-image\`）；`D:\HarmonyOS\Tools\Sdk\system-image\` 下另有 2026-08-25/26 下载的 API 26 Beta 镜像 `HarmonyOS-7.0.0-B1/pc_all_x86` 与 `HarmonyOS-7.0.0-B2/tablet_x86`（B2 下含 `phone_all_x86`）。本机没有 6.1.1 的 tablet/pc 镜像，tablet/2in1 档验证属向上兼容运行；镜像清单与模拟器启动门禁详见 `docs/hm.md` §7.1。

主线静态检查、debug 构建和 ohosTest HAP 构建使用 DevEco CLI；只有本地单元测试使用底层 hvigor test：

```powershell
cd NeriPlayer-HarmonyOS
devecocli check lint entry/src/main/ets --incremental --format json
devecocli build --modules entry@default --product default --build-mode debug
& 'D:\HarmonyOS\Tools\command-line-tools\bin\hvigorw.bat' test --mode module -p product=default -p buildMode=debug --no-daemon
devecocli build --modules entry@ohosTest --product default --build-mode debug
```

DevEco CLI 构建会处理需要的 ohpm 安装/同步，不要在每轮构建前重复运行 `ohpm install --all`。只有需要证明干净状态可重现时先执行 `devecocli build clean`，再执行目标构建；普通局部迭代保留增量缓存。

仓库脚本需要解析 Studio/SDK 目录时，使用本机真实路径：

```powershell
$env:DEVECO_SDK_HOME = 'D:\HarmonyOS\Tools\command-line-tools\sdk'
$env:DEVECO_STUDIO_HOME = 'D:\HarmonyOS\Tools\devecostudio-windows-26.0.0.621\DevEco Studio'
```

需要走仓库提供的本地调试签名流程时（2026-08-14 已全链验证：构建→签名→安装→冷启动通过）：

```powershell
cd NeriPlayer-HarmonyOS
.\sign-local.ps1 -HvigorwPath 'D:\HarmonyOS\Tools\command-line-tools\bin\hvigorw.bat'
```

sign-local.ps1 依赖以下环境（用户级已持久化）：`DEVECO_SDK_HOME`（command-line-tools 的 API 24 SDK，提供 hap-sign-tool 与 hdc）、`DEVECO_STUDIO_HOME`（26.0.0.621 Studio，提供 jbr 的 java）、`NERIPLAYER_SIGNING_PASSWORD`（33 位本地调试口令）与 `NERIPLAYER_DEVICE_IDS` 或 `-DeviceIds`（目标设备 UDID）。运行脚本前优先用 `devecocli device list --format json` 选择目标；脚本内部必须使用 UDID 时才以 `hdc shell bm get --udid` 补充查询。`-HvigorwPath` 保留为仓库专用签名脚本的已验证构建入口，不代表日常构建应绕过 DevEco CLI。

设备侧 ohosTest（`entry/src/ohosTest/`，2026-08-14 已验证 1/1 通过）：先构建并签名 ohosTest HAP（用 hap-sign-tool 对 `entry-ohosTest-unsigned.hap` 执行与 sign-local.ps1 相同的 sign-app 命令），安装两个 HAP 后执行：

```powershell
hdc -t 127.0.0.1:5555 shell "aa test -b moe.ouom.neriplayer -m entry_test -s unittest OpenHarmonyTestRunner -s class ActsAbilityTest#assertContain -s timeout 15000"
```

模拟器优先由 `devecocli emulator start '<name>'` 启动，并用 `devecocli device list --format json` 等待可用。只有历史 API 24 实例未被 CLI 发现且已确认监听 `127.0.0.1:5555` 时，才回退执行一次 `hdc tconn 127.0.0.1:5555`。

仅在有明确设备验证需求且设备已准备好时运行安装流程：

```powershell
cd NeriPlayer-HarmonyOS
$env:NERIPLAYER_DEVICE_IDS = '真实设备UDID'
$env:NERIPLAYER_SIGNING_PASSWORD = '本地调试口令'
.\sign-local.ps1
```

主线已在 `entry/src/test/` 建立本地单元测试（`@ohos/hypium` 1.0.28，随里程碑累积至 874 用例，2026-08-29 记录全绿，沿革见 `docs/hm.md` §8.1），并在 `entry/src/ohosTest/` 建立设备测试族（TestAbility + OpenHarmonyTestRunner，含播放/下载/同步/一起听/诊断等 Acts* 用例，各轮设备实测记录见 `docs/PORTING_EXECUTION_PLAN.md` §6）。修改纯逻辑时应优先补充或更新 `entry/src/test/` 用例；涉及 Ability、权限、AVPlayer、AVSession、后台播放或系统 UI 时补充 `entry/src/ohosTest/` 用例并按上文 `aa test` 流程验证。静态检查统一使用 `devecocli check lint`（2026-08-27 历史基线：26 warn + 2 suggestion，无 error；不要仅凭退出码判断，解析报告内容，最新值以 `docs/hm.md` 记录为准）。

### Android 参照工程

只有修改 Android 快照或需要验证跨端行为时才运行：

```powershell
cd NeriPlayer-master
.\gradlew.bat :app:testDebugUnitTest :app:lintDebug --warning-mode all --stacktrace
.\gradlew.bat :app:assembleDebug --warning-mode all --stacktrace
```

设备测试使用 `:app:connectedDebugAndroidTest`。若缺失上游子模块导致构建失败，应如实记录阻塞，不要在未授权情况下替换依赖或伪造子模块内容。

### ASCF 实验

只有修改 `NeriPlayer-ASCF/` 时才执行其同步与构建：

```powershell
cd NeriPlayer-ASCF
devecocli check lint entry/src/main --incremental --format json
devecocli build --modules entry@default --product default --build-mode debug
```

DevEco CLI 会处理需要的 ohpm 同步；ohpm 官方默认 registry 为 `https://ohpm.openharmony.cn/ohpm/`，不要无故覆盖 registry。

### 最低验证要求

- 文档或配置改动：检查链接/路径，运行 `git diff --check`；若修改 DevEco CLI 指令，至少执行对应 `--help` 或无副作用查询验证参数。
- 纯模型、解析、队列或数据逻辑：补充或更新确定性单元测试，执行相关 hvigor test，并用 `devecocli check lint` + `devecocli build` 收尾。
- ArkUI 页面或资源：至少完成 `devecocli build`；有设备时执行 `devecocli run`，并以 `devecocli ui layout` + `ui screenshot` 检查相关设备形态。
- 播放、网络、权限、文件、后台或 AVSession：除构建外，需要模拟器/真机 smoke test，并检查 `devecocli log`；不能执行时明确标记为“未验证”。
- 数据格式或迁移：使用旧版本 fixture 验证读取、升级和重新读取，检查异常终止和损坏数据路径。

完成前运行：

```powershell
git diff --check
git status --short
```

## 文档同步

- 行为、权限、构建方式、用户流程或兼容性发生变化时，同步更新相关 README 和 `docs/`。
- 功能状态变化时更新 `docs/FEATURE_MATRIX.md`，但只有可重复验证后才能提升状态。
- 新的审计结论必须注明日期、环境、命令和证据来源。
- 不要通过修改文档掩盖代码缺失，也不要把 UI 入口、占位实现或历史日志描述为功能闭环。

## 交付说明

最终回复应包含：

- 修改了什么以及涉及哪些目录。
- 实际执行的构建/测试命令及结果。
- 未执行的验证、原因和剩余风险。
- 是否触及数据格式、权限、第三方接口、签名或设备相关行为。

除非用户明确要求，不要自行提交、推送、创建 PR、修改版本号或生成发布产物。
