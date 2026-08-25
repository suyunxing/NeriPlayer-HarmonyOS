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
2. `docs/hm.md`（HarmonyOS 开发与迁移指南：版本矩阵、构建命令、2026-08-13 验证记录）、`docs/PROJECT_AUDIT.md`、`docs/FEATURE_MATRIX.md`、`docs/HARMONYOS_PORTING_PLAN.md`、`docs/PORTING_EXECUTION_PLAN.md`（任务级执行计划与进度看板，开始移植任务前先读其 §1/§6）。
3. 根目录 `README.md`。
4. 各原型目录中的 `README.md`、`PORTING.md` 和历史日志。

历史文档中的“已完成”“已实测”只能视为历史记录。若当前环境不能从干净状态重现，不得将其描述为当前已验证能力。功能状态应使用“已静态确认”“有历史证据”“待复核”等准确措辞。

## 修改前检查

- 运行 `git status --short`，识别用户已有的修改；不要覆盖、回退或顺手整理无关改动。
- 阅读根目录 `README.md` 和上述相关审计/迁移文档。
- 在 Android 快照中定位对应行为、模型及测试，但不要机械逐行翻译 Kotlin。
- 检查目标目录中的相邻实现、资源命名和测试模式，保持局部一致。
- 将修改限制在完成任务所需的最小范围；避免无关格式化、目录重排或依赖升级。
- 仓库中的 `.ps1` 脚本必须保持纯 ASCII 内容（含注释）：Windows PowerShell 5.1 将无 BOM 的 UTF-8 脚本按 ANSI/GBK 解析，非 ASCII 字符的乱码可能破坏后续代码行的解析（2026-08-14 实证：中文注释导致参数绑定静默失效）。

## 目录职责

### `NeriPlayer-HarmonyOS/`

- `entry/src/main/ets/app/`：应用常量、日志和应用级基础设施。
- `entry/src/main/ets/model/`：歌曲、歌单、歌词、下载和队列模型。
- `entry/src/main/ets/data/`：设置、历史、统计、歌单和本地媒体数据访问。
- `entry/src/main/ets/network/`：HTTP 与第三方音乐平台适配器。
- `entry/src/main/ets/player/`：AVPlayer、AVSession 和后台播放。
- `entry/src/main/ets/lyrics/`：歌词解析。
- `entry/src/main/ets/view/`：ArkUI 页面、路由、主题和共享组件。
- `entry/src/main/resources/`：字符串、颜色、图标、路由和网络配置。
- `entry/src/test/`：本地单元测试（hypium），待扩展 `entry/src/ohosTest/` 设备测试。

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

