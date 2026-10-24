# NeriPlayer HarmonyOS 开发与迁移指南

> 核验日期：2026-08-14；2026-08-31 复核了 §3.1/§3.2/§8.1 的源码规模、能力域状态与用例计数；2026-09-08 复核了 §1/§2.2/§3.1/§8.1/§8.3/§9 的基线、包名、规模与用例计数（API 26 迁移与 bundleName 改名后的文档对齐）；2026-09-14 复核了 §3.1/§8.1 的规模与用例计数并补记 §7.14（2026-09-08～09-14 真机反馈修复与播放页转场波次）；2026-09-17 复核了 §3.1/§3.2/§8.1 的源码规模与用例计数；**2026-10-22 复核了 §3.1/§3.2/§8.1/§9 的包名、权限清单、源码规模、用例计数与法务状态**（bundleName 定稿 `com.sc.neriplayer`、权限 4 项、335 文件 / 81,505 行 / 1334 用例、协议已定稿）。本文依据华为开发者联盟文档中心、版本说明和当前工作区源码重写并复核：版本映射与官方文档核对一致；本机工具链路径按 2026-08-14 迁移后的 `D:\HarmonyOS\Tools\` 布局更新（2026-08-13 的验证记录当时基于旧布局 `D:\HarmonyOS\` 根目录）。本文面向 NeriPlayer 的 HarmonyOS 原生迁移，不是 HarmonyOS API 的完整百科。

## 0. 阅读索引（先看这里，避免通读）

> 本文 **55 KB / ~27k token**（2026-10-22 起，原 142 KB 的逐轮验证记录已外移至 [`docs/archive/HM_HISTORY.md`](archive/HM_HISTORY.md)）。可完整通读，或按需定位。

| 我想知道 | 读这里 |
| --- | --- |
| 主迁移路线、当前工程定性 | §1 |
| 官方版本矩阵、三个 SDK 版本属性、升级适配 | §2 |
| **工程基线：包名/版本/源码规模/权限/测试计数** | **§3（尤其 §3.1、§3.2）** |
| Android → HarmonyOS 架构映射与目录职责 | §4 |
| 分阶段迁移路线（阶段 0~7） | §5 |
| Stage 生命周期、Navigation 多设备、ArkTS 状态管理、权限、网络、NAPI | §6 |
| **构建/签名/设备 smoke 的具体命令** | **§7.1~§7.3** |
| **测试计划与计数沿革** | **§8.1** |
| **发布前验收清单（哪些已勾/未勾）** | **§9** |
| 官方文档链接索引 | §10 |
| 文档维护规则 | §11 |

**§7.4~§7.23 历史验证记录已外移**：20 个逐轮验证子节（2026-08-13 起，含 API 26 迁移、下载五连修复、壳层与迷你条多轮真机迭代等）移至 [`docs/archive/HM_HISTORY.md`](archive/HM_HISTORY.md)，主线 §7 只保留操作性的 §7.1~§7.3。原「§7.6~§7.23 错位到 §11 之后」的结构问题已修复。

**引用提示**：全仓对 `hm.md §7.4`~`§7.23` 的引用已批量改指 `docs/archive/HM_HISTORY.md §7.x`（节号不变）。

**当前状态速览（2026-10-22，dev HEAD `72059b1`）**：bundleName `com.sc.neriplayer`、versionName 1.3.0、API 26（`26.0.0`）、权限 4 项全 normal、源码 335 个 `.ets` / 81,505 行、单测静态 1334 例（最近一次真实全量执行 874/874，2026-08-29）、法务已定稿 v1.0.0。**§9 验收清单仍有 8 项未勾**（真机 AVPlayer/AVSession、功耗、无障碍听读等），属真实未做而非文档滞后。

---

## 1. 先看结论

NeriPlayer 的主迁移路线是 HarmonyOS 普通应用：ArkTS + ArkUI + Stage 模型。
`NeriPlayer-ASCF` 仅用于元服务能力验证，不能替代普通应用主线。

当前工程是可继续开发的 ArkTS 原型，不应描述为“已完成 Android 全量移植”。
源码、配置和审计结果显示，页面骨架、基础播放、部分数据仓库和三平台搜索已存在，但功能等价性、异常恢复和设备验证仍不足。

生产开发默认使用 **HarmonyOS 26.0.0（API 26）Release 工具链**：

- 2026-09-07 工程从 `6.1.1(24)` 全量迁移到 `26.0.0`（版本号自 26.0.0 起改用纯 SemVer，配置中不带 `(26)` 后缀，见 §2.2 与 §7.12）。
- 迁移前基线为 HarmonyOS 6.1.1 Release（DevEco Studio 6.1.1 Release、SDK `Ohos_sdk_public 6.1.1.125`；API 24 Release 于 2026-05-26 发布）。
- `compatibleSdkVersion` 已随迁移抬至 `26.0.0`，26 以下设备不再可安装本应用。

这是 NeriPlayer 当前工程的项目基线，不代表华为对所有应用的统一升级建议；已有应用应根据目标 API、设备覆盖和新能力需求决定是否升级。

**26.0.0 Beta2**（配套 DevEco Studio 26.0.0 Beta2（26.0.0.621）和 SDK `Ohos_sdk_public 26.0.0.32`）等 Beta 通道工具链只用于预览特性和适配验证；本项目生产构建以 26.0.0 Release 工具链为准（§7.12 为服务器 CLT 26.0.0.105 的迁移实测记录）。

## 2. 官方版本与兼容性规则

### 2.1 当前版本矩阵

| 用途 | API/套件 | 状态 | 本项目策略 |
| --- | --- | --- | --- |
| 生产发布 | 26.0.0(26) + command-line-tools 26.0.0.105 Release | Release | 默认基线（2026-09-07 迁移，见 §7.12） |
| 兼容旧设备 | 6.0.x～6.1.1(20～24) | Release | 不再支持：compatibleSdkVersion 已随迁移抬到 26.0.0，26 以下设备无法安装本应用 |
| 新能力预览 | 26.0.0 Beta2 + DevEco Studio 26.0.0 Beta2 | Beta | 独立适配分支或产品配置 |

华为文档中的发布类型含义是：Release 为正式稳定版本，Beta 为公开但仍在稳定中的版本，Canary 为更早期体验版本。
只有 Release 版本适合作为“承诺质量并发布应用”的默认开发套件。

### 2.2 三个 SDK 版本属性

应用工程至少要明确以下三个版本：

- `compileSdkVersion`：编译时可使用的 API 范围。
- `targetSdkVersion`：应用声明采用的 API 行为范围。
- `compatibleSdkVersion`：应用承诺兼容的最低 API 范围。

官方规则是：

```text
compatibleSdkVersion ≤ targetSdkVersion ≤ compileSdkVersion
```

当前工程根目录 `build-profile.json5` 已配置 `targetSdkVersion` 和 `compatibleSdkVersion` 为 `26.0.0`（2026-09-07 迁移），未显式配置 `compileSdkVersion`（hvigor 使用工具链配套 SDK）。
注意自 26.0.0 起版本号改用纯 SemVer 三段式，**不再写 `(26)` 括号后缀**：hvigor 6.26.4 对 `"26.0.0(26)"` 直接报 `api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>]`（2026-09-07 实测）。

生产配置示例：

```json5
{
  "app": {
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compileSdkVersion": "26.0.0",
        "targetSdkVersion": "26.0.0",
        "compatibleSdkVersion": "26.0.0",
        "runtimeOS": "HarmonyOS"
      }
    ]
  }
}
```

示例只表达版本关系。具体字段位置和 schema 以当前 DevEco Studio 生成的工程为准。
若要让应用运行在更低版本设备上，应降低 `compatibleSdkVersion`，并为所有较新 API 增加运行时兼容保护。

26.0.0 起 API 版本号改用 SemVer，但兼容性判断的基本逻辑不变。当前顺序可按下式理解：

```text
26.0.0 > 6.1.1(24) > 6.1.0(23) > 6.0.2(22) > 6.0.1(21) > 6.0.0(20)
```

不要把 Beta 通道页面中的新增 API 直接混入生产代码。需要时建立 capability adapter，并在预览设备上单独验证。

### 2.3 升级适配闭环

华为官方升级流程可概括为：升级开发工具链，评估 API 新增、废弃和行为变化，完成适配，在新旧系统设备上验证，再发布新包。

每次升级都记录以下信息：

1. 旧套件、新套件和 SDK 版本。
2. `compileSdkVersion`、`targetSdkVersion`、`compatibleSdkVersion`。
3. API 变更页面中受影响的接口和行为。
4. 最低兼容设备、预览设备和实际测试结果。
5. 失败回退路径和发布说明。

## 3. NeriPlayer 当前工程基线

### 3.1 目录角色

| 路径 | 角色 | 结论 |
| --- | --- | --- |
| `NeriPlayer-master/` | Android 上游快照 | 功能和行为参照 |
| `NeriPlayer-HarmonyOS/` | ArkTS/ArkUI 普通应用 | HarmonyOS 主线 |
| `NeriPlayer-ASCF/` | ASCF 元服务试验 | 非主线 |
| `docs/` | 审计、矩阵、路线图 | 迁移决策记录 |

HarmonyOS 工程当前是单 `entry` HAP、Stage 模型、ArkTS 严格模式。
工程声明支持 phone、tablet、2in1，包名为 `com.sc.neriplayer`（2026-10-05 由 `moe.ouom.neriplayer.hmos` 改名，commit `5c75691`；更早名为 `moe.ouom.neriplayer`，两者均已作废），版本 1.3.0 / versionCode 1003000，许可证沿用 GPL-3.0。

源码 `entry/src/main/ets` 下 335 个 `.ets` 文件、约 8.15 万行（2026-10-22 实测 81,505 行）。`entry/src/test/` 本地单元测试已随里程碑累积到 **1334 用例 / 128 个测试文件 / 248 个 describe**（2026-10-22 静态清点；最近一次全量执行为 2026-08-29 的 874/874 全绿，此后新增用例尚未全量执行——Linux `hvigorw test` 执行阶段挂死，需 Windows 工作站复跑），`entry/src/ohosTest/` 建有设备测试族（21 个 `*.test.ets` 文件）；测试范围与计数沿革见 §8.1。
2026-08-13 已使用 `D:\HarmonyOS` 中的 6.1.1 Release 工具链从 `ohpm install --all`、`clean` 开始完成 Debug HAP 构建，随后执行 ArkTS 单元测试、调试签名、模拟器安装、冷启动和设置页 smoke test。构建与测试结果可从当前源码重复获得，不再依赖 2026-08-02 的历史日志。

### 3.2 已有代码与可信度

| 能力域 | 当前情况 | 可信度/下一步 |
| --- | --- | --- |
| 启动、免责声明、引导、安全模式 | `Index.ets` 和对应页面已有路径；2026-09-23 免责声明加版本门控（`util/DisclaimerConsentPolicy.ets` + 偏好键 `np.disclaimer_accepted_version`：协议正文修订时递增 `CURRENT_DISCLAIMER_VERSION`，已同意旧版的安装升级后首启重新进合规页，`DisclaimerPage` 显示更新提示行） | 静态存在；需冷启动、升级和异常恢复测试（版本门控的真机升级重弹路径未验证） |
| 主导航和页面 | 首页、探索、资料库、设置、播放页等已存在 | `Navigation`/`NavDestination` + `NavPathStack` 已落地（2026-08-26，`Router` 保留门面）；多形态布局回归记录见 §9 |
| 基础播放 | `PlayerManager.ets` 使用 AVPlayer，支持 URL/fd、队列、seek、倍速和错误重试骨架 | 原型/待复核；需真实设备闭环 |
| 系统媒体控制 | `AVSessionManager.ets` 可创建并更新 AVSession | 播控中心元数据/歌词字段/seek 回灌已设备实测（2026-08-24/25 M10.1/M10.3）；锁屏、耳机与进程回收真机测试待复核 |
| 后台播放 | `audioPlayback` 配置 + 真实 AUDIO_PLAYBACK 长时任务申请/取消（2026-08-16；2026-09-01 修复 wantAgent 旧包名/失败短路/静默吞错三缺陷，加 cancel/suspend 监听与终态取消） | 模拟器已实测：ohosTest 断言任务注册/释放（含修复前 9800005 失败实锤）、后台连播 >5 分钟跨 3 首切歌 pid 未重启；真机熄屏长播待复核 |
| 本地媒体 | `AudioViewPicker` + `AVMetadataExtractor` | 代码路径存在；需真机验证 URI 生命周期和播放 |
| 网易云 | 搜索、取流、歌词、歌单 + QR 登录与登录态歌单（M4，2026-08-16/17） | 有风控回退；限流、会员内容待复核 |
| Bilibili | 搜索/取流（WBI 签名）+ QR 登录与收藏夹（M4.4～M4.7，2026-08-17/18） | 真网 ohosTest 覆盖搜索/取流/AVPlayer 播放；dolby/flac 音轨、区域错误分类待补 |
| YouTube Music | 搜索 + 匿名 IOS 直连取流（M6.1/M6.2，2026-08-19） | 设备实测搜索→取流通过，播放受上游约一分钟封顶（M6.5）；完整取流待 PoToken/JS 运行时（M6.3）；登录未开始 |
| 下载 | `download/` 引擎 + DownloadsPage（M3，2026-08-16 全链模拟器实测） | Range/HLS 续传、原子提交、启动恢复已落地；断网/杀进程恢复的设备端自动化待补 |
| GitHub/WebDAV 同步 | `sync/`（传输 + 三路合并 + 协调器）+ 同步报告 UI（M5，2026-08-19） | 双设备冲突验收已过本地自建服务器（M5.6）；真实云凭据待复核 |
| 一起听 | `listentogether/` 全链 + 房间页（M7，2026-08-21/22） | 建房/加入/同步播放/重连/邀请分享双端设备闭环；房间设置开关等增强项未做 |
| USB 独占 | M9.1 spike 定案**不移植**（2026-08-24，`docs/USB_M91_SPIKE.md`） | API 面可行，但 ArkTS 单 JS 线程守不住等时节拍、SDK 无公开 USB DDK；系统路径 AVPlayer→USB Audio HAL 可用 |
| 动态取色/高级模糊 | `view/theme/`（Palette/DynamicTheme 等）+ 背景模糊/玻璃子集（M8.1/M8.4，2026-08-23） | 设备实证随封面变色；AGSL 区域掩码玻璃无平台对应（D 级降级）；壁纸取色待复核 |
| 测试 | ArkTS 本地单元测试 874/874 通过（2026-08-29 S 阶段记录，为最近一次全量执行；2026-10-22 静态清点 1334 例 / 128 文件 / 248 describe；最初仅 3 个 LRC 用例，随各里程碑累积）+ `ohosTest` 设备测试族 | 已建立并持续扩充；UI/Instrument 自动化仍薄 |

### 3.3 当前配置审查

`AppScope/app.json5` 的 `bundleName`（`com.sc.neriplayer`）、版本号（1.3.0 / 1003000）和图标配置完整。
`entry/src/main/module.json5` 的 `requestPermissions` 恰为 4 项且**全部 normal 级**：`ohos.permission.INTERNET`、`GET_NETWORK_INFO`、`FILE_ACCESS_PERSIST`、`KEEP_BACKGROUND_RUNNING`；`audioPlayback` 长时任务在 ability 层声明。

原 `READ_AUDIO`（user_grant）已于 2026-08-25 删除——全项目 `grep requestPermissionsFromUser` 零命中，即声明了但从未申请过；本地音频入口收敛为 `AudioViewPicker` 受控 URI + `FILE_ACCESS_PERSIST` 持久授权（下载目录与本地音乐目录同样走该权限）。不要把「选择器可用」和「全库扫描授权」混为一谈：若未来要扫描公共媒体库，必须重新核对权限等级、运行时申请、隐私说明和应用市场要求。

## 4. Android 到 HarmonyOS 的架构映射

不要逐行翻译 Kotlin。先固化领域契约，再替换平台边界。

| Android | HarmonyOS 主方向 | 迁移注意 |
| --- | --- | --- |
| `Application`/`Activity` | `AbilityStage`/`UIAbility` | 生命周期和上下文模型不同 |
| Jetpack Compose | ArkUI 声明式 UI | 重新设计状态所有权和页面生命周期 |
| Media3/ExoPlayer | Media Kit `AVPlayer` | 状态、错误、格式和缓存能力不一一对应 |
| `MediaSession` | AVSession Kit | 需同步元数据、播控状态和命令 |
| 前台服务 | `audioPlayback` + AVSession + 长时任务 | 不能只复制 Android 保活逻辑 |
| OkHttp | Network Kit HTTP/WebSocket | Cookie、重定向、超时和流式响应需封装 |
| DataStore/Room | `preferences`/关系型数据库/文件 | 必须定义 schema、迁移和损坏恢复 |
| WorkManager | Background Tasks Kit/TaskPool | 按任务时长和触发条件重新选型 |
| MediaStore/SAF | Picker/Core File Kit/用户文件 URI | URI 不应被解析为业务路径 |
| JNI/USB C++ | NAPI C/C++ | 先确认 syscap、设备支持和弱链接策略 |

### 4.1 推荐目录

```text
entry/src/main/ets/
├── app/                 启动、依赖装配、日志、错误边界
├── domain/              Song、Playlist、Queue、Lyrics、Download 等纯契约
├── data/                preferences、数据库、文件、远端仓库
├── network/             HTTP/WebSocket、平台适配器、鉴权
├── playback/            AVPlayer、AVSession、队列、中断、后台
├── download/            任务状态机、传输、校验、恢复
├── sync/                GitHub/WebDAV、冲突合并、凭据抽象
├── feature/             按业务域组织页面和状态
├── native/              USB 等 NAPI 边界
└── shared/              小型通用组件和格式化工具
```

`domain` 不导入 `@kit.*`。AVPlayer、HTTP、文件、时钟和随机数均通过接口注入，纯逻辑才可以稳定做单元测试。
UI 只订阅状态并派发意图，播放和下载状态机不能依赖某个页面是否可见。

## 5. 分阶段迁移路线

### 阶段 0：建立可复现基线

1. 固定 Android 上游 commit、许可证和子模块状态。
2. 安装 DevEco Studio 6.1.1 Release，记录 SDK、Hvigor、ohpm、Node/JBR 版本。
3. 在 `build-profile.json5` 显式配置三个 SDK 版本。
4. 删除 `.hvigor`、`build` 等缓存后执行干净同步和构建。
5. 建立 API 24 生产设备矩阵；另建 API 26 Beta2 预览矩阵。
6. 加入 JsUnit、UITest、静态检查和最小 smoke test。

退出条件：新机器能按文档完成同步、编译、安装和 smoke test。

### 阶段 1：领域契约与本地 fixture

先移植 `SongItem`、`SongIdentity`、`Playlist`、`QueueState`、LRC 和设置 schema。
保留 Android 端匿名 fixture，验证稳定歌曲键、序列化、队列随机/循环、歌词偏移和版本迁移。

为失败建模：网络、鉴权、受限内容、解析、存储、播放和系统策略要有可区分的错误类型。

退出条件：核心纯逻辑测试不访问设备和第三方网络，并与 Android fixture 一致。

### 阶段 2：播放垂直切片

以仓库内短音频 fixture 开始，暂时不依赖网易云、Bilibili 或 YouTube。
先完成 AVPlayer 生命周期、URL/fd 资源、播放/暂停/seek/下一首、队列恢复和错误重试。

AVPlayer 的正式流程应注册 `stateChange`、`durationUpdate`、`timeUpdate`、`error` 等监听，再按状态调用 `setMediaSource`、`prepare`、`play`、`pause`、`reset` 和 `release`。
不要在页面 `aboutToAppear` 中创建播放器、在页面隐藏时无条件释放，然后假设返回页面仍可继续播放。

AVSession 负责系统媒体控制：创建并激活会话，持续更新歌曲元数据、播放状态、位置和速度，处理 play、pause、next、previous、seek 等命令。

后台音乐播放必须按官方“后台播放”指南验证 AVSession、后台模式、长时任务和前后台生命周期。
仅在 `module.json5` 写入 `backgroundModes: ["audioPlayback"]`，不能替代整套接入和设备验证。

音频焦点要覆盖来电、导航播报、其他播放器抢占、耳机拔出和输出设备切换。
至少实现暂停/恢复、降音量或停止的明确策略，并记录用户可理解的状态。

退出条件：API 24 设备完成本地 fixture 播放闭环；锁屏/控制中心可控；熄屏持续播放；中断后行为符合预期。

### 阶段 3：数据层与本地媒体

轻量设置可使用 `preferences`。历史、歌单、下载任务和统计若继续存为 JSON，必须增加 schema 版本、原子写、损坏恢复和并发保护。
数据量增长后评估关系型数据库，不要让页面直接读写存储文件。

本地音乐导入建议使用 `AudioViewPicker` 获取用户选择的 URI，再用 `AVMetadataExtractor` 读取标题、歌手、专辑和时长。
保存 URI 时遵守用户文件 URI 生命周期；不要截取 URI 字符串拼接物理路径。

如果要做“扫描整个音乐库”，另行核对 `READ_AUDIO` 的 user_grant 流程、权限说明和用户拒绝分支。
授权失败时仍应允许在线播放和已导入条目工作。

退出条件：首次授权、拒绝授权、失效 URI、升级迁移、空间不足和异常终止均有测试。

### 阶段 4：在线来源适配器

统一接口建议拆为 `search`、`detail`、`lyrics`、`resolveStream`、`login` 和 `capabilities`。
平台差异、Cookie、风控、限流、会员/版权限制和错误码在适配器内部处理，不泄漏到 UI。

网易云当前有 weapi 风控回退路径，但不能把回退等同于稳定登录方案。
需要补齐登录态、凭据安全存储、限流重试、受限内容提示和脱敏响应 fixture。

Bilibili 需要验证 DASH 资源、Cookie、区域限制和音视频轨选择。
YouTube Music 目前只完成搜索；取流仍缺 signature/n、PoToken、EJS/HLS 解析，不得在功能矩阵中标为已完成。

所有第三方接口必须遵守其服务条款、版权规则和应用市场政策；不要在文档中承诺绕过验证码、风控或访问受限内容。

退出条件：每个平台在匿名、登录、会话过期和受限内容四种状态下都有明确行为。

### 阶段 5：下载、同步与凭据

下载模块要从“任务目录”升级为可恢复状态机：解析资源、创建临时文件、Range/HLS 分段、校验长度或摘要、原子提交、断点恢复和清理。
进程被杀、断网、服务器不支持 Range、空间不足和文件损坏都必须可测试。

GitHub/WebDAV 同步应使用条件写、ETag/版本指纹和确定性冲突合并。
凭据、Cookie 和 token 使用 Asset Store Kit 等安全能力保存；日志中不得打印原文。

从 Android 导入数据要提供显式迁移工具和 schema 版本，不要依赖“猜测旧 JSON 字段”的隐式兼容。

退出条件：下载和同步在断网、进程终止、冲突、空间不足、凭据失效场景下可恢复或可解释失败。

### 阶段 6：高风险能力

Listen Together 单独实现 WebSocket 房间协议、重连、主持权、时钟偏移和播放状态校准，不要把网络回调直接绑定到页面。

USB 独占播放先确认目标设备 USB Host、相关 syscap、NAPI 和等时传输能力，再移植 C++ 协议层。
原 Android C++ 代码不能直接当作 HarmonyOS I/O 层；低版本设备还要做 C API 兼容保护和弱链接检查。

悬浮歌词、状态栏歌词、动态取色和高级模糊按设备能力分级，并提供关闭或降级选项。
这些能力不能阻塞 API 24 的核心播放交付。

### 阶段 7：发布门槛

发布前在 API 26（26.0.0）生产设备上执行构建、安装、升级、权限、播放、后台、网络、存储和恢复测试；`compatibleSdkVersion` 已抬至 26.0.0，无更低版本设备兼容负担（2026-09-07 迁移，见 §7.12）。
Beta 通道预览矩阵不能替代 Release 回归。

完成无障碍、phone/tablet/2in1 布局、启动速度、内存、功耗、隐私、权限最小化、日志脱敏和应用市场合规检查。

## 6. 关键实现规范

### 6.1 Stage 模型和生命周期

新功能使用 Stage 模型：`AbilityStage` 做进程级初始化，`UIAbility` 管理窗口和页面，`WindowStage` 负责加载页面。
不要用 Android Activity 的生命周期类比替代 HarmonyOS 的上下文和 Ability 语义。

建议把播放器、下载器和同步器放在应用级服务中，由 `UIAbility` 注入上下文和生命周期信号。
页面销毁不应导致后台播放状态机被销毁。

### 6.2 Navigation 和多设备布局

官方当前推荐 `Navigation` + `NavDestination` + `NavPathStack`，`router` 页面路由标为不推荐。
**2026-08-26 已落地**：`MainShell` 外层改为 `Navigation(pageStack).mode(NavigationMode.Stack).navDestination(pageMap)`，11 个全屏路由 `if/else` 分支收成一个 `@Builder`；`view/Router.ets` 保留为 `NavPathStack` 的门面（公开 API 签名与语义不变，38 个调用点零改动），三个 `AppStorage` 路由镜像已删除。原「作为过渡层，新页面不应继续扩大旧 Router 依赖」的约束因此可以放宽：继续调 `Router.push` 是正确做法，它已经就是 `NavPathStack`。

Navigation 宽度小于 600vp 时建议单栏，大于等于 600vp 时建议分栏；使用 `NavigationMode.Auto` 可让系统按容器宽度切换。
这对 tablet 和 2in1 尤其重要。
**本工程有意不用 Auto**：Split 会把 navBar 压进默认 240vp 的侧栏，而这里的 navBar 内容是**整个 Tab 骨架（完整页面）**，结构不匹配。大屏分栏改由 `Tabs.vertical(true).barWidth(96)` 侧边导航栏提供（tablet 1440vp 实测：侧栏固定 96vp，内容区 `GridRow` lg 12 列 span 2 → 每行 6 张卡）。断点常量在 `util/Breakpoint.ets`（600/840vp，与 `GridRow` 默认断点同源），窗口宽度与底部避让量由 `util/WindowMetrics.ets` 单一订阅源发布到 `AppStorage`。

**系统字号跟随必须显式开启（2026-08-24 M9.3 设备实证，此前的推断是错的）。** HarmonyOS 应用默认 `nonFollowSystem`，即**不跟随系统字体大小**；"UI 全用 fp 所以自动跟随"是错的——fp 只保证换算单位，不代表订阅了系统档位。开启方式是新增 `AppScope/resources/base/profile/configuration.json`：

```json
{ "configuration": { "fontSizeScale": "followSystem", "fontSizeMaxScale": "1.75" } }
```

并在 `AppScope/app.json5` 里以 `"configuration": "$profile:configuration"` 引用。

档位倍率（设备实测）：小 0.85 / 标准 1.0 / 大1 1.15 / 大2 1.3 / **大3 1.45** / 大4 1.75 / 大5 2.0 / 大6 3.2。取证路径有个坑：「设置→显示和亮度→字体大小」滑杆**最高只到 1.45×**，要到 1.75× 必须走「设置→关怀和无障碍→关怀模式→放大显示」的「大 4 档」；而且滑杆拖到**最左不是标准而是 0.85 档**，标准是右移一格。声明了 `fontSizeMaxScale` 就要真的在该倍率下验证过，否则是空承诺。

官方适配要求：≥1.75× 时布局不得错乱、**组件不得叠加**、文字不得截断；被挤压时的正解是"将 X 轴扩展至 Y 轴"，即 `Row` → `Flex({ wrap: FlexWrap.Wrap })`。

**守则：布局代码避免 `.position()` 的百分比值。** 百分比按父容器的**实测宽度**解析，字号放大后父容器变宽会把子元素推到别的元素上（M9.3 的 SongRow 序号角标就这样压在时长文字上，重叠 36×57px）。稳定写法是 `Stack({ alignContent: ... })` + 给容器钉死 `.width()/.height()` + 用 `.margin()` 微调，结果与字号无关。

**布局回归要用度量而不是看截图。** `hdc shell uitest dumpLayout` 导出的节点树里，`bounds` 是**裁剪后的可见矩形**、`origBounds` 是**布局矩形**，两者之差正是缺陷信号；据此可分出四类：非滚动区溢出屏幕（`origBounds` 越出根节点宽度或左边界为负——元素被排到屏外，**滚动也到不了**，真缺陷）、非滚动区被裁剪、滚动区裁剪（在 Scroll/List/Grid/Swiper/WaterFlow 内，允许）、`Text` 叶子两两相交 >2px（对应"组件不得叠加"）。判定时屏宽应取自根节点 `bounds` 而非写死，这样同一套判据能直接跑折叠屏/平板 dump。两个易踩的假信号：① 只比 `Text` 叶子，容器天然互相包含；② 每份 dump 里都有的 `'12, :, XX'` 一类裁剪是**系统状态栏时钟**，非应用内容。

屏幕密度在模拟器上读不到（`param get const.display.density` 等键均 errNum 1002），可用应用内已知 vp 尺寸的控件反推——例如 `.width(40).height(40)` 的返回按钮实测 125px → 3.125 px/vp。

### 6.3 ArkTS 与状态管理

ArkTS 是严格约束的 TypeScript 方言。避免 `any`、隐式类型、动态对象字段和把页面状态当作全局可变变量。
先定义领域类型，再在 UI 层做展示映射。

短期可维护现有 V1 装饰器；新代码按目标 API 和团队规范评估 V2 状态管理。
不要混用 `@State`、`@Prop`、`@Link` 或 V2 装饰器而不说明所有权和刷新边界。

大列表使用 `LazyForEach` 和稳定 key；不要在 `build()` 中做网络、解析、数据库或大规模计算。

### 6.4 权限和数据访问

权限流程是“静态声明 + 运行时授权 + 拒绝处理”。`user_grant` 权限必须在模块配置中声明，并在需要时通过 Ability context 请求。
权限弹窗要说明用途，不得在启动时一次性申请所有权限。

`INTERNET`、网络状态、后台音频、本地音频读取分别评估。只使用系统 Picker 时，优先采用用户选择后的受控 URI；不要为了方便扫描而扩大权限范围。

### 6.5 网络和安全

统一封装 HTTP 超时、重试、取消、重定向、Cookie、TLS 错误和响应大小限制。
WebSocket 统一封装心跳、重连、序列号、超时和关闭原因。

用户 token、平台 Cookie、GitHub/WebDAV 凭据使用安全存储能力；不要写入 preferences、日志、崩溃文本或提交记录。
第三方 API 返回内容需做长度、类型和字段存在性校验。

### 6.6 Native/NAPI 边界

只把 USB、编解码或确有性能收益的部分放入 NAPI C/C++。
业务状态、网络协议和数据迁移保留在可测试的 ArkTS 层。

当 Native 代码调用较新 C API 时，使用官方 C API 兼容保护：配置兼容 SDK、正确链接库、必要时配置 weak library，并通过 `APIAVAILABLE` 做运行时分支。
编译通过不等于旧设备运行安全。

## 7. 构建、签名和本地验证

### 7.1 环境准备

使用与项目基线匹配的 DevEco Studio 和 HarmonyOS SDK。命令行工具应来自同一套开发套件，避免 PATH 中混用不同版本的 `hvigorw`、`ohpm`、`hdc`。

当前可用环境位于 `D:\HarmonyOS\Tools\`（2026-08-14 迁移后布局；同日已修复用户级 PATH 与 `DEVECO_SDK_HOME`/`HOS_SDK_HOME`/`DEVECO_STUDIO_HOME` 环境变量，新终端可直接裸调 `ohpm`/`hvigorw`/`hdc`）：

- 命令行工具 6.1.1.300（`command-line-tools\`）：`bin\ohpm.bat`（ohpm 6.1.2.285）、`bin\hvigorw.bat`（Hvigor 6.24.4，包装器自动定位 SDK 与 Node）、`codelinter`、`Emulator`，Node.js 18.20.1 在 `tool\node\`。
- HarmonyOS SDK 6.1.1.125 / API 24 Release（`command-line-tools\sdk\default`，本机唯一完整的 API 24 SDK）；`hdc.exe` 在其 `openharmony\toolchains\` 下。
- DevEco Studio 26.0.0.621 Beta2（`devecostudio-windows-26.0.0.621\DevEco Studio\`）：完整 IDE（jbr、tools\hvigor、tools\ohpm），自带 API 26 Beta2 SDK，当前主力 IDE。**其 hvigor（6.26.x）不能构建 6.1.1(24) 工程（错误 00303031），构建必须用 command-line-tools 的 hvigorw；其 jbr 的 java 可用于运行 hap-sign-tool。**
- 模拟器系统镜像：HarmonyOS-6.1.1（API 24，**只有 `phone_all_x86`**）+ **HarmonyOS-7.0.0-B1（`pc_all_x86`）** + **HarmonyOS-7.0.0-B2（`tablet_x86`）**（后两份于 2026-08-25/26 在 DevEco GUI 内下载，命令行 `Emulator.bat -imageList/-install` 在无 GUI 会话下退出码 0、零输出、无副作用）。已部署 4 个 AVD（Pura 90、Mate X7、MateBook Pro、MatePad Pro 13）。**注意口径**：tablet 与 2in1 实例跑的是 API 26 / HarmonyOS 7.0.0 Beta（`os.isPublic=false`），**本机没有任何 6.1.1 的 tablet/pc 镜像**，这两档的验证结论属向上兼容运行，不能替代目标 6.1.1(24) 回归。另有启动门禁：CLT 的 `Emulator.bat -start` 起得来但检测不到 `EmitGuestOSBootComplete`（不建 hdc 端口转发）；DevEco 自带的 `Emulator.exe` 要求华为账号处于登录态 → 可行路径只有「在 DevEco 登录账号 → 从设备管理器启动实例」。
- 本地调试签名：用户级环境变量 `NERIPLAYER_SIGNING_PASSWORD` 保存 33 位口令（`signing/OpenHarmony.p12` 为 SDK stock 调试密钥对的重加密副本，旧口令未知已于 2026-08-14 重置；原文件备份为 `signing/OpenHarmony.p12.bak-20260814`）。

项目 `local.properties` 应指向 SDK 根目录：

```properties
sdk.dir=D:/HarmonyOS/Tools/command-line-tools/sdk/default
```

不要把路径写成 `.../sdk/default/openharmony/default`；该目录不存在，并会触发“Cannot find the corresponding SDK version”错误。

华为 6.1.1(24) 版本页在 2026-08-04 更新的配套信息为：API 24 Release、DevEco Studio 6.1.1 Release（最新列出的构建为 6.1.1.300）和 `Ohos_sdk_public 6.1.1.125`。当前本机 command-line-tools（6.1.1.300，SDK 6.1.1.125）与该配套关系一致。

2026-08-13 的实际验证结果：依赖安装、干净 `clean`、Debug HAP 构建和 ArkTS 单元测试均成功。构建仍有 6 条“Function may throw exceptions”警告，分布在 `LibraryPage.ets`、`PlaylistDetailPage.ets` 和 `DebugPage.ets`，不影响当前产物生成，但应在后续错误处理专项中消除。

### 7.2 命令行构建

在 `NeriPlayer-HarmonyOS` 根目录执行（`hvigorw.bat` 包装器自动定位 SDK 与 Node，无需手动设置环境变量）：

```powershell
$cli = 'D:\HarmonyOS\Tools\command-line-tools\bin'

