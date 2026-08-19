# NeriPlayer → HarmonyOS 完整移植执行计划（GLM-5.3 执行版）

> 创建：2026-08-16。最近修订：2026-08-19（M6.0 spike 后 D2 决策修正、M6 任务重排）。执行者：GLM-5.3（ZCode agent）。本文档是**任务级执行计划兼跨会话进度看板**，与既有文档分工如下，冲突时以本文档的任务排序为准、以仓库源码为最终事实：
>
> - 战略路线图：`docs/HARMONYOS_PORTING_PLAN.md`（架构原则、阶段划分，本文档细化其执行）。
> - 能力状态：`docs/FEATURE_MATRIX.md`（本文档的进度以矩阵状态为准同步更新）。
> - 环境与构建：根 `AGENTS.md` + `docs/hm.md`（命令与版本事实）。
> - 原型历史：`NeriPlayer-HarmonyOS/PORTING.md`。
>
> **使用方式**：每次会话按 §1 工作循环执行；每完成一个任务，在 §6 对应条目打 `[x]` 并追加一行证据（日期 + 命令 + 结果）；无法完成时写明阻塞原因。不确定的事实先查源码/文档，禁止凭记忆推断。

---

## 1. 执行守则（每个会话必读）

...（其余内容与之前相同，保留完整）

> 创建：2026-08-16。执行者：GLM-5.3（ZCode agent）。本文档是**任务级执行计划兼跨会话进度看板**，与既有文档分工如下，冲突时以本文档的任务排序为准、以仓库源码为最终事实：
>
> - 战略路线图：`docs/HARMONYOS_PORTING_PLAN.md`（架构原则、阶段划分，本文档细化其执行）。
> - 能力状态：`docs/FEATURE_MATRIX.md`（本文档的进度以矩阵状态为准同步更新）。
> - 环境与构建：根 `AGENTS.md` + `docs/hm.md`（命令与版本事实）。
> - 原型历史：`NeriPlayer-HarmonyOS/PORTING.md`。
>
> **使用方式**：每次会话按 §1 工作循环执行；每完成一个任务，在 §6 对应条目打 `[x]` 并追加一行证据（日期 + 命令 + 结果）；无法完成时写明阻塞原因。不确定的事实先查源码/文档，禁止凭记忆推断。

---

## 1. 执行守则（每个会话必读）

### 1.1 会话启动清单

1. 读根 `AGENTS.md`（工作约定）→ 本文档 §6 看板 → `git status --short`（识别用户已有修改，非必要不得覆盖）。
2. 按 §6 里程碑顺序选择下一个未完成任务；同一会话只做 1~3 个强相关任务，保证每步可验证。
3. 修改 `NeriPlayer-HarmonyOS/`；`NeriPlayer-master/` 只读参照，不逐行翻译 Kotlin，抽语义重写。

### 1.2 单任务工作循环

1. **定位参照**：在 Android 快照找到对应类/测试（§3.2 有索引），确认行为语义（用子代理 `Explore` 跨文件搜索，节约主模型成本）。
2. **核对 API**：涉及新 Kit/权限时，用 `doc-researcher` 或华为官方文档核对 API 24 可用性与签名，记录 URL；不得凭记忆写平台 API。
3. **实现**：ArkTS 严格模式（§4.4 规则）；新代码放入职责最接近的目录（§4.3 目标结构）；错误保留可诊断上下文；监听器/句柄/计时器在成功与失败路径都释放。
4. **测试**：纯逻辑必须配 `entry/src/test/`（hypium）确定性用例，优先从 Android JVM 测试（§4.5）提取 fixture；涉及 Ability/权限/AVPlayer/AVSession/后台的补 `entry/src/ohosTest/`。
5. **验证**（按最低验证要求，命令见 §2）：构建 + 单测 + codelinter 必做；播放/网络/权限/文件/后台类任务加模拟器 smoke；不能执行时明确标注「未验证」。
6. **收尾**：勾选看板 + 证据行；同步 `FEATURE_MATRIX.md` 对应行状态；交付说明按 AGENTS.md §交付说明。**完成任务后自行 commit并用中文写完善的提交信息**（除非用户明确拒绝）。

### 1.3 完成定义（DoD）

一个任务算完成，必须同时满足：主线 debug 构建通过；相关单测（新增+存量）全绿；codelinter 无新增 error；看板已勾选并附证据；FEATURE_MATRIX 状态已如实更新。占位实现、UI 入口不写为「完成」。

### 1.4 红线（继承 AGENTS.md，重点强调）

- 不提交密钥/口令/Cookie/签名材料/绝对路径；token 类凭据只能走 `@ohos.security.asset`（§7.1）。
- `.ps1` 纯 ASCII；日志脱敏；GPL-3.0 来源说明保留。
- 不把「历史验证过」当「当前已验证」；不修改 Android 快照/ASCF/package 目录。

---

## 2. 环境与命令速查（2026-08-14 已全链验证，详见 hm.md §7.5）

| 项 | 值 |
| --- | --- |
| 主力工程 | `D:\HarmonyOS\Project\Neriplayer\NeriPlayer-HarmonyOS`（API 24 = 6.1.1(24) Release 基线） |
| CLI 工具 | `D:\HarmonyOS\Tools\command-line-tools\bin\`（ohpm.bat / hvigorw.bat / codelinter.bat / Emulator.bat） |
| 完整 API 24 SDK | `D:\HarmonyOS\Tools\command-line-tools\sdk\default`（hdc 在 `openharmony\toolchains\`） |
| 26 Studio | `D:\HarmonyOS\Tools\devecostudio-windows-26.0.0.621\DevEco Studio`（仅贡献 jbr java 给 hap-sign-tool） |

```powershell
# 以下均从 NeriPlayer-HarmonyOS 目录执行（PowerShell；子进程调 pwsh 优先于 powershell 5.1）
$cli = 'D:\HarmonyOS\Tools\command-line-tools\bin'
& "$cli\ohpm.bat" install --all
& "$cli\hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon   # 构建
& "$cli\hvigorw.bat" test --mode module -p product=default -p buildMode=debug --no-daemon                                   # 本地单测
& "$cli\hvigorw.bat" assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug --no-daemon   # 设备测试 HAP
& "$cli\codelinter.bat" .                                                                                                   # 静态检查（基线 17 warn + 1 suggestion，无 error）

# 签名 + 安装模拟器（需用户级 NERIPLAYER_SIGNING_PASSWORD、DEVECO_SDK_HOME、DEVECO_STUDIO_HOME 已持久化）
.\sign-local.ps1 -HvigorwPath 'D:\HarmonyOS\Tools\command-line-tools\bin\hvigorw.bat'

