# NeriPlayer HarmonyOS 开发与迁移指南

> 核验日期：2026-08-14。本文依据华为开发者联盟文档中心、版本说明和当前工作区源码重写并复核：版本映射与官方文档核对一致；本机工具链路径按 2026-08-14 迁移后的 `D:\HarmonyOS\Tools\` 布局更新（2026-08-13 的验证记录当时基于旧布局 `D:\HarmonyOS\` 根目录）。本文面向 NeriPlayer 的 HarmonyOS 原生迁移，不是 HarmonyOS API 的完整百科。

## 1. 先看结论

NeriPlayer 的主迁移路线是 HarmonyOS 普通应用：ArkTS + ArkUI + Stage 模型。
`NeriPlayer-ASCF` 仅用于元服务能力验证，不能替代普通应用主线。

当前工程是可继续开发的 ArkTS 原型，不应描述为“已完成 Android 全量移植”。
源码、配置和审计结果显示，页面骨架、基础播放、部分数据仓库和三平台搜索已存在，但功能等价性、异常恢复和设备验证仍不足。

生产开发默认使用 **HarmonyOS 6.1.1(24) Release**：

- DevEco Studio 6.1.1 Release（当前版本页列出 6.1.1.300、6.1.1.290、6.1.1.280）。
- HarmonyOS SDK 6.1.1 Release，基于 OpenHarmony SDK `Ohos_sdk_public 6.1.1.125`。
- API 24 Release 于 2026-05-26 发布。

这是 NeriPlayer 当前工程的项目基线，不代表华为对所有应用的统一升级建议。官网“所有版本”页当前把 6.1.1(24) 标为“按需使用/按需升级”，把 6.0.0(20) 标为“推荐使用/推荐升级”；已有应用应根据目标 API、设备覆盖和新能力需求决定是否升级。

**26.0.0 Beta2** 是当前官网列出的最新开发者 Beta，配套 DevEco Studio 26.0.0 Beta2（26.0.0.621）和 SDK `Ohos_sdk_public 26.0.0.32`。
它只用于预览特性和适配验证，不作为本项目的生产默认基线。

## 2. 官方版本与兼容性规则

### 2.1 当前版本矩阵

| 用途 | API/套件 | 状态 | 本项目策略 |
| --- | --- | --- | --- |
| 生产发布 | 6.1.1(24) + DevEco Studio 6.1.1 Release | Release | 默认基线 |
| 兼容旧设备 | 6.0.x(20～23) | Release | 作为兼容测试目标，按实际设备分布选择 |
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

当前工程根目录 `build-profile.json5` 已配置 `targetSdkVersion` 和 `compatibleSdkVersion` 为 `6.1.1(24)`，但未显式配置 `compileSdkVersion`。
迁移前应在 DevEco Studio 中补齐并由 IDE 校验，不要依赖缓存或工具默认值。

生产配置示例：

```json5
{
  "app": {
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compileSdkVersion": "6.1.1(24)",
        "targetSdkVersion": "6.1.1(24)",
        "compatibleSdkVersion": "6.1.1(24)",
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

不要把 Beta2 页面中的新增 API 直接混入 API 24 生产代码。需要时建立 capability adapter，并在预览设备上单独验证。

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
工程声明支持 phone、tablet、2in1，包名为 `moe.ouom.neriplayer`，许可证沿用 GPL-3.0。

源码约 56 个 `.ets/.ts` 文件、约 7,700 行（2026-08-14 复核为 7,698 行）。当前工作区已在 `entry/src/test/` 建立 ArkTS 单元测试入口，并使用 `@ohos/hypium` 覆盖 LRC 解析、排序、翻译时间容差和时间格式化。
2026-08-13 已使用 `D:\HarmonyOS` 中的 6.1.1 Release 工具链从 `ohpm install --all`、`clean` 开始完成 Debug HAP 构建，随后执行 ArkTS 单元测试、调试签名、模拟器安装、冷启动和设置页 smoke test。构建与测试结果可从当前源码重复获得，不再依赖 2026-08-02 的历史日志。

### 3.2 已有代码与可信度

| 能力域 | 当前情况 | 可信度/下一步 |
| --- | --- | --- |
| 启动、免责声明、引导、安全模式 | `Index.ets` 和对应页面已有路径 | 静态存在；需冷启动、升级和异常恢复测试 |
| 主导航和页面 | 首页、探索、资料库、设置、播放页等已存在 | 原型；需迁移到官方推荐 Navigation 并做多设备验证 |
| 基础播放 | `PlayerManager.ets` 使用 AVPlayer，支持 URL/fd、队列、seek、倍速和错误重试骨架 | 原型/待复核；需真实设备闭环 |
| 系统媒体控制 | `AVSessionManager.ets` 可创建并更新 AVSession | 原型；需锁屏、控制中心、耳机和进程回收测试 |
| 后台播放 | `audioPlayback` 配置和后台任务封装已存在 | 未完成官方接入闭环；需 AVSession、长时任务和中断测试 |
| 本地媒体 | `AudioViewPicker` + `AVMetadataExtractor` | 代码路径存在；需真机验证 URI 生命周期和播放 |
| 网易云 | 搜索、歌词和部分取流适配器 | 有风控回退；登录态、限流和版权场景未闭环 |
| Bilibili | 基础搜索/取流适配器 | 原型；需 DASH、Cookie、区域和错误测试 |
| YouTube Music | 搜索适配器 | 取流明确未完成，缺 signature/n、PoToken、EJS/HLS 闭环 |
| 下载 | 任务模型、页面和 preferences 目录 | 字节传输、Range/HLS、校验和恢复未完成 |
| GitHub/WebDAV 同步 | 设置页入口 | 同步层未移植 |
| 一起听 | 设置页入口 | WebSocket 协议、重连和校时未移植 |
| USB 独占 | 调试页提示 | 没有 NAPI C++ 模块 |
| 动态取色/高级模糊 | 设置入口和基础主题 | 渲染引擎未完成 |
| 测试 | 已有 LRC 解析 ArkTS 单元测试，3/3 通过 | 已建立最小基线；仍需补 SongIdentity、队列、设置迁移、下载和 UI/Instrument 测试 |

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

发布前在 API 24 生产设备和明确声明支持的旧版本设备上执行构建、安装、升级、权限、播放、后台、网络、存储和恢复测试。
API 26 Beta2 只作为独立预览适配矩阵，不能替代 Release 回归。

完成无障碍、phone/tablet/2in1 布局、启动速度、内存、功耗、隐私、权限最小化、日志脱敏和应用市场合规检查。

## 6. 关键实现规范

### 6.1 Stage 模型和生命周期

新功能使用 Stage 模型：`AbilityStage` 做进程级初始化，`UIAbility` 管理窗口和页面，`WindowStage` 负责加载页面。
不要用 Android Activity 的生命周期类比替代 HarmonyOS 的上下文和 Ability 语义。

建议把播放器、下载器和同步器放在应用级服务中，由 `UIAbility` 注入上下文和生命周期信号。
页面销毁不应导致后台播放状态机被销毁。

### 6.2 Navigation 和多设备布局

官方当前推荐 `Navigation` + `NavDestination` + `NavPathStack`，`router` 页面路由标为不推荐。
现有 `view/Router.ets` 可以作为过渡层，但新页面不应继续扩大旧 Router 依赖。

Navigation 宽度小于 600vp 时建议单栏，大于等于 600vp 时建议分栏；使用 `NavigationMode.Auto` 可让系统按容器宽度切换。
这对 tablet 和 2in1 尤其重要。

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
- 模拟器系统镜像：仅 HarmonyOS-6.1.1（API 24，phone_all_x86）；已部署 4 个 AVD（Pura 90、Mate X7、MateBook Pro、MatePad Pro 13）。API 26 镜像未下载，鸿蒙 7.0 模拟器验证前需在 SDK Manager 补齐。
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
& $hdc shell aa start -a EntryAbility -b moe.ouom.neriplayer -m entry
```

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
仍未就绪：API 26 模拟器镜像未下载（鸿蒙 7.0 设备侧验证需先在 SDK Manager 补齐）；真机测试未执行。

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

当前最小基线位于 `entry/src/test/`，通过 `@ohos/hypium` 和 Hvigor 本地单元测试任务执行 3 个 LRC 用例。测试不访问设备和第三方网络。该结果不替代需要安装测试包并通过 `aa test` 执行的设备侧 JsUnit/Instrument 测试。

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
| 系统 | API 24 Release；声明支持的旧 API；API 26 Beta2 预览 |
| 设备 | phone、tablet、2in1；至少一台真实设备 |
| 音频 | 扬声器、蓝牙耳机、耳机拔出、来电、导航播报、其他播放器抢占 |
| 生命周期 | 冷启动、后台、熄屏、旋转/折叠、多窗口、进程被回收 |
| 数据 | 首次安装、升级、权限拒绝、URI 失效、空间不足、损坏恢复 |
| 网络 | 慢网、断网、超时、重定向、Cookie 过期、服务端错误 |

## 9. 发布前验收清单

- [x] 2026-08-13 已在当前 6.1.1 Release 环境完成依赖同步、干净编译、3 个单元测试、调试签名、模拟器安装和冷启动。
- [x] 2026-08-14 迁移后全链复验通过：PATH/环境变量修复、显式三版本配置、ohosTest 骨架（设备实测 1/1）、codelinter 基线、签名口令重置（见 7.5）。
- [x] 三个 SDK 版本显式配置且满足大小关系（compileSdkVersion/targetSdkVersion/compatibleSdkVersion = 6.1.1(24)）。
- [ ] API 24 Release 完整功能回归通过；当前只完成构建、单测和设置页 smoke test，Beta API 未混入生产路径。
- [ ] Stage、UIAbility、AbilityStage 的职责和生命周期清晰。
- [ ] 新页面使用 Navigation/NavPathStack，或记录 Router 过渡原因。
- [ ] AVPlayer 状态监听、错误恢复、资源释放和本地 fd 生命周期经过测试。
- [ ] AVSession 元数据、播控、后台播放和音频焦点经过真机测试。
- [ ] 权限按最小化原则声明，运行时拒绝有可用降级路径。
- [ ] 本地 URI、下载文件、设置和数据库有 schema 与恢复策略。
- [ ] 第三方接口状态、版权和服务条款已审查。
- [x] 账号登录以及下载、同步、一起听、USB、YouTube 取流等未完成项已显式标注，不得伪装为已支持。
- [ ] 正式证书、Profile、私钥和密码不在仓库或日志中。
- [ ] 完成无障碍、平板/2in1、性能、功耗、隐私和上架预检。

## 10. 官方资料索引

以下链接均来自华为开发者联盟文档中心；页面会持续更新，使用前再次确认适用 API 和更新时间。

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

预研 API 26 新能力时参考（不得混入 API 24 生产路径）：

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

- 仓库根 `.github/workflows/harmonyos-ci.yml`（GitHub `suyunxing/NeriPlayer-HarmonyOS`，私有，当前默认分支 `su`）。触发：push 到 `main`、`dev`，PR 到 `main`、`dev` 或迁移期兼容分支 `su`（直接 push 到 `su` 不触发；paths 限定 `NeriPlayer-HarmonyOS/**` 与 workflow 自身）+ 手动 `workflow_dispatch`；同一 PR 或分支并发取消旧跑。dev 分支上早先手写的 `build-pr.yml` 草稿（npm install/hvigor 命令不可用）已删除，以本文件为准。
- 工具链：`ErBWs/setup-ohos@v2` action，从社区镜像仓库 `ErBWs/ohos-sdk` Releases 下载 Command Line Tools **6.1.1.280**（SDK 6.1.1.125 / API 24，与本机 CLT 6.1.1.300 同 SDK 基线；hvigorw/ohpm/Node 进 PATH，`cache: true` 缓存 `~/ohos-sdk`）。华为官网 CLT 下载需账号登录无法直链，镜像分卷资产带 sha256 校验。**不要用镜像里的 26.0.0.621**：其 hvigor 6.26.x 不能构建 6.1.1(24) 工程（同 7.1 的 00303031 限制）。
- 步骤：`apt libgl1-mesa-dev` → setup → `ohpm install --all` → debug `assembleHap` → 上传 debug unsigned HAP（PR 保留）→ push/手动运行时再构建并上传 release unsigned HAP（14 天）→ Linux 单测诊断。**hypium 本地 runner 在 Linux CI 上挂死**（`UnitTestArkTS` 编译完成后 `> hvigor Linux` 起零输出；本机 Windows 同命令可完成），故单测限时 4 分钟、保留退出码但不阻塞构建，打印 `.test` 目录树并上传 `test-output` artifact。缓存 `~/ohos-sdk`（action 自带）、`~/.ohpm`、`~/.hvigor`。
- 已知事实：hypium 断言失败不会使 `hvigorw test` 非零退出（本机 StreamHeaders 用例失败仍 BUILD SUCCESSFUL/EXIT 0），CI 的单测把关需解析报告而非依赖退出码；Linux 挂死根因未明，修复后应移除限时与非阻塞。
- 2026-08-18 首轮验证：run 32048335317（dev）单测步骤 40 分钟零输出超时取消；二轮 run 32083328097 通过（conclusion success）——单测 `exit=124` 挂死复现（`.test` 下仅 testability 骨架、outputs 从未生成），debug/release HAP 分别 19s/14s 构建成功，`hap-unsigned-2`（782KB）产物正常。工具链下载+解压约 3 分钟；被取消的 run 不写 actions/cache，需完整成功跑一次后后续 run 才命中缓存。
- 产物为 unsigned HAP：CI 无签名材料，签名仍在本地走 7.3 的 `sign-local.ps1`（符合"证书与口令不入库"约定）。
- 未纳入 CI：codelinter（存量 17 warn+1 suggestion 基线，需过滤规则后才可门禁）、ohosTest（需模拟器+签名）、Release 自动发布。后续可选：tag 触发上传 unsigned HAP 到 GitHub Release。
- 2026-08-18 协作配置补齐：新增 `.github/PULL_REQUEST_TEMPLATE.md`、HarmonyOS Bug/Feature/分支整合 Issue Forms、`.github/dependabot.yml`、根目录 `CONTRIBUTING.md` 与 `docs/GITHUB_COLLABORATION.md`；workflow 增加 `contents: read`、关闭 checkout 持久凭据、按 lockfile 失效依赖缓存，并使用 PR 号/分支维度并发组。目标模型为 `main` 稳定、`dev` 集成、个人/feature 分支 PR 协作；`su` 在迁移期只保留 PR 检查，不响应直接 push。未修改 Android 参照工程与业务源码。


每次 SDK 或上游 Android 更新，都更新本文件的核验日期、版本矩阵、源码状态和测试结果。
新增能力必须附官方页面 URL、适用 API、代码位置、验证设备、失败日志和降级方案。

如果官方页面、工程配置和历史日志冲突，以当前官方 Release 文档、当前 DevEco Studio 生成配置和可重现设备测试为准。
