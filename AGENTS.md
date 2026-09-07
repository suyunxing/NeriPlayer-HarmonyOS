# AGENTS.md

本文件为本仓库内编码代理的项目级工作约定，适用于仓库根目录及其全部子目录。若子目录中存在更具体的 `AGENTS.md`，以离目标文件最近的说明为准；用户或系统的明确指令始终优先。

本文件只包含与机器无关的项目约定；工具链路径、构建入口、签名环境变量和模拟器镜像等机器相关配置，维护在各机器自己的代理全局配置中（见「机器环境分界」）。

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
2. 本机可用的官方 HarmonyOS 文档（本机配置了 DevEco CLI 时使用 `devecocli docs search` / `devecocli docs read`，命中后读取完整 `documentId`，不要仅凭 snippet 或模型记忆下结论；本机没有文档工具时访问华为官方在线文档，并记录缺口）。涉及 ArkTS、ArkUI、Kit、权限、系统能力、SDK 或构建参数时，编码前必须先查。
3. `docs/hm.md`（HarmonyOS 开发与迁移指南：版本矩阵、构建命令、2026-08-13 验证记录）、`docs/PROJECT_AUDIT.md`、`docs/FEATURE_MATRIX.md`、`docs/HARMONYOS_PORTING_PLAN.md`、`docs/PORTING_EXECUTION_PLAN.md`（任务级执行计划与进度看板，开始移植任务前先读其 §1/§6）。
4. 根目录 `README.md`。
5. 各原型目录中的 `README.md`、`PORTING.md` 和历史日志。

历史文档中的“已完成”“已实测”只能视为历史记录。若当前环境不能从干净状态重现，不得将其描述为当前已验证能力。功能状态应使用“已静态确认”“有历史证据”“待复核”等准确措辞。

## 机器环境分界

- 本仓库由多台机器（Windows 工作站、服务器等）共用同一份 `AGENTS.md`。本文件不得出现任何机器绝对路径或单机工具链细节。
- 各机器的工具链位置、首选构建入口（DevEco CLI 或 command-line-tools hvigorw 等）、签名环境变量（`NERIPLAYER_SIGNING_PASSWORD`、`NERIPLAYER_DEVICE_IDS`）与模拟器/设备启动方式，写在各机器用户目录下的代理全局配置（如 `~/.zcode/AGENTS.md`、`~/.codex/AGENTS.md`）中；处理本仓库任务时与本文件叠加生效。
- `docs/` 中的验证记录（命令、路径、日期）属于记录当时环境的历史证据，不构成当前机器的配置来源。

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

所有命令都从对应工程目录执行（主线为 `NeriPlayer-HarmonyOS/`，ASCF 为 `NeriPlayer-ASCF/`，先确认存在 `build-profile.json5`，不要从仓库聚合根目录猜测工程）。不要把历史缓存或已有产物当作验证结果。具体构建/测试/签名命令与工具链路径按各机器全局配置执行；以下是仓库层面的固定事实与最低要求。

### HarmonyOS 主线

工程基线为 SDK `6.1.1(24)`（HarmonyOS 6.1.1 Release，API 24，官方 2026-05-26 发布，截至 2026-08 仍是最新稳定 Release）。HarmonyOS 7.0 对应开发套件 `26.0.0`（API 26，2026-07-28 处于 Beta2；版本号自 26.0.0 起改用 SemVer）。版本映射以官方[所有 HarmonyOS 开发套件版本](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)页为准，不得凭目录名推断。

- 本工程不自带项目级 hvigor wrapper；构建工具链随 DevEco Studio / command-line-tools 分发，调用入口以各机器全局配置为准。
- 依赖同步由构建入口自动处理（ohpm 安装/同步），不要在每轮构建前重复手动 `ohpm install --all`；只有需要证明干净状态可重现时才先 clean，普通局部迭代保留增量缓存。
- 本地单元测试：`entry/src/test/`（`@ohos/hypium` 1.0.28，随里程碑累积至 874 用例，2026-08-29 记录全绿，沿革见 `docs/hm.md` §8.1），经 `hvigorw test --mode module -p product=default -p buildMode=debug --no-daemon` 执行。
- 设备侧测试：`entry/src/ohosTest/`（TestAbility + OpenHarmonyTestRunner，含播放/下载/同步/一起听/诊断等 Acts* 用例，各轮实测记录见 `docs/PORTING_EXECUTION_PLAN.md` §6）。先构建并签名 ohosTest HAP（对 `entry-ohosTest-unsigned.hap` 执行与 `sign-local.ps1` 相同的 sign-app 命令），安装后执行：

```powershell
hdc -t 127.0.0.1:5555 shell "aa test -b moe.ouom.neriplayer -m entry_test -s unittest OpenHarmonyTestRunner -s class ActsAbilityTest#assertContain -s timeout 15000"
```