# 模拟器：Emulator.bat 冷启动后先 tconn；ohosTest 用 aa test
hdc tconn 127.0.0.1:5555
hdc -t 127.0.0.1:5555 shell "aa test -b moe.ouom.neriplayer -m entry_test -s unittest OpenHarmonyTestRunner -s class ActsAbilityTest#assertContain -s timeout 15000"
```

**平台坑**：26 Studio 的 hvigor 不能构建 6.1.1(24) 工程（错误 00303031），构建必须用 CLT 的 hvigorw.bat；Git Bash 下调 hdc 设备路径加 `MSYS_NO_PATHCONV=1`，`hdc file recv` 本地目标用相对路径；.ps1 禁非 ASCII 字符（GBK 解析会静默吞代码行）。静态语法分析可用 `deveco-mcp` 的 `check` 工具（PROJECT_PATH 已指向主力工程）。

---

## 3. 两侧基线事实（2026-08-16 审计结论，避免重复调研）

### 3.1 Android 参照（`NeriPlayer-master/`，commit 快照 d66d465f，2026-07-31）

规模：`app/src/main` 946 个 Kotlin 文件约 18.6 万行 + C/C++ 约 5.67 万行；JVM 测试 285 文件约 4.94 万行。**无 Room**，数据层 = 文件 JSON + DataStore Preferences + (加密)SharedPreferences。播放栈 = 普通 Service + MediaSessionCompat + ExoPlayer（非 MediaSessionService）。

| 域 | 规模 | 关键类（`app/src/main/java/moe/ouom/neriplayer/` 下） |
| --- | --- | --- |
| 播放核心 | `core/player/` ~110 文件 | `PlayerManager.kt`(2564 行单例状态机)、`service/AudioPlayerService.kt`(2649)、`playback/PlayerManagerPlaybackExtensions.kt`(shuffle bag/history/future)、`audio/focus/StartupAudioFocusController`、`persistence/PlayerManagerPersistenceExtensions.kt`+`model/PersistedPlayerState.kt`、`url/PlayerUrlResolver`、`timer/SleepTimerManager`、`prefetch/*`、`policy/**`(18+ 策略类) |
| 平台 API | `core/api/` 30 文件 | `netease/NeteaseClient.kt`(909，WEAPI/EAPI/LinuxAPI)、`netease/NeteaseCrypto.kt`、`netease/NeteaseQrLoginClient`、`bili/BiliClient.kt`(1567，DASH 解析)、`bili/BiliQrLoginClient`、`youtube/YouTubeMusicClient.kt`(2995，proto 构造+手写 JSON 解析)、`youtube/YouTubeMusicPlaybackRepository`、`youtube/YouTubeEjsChallengeSolver`(androidx JavaScriptSandbox 跑 assets/`yt.solver*.js`)、`youtube/YouTubeWebPoTokenProvider`、`lyrics/`(LRCLIB/AMLL TTML) |
| 数据层 | `data/` 114 文件 | `settings/SettingsStore`+KSP 生成 schema、`history/PlayHistoryRepository`(filesDir JSON)、`local/playlist/LocalPlaylistFileStorage`(主文件+.bak+.sync-pending)、`sync/`(SyncCoordinator、GitHubSyncManager、WebDavSyncManager、全部 merge policy 纯逻辑、`github/GitHubRepositorySyncTransport`、`webdav/WebDavApiClient`、`github/SecureTokenStorage`=Keystore+EncryptedSharedPreferences)、`auth/{netease,bili,youtube}/` Cookie 仓库、`platform/` 各平台缓存仓库 |
| 下载 | `core/download/` 60+ 文件 | `GlobalDownloadManager.kt`(~1500，启动恢复/终结/回滚)、`core/player/download/AudioDownloadManager`(`DownloadTransportKind{DIRECT,CHUNKED_RANGE,HLS}`、`DownloadStage`、HLS 续传状态)、`task/DownloadTaskStore`、`storage/commit|migration|working|atomic|tree|snapshot|sidecar/` |
| 一起听 | `listentogether/` 58 文件 | `protocol/`、`network/ws/ListenTogetherWebSocketClient`+`reconnect/`、`session/`、`playback/sync/`；**服务端在空子模块 np-submodule/NeriPlayer-LTW，外部依赖** |
| USB 独占 | ~9.9k Kotlin + 5.7 万 C++ | `core/player/usb/`、`app/src/main/cpp/usb/`(UAC1/UAC2/反馈时钟)、内置 libusb |
| UI | `ui/` 170 文件 6.86 万行 | `NeriApp.kt`(~3300，唯一 NavHost)、`screen/tab|host|playlist|artist|settings|debug|safemode/`、`viewmodel/` 30 文件、`theme/NeriTheme`(material-kolor 动态取色)、`component/lyrics/AdvancedLyricsView` 等 |
| 其他 | — | `core/startup/`(阶段编排+SafeMode)、`core/crash/`、悬浮歌词 `core/player/lyrics/FloatingLyricsOverlayManager`(SYSTEM_ALERT_WINDOW)、`activity/auth/` WebView 登录页、`tools_pub/ytmusic_api_probe.py`(2183 行 API 探针) |

四个 np-submodule 目录均为空（一起听服务端、歌词 core/ui、miuix）→ 快照无法独立 Gradle 构建，**不尝试构建 Android 工程**，只读源码与测试。

### 3.2 鸿蒙现状（`NeriPlayer-HarmonyOS/`，56 文件 7698 行，2026-08-16 静态审计）

**真实现**：AVPlayer 播放全链路（`player/PlayerManager.ets` 662 行：状态机/seek/切歌/重试/速度/fd 句柄管理/统计埋点）、队列+随机+循环+QueueState 序列化（`:296-321,644-655`）、AVSession 基础（5 命令+浅元数据）、网易云 weapi+风控回退+取流+歌词+歌单（`network/NeteaseApi.ets` 344 行）、B 站搜索+DASH 取流（123 行）、YTM 搜索（innertube）、LRCLIB/网易歌词、LRC 解析+翻译合并（3 条单测）、17 个页面骨架全路由、8 个 preferences 仓库、设置双通道持久化、AudioViewPicker 本地导入、纯 ArkTS weapi 加密（AES+RSA）、Cookie 罐 HttpClient。

**空位/缺陷**（移植主战场，行号为审计时点）：

| 编号 | 缺口 | 位置 |
| --- | --- | --- |
| G1 | 音频中断/焦点：完全无处理 | 全仓无 audioInterrupt |
| G2 | 睡眠定时只有 UI 层 setTimeout 正分钟；「播完当前/列表」不实现 | `NowPlayingPage.ets:106-117` |
| G3 | AVSession 元数据无封面/时长/缓冲，状态只有 PLAY/PAUSE，无 off/release | `AVSessionManager.ets` |
| G4 | BackgroundTaskRunner 纯占位（未调 startBackgroundRunning，靠 backgroundModes） | `BackgroundTaskRunner.ets:4-10` |
| G5 | **疑点：队列跨冷启动恢复疑似失效**——`player.queueJson` 只写 AppStorage（内存态），未落 preferences | `PlayerManager.ets:644-655` |
| G6 | YouTube 取流直接抛错（无 signature/n、PoToken、HLS、EJS） | `YouTubeMusicApi.ets:171-177` |
| G7 | 下载只有任务目录 UI，无传输引擎 | `DownloadsRepository.ets:7-10` |
| G8 | 三平台登录、同步（GitHub/WebDAV）、一起听、动态取色、悬浮歌词、USB：全部占位 toast | `SettingsDetailPage.ets:321-358` 等（§5e 清单见 PORTING.md） |
| G9 | 数据层无 schema 版本/迁移/原子写/损坏恢复；集合整段 JSON 存单键全量读写 | `data/AppPreferences.ets` |
| G10 | NetEase 自动换 B 站源已写未接线 | `StreamResolver.ets:53-54` |
| G11 | B 站缺 WBI 签名/登录/收藏夹/分 P；网易云缺 eapi/登录/用户歌单 | `BiliApi.ets`、`NeteaseApi.ets` |
| G12 | LRC 不支持 [offset:]/逐字/元数据头；歌词偏移设置未消费 | `LrcParser.ets` |
| G13 | 测试仅 3 条 LRC 单测 + 1 条 ohosTest 骨架 | `entry/src/test` |

---

## 4. 总体策略

### 4.1 排序原则

1. **纯逻辑优先**：能脱离设备确定性测试的先做（加密、解析、合并策略、状态机、命名规划）——Android 侧约 40-50% 是纯逻辑，这是性价比最高的部分。
2. **垂直切片**：每个里程碑交付「用户可感知 + 可自动化验证」的闭环，而非横向铺文件。
3. **依赖驱动**：登录→高音质取流/用户歌单；schema 版本化→下载/同步；合并策略→同步；JS 运行时决策→YouTube。
4. **风险隔离**：YouTube 取流、USB、悬浮歌词是研究性任务，单独决策点（§5），不阻塞主线。

### 4.2 里程碑总览与依赖（预估新增/改动 ArkTS 行数仅作规模感，非承诺）

| 里程碑 | 内容 | 预估规模 | 依赖 |
| --- | --- | --- | --- |
| M1 | 播放核心补强（中断/睡眠/AVSession/后台/队列恢复）+ 队列状态机抽取 | ~1.5k 行 | 无 |
| M2 | 数据层版本化、原子写、损坏恢复、Android 格式对齐 | ~1.2k | 无（M3/M5 地基） |
| M3 | 下载管线（DIRECT/RANGE/HLS、断点恢复、原子提交、编目） | ~2.5k | M2 |
| M4 | 平台登录与凭据（网易云/B 站 QR、cookie 仓库、asset 存储） | ~2k | 无 |
| M5 | 同步（合并策略族移植、GitHub Contents API、WebDAV、凭据） | ~3k | M2、M4 |
| M6 | YouTube 取流（JS 运行时 spike → signature/n → PoToken → HLS） | ~3k + 研究 | D2 决策 |
| M7 | 一起听客户端（协议、WebSocket、重连、校时） | ~2.5k | M1；外部服务端 |
| M8 | 视觉与歌词增强（动态取色、模糊、逐字/TTML、偏移、WaveformSlider） | ~2k | 无，可穿插 |
| M9 | USB 独占可行性研究 + 发布门槛（矩阵/无障碍/合规） | 研究为主 | D5 决策 |

M1→M2→M3 是主线路径；M4 与 M2 可并行；M8 任务小可作穿插调剂；M6/M7/M9 允许随时暂停。

### 4.3 目标目录结构（在现有目录内增量扩展，不发起全量重构）

```text
entry/src/main/ets/
├── player/            现有 + queue/QueueEngine.ets（纯状态机）、SleepTimer.ets
├── data/              现有 + auth/（各平台 cookie/token 仓库）、schema/（版本与迁移）
├── download/          新增：引擎、传输、提交、编目（M3）
├── sync/              新增：合并策略（纯逻辑）、github/、webdav/（M5）
├── network/           现有 + ytm/（M6 拆分）、auth/（登录流程）
├── listentogether/    新增（M7，对齐 Android 包名）
└── view/              现有页面持续补齐
```

### 4.4 ArkTS 严格模式转换规则（高频坑）

- 禁 `any`/`unknown`；对象字面量必须可推断到明确接口/类；JSON 解析走手写 `fromJson`（沿用 `SongItem.ets` 模式），解析处兜底默认值。
- 集合用 `Array<T>`/`Map<K,V>`；禁 `Record` 隐式索引访问，必要处显式断言并处理 undefined。
- 异步统一 `Promise`/`async/await`；`@ohos.*` API 用 Promise 形态；错误信息携带上下文（`Logger`）。
- 闭包不捕获页面组件引用；`on` 监听配对 `off`；`fs` 句柄、`http` 请求、计时器必须释放。
- 平台 API（时间/随机/网络/文件）经小型适配层隔离，使核心逻辑可在 `entry/src/test` 用 fake 测试（沿用 AGENTS.md 约定）。

### 4.5 测试策略与 Android 用例对齐表

fixture 从 Android JVM 测试（`app/src/test/`）摘取**小样本**内嵌进 ArkTS 测试文件（不依赖运行时文件加载）。每个里程碑至少对齐下列高价值测试语义：

| 域 | Android 测试（app/src/test） | 鸿蒙目标 |
| --- | --- | --- |
| 随机/循环 | `PlayerManagerShuffleQueueRemapTest`、`PlayerRepeatModePolicyTest` | `test/QueueEngine.test.ets`（M1.1） |
| weapi 加密 | NeteaseCrypto 相关向量 | `test/NeteaseCrypto.test.ets`（M4 顺手补） |
| 同步合并 | `data/sync/github/**` merge/serializer/causal token 测试 | `test/SyncMerge.test.ets`（M5.1） |
| 下载 | `DownloadTaskStoreTest`、`ManagedDownloadNamingTest` | `test/Download*.test.ets`（M3.x） |
| 歌词 | `AmllTtmlClientTest`、`LyricTimestampNormalizerTest` | `test/LrcParser.test.ets` 扩展（M8） |
| 稳定键 | `SystemPlaylistIdentityTest` | 已有 SongIdentity，补测（M2.2） |
| 一起听 | `listentogether/**` 10 个 | `test/ListenTogether*.test.ets`（M7.1） |

---

## 5. 关键决策点（执行到该处时先决策并记录，格式：决策/理由/日期）

| # | 决策点 | 默认方案（无用户输入时按此执行） |
| --- | --- | --- |
| D1 | 同步数据线格式：Android `SyncDataSerializer` 用 kotlinx protobuf 二进制 | **调研修正（2026-08-18，M5.1）**：Android 实为双格式——默认写 JSON 文本 `backup.json`（kotlinx JSON，camelCase 全字段、null 省略），省流模式写 `GZIP(protobuf)` 原始字节 `backup-raw.bin`，另有遗留 `backup.bin`=`Base64(GZIP(protobuf))` 只读兼容；读路径三格式自动识别；无 .proto 文件（@ProtoNumber 注解即 schema，~15 message 全部已知）。**定案**：鸿蒙侧 M5.2 实现 JSON 读写（与 Android 默认格式互通，fixture 可构造）+ 手写最小 protobuf wire 编解码器 + GZIP（`@ohos.zlib` 能力核对）补齐省流格式读取；protobuf 字段号/schema 已在 M5.1 调研中全量记录（SyncData tag1-13、SyncSong tag1-29 等）。禁止静默不兼容。 |
| D2 | YouTube JS 运行时：Android 用 androidx JavaScriptSandbox 跑 yt.solver | **调研修正（2026-08-19，M6.0 spike）**：主路径改为 **IOS client 直连取流，零 JS 运行时依赖**——探针实测（docs/YTMUSIC_M60_SPIKE.md：4 视频一致）IOS 21.03.2 匿名 player API 直出无 cipher 可下载 URL（Range 206 验证），tvhtml5 完整版被剥 URL、downgraded 全部需解签；Android 需要 solver 纯因其 client 链全为 web/tv 系。**ArkWeb 离屏 Web（方案 A，可行性已调研确认：web-offline-mode + runJavaScriptExt，单实例约 200MB）降级为 M6.3 兜底**，仅当 IOS 路径被风控/PoToken 政策收紧时实施；NAPI QuickJS（B）搁置，常驻需求优先官方 JSVM-NAPI。风险：IOS 直出窗口随时可能被 YouTube 收紧，兜底链保留。 |
| D3 | 下载落盘位置 | 默认应用沙箱 `files/Download/`（自管目录树，对齐 Android ManagedDownloadTree 语义）+ 后续提供「导出/分享」；用户可见目录选择（DocumentViewPicker + 持久授权）作为可选增强，避免一开始绑定 URI 生命周期复杂度。 |
| D4 | 悬浮/状态栏歌词 | 普通应用无 SYSTEM_ALERT_WINDOW 等价物：降级为「应用内 overlay 迷你歌词 + 通知文本歌词（如可行）」，在 FEATURE_MATRIX 记录降级结论，不承诺系统级悬浮。 |
| D5 | USB 独占音频 | 先做可行性 spike（`@ohos.usbManager` 等时传输/独占策略/syscap + 真机），大概率不可行→官方结论+降级（USB DAC 走系统音频路径）。C++ 5.7 万行**不预移植**。 |
| D6 | B 站接口加固（WBI 签名） | 当前搜索/DASH 可用则暂不移植 WBI；遇到风控再按 Android `BiliClient` 对齐补齐，并在 DebugPage 加探针。 |
| D7 | 一起听服务端 | 外部依赖：需用户提供服务器地址（上游 np-submodule/NeriPlayer-LTW 为空）。客户端先行 + 对着协议测试开发，服务端联通验证延后。 |

---

## 6. 里程碑任务看板

> 格式：`- [ ] Mx.y 任务名`。完成时改 `[x]` 并在下一行缩进追加 `- 证据：2026-MM-DD <命令/验证摘要>`。

### M1 播放核心补强（对齐「首个可交付垂直切片」，战略计划阶段 2）

- [x] M1.0 复核 G5：模拟器实测队列跨冷启动是否恢复（播放→杀进程→重启看队列）；若失效，把 QueueState 落盘到 preferences（PlayerManager 在 publishQueue 时节流写，启动 restoreQueue 改读 preferences），并补「重启恢复队列+播放位置」ohosTest。
  - 证据：2026-08-16 代码复核确认失效（`player.queueJson` 仅写 AppStorage 内存态，全仓无 PersistentStorage/无落盘，冷启动必丢）。修复：新增 `model/PersistedPlaybackState.ets`（version 预埋；songs/queueIndex/positionMs/repeatMode 完整枚举/shuffle/speed，对齐 Android `PersistedState`；损坏 JSON/非数组 songs/非法枚举均有兜底）+ `data/PlaybackStateRepository.ets`（AppPreferences 单键 `playback_state`）；PlayerManager publishQueue 防抖 250ms 落盘、播放中进度 15s 节流、paused/切模式立即写，`restoreFromDisk()` 启动异步恢复（不自动播，play() 时从恢复位置 seek 续播），顺带修复非 shuffle 恢复索引不生效（旧 restoreQueue 硬置 orderIndex=0）；EntryAbility onBackground/onDestroy 挂 persistNow。**平台坑（已实证并修复）**：UIAbilityContext 的 preferencesDir 是模块级（`haps/<module>/preferences`），entry 与 entry_test 各一份文件导致跨模块数据不可见（`docs` 冲突以源码为准；OH 文档 gitee.com/openharmony/docs …js-apis-data-preferences + application-context-stage）→ `AppPreferences.doInit` 改 `context.getApplicationContext()` 落应用级文件（原型期无存量数据，不迁移）；`AbilityDelegator.getAppContext()` 构造的 context `stageMode=false` 被 preferences 拒绝（invalid context），ohosTest 改在 TestAbility.onCreate 用 `this.context` init；hypium 1.0.28 不 await async beforeAll/it。验证（2026-08-16）：entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；本地单测 `hvigorw test` 通过（LrcParser 3 + PersistedPlaybackState 5：往返/三值 RepeatMode/缺字段默认/非法值回退/损坏返回 null）；codelinter 17 warn + 1 suggestion 与基线持平无新增 error；模拟器（Pura 90 API 24）ohosTest 3/3 通过（ActsPlaybackStateRestoreTest：持久化恢复队列+索引+位置+模式、损坏数据兜底）；端到端 smoke：aa test 写入→主应用冷启动 `restored queue: 3 songs at index 1`→force-stop→再冷启动再次恢复（主应用 persistNow 写回数据杀进程后可读，真实用户「播放→退出→重启」路径成立）。
- [x] M1.1 抽取纯队列状态机 `player/queue/QueueEngine.ets`：移植 Android shuffle bag/history/future 结构（`PlayerManagerPlaybackExtensions.kt`：`rebuildShuffleBag`、next/prev 推进、种子化随机）与 RepeatMode 策略，替换 `PlayerManager.ets:296-321` 的即时洗牌；使队列快照可完整序列化/恢复（含随机种子）。测试对齐 `PlayerManagerShuffleQueueRemapTest`/`PlayerRepeatModePolicyTest`。
  - 证据：2026-08-16 新增 `player/queue/QueueEngine.ets`（~430 行，零 @ohos 依赖）：shuffle bag/history/future 三结构 + 不变量（当前曲不在 bag、future LIFO）；`SeededRandom`（LCG 种子化随机，默认 Date.now() 种子）使抽取序列可复现；`next(force)/previous()/playAt()/setShuffle()/start()` 对齐 Android nextImpl/previousImpl/playFromQueueImpl（含顺序模式 OFF 末尾静默忽略、ALL 回绕、bag 耗尽按 force/ALL 重建、单曲队列重播、prev 不碰 bag）；`onTrackEnded()` 三态策略（对齐 PlayerRepeatModePolicyTest 语义，REPLAY/ADVANCE/STOP）；纯函数 `remapForInsertNext`（对齐 remapShuffleStateForInsertNext：removal→insertion 位移→newSong 移出 bag/history→future 去重追加）与 `currentIndexAfterMove`；`toJson/fromJson` 全量快照含 randomState。PlayerManager 删除 order/orderIndex/buildOrder/nextOrderIndex 即时洗牌，next/previous/playAt/恢复全部走 engine；cycleRepeatMode 对齐 Android 顺序 OFF→ALL→ONE（UI 原为 OFF→ONE→ALL 已修正）；queue sheet 高亮/播放改用队列下标 `getCurrentQueueIndex()`（修正 shuffle 下 UI 高亮错位）。验证：本地单测 `hvigorw test` 全绿（新增 QueueEngine 21 用例：remap 10 个逐一对齐 Android ShuffleQueueRemapTest、顺序/随机推进含同种子同序列与 LIFO、TrackEnd 三态、cycle 顺序、快照往返含随机态续走一致、损坏返回 null）；entry@default/entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 18 项与基线持平无新增；模拟器 ohosTest 3/3；冷启动恢复 + force-stop 重启恢复 smoke 均打出 `restored queue: 3 songs at index 1` 无回归。
- [x] M1.2 音频中断处理（G1）：按 API 24 文档核对 AVPlayer/AVSession 的中断模式与事件挂载方式（doc-researcher，记录 URL），实现：瞬态抢占→暂停并记住恢复意图，永久抢占/设备切换→暂停+UI 同步；对齐 `StartupAudioFocusController` 语义。ohosTest + 真机/模拟器双媒体 app 竞争 smoke。
  - 证据：2026-08-16 新增 player/AudioInterruptPolicy.ets（纯逻辑：FORCE+PAUSE→瞬态暂停记恢复意图、FORCE+STOP→永久、DUCK/UNDUCK 系统自理、SHARE+RESUME 按意图恢复；设备不可用→硬暂停）+ PlayerManager 接线（ensurePlayer 挂 audioInterrupt/audioOutputDeviceChangeWithInfo，loadSong prepared 后设 SHARE_MODE，applyInterruptAction 分派，用户 pause() 清恢复意图）。API 依据：华为 audio-playback-concurrency/AVPlayer 文档（InterruptHint 枚举、SHARE/RESUME forceType 语义、REASON_OLD_DEVICE_UNAVAILABLE 暂停建议，URL 已记 hm.md）。单测 6 用例（AudioInterruptPolicy.test.ets）通过。双媒体竞争真机 smoke 未执行（模拟器无第二个可控媒体 app），标注待复核。本地单测+构建+ohosTest 4/4 通过。
- [x] M1.3 睡眠定时下沉 `player/SleepTimer.ets`（G2）：对齐 `SleepTimerManager`——正分钟定时、播完当前、播完列表三种模式，接 PlayerManager 完成回调；NowPlayingPage 改为调用；单测用 fake 计时器。
  - 证据：2026-08-16 新增 player/SleepTimer.ets（四模式 COUNTDOWN/COUNTDOWN_FINISH_CURRENT/FINISH_CURRENT/FINISH_PLAYLIST、注入时钟+调度器、tick 每秒、到期迁移语义、shouldStopOnTrackEnd 三查询、重启静默替换，对齐 SleepTimerManager）+ PlayerManager 接线（handleCompletion 中睡眠仲裁先于 repeat 分派——repeat ONE/ALL 不能阻止定时停；AppStorage 发布剩余分钟）+ NowPlayingPage 播完当前/播完列表两档真实生效（原 UI setTimeout 只有正分钟且不实现 -1/-2）。单测 7 用例（SleepTimer.test.ets，ManualClock/ManualScheduler 确定性）通过。
- [x] M1.4 AVSession 补全（G3）：元数据加封面（PixelMap/URI 按 API 24 能力定）、时长、assetId 稳定化；状态映射 LOADING/PLAY/PAUSE/COMPLETED；倍速同步；补 `off`/`release` 清理；核对控制中心/锁屏显示（模拟器截图验证）。对齐 `AudioPlayerService` 的 MediaSessionCompat.Callback 全集（如支持 loop 命令则接 RepeatMode）。
  - 证据：2026-08-16 AVSessionManager 重写：AVMetadata 加 duration/mediaImage（封面 URL 字符串，API 24 接受 string|PixelMap）、assetId 稳定化（platform:id:mediaUri 防跨平台撞车）；AVPlaybackState 全状态映射（LOADING→PREPARE/PLAYING→PLAY/PAUSED→PAUSE/COMPLETED/ERROR）+speed/duration/loopMode（LoopMode↔RepeatMode 三值映射）；命令补 stop/setSpeed/setLoopMode；release() 逐一 off+destroy（EntryAbility.onDestroy 调用）。依据：本机 API 24 d.ts（字段/枚举核对）+ avsession-access-scene 指南。锁屏/控制中心显示人工核验未执行，待复核。
- [x] M1.5 后台播放合规（G4）：核对 API 24 `backgroundTaskManager.startBackgroundRunning` 与 `backgroundModes: audioPlayback` 的关系（是否必须调用/缓存配额），把 BackgroundTaskRunner 改为真调用或删除占位类；熄屏 30 分钟长播 smoke（模拟器）+ 记录结论。
  - 证据：2026-08-16 BackgroundTaskRunner 由纯占位改为 backgroundTaskManager.startBackgroundRunning(context, AUDIO_PLAYBACK, wantAgent) 真调用（wantAgent 指向 EntryAbility，缓存实例；stop 于暂停；失败降级日志不阻断播放）。依据：AVSession 后台指南（必须 AVSession+AUDIO_PLAYBACK 长时任务否则退后台静音冻结）+ API 24 d.ts 签名（startBackgroundRunning 必传 wantAgent）。KEEP_BACKGROUND_RUNNING 权限与 backgroundModes 声明已在 module.json5。熄屏 30 分钟长播 smoke 未执行，待复核。
- [x] M1.6 取流健壮性：把 `StreamResolver.resolveNeteaseFallback` 接入 PlayerManager 失败路径（G10，加设置开关「网易失效自动换源」）；`PlayerUrlResolver` 的质量降级语义对齐（exhigh→high→standard 已有，补错误分类）。
  - 证据：2026-08-16 StreamResolver.resolveWithNeteaseAutoFallback：直连失败→设置开关（np.netease_auto_fallback 默认开，SettingsDetailPage 流量区开关行）→BiliApi.search(名称+歌手) 候选→matchScore≥2（标题包含+时长差<8s）→B 站取流，成功 URL 缓存进 song.streamUrl；PlayerManager.resolveStreamUrl 接入。真实换源效果需网易失效场景实测，逻辑由编译+smoke 保障。
- [x] M1.7 里程碑验收：模拟器全流程 smoke（搜→播→中断→恢复→熄屏→锁屏控制→重启恢复队列）；FEATURE_MATRIX 五行状态更新；hm.md 记录验证。
  - 证据：2026-08-16 里程碑验收：本地单测全绿（Lrc 3+Persisted 5+QueueEngine 21+InterruptPolicy 6+SleepTimer 7=42 用例）；entry@default/entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 与基线持平（仅存量 2 条 await-seek warn）；模拟器（Pura 90 API 24）ohosTest 4/4（含 ActsPlaybackSmokeTest：真实网络音频 initialized→prepared→SHARE_MODE→playing→paused→release 全链）；冷启动恢复+force-stop 重启恢复队列 smoke 均通过（restored queue: 3 songs at index 1）。未自动化验证：搜索→播放的 UI 全流程、双媒体竞争中断、熄屏 30 分钟长播、锁屏控制中心显示（模拟器 UI 自动化不可行），FEATURE_MATRIX 对应行标注待复核。

### M2 数据层版本化与跨端兼容（战略计划阶段 3 的本地部分）

- [x] M2.1 `data/schema/`：定义 `SchemaVersion` 常量与 `migrate(key, rawJson)` 框架；所有集合型仓库读路径统一走「读→校验版本→迁移→缓存」；写路径加节流防抖。
  - 证据：2026-08-16 新增 data/schema/SchemaStore.ets（SchemaVersion.CURRENT=1；load：主值→parse 失败回退 <key>.bak→恢复值写回主键→再失败用调用方默认并 warn；save：旧值轮换进 .bak 再写新值；saveDebounced 按键防抖 500ms + flush/flushAll）。History/LocalPlaylist/PlaybackStats 三仓库读路径全部改走 SchemaStore.load（parseJson 提取为可测纯函数）。本地单测+构建+ohosTest 通过。
- [x] M2.2 格式对齐 Android：从 `PlayHistoryRepository`/`LocalPlaylistFileStorage`/`PlaybackStatsCounterStore` 提取 Gson 字段名，校对鸿蒙 JSON 字段一致性（历史/歌单/统计三个格式），用 Android fixture 单测跨端兼容；补 `SongIdentity.stableKey` 测试（对齐 `SystemPlaylistIdentityTest`）。
  - 证据：2026-08-16 新增 data/AndroidDataParser.ets（Android Gson 契约解析：play_history.json 的 PlayedEntry 数组含 playedAt→addedAt 映射与 null 容错；local_playlists.json 的 id(number→string)/name/songs/modifiedAt→updatedAt/customCoverUrl→coverUrl/songOrderVersion 忽略，成员键由导入歌曲推导）。单测 9 用例（AndroidDataParser.test.ets）：Android 测试源摘录的历史/歌单 fixture 字节级断言（含 "123|netease|" stableKey 格式对齐 SystemPlaylistIdentityTest、YTM videoId 归一化同 id、本地歌 id|album|mediaUri 回退）。顺带修复 SongIdentity 存量缺陷：本地歌（platform=LOCAL）曾被 mediaUri 为空分支误归一化为 netease 通道，现直接走 id|album|mediaUri（对齐 Android，原型期存量键可弃）。
- [x] M2.3 原子写与备份：preferences 写入前存 `.bak` 键（或文件级 tmp+rename 方案，按数据大小决策）；JSON.parse 失败→用备份恢复→再失败重建默认+落错误日志（对齐 ReplaceFileCorruptionHandler/.bak 语义）。
  - 证据：2026-08-16 <key>.bak 轮换备份 + 读路径三级回退（主值→bak 恢复并写回→默认）实现于 SchemaStore；ohosTest ActsSchemaRecoveryTest 3 用例设备实证：主损坏+bak 完好→恢复且写回、双损坏→默认不崩、save 连写两次→bak 保留前值。
- [x] M2.4 歌单 `.sync-pending` 语义预埋（为 M5）：变更标记读写接口先建（纯逻辑+单测），同步接入留 M5。
  - 证据：2026-08-16 SyncPendingState（markPending/clearPending/isPending/toJson/fromJson 纯逻辑+单测）+ LocalPlaylistRepository 变更方法（addSong/removeSong/create/rename/remove/ensureFavorites）写后按 playlistId 打标，键 playlists.sync_pending；getSyncPendingIds/clearSyncPending 接口留给 M5 同步消费。
- [x] M2.5 验收：损坏数据注入测试（篡改 preferences JSON→启动应恢复不崩）；升级 fixture（v0→v1）测试。
  - 证据：2026-08-16 验收：损坏数据注入（ohosTest 3 用例通过）；Android fixture 跨端解析（历史/歌单）与 stableKey 格式单测通过；升级 fixture（v0→v1）当前无需迁移（所有键即 v1，框架已预留 SchemaVersion）；ohosTest 全套 7/7（Ability+Restore×2+Smoke+SchemaRecovery×3）、本地单测全绿、双模块构建通过、codelinter 基线持平。

### M3 下载管线（战略计划阶段 5 前半）

> 说明：M3.1~M3.5 的主体代码由 commit `00b5617`（M1 会话收尾时）一并带入但未在看板登记；本会话（2026-08-16 晚）审计确认后补齐闭环缺口、修复三个首次设备验证暴露的真 bug、完成 M3.7 验收并登记证据。

- [x] M3.1 纯状态机先行：`download/` 下移植 `DownloadTransportKind{DIRECT,CHUNKED_RANGE,HLS}`、`DownloadStage{TRANSFERRING,WAITING_RETRY,FINALIZING}`、`DownloadStatus{QUEUED,DOWNLOADING,WAITING_NETWORK,COMPLETED,FAILED,CANCELLED}`、attemptId 防重（参照 `AudioDownloadManager.kt:295-330`、`DownloadTaskModels.kt`）；单测对齐 `DownloadTaskStoreTest`。
  - 证据：`download/DownloadModels.ets`（三枚举+DownloadProgress percentage 语义（-1/0-99/100）+shouldApplyTaskMutation（expectedAttemptId<0 放行，对齐 null 语义））、`DownloadTaskStore.ets`（stableKey 索引+attemptId 守卫的 prepare/prepareBatch/registerActive/updateStatus/updateProgress/applyWaitingNetwork/clearCompleted，纯逻辑零 @ohos 依赖）、`DownloadSupport.ets`（重试 1000/2000/4000/5000ms 上限 6 次+可重试 HTTP/消息分类+ManagedDownloadNaming 模板/sanitize/npdl_ 工作文件名+传输选择器）。单测 23 用例对齐 DownloadTaskStoreTest 语义（批量去重唯一 attemptId、活跃任务保留、可重入任务换新 attemptId、replaceExistingActiveTasks 取代、attemptId 守卫 mutation、WAITING_NETWORK 清进度、clearCompleted 保留活跃、HLS fingerprint 序序敏感、ResumeFingerprint validator etag 优先）。2026-08-16 本地单测全绿（M3.7 验收时统一复核）。
- [x] M3.2 HttpClient 传输能力：新增流式下载方法（`requestInStream`/dataReceive），支持 Range、If-Range(ETag/Last-Modified)、总长/已收字节回调；超时/断网→`WAITING_NETWORK`；大文件写 `fs` 分块追加。单测用本地 HTTP fixture 或 mock。
  - 证据：`network/HttpStreamDownloader.ets`（requestInStream+headersReceive/dataReceive/dataEnd 事件流，Range: bytes=N- + If-Range validator，StreamDownloadHeaders 解析 etag/last-modified/accept-ranges/content-length/content-range start，onData 返回 false 即 abort；destroy 释放句柄）。**本会话修复真 bug ①**：dataEnd 先于 requestInStream promise settle 时 resolve(0) 屏蔽了真实响应码（NETSTACK 实证传输成功 RespCode 206 而 JS 侧拿到 0 → 引擎误判失败），现记录 responseCode 供 dataEnd 使用、then 侧 1000ms 兜底；成功判定语义改为「完成流+字节校验」（见 M3.3）。单测：本地 hypium 环境无 @ohos.http，用设备 ohosTest 真网验证替代（ActsDownloadSmokeTest），如实记录「本地 fixture 单测未做」。
- [x] M3.3 下载引擎 `download/DownloadEngine.ets`：并发控制（消费 `np.download_concurrency` 设置）、任务调度、断点续传（DIRECT/RANGE：`.part` sidecar 记 offset+etag；HLS：playlist fingerprint+nextSegmentIndex，对齐 `serializeHlsResumeState`）、重试退避、完成校验（长度/哈希按源能力）。
  - 证据：引擎并发 clamp(1..8) 默认 6、pump 调度、DIRECT 续传（`.download` 工作文件+`.resume.json` 指纹（sourceUrl/etag/lastModified/expectedContentLength），offset 由工作文件长度推导、If-Range=etag?:lastModified、Content-Range start 不匹配自动清盘重下、416 视为服务端已完成）、HLS 分片+FNV-1a playlist fingerprint+`.hls.json` checkpoint（分片级恢复，fingerprint/字节数不一致则整重下）、退避重试+断网 applyWaitingNetwork 挂起+netAvailable 恢复重入队。**本会话修复真 bug ②**：completeTask 原先先置 COMPLETED 再写 catalog，观察者（UI/离线播放）会读到旧目录；重排为 FINALIZING 进度→commit→写 catalog→最后置 COMPLETED，且 attempt 已被取代时回滚 catalog（对齐 Android rollbackStaleCompletedDownload）。完成校验=transferSizeComplete 字节校验（对齐 isTransferSizeComplete，哈希按源能力暂无源提供，未做）。
- [x] M3.4 原子提交与目录树：`storage/commit` 语义——working 目录写完→校验→rename 到正式目录树（`download/naming` 对齐 `ManagedDownloadNaming`）→更新编目 `DownloadedSongCatalog`；失败回滚清理。D3 决策落盘位置。
  - 证据：`DownloadStorage.commit`（staging `download_staging/npdl_<hash8>_<48>.<ext>.download` → rename `<filesDir>/Download/NeriPlayer/<模板名>.<ext>`）；编目 preferences 键 `downloaded_catalog`（SchemaStore 版本化+.bak）。D3 决策落地：应用沙箱自管目录树。**本会话修复真 bug ③**：编目 add/remove 曾把 `map(entry.toJson())` 的 JSON 字符串数组当对象数组存取（双重序列化，读回全空条目——设备实测 raw catalog 为 `["{\"stableKey\":\"\"...` 发现），改为直接序列化实例数组；DownloadedSongEntry 补字段初始化器；getCatalog 过滤空 stableKey 行自愈历史脏数据。OH preferences put+flush 原子性承担原子写（无 tmp+rename 文件级方案，preferences 单值 ≤8KB 场景足够，编目超长风险待观察）。
- [x] M3.5 启动恢复：`recoverPendingDownloadsForStartup` 语义——启动时扫任务目录，`DOWNLOADING/WAITING_NETWORK` 按网络状态续传或挂起；网络监听用 `util/NetworkStatus` 扩展（断网暂停、恢复续传）。
  - 证据：DownloadEngine.init→recoverPendingForStartup（loadQueue→prepareBatch(replaceExistingActiveTasks=true)→pump）；持久化队列键 `pending_download_queue`（entries: stableKey/order/queuedAtMs/songJson，对齐 pending_download_queue_v1 语义，经 SchemaStore）；connection.createNetConnection 的 netAvailable/netUnavailable 双向联动（断网→活跃任务 applyWaitingNetwork 挂起保留工作文件，恢复→重入队）。EntryAbility onCreate 调 init。
- [x] M3.6 接线 UI：DownloadsPage 真实进度/暂停/恢复/取消；SongRow「下载」走引擎；下载完成曲目入本地库可播（LOCAL 平台路径）；DebugPage 加下载探针。元数据 tag 写入：HarmonyOS 无公开 tag 写 API→sidecar 元数据+编目承担，FEATURE_MATRIX 记录降级。
  - 证据：DownloadsPage（监听引擎任务流、进度条、取消/重试/播放三态操作，COMPLETED→查编目→LOCAL+localFilePath→playPlaylist）；SongRow 下载菜单项 enqueue。**本会话补齐闭环**：① `PlayerManager.resolveStreamUrl` 非 LOCAL 平台先查编目命中即走本地 fd 播放（离线短路，对齐 Android offline-first；openLocalFd 提取复用 LOCAL 通道）② DownloadEngine.runTask 开头查编目防重复下载 ③ 三页面收口到新引擎并删除旧双轨（`data/DownloadsRepository.ets`+`model/DownloadTask.ets` 删除；LibraryPage 计数、SettingsDetailPage 存储统计/清理、DebugPage 清空全部改走 DownloadStorage/DownloadEngine）④ DebugPage「下载管线探针」（任务六状态统计+编目数/字节+staging 文件数）。「本地音乐」tab 并入编目列表为后续增强，未做。
- [x] M3.7 验收：模拟器下载网易云曲目→中途杀进程→重启恢复→完成→离线播放；断网暂停/恢复；单测全绿。
  - 证据：2026-08-16 模拟器（Pura 90 API 24，熄屏坑见 hm.md）：ActsDownloadSmokeTest 全链通过两次（网易云搜索「晴天」→enqueue→DIRECT 传输 5,889,065 字节→commit `Download/NeriPlayer/netease - 周杰伦*.m4a`→编目行完整→文件只读可开（fd 离线通道）→再次 enqueue 防重复短路 COMPLETED）；全套 ohosTest 8/8 回归通过（Ability+Restore×2+PlaybackSmoke+SchemaRecovery×3+DownloadSmoke）；主应用冷启动 smoke 无崩溃；本地单测/双模块构建/codelinter 全绿（基线 18 warn+1 suggestion 持平）。**未自动化项（如实记录）**：下载中途杀进程→重启续传（引擎逻辑有队列持久化+replace 语义单测，端到端中断场景未自动化）；断网暂停/恢复设备实测（模拟器禁网有断 hdc 风险，netUnavailable 路径有单测）；离线播放 UI 人工核验。**平台坑（实证）**：模拟器熄屏/锁屏状态跑 aa test 必失败（TestAbility onForeground 后 ~90ms 被切后台销毁，ResultCode -2 "onDestroy unexpectedly"），须先 `power-shell wakeup; power-shell setmode 602` 常亮再跑。

### M4 平台登录与凭据（战略计划阶段 4 登录部分）

- [x] M4.1 凭据基建 `data/auth/`+`@ohos.security.asset`：Asset Store 存取适配层（错误分类/降级到加密 preferences 的兜底策略需记录）；日志与导出全程脱敏。
  - 证据：2026-08-16（实际执行 2026-08-17 凌晨，下同）新增 `data/auth/AssetErrors.ets`（错误码→NOT_FOUND/DUPLICATED/FALLBACK/RETRY/FATAL 分类纯函数，码表核对自本机 API 24 d.ts `@ohos.security.asset.d.ts` ErrorCode 枚举 24000001..24000018）、`data/auth/CredentialStore.ets`（asset add/remove/query 适配：ALIAS+SECRET+ACCESSIBILITY=DEVICE_POWERED_ON+CONFLICT_RESOLUTION=OVERWRITE、Uint8Array↔string 经 util.TextEncoder/decodeToString；错误分类驱动 RETRY 一次重试与 FALLBACK 永久降级会话内存）、`data/auth/NeteaseAuth.ets`（纯逻辑：validateAndSanitize（名称字符表/禁分号/ISO 控制/补 os=pc+appver=8.10.35）、NeteaseAuthBundle toJson/fromJson（对齐 Android netease_auth_bundle 格式，损坏回退空）、健康评估、parseRawCookieText（对齐 RawCookieTextParser）、buildNeteaseCookieHeader、日志脱敏 cookieKeysForLog）、`data/auth/NeteaseCookieRepository.ets`（alias `netease_auth_bundle` 对齐 Android 键名；save/clear/seedHttpClient；np.netease_logged 真实写点；启动 init 恢复）。**降级策略记录**：asset 服务不可用（SERVICE_UNAVAILABLE/IPC/BMS/UNSUPPORTED 等类）→ 会话内存（不落盘、重启丢失、设置页展示 backend 状态）；明文 preferences 存凭据被红线禁止，不采用。日志全程只输出 cookie 键名不输出值。验证：本地单测 NeteaseAuth 7 用例全绿（sanitize 双路径/往返/损坏/健康/粘贴解析/头构建/错误分类）；entry@default+ohosTest 构建 BUILD SUCCESSFUL；codelinter 0 error（新文件零缺陷）；模拟器（Pura 90 API 24）ActsCredentialStoreTest 3/3（**asset 后端在模拟器可用且实证持久化**：put→get→remove 往返、backendName='asset'）、ActsNeteaseCookieRepositoryTest 2/2（粘贴导入含 MUSIC_U 保存+持久化+清除；缺 MUSIC_U 拒绝）；全套 ohosTest 14/14。
- [x] M4.2 网易云 QR 登录：`/weapi/login/qrcode/unikey` 创建 + 轮询 check（对齐 `NeteaseQrLoginClient`）；二维码渲染用纯 ArkTS QR 生成器（自写 ~200 行，避免第三方依赖）；cookie 入 asset+HttpClient 种子（MUSIC_U）；登录后 `getSongUrl` 携带 MUSIC_U 重试（缓解 weapi 风控，PORTING.md 待办 1）。UI：SettingsDetailPage 账号区（占位在 `:321-339`）。
  - 证据：①`util/QrEncoder.ets`（~600 行纯 ArkTS，字节模式/ECC M/版本 1-10 上限 213 字节/8 掩码自动罚分选择）：开发期先以 Node 原型对照 segno 参考实现逐 bug 修复（生成多项式乘法方向、BCH 移位对齐、格式信息须先于数据放置、v1 无定位图案、定位图案中心表版本偏移、segno boost_error 默认升纠错级、整字节对齐时补 0x00、N3 边界语义、自动掩码须在格式信息未写入时评分），最终 **4 个字节级夹具（v1/v3/v9/v10，掩码 0/3/7/5，覆盖单/多块交织、8/16 位长度位、v≥7 版本信息块）+ 152 组合长度×掩码扫描 + 10 个自动掩码载荷全部与 segno 完全一致**；单测 QrEncoder 5 用例（夹具逐位/UTF-8 编码/容量边界 180-181-213-214/自动掩码结构/超限抛错）全绿。②`network/NeteaseQrLogin.ets`（对齐 Android：unikey/type=1+noCheckToken、check 带 key+ydDeviceToken('')+x-loginmethod/x-login-chain-id 头、803 后 jar cookie 经 /weapi/w/nuser/account/get 校验、x-refresh-token 头兜底种 MUSIC_U 再试、失败移除；scanlogin URL 拼 codekey/chainId/hdw_device/hdw_appid/hitExp）；HttpClient 扩展 postFormDetailed（返回响应头文本）+removeCookie/clearCookies。③UI：SettingsDetailPage 账号区真实接线（Canvas 绘制 QR+2s 轮询状态机 801/802/803/800 自动刷新+取消/登出 AlertDialog；粘贴 Cookie 导入 CustomDialog 备用路径（模拟器无摄像头可走此路）；aboutToDisappear 清定时器）。④取流：doEnsureSession 先种持久化 cookie 再访问首页拿 __csrf（顺带删除原全量 cookie 日志输出）；requestSongUrl 301+已登录→resetSession 重试一次（对齐 getSongDownloadUrl 语义）。⑤EntryAbility onCreate 接 NeteaseCookieRepository.init()。验证：entry@default/ohosTest 构建 BUILD SUCCESSFUL；本地单测全绿（42 存量+12 新增=54）；模拟器 ActsNeteaseQrLoginTest 1/1（**真网**：createSession 返回 scanlogin URL 含 unikey，fresh check=801 等待扫码）；全套 ohosTest 14/14；主应用冷启动存活。**未自动化项（如实记录）**：真机扫码确认（803→cookie 落库→高音质取流）需真机+网易云 App，未执行；weapi 搜索风控（50000005）在登录后的缓解效果待真机验证。
  - 证据（2026-08-17 bugfix，扫码授权后「登录校验失败，请重试」）：用户模拟器真网实测——手机扫码+授权后 803 已确认，但 cookie 校验失败。根因：HarmonyOS `HttpResponse.header` 为对象且 `set-cookie` 值是数组（社区实证：https://zhuanlan.zhihu.com/p/1903807665301453），旧实现 `JSON.stringify` 后正则 `/set-cookie:/` 因键名与冒号间隔引号永不相符，MUSIC_U 从未入 jar；`x-refresh-token` 兜底正则同因失效。修复：新增纯逻辑 `network/HttpHeaderParser.ets`（`toHeaderText` 把对象/数组/原始字符串统一归一为 `Key: value` CRLF 行；`extractCookiePairs` 支持逗号合并值拆分、丢弃 Expires 日期碎片与 Path/Domain/Max-Age 等属性名、重名取后值）；HttpClient 的 getText/postForm/postFormDetailed 响应头统一走归一化，captureCookies 弃用正则改调 extractCookiePairs，`NeteaseQrLogin.readRefreshToken` 在归一化文本上自然恢复。验证：deveco-mcp check 4 文件 0 诊断；本地单测 101/101（新增 HttpHeaderParser 6 用例覆盖对象+数组、原始文本、逗号合并、Expires 碎片、重名、x-refresh-token 契约）；`hvigorw assembleHap`（CLT 6.1.1.300）BUILD SUCCESSFUL。**未验证项（如实记录）**：修复后完整扫码 803→cookie 落库→登录态取流需用户带网易云 App 的手机在模拟器复测。
- [x] M4.3 网易云登录态收益：用户歌单列表+导入、每日推荐（按 `NeteaseClient` 端点清单逐个补）；`np.netease_logged` 键真实写点。
  - 证据：2026-08-17 新增 `network/NeteasePlaylistParser.ets`（纯解析器：`/weapi/user/playlist`→playlist[]/coverImgUrl、`/weapi/personalized/playlist`→result[]/picUrl/截 30 条、`/weapi/w/nuser/account/get`→profile.userId，http 封面升级 https、非法条目过滤、code=301/50000005 匿名回退判定，字段名核对自 Android `NeteaseClient`/`HomeViewModel.parseRecommend`）；NeteaseApi 扩展 getRecommendedPlaylists（登录态命中风控码→临时摘除 MUSIC_U 匿名重试→恢复 jar，对齐 Android usePersistedCookies=false 语义）、getCurrentUserId（uid 内存缓存按登录态失效，避免 logout/relogin 串号）、getUserPlaylists（301 登录态刷新重试）、getPlaylistOverview（v6 详情+name/cover/trackCount，trackIds>200 走 v3/song/detail 补齐）。UI：新页面 `NeteasePlaylistPage`（路由 `netease_playlist`：封面/全量播放/随机/批量导入对话框，导入上限 500 首防 preferences 超长）+ LocalPlaylistRepository 新增 `createPlaylistWithSongs`/`importSongs`（纯函数 `mergePlaylistSongs` 按 stableKey 去重保序、单次落盘，Playlist 模型内）+ 首页「每日推荐」横滑封面区（失败静默隐藏，原图改名「我的歌单」）+ 资料库「网易云歌单」区（登录后自动拉取/手动刷新/错误重试，未登录跳设置账号区）。`np.netease_logged` 写点 M4.1 已完成（NeteaseCookieRepository doInit/saveInternal/clear）。验证：本地单测全绿（新增 NeteasePlaylistParser 7 + PlaylistMerge 3，覆盖率报告确认解析器 7/7 函数执行）；entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 0 error（21 warn+1 suggestion，新增 3 warn 为新页面 @State 临时变量 stylistic 规则，与存量页面同规则）；模拟器（Pura 90 API 24，先 wakeup+setmode 602）ActsNeteaseLibraryTest 3/3（**真网**：推荐歌单 weapi 全链（加密→会话→解析）返回有效条目、匿名 account/get 拒绝语义（实证返回 code=200+profile:null，与 Android「未找到 userId」同分支，测试断言已按实证修正）、v6 歌单 Overview 含曲目）；全套 ohosTest 17/17；主应用冷启动 smoke + 截图确认首页「每日推荐」区 3 张真网封面正常渲染。**未验证项（如实记录）**：登录态下用户歌单列表真机实测（模拟器无网易云 App 无法扫码，粘贴 cookie 导入路径可人工验证未自动化）；weapi 风控 50000005 匿名回退路径仅单测覆盖。
  - 证据（2026-08-17 bugfix，登录后歌单详情歌曲无封面）：用户扫码登录后实测反馈——首页推荐封面正常，进入私人雷达等歌单详情后歌曲列表均无封面（占位符）。根因：网易云端点字段形状不一致——`/weapi/cloudsearch` 曲目用全称 `artists`/`album`/`duration`，而 `/api/v6/playlist/detail`（及 `/api/v3/song/detail`）用缩写 `ar`/`al`/`dt`（curl 实证），旧 `toSongItem` 只读全称形状致歌单详情歌手/专辑/封面全空（M4.3 之前该路径无调用者，缺陷潜伏）。修复：歌曲映射提取为纯函数 `neteaseSongToSongItem`（双形状适配、`picStr` 兜底、封面 http→https 升级）入 `NeteasePlaylistParser.ets`，NeteaseApi.toSongItem 委托并删除本地重复接口/死代码。验证：新增单测 4 用例（v6 缩写形状/cloudsearch 全称形状/多歌手 join+picStr/缺专辑兜底），映射函数 8/8 覆盖；设备测试强化断言（Overview 歌曲至少一首 https 封面——此断言本可拦截该 bug）；本地单测+双模块构建+codelinter 基线持平（0 error）；模拟器全套 ohosTest 17/17；UI 实证（uitest 点击首页推荐卡进详情，布局转储确认歌曲行 10 个 Image 节点、0 个 ♫ 占位符）。
- [x] M4.4 B 站 QR 登录：`/x/passport-login/web/qrcode/*`（对齐 `BiliQrLoginClient`）；buvid3 种子 cookie；登录后收藏夹浏览（`BiliClient` 收藏夹分页端点）。D6 决定是否补 WBI。
  - 证据：2026-08-17 ①`network/BiliQrLogin.ets`（对齐 Android：generate/poll 均 GET+Chrome/124 Windows UA+passport Referer、顶层 code!=0 抛错、业务码 data.code（86101/86090/0/86038）、成功时 passport 域被动累积的 Set-Cookie 全量快照；无单独 buvid 种子端点，与 Android 一致）。②`data/auth/BiliAuth.ets` 纯逻辑（登录判定仅 SESSDATA 非空、无过期语义、bundle toJson/fromJson 往返空 key 剔除、sanitize 复用抽取的 `data/auth/RawCookieTextParser.ets`（对齐 Android common 包，NeteaseAuth 改 re-export））+ `BiliCookieRepository.ets`（alias `bili_auth_bundle` 对齐 Android 加密 prefs 键名、seed 双 host（api+passport）、`np.bilibili_logged` 三写点、getMid=DedeUserID）。③buvid 种子：BiliApi.ensureRequestCookies——未登录时 GET `/x/frontend/finger/spi` 种 buvid3/buvid4/buvid_fp/b_lsid（内存 TTL 1h，失败静默降级无 cookie，对齐 getEffectiveCookies）；search/resolveAudioUrl 全部带 cookie jar。④收藏夹：`network/BiliFavParser.ets` 纯解析器（list-all title/name、media_count/total 回落、cover https 升级、bvid/bv_id 兜底、mediaId=0/空标题过滤、业务码不抛错→空结果）+ BiliApi.getUserFavFolders（list-all+count>size 分页兜底）/getFavFolderPage（fav/resource/list pn/ps=20/order=mtime/platform=web）/getAllFavFolderItems（has_more+count 终止、type:id:bvid 去重、失败页跳过）。D6：收藏夹端点均无 WBI，维持不移植。⑤UI：抽取共享组件 `view/components/QrLoginPanel.ets`（QR 绘制+轮询状态机+过期自动刷新+controller 命令式开关，平台差异经 createSession/pollSession 回调与归一化 QrPollOutcome 注入，token 字段携带网易 chainId），网易面板换用组件（行为等价），B 站平行接入 SettingsDetailPage（轮询 1500ms 对齐 Android、粘贴 Cookie 导入 CustomDialog 参数化、登出二次确认）；新页面 `BiliFavPage`（路由 `bili_fav`：info 头+分页列表 onReachEnd 加载更多+全量播放/随机/导入本地歌单 cap 500）+ LibraryPage「B 站收藏夹」区与平台区登录态。EntryAbility onCreate 接 BiliCookieRepository.init()。验证：本地单测 127/127 全绿（新增 BiliAuth 12+BiliFavParser 10）；entry@default/entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 0 error（24 warn+1 suggestion，新增 4 条为 BiliFavPage @State 临时变量与 LibraryPage 组件规则 stylistic warn，与 M4.3 时 NeteasePlaylistPage 同规则同性质）；模拟器（Pura 90 API 24，wakeup+setmode 602）全套 ohosTest 20/20（**真网**：ActsBiliQrLoginTest createSession 返回 passport 扫码 URL 含 key、fresh poll=86101 等待；ActsBiliCookieRepositoryTest 粘贴含 SESSDATA 保存→asset 持久化→getMid→clear、缺 SESSDATA 拒绝）；主应用冷启动 smoke 无 crash。**未自动化项（如实记录）**：真机扫码确认（0→SESSDATA 落库→收藏夹真实数据）需真机+哔哩哔哩 App；登录后收藏夹列表真网数据未拉取（模拟器无 B 站账号，粘贴导入路径已由 ohosTest 覆盖同链路）。
- [x] M4.5 验收：模拟器完成扫码登录（备用路径：DebugPage 粘贴 cookie 导入）→高音质完整曲目播放→重启会话保持→注销清理；ohosTest 覆盖 cookie 仓库持久化（对齐 `NeteaseCookieRepositoryAndroidTest` 语义）。
  - 证据：2026-08-17 ohosTest cookie 仓库持久化对齐达成（ActsBiliCookieRepositoryTest 语义=Android BiliCookieRepositoryAndroidTest：saveCookies→重建可读→clear 清除；ActsNeteaseCookieRepositoryTest 同语义已有）；粘贴 Cookie 导入路径实测可用（含 SESSDATA 保存+持久化，未含则拒绝）；重启会话保持由 EntryAbility init 恢复链路+冷启动 smoke 保障（未登录态无 bili auth restored 日志为预期）。全套设备测试 20/20（M4.1~M4.4 全回归）。**未执行项（如实记录）**：模拟器扫码登录闭环（0→落库→高音质取流）需用户手机哔哩哔哩 App 扫码，模拟器无摄像头与 B 站客户端，留待用户真机验证；登录态 B 站 playurl 高音质收益（杜比/Hi-Res 音轨下发）随之待复核。
- [x] M4.7 用户二轮反馈三 bug 修复 + 匿名 buvid 软拒绝根因（2026-08-18）：
  - **①歌词页切不进**：`NowPlayingPage:182` 的 `lyrics.length > 0` 硬门控使无词歌曲（B 站/LOCAL）永远停在封面视图。修复：gate 放开为 `showLyrics`，LyricView 自带「暂无歌词」空态兜底（对齐 Android「B 站暂无歌词源」语义，Explore 证实 Android B 站歌曲也不查任何远程歌词库）；连带 `LyricView.lyrics` 从普通成员改 @Prop（否则空数组先挂载后异步填充不刷新，也修了换歌歌词不更新的同源问题）。
  - **②播放/暂停图标不随状态变化**：`PlayerControlButton.icon/active/buttonSize` 是普通成员（无装饰器），父组件状态变化不触发子组件重渲染（MiniPlayer 内联 Image 无此问题）。修复：三者 @Prop 化；另 `PlayerManager.play()/pause()` 成功后同步 `publishStatus`（原来完全依赖 AVPlayer 异步 stateChange 事件回写）。UI 实证：uitest 点击播放页大按钮与 MiniPlayer 按钮，像素形状分析确认 pause↔play 双向切换（截图直方图两两吻合）。
  - **③播放卡带（片段重复）**：音轨盲选最大 bandwidth（无损 ~1Mbps）在慢网络 buffer underrun。修复：移植 Android `BiliAudioSelector` 语义为 `network/BiliAudioSelector.ets` 纯逻辑（np.audio_quality→带宽带映射 standard=LOW[60,120)/high=MEDIUM[120,180)/exhigh=HIGH[180,500)/lossless/hires，带内取最高、空带降级、链尽回退最高；upos-* bilivideo CDN 主机优先重排 primary+backup URL），resolveAudioUrl 接入，7 单测对齐 Android BiliAudioSelectorTest 语义（开发中修正两处：ArkTS 禁匿名对象字面量、测试断言与带内取高语义对齐）。
  - **④附带根因发现（WBI 搜索软拒绝）**：验证③时 B 站播放 smoke 隔离冷启动 3 连败（`code=0 results=0`），Host Python 矩阵实验实锤：**任何带 `/x/frontend/finger/spi` 新鲜匿名 buvid 的 WBI 搜索一律返回 code 0+空结果（软拒绝），无 cookie 反而正常**（排除时钟偏差/关键词因素）——M4.4 引入的匿名 buvid 种子在当前风控下反效果（此前「全套跑偶过」实为该轮 spi 请求失败裸发）。修复：移除匿名种子逻辑（ensureRequestCookies/spi 解析/TTL 全删），匿名请求保持无 cookie，登录态仍带 SESSDATA；search 保留一次 600ms 延迟重试兼容偶发抖动。验证：隔离冷启动 3/3、全套 ohosTest 21/21、本地单测 147/147（新增 BiliAudioSelector 7）。
  - 未验证项：歌词页 UI 切换人工核验（gate/@Prop 逻辑+构建保障，留用户手测）；卡带改善程度依赖真机网络（降带宽+upos 优先为机理修复）。
- [x] M4.6 B 站取流修复（用户实测暴露，D6 触发执行）：登录后收藏夹音乐无法播放。根因双重：① 2024 风控收紧后无 WBI 签名的 `search/type` 返回 HTML、`playurl` 一律 -400（Host curl 实证）；② bilivideo CDN 要求流请求带 `Referer`，AVPlayer 裸播 403（Host 实证：完整 URL+Referer 200、无 Referer 403、UA 无关）。
  - 证据：2026-08-18 ①WBI 签名移植 `network/BiliWbi.ets` 纯逻辑（RFC1321 md5 自实现、64 位混淆表、mixinKey 推导、`!'()*` 过滤、wts 参与排序、w_rid=md5(query+mixinKey)；fixture 双源：bilibili-API-collect 官方示例（img/sub key→mixin `ea1db124...4ff8`、{foo,bar,zab} wts=1702204169→w_rid `8f6f2b5b...`）+ Host Python 独立实现交叉生成的中文搜索/PLAYURL 形状，8 用例字节级全对；开发中还暴露 wts 未参与排序的真 bug 由官方 fixture 拦截）。②BiliApi：nav mixinKey 缓存 10min+in-flight 去重（Android WebTicket 兜底未移植，nav 稳定）；search 改 `wbi/search/type` 签名；resolveAudioUrl 改两步 `wbi/view`(→cid)+`wbi/playurl`（bvid+cid+fnval=272+platform=pc，对齐 Android getPlayInfoByBvid；Host 实证 cid 缺失或仅有 cid 均 -400）；code!=0 抛可诊断错误。③播放头 `network/StreamHeaders.ets`（对齐 Android ConditionalHttpDataSourceFactory.buildBiliHeaders：bilivideo/mountaintoys 域名→强制 Referer+Chrome/124 UA+登录 Cookie；isBiliStreamUrl 标签级匹配防 notbilivideo.com 误命中）+ PlayerManager.loadSong 经 createMediaSourceWithUrl(url, headers) 注入。④新增 ohosTest ActsBiliPlaybackSmokeTest（真网搜索→cid→playurl→AVPlayer 带 headers prepared→playing→paused，填补 B 站 URL 播放从未实测的洞）。验证：本地单测 140/140；双模块构建通过；模拟器全套 ohosTest 21/21（首轮 B 站搜索一次偶发空结果，隔离+全套重跑均过，flaky 如实记录）；主应用冷启动无 crash。**未做项（如实记录）**：D6 提到的 DebugPage B 站探针未加；Android WebTicket 兜底与 dolby/flac 音轨组映射未移植（dash.audio 主轨链路已通）；首轮 flaky 成因（首调时序竞态假说）未深挖。

### M5 同步（战略计划阶段 5 后半）

- [x] M5.1 纯合并策略族移植 `sync/`：`SyncPlaylistSongMergePolicy`、`SyncSongMetadataMergePolicy`、`SyncPlaybackStatsMergePolicy`、`SyncPlaylistDeletionPolicy`、`SyncDataChangeDetector`、`SyncCausalToken`——全部纯逻辑+单测（Android fixture 对齐）；D1 线格式决策落地（最小 protobuf wire 读写器 + 字节级 fixture 测试，或 JSON v2+迁移记录）。
  - 证据：2026-08-18 新增 `entry/src/main/ets/sync/` 六文件（零 @ohos 依赖，deveco-mcp check 全部 0 诊断）：①`SyncModels.ets`——全量同步数据模型（SyncData tag 顺序对齐 Android @ProtoNumber 布局：SyncData 13 字段/SyncSong 29 字段/SyncFavoritePlaylist/SyncTrackStat/SyncPlaybackStatBucket(+dayStartAt)/SyncPlaylistSongDeletion 等）+ `SyncCausalToken` 归一化（filter invalid→distinct→(deviceId,counter) 排序）+ `SongIdentityKey`（id 用规范十进制字符串避开 JS number 2^53 精度丢失；mediaUri 保留 null≠'' 语义而 stableKey() 折叠 null→''，逐字段对齐 Android data class）+ `syncSongIdentity()`（完整移植 SyncSong.identity()：YTM mediaUri 前缀归一化、channel/audio/subAudio 通道归一化、netease 数字直通）+ 纯 ArkTS SHA-256（FIPS 向量验证）与 `stableSyncId()`（**修正跨端缺陷**：Android `stableYouTubeMusicId`=SHA-256 前 8 字节大端有符号 int64（BigInt 实现，0→1），鸿蒙既有 `hashStableId` FNV-1a 与之不兼容——同步互通的 YTM/B 站通道 stableKey 由此对齐；模型层 SongItem.id 的存量 FNV 键不迁移，同步域内自洽）+ `normalizeCounterShards`（清数→(deviceId,epoch) 分组 reduce→排序，聚合语义对齐）。②`SongMetadataMergePolicy.ets`——canonicalPayloadKey 27 字段长度前缀拼接（`len:value` 无分隔符，`9:Old Album`>`10:New Album` 关键案例测试锁定）、selectDeterministicPayload（版本高者胜/平局 canonical key 大者胜，maxWith 取第一个最大元素对齐 Kotlin）、current payload 权威（显式清空不回填）、legacy 字段回填。③`PlaylistSongMergePolicy.ets`——六分支两路合并（含 `>=`/`>` 不对称平局偏 local、isUpdated=与 local 差异、收藏首同步取 remote）+ 四级匹配键（membershipToken→identity→channelAudio→fallback(id+规范化名/艺名, sourceHint 分桶 unknown 通配)）+ SongMergeAccumulator（tokens 归一化并集、payload 确定性/主方原子、alias 桥接合并、索引重建）+ 桥接排列不变性。④`PlaylistDeletionPolicy.ets`——墓碑合并（legacy 取 deletedAt/deviceId 最大、causal token 并集）、limitDeletions 容量分配（legacy 先得 maxCount/2，剩余先补 legacy 再补 causal）、applyDeletions（**设备验证前单测拦截的真 bug 已修**：分组键曾误用带 `playlistId|` 前缀的 stableKey 导致 legacy 墓碑永不匹配，改为 `identity().stableKey()` 对齐 Android；causal token 全局集剔除、无 token 歌走 effectiveAddedAt(legacyAddedAt?:addedAt)>deletedAt）、pruneResolvedDeletions（P1-1：仅带 token 的重添可裁 legacy 墓碑）、mergeFavoritePlaylists（同时间戳删除方赢/并集/max）。⑤`PlaybackStatsMergePolicy.ets`——纯 max/union 收敛合并、shard 化计数（base=max(退化为 total 当无 shard)+Σshards 不双计 legacy）、clear 屏障（丢旧/重置 firstPlayedAt/清 base）、trimStats/trimBuckets（锚点=数据集 max dayStartAt 非墙钟）、finalizeMergedStats 先 lift 未裁剪桶再 trim（顺序与桌面逐字一致）。⑥`DataChangeDetector.ets`——位置敏感逐项比较（identity 序列、25 标量字段、tokens 集合相等、统计 key 集+sameMetadata），决定是否上传。单测 6 文件 107 用例（对齐 Android `SyncPlaylistSongMergePolicyTest` 38/`SyncPlaybackStatsMergePolicyTest` 21/`SyncPlaylistDeletionPolicyTest` 24/`SyncCausalTokenTest` 3/`SyncTimestampMergePolicyTest`/`SyncPlaylistObservedRemoveIntegrationTest` 的 fixture 数值与断言语义，含 ObservedRemove 集成：新 token 免疫旧墓碑）。验证：本地单测 `hvigorw test` **234/234 全绿**（127 存量+107 新增）；entry@default 构建 BUILD SUCCESSFUL；codelinter 0 error（24 warn+1 suggestion 与基线持平，新增 sync/ 六文件零缺陷）。D1 决策已按调研修正落地（§5 表：Android 双格式 JSON 默认+GZIP(protobuf) 省流，M5.2 实现 JSON 互通+protobuf wire 补齐）。**未做（属 M5.2）**：SyncDataSerializer 序列化/快照构建、normalizedForDisplayOrder 迁移（对应 Android 两个 legacy 迁移测试随 M5.2 补）。
- [x] M5.2 序列化与快照：`SyncDataSerializer` 语义（版本字段、向后兼容读）；快照构建（歌单/历史/统计/设置的导出模型）。
  - 证据：2026-08-18 新增四文件（deveco-mcp check 0 诊断）：①`sync/SyncDataJsonCodec.ets`——Android kotlinx JSON 语义手写复刻（encodeDefaults=true 全字段写出/explicitNulls=false null 省略/ignoreUnknownKeys/coerce 枚举回退）+ **自写递归下降 JSON parser（~200 行）解决 int64 精度保真**：超出 2^53 的整数字面量保留原始十进制文本（JsonValue string），SyncSong/SyncPlaylistSongDeletion/SyncRecentPlayDeletion 增设 wire 层 `syncIdText` 字段存原文（YTM/B 站 SHA-256 id 不丢精度，stableKey/canonicalPayloadKey/再序列化全部经 songIdKeyText 走原文，M5.1 六文件同步适配）；读路径三格式识别（GZIP 魔数→proto、BOM/空白后 `{`→JSON、其余→legacy Base64）+ 顶层集合字段类型严格校验（对齐 kotlinx：非数组即解码失败）+ 大小上限（JSON 8MiB/压缩 12MiB/解压 16MiB）+ 文件名决策（backup.json/backup-raw.bin/backup.bin 与 getReadFallbackFileNames）+ 纯 ArkTS UTF-8 编解码（无 @ohos.util 依赖，本地单测可跑）。②`sync/SyncSongConvert.ets`——SyncSong.fromSongItem/toSongItem（''↔null 转换、本地歌过滤 isLocalSongItem=platform LOCAL/localFilePath/本地 URI scheme、sanitizeMediaUriForSync、platform 推断）+ Playlist↔SyncPlaylist（鸿蒙 `local_<ts>` 字符串 id ↔ 数值：剥前缀/纯数字直通/其余 FNV 哈希兜底；createdAt=id 对齐 Android）+ **normalizedForDisplayOrder**（已删歌单清空+DISPLAY 版；display 版 addedAt 降序稳定排序；legacy 迁移锚点=歌单 modifiedAt 非墙钟、倒序合成 addedAt≥1、legacyAddedAt 保留原值——M5.1 遗留的两个 Android P1-1 回归测试语义补齐）。③`sync/SyncSnapshotBuilder.ets`——buildLocalSyncData 注入式纯函数（对齐 GitHubSyncManager.buildLocalSyncData：歌单保仓库序+缺失墓碑补 isDeleted、recentPlays 排除本地歌后截 500、墓碑 mediaUri 消毒+token 归一、统计 counterBase=max(0,total−Σshards) 且先归一化再算底（对齐 Android snapshot()→mapper 调用链）、syncLog 恒空、deviceId/deviceName/lastModified 注入）+ localDayStartAt（本地时区日零点，对齐 Calendar 语义非 UTC floor）。④`sync/SyncDeletionStore.ets`——SecureTokenStorage 子集：墓碑状态 SchemaStore 版本化持久化（toJsonText/fromJsonText 经精度保真 parser）+ normalizeRecentPlayDeletions（groupBy stableKey→(deletedAt,deviceId) 最大→降序→500 截断）+ getOrCreateDeviceId（注入生成器，非凭据走 preferences 并记录理由）。测试 4 文件 39 用例（codec 14：转义/大整数/损坏拒绝/roundtrip 经 hasDataChanged 验证等价/默认写出与 null 省略/未知字段/格式嗅探/文件名；convert 13：字段映射/平台推断/displayOrder 含 P1-1 两回归；builder 6：墓碑补位/500 截断/counterBase/本地日零点；deletionStore 6：归一化/roundtrip/大 id）。验证：本地单测 **273/273 全绿**（234 存量+39 新增，中途修复 4 处：严格集合类型/先归一后算底/两测试构造/一断言语义笔误）；entry@default 构建 BUILD SUCCESSFUL；codelinter 0 error（24 warn+1 suggestion 基线持平，sync/ 零贡献）。**未做（显式登记为 M5.2b）**：GZIP(proto) 与 legacy Base64 分支的实际解码器（protobuf wire varint 读写 + gzip inflate，当前 deserializeSyncContent 已识别格式但返回「not available yet」，D1 决策修正案中为补齐项）；仓库真实数据源接线（含 HistoryRepository 增强 playedAt/resumePositionMs、PlaybackStatsRepository 对齐 TrackStat 元数据与 identityKey 迁移）留 M5.5 协调器接线时一并处理。
- [x] M5.2b（后续子任务）protobuf wire 读取 + gzip inflate：手写 protobuf varint/length-delimited 解码器（schema 已在 M5.1/M5.2 调研全量记录：SyncData tag1-13、SyncSong tag1-30 含 64 位 id BigInt 保真）+ gzip 解压（调研 @ohos.zlib 能力边界或 ohpm pako，本地单测环境需纯 ArkTS 方案），补齐 backup-raw.bin/backup.bin 读取；字节级 fixture 用 Android SyncDataSerializerBinaryStreamTest 语义构造。
  - 证据：2026-08-19 新增三文件 + codec 接线，D1 决策补齐项全部落地。①`sync/GzipInflate.ets`（~470 行纯 ArkTS）：RFC1951 解压（stored/fixed/dynamic 块、puff 式 canonical Huffman counts+sorted symbols 解码、LZ77 重叠回拷、输出上限强制 16MiB）+ RFC1952 容器（FLG 可选字段解析、多 member 拼接、CRC32+ISIZE 双校验、尾部全零 padding 容忍、损坏返回 null 不抛）。**不采用 @ohos.zlib**：本地 hypium 单测环境无 @ohos API（M5.2 已实证），统一纯实现避免设备/测试双实现分叉。②`sync/ProtobufWire.ets`：varint（BigInt 读出、10 字节上限、两补码负数）、length-delimited 零拷贝视图、未知字段按 wire type 跳过（含 group 防御）、int64→(number,text) 分流 helpers（对齐 JSON codec 的 2^53 精确/十进制文本语义）、UTF-8 容错解码（非法序列替换字符，对齐 Kotlin String(UTF_8)）。③`sync/SyncDataProtoCodec.ets`：两阶段解码——RawFields.parse 按每消息 varint/LEN 字段号集合做**严格 wire-type 校验**（不匹配→整体 null，这正是 Android 端触发 Legacy 回退的机制：Legacy SyncSong tag8=varint addedAt 撞当前 tag8=string mediaUri）+ 类型化映射；当前 schema 12 个消息全量（SyncData tag1-13 至 SyncCausalToken，lastModified 缺省注入 nowMs 对齐 kotlinx 默认 System.currentTimeMillis()、enum 序数越界拒绝、token 归一化对齐 JSON codec 行为）+ Legacy schema 兜底（8 字段布局 + toCurrent 映射：mediaUri/channelId 等置 null、favorite modifiedAt=sortOrder=addedTime、resumePositionMs=0）。④`SyncDataJsonCodec.deserializeSyncContent` 两个「not available yet」占位替换为真实现（gzip→inflate≤16MiB→proto 双 schema 回退；文本→decodeLegacyBase64Text：strip ASCII 空白、非空、%4、字符集、'=' 仅限尾部 1-2 位——逐项对齐 Android decodeLegacyBase64/java.util.Base64 严格校验）。测试 `SyncBinaryCodec.test.ets` 11 用例，**fixture 全部由独立参考实现生成**（Node 手写 protobuf 编码器模拟 kotlinx encodeDefaults=false 语义产出 926B 当前 schema/369B legacy schema/未知字段字节；Node zlib 三种 deflate 变体（dynamic/stored/Z_FIXED）+ 双 member；jbr 21 真实 java.util.zip.GZIPOutputStream 字节（非零 MTIME/OS 头部变体）；生成脚本在仓外 D:\HarmonyOS\tmp-m52b\），断言语义对齐 Android SyncDataSerializerBinaryStreamTest（gzip 魔数、legacy base64 read-both、截断/空/坏 CRC 失败、'H4sI!invalid' 拒绝）+ 全字段值校验（含超 2^53 大 id 的 number+text 双断言、负数 10 字节 varint、负 id 精确、emoji 字符串）。**过程修复 4 个实现 bug**（strOf 对 sub-reader 双重读取 length 前缀致字符串错位、base64 padding 字符被误判非法、inflate consumed 返回绝对位置致 trailer 定位越界（CRC/ISIZE 读 0）、SyncPlaybackStatBucket field5=album 误归 varint 集合致 wire-type 冲突整体 null）与 2 处 fixture 手抄笔误（hex/base64 各一处——已改为脚本注入，教训：长 fixture 禁止手工复制）。验证：本地单测 **284/284 全绿**（273 存量+11 新增）；entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 与基线完全持平（24 warn+1 suggestion，0 error，sync/ 新文件零缺陷）；deveco-mcp check 全部 0 诊断。**未做（如实登记）**：省流格式**写出**（proto encode+gzip deflate）不在本任务范围，留 M5.3 传输需要时实现（届时鸿蒙端省流上传可先降级写 JSON，读路径已三格式全兼容）；真实 Android 端备份文件端到端互通验证（无 Android 产物可跑，兼容性由独立参考实现的字节级 fixture + 真实 Java gzip 字节保障）。
- [x] M5.3 GitHub 传输 `sync/github/`：Contents API——createBinaryBlob/createSyncFileTree/commit（对齐 `GitHubRepositorySyncTransport`）；PAT 存 asset（对齐 `SecureTokenStorage` 键名 github_token/repo/device_id）；401/限流错误分类；UI 配置页+手动同步按钮。
  - 证据：2026-08-19 新增 `sync/github/` 五文件+`util/Base64.ets`。①传输层 `GitHubTransport.ets`（纯 ArkTS、注入式 GhExecutor）：对齐 Android——读走 Contents raw（404→文件不存在、MAX_SYNC_FILE_BYTES 12MiB 双保险）；上传走 Git Data API 流水线 getCommitTree→createBinaryBlob（base64 信封）→createSyncFileTree（base_tree+100644）→createSyncFileCommit（parents 乐观锁基线）→updateBranchRef（PATCH /git/refs/heads force:false，409/422+"reference"→CONTENT_CONFLICT，对齐 throwForResponse）；另有 validateToken(/user→login)、getRepoInfo（default_branch ifBlank→main）、createRepository（private+auto_init+description 对齐）、getBranchHead。**平台决策（doc-researcher 调研定案）**：`@ohos.net.http` RequestMethod 枚举无 PATCH（API 24 d.ts 实证），但官方 `customMethod` 字段（@since 23，本机 d.ts:576；netstack 源码映射 CURLOPT_CUSTOMREQUEST 实证）可发真 PATCH——曾实现 temp-ref+merges 变通后被调研实证否决（merges 总创建 merge commit 且无 fast-forward 校验、乐观锁语义丢失，私有仓库逐 case 实测），定案改回 Android 原版 PATCH ref 方案（语义 100% 对齐）。②`GitHubSyncClient.ets`：fetchRemoteSnapshot（preferred→fallback 文件名序列去重、404→null 首同步标记、空文件→失败（github_backup_file_invalid）、非 404 错误立即中止不回退（对齐 Android P1-4））+ uploadBackup（message 恒 "Update backup data"、默认分支）。③`GitHubErrors.ets`：401→TOKEN_EXPIRED、404 按上下文 FILE_NOT_FOUND/REPO_NOT_FOUND、冲突判定、**本端口增补**（Android 无）限流分类 403+X-RateLimit-Remaining=0（reset epoch 差值）或 429+Retry-After→RATE_LIMITED 带 retryAfterMs、NETWORK、API；错误消息体 {"message"} 提取+240 截断。④`GitHubConfigRepository.ets`：token→asset alias `github_token`（键名对齐 Android）、owner/repo/省流→设置键 np.github_*（非机密走 preferences 的分层依据：项目红线只要求凭据走 asset，deviceId 复用 SyncDeletionStore sync_device_id）、lastRemoteSha/lastSyncTime 运行态键、clear 保留 deviceId；省流默认 **false**（M5.2b 记录：省流写出未实现，上传 JSON，读三格式兼容；Android 默认 true 的差异已在 UI 文案注明）。⑤`OhosGhExecutor.ets`（唯一 @ohos 依赖文件）：customMethod PATCH+expectDataType ARRAY_BUFFER+PATCH 时 method=POST 保证 body 上传（netstack body 非空走 POSTFIELDS 实证）。⑥UI：SettingsDetailPage 同步区 GitHub 卡片（配置 CustomDialog：token/owner/repo+名字白名单校验防 URL 注入、测试连接（validateToken+getRepoInfo）、创建备份仓库（already exists 友好提示）、检查远端备份（fetchRemoteSnapshot→deserializeSyncContent→摘要 toast：歌单/最近播放/统计数+更新时间）、省流开关、清除配置二次确认；busy 防重入；错误分类→中文文案映射）+ WebDAV/一起听占位保留。「手动同步」按钮按范围界定接为「检查远端备份」（传输层端到端真网验证入口），完整三路合并同步留 M5.5（快照数据源接线也在 M5.5，强做即偷跑）。EntryAbility onCreate 接 GitHubConfigRepository.init()。**单测拦截真 bug 1 个**：escapeJsonString 返回带引号完整字面量，拼接处手写外层引号产出 `""value""` 坏 JSON（真网必 400），三处修正。测试 2 文件 32 用例（fake 执行器倒序路由匹配——正序匹配会因 '/repos/o/r' includes 抢答子路径（首轮 10 失败的根因）：五步/七步流水线调用序与 body 逐字段断言、baseline 直传短路、404→null、空文件拒绝、非 404 中止、fallback 命中、oversize 拒绝、PATCH 409/422+reference→CONFLICT、错误分类 10 用例、base64 向量、名字白名单）。验证（2026-08-19）：本地单测 **316/316 全绿**（284 存量+32 新增）；entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 24 warn+1 suggestion 与基线持平 0 error（sync/github/ 零贡献）；模拟器（Pura 90 API 24，锁屏坑见 hm.md）全套 ohosTest **25/25**（存量 20 回归+新增 **ActsGitHubTransportTest 5/5 真网**：匿名公开读 repo info→branch head→raw README、backup.json 缺失→null、匿名与无效 Bearer /user→401→TOKEN_EXPIRED、**PATCH updateBranchRef 无效 token→401（实证 customMethod PATCH 请求行被 GitHub 认真接受，非 404/405）**）；主应用冷启动 smoke 无 crash（GitHubConfigRepository.init 无 token 静默）。**未自动化项（如实记录）**：带真 PAT 的写路径端到端（blob→tree→commit→PATCH ref 真提交、测试连接/创建仓库/远端检查 UI 流）需用户提供 PAT 人工验证（写路径逻辑由 fake 执行器单测覆盖+GitHub API 语义调研实证）；「立即同步」完整闭环属 M5.5。
- [x] M5.4 WebDAV 传输 `sync/webdav/`：PROPFIND/GET/PUT + ETag/Last-Modified 条件写；无条件 token 时用 SHA-256 指纹重新校验后才允许一次 PUT（对齐 `WebDavConcurrencyFallbackPolicy`）。
  - 证据：2026-08-19 新增 `sync/webdav/` 四个实现文件与 `WebDavTransport.test.ets`；覆盖 URL 规范化、Basic Auth、PROPFIND、强/弱 ETag、Last-Modified、404/认证/冲突/网络错误、12 MiB 上限及指纹回退。补充修复了协调器传入 `null` token 时绕过回退校验的路径，并以回归测试锁定。最终 `hvigorw test --mode module -p product=default -p buildMode=debug --no-daemon` **378/378 全绿**；`devecocli build --modules entry@default` 与 `entry@ohosTest` 均 BUILD SUCCESSFUL；CodeLinter 0 error（24 warn + 1 suggestion，与基线一致）。真实 WebDAV 服务写入仍需用户凭据验证。
- [x] M5.5 SyncCoordinator：互斥、三路合并执行、`.sync-pending` 消费（接 M2.4）、上传重试（对齐 `SyncUploadRetryExecutor`）；同步报告 UI（成功/冲突/失败明细）。
  - 证据：2026-08-19 新增 `SyncCoordinator`、`SyncMergeEngine`、`SyncBackends`、`SyncAppLocalStore`、`SyncService`、`SyncReport`、`SyncUploadRetryExecutor`；接入歌单/历史/统计/收藏快照、持久化因果 token、播放 counter shards、删除墓碑、apply journal 崩溃恢复、GitHub SHA/WebDAV 内容指纹运行态标记和 fallback 文件迁移上传；Settings 同步页接入 GitHub/WebDAV 报告弹窗。`SyncCoordinator.test.ets` 与 `SyncLocalMetadata.test.ets` 覆盖 fetch→冲突→refetch→remerge→upload→apply、同步期间本地修改、远端标记变化、fallback 迁移和本地元数据 round-trip。最终本地单测 **378/378 全绿**，主线与 ohosTest 构建成功，CodeLinter 无新增 error。双设备冲突验收及带真实 PAT/WebDAV 凭据的写路径仍未执行。
- [ ] M5.6 验收：模拟器实例 A 写→同步→构造远端冲突→实例 B 同步合并结果与 Android 策略测试一致；token 失效/断网路径明确报错；单测全绿。
  - 当前状态（2026-08-19）：纯逻辑、fake transport 和错误分类已有自动化覆盖；本机无活动设备，且未使用真实 GitHub PAT/WebDAV 凭据，因此双实例冲突和真实写入验收保持未完成。

### M6 YouTube 取流（研究驱动，D2 决策已于 M6.0 修正为 IOS 直连主路径）

> 2026-08-19 M6.0 后按 D2 修正案重排：M6.1 主路径 IOS 直连（无 JS 运行时）；solver 相关降级为 M6.3 可选兜底。

- [x] M6.0 spike：`tools_pub/ytmusic_api_probe.py` 跑通记录当前可用 client/格式（用户环境执行，输出存 docs）；同步调研 ArkWeb 执行外部 JS 的能力边界（runJavaScript 时序/离屏/生命周期），产出 D2 决策记录。
  - 证据：2026-08-19 探针实测（Windows 本机，Python 3.14+requests，经本地代理 7897——直连 YouTube 全域超时，大陆网络前提）：bootstrap 成功（webRemix 1.20260811.15.00/signatureTimestamp 20681）；4 个公开音乐视频 ×3 client 一致——**IOS 21.03.2 匿名直出无 cipher URL（Range GET 206 实证可下载，itag 251/140，URL 寿命约 6h）**、tvhtml5 7.x 完整版 URL 被剥离（0 直连 0 cipher，不可用）、tvhtml5_downgraded 5.x 全部 signatureCipher（需解签）；受限视频三 client 均 LOGIN_REQUIRED。Android 侧 Explore 调研：回退链 WEB_REMIX→TVHTML5→downgraded 无 IOS client 参与 player API，EJS solver 仅响应含 cipher/n 时触发，direct URL 本来优先——Android 需要 solver 纯因 client 链全为 web/tv 系。ArkWeb 调研（doc-researcher）：离屏 Web 官方方案可行（web-offline-mode/BuilderNode + onPageEnd 后 runJavaScriptExt，消息通道齐备）但单实例约 200MB+渲染进程常驻、后台定时器降频无官方保证；ArkTS 禁 eval；轻量正道为官方 JSVM（NAPI 封装）。D2 决策修正：**主路径 IOS 直连零 JS 依赖，方案 A 降级 M6.3 兜底**。产出 `docs/YTMUSIC_M60_SPIKE.md`（含重跑指引）。未执行：webpo/yt-dlp 下载探测（无 pydeps/登录 cookie，IOS URL 可下载性已由 curl Range 等价覆盖）、登录态 HAR 链路、模拟器网络复测（YouTube 大陆不可达，M6.5 验收需用户代理环境）。
- [ ] M6.1 主路径 IOS 直连取流（D2 修正案）：`network/ytm/` 拆分 YouTubeMusicApi 取流——IOS client 上下文（版本号集中管理）匿名回放 `youtubei/v1/player`、direct URL 优先（对齐 Android `resolveFormatUrl:932-983` 语义）、itag 251/140 音质映射（对齐 `np.audio_quality` 通道）、playability/错误分类（LOGIN_REQUIRED/受限/网络/解析）、URL 短缓存（6h 过期）；PlayerManager 接线替换 `YouTubeMusicApi.ets:171-177` 抛错占位。无 JS 运行时依赖。
- [ ] M6.2 取流健壮性：client 健康追踪（`PlayerClientHealthTracker` 语义：连续 3 败压制 30min）、IOS 失败→tvhtml5_downgraded 兜底（响应含 signatureCipher 时明确报错「需解签兜底未实现」，为 M6.3 留 seam）、IOS 版本漂移降级重试、年龄/地区限制形态错误分类；ohosTest 真网 smoke（需代理环境）。
- [ ] M6.3 solver 兜底链（可选增强，触发条件：M6.2 上线后 IOS 路径被风控/PoToken 收紧致兜底命中率显著）：`network/ytm/SolverRuntime.ets`——按 M6.0 调研结论实现离屏 Web（onControllerAttached 加载 $rawfile + onPageEnd 后 runJavaScriptExt，单实例、FAST_MODE 按需销毁；资产自 Android assets 复制，GPL 兼容）；signature/n 解算入队（对齐 `YouTubeJsSolveQueue`）。实施前复核当时 client 可用性（重跑探针）。
- [ ] M6.4 YouTube 登录（可选）：Web 组件 cookie 导出入 `data/auth/youtube/`（对齐 `YouTubeAuthRepository`/`YouTubeCookieRotator` 最小集）；天然仍需 Web 组件，与 D2 修正不冲突。
- [ ] M6.5 验收：模拟器实测 YTM 搜索→取流→播放；DebugPage YTM 探针；FEATURE_MATRIX YouTube 行状态更新。

### M7 一起听客户端（D7 外部依赖：服务端地址）

- [ ] M7.1 协议与纯逻辑 `listentogether/protocol/`：信封/事件/房间模型 + 校验（对齐 Android `protocol/`、`validation/`）+ 邀请链接解析；单测对齐 `listentogether/**` 10 个测试。
- [ ] M7.2 WebSocket 客户端：`@ohos.net.webSocket`（对齐 `ListenTogetherWebSocketClient` onOpen/onMessage/onClosed + `ListenTogetherReconnectPolicy` 指数退避）；服务器地址设置项接线（占位在 `SettingsDetailPage.ets:355-357`）。
- [ ] M7.3 会话与播放同步：`ListenTogetherSessionManager` 语义（加入/离开/主持权切换）+ 播放对齐（`ListenTogetherPlayerSyncPlanner`/`StateApplier`：position 校正、时钟偏移估计、阈值内不抖动）；与 PlayerManager 通过监听器集成，不依赖页面。
- [ ] M7.4 UI：房间页/邀请分享；最小可用（不追求 Android 全部 58 文件规模）。
- [ ] M7.5 验收：双模拟器实例同房间同步播放偏差 <300ms；断线重连恢复；单测全绿。（依赖 D7 服务端，无则标注「待外部依赖」收尾）

### M8 视觉与歌词增强（可穿插，无硬依赖）

- [ ] M8.1 动态取色：封面 `image.createImageSource`→降采样 PixelMap→纯 ArkTS Palette 语义（Vibrant/Muted/Dominant，对齐 `CoverArtColorCache`）→Theme 覆盖层；设置开关接线（占位 `SettingsPage.ets:95`）；低端机降采样降级。
- [ ] M8.2 LRC 增强（G12）：`[offset:]` 标签、元数据头保留、逐字（Word LRC）、`np.lyric_offset_ms` 设置消费；单测对齐 `LyricTimestampNormalizerTest`。
- [ ] M8.3 AMLL TTML 歌词：`AmllTtmlClient` 语义（逐字/翻译/音译），作为高阶歌词源接入 LyricApi 分发。
- [ ] M8.4 高级模糊/玻璃：backgroundBlurStyle/visualEffect 路径（AGSL shader 无直接对应，D 级降级记录）；NowPlaying 背景效果对齐 Android `ui/effect/glass` 的可用子集。
- [ ] M8.5 UI 打磨包：WaveformSlider（播放心形/波形进度，Android `ui/component/playback/`）、歌词分享卡片、音译显示、MiniPlayer 增强。
- [ ] M8.6 悬浮/状态栏歌词按 D4 降级实现；蓝牙 AVRCP 歌词调研后同样按能力降级。

### M9 USB 可行性 + 发布门槛（战略计划阶段 6/7）

- [ ] M9.1 USB spike（D5）：API 24 `usbManager`/USB DDK 文档核对（等时传输、接口独占、普通应用权限）→ 真机枚举 UAC 设备试探 → 结论记录（大概率降级：USB DAC 走系统路径，独占模式不做）。
- [ ] M9.2 崩溃诊断闭环：HiAppEvent 订阅/导出（对齐 `core/crash`+SafeMode 导出占位 `SafeModePage.ets:26-30`）、ANR(AppFreeze) 日志收集、DebugPage 日志查看。
- [ ] M9.3 发布矩阵：phone/tablet/2in1 布局回归、返回栈/转场、无障碍（文本缩放/触控目标）、功耗与内存冒烟、隐私声明与市场合规清单（第三方源条款）。
- [ ] M9.4 API 26 前瞻（可选）：SDK Manager 下载 API 26 镜像后在 7.0 跑回归；7.0-only 能力走 capability adapter，不污染 24 基线。

### 收尾常设任务（不编号，每里程碑末执行）

- FEATURE_MATRIX.md / PORTING.md / hm.md 状态同步；`git diff --check`；交付说明。

---

## 7. 跨领域事项

### 7.1 安全与凭据

- 所有 token/cookie/PAT：`@ohos.security.asset`（核对 API 24 可用性与配额），禁止明文 preferences；键名对齐 Android（github_token/repo/device_id、MUSIC_U、SESSDATA 等）以便用户从 Android 迁移。
- 日志脱敏（Cookie/Token/完整请求头/用户路径）；DebugPage 探针输出同样过滤。

### 7.2 与 Android 数据互通

- 提供「从 Android 导入」显式工具（战略计划阶段 5）：用户通过 picker 选择 Android 侧导出的 JSON/备份文件→按 M2.2 对齐的格式解析入库；禁止隐式猜测。

### 7.3 上游同步

- Android 快照基线 d66d465f（2026-07-31），上游仍在活跃开发。**冻结基线移植**；如需同步，按 AGENTS.md 以 commit 为单位走同步流程并更新 §3.1。

### 7.4 成本控制（用户全局规则）

- 跨文件搜索/代码定位→`Explore`；外部 API/报错调研→`doc-researcher`；跑构建/测试/读日志→`test-runner`；识图→`image-analyst`。主模型只做设计、写码与整合。

---

## 8. 进度记录协议

- 每任务完成：`[x]` + 证据行（日期、命令、结果摘要）。
- 每里程碑完成：在本节追加一行 `M< n> 完成：YYYY-MM-DD <验证摘要>`。
- 计划本身修订：直接编辑并在文首更新日期；重大变更（里程碑增删、决策点变更）需在 §5 表格记录决策依据。
- 阻塞：任务保持 `[ ]`，追加 `- 阻塞：YYYY-MM-DD <原因/所需输入>`。

- M1 完成：2026-08-16 单测 42 用例全绿；ohosTest 4/4（含网络播放 smoke、队列冷启动恢复）；codelinter 基线持平（详见 §6 M1.7 与 hm.md §7.6）。
- M2 完成：2026-08-16 SchemaStore 版本化/.bak/损坏恢复设备实证（ohosTest 7/7 累计）；Android fixture 跨端解析与 stableKey 格式单测通过（详见 §6 M2.5）。
- M3 完成：2026-08-16 下载全链模拟器实测通过（ActsDownloadSmokeTest：搜索→DIRECT 传输 5.6MB→commit→编目→防重复，两次独立运行）；全套 ohosTest 8/8；修复 3 个真 bug（dataEnd 响应码屏蔽、COMPLETED/catalog 竞态、编目双重序列化）；未自动化项见 M3.7（详见 hm.md §7.7）。
- M4 完成：2026-08-17 凭据基建（asset 后端实证+降级策略）、网易云 QR 登录+登录态歌单（用户歌单/每日推荐/批量导入）、B 站 QR 登录+收藏夹浏览（共享 QrLoginPanel、匿名 buvid 种子）；本地单测 127/127、设备 ohosTest 20/20（含网易/B 站真网 QR smoke 与推荐歌单真网链路）；真机扫码确认（网易云 803、B 站 0→收藏夹数据、登录态高音质）待用户带对应 App 复核（详见 §6 M4.2/M4.3/M4.4 证据）。
