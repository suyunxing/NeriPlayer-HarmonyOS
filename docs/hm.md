# NeriPlayer HarmonyOS 开发与迁移指南

> 核验日期：2026-08-14；2026-08-31 复核了 §3.1/§3.2/§8.1 的源码规模、能力域状态与用例计数；2026-09-08 复核了 §1/§2.2/§3.1/§8.1/§8.3/§9 的基线、包名、规模与用例计数（API 26 迁移与 bundleName 改名后的文档对齐）；2026-09-14 复核了 §3.1/§8.1 的规模与用例计数并补记 §7.14（2026-09-08～09-14 真机反馈修复与播放页转场波次）；2026-09-17 复核了 §3.1/§3.2/§8.1 的源码规模与用例计数。本文依据华为开发者联盟文档中心、版本说明和当前工作区源码重写并复核：版本映射与官方文档核对一致；本机工具链路径按 2026-08-14 迁移后的 `D:\HarmonyOS\Tools\` 布局更新（2026-08-13 的验证记录当时基于旧布局 `D:\HarmonyOS\` 根目录）。本文面向 NeriPlayer 的 HarmonyOS 原生迁移，不是 HarmonyOS API 的完整百科。

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
工程声明支持 phone、tablet、2in1，包名为 `moe.ouom.neriplayer.hmos`（2026-09-01 由 `moe.ouom.neriplayer` 改名），许可证沿用 GPL-3.0。

源码 `entry/src/main/ets` 下 269 个 `.ets` 文件、约 6.08 万行（2026-09-17 实测 60,800 行）。`entry/src/test/` 本地单元测试已随里程碑累积到 1035 用例（2026-09-17 静态清点；最近一次全量执行为 2026-08-29 的 874/874 全绿），`entry/src/ohosTest/` 建有设备测试族（24 个测试文件）；测试范围与计数沿革见 §8.1。
2026-08-13 已使用 `D:\HarmonyOS` 中的 6.1.1 Release 工具链从 `ohpm install --all`、`clean` 开始完成 Debug HAP 构建，随后执行 ArkTS 单元测试、调试签名、模拟器安装、冷启动和设置页 smoke test。构建与测试结果可从当前源码重复获得，不再依赖 2026-08-02 的历史日志。

### 3.2 已有代码与可信度

| 能力域 | 当前情况 | 可信度/下一步 |
| --- | --- | --- |
| 启动、免责声明、引导、安全模式 | `Index.ets` 和对应页面已有路径；2026-09-22 免责声明加版本门控（`util/DisclaimerConsentPolicy.ets` + 偏好键 `np.disclaimer_accepted_version`：协议正文修订时递增 `CURRENT_DISCLAIMER_VERSION`，已同意旧版的安装升级后首启重新进合规页，`DisclaimerPage` 显示更新提示行） | 静态存在；需冷启动、升级和异常恢复测试（版本门控的真机升级重弹路径未验证） |
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
| 测试 | ArkTS 本地单元测试 874/874 通过（2026-08-29 S 阶段记录，为最近一次全量执行；2026-09-17 静态清点 1035 例；最初仅 3 个 LRC 用例，随各里程碑累积）+ `ohosTest` 设备测试族 | 已建立并持续扩充；UI/Instrument 自动化仍薄 |

### 3.3 当前配置审查

`AppScope/app.json5` 的 `bundleName`、版本号和图标配置完整。
`entry/src/main/module.json5` 声明 `audioPlayback`、`INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING` 和 `READ_AUDIO`。

其中 `READ_AUDIO` 是用户授权权限；如果采用系统 `AudioViewPicker` 让用户主动选择文件，应优先走选择器的受控 URI 访问，不要把“选择器可用”和“全库扫描授权”混为一谈。
若产品要扫描公共媒体库，必须重新核对权限等级、运行时申请、隐私说明和应用市场要求。

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
& $hdc shell aa start -a EntryAbility -b moe.ouom.neriplayer.hmos -m entry
```

**双实例（2026-08-22 M7.5 验证）**：`Emulator.exe -start 'Mate X7'` 可再起第二个实例（foldable 与 phone 共享 phone_all_x86 镜像），hdc 端口自动分配（实测 5561，需 `hdc tconn 127.0.0.1:5561` 探测）；一份 HAP 用双 UDID profile 签名即可双端安装：`sign-local.ps1 -Device <A> -DeviceIds <udidA>,<udidB> -HvigorwPath ...`（`-DeviceIds` 必传，`-Device` 只是安装目标）。devecocli 的 ui 子命令在多设备下用 `--device 127.0.0.1:<port>` 区分。guest 无 root/su：`ifconfig eth0 down`、`kill -19` 均 Permission denied，无法在 guest 内断网/冻结进程。

不要提交签名材料、调试 Profile、HAP、设备标识或本地日志。

### 7.4 2026-08-13 可重复验证记录

| 项目 | 结果 |
| --- | --- |
| `ohpm install --all` | 成功 |
| `hvigorw clean --no-daemon` | `BUILD SUCCESSFUL` |
| Debug `assembleHap` | `BUILD SUCCESSFUL`，生成 unsigned HAP；6 条非阻塞异常处理警告 |
| ArkTS 单元测试 | `Tests run: 3, Failure: 0, Error: 0, Pass: 3` |
| 调试签名与覆盖安装 | 成功；仅用于本地调试 |
| 冷启动 | `EntryAbility` 和应用进程保持 `FOREGROUND` |
| 首页安全区 | 标题不再侵入状态栏；应用保留状态栏和导航栏 |
| 设置 → 账号与登录 | 网易云音乐、Bilibili、YouTube 三行正常渲染并可点击 |
| 登录能力 | 三个平台仍明确标注“待移植”，未声明为已完成 |
| 崩溃检查 | 未发现 `JS_CRASH`、`CPP_CRASH`、`FaultLogger`、Fatal 或未捕获异常特征 |

该 smoke test 只证明当前构建、启动、系统安全区和账号占位入口可用，不代表在线播放、登录、后台播放、AVSession、权限、下载或同步已完成设备验收。