- 本地调试签名使用仓库 `sign-local.ps1`；其依赖的 `NERIPLAYER_SIGNING_PASSWORD`（本地调试口令）与 `NERIPLAYER_DEVICE_IDS`（目标设备 UDID）为机器级用户环境变量，不入库。在线签名/重建签名配置会访问账号并修改 `build-profile.json5`，仅用户明确要求时使用。
- 静态检查用本机可用的 codelinter 或 `devecocli check lint`（2026-08-27 历史基线：26 warn + 2 suggestion，无 error；不要仅凭退出码判断，解析报告内容，最新值以 `docs/hm.md` 记录为准）。
- 修改纯逻辑时应优先补充或更新 `entry/src/test/` 用例；涉及 Ability、权限、AVPlayer、AVSession、后台播放或系统 UI 时补充 `entry/src/ohosTest/` 用例并按上文 `aa test` 流程验证。

### Android 参照工程

只有修改 Android 快照或需要验证跨端行为时才运行：

```powershell
cd NeriPlayer-master
.\gradlew.bat :app:testDebugUnitTest :app:lintDebug --warning-mode all --stacktrace
.\gradlew.bat :app:assembleDebug --warning-mode all --stacktrace
```

设备测试使用 `:app:connectedDebugAndroidTest`。若缺失上游子模块导致构建失败，应如实记录阻塞，不要在未授权情况下替换依赖或伪造子模块内容。

### ASCF 实验

只有修改 `NeriPlayer-ASCF/` 时才执行其同步与构建；命令入口按机器配置，等价于 `hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon`。ohpm 官方默认 registry 为 `https://ohpm.openharmony.cn/ohpm/`，不要无故覆盖 registry。

### 最低验证要求

- 文档或配置改动：检查链接/路径，运行 `git diff --check`。
- 纯模型、解析、队列或数据逻辑：补充或更新确定性单元测试，执行相关 hvigor test，并以 lint + debug 构建收尾。
- ArkUI 页面或资源：至少完成 debug 构建；有设备时安装运行，并用本机可用的 UI 树/截图工具检查相关设备形态。
- 播放、网络、权限、文件、后台或 AVSession：除构建外，需要模拟器/真机 smoke test，并检查运行日志（hilog 等）；不能执行时明确标记为“未验证”。
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

## Git 提交与推送（用户 2026-09-06 起的常设要求）

**每个任务完成（功能、修复、文档、配置均算）后，必须提交并推送**，不允许攒批：

```bash
git add -A
git commit -m "<类型>: <中文简述>"   # feat/fix/docs/refactor/chore/test
git push
```

- 提交前必须通过对应验证（主线改动至少 `hvigorw assembleHap` 构建成功，见下文服务器环境）。
- push 被拒时 `git pull --rebase` 后重推；禁止 `--force`。
- 不要把多个不相关改动混进一个 commit。
- 创建 PR、修改版本号、生成发布产物仍需用户明确要求。
- `signing/`、`local.properties`、构建产物严禁入库（.gitignore 已排除）。

## 服务器开发环境（Azure Linux，2026-09-06 起可用）

服务器为 Ubuntu 24.04 + 中文 XFCE 桌面，经 Tailscale 内网 `100.73.184.27` RDP 访问，ZCode 已装在服务器上可直接开发本仓库。

- 鸿蒙工具链：`/opt/command-line-tools`，版本 **26.0.0.821 正式版**（API 26 SDK、hvigor 6.26.4、ohpm 26.0.0.630、Node 18 自带）。**与 PC 上 26.0.0.621 Beta2 不同，.821 的 hvigor 可直接构建 6.1.1(24) 工程**（2026-09-06 服务器实测 BUILD SUCCESSFUL）。
- `hvigorw`/`ohpm`/`hdc`/`codelinter` 已在 PATH；`HOS_SDK_HOME` 等环境变量见 `~/.bashrc`。
- JDK 17（`java`）已装，用于 hap-sign-tool 签名。
- 工程内 `local.properties` 已指向服务器 SDK：`sdk.dir=/opt/command-line-tools/sdk/default`（本机文件，不入库）。

服务器上的构建与签名（在仓库根目录执行）：

```bash
cd NeriPlayer-HarmonyOS
ohpm install --all
hvigorw --no-daemon assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug
# 或在仓库根目录一键构建+签名：
./build-signed.sh
```

- 签名材料位于 `NeriPlayer-HarmonyOS/signing/`（AGC 官方调试证书：`harmonyos_debug.p12/.cer` + `NeriPlayerDebug.p7b`，绑定设备与 bundleName）。密钥口令在服务器 `~/harmony-projects/signing/keystore-password.txt`，严禁写入仓库。
- `build-signed.sh`：构建 → hap-sign-tool 签名 → 复制产物到下载目录（Tailscale 内网 http://100.73.184.27:8000/NeriPlayer-signed.hap），PC 端 `hdc install -r` 安装。
- 真机无线调试：手机与服务器均可访问时 `hdc tconn <手机IP>:<端口>`（跨网络时可在手机装 Tailscale 后用其 100.x 地址）。
- 服务器磁盘约 8GB 可用，不要在服务器上解包无关大文件；`.appanalyzer` 等缓存已在 .gitignore 排除。