& "$cli\ohpm.bat" install --all
& "$cli\hvigorw.bat" clean --no-daemon
& "$cli\hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
& "$cli\hvigorw.bat" test --mode module -p product=default -p buildMode=debug --no-daemon
& "$cli\hvigorw.bat" assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug --no-daemon
```

ohpm 官方默认 registry 为 `https://ohpm.openharmony.cn/ohpm/`，一般无需 `--registry` 覆盖。若在新终端中 PATH 已包含 `command-line-tools\bin`，可直接裸调 `ohpm`/`hvigorw`；旧会话进程持有迁移前环境变量，需完整路径并显式覆盖 `DEVECO_SDK_HOME`。

CI 还应保存 SDK、Node、Hvigor、ohpm 版本和完整日志。
不要提交 `.hvigor`、`build`、HAP、证书、Profile、私钥或含密码的本地配置。

### 7.3 签名和设备 smoke test

本地 `sign-local.ps1` 仅用于调试签名和安装，不能作为应用市场发布流程（2026-08-14 已全链验证）。运行方式：

```powershell
cd NeriPlayer-HarmonyOS
.\sign-local.ps1 -HvigorwPath 'D:\HarmonyOS\Tools\command-line-tools\bin\hvigorw.bat'
```

依赖的环境变量（用户级已持久化）：`DEVECO_SDK_HOME`（CLT 的 API 24 SDK）、`DEVECO_STUDIO_HOME`（26.0.0.621 Studio，提供 jbr java）、`NERIPLAYER_SIGNING_PASSWORD`（33 位调试口令）。`-HvigorwPath` 不可省略时使用 Studio hvigor 会因 26 Beta2 不支持 6.1.1(24) 而构建失败。口令要求至少 32 位；DevEco/SDK 附带的 OpenHarmony 示例签名材料不满足项目策略时，应使用 DevEco Studio 的调试签名配置或直接按官方 `hap-sign-tool.jar` 流程签名，不要降低正式密钥要求。
正式发布必须在 AppGallery Connect 创建应用，使用正式证书和 Profile 完成签名，并保护密钥和密码。