> 2026-08-14 复核注记：上述验证基于迁移前的旧目录布局（`D:\HarmonyOS\` 根与 `D:\Neriplayer` 工程）。工具链现已整体迁至 `D:\HarmonyOS\Tools\`、工程迁至 `D:\HarmonyOS\Project\Neriplayer`，`local.properties` 已同步更新；PATH 与签名脚本的跨版本组合（见 7.1/7.3）调整后尚未整链重跑，下次构建前按 7.2 执行并更新本表。

### 7.5 2026-08-14 迁移后全链验证记录

工具链迁移与新配置（显式 `compileSdkVersion`、新增 `entry/src/ohosTest/` 骨架、重置调试密钥口令、修复用户级 PATH 与环境变量）完成后的完整验证：

| 项目 | 结果 |
| --- | --- |
| `ohpm install --all` | 成功 |
| `hvigorw clean --no-daemon`（CLT hvigorw 6.24.4） | `BUILD SUCCESSFUL` |
| Debug `assembleHap`（entry@default，含显式 compileSdkVersion） | `BUILD SUCCESSFUL in 33s`，unsigned HAP 1,197KB；6 条既知非阻塞警告（LibraryPage/PlaylistDetailPage/DebugPage） |
| 本地单元测试 `hvigorw test` | `BUILD SUCCESSFUL`；LrcParser 覆盖率 44/48 行（3 用例实际执行，报告在 `entry/.test/.../reports/`） |
| ohosTest HAP 构建（entry@ohosTest，新骨架首次编译） | `BUILD SUCCESSFUL in 20s`，unsigned HAP 1,390KB |
| codelinter 静态扫描 | 可用；17 warn + 1 suggestion，无 error（top 规则：avoid-overusing-custom-component ×15、await-thenable ×2、effectkit-blur ×1） |
| 模拟器冷启动 + `hdc tconn 127.0.0.1:5555` | Pura 90（API 24）连上；UDID 经 `bm get --udid` 获取 |
| `sign-local.ps1 -HvigorwPath <CLT hvigorw>` | 5/5 全过：构建 → debug profile → 证书链 → 签名 → 安装 |
| 应用冷启动 smoke | `aa start` 成功；进程存活；无新增 faultlog；截图确认首页正常渲染（标题栏/推荐歌单空态/四 Tab 导航） |
| 设备 ohosTest（`aa test`，OpenHarmonyTestRunner） | `Tests run: 1, Failure: 0, Error: 0, Pass: 1` |

本轮发现并已解决的阻塞：① 用户级 PATH 与 `DEVECO_SDK_HOME` 等三个环境变量残留迁移前旧路径（已修）；② DevEco 26 Beta2 的 hvigor 不能构建 6.1.1(24) 工程（构建固定走 CLT hvigorw，26 Studio 仅提供 jbr java）；③ `sign-local.ps1` 加入中文注释后因 PowerShell 5.1 按 GBK 解析无 BOM UTF-8 而静默失效（仓库 `.ps1` 必须纯 ASCII，已写入 AGENTS.md）；④ 调试密钥旧口令未知（已用 SDK stock 密钥对重加密为新 33 位口令，存用户级 `NERIPLAYER_SIGNING_PASSWORD`，原文件有备份）。
仍未就绪：API 26 模拟器镜像未下载（鸿蒙 7.0 设备侧验证需先在 SDK Manager 补齐）；真机测试未执行。**2026-08-26 更新**：`tablet_x86`（7.0.0-B2）与 `pc_all_x86`（7.0.0-B1）两份 Beta 镜像已在 DevEco GUI 内下载并完成设备回归（见 §7.1 环境准备的镜像清单与 `RELEASE_CHECKLIST.md` §1）；**API 26 SDK 仍未装**（`compileSdkVersion` 保持 24 不动），真机测试仍未执行。

### 7.8 2026-08-17 M4.1/M4.2 平台登录与凭据验证记录（Pura 90 模拟器，API 24）

| 项 | 结果 |
| --- | --- |
| entry@default / entry@ohosTest 构建 | 双 BUILD SUCCESSFUL（CLT hvigorw 6.24.4） |
| 本地单测 `hvigorw test` | 全绿（存量 42 + QrEncoder 5 + NeteaseAuth 7 = 54 用例） |
| codelinter | 18 warn + 1 suggestion，与基线持平，0 error，新增文件零缺陷 |
| 模拟器 ohosTest（全套） | **14/14**（原 8 + 新增 ActsCredentialStoreTest 3 + ActsNeteaseCookieRepositoryTest 2 + ActsNeteaseQrLoginTest 1） |
| 主应用冷启动 | force-stop 后 aa start 存活（EntryAbility 接 NeteaseCookieRepository.init() 无崩溃） |

要点与坑：

- **`@ohos.security.asset` 在 API 24 模拟器可用**：ActsCredentialStoreTest 实证 put→get→remove 往返与 backendName='asset'（add 用 CONFLICT_RESOLUTION=OVERWRITE 免 update 分支；query 用 RETURN_TYPE=ALL 取 SECRET Uint8Array 后 `util.TextDecoder.decodeToString`）。降级链路已实现但本环境未触发：服务不可用类错误码（24000001/10/11/12/13/17）→ 会话内存（设置页显示 backend 状态），明文 preferences 存凭据被红线禁止。
- **QR 生成器**（`util/QrEncoder.ets`，字节模式/ECC M/v1-10）：与 segno 参考实现字节级对齐是唯一验收标准。调试中确认的规范细节：v1 无定位图案；定位中心表 `ALIGNMENT_POS[version-2]`（v3=(6,22) 而非 (6,26)）；格式信息必须先于数据放置（否则数据位占用格式区）；segno `make()` 默认 `boost_error=True` 会静默升纠错级（夹具必须 `boost_error=False`）；码字流整字节对齐时 segno 补一个 0x00 再开始 EC/11 交替；自动掩码评分须在格式/版本信息未写入（视为亮）的矩阵上进行。4 夹具（v1/v3/v9/v10）+152 组合扫描+10 自动掩码载荷全部一致（开发用 Node 原型验证后转录）。
- **QR 登录真网 smoke**：createSession（weapi /weapi/login/qrcode/unikey）→ qrContent 含 codekey；checkLogin（/weapi/login/qrcode/client/login）对未扫码的 fresh key 返回 801。803 确认路径（jar cookie 经 /weapi/w/nuser/account/get 校验 + x-refresh-token 头兜底种 MUSIC_U）需真机扫码，未自动化。
- **ohosTest HAP 手动签名**（复用 §7.7 结论）：sign-local.ps1 生成 signing/ 材料后，对 `entry-ohosTest-unsigned.hap` 用相同 hap-sign-tool sign-app 命令（本记录实测 `-compatibleVersion 9`）签名安装即可。
- 模拟器跑 aa test 前仍须 `power-shell wakeup; power-shell setmode 602`（§7.7 坑）。

## 8. 测试计划

### 8.1 纯逻辑测试

当前基线位于 `entry/src/test/`，通过 `@ohos/hypium` 和 Hvigor 本地单元测试任务执行 **1035 个用例**（2026-09-17 静态清点 `it(` 声明；最近一次全量执行记录为 2026-08-29 的 874/874 全绿，`docs/FEATURE_MATRIX.md`；此前各里程碑计数 3→42→…→809→816→848→874→935→980→1035 递增，`hvigorw test` 默认不打印计数，结果读 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`）。测试不访问设备和第三方网络。该结果不替代需要安装测试包并通过 `aa test` 执行的设备侧 JsUnit/Instrument 测试。

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
- [ ] 目标 API（26.0.0）完整功能回归通过；2026-09-07 迁移后设备侧回归未执行（见 §7.12），此前 API 24 阶段的设备实测记录见 §7.6～§7.10。Beta API 未混入生产路径。
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
  - 2026-08-24 M9.3 部分闭合，逐项实况见 `docs/RELEASE_CHECKLIST.md`：**已完成**——字号缩放（开启 followSystem 并在 1.45×/1.75× 两档度量，修掉 3 处真实缺陷）、触控目标（度量确认 40vp 下限，**并修正旧结论：实际未达 ≥48vp 推荐值，约 30 控件落在 40–48vp**）、内存冒烟（127–151 MB 无单调增长）、隐私与市场合规清单（权限清单、无第三方统计/崩溃 SDK、诊断仅本地+导出前脱敏、凭据走 asset）、phone 377vp 与 foldable 展开内屏 707vp 两形态布局回归。**仍未完成**——tablet 2880×1920 与 2in1 3120×2080（镜像未下载，执行计划 M9.3a）、折叠外屏 346vp（传感器 hdc 无法注入）、横屏、真机全部指标、屏幕朗读实际听读效果（已补 21 处 `.accessibilityText`/13 文件，但 `uitest dumpLayout -e accessibilityText` 被工具拒绝、本链路无法导出无障碍属性验证）、熄屏 30 分钟功耗（CPU 0.017%/0.74% 只是代理指标，模拟器无电量计）。故本项**不得整体勾选**。
  - 2026-08-25 按少数派《鸿蒙上架指南》第一章补做设计/交互/生态规范自查，逐条记录见 `docs/UX_COMPLIANCE_AUDIT.md`。**已整改**——分层图标（原 216×216 单层且 22.3% 透明 → 前后景各 1024×1024，背景层写成无 alpha 通道的纯色 PNG）、启动页背板与图标背板统一为 `#1E293A`、全量沉浸式（系统栏透明 + 背景层 `expandSafeArea`，底部固定控件上抬 28vp 并修掉 Tab 栏 56→50vp 挤压）、深色模式冷启动（`systemDark` 原硬编码 false 导致系统深色下整会话渲染浅色）、状态栏首帧对比度、路由转场动效（10 个全屏路由原为单帧硬切）、权限最小化（删除从未申请的 user_grant `READ_AUDIO`，`reason` 按场景+动作+目的重写并补 zh_CN）、**上架红线：首启弹窗补「不同意」+ 二次确认后礼貌退出，新增应用内可离线打开的隐私政策与用户协议**。**仍未完成**——大屏三档响应式布局（`GridRow`/断点系统零命中，本轮按决定仅登记不改码；只要 `deviceTypes` 保留 tablet/2in1 即为强制项）、法务文案定稿并同步 AGC（当前为 `v1.0.0-draft` 草案）、重大政策变更重新征同意（文案已承诺、代码未实现）、键鼠支持。**验证边界**：本轮无可用设备（`hdc list targets` 恒 `[Empty]`），仅 `assembleHap` BUILD SUCCESSFUL 与 codelinter `25 warn / 2 suggestion / 0 error` 为实测；单测未运行，M9.3 的 798 pass 对**当前源码**降级为「有历史证据 / 待复核」；全部 UI 表现与权限删除的设备冒烟均**未验证**。
  - 2026-08-26 tablet / 2in1 镜像阻塞解除后完成两形态回归（**跑的是 API 26 Beta 而非目标 6.1.1(24)**），四类布局缺陷全 0，但暴露 11 条大屏信息密度问题；根因是全项目未使用 ArkUI 标准响应式组件（`GridRow`/`Navigation`/`Tabs`/断点 grep 零命中），已同日整改：`Tabs`/`TabContent`（大屏 `.vertical(true).barWidth(96)` 侧边栏）、`Navigation`/`NavDestination` + `NavPathStack`、`GridRow`/`GridCol` 按断点分列、`ContentBand` 栏宽（正文 600vp / 列表 840vp / 按钮 360vp）、硬编码 28vp → `TYPE_NAVIGATION_INDICATOR` 动态避让，共 24 文件（新增 3）。**已完成**——tablet 一档 7 页改后复测四类缺陷全 0、11 条密度问题逐条填回实测数字、返回栈未双弹、本地单测 819/819、codelinter 0 error。**仍未完成**——phone 与 2in1 的改后复测、2in1 上「自由窗口避让区 0 → 抬升量 0」这一动态避让核心验收点、动态跨断点切换、字号三档改后复测、目标 API 24 上的 tablet/2in1、折叠屏悬停态、触控目标 48vp、横屏、真机、朗读听读、熄屏功耗。逐项见 `docs/UX_COMPLIANCE_AUDIT.md` §8.2/§10.2/§11.5 与 `docs/RELEASE_CHECKLIST.md` §1/§7.3。
  - 2026-08-27 phone（Pura 90，**唯一 API 24 形态**）改后复测完成，`Tabs` 底部栏分支首次上设备：Tab 单格 97.8vp 与改造前逐像素一致、避让区 27.85vp 且 Tab 底边与指示器上沿重合（S2 判定规则在目标 API 上成立）、首启与全页四类缺陷 0、深/浅/auto 三档无缝、字号 1.45×/1.8125× 三处旧缺陷无回归、返回栈无一次双弹、内存 6 轮平台期 257–264MB 无泄漏；静态与单测复跑持平（codelinter 26/2/0、819/819）。**复测发现并修复两处真实缺陷**（tablet 轮漏检，因 tablet 色带与页面同色不可见）：① 指示器条带与 Tab 栏 28vp 色差接缝——NavBar 内容区内层 `expandSafeArea` 不延伸，改由 `Tabs` 容器自身背景铺底（`Tabs` bounds 天然到窗口物理底边）；② `NavDestination` 默认白背景在深色模式内容区以下露白边，显式置透明回落 Index 沉浸层。均改在 `MainShell.ets`。一个未复现的观察项（后台改显示密度后恢复时一次 Back 直接退出）已登记 audit §11.6。证据前缀 `tools/.m9/pa*`。
  - 2026-08-27 深夜 2in1（MateBook Pro，API 26 Beta）改后复测完成，**ArkUI 改造轮三形态证据收齐**：自由窗口 1100vp 侧边栏 96.3vp 固定、**S2 核心验收点通过**（避让区 0 → 抬升 0，TabBar 底边距窗口底 0.0vp，整改前 27.9vp 纯死区）、**跨断点 809↔1101vp 双向换栏**且两次重建后页面状态保留、最大化 1642vp 侧边栏保持、四类缺陷全 0、设置行 716.8vp/法务 568.4vp/每日推荐 6 卡每行、深色含 DecorBar 跟随。**环境事故记录**：bundleName 已在工作树改为 `moe.ouom.neriplayer.hmos`（08-27 上午的未提交变更，晚于当日提交），2in1 模拟器上旧名残留包与新包同图标并存，`aa start -b moe.ouom.neriplayer` 误启动旧应用产生一串假阳性；**旧包需卸载、所有 `-b` 参数需随改名更新**（排查记录 audit §11.7）。另记该 Beta 镜像 a11y dumpLayout 树不稳定（需截图像素交叉验证）、DecorBar 按钮顺序实测为最大化/最小化/关闭。证据前缀 `tools/.m9/wb*`。

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

### 7.6 2026-08-16 M1 播放核心补强验证记录（Pura 90 模拟器，API 24）

- 本地单测 42 用例全绿（Lrc 3 + PersistedPlaybackState 5 + QueueEngine 21 + AudioInterruptPolicy 6 + SleepTimer 7），命令 `hvigorw.bat test --mode module -p product=default -p buildMode=debug --no-daemon`。
- entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 与基线持平（17 warn + 1 suggestion，另 2 条 await-seek warn 为存量）。
- ohosTest 4/4（aa test）：ActsAbilityTest、ActsPlaybackStateRestoreTest×2（冷启动恢复队列+索引+位置+模式、损坏兜底）、ActsPlaybackSmokeTest（真实网络音频 `w3schools.com/html/horse.mp3`：initialized→prepared→audioInterruptMode=SHARE_MODE→playing→paused→release 全链通过，证明模拟器外网可达且 AVPlayer 中断模式可设置）。
- 冷启动 + force-stop 重启恢复 smoke：两次启动均打出 `PlayerManager restored queue: 3 songs at index 1`（应用级 preferences 跨进程/跨模块共享，AppPreferences 已改 getApplicationContext）。
- 平台事实（API 24 实证）：
  - preferences 的 UIAbilityContext 指向模块级 `haps/<module>/preferences`，必须 `context.getApplicationContext()` 才是应用级共享文件；`AbilityDelegator.getAppContext()` 构造的 context 被 preferences 判 invalid（stageMode=false）。
  - AVPlayer.on('audioInterrupt') 事件 `audio.InterruptEvent{hintType,forceType}`，SHARE_MODE 须在 prepared 后、首次 play 前设置；RESUME 恒为 SHARE 需应用主动 play（文档 https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/audio-playback-concurrency）。
  - `backgroundTaskManager.startBackgroundRunning` 在 API 24 必传 wantAgent（`(context, BackgroundMode, WantAgent)` 重载），权限 ohos.permission.KEEP_BACKGROUND_RUNNING；后台音频必须 AVSession + AUDIO_PLAYBACK 长时任务（https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-background-scene）。
  - AVSession off() 只接受字面量事件名；AVMetadata 封面字段为 mediaImage（string|PixelMap）。
  - hypium 1.0.28 不 await async beforeAll/it 钩子（beforeAll 内异步初始化不可靠，用例内自行 await 幂等 init）。
- 未自动化（模拟器 UI 自动化不可行，待人工/真机复核）：搜索→播放 UI 全流程、双媒体竞争中断、熄屏 30 分钟长播、锁屏/控制中心封面显示。

### 7.7 2026-08-16 M3 下载管线验证记录（Pura 90 模拟器，API 24）

- ActsDownloadSmokeTest 两次通过：网易云搜索「晴天」→DownloadEngine.enqueue→DIRECT 传输 5,889,065 字节→commit 至 `<filesDir>/Download/NeriPlayer/netease - 周杰伦*.m4a`→编目完整→文件只读可开→再次 enqueue 防重复短路。全套 ohosTest 8/8（Ability+Restore×2+PlaybackSmoke+SchemaRecovery×3+DownloadSmoke）。
- 主应用冷启动 smoke（含离线短路/双轨收口改动）无崩溃；本地单测通过（含 DownloadTaskStore 域 23 用例，两轮验证退出码 0）；entry@default/entry@ohosTest BUILD SUCCESSFUL；codelinter 18 warn+1 suggestion 与基线持平。
- ohosTest HAP 签名：与 sign-local.ps1 相同的 hap-sign-tool sign-app 命令手动签 `entry-ohosTest-unsigned.hap`（复用 signing/ 材料+同一 UDID），debug profile 无模块限制，entry/entry_test 共用可行。
- 平台事实（API 24 实证）：
  - **模拟器熄屏/锁屏跑 aa test 必失败**：TestAbility onForeground 后 ~90ms 被切后台销毁，输出 `TestFinished-ResultCode: -2 TestAbility onDestroy unexpectedly!`，hypium 无任何用例执行痕迹（hilog 特征：完整 onCreate→onWindowStageCreate→onForeground→onBackground→onDestroy 链）。跑设备测试前必须 `hdc shell "power-shell wakeup; power-shell setmode 602"`（唤醒+常亮），锁屏时另加 uinput 上滑解锁。
  - `http.requestInStream` 的 promise 与 dataEnd 事件时序不保证先后：传输成功（NETSTACK RespCode 206、字节完整）时 promise 可能晚于 dataEnd settle，若 dataEnd 固定 resolve(0) 会屏蔽真实响应码——流式下载成功判定应以「dataEnd 到达+接收字节校验」为准，响应码仅作错误分类（HttpStreamDownloader/DownloadEngine.transferSizeComplete 按此实现，对齐 Android isTransferSizeComplete）。
  - ArkTS 类字段须有初始化器（`x: string = ''`）+ constructor 赋值后才可靠参与 JSON.stringify(this)；`JSON.stringify(arr.map(e => e.toJson()))` 会产生 JSON 字符串数组的双重序列化，按对象数组解析时静默退化为全空条目（下载编目 bug 根因，已修复并加空行自愈过滤）。
- 未自动化（待复核）：下载中途杀进程→重启续传端到端（队列持久化+replace 恢复语义有单测）；断网暂停/恢复设备实测（模拟器禁网有断 hdc 风险，netUnavailable 路径有单测）；离线播放 UI 人工核验；编目单值超长（>8KB）场景。

### 7.9 2026-08-18 GitHub Actions CI 上线记录

- 仓库根 `.github/workflows/harmonyos-ci.yml`（GitHub `suyunxing/NeriPlayer-HarmonyOS`，私有，记录时默认分支 `su`；**2026-08-31 复核已切换为 `dev`**，push/PR 触发规则未变）。触发：push 到 `main`、`dev`，PR 到 `main`、`dev` 或迁移期兼容分支 `su`（直接 push 到 `su` 不触发；paths 限定 `NeriPlayer-HarmonyOS/**` 与 workflow 自身）+ 手动 `workflow_dispatch`；同一 PR 或分支并发取消旧跑。dev 分支上早先手写的 `build-pr.yml` 草稿（npm install/hvigor 命令不可用）已删除，以本文件为准。
- 工具链：`ErBWs/setup-ohos@v2` action，从社区镜像仓库 `ErBWs/ohos-sdk` Releases 下载 Command Line Tools **6.1.1.280**（SDK 6.1.1.125 / API 24，与本机 CLT 6.1.1.300 同 SDK 基线；hvigorw/ohpm/Node 进 PATH，`cache: true` 缓存 `~/ohos-sdk`）。华为官网 CLT 下载需账号登录无法直链，镜像分卷资产带 sha256 校验。**不要用镜像里的 26.0.0.621**：其 hvigor 6.26.x 不能构建 6.1.1(24) 工程（同 7.1 的 00303031 限制）。
- 步骤：`apt libgl1-mesa-dev` → setup → `ohpm install --all` → debug `assembleHap` → 上传 debug unsigned HAP（PR 保留）→ push/手动运行时再构建并上传 release unsigned HAP（14 天）→ Linux 单测诊断。**hypium 本地 runner 在 Linux CI 上挂死**（`UnitTestArkTS` 编译完成后 `> hvigor Linux` 起零输出；本机 Windows 同命令可完成），故单测限时 4 分钟、保留退出码但不阻塞构建，打印 `.test` 目录树并上传 `test-output` artifact。缓存 `~/ohos-sdk`（action 自带）、`~/.ohpm`、`~/.hvigor`。
- 已知事实：hypium 断言失败不会使 `hvigorw test` 非零退出（本机 StreamHeaders 用例失败仍 BUILD SUCCESSFUL/EXIT 0），CI 的单测把关需解析报告而非依赖退出码；Linux 挂死根因未明，修复后应移除限时与非阻塞。
- 2026-08-18 首轮验证：run 32048335317（dev）单测步骤 40 分钟零输出超时取消；二轮 run 32083328097 通过（conclusion success）——单测 `exit=124` 挂死复现（`.test` 下仅 testability 骨架、outputs 从未生成），debug/release HAP 分别 19s/14s 构建成功，`hap-unsigned-2`（782KB）产物正常。工具链下载+解压约 3 分钟；被取消的 run 不写 actions/cache，需完整成功跑一次后后续 run 才命中缓存。

### 7.10 2026-08-19 M5.3 GitHub 传输层验证记录（Pura 90 模拟器，API 24）

- 本地单测 316/316（284 存量+32 新增，fake 执行器驱动 Git Data API 全流水线与错误分类）；entry@default / entry@ohosTest BUILD SUCCESSFUL；codelinter 24 warn+1 suggestion 基线持平 0 error；全套 ohosTest **25/25**，其中 **ActsGitHubTransportTest 5/5 真网**（octocat/Hello-World 匿名公开读：repo info→branch head→raw README；backup.json 缺失→null snapshot；匿名与无效 Bearer `/user`→401→TOKEN_EXPIRED；无效 token `updateBranchRef` PATCH→401，即 PATCH 请求行被 GitHub 认真接受而非 404/405）；冷启动 smoke 无 crash。
- **平台事实（API 24 实证 + netstack 源码/文档三重核对）**：
  - `@ohos.net.http` 的 `RequestMethod` 枚举无 PATCH（OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT），但 `HttpRequestOptions.customMethod?: string`（**@since 23**，本机 SDK d.ts:576）可发任意自定义方法：netstack `ParseMethod()` 优先读 customMethod、`CURLOPT_CUSTOMREQUEST` 写请求行、body 非空走 `CURLOPT_POST+POSTFIELDS`——`customMethod:'PATCH'` + `method:POST`（保证 body 上传）= 真 PATCH 带 body。M5.3 的 GitHub 同步乐观锁（PATCH /git/refs force:false）依赖此。
  - **GitHub REST「合并」端点不能当乐观锁用**（doc-researcher 私有仓库逐 case 实测，2026-08-19）：`POST /merges` base 未分叉时也必然创建双父 merge commit、无 fast-forward 校验、并发推进时若无文件冲突照样成功——无法表达「base 被推进则失败」；备选 GraphQL `updateRef` 的 `refId` 是 Ref 的全局 Node ID（非 "refs/heads/main" 字符串，需先 query 取 ID），非 ff 时返回 HTTP 200 + errors[].type=UNPROCESSABLE（message 原文拼错为 "fast-foward"，判定勿按正确拼写匹配）。最终定案用 customMethod PATCH 直连 REST，与 Android 语义完全一致。
  - 模拟器跑长 aa test：`power-shell setmode 602` 的常亮只维持 ~10s（覆盖时间被重置），必须再 `power-shell timeout -o 600000` 延长，否则测试中途熄屏仍触发 onDestroy unexpectedly（本轮 25 用例耗时约 3 分钟曾两度复现）；锁屏状态另需 uinput 上滑解锁（§7.7 坑不变）。
  - Emulator.bat 冷启动在部分 shell 环境下进程不驻留（无窗口即退），可用 `Emulator.exe -start 'Pura 90'` 直启（返回码 0 且 GUI+crash-service 进程驻留）。
  - Git Bash 下 hdc 对绝对路径参数会把 Git Bash cwd 拼成非法路径报假 fail，本地 HAP 路径用相对路径（install 用 `cd` 到产物目录后传文件名）。
  - `SyncDataJsonCodec.escapeJsonString()` 返回**带引号的完整 JSON 字符串字面量**（`'"'+escaped+'"'`），不是纯转义文本——拼接请求体时外层不要再手写引号（双重引号产出坏 JSON，GitHub 必 400；M5.3 单测拦截的真 bug）。
- 未自动化（待复核）：带真 PAT 的写路径端到端（真实 blob→tree→commit→PATCH ref 提交、设置页测试连接/创建仓库/远端检查 UI 流）需用户提供 PAT 人工验证；「立即同步」完整三路合并闭环属 M5.5。
- 产物为 unsigned HAP：CI 无签名材料，签名仍在本地走 7.3 的 `sign-local.ps1`（符合"证书与口令不入库"约定）。
- 未纳入 CI：codelinter（存量基线 **24 warn + 2 suggestion**，2026-08-24 M10.1 复核值；2026-08-18 CI 落地时为 17 warn+1 suggestion，差额来自此后新增模块的存量告警，0 error 始终未变——需过滤规则后才可门禁）、ohosTest（需模拟器+签名）、Release 自动发布。后续可选：tag 触发上传 unsigned HAP 到 GitHub Release。
- 2026-08-18 协作配置补齐：新增 `.github/PULL_REQUEST_TEMPLATE.md`、HarmonyOS Bug/Feature/分支整合 Issue Forms、`.github/dependabot.yml`、根目录 `CONTRIBUTING.md` 与 `docs/GITHUB_COLLABORATION.md`；workflow 增加 `contents: read`、关闭 checkout 持久凭据、按 lockfile 失效依赖缓存，并使用 PR 号/分支维度并发组。目标模型为 `main` 稳定、`dev` 集成、个人/feature 分支 PR 协作；`su` 在迁移期只保留 PR 检查，不响应直接 push。未修改 Android 参照工程与业务源码。

### 7.11 2026-09-07 下载目录选择落地记录（服务器 Linux CLT 26.0.0.821，无设备）

- 实现（分支 `feature/下载目录选择`）：设置→下载设置→「下载目录」行（原「目录选择待移植」占位替换）+ 自定义时追加「恢复默认目录」确认行。新增 `download/DownloadDirectory.ets`（纯逻辑，8 单测）与 `download/DownloadDirectoryManager.ets`（picker/fileShare 胶水）；`DownloadStorage` 目录解析改为「配置的 URI 优先，否则沙箱默认」，自定义目录 commit 从 `renameSync` 改为 fd 对拷（`FileUri(...).path` 转换后 `openSync(CREATE)`），`init` 对自定义目录跳过 `ensureDir`；`DownloadEngine.init` 追加冷启动 `activatePermission`；设置 key `np.download_directory_uri`/`np.download_directory_label`（空=默认，对齐 Android `download_directory_uri`/`_label` 双 key 语义）。
- 平台事实（官方文档 + 本机 SDK d.ts 核实，**非设备实证**）：
  - 文件夹选择现行 API 是 `DocumentSelectOptions.selectMode = picker.DocumentSelectMode.FOLDER`（API 11+，SC `SystemCapability.FileManagement.UserFileService.FolderSelection`；不存在 `documentViewMode`）。官方《选择用户文件》指南注明 **FOLDER 类型在 Phone 设备 26.0.0 起才支持**——本工程 6.1.1(24) 设备上 `canIUse` 预计 false，入口已做降级 toast。`select()` 直接返回 `string[]`（无 `DocumentSelectResult` 包装）。https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file
  - picker 返回的目录 uri 只有临时读写授权；跨重启须 `fileShare.persistPermission`（API 11+，需 `module.json5` 声明 `ohos.permission.FILE_ACCESS_PERSIST`，按 system_grant 方式声明即用、无运行时弹窗），且**每次冷启动须 `activatePermission` 重新激活**（持久化授权不会自动加载）。`PolicyInfo` 为 `{uri: string, operationMode: number}`，读写组合 `READ_MODE | WRITE_MODE`。https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission
  - fs 对目录 URI 的操作边界：`openSync(uri + '/<name>', READ_WRITE|CREATE)`（官方 DOWNLOAD 示例即此写法，建议先 `new FileUri(...).path` 转换）与 `fs.stat(path)`（path 参数 API 22+ 支持 URI）有文档承诺；`renameSync`/`mkdirSync`/`accessSync`/`unlinkSync`/`listFileSync` 参数文档只写「应用沙箱路径」，对 URI 不可依赖——这是 commit 改 fd 对拷、init 跳过 ensureDir 的依据。
- 验证（服务器，2026-09-07）：`hvigorw --no-daemon assembleHap` BUILD SUCCESSFUL；`hvigorw test` 编译级 0 error（执行阶段挂死为 §服务器已知限制，新用例已编入测试 abc，真实计数待 Windows 工作站）；codelinter 改动文件 **0 新增**（全仓现值 5 error + 23 warn + 3 suggestion，5 个 `await-thenable` error 均在 8 月存量文件——AmllLyricsResolver/AppPreferences/CoverColorCacheCore/YtmLoopbackStreamBridge，与 2026-08-24 基线「0 error」漂移，属基线漂移或 codelinter 版本变化，待单独复核，非本次引入）。
- 未验证（设备侧全部）：API 24 真机/模拟器上 `canIUse(FolderSelection)` 实际值；FOLDER 选择器实际拉起与返回 uri 形态；persist/activate 真实生效；uri 下创建文件/中文文件名/播放（catalog 存 uri 后 `openSync(READ_ONLY)`）冷启动可读；`FILE_ACCESS_PERSIST` 在真机的授予行为（华为在线权限列表页 JS 渲染未能核对该权限级别）。恢复默认后旧目录授权保留策略（保播放）未在设备回归。

### 7.12 2026-09-07 API 26 全量迁移记录（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/api26-migration`）

工程从 6.1.1(24) 整体迁移到 26.0.0(26)。所有结论以本机 SDK `.d.ts`（`/opt/command-line-tools/sdk/default`，apiVersion 26，releaseType Release）与官方文档为依据，**无任何设备实证**。

- 配置：根 `build-profile.json5` 的 `compatibleSdkVersion`/`targetSdkVersion` 均改为 `"26.0.0"`（纯 SemVer，带 `(26)` 后缀会被 hvigor 拒绝）。`module.json5`/`app.json5` 无需配套改动（minAPIVersion/targetAPIVersion 由打包工具自动注入）。
- 弃用接口修复（编译器在新基线暴露，全部替换为官方 `@useinstead`）：
  - `util.TextDecoder.decodeWithStream`（@deprecated since 12）→ `decodeToString`：`download/DownloadStorage.ets`、`ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets`。
  - 全局 `animateTo` → `UIContext.animateTo`：`view/pages/NowPlayingPage.ets:154`（封面 crossfade）。
  - `AlertDialog.show`（@useinstead `UIContext#showAlertDialog`）→ `this.getUIContext().showAlertDialog`：`view/pages/SettingsDetailPage.ets` 6 处确认对话框。
- 有意保留的弃用：`app/diagnostics/CrashEventWatcher.ets` 的 `FaultLogger.querySelfFaultLog` 拉取通道（faultLogger 模块 @deprecated since 18，官方指向 hiAppEvent，但新版 `@ohos.hiviewdfx.hiAppEvent` 仍**无历史故障查询接口**，addWatcher 只订阅不回放；`FaultLogExtensionAbility` 是需注册 ExtensionAbility 的延迟通知机制，架构改造代价大）。该组弃用告警为已知项。
- 新特性接入（均为既有功能的 API 26 升级）：
  - `player/AVSessionManager.ets`：`setMediaCenterControlType`（@since 26）向播控中心显式声明按钮集 `playNext/playPrevious/setSpeed/setLoopMode/toggleFavorite`（与 `on()` 注册命令一一对应；失败降级为系统默认布局，不阻塞会话）。
  - `player/BackgroundTaskRunner.ets`：`continuousTaskCancel` 日志接入 `detailedReason`（@since 26，`ContinuousTaskDetailedCancelReason`，可区分用户划除通知(3)与播放合规审计(6)等精确触发；字段缺省时留空兼容）。
- 评估后不接入（结论备查）：
  - `window.setImageForRecent`（多任务卡片自定义封面，@since 20 在 26 权限列表中开放权限名）：需 `ohos.permission.MANAGE_RECENT_SNAPSHOT`（system_basic 级，三方应用不可申请），跳过。
  - AVPlayer 原生播放列表（`addPlaybackMediaSource`/`playlistLoopMode`/`onPlaybackContentChanged`，@since 26）与 `createAVDownloaderManager` 流式下载（@since 26）：与既有 `QueueEngine` 状态机/自研下载引擎（Range+If-Range 指纹、HLS checkpoint）是整体替换关系而非增量升级，牵动播放恢复、一起听同步与 900+ 单测，本轮不做，留待独立专项。
  - AVPlayer `seek` 在 26 仍为 `void`（无 Promise 重载），原样保留。
- targetSdk 26 行为变更核对（逐项走查，均不受影响）：后台「真播放」审计收紧——本工程暂停即 `stopBackgroundRunning`，已合规；沙箱 stat/access 收紧——无硬编码沙箱路径；剪贴板读取需 PasteButton/权限——工程只写不读；Dialog/Toast 默认沉浸材质——工程弹窗均走系统默认样式，与 glass UI 方向一致，**视觉实际效果待设备复核**；`WindowProperties.type` 更名 `windowType`、avSession `playFromAssetId`（since 20 废弃）——工程均未使用。
- 验证（服务器）：`hvigorw --no-daemon assembleHap` BUILD SUCCESSFUL 且无新增弃用告警；`hvigorw test` 编译级 0 error（执行阶段挂死为 Linux 已知限制，真实通过计数待 Windows 工作站）；codelinter 全仓 5 error + 23 warn + 3 suggestion，与迁移前 stash 基线**逐字节一致**（5 个 `await-thenable` error 为 CLT 26.0.0.105 codelinter 对 8 月存量文件的误报，见 §7.11），本次 8 个改动文件 0 error 0 warn。
- 未验证（设备侧全部）：播控中心按钮实际渲染；`detailedReason` 实际取值分布；26 镜像上全功能回归（播放/下载/同步/一起听）；弹窗沉浸材质视觉。`compatibleSdkVersion` 抬至 26.0.0 后 26 以下设备无法安装，属预期取舍（用户要求全量迁移）。

### 7.13 2026-09-07 API 26 原生播放列表桥接与播放缓存落地记录（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/api26-migration`）

§7.12 中「评估后不接入」的两项按既定定位落地：原生播放列表作为 QueueEngine 之下的**换源加速层**（不替换状态机），AVDownloaderManager 作为**播放缓存补充**（不替换下载引擎）。所有平台调用 8s 超时包裹 + 首次硬失败按进程闭锁（防 `setLoudnessGain` 式挂死桩），全部带回退路径。

- **原生播放列表桥（gapless 切歌）** `player/AvPlaylistBridge.ets` + 纯策略 `player/AvPlaylistPolicy.ets`：
  - 架构：`handleCompletion` 的全部仲裁（睡眠定时、一起听房间、单曲循环重播、TRACK_FINISHED 上报）保持应用侧；仅当仲裁决定前进时，才用内核 `advanceToNextMediaSource()` 换源（无 reset/prepare 空窗）。`playlistLoopMode` 钉死 `NONE`，系统永不自行前进。
  - 预热条件（AvPlaylistPolicy.shouldPrimeNext，5 门全查）：非单曲循环、队列 ≥2、无一起听会话、引擎会前进、**下一首可离线解析**（下载目录条目或本地文件）。网络流永不预热：预解析每首歌多打一次平台 API（B 站风控教训）且签名 URL 在前进时大概率过期。
  - 预测一致性：`peekNextIndex` 用 `QueueEngine.toJson()/fromJson()` 全量克隆（含种子随机态）预测 `next(force)` 落点；完成时若克隆预测 ≠ 桥内缓存索引（模式中途切换等）→ 弃用预热回退 loadSong。`QueueEngine` 补 `getQueueSize()`。
  - fd 生命周期：桥持有预热源的 fd，consume（前进已消费）/abandon（新加载、REPLAY、STOP、清空队列）/失败三条路径都恰好释放一次。
  - PlayerManager 接线：`loadSong` 前缀抽为 `beginTrackTransition`（原生前进复用同一套元数据/历史/统计/自动匹配副作用）；`ensurePlayer` attach；`clearQueue`/`loadSong` 开头 abandon。
- **播放缓存** `player/PlaybackCacheManager.ets` + 纯账本 `player/PlaybackCacheLedger.ets`：
  - 设置 `np.playback_cache` 默认关（opt-in，设置→播放设置→「播放缓存（实验）」）。语义：在线流播放成功后后台入队 `addAVDownloadTask`（带防盗链头），完成后系统缓存目录记入 LRU 账本（上限 24、SchemaStore 持久化、驱逐目录 best-effort rmdir、僵尸任务 5 分钟清扫）；下次 `loadSong` 在下载目录之后、房间权威链接之前查缓存命中（`createMediaSourceWithDirectory` 离线秒开；一起听会话中让位；失效命中自愈剔除）。Wi-Fi only（系统默认）。与文件下载引擎并存不替代。
- 单测：新增 `AvPlaylistPolicy.test.ets`（5 例：force 镜像、顺序/随机 peek 精确预测、不变更引擎、五门禁）+ `PlaybackCacheLedger.test.ets`（6 例：命中 touch、LRU 驱逐、刷新不驱逐、remove、JSON 往返、损坏降级），编入本地套件。
- 设备探针（ohosTest，待真机/Windows 跑）：`ActsNativePlaylistProbeTest`（2 例：API 可达性+advance 落点+contentChanged 回传 id、NONE 模式 5s 静默窗不自进）与 `ActsAvDownloaderProbeTest`（1 例：manager 创建→小 MP3 下载完成→getTaskCacheDirectory→目录源 prepare 全链）。
- 验证（服务器）：entry@default assembleHap **BUILD SUCCESSFUL 0 error**；entry@ohosTest assembleHap（含两个探针）**BUILD SUCCESSFUL 0 error**；`hvigorw test` 编译级 0 error（执行挂死为 Linux 已知限制，真实计数待 Windows 工作站）；codelinter 14 个改动文件 **0 新增缺陷**（全仓仍为基线 5 error + 23 warn + 3 suggestion）。
- 未验证（设备侧全部）：gapless 实效与 advance 是否跳过 prepare 周期（探针 1 回答）；NONE 模式是否真不自进（探针 2）；缓存目录跨进程存活与 prepare 可行性（探针 3）；B 站带 Referer 头的下载任务是否被 CDN 接受；缓存命中音频与在线流音质一致性。

### 7.14 2026-09-08～09-14 真机反馈修复与播放页转场波次记录（分支 `dev`，PR #20–#30）

本节为波次汇总；单事件取证在专项文档与看板，不在此重复。波次内各提交以服务器侧构建、改动文件 codelinter、`hvigorw test` 编译级检查为常规门禁（Linux 测试执行段挂死为已知限制），push/PR 由 CI（`harmonyos-ci.yml`）复核；**设备侧结论来自用户真机反馈**（日志/录屏/诊断输出），非本服务器取证。

- **网易云登录四连修复**（3f4dea0f→bd4d9c0→bc19926→fe101cf）：杀后台掉登录（凭据从未落盘 + 冷启动时序）→ 803 后 Set-Cookie 双来源捕获 → Asset `ASSET_TAG_SECRET` 1024 字节上限触发 `AssetError(401)`（自动分块存储 `AssetChunking`）。取证详见 `PORTING_EXECUTION_PLAN.md` 三节「缺陷修复：网易云……（2026-09-08～09）」；扫码链路真机诊断日志实证生效，落盘修复真机复测待验证。
- **下载完整性系列修复**（77a6745→3d655fc→c60dfb1→b8ff989→b5c136d）：分块写入 `offset` 误用致带零洞坏容器、播放失败重试风暴、5400106 双根因（下载源改 legacy 干净接口 + 本地源走 `fdSrc`）、完整性门禁与 8 条边界加固。取证详见 `PORTING_EXECUTION_PLAN.md`「缺陷修复：下载完整性……（2026-09-12～14）」节；坏文件 5400106 由真机日志实证。
- **播放页一镜到底转场整层重写**（654ca5d→26b49aa，PR #24–#28，九轮迭代记录见 `docs/NOW_PLAYING_TRANSITION_20260910.md`）：最终形态为 `bindContentCover` 全屏模态 + 单一进度 `panelAmount` 分阶段**原生属性动画**（S6-core 的 `geometryTransition` 共享元素方案已整层移除；展开 300ms/收起 400ms；`NowPlayingCurves.ets` 先慢后快/回弹自定义曲线）。`Router.push(NOW_PLAYING)` 不再入 NavPathStack，改为翻转 `ui.nowPlayingShown`；起止矩形按真机录屏逐帧标定（HdsTabs miniBar 槽位测量只反映槽位布局矩形，需标定偏移换算药丸视觉矩形）。审查跟进：计时器竞态/压暗跳变/宽屏锚点（26b49aa）、迷你条切页槽位重建时播放键符号动效误闪（552df87，`symbolTrigger` 初值改 -1）。观感经用户真机多轮反馈修正；折返打断、歌词页返回、宽屏形态仍待系统真机回归。
- **壳层沉浸改版**（f38205d→8958d16→073b852→4edac60→b9589db）：外壳改用 `HdsNavigation`（§S 阶段 S0「HdsNavigation 内容子树不挂载已回退」的模拟器结论被后续版本推翻，自建 `TitleBarBlurBackdrop` 等价实现随之删除）、标题栏 `ScrollEffectType.GRADIENT_BLUR` 渐变模糊并经 `expandSafeArea(SYSTEM/CUTOUT, TOP|BOTTOM)` 延伸到状态栏后；探索/资料库/设置页与首页统一内容穿透（`.clip(false)` + 列表顶部 `expandSafeArea`）；标题栏移除系统返回与「刷新推荐」按钮。**未验证**：渐变模糊材质在真机的实际渲染档位。
- **音量淡入淡出**（54fb31f→c3acdbd）：`VolumeFader` 纯状态机 25ms 插值接入 `PlayerManager` 三类路径，后设置化为 `np.playback_fade` 总开关 + 双向时长滑条；详见 `FEATURE_MATRIX.md` 对应行。设备端听感未验证。
- **资料库收尾**（d9b209c）：统计卡片图标/新建按钮/歌单图标随封面取色重染，消除主题色残留。
- **工程协作**（d68f4f3、cbef581、8de4ca1）：配置 Copilot 代码审查（`.github/skills/harmonyos-code-review/SKILL.md`、`.github/copilot-instructions.md`、`.github/instructions/` 按 ArkTS 与 CI workflow 两域分流）；根目录与工程 README 按上游风格重写；`NeriPlayer-master/` 解除 Git 追踪并加入 `.gitignore`（磁盘保留为只读参照快照；`NeriPlayer-ASCF/` 仍在版本控制中）。
- **审查工具切换**（2026-09-16）：应用户要求移除上一条的 Copilot 审查 4 个配置文件（GitHub 侧 `copilot-pull-request-reviewer` 与 `chatgpt-codex-connector` 两个审查 App 由用户网页端停用）；AI 审查改走 CodeRabbit（`.coderabbit.yaml`，App 待装、仓库转公开后免费）+ gitleaks 密钥扫描（`.github/workflows/gitleaks.yml`，已上线）。

### 7.15 2026-09-16 二、三级页沉浸渐变模糊标题栏统一（服务器 Linux CLT 26.0.0.105，无设备，分支 `settings-card-radius`）

将 §7.14「壳层沉浸改版」的 `HdsNavigation` GRADIENT_BLUR 标题栏模式下沉到全部 12 个路由页（本地歌单/网易云歌单/B 站收藏夹/专辑/艺人/播放历史/播放统计/下载管理/一起听/调试/设置详情/协议文档），按官方 UIDesignKit「组件导航-开发实例」（`ui-design-navigation-dynamic-blur-demo`）的 HdsNavDestination 写法：

- **共享配置** `view/components/HdsSubPage.ets`（新文件）：`subPageTitleBar(title, menu?, subTitle?)` 构造与外壳逐参数对齐的 titleBar（`ScrollEffectType.GRADIENT_BLUR` 0→8vp + `BlurStrategy.ADAPTIVE` + `systemMaterialEffect`（HdsLight 探测降级）+ `enableComponentSafeArea: true`）；`SubPageBottomFade` 组件复刻 MainShell 手势条渐变遮罩（页面底色 0xD9→透明，`@StorageProp('ui.bottomLiftVp')` 跟随避让区）。
- **MainShell.pageMap**：去掉共享 `NavDestination().hideTitleBar(true)` 包装层，各路由页自身以 `HdsNavDestination` 为根（官方允许与标准 NavDestination 混用；未知路由兜底分支保留标准 NavDestination）。`onWillDisappear → Router.notifyReturned()` 返回广播随之下沉到各页。
- **每页模式**：根 `HdsNavDestination().titleBar(...).bindToScrollable([scroller]).backgroundColor(Transparent).ignoreLayoutSafeArea([SYSTEM],[BOTTOM]).onWillDisappear(...)`；滚动容器 `.clip(false)`（内容滚入标题栏下方被渐变模糊覆盖）+ List 加 `.cachedCount(3, true)`（官方 FAQ：防穿透区列表项闪空）；`ignoreLayoutSafeArea` 底边延伸后列表尾部加 `bottomLift + 32` 让位 spacer、Scroll 类页面改 padding 尾部同高。
- **结构归一**：原「固定头部 + 内嵌 List」的页面（三个歌单页、艺人页、历史页）把头图/搜索框/胶囊等并入同一个 List/Scroll 作首组 ListItem，保证整页内容可穿到标题栏下；StatsPage 曲目榜（≤100 行）直接平铺进外层 Scroll 免嵌套滚动。原页内头部操作迁入 titleBar 菜单（RecentPage 排序+说明/导出/导入/清除 5 项、DownloadsPage 清空记录、PlaylistDetailPage 歌单管理；sys.symbol 资源名经 `toolchains/id_defined.json` 核实存在）。LegalDocPage 双模式：新增 `asRoute` 属性，全屏路由走 HdsNavDestination，免责声明浮层保留自绘头部。
- **模拟器风险**：S4 曾实测 HdsNavDestination 在模拟器只渲染标题栏 chrome 不挂载内容子树（8958d16 注释）；同类的 HdsNavigation 外壳问题真机不复现（2026-09-10 用户确认），子页按官方标准启用，**模拟器行为待复核、真机渲染未验证**。
- 验证（服务器）：entry@default assembleHap **BUILD SUCCESSFUL 0 error**（首轮 10 error 为 `.margin()` 链在带尾随闭包的 `PlaylistHeader{...}` 之后的 ArkTS 语法限制，改 Column 包裹后清零）；codelinter 14 个改动文件 **0 error / 8 warn**（其中 6 warn 为 BiliFav/Netease 存量性能提示、2 warn 为 custom-component 风格提示——SubPageBottomFade 因自带 `@StorageProp` 响应式跟踪保留组件形态）。
- **修订（2026-09-16 用户真机截图反馈后）**：首版照官方 demo 用 `enableComponentSafeArea: true` 让内容避开标题栏，真机实测标题栏底下没有页面内容，光感材质渲染出自己的暖色底板，顶部出现一条淡米黄断层（与内容区冷灰背景清晰分界）；底部渐变带过矮过黑（仅 bottomLift+8、起始即 0xD9），与首页观感差距大。修复：子页布局模型整体对齐首页外壳——titleBar 去掉 `enableComponentSafeArea`（其余参数与外壳逐字一致），`ignoreLayoutSafeArea` 补 `TOP` 把内容根拉到全窗 y=0（标题栏浮在自己页面内容之上，材质模糊采样页面自身），List 首加 56vp 让位 spacer / Scroll 内容 padding top 56（让位量随内容滚走，同首页）；底部 `SubPageBottomFade` 重做为首页复合遮罩同款（92vp 渐入 0x99 → 手势条上方 0xD9 → 屏幕底边归零，总高 92+bottomLift+8），尾部让位统一 `bottomLift + SUB_BOTTOM_CLEARANCE_VP(116)`。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 8 warn（无新增）**；真机观感待用户复测。
- **修订二（2026-09-16 二轮真机截图：歌词设置页/网易云歌单页）**：(1) 顶部重合——内容根已在 y=0 但让位只补了 56vp，标题栏实占「状态栏 topInset + 56vp」，首卡约 1/3 被压在标题栏下；首页无此问题是因为首页内容区从状态栏下沿起算。修复：12 页统一 `@StorageProp('ui.topInsetVp')`，让位改 `topInset + SUB_TITLEBAR_SPACE_VP`（StatsPage loading 骨架同步）。(2) 底部黑雾——渐变终止色 `0x00000000` 是**透明黑**，插值穿过半透明黑，浅色主题下底部呈黑雾（首页同写法但该区被悬浮 Tab 栏 + gradientMask 盖住不可见，子页无遮挡直接露出）；修复：`SubPageBottomFade` 全部色标改用页面底色透明变体（含终止色），峰值 0xD9 移到手势带上沿之上 40% 处。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 8 warn（无新增）**；真机观感待复测。
- **修订三（2026-09-16 三轮真机截图）**：修订二把渐变末端回退到透明后，导航指示条区域反而无覆盖，观感是「渐变从导航条上沿才开始」（避开导航条）。修复：`SubPageBottomFade` 色标简化为三段（0x00 → 92vp 处 0x99 → 屏幕最底边 0xD9），末段一路加深直达底边、不避让手势条。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 1 warn（存量）**。

### 7.16 2026-09-18 子页 dock 态迷你条：进入二级页后迷你条下沉为 Tab 栏形态（服务器 Linux CLT 26.0.0.105，无设备，分支 `minibar-dock`）

参照网易云 Android 客户端录屏（用户提供的参考视频）：迷你条常驻悬浮于子页之上，推入二级页时 Tab 栏被盖住，迷你条从药丸原位**扩大到 Tab 栏足迹并落到 Tab 栏位置**，返回时逆向归位。此前本工程子页是全屏 NavDestination，会把 HdsTabs 连同槽位迷你条一起盖住（子页上无任何播放条）。实现：

- **深度状态源**（`view/Router.ets`）：新增 `KEY_SUB_PAGE_DEPTH ('ui.subPageDepth')`，`publishDepth()` 在 push（含 CLEAR/REPLACE_TOP/EVICT 分支）/pop/reset 每次栈操作后同步发布 `NavPathStack.size()`。所有入栈都经 `Router.push`、所有返回都经 `Index.onBackPress → Router.pop`，Router 即深度唯一事实来源（`size()` 栈操作后即时可读——push 防重决策本就依赖该语义）。
- **MiniPlayer `embedded` 形态**（`view/components/MiniPlayer.ets`）：脱离 HdsTabs 槽位独立承载时非紧凑形态去掉自带 {10,10,8} 悬浮卡片外边距（几何由使用方给定），且 `followsBarMaterial()` 恒 false——沉浸光感材质只存在于悬浮栏内部，独立承载必须自绘玻璃。
- **MainShell dock 态覆盖层**（`view/pages/MainShell.ets`）：根 Stack 内 `HdsNavigation` 之上挂 `dockMiniBarOverlay()`（NavDestination 盖不住它，且位于一镜到底压暗层之下）。状态机 `syncDockBar()`（由 `subPageDepth`/`currentSong`/`breakpoint` 三路 @Watch 驱动）：下潜 = 以药丸矩形（已标定的 `miniRect`）挂载 → 延迟一帧翻转到 dock 矩形（悬浮 Tab 栏边距体系：左右 16 = `barSideMargin`、底部 `bottomLift+8` = `barBottomMargin`、高 62 = 非紧凑胶囊）做原生属性动画（350ms Friction）；返回 = 翻回药丸矩形 → 落定后卸载，与槽位内真实迷你条（同位同形，延迟淡入）无缝交还；返回动画中途再次入栈会清卸载计时器并反向重定目标。紧凑/展开两份内容按目标形态交叉淡入淡出（180ms，对读屏/命中同样互斥），规避 40↔62vp 内容重排跳变。悬浮 Tab 栏边距常量提取为 `FLOAT_BAR_SIDE_MARGIN_VP`/`FLOAT_BAR_BOTTOM_GAP_VP` 两处共用。
- **一镜到底锚点适配**：`onNowPlayingRequested` 展开起点在 `subPageDepth > 0` 时取 `dockRect()`（窗口坐标，与 `miniRect` 同系），面板从子页上可见的 dock 条起飞；dock 条透明度/命中沿用真实迷你条的模态开合同规格显隐（展开隐藏、收起后半段延迟淡入）。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（1 条非阻塞 throw 警告）；codelinter 3 个改动文件 **0 error / 0 warn**。**设备侧未验证**：dock 矩形与真实 Tab 栏足迹的像素级对齐（HdsTabs 内部栏高未知，按边距体系推导）、迁移动画与 NavDestination 系统转场的节奏手感、子页列表尾部与 dock 条的遮挡关系，均待真机复测。
- **修订一（2026-09-18 真机首测反馈，两张症状截图）**：(1) 子页上迷你条整层不显示——覆盖层容器透明度复用了 `miniBarHidden()`，而该方法为隐藏槽位真实迷你条新增了 `subPageDepth > 0` 条件，恰好把覆盖层在子页上（深度必 >0）永远置 opacity 0，自相矛盾；修复：覆盖层改用只跟随播放页模态的 `dockOverlayHidden()`（`modalMounted && !closing`）。(2) 返回主页后只剩空药丸壳（无封面/歌名/按钮）——侧滑返回手势与子页标题栏返回键由 Navigation 直接弹栈，不经过 `Router.pop()`，`ui.subPageDepth` 卡在 1，槽位 MiniPlayer 永久隐藏而 HdsTabs 自绘的槽位药丸背景（`enableMiniBarBackground`）仍可见；修复：`Router.notifyReturned()`（各 NavDestination `onWillDisappear` 统一回调，覆盖 Router.pop/系统返回键/侧滑/clear 四条路径）补发 `publishDepth()`，幂等无副作用。
- **修订二（2026-09-18 用户要求子页播放条使用沉浸光感材质）**：SDK 勘察结论——HDS `SystemMaterialParams`（`systemMaterialEffect`）只能在 HdsTabs 悬浮栏 / HdsNavigation/HdsNavDestination 标题栏两处宿主内生效，无独立材质容器组件（无 HdsGlass/HdsFloatBar 之类）；独立悬浮组件挂系统玻璃材质的正道是 ArkUI 底座通用属性 `.systemMaterial(SystemUiMaterial)`（`@ohos.arkui.uiMaterial`，API 26 起，`uiMaterial.ImmersiveMaterial` 默认参数 REGULAR 玻璃质感 + applyShadow 自带投影，官方告诫启用后系统接管背景色/边框/阴影）。实现：`HdsLight` 门面新增 `SystemMaterialCapability`（`isImmersiveMaterialSupported()` 进程内探测缓存 + `ImmersiveMaterial` 实例缓存），`MiniPlayer` embedded 形态背景改挂 `.systemMaterial()`（材质档：背景透明、模糊 NONE、卡片阴影关闭防叠加；不支持设备保持自绘玻璃兜底；HdsTabs 槽位形态行为不变）。首轮构建报 ArkTS 静态字段与静态方法同名 `supported` 标识符冲突，字段改名 `materialSupported` 后 assembleHap **BUILD SUCCESSFUL**、codelinter 2 改动文件 **0 error / 0 warn**；真机材质观感待复测（模拟器/不支持设备走兜底，无回归风险）。

### 7.17 2026-10-01 歌单类长列表滑动掉帧治理：LazyForEach + 封面降采样（服务器 Linux CLT 26.0.0.105，无设备，分支 `perf/cover-scroll-jank`）

用户反馈：进入歌单等大量封面的页面后滑动大幅掉帧（Android 上游与其他鸿蒙音乐应用无此问题）。根因（代码级定位，官方 Image 文档佐证）：

1. **长列表全量 ForEach**：歌单/专辑/艺人/B站收藏/播放历史/搜索结果 7 个页面的歌曲列表都是 `ForEach` 一次性建满全部行——千首级歌单进场即建数千组件、每行各发一次收藏检查异步 DB 查询、各 Image 立即发起网络请求，进场即拥塞。
2. **封面按原图解码**：官方文档明确 ArkUI `Image` 的 `autoResize` **默认 false，按原图尺寸解码**（网易云原图常见 1000px+，单张解码数十 MB 内存），52vp 缩略图也照单全收；且网易云 `picUrl` 存储时不带 `?param=` 尺寸参数，原图整张下载。
3. **SongRow 重复 JSON.parse**：入参是整只歌的 JSON 串，`build()` 内多次直读 `song()`，单行单次渲染触发 5+ 次完整解析，进场即数千次。

修复：

- **`view/components/SongListDataSource.ets`（新增）**：`IDataSource` 实现，`reset()` 整表替换 + `onDataReloaded` 通知；页面 `@State` 数组整体重赋值经 `@Watch` 同步进数据源。
- **7 个页面 ForEach → LazyForEach**：PlaylistDetailPage（歌曲 + 「从播放历史添加」弹窗两个列表）、NeteasePlaylistPage、AlbumPage、ArtistPage、BiliFavPage、RecentPage、ExplorePage；ExplorePage 顺带补 `.cachedCount(3, true)`（此前无，对齐其他页）。**key 含 index**（RecentPage 另含 playCount）：LazyForEach 中 key 未变的行不会重建，删歌/重排/过滤后行内缓存的 index（序号徽标、onPlay 定位）会过期，靠 key 变化强制重建受影响行。歌单按 stableKey 去重、播放历史按 stableKey 去重，key 唯一性成立。
- **SongRow**：`song()` 按 songJson 串比较做惰性缓存（@Prop 重同步自动失效），单次渲染只解析一次；52vp 封面 `Image.autoResize(true)` 按显示尺寸降采样解码 + `coverThumbnailUrl(url, 200)` 显示层拼 `?param=200y200`（`view/components/Ui.ets` 新增；只用于显示，不写回 SongItem、不落库不参与同步，Android 端读 URL 时本就剥 `?param=` 后缀）。
- **其余封面位同规格**：HomePage（118vp 每日推荐 hero/132vp 卡片 → 400、46vp 最近播放 → 200）、LibraryPage 歌单卡、Ui.ets PlaylistCard、DownloadsPage、StatsPage、MiniPlayer、PlaylistHeader 均 `autoResize(true)` + 网易云源拼缩放参数。NowPlayingPage 大封面/模糊背景/取色链路**有意不动**（质量与 S5 取色敏感，非本症状来源）。
- **未做**（记录为后续项）：`SongRow` 未加 `@Reusable`（codelinter `hp-arkui-use-reusable-component` 提示；本轮以行为保守为先，滚动重建成本已由 LazyForEach 界定在视口 + cachedCount 内）；播放队列面板（无封面、纯文本行）未改。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**；codelinter 16 个改动文件 **0 error**（新增 warn 均为存量规则提示，与基线 diff 对比确认为行号平移/建议类）；`build-signed.sh` 签名包已刷新。**设备侧未验证**：滑动帧率改善幅度、千首级歌单进场内存峰值、B 站/NetEase 云缩略图 CDN 兼容性（`?param=` 为网易云图片 CDN 标准参数）待真机复测。
- **修订一（2026-10-01 真机反馈：仍卡且更卡，下滑再上滑封面全部重载）**：首轮改造只做对了「进场不全量建行」，漏算了 LazyForEach 的行销毁语义——滚出视口+cachedCount 的行会被销毁，回滚重进时 aboutToAppear 与 Image 全部重跑：(1) `SongRow.aboutToAppear → LocalPlaylistRepository.isFavorite()` 每次都 `loadAll()` 全量读取+JSON.parse 整个歌单库（无任何内存缓存），ForEach 时代每行只跑一次（进场卡一阵就完），LazyForEach 时代每次行重进视口都跑，千首列表滚动=几百次主线程全量解析，比改造前更卡；(2) 系统 Image 随行销毁重建重新走网络加载/解码，表现为封面反复重载。修复：`LocalPlaylistRepository` 新增收藏键集合进程内缓存（`getFavoriteKeySet`，`saveAllSilent`/`replaceAllFromSync` 统一失效）；新增 `util/LruCache`（纯逻辑，4 条单测）+ `data/CoverCache`（进程级封面 LRU，256 张 × 156px 解码图 ≈25MB 上限，下载拼 `?param=312y312` 缩略、desiredSize 降采样解码、同 URL inflight 去重）+ `view/components/CoverImage`（渲染走缓存，行重建同步命中直接出图；@Prop url 变更重载并丢弃过期响应）；`coverThumbnailUrl` 从 `view/components/Ui.ets` 迁至 `util/CoverUrls.ets`（CoverCache 在 data 层，不反向依赖 view）。歌单/搜索等 7 页行为不变，其余页面（首页/资料库/下载页/迷你条/歌单头图）仍用系统 Image+autoResize，不在滚动高频路径。
### 7.18 2026-10-01 设置页「打赏作者」入口与关于页仓库链接外跳（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/donate-about-link`；本文件 §7.17 在 `perf/cover-scroll-jank` 分支，尚未合入 dev）

- **打赏入口**：设置页「其他」分区新增「打赏作者」（`SETTING_DONATE`，`view/pages/SettingsPage.ets`），二级页（`view/pages/SettingsDetailPage.ets`）顶部说明文案 + 并排两张收款码卡片（`donateCard` @Builder，`Theme.surface` 底、`aspectRatio(1)` + `ImageFit.Contain`）。收款码占位图 `entry/src/main/resources/base/media/donate_wechat.png` / `donate_alipay.png`（720×720 仿二维码样式 PNG，微信绿 #07C160 / 支付宝蓝 #1677FF，脚本生成）；作者把真实收款码图片按同名文件替换即可生效，无需改代码。
- **关于页链接外跳**：仓库链接由安卓原版 `github.com/cwuom/NeriPlayer` 改为鸿蒙移植仓库 `github.com/suyunxing/NeriPlayer-HarmonyOS`（`PROJECT_REPO_URL`），并从纯文本改为可点击。新增 `entry/src/main/ets/util/LinkLauncher.ets`：`openExternalLink(context, url)` 走 `UIAbilityContext.openLink`（API 12+，`OpenLinkOptions.appLinkingOnly: false`——无 App Linking 匹配应用时回落系统默认浏览器；官方本地文档 `OpenLinkOptions` 页确认签名），失败仅 Logger.warn 不打断 UI；调用侧经 AppStorage `abilityContext` 取上下文（本文件既有模式），上下文未就绪时 toast 兜底。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（dev 基线复验）；codelinter 3 个改动/新增文件 **0 error**（SettingsPage 1 warn 命中未改动的 struct 声明行，存量 @Builder 建议类）。**未验证**：真机浏览器外跳（openLink 回落路径）、收款码卡片显示效果；收款码真实图片待作者替换。
### 7.19 2026-10-01 长标题跑马灯（迷你条/播放页/一起听当前曲目）（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/marquee-song-title`；本文件 §7.18 在 `feature/donate-about-link` 分支，尚未合入 dev）

- **方案来源**：参照 HarmonyOS 官方示例仓库 animation-collection（`br_release_hmos` 分支 `pageMarqueeView` 模块 `Marquee.ets`）的跑马灯做法——`Text + textOverflow({ overflow: TextOverflow.MARQUEE })`，非独立 Marquee 组件亦非自绘动画。本工程 API 26 完整覆盖 `marqueeOptions`（`@since 18`）与 `MarqueeUpdatePolicy`（`@since 23`），SDK 头文件 `text.d.ts` 已核对字段（`start/step/spacing/loop/fromStart/delay/fadeout/marqueeStartPolicy/marqueeUpdatePolicy`）。
- **新增共享组件** `entry/src/main/ets/view/components/MarqueeText.ets`：`@Prop text/fontSize/fontWeight/fontColor`，内部 `maxLines(1)` + `TextOverflow.MARQUEE` + `marqueeOptions({ start: true, loop: -1, fadeout: true, marqueeUpdatePolicy: MarqueeUpdatePolicy.DEFAULT })`。行为要点：文本未超宽时静止（引擎自行判定，滚动期 textAlign 失效）；`fadeout` 为引擎两端真 alpha 渐隐（毛玻璃等非纯色背景成立，开启后 clip 锁定）；DEFAULT 更新策略保证切歌后从头重滚；`step` 不设走引擎默认 4vp（调速留待真机反馈）。
- **替换三处当前标题**：① `MiniPlayer.ets` 标题由手写离屏 DST_IN 静态渐隐蒙版（Stack+linearGradient+blendMode 约 27 行）改为 MarqueeText——长标题从「永远看不全的静态截断」变为可滚动读全；② `NowPlayingPage.ets` 标题（22/Bold）由 Ellipsis 改 MarqueeText；③ `ListenTogetherPage.ets` 房间卡「当前曲目」行由 Ellipsis 改 MarqueeText。播放队列弹窗列表项与分享面板副标题维持 Ellipsis（滚动列表内条件跑马灯是反模式，静态展示不滚动）。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（42s）；codelinter 4 个改动/新增文件 **0 error**（MarqueeText 1 条「@Builder 替代自定义组件」性能建议 warn，与项目同层组件均为 @Component 的现状一致；NowPlayingPage 2 条 suggestion 为存量 blur 建议，非本轮引入）。**未验证**：真机滚动速度与两端渐隐观感、跑马灯滚动与迷你条横滑切歌手势的叠加表现（本机无设备）。
- **修订一（2026-10-01 每轮滚动前在开头停留 2 秒，用户要求）**：调研确认（官方文档 + ACE 引擎 `text_content_modifier.cpp` 的 `ResumeTextRace`）原生 `delay` 只作用于**轮与轮之间**——引擎对首轮启动强制 `delay=0`（首轮立即滚），它是动画启动延迟而非步间隔。故首轮与切歌后的那一轮由组件自管：`MarqueeText` 挂载（`aboutToAppear`）与 `@Prop text` 变化（`@Watch`）时经 `scheduleStart()` 置 `start=false`（引擎停轮、文字回起点静止，超宽静止期右端仍有 fadeout 渐隐），停满 `MARQUEE_HOLD_MS=2000ms` 再放行 `start=true`；轮与轮之间的停顿交给原生 `delay: 2000`。`aboutToDisappear` 清理未到点的定时器（MiniPlayer 槽位随切 Tab 重建，定时器必须随组件销毁释放）。顺带确认 `onMarqueeStateChange`（API 18+）枚举为 `START/BOUNCE/FINISH`，`loop:1`+回调手动重启方案更耗弃用。验证：assembleHap **BUILD SUCCESSFUL**（26s，分支基线复验）；codelinter 改动文件 **0 defect**。**未验证**：真机上停留节奏观感（同上）。
### 7.20 2026-10-01～02 悬浮栏滚动自适应形变：miniBar 展开/折叠（官方原生联动），滚动位置驱动（服务器 Linux CLT 26.0.0.105，无设备，分支 `scroll-adaptive-floating-bar`）

目标效果（用户参考视频，与官方 Spatialization 示例 dev@25cf533「自适应悬浮导航」演示一致）：静止/回顶=上下堆叠（迷你条胶囊在上、全宽页签栏在下）；滚入正文=**两行并一行**——页签栏折叠成当前项小钮、迷你条展开占满余下行宽，形变过程系统原生动画。**方案沿革三轮**（0233a40 → 9a6aecc → aaa805e+本提交，其中 9a6aecc 自绘版已整体 revert）：

- **一版（applyHide/ShowAnimation，弃用）**：误把官方示例「沉浸光感」场景（`ImmersiveLightView`）的整组淡出 API 当成目标效果入口。真机实测（2026-10-01 用户反馈视频）：SCROLL_ANIMATION 为**原地半透明淡出**（栏组变幽灵叠在内容上，非形变收起），且滚动方向反复时实心/半透明**闪切**。教训：`applyHide/ShowAnimation` 管「整组显隐」，与「自适应悬浮导航」场景的 miniBar 形变是两套 API，不可混用。
- **二版（自绘两态栏组，9a6aecc，已 revert）**：为绕开黑盒自绘两枚胶囊 + barHeight(0) 隐藏自带栏。功能可达但弃用：官方原生形变（材质/光晕/联动动画）质量更高，且用户指认官方演示即目标效果——应走官方机制。
- **终版（官方 miniBar COLLAPSE↔EXPAND + 滚动驱动）**：SDK 语义（`@hms.hds.hdsBaseComponent.d.ets`）——`BarStyleChangeCallback` 同时回调 miniBarStyle 与 tabBarStyle；`HdsTabsBarChangeMode` 分 `USER_CLICK`（点击折叠态迷你栏/页签栏，系统内置切换）与 `APP_TRIGGER`（应用调 `applyMiniBarStyle`）；README 明言「miniBar展开的同时和tabsBar会折叠起来」——**迷你条展开 ↔ 页签栏折叠是 HdsTabs 原生联动形变**。官方示例靠点击触发，本工程按参考视频改为滚动位置驱动：
  - `handleTabBarScroll`：向下滚且滚过 `MINI_EXPAND_ON_OFFSET_VP(96)` → `applyMiniBarStyle(EXPAND)`；滚回 `MINI_COLLAPSE_ON_OFFSET_VP(48)` 以内 → `COLLAPSE`。双阈值滞回防抖（48~96 区间保持现态，杜绝一版的方向闪切）；无歌不展开（空玻璃壳）；触底报 -1 无操作（展开态在底部保持，同参考视频）。
  - `onBarStyleChange` 为形态事实源（`miniExpanded` 字段 + `AppStorage 'ui.miniBarExpanded'` 发布）：覆盖 USER_CLICK 与 APP_TRIGGER 两条变更路径；槽内 `SlotMiniBar` 经订阅切换紧凑(40vp)/非紧凑(62vp) MiniPlayer 内容（槽位闭包不响应壳层状态的老坑，仍走 AppStorage 订阅）。`miniBarStyle: COLLAPSE` 显式声明初值。
  - 衔接：切 Tab 目标页在顶部则收回展开态；切歌清空收回（`collapseMiniBarIfSongEmpty`）；一镜到底展开起点 `pillRect()` 增展开态分支（底部整行近似值：行高 56/钮宽 64，飞行起点偏差不敏感，真机可按 §7.16 同法精标）；四 Tab 页 `onBarScroll` 上报接线同一版保留。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL 0 error**；codelinter 改动文件 **0 error**。**设备侧未验证**（核心风险点）：VERTICAL 布局下 EXPAND 的真实形态是否为「两行并一行+页签小钮」（当前假设来自 README+视频对照）；展开态槽位药丸实际高度与非紧凑 MiniPlayer(62vp) 的匹配；USER_CLICK 系统点击切换与迷你条内容自身点击（开播放页/播放键）是否会同时触发；96/48vp 阈值手感。若真机 EXPAND 形态与预期不符，备选：HORIZONTAL 布局（静止态变单行小圆钮，形变同款）或恢复二版自绘。
- **修订一（2026-10-02 真机首测反馈视频，形变已验证 + 材质缺陷修复）**：真机确认 VERTICAL+EXPAND 形态正确——两行并一行、页签栏折叠为当前项小钮（其玻璃材质正常）、回顶恢复堆叠，核心假设全部成立。缺陷：**展开行迷你条呈深色平板、无沉浸光感**——`MiniPlayer.followsBarMaterial()`（背景透明透出栏身系统材质的档位）原带 `this.compact` 条件，展开态渲染的非紧凑形态走了自绘玻璃分支（surfaceGlass+卡片边距+阴影），整层盖住槽位壳的沉浸材质。修复（`view/components/MiniPlayer.ets`）：`followsBarMaterial()` 去掉 compact 条件（槽位形态两种紧凑度统一跟随栏材质），且跟随栏材质时零边距、无卡片阴影（几何由栏壳给定）。改动面安全：非 embedded 非紧凑形态全工程仅槽位展开态一处使用（dock 层两副本均 embedded）。不支持材质的设备（模拟器）回落行为不变。
- **修订二（2026-10-02 二轮真机反馈截图，光感已生效后的内容形态调整）**：展开行迷你条内容弃用上版的非紧凑形态切换，**两种形态统一紧凑样式**（用户决策：圆形封面 + 播放键外圈进度环，与堆叠态药丸同观感）——非紧凑内容的三处观感问题：62vp 内容在展开行壳内上下不居中、封面变圆角方形、播放键无进度环。`SlotMiniBar` 改为 Stack 垂直居中包裹（展开行壳高于 40vp 内容时居中，堆叠态同高无感）；`'ui.miniBarExpanded'` AppStorage 广播链删除（形态只在 MainShell 逻辑内消费：pillRect 展开态分支/切 Tab 收回判定）。
- **修订三（2026-10-02 三轮真机反馈截图 + 参考图，折叠行内容定版为 row 档）**：紧凑样式在折叠行的高药丸里暴露三问题——32vp 封面相对药丸弧度过小、标题过早截断、作者行贴底被裁。弃「统一紧凑」，MiniPlayer 新增第三形态 `row`（槽位折叠行专用，参考用户图二布局）：48vp 圆形封面（直径≈药丸高 85%）、标题/作者两行垂直居中、播放键保留外圈进度环（34vp 环 + 主色图标）、下一首 40vp，无线性进度条；内容行 48vp 由 SlotMiniBar 的 Stack 垂直居中包裹适配壳高。`'ui.miniBarExpanded'` 广播链恢复（SlotMiniBar 按形态切 compact↔row）。堆叠态药丸仍为紧凑档、dock 态仍为 embedded 档，均不变。
- **修订四（2026-10-02 四轮真机反馈截图，row 档两处精修）**：(1) **作者行消失**——当时归因为 `displayArtist` 空值塌陷，加了平台名回退；**该归因次轮被用户推翻**（见修订五），回退已撤。(2) **封面与药丸左端同心**——用户要求「封面左半边每一点与迷你条边缘距离一致」即封面圆心落在药丸左端半圆圆心；实现：SlotMiniBar 经 onAreaChange 实测槽位壳高下发给 MiniPlayer（新 prop `rowShellHeight`），row 形态封面左缩进 = (壳高−48)/2（未测量时按 56vp 标准壳取 4vp），不再用固定 padding。
- **修订五（2026-10-02 五轮用户指正，作者行越界的真实原因与修复）**：作者行并非数据缺失（撤回平台名回退），而是**固定 48vp 内容 + 外层 Stack 居中的两段式**在壳高与内容高不一致时把文字块排偏——作者行落到药丸可视范围之外。修复：row 形态内容行高度改为**填满实测壳高**（`rowContentHeight()` = rowShellHeight，未测量按 56），文字块（歌名+作者名）经 Row 默认垂直居中在壳内——歌名与作者名之间的中线与药丸中线齐平（用户要求）；封面同心缩进与 Stack 兜底包裹不变。
- **修订六（2026-10-02 六轮用户质疑「还是这样」——修订四/五的实测链路是循环测量，两轮修复均无效）**：用户截图佐证：封面与药丸左端间距≈0 → 修订四的同心缩进 (实测-48)/2 算出 0 → **实测值=内容自身高度 48**——槽位不约束 builder 高度，包装层 `height('100%')` 回落为包内容，onAreaChange 量到的永远是内容自己而非药丸。教训：**HdsTabs miniBar 槽位的 builder 高度由内容自然撑起（官方示例 miniBarBuilder 即不设高度、按 56vp 封面规格自然成形），任何「实测壳高」的尝试在该槽位内都是循环的**。修复：弃 rowShellHeight 链路，row 形态内容行**定高 56**（HDS 悬浮栏标准，官方示例规格）居中排版（文字块中线=行中线；封面同心缩进固定 (56-48)/2=4）；SlotMiniBar 保留 onAreaChange 仅作**临时调试读数**（row 形态药丸右下角 8fp 红字 `H=xx`），真机截图定版药丸真实几何后删除。
- **修订七（2026-10-02 七轮调试读数截图，几何模型定案：展开态内容区≈40vp、顶部对齐、底部裁切）**：调试读数显示 **H=0**——builder 盒是**零高度**（`height('100%')` 在无约束父级下解析为 0，此前所有「包内容」推断亦不成立），children 从零高锚点渲染。同张截图三处独立证据：文字块贴顶+下方大片留白、作者行完全消失、进度环只剩残弧——结合修订二~六全部现象，唯一自洽模型：**展开态药丸的 builder 内容区约 40vp 高（与堆叠态药丸同族同高），内容顶部对齐，超出 ~40vp 的部分被药丸底部裁切**。修订五/六的 48/56vp 内容的下半部（作者行、进度环下弧、封面下缘）均被此线吃掉；修订二的紧凑 40 内容因恰好贴合从未被裁（其「作者行贴底被裁」实为 40 行内文字块自身偏高）。修复：row 形态内容行回落**定高 40**（封面 34 同心圆（(40-34)/2=3 缩进）、两行文字 14/11fp 行内居中、进度环 30、播放键图标 16），标题弃渐隐蒙版改普通省略号（窄药丸里渐隐进一步压缩可读段）。**临时调试**：内容行加 1px 半透明红边框（可视化内容盒与裁切线关系），连同 H= 读数在真机确认后一并删除。
- **修订八（2026-10-02 八轮真机红框验证截图，模型证实、调试件移除、折叠行内容定稿）**：红框调试截图确认 40vp 模型——**红框完整落于药丸内**（顶边与药丸上缘重合、底边略高于药丸下缘），两行文字（标题+作者）、完整进度环、同心封面全部恢复显示。据此定稿：删除临时红框与 H= 读数（连同 SlotMiniBar 的 onAreaChange/shellHeight 链路）。已知边界：内容区顶部对齐使文字块相对药丸玻璃整体略偏上约 2-4vp——底部裁切线约束下不可再下移（下移即重新触发作者行裁切），为系统槽位约束内的最优解；若后续版本 HdsTabs 调整槽位几何，按修订七红框法重测。
- **修订九（2026-10-02 九轮用户定稿意见：大圆封面恢复 + 折叠行标题跑马灯）**：(1) **封面恢复 48vp 大圆**（用户指定回退 2d0cb29 观感）：顶边贴药丸上缘、底缘没入药丸下弧被自然裁切（该裁切即修订七定案的底部裁切线，用户认可此观感）；占位图标边距回 48 档。(2) **折叠行标题接跑马灯**：`MarqueeText` 组件自 `feature/marquee-song-title` 移植（该分支未合入 dev；Text 原生 MARQUEE + marqueeOptions，开头停留 2s（首轮/切歌自管）+ 轮间 delay 2000、切歌从头重滚、未超宽静止、fadeout 渐隐）——折叠行文字区最窄，省略号/渐隐均浪费可读段；堆叠态标题维持渐隐蒙版不动（跑马灯化属 marquee 分支既有工作，避免双分支改同一处）。后续两分支合入 dev 时 MarqueeText.ets 内容一致、冲突取任一侧即可。
- **修订十（2026-10-02 十轮用户反馈「封面歪了」——改用程序化像素测量定同心参数）**：视觉模型对亚像素几何描述反复自相矛盾，弃用；改 ffmpeg 解码截图 + Python 亮度/饱和度分类逐像素测量（可复现脚本见本次会话记录）。测量结果（1316×2832 截图）：展开药丸左缘 x308、上 y432、下 y623（高 191px≈55-56vp，与页签钮 195px 互证，HDS 56vp 标准在展开态成立）；封面圆赤道直径 168px≈48vp 渲染正确、左缘与药丸左缘重合（inset 0 生效）；**同心目标（左端半圆圆心 403.5,527.5）与封面实际圆心 (392,531) 偏差：横向 11.5px≈3.3vp、纵向 3.5px≈1vp**——左缘 0 间隙 vs 上缘 15px 间隙的不对称即用户所见「歪」。修复：`rowCoverInset` 定值 3.5vp、封面纵向 offset 4→3。修订九的封面定位描述（顶边贴上缘/inset 收敛 0）随本修订修正。
- **修订十一（2026-10-03 十一轮用户反馈「仍然偏下」——二轮像素复测，横向已准、纵向修正）**：新截图（浅色背景，玻璃不可见，改以页签钮图标中心 529.5 定药丸中线）复测：封面圆赤道左 320.5/右 487 → 圆心 x=403.5 与帽心（308+95.5）**精确重合**（修订十的 inset 3.5 定准，横向结案）；圆顶 455、圆心 y≈538.5（底 622 为药丸底裁切线），较药丸中线 529.5 **偏低 9px≈2.6vp**。修正修订十的一处推断误差：上轮「圆心 531」来自赤道行=圆心的假设（赤道 ±6px 内弦长差异不可辨），非直接测量；本轮以圆顶直接测量为准。修复：纵向 offset 3 → 0.5（上移 2.5vp，残差≈0.3px）。
- **修订十二（2026-10-03 十二轮用户反馈「仍有较小的向下偏移」——三轮像素复测，改以玻璃边线直测药丸中线）**：新旧两截图对比确认 offset 0.5 已生效（封面上移整 10px，与 -2.5vp 改动量吻合），残余偏差源于**中线估计量本身**：本轮发现浅色背景下药丸玻璃上/下边各有一条纯白高光线（255.0，水平范围 x≈376–1164），即药丸真实边界——顶边线 y=430.5、底边线 y=624.5 → 高 194px≈56vp、**真中线 y=527.5**；修订十一所用页签钮图标中心 529.5 系估计量偏高 2px。封面圆按亮度剖面直测（圆心 x 处暗区 y[446,614]，直径 168px 精确）：圆心 y=530.0，仍偏低 **2.5px≈0.7vp**。横向复测无退化（圆心 x=403.5，药丸左缘高光起于 x≈305，同心差 ≤0.4vp，维持 inset 3.5）。修复：纵向 offset 0.5 → **-0.2**（上移 0.7vp，残差 ≈0.2px）。本条同时修正：饱和度聚类抓不到真圆边（灰色封面艺术上半部低饱和，d_y=92≠168），圆缘必须按亮度剖面测。
- **修订十三（2026-10-03 十三轮用户反馈「上滑不展开，须回顶再上滑才恢复」——折叠态恢复由位置驱动改方向驱动）**：原恢复条件仅看位置（滚回 `MINI_COLLAPSE_ON_OFFSET_VP`=48vp 内），列表中部上滑（负增量）无分支命中，只有滚到顶部附近才恢复双行。修复：恢复条件改 `yDelta < 0 || yOffset < 48`——**任意上滚增量即恢复，与下滚收起方向对称**（用户指定参照下滑收起逻辑）；48vp 位置条件保留为兜底（内容缩短等无声增量场景）。连带清理：四 Tab 页「触底兜底报 -1」（HomePage/LibraryPage/SettingsPage 的 `onScrollEdge(Edge.Bottom)`、ExplorePage 的 `onReachEnd`）随之移除——方向驱动后该 -1 会伪造成一次上滑，导致触底瞬间错误展开；触底保持折叠态不变（同参考视频），上滑离开底部时自然有真实负增量触发恢复。防抖说明：展开/折叠各由 `miniExpanded` 状态闩锁，同方向连续帧不重复触发，方向交替才切换（与官方 ImmersiveLightView 示例 `isScrollUp` 闩锁同构）。

### 7.21 2026-10-04 网易云手机验证码登录「网络环境异常」复发修复：匿名设备凭证 MUSIC_A（服务器 Linux CLT 26.0.0.105，无设备，分支 `fix/netease-captcha-music-a`）

§7 记录外的前情：2026-09-27（commit 8931990）曾修过一次同报错（补 web 会话指纹 cookie + 首页预热取 `__csrf`/NMTID），2026-10-04 用户反馈**复发**。本轮为第二次风控对抗，结论：上轮的指纹方案已不够——登录族接口现在还要求**匿名设备凭证 `MUSIC_A`**。

- **社区证据链（2026-09～10，均为一手 issue/PR/源码直读）**：① QueMusic PR #79（2026-10-01 合入，同款 -460 回归的真机修复）：启动时调 `register_anonimous` 换 `MUSIC_A` 并注入后续所有请求 cookie，缺它则登录族接口必被风控拦截；附带 A/B 实证「UA 平台与 cookie `os` 矛盾即可独立触发 -460」（本工程上轮已自洽：桌面 UA + os=pc）。② api-enhanced（Binaryify 继任仓库，v4.41.0/2026-10-03）`util/request.js`：`processCookieObject` 对无 `MUSIC_U` 的每个 weapi/eapi 请求注入 `MUSIC_A=anonymous_token`（启动经 register_anonimous 落盘复用）。③ open-orpheus #17/#75（2026-04/05）：匿名态接口 2026 年起收紧，`MUSIC_A` 成为登录类接口隐式必填——「9 月能过、10 月不过」与凭证回收时间线吻合。④ api-enhanced PR #243（2026-08-24）：预置合成 NMTID 会阻止服务端下发真值（服务器只在请求不带 NMTID 时经 Set-Cookie 下发）。
- **register_anonimous 协议（QCloudMusicApi 源码直读，QueMusic 真机验证通过的 weapi 通道）**：`POST /weapi/register/anonimous`，payload `{username}`，`username = base64("<deviceId> <dllEncodeId(deviceId)>")`，`dllEncodeId = base64(MD5(deviceId 逐字符 XOR '3go8&$8*3*3h0k(2)2'))`；deviceId 为进程级随机 52 位大写 hex（api-enhanced `generateDeviceId` 同款）。响应 body 带 `token`，Set-Cookie 下发 `MUSIC_A`（本工程 `HttpClient` 的双来源 cookie 捕获自动入 jar，body token 仅作净栈丢头时的兜底，与 QueMusic 同款双源提取）。api-enhanced 现版该接口已迁自研 `xeapi` 通道（依赖服务端下发会话密钥），社区鸿蒙/桌面端实现的 weapi 通道仍有效。
- **本轮改动（`network/NeteasePhoneLogin.ets` 为主）**：① `ensureWebSession` 末尾新增 `ensureAnonymousDevice()`：进程内至多注册一次（失败降级为上轮的纯指纹会话、不阻断登录流程；重复注册本身会累积风控分），jar 已有 `MUSIC_A`/`MUSIC_U` 时跳过；注册成功后 `MUSIC_A` 经共享 jar 自动随发码/登录请求携带（扫码登录同 jar 亦受益）。② 发码 payload 补 `secrete: 'music_middleuser_pclogin'`（api-enhanced 2026-07 起的现行字段，缺省兼容但补齐为持平）。③ `fallbackNmtid` 形状修正：`00O`+19hex（22 位、与服务端下发 42 位形态不符）→ 32 位小写 hex（社区客户端自生成 NMTID 的真实形状），且仅在首页预热未取到时兜底（#243 教训：预置合成值阻止服务端下发真值）。④ 指纹 `appver` 8.10.35（2021 年代 web 播放器）→ **3.1.17.204416**（api-enhanced 现版 osMap pc 生产值），三处统一防共享 jar 内 appver 漂移：`buildWebSessionSeed`、`NeteaseApi.doEnsureSession` 种子、`NETEASE_FALLBACK_APPVER`（NeteaseAuth 粘贴 cookie 兜底）。⑤ `NeteaseCrypto.bytesToBase64` 转 public（username 构造需要），`NeteaseLoginResult` 增 `token` 字段。
- **单测**（`NeteasePhoneLoginSeed.test.ets` 重写为 5 例 + `NeteaseAuth.test.ets` 2 处断言随 appver 更新）：dllEncodeId 双已知答案向量（Node crypto 算得：`testdev`→`aUNnZQ4t4g9xOuS/lFXa7Q==`、52 位 deviceId→`AQnKVRmBziu7FJISAzbr6A==`）、`buildRegisterUsername` 完整向量、seed 指纹集、NMTID 新形状（32 hex + 随机性）。
- **未验证（本机无设备）**：真机发码/登录全链（用户验证路径：安装刷新后的签名 HAP）；若仍被拦，社区证据指向的下一嫌疑为出口 IP（机房/海外/VPN 触发 -462 人机验证，`realIP` 对此已证实无效）与账号级风控标记（换浏览器 cookie 或 frontrisk 验证兜底），届时按 go-musicfox #596 判例处理。扫码登录（NeteaseQrLogin）未主动接 `ensureAnonymousDevice`，仅经共享 jar 间接受益。
- **修订一（2026-10-04 真机反馈「当前环境存在安全风险」——判定为 10003/10004，补齐 QueMusic 配方剩余项）**：上版装上后报错从 -460「网络环境异常」变为 10003/10004「当前(登录)环境存在安全风险，请稍后再试」——**正是 QueMusic PR #79 修复前的中间态**（该 PR 自述：修复前 -460 → 10003/10004，修复后登录成功），说明方向对但配方缺件。与 QueMusic 终态配方的逐项 diff：①其 deviceId 持久化（`Account.ini: Netease/deviceId`，源码注释明言「每次启动随机换设备是扫码被判环境异常的主要嫌疑之一」）——本工程上版恰是每进程随机（本轮已改：`np.netease_device_identity` 落盘复用 nuid/wnmcid/tsMs/deviceId 四元组，`MUSIC_A` 亦经 `np.netease_anon_music_a` 落盘、重启后注入 jar 免重复注册）；②登录 payload 现版必带 `secureCaptcha: ''`（api-enhanced 2026-10-03 main，已补）；③验证码登录先过 `/captcha/verify` 再发 login（folia-major：「新版验证码登录必须先 verify，直接登录易触发风控」；第 1 轮删 verify 的教训保留——失败仅告警不阻断，已按软前置加回）。诊断增强：发码/登录 Toast 与日志均带数字 code（`登录失败[10004]: …`）、`postWeapi` 每请求 debug 行、匿名注册成败均落日志——用户下次反馈可直接定位环节与判决。另注：服务器侧（美西机房 IP）实测 weapi/eapi 经典匿名注册通道均不可用（weapi 恒 `{"code":400}`、eapi 空 body 200），与 QCloudMusicApi/QueMusic 国内真机可用矛盾，判定为地域/出口差异；api-enhanced 主线 2026-10-03 已迁 xeapi 注册（X25519+AES-GCM+`/api/bsr/sk/get` 公钥协商，纯 ArkTS 移植代价大），留作国内真机 weapi 注册仍失败时的下一梯队方案；eapi 版 `middle/captcha/sent/v1`（scene:'0'，interfacepc）为另一候选。本轮在并行会话占用主检出的情况下经 sparse worktree（`np-netease-fix`）完成。

每次 SDK 或上游 Android 更新，都更新本文件的核验日期、版本矩阵、源码状态和测试结果。

新增能力必须附官方页面 URL、适用 API、代码位置、验证设备、失败日志和降级方案。

如果官方页面、工程配置和历史日志冲突，以当前官方 Release 文档、当前 DevEco Studio 生成配置和可重现设备测试为准。