本机工具链位于 `E:\DevEco Studio\`（2026-08-26 实测校正：旧记录的 `D:\HarmonyOS\Tools\` 整条路径已不存在，环境已迁移到 DevEco Studio 自带工具链，`command-line-tools` 不再安装）：

- DevEco Studio **6.1.1.300**（`build.txt` = `DS-243.24978.46.36.611300`）：`E:\DevEco Studio\`，当前唯一 IDE，自带 `jbr`（`jbr\bin\java.exe`、`keytool.exe`）。
- 唯一 SDK：`E:\DevEco Studio\sdk\default`（`sdk-pkg.json` = API **24** / HarmonyOS **6.1.1** / **6.1.1.125 Release**），与工程 `compatibleSdkVersion 6.1.1(24)` 自洽。
- `hvigorw.bat`：`E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`（`--version` = **6.24.4**，2026-08-26 实测可构建本工程）。
- `ohpm.bat`：`E:\DevEco Studio\tools\ohpm\bin\ohpm.bat`；Node 在 `E:\DevEco Studio\tools\node\`。
- `hdc.exe`：`E:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`；`hap-sign-tool.jar` 与 `OpenHarmony.p12` 在同目录的 `lib\` 下。
- 模拟器：`E:\DevEco Studio\tools\emulator\Emulator.exe`。
- 用户级环境变量（已指向新位置，无需重设）：`DEVECO_SDK_HOME` = `HOS_SDK_HOME` = `E:\DevEco Studio\sdk`，`DEVECO_STUDIO_HOME` = `E:\DevEco Studio`。
- `NeriPlayer-HarmonyOS/local.properties` **当前不存在**，且 2026-08-26 实测**构建不需要它**——`DEVECO_SDK_HOME` 已足够。若某工具坚持要求，按新路径重建（该文件 gitignore，不入仓）：`sdk.dir=E\:\\DevEco Studio\\sdk\\default`。

**两条已作废的旧结论，不要再沿用**：

1. ~~"DevEco 26.0.0 Beta2 的 hvigor 不支持构建 6.1.1(24)（报 00303031），构建必须用 command-line-tools 的 hvigorw"~~ —— 该 Studio 与 command-line-tools 均已不存在。现在 Studio 6.1.1.300 自带的 hvigor 6.24.4 与 API 24 SDK 版本自洽，**只能也应当**用它构建。
2. ~~"静态检查用 `codelinter.bat`"~~ —— **命令行入口已不存在**，只剩 IDE 插件 `E:\DevEco Studio\plugins\codelinter`。历史上记录过两个互相矛盾的基线（本节旧文 "17 warn + 1 suggestion"、`docs/UI_REVIEW_M11.md` §7 "0 error / 24 warn / 2 suggestion"），**两者当前都无法从命令行复现**。CodeLinter 只能在 IDE 内跑；命令行会话中应如实记为"本轮未跑 lint"，不得伪造该项通过。

依赖同步与主线 debug 构建：

```powershell
$hv   = 'E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
$ohpm = 'E:\DevEco Studio\tools\ohpm\bin\ohpm.bat'
cd NeriPlayer-HarmonyOS
& $ohpm install --all
& $hv assembleHap --mode module -p module=entry@default  -p product=default -p buildMode=debug --no-daemon
& $hv test        --mode module                          -p product=default -p buildMode=debug --no-daemon
& $hv assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug --no-daemon
```

仓库脚本需要解析 Studio/SDK 目录时，使用本机真实路径：

```powershell
$env:DEVECO_SDK_HOME    = 'E:\DevEco Studio\sdk'
$env:DEVECO_STUDIO_HOME = 'E:\DevEco Studio'
```

需要走仓库提供的本地调试签名流程时：

```powershell
cd NeriPlayer-HarmonyOS
.\sign-local.ps1 -HvigorwPath 'E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
```

sign-local.ps1 依赖：`DEVECO_SDK_HOME`（提供 hap-sign-tool 与 hdc）、`DEVECO_STUDIO_HOME`（提供 jbr 的 java）、`NERIPLAYER_SIGNING_PASSWORD`（本地调试 keystore 口令）与 `NERIPLAYER_DEVICE_IDS` 或 `-DeviceIds`（目标设备 UDID，用 `hdc shell bm get --udid` 获取）。签名与安装用 `hdc install -r`（替换安装，不 uninstall）。

**签名口令是本机私有前置条件**：脚本第 93 行强制要求 keystore 口令 **≥32 字符**，SDK 自带的 `OpenHarmony.p12`（口令为公开默认值 `123456`，含 `openharmony application profile debug` 别名）会被该校验直接拒绝。2026-08-26 实测：`NERIPLAYER_SIGNING_PASSWORD` 未设置时签名链无法启动；且模拟器上已安装的包是用私有 keystore 签的，换用 SDK 默认 keystore 签出的 HAP 签名不一致，`install -r` 会失败，只能先 uninstall（**会丢失 `preferences/neri_player_data` 等应用数据**）。因此在没有该口令的会话里，**不要**为了跑设备验证去 uninstall 用户的应用，应如实记录设备验证未执行。

设备侧 ohosTest（`entry/src/ohosTest/`，2026-08-14 已验证 1/1 通过）：先构建并签名 ohosTest HAP（用 hap-sign-tool 对 `entry-ohosTest-unsigned.hap` 执行与 sign-local.ps1 相同的 sign-app 命令），安装两个 HAP 后执行：

```powershell
hdc -t 127.0.0.1:5555 shell "aa test -b moe.ouom.neriplayer -m entry_test -s unittest OpenHarmonyTestRunner -s class ActsAbilityTest#assertContain -s timeout 15000"
```

模拟器冷启动后需 `hdc tconn 127.0.0.1:5555` 才会出现在 `hdc list targets`。

模拟器现状（2026-08-26 实测，**旧记录的"镜像只有 phone_all_x86"属于迁移前事实，已重新核对**）：

- `hdc list targets` 返回 `127.0.0.1:5555`，实测存活；`param get` 显示 `const.product.model` = `emulator`、`const.ohos.apiversion` = **24**、`const.ohos.fullname` = `OpenHarmony-6.1.1.125`，与工程目标 SDK 一致。`moe.ouom.neriplayer` 已安装（`appProvisionType` = debug，且 `preferences/neri_player_data` 存在，即**含用户数据**）。
- ⚠️ `E:\DevEco Studio\tools\emulator\platforms\` 里只有 `qwindows.dll`——那是 **Qt 平台插件目录，不是系统镜像目录**，不要据此判断"没有镜像"。
- 镜像 zip 实际暂存在 `%LOCALAPPDATA%\Huawei\Sdk\.temp\system-image,HarmonyOS-6.1.1,phone_all_x86\install\system-image-phone_all-x86.zip`（2.16 GB，2026-08-16），未解包进 SDK；`%LOCALAPPDATA%\Huawei\Emulator\deployed\phone_config.json` 为 `[]`（无 AVD 定义）。即已运行的实例并非由该暂存包部署，新建 AVD 仍需在 SDK Manager 内完成。

仅在有明确设备验证需求且设备已准备好时运行安装流程：

```powershell
cd NeriPlayer-HarmonyOS
$env:NERIPLAYER_DEVICE_IDS = '真实设备UDID'
$env:NERIPLAYER_SIGNING_PASSWORD = '本地调试口令'
.\sign-local.ps1
```

主线已在 `entry/src/test/` 建立本地单元测试（`@ohos/hypium` 1.0.28；**2026-08-26 实测基线 827/827，0 failure 0 error**，其中 816 为 M11 之前的基线、11 为 `LyricIndexResolver.test.ets` 新增），并在 `entry/src/ohosTest/` 建立设备测试骨架（TestAbility + OpenHarmonyTestRunner + ActsAbilityTest，2026-08-14 模拟器实测 1/1 通过）。

⚠️ **`hvigorw test` 的 `BUILD SUCCESSFUL` 与退出码 0 不代表用例通过**——2026-08-26 实证：一个 `assertEqual` 失败时 hvigor 仍打印 `BUILD SUCCESSFUL`、`exit=0`，失败只出现在日志的 `ERROR: Error in <caseName>` 行。真实结果必须读：

```powershell
# 权威结果（取最后一行）
Select-String -Path entry\.test\default\intermediates\test\coverage_data\coverage.log -Pattern 'OHOS_REPORT_RESULT: stream=Tests run:' | Select-Object -Last 1
```

新增用例**必须注册进 `entry/src/test/List.test.ets`**（import + 在函数体内调用）；未注册的 suite 能编译但永不执行，测试数不会增加。修改纯逻辑时应优先补充或更新 `entry/src/test/` 用例；涉及 Ability、权限、AVPlayer、AVSession、后台播放或系统 UI 时补充 `entry/src/ohosTest/` 用例并按上文 `aa test` 流程验证。静态检查见上文 CodeLinter 说明（当前无命令行入口）。

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
& 'E:\DevEco Studio\tools\ohpm\bin\ohpm.bat' install --all
& 'E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

ohpm 官方默认 registry 为 `https://ohpm.openharmony.cn/ohpm/`，通常无需 `--registry` 覆盖。

### 最低验证要求

- 文档或配置改动：检查链接/路径、运行 `git diff --check`。
- 纯模型、解析、队列或数据逻辑：补充或更新确定性单元测试，并执行相关构建。
- ArkUI 页面或资源：至少完成主线 debug 构建；可用时在相关设备形态做人工检查。
- 播放、网络、权限、文件、后台或 AVSession：除构建外，需要模拟器/真机 smoke test；不能执行时明确标记为“未验证”。
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