建议 smoke test 至少覆盖：安装、启动、进入主界面、加载本地 fixture、播放/暂停/seek、系统媒体控制、退出和再次启动。
多设备连接时显式选择目标设备，并在安装、启动或测试失败时让流水线失败。

当前已验证的模拟器是 DevEco Studio 中已有的 `Pura 90`，HarmonyOS 6.1.1 / API 24。可使用 command-line-tools 自带的 Emulator 启动实例：

```powershell
& 'D:\HarmonyOS\Tools\command-line-tools\emulator\Emulator.exe' `
  -start 'Pura 90' -bootmode coldboot

$hdc = 'D:\HarmonyOS\Tools\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc install -r '.\entry\build\default\outputs\default\entry-default-signed.hap'
& $hdc shell aa start -a EntryAbility -b com.sc.neriplayer -m entry
```

**双实例（2026-08-22 M7.5 验证）**：`Emulator.exe -start 'Mate X7'` 可再起第二个实例（foldable 与 phone 共享 phone_all_x86 镜像），hdc 端口自动分配（实测 5561，需 `hdc tconn 127.0.0.1:5561` 探测）；一份 HAP 用双 UDID profile 签名即可双端安装：`sign-local.ps1 -Device <A> -DeviceIds <udidA>,<udidB> -HvigorwPath ...`（`-DeviceIds` 必传，`-Device` 只是安装目标）。devecocli 的 ui 子命令在多设备下用 `--device 127.0.0.1:<port>` 区分。guest 无 root/su：`ifconfig eth0 down`、`kill -19` 均 Permission denied，无法在 guest 内断网/冻结进程。

不要提交签名材料、调试 Profile、HAP、设备标识或本地日志。

**§7.4~§7.23 历史验证记录（已外移）**

> **2026-10-22 起，各轮验证记录（原 §7.4~§7.23，共 20 个子节、约 92 KB）移至 [`docs/archive/HM_HISTORY.md`](archive/HM_HISTORY.md)**，以控制主线文档体积。
>
> 内容概览：§7.4 首次可重复验证（2026-08-13）｜§7.5 迁移后全链验证｜§7.6~§7.7 M1/M3 验证｜§7.8 M4 登录凭据｜§7.9 CI 上线｜§7.10 M5.3 同步传输｜§7.11 下载目录选择｜§7.12 API 26 全量迁移｜§7.13 原生播放列表桥接｜§7.14 真机反馈修复与转场｜§7.15~§7.16 壳层与迷你条｜§7.17 LazyForEach 掉帧治理｜§7.18 打赏入口｜§7.19 跑马灯｜§7.20 悬浮栏滚动自适应｜§7.21 网易云验证码登录｜§7.22 资料库平台标签页｜§7.23 真机反馈五问题修复
>
> 全仓原有的 `hm.md §7.x` 引用已同步指向新路径（`docs/archive/HM_HISTORY.md §7.x`）。


## 8. 测试计划

### 8.1 纯逻辑测试

当前基线位于 `entry/src/test/`，通过 `@ohos/hypium` 和 Hvigor 本地单元测试任务执行 **1334 个用例**（2026-10-22 静态清点 `it(` 声明，128 个测试文件 / 248 个 describe；最近一次全量执行记录为 2026-08-29 的 874/874 全绿，此后新增用例尚未全量执行，`docs/FEATURE_MATRIX.md`；此前各里程碑计数 3→42→…→848→874→935→980→1035→1332 递增，`hvigorw test` 默认不打印计数，结果读 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`）。测试不访问设备和第三方网络。该结果不替代需要安装测试包并通过 `aa test` 执行的设备侧 JsUnit/Instrument 测试。

优先为以下模块补 JsUnit：

- `SongIdentity` 稳定歌曲键和跨端序列化。
- LRC 解析、翻译行、逐字时间轴和偏移。
- 队列随机、循环、下一首/上一首和恢复。
- 下载状态机、Range 分片和重试策略。
- 设置 schema 迁移、损坏恢复和冲突合并。
- 网络错误映射和脱敏日志。

这些测试使用 fake 时钟、fake 文件系统、fake HTTP 和本地 fixture，不访问真实第三方服务。

### 8.2 Instrument/UI 测试

使用官方 `ohosTest`/Instrument Test、JsUnit 和 UITest。
核心 UI 流程包括启动引导、搜索、歌曲详情、播放页、队列、设置、权限拒绝和错误提示。

### 8.3 设备矩阵

| 维度 | 必测场景 |
| --- | --- |
| 系统 | API 26 Release（`compatibleSdkVersion` 已抬至 `26.0.0`，26 以下设备不再可安装，见 §7.12）；API 26 Beta2 预览 |
| 设备 | phone、tablet、2in1；至少一台真实设备 |
| 音频 | 扬声器、蓝牙耳机、耳机拔出、来电、导航播报、其他播放器抢占 |
| 生命周期 | 冷启动、后台、熄屏、旋转/折叠、多窗口、进程被回收 |
| 数据 | 首次安装、升级、权限拒绝、URI 失效、空间不足、损坏恢复 |
| 网络 | 慢网、断网、超时、重定向、Cookie 过期、服务端错误 |

## 9. 发布前验收清单

- [x] 2026-08-13 已在当前 6.1.1 Release 环境完成依赖同步、干净编译、3 个单元测试、调试签名、模拟器安装和冷启动。
- [x] 2026-08-14 迁移后全链复验通过：PATH/环境变量修复、显式三版本配置、ohosTest 骨架（设备实测 1/1）、codelinter 基线、签名口令重置（见 7.5）。
- [x] SDK 版本显式配置且满足大小关系（targetSdkVersion/compatibleSdkVersion = `26.0.0`；compileSdkVersion 未显式配置、随工具链 SDK——2026-09-07 迁移，见 §7.12）。
- [ ] 目标 API（26.0.0）完整功能回归通过；2026-09-07 迁移后设备侧回归未执行（见 §7.12），此前 API 24 阶段的设备实测记录见 §7.6～§7.10。**2026-10-22 补记**：迁移后已有多轮用户真机反馈（09-16 三轮截图、10-01/10-02 六轮滚动与迷你条、10-13 五问题、10-13 二轮本地歌单三修），均修复入 dev；但**系统性真机回归（播放/下载/同步/一起听/卡片主路径）仍未执行**。Beta API 未混入生产路径。
- [ ] Stage、UIAbility、AbilityStage 的职责和生命周期清晰。
- [x] 新页面使用 Navigation/NavPathStack，或记录 Router 过渡原因。2026-08-26：全部 11 个全屏路由已迁到 `Navigation`/`NavDestination` + `NavPathStack`，`Router` 保留为门面（见 6.2）。
- [ ] AVPlayer 状态监听、错误恢复、资源释放和本地 fd 生命周期经过测试。
- [ ] AVSession 元数据、播控、后台播放和音频焦点经过真机测试。
- [ ] 权限按最小化原则声明，运行时拒绝有可用降级路径。
- [ ] 本地 URI、下载文件、设置和数据库有 schema 与恢复策略。
- [ ] 第三方接口状态、版权和服务条款已审查。
- [x] 账号登录以及下载、同步、一起听、USB、YouTube 取流等未完成项已显式标注，不得伪装为已支持。
- [ ] 正式证书、Profile、私钥和密码不在仓库或日志中。
- [ ] 完成无障碍、平板/2in1、性能、功耗、隐私和上架预检。
  - 2026-08-24 M9.3 部分闭合（下表数字为当时快照；无障碍标注后已增至 31 处/12 文件，见 `HARMONYOS_NATIVE_FEATURES.md`），逐项实况见 `docs/RELEASE_CHECKLIST.md`：**已完成**——字号缩放（开启 followSystem 并在 1.45×/1.75× 两档度量，修掉 3 处真实缺陷）、触控目标（度量确认 40vp 下限，**并修正旧结论：实际未达 ≥48vp 推荐值，约 30 控件落在 40–48vp**）、内存冒烟（127–151 MB 无单调增长）、隐私与市场合规清单（权限清单、无第三方统计/崩溃 SDK、诊断仅本地+导出前脱敏、凭据走 asset）、phone 377vp 与 foldable 展开内屏 707vp 两形态布局回归。**仍未完成**——tablet 2880×1920 与 2in1 3120×2080（镜像未下载，执行计划 M9.3a）、折叠外屏 346vp（传感器 hdc 无法注入）、横屏、真机全部指标、屏幕朗读实际听读效果（已补 21 处 `.accessibilityText`/13 文件，但 `uitest dumpLayout -e accessibilityText` 被工具拒绝、本链路无法导出无障碍属性验证）、熄屏 30 分钟功耗（CPU 0.017%/0.74% 只是代理指标，模拟器无电量计）。故本项**不得整体勾选**。
  - 2026-08-25 按少数派《鸿蒙上架指南》第一章补做设计/交互/生态规范自查，逐条记录见 `docs/UX_COMPLIANCE_AUDIT.md`。**已整改**——分层图标（原 216×216 单层且 22.3% 透明 → 前后景各 1024×1024，背景层写成无 alpha 通道的纯色 PNG）、启动页背板与图标背板统一为 `#1E293A`、全量沉浸式（系统栏透明 + 背景层 `expandSafeArea`，底部固定控件上抬 28vp 并修掉 Tab 栏 56→50vp 挤压）、深色模式冷启动（`systemDark` 原硬编码 false 导致系统深色下整会话渲染浅色）、状态栏首帧对比度、路由转场动效（10 个全屏路由原为单帧硬切）、权限最小化（删除从未申请的 user_grant `READ_AUDIO`，`reason` 按场景+动作+目的重写并补 zh_CN）、**上架红线：首启弹窗补「不同意」+ 二次确认后礼貌退出，新增应用内可离线打开的隐私政策与用户协议**。**仍未完成**——键鼠支持；以及 AGC 同步上传定稿文案（商业上架动作，本开源项目不做）。~~大屏三档响应式布局~~ **已于 2026-08-26 整改并三形态复测收口**（见下两轮记录与 §6.2）；~~法务文案定稿~~ **已于 2026-09-20 定稿 v1.0.0**（`d3eadb3`，草案横幅 09-22 删除）；~~重大政策变更重新征同意~~ **已于 2026-09-23 实现**（`9d56a07`，`util/DisclaimerConsentPolicy.ets`，`CURRENT_DISCLAIMER_VERSION='2'`）。**验证边界**：本轮无可用设备（`hdc list targets` 恒 `[Empty]`），仅 `assembleHap` BUILD SUCCESSFUL 与 codelinter `25 warn / 2 suggestion / 0 error` 为实测；单测未运行，M9.3 的 798 pass 对**当前源码**降级为「有历史证据 / 待复核」；全部 UI 表现与权限删除的设备冒烟均**未验证**。
  - 2026-08-26 tablet / 2in1 镜像阻塞解除后完成两形态回归（**跑的是 API 26 Beta 而非目标 6.1.1(24)**），四类布局缺陷全 0，但暴露 11 条大屏信息密度问题；根因是全项目未使用 ArkUI 标准响应式组件（`GridRow`/`Navigation`/`Tabs`/断点 grep 零命中），已同日整改：`Tabs`/`TabContent`（大屏 `.vertical(true).barWidth(96)` 侧边栏）、`Navigation`/`NavDestination` + `NavPathStack`、`GridRow`/`GridCol` 按断点分列、`ContentBand` 栏宽（正文 600vp / 列表 840vp / 按钮 360vp）、硬编码 28vp → `TYPE_NAVIGATION_INDICATOR` 动态避让，共 24 文件（新增 3）。**已完成**——tablet 一档 7 页改后复测四类缺陷全 0、11 条密度问题逐条填回实测数字、返回栈未双弹、本地单测 819/819、codelinter 0 error。**仍未完成**——phone 与 2in1 的改后复测、2in1 上「自由窗口避让区 0 → 抬升量 0」这一动态避让核心验收点、动态跨断点切换、字号三档改后复测、目标 API 24 上的 tablet/2in1、折叠屏悬停态、触控目标 48vp、横屏、真机、朗读听读、熄屏功耗。逐项见 `docs/UX_COMPLIANCE_AUDIT.md` §8.2/§10.2/§11.5 与 `docs/RELEASE_CHECKLIST.md` §1/§7.3。
  - 2026-08-27 phone（Pura 90，**唯一 API 24 形态**）改后复测完成，`Tabs` 底部栏分支首次上设备：Tab 单格 97.8vp 与改造前逐像素一致、避让区 27.85vp 且 Tab 底边与指示器上沿重合（S2 判定规则在目标 API 上成立）、首启与全页四类缺陷 0、深/浅/auto 三档无缝、字号 1.45×/1.8125× 三处旧缺陷无回归、返回栈无一次双弹、内存 6 轮平台期 257–264MB 无泄漏；静态与单测复跑持平（codelinter 26/2/0、819/819）。**复测发现并修复两处真实缺陷**（tablet 轮漏检，因 tablet 色带与页面同色不可见）：① 指示器条带与 Tab 栏 28vp 色差接缝——NavBar 内容区内层 `expandSafeArea` 不延伸，改由 `Tabs` 容器自身背景铺底（`Tabs` bounds 天然到窗口物理底边）；② `NavDestination` 默认白背景在深色模式内容区以下露白边，显式置透明回落 Index 沉浸层。均改在 `MainShell.ets`。一个未复现的观察项（后台改显示密度后恢复时一次 Back 直接退出）已登记 audit §11.6。证据前缀 `tools/.m9/pa*`。
  - 2026-08-27 深夜 2in1（MateBook Pro，API 26 Beta）改后复测完成，**ArkUI 改造轮三形态证据收齐**：自由窗口 1100vp 侧边栏 96.3vp 固定、**S2 核心验收点通过**（避让区 0 → 抬升 0，TabBar 底边距窗口底 0.0vp，整改前 27.9vp 纯死区）、**跨断点 809↔1101vp 双向换栏**且两次重建后页面状态保留、最大化 1642vp 侧边栏保持、四类缺陷全 0、设置行 716.8vp/法务 568.4vp/每日推荐 6 卡每行、深色含 DecorBar 跟随。**环境事故记录（历史）**：bundleName 当时在工作树改为 `moe.ouom.neriplayer.hmos`（08-27 上午的未提交变更，晚于当日提交；**该名与更早的 `moe.ouom.neriplayer` 均已作废，2026-10-05 起现名为 `com.sc.neriplayer`**），2in1 模拟器上旧名残留包与新包同图标并存，`aa start -b moe.ouom.neriplayer` 误启动旧应用产生一串假阳性；**旧包需卸载、所有 `-b` 参数需随改名更新**（排查记录 audit §11.7）。另记该 Beta 镜像 a11y dumpLayout 树不稳定（需截图像素交叉验证）、DecorBar 按钮顺序实测为最大化/最小化/关闭。证据前缀 `tools/.m9/wb*`。

## 10. 官方资料索引

以下链接均来自华为开发者联盟文档中心；页面会持续更新，使用前再次确认适用 API 和更新时间。

> 补充（2026-08-24）：面向**鸿蒙独有特性与官方设计规范**的资料索引已单独整理于 `docs/HARMONYOS_NATIVE_FEATURES.md` §13，含服务卡片、AVSession 播控自检表、音乐低功耗、一多与折叠屏悬停态、投播、实况窗、分层图标、意图框架共 30 余个官方文档 ID（均已在本机 `devecocli docs` 验证可读），以及各能力在本机 API 24 SDK 中的 `.d.ts` 声明位置。本节（§10）保留移植期使用的通用资料。另：该文 §6 就本文 §6.2 已提出的 `Navigation` 迁移建议给出了取舍结论——**维持建议但不单独立项**，理由是纯迁移不产生用户可见新功能，且会作废 M9.3 已完成的 17 页 × 3 档字号 × 2 形态布局回归，宜与 tablet/2in1 适配、折叠屏悬停态、触控目标 48vp 合并为一个里程碑以共享一次回归成本（`NavigationMode.Auto` 自带 ≥600vp 分栏，正是分栏适配所需）。**2026-08-26 更新**：该结论已按「与 tablet/2in1 适配合并」执行完毕（`Navigation`/`NavDestination` + `NavPathStack` 已落地），但两处与当时预期不同：① **`NavigationMode.Auto` 的分栏收益被主动放弃**——Split 会把 navBar 压进默认 240vp 侧栏，而本工程的 navBar 是整个 Tab 骨架，结构不匹配，故显式 `NavigationMode.Stack`，大屏分栏改由 `Tabs.vertical(true)` 提供；② **「作废既有回归」这个风险确实兑现**——改后只复测了 tablet 一档，phone/2in1 与字号三档都未重跑。折叠屏悬停态与触控目标 48vp 没赶上这一轮，仍会各自触发一遍回归。详见 `HARMONYOS_NATIVE_FEATURES.md` §6.2、§12 M10.4。

### 版本和兼容性

- [文档中心](https://developer.huawei.com/consumer/cn/doc/)
- [所有 HarmonyOS 开发套件版本](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)
- [6.1.1(24) 版本概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-611)
- [26.0.0 Beta 版本概览](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-2600)
- [26.0.0 起版本号格式调整说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/version-number-26)
- [应用兼容性影响因素](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/app-compatibility-influence-factor)
- [ArkTS API 兼容性保护](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/arkts-api-compatibility-warning-elim)
- [应用升级适配简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/app-upgrade-intro)

### API 26（HarmonyOS 7.0）差异预览

预研 API 26 新能力时参考（不得混入生产路径；生产基线已是 26.0.0，Beta 页面能力仍需单独验证）：

- [Media Kit API 差异（26.0.0 Beta2）](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/js-apidiff-mediakit-7002)：AVPlayer 播放列表、离线缓存下载 `AVDownloaderManager`、`AVTimedMetaData`、可加载/可 seek 时间段查询等。
- [AVSession Kit API 差异（26.0.0 Beta2）](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/js-apidiff-avsessionkit-7002)：`setSupportedPlaySpeeds`/`setSupportedLoopModes`/`setSupportedMediaCenterControlTypes` 等。
- [Background Tasks Kit API 差异（26.0.0 Beta2）](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/js-apidiff-backgroundtaskskit-7002)：长时任务授权对话框、挂起消息等。

### 应用模型、ArkTS、ArkUI

- [应用开发导读](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-dev-guide)
- [快速入门](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/start-overview)
- [应用开发基础知识](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/development-fundamentals)
- [ArkTS 入门](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started)
- [应用模型概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/stage-model-development-overview)
- [UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle)
- [Navigation 基础架构](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-architecture)
- [Navigation 页面路由](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-jump)
- [从 Router 切换 Navigation](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-router-to-navigation)

### 媒体、后台和权限

- [Media Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/media-kit-intro)
- [使用 AVPlayer 播放音频（ArkTS）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback)
- [AVPlayer 设置播放 URL](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/playback-url-setting-method)
- [后台播放](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-background-scene)
- [应用接入 AVSession](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-access-scene)
- [音频焦点介绍](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/audio-playback-concurrency)
- [音频会话管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/audio-session-management)
- [选择器 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker)
- [开放权限（用户授权）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/permissions-for-all-user)
- [程序访问控制管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-abilityaccessctrl)

### 数据、网络、安全、构建和测试

- [用户首选项 preferences](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-preferences)
- [Core File Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-file-kit-intro)
- [用户文件 URI](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/user-file-uri-intro)
- [HTTP 访问网络](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/http-request)
- [WebSocket API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-websocket)
- [Asset Store Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/asset-store-kit-overview)
- [命令行构建流水线](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app)
- [发布应用](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-publish-app)
- [单元测试框架](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/unittest-guidelines)
- [UI 测试框架](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uitest-guidelines)
- [HarmonyOS 开发者测试服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-testing-overview)
- [音乐应用案例](https://developer.huawei.com/consumer/cn/doc/architecture-guides/practice-audio-app-architecture-v1-0000002041168218)

## 11. 维护规则

每次 SDK 或上游 Android 更新，都更新本文件的核验日期、版本矩阵、源码状态和测试结果。


新增能力必须附官方页面 URL、适用 API、代码位置、验证设备、失败日志和降级方案。

如果官方页面、工程配置和历史日志冲突，以当前官方 Release 文档、当前 DevEco Studio 生成配置和可重现设备测试为准。
