# NeriPlayer → HarmonyOS 原生移植说明 (PORTING.md)

> **审计提示（2026-08-12）：** 本文保存 2026-08-02 原型开发时的记录。“实测/完成”仅指当时特定 API 24 模拟器与缓存环境中的结果，本次未独立重现，也不等同于当前 Android 上游的完整功能等价。后续计划与可信度分级以仓库根目录 `docs/` 为准。

本目录是 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)（Jetpack Compose + Media3 的 Android 原生音频播放器）到 **HarmonyOS NEXT 原生应用**的移植工程。

## 基线 (Baseline)

- **HarmonyOS 26.0.0 Release / API 26**（2026-09-07 从 6.1.1 Release / API 24 全量迁移，见 `../docs/hm.md` §7.12；迁移前本机 DevEco Studio 6.1.1.300，SDK 6.1.1.125）
- **Stage 模式**（UIAbility + 单入口），主语言 **ArkTS**（严格模式），UI 框架 **ArkUI**
- 包名：`moe.ouom.neriplayer.hmos`（2026-09-01 由原项目包名 `moe.ouom.neriplayer` 改名）
- 许可证沿用 **GPL-3.0**

## 当前状态（2026-08-02 已在 API 24 模拟器实测）

✅ 已实测通过：

| 功能 | 说明 |
|---|---|
| 工程构建 | `hvigorw assembleHap` 全量构建零错误、零 ArkTS 警告 |
| 本地签名安装 | `sign-local.ps1` 一键构建 → OpenHarmony 调试签名 → `hdc install` 到模拟器 |
| 启动流程 | Loading → 免责声明 → 引导（3 步）→ 主界面；设置持久化（preferences）跨进程重启保留 |
| 主界面导航 | 首页 / 探索 / 资料库 / 设置四个 Tab + 全页面路由（播放/歌单/历史/统计/下载/设置详情/调试） |
| UI 全量移植 | 对照原项目页面清单：首页（继续收听/最近播放/推荐歌单）、探索（搜索+平台+历史）、资料库（收藏/本地歌单/统计/下载）、设置（10 个分区+二级页）、播放页（模糊封面/进度/控制/速度/睡眠/队列/双语歌词）、下载管理、播放历史、播放统计、歌单详情、引导、安全模式、调试页 |
| 网易云搜索 | weapi 被服务端风控（50000005）时自动回退旧版 `/api/search/get/web`，实测返回真实歌曲列表 |
| 在线播放 | 点歌 → 取流（weapi/旧版 URL 回退）→ AVPlayer prepare → playing，媒体流完整下载 |
| 歌词 | NowPlaying 页渲染 LRC + 翻译（作词/作曲头部、双语逐行高亮） |
| 迷你播放器 | 播放中显示当前歌曲 + 进度条 + 来源角标，点击进入 NowPlaying 页 |
| 崩溃安全模式 | 标记后重启进入 SafeMode（代码路径，未实测崩溃注入） |

## 当前状态（2026-08-31 复核）

2026-08-13 在本机 6.1.1 Release 工具链完成可重复验证：`ohpm install --all`、`hvigorw clean`、Debug `assembleHap` 构建成功（存在 6 条"Function may throw exceptions"非阻塞警告，分布在 `LibraryPage.ets`、`PlaylistDetailPage.ets`、`DebugPage.ets`）；ArkTS 单元测试 3/3 通过（`entry/src/test/`，LRC 解析/翻译合并/时间格式化）；调试签名、模拟器安装、冷启动与设置页 smoke test 通过。完整记录见 `../docs/hm.md` §7.4。

该验证只覆盖构建、启动、安全区和设置页入口，不代表下述能力已完成。2026-08-19 又完成同步核心的本地验证：WebDAV PROPFIND/GET/PUT 与 ETag/Last-Modified/SHA-256 回退、SyncCoordinator 三路合并与冲突重试、真实仓库快照接线、apply journal 和设置页同步报告；本地单测 378/378、`entry@default`/`entry@ohosTest` 构建成功、CodeLinter 0 error。真实 PAT/WebDAV 写入和双设备冲突仍未验证。当前待办（2026-08-31 复核更新；代码中均有 porting seam 标注，不得在文档中标为已完成）：

1. **weapi 风控**：`weapi/cloudsearch/get/web` 在本模拟器网络环境返回 `{"code":50000005}`（无浏览器指纹/IP 风控），目前靠旧版接口回退可用；后续可补 eapi 路径或二维码登录后携带 `MUSIC_U` 重试。
2. **YouTube 取流**：搜索与匿名 IOS 直连取流已落地（M6.1/M6.2，`network/ytm/*`）；设备实测匿名直链仅整轨前约一分钟可播、生产播放链路未接环回桥（M6.5），完整取流仍需 PoToken/JS 运行时（M6.3 未开始）。
3. **下载管线**：已于 2026-08-16 全链落地并模拟器实测（DIRECT Range/If-Range 续传、HLS checkpoint、原子提交、启动恢复、离线短路）；断网暂停/杀进程恢复的设备端自动化与元数据 tag 写入（现为 sidecar 编目）待补。
4. **同步验收**：核心传输、合并和本地接线已完成；双设备冲突验收已于 2026-08-22 经本地自建 WebDAV 服务器通过（M5.6），真实云 PAT/WebDAV 写路径与省流格式写出（现降级 JSON）待复核。
5. **一起听 / USB 独占 / 悬浮歌词**：一起听核心链路已于 2026-08-22 双端设备闭环（M7.5，房间设置开关等增强项未做）；USB 独占经 M9.1 spike 定案**不移植**（ArkTS 单 JS 线程守不住等时节拍、SDK 无公开 USB DDK，见 `../docs/USB_M91_SPIKE.md`）；悬浮歌词已按 D4 降级落地（应用内悬浮条 + AVSession 正规歌词字段，系统级桌面歌词渲染层待真机，M10.2）。
6. **动态取色与高级模糊**：已于 2026-08-23 落地（M8.1 封面 Palette 取色 + Theme 覆盖层；M8.4 背景模糊/玻璃子集，AGSL 区域掩码玻璃无平台对应、按 D 级降级，记录见 `../docs/FEATURE_MATRIX.md`）。

## 目录结构

```text
NeriPlayer-HarmonyOS/
├── AppScope/                     # 应用级配置（bundleName、图标、label）
├── build-profile.json5           # 工程级构建配置（compatibleSdkVersion 26.0.0）
├── hvigor/                       # Hvigor 版本配置
├── sign-local.ps1                # 本地构建+签名+安装脚本（命令行调试用）
├── signing/                      # 本地调试签名材料（自动生成，勿提交密钥）
└── entry/
    └── src/main/
        ├── module.json5          # 权限、后台音频、网络配置
        ├── ets/
        │   ├── entryability/     # EntryAbility（启动、窗口、主题）
        │   ├── pages/Index.ets   # 启动状态机
        │   ├── app/              # Logger、Constants
        │   ├── model/            # SongItem、SongIdentity、Playlist、QueueState
        │   ├── data/             # 设置/历史/歌单/统计/本地媒体
        │   ├── network/          # HttpClient(Cookie罐)、网易云/B站/YTMusic、歌词、流解析
        │   ├── player/           # PlayerManager(AVPlayer)、AVSession、后台任务
        │   ├── lyrics/           # LRC 解析
        │   └── view/             # 页面与组件（首页/探索/资料库/设置/正在播放/调试）
        └── resources/            # 字符串、颜色、图标、路由、网络安全配置
```

## 本地命令行构建与安装

DevEco Studio 6.1.1 的 `build-profile.json5` 不再接受明文签名口令（要求加密串 + material 目录），因此工程保持 `signingConfigs: []`，由脚本用 SDK 自带的 OpenHarmony 调试证书手动签名：

```powershell
# 前置（2026-08-14 本机布局）：API 24 SDK 与 CLI 在 D:\HarmonyOS\Tools\command-line-tools\，
# sign-local.ps1 还需要 Studio 布局中的 jbr 与 hvigor，因此显式设置以下两个环境变量。
$env:DEVECO_SDK_HOME = 'D:\HarmonyOS\Tools\command-line-tools\sdk'
$env:DEVECO_STUDIO_HOME = 'D:\HarmonyOS\Tools\devecostudio-windows-26.0.0.621\DevEco Studio'
.\sign-local.ps1          # 构建 -> 签名 -> 安装到 127.0.0.1:5555
.\sign-local.ps1 -SkipInstall
```

签名材料（`signing/`）由脚本首次自动生成：复制 SDK `toolchains/lib/OpenHarmony.p12` 并设置 >=32 位的奇数长度口令，导出证书链后调用 `hap-sign-tool.jar`。密钥仅用于本地调试。

## 模块映射 (Android → HarmonyOS)

| Android 模块 | 原实现 | 移植位置 | 状态 |
|---|---|---|---|
| 启动流程 | `MainActivity` + `StartupStageFlow` | `pages/Index.ets` + `view/pages/*` | ✅ 实测 |
| 安全模式 | `SafeModeManager` | `Index` 阶段 + `SafeModePage` | ✅ 基础 |
| 导航 | Compose NavHost + 底部 Tab | `view/pages/MainShell.ets` + `view/Router.ets` | ✅ 实测 |
| 播放核心 | `PlayerManager` + Media3 ExoPlayer | `player/PlayerManager.ets`（AVPlayer） | ✅ 实测 |
| 媒体会话 | `MediaSession` | `player/AVSessionManager.ets`（AVSession） | ✅ 初始化 |
| 后台播放 | 前台服务 + 后台策略 | `module.json5` + `player/BackgroundTaskRunner.ets` | ✅ 基础 |
| 歌曲模型 | `SongItem` / `SongIdentity` | `model/SongItem.ets` / `model/SongIdentity.ets` | ✅ |
| 设置 | DataStore/SharedPreferences | `data/SettingsRepository.ets`（preferences + AppStorage） | ✅ 实测持久化 |
| 播放历史/统计 | `PlayHistoryRepository` 等 | `data/HistoryRepository.ets` / `PlaybackStatsRepository.ets` | ✅ |
| 继续收听 | `PlaylistUsageRepository` | `data/UsageRepository.ets` | ✅ |
| 下载任务目录 | `DownloadTaskStore` | `data/DownloadsRepository.ets` + `model/DownloadTask.ets` | ✅ 目录/UI；传输管线已落地（2026-08-16 全链实测） |
| 搜索历史 | 探索页历史 | `data/SearchHistoryRepository.ets` | ✅ |
| 歌单/收藏 | `LocalPlaylistRepository` | `data/LocalPlaylistRepository.ets` | ✅ |
| 网络 | OkHttpClient | `network/HttpClient.ets`（@ohos.net.http + Cookie 罐） | ✅ |
| 网易云 | weapi 搜索/取流/歌词/歌单 | `network/NeteaseApi.ets` + `NeteaseCrypto.ets` | ✅ 搜索/歌词实测；weapi 有风控回退 |
| Bilibili | 搜索 + DASH 取流 | `network/BiliApi.ets`（含 `BiliWbi.ets` WBI 签名、音轨选择） | ✅ QR 登录/收藏夹/真网搜索取流实测（2026-08-18/19） |
| YouTube Music | innertube 搜索 + IOS 直连取流 | `network/YouTubeMusicApi.ets`、`network/ytm/*` | ⏳ 搜索/取流已落地（M6.1/M6.5），播放受上游约一分钟封顶，完整取流待 M6.3 |
| 歌词 | LRCLIB + 网易云 + LRC 解析 | `network/LyricApi.ets` + `lyrics/LrcParser.ets` | ✅ 实测 |
| 本地媒体 | `LocalAudioImportManager` | `data/LocalMediaScanner.ets` | ⏳ 待真机验证 |
| 主题 | Material3 色板（浅/深色） | `view/Theme.ets` + `view/theme/` | ✅ 浅/深色 + 封面动态取色（M8.1，2026-08-23 设备实证） |
| 下载 | `GlobalDownloadManager` | `view/pages/DownloadsPage.ets` + `download/` 引擎 | ✅ UI/目录/传输管线全链实测（2026-08-16） |
| 同步 | GitHub/WebDAV 三路合并 | `sync/`、`SettingsDetailPage.ets` | ✅ 核心 + 双设备本地服务器验收（M5.6）；真实云凭据待复核 |
| 一起听/USB/悬浮歌词 | — | `listentogether/`、`view/components/FloatingLyricBar.ets` 等 | 一起听核心闭环（M7.5）；USB 定案不移植（M9.1）；悬浮歌词 D4 降级落地（M8.6） |

### UI 页面映射（Android → HarmonyOS）

| Android | HarmonyOS |
|---|---|
| `HomeScreen`（继续收听/推荐网格） | `view/pages/HomePage.ets` |
| `ExploreScreen`（搜索+平台+歌单搜索） | `view/pages/ExplorePage.ets` |
| `LibraryScreen`（本地/收藏/统计入口） | `view/pages/LibraryPage.ets` |
| `SettingsScreen`（全部分区） | `view/pages/SettingsPage.ets` + `SettingsDetailPage.ets` |
| `NowPlayingScreen`（封面/歌词/进度/控制/睡眠/队列） | `view/pages/NowPlayingPage.ets` |
| `RecentScreen` | `view/pages/RecentPage.ets` |
| `DownloadManagerScreen` / `DownloadProgressScreen` | `view/pages/DownloadsPage.ets` |
| `PlaybackStatsScreen` | `view/pages/StatsPage.ets` |
| `LocalPlaylistDetailScreen` | `view/pages/PlaylistDetailPage.ets` |
| `StartupOnboardingScreen` | `view/pages/OnboardingPage.ets`（3 步） |
| `SafeModeScreen` | `view/pages/SafeModePage.ets` |
| `DebugHomeScreen` | `view/pages/DebugPage.ets` |
| `NeriMiniPlayer` | `view/components/MiniPlayer.ets`（含进度条/来源角标） |
| 共享卡片/行/空态 | `view/components/Ui.ets` + `SongRow.ets`（溢出菜单：收藏/下载/分享） |

## 关键设计决策

1. **稳定歌曲身份**：`stableKeyOf()` 保持 `id|album|mediaUri` 格式，与 Android 端兼容。
2. **播放器状态发布**：`PlayerManager` 通过 AppStorage（`player.*`）发布快照，页面用 `@StorageLink` 绑定；非 UI 服务用监听器 + AVSession。
3. **设置持久化**：不再依赖 `PersistentStorage`（实测冷启动丢失），改用 `preferences` 读写 + AppStorage 响应式；`AppPreferences` 带初始化等待屏障，避免启动早期读写丢失。
4. **weapi 加密**：`NeteaseCrypto` 纯 ArkTS 实现 AES-128-CBC（两次）+ RSA-1024（随机密钥反转后无填充 RSA、hex 输出），与 Android 原版一致；先访问首页拿 Cookie（`os=pc`、`appver`）并携带 `csrf_token`。
5. **搜索回退**：weapi 被风控时自动回退 `/api/search/get/web`，保证离线风控环境下搜索可用。
6. **本地播放 fd 生命周期**：AVPlayer 播放 `fd://` 期间保持 `fileIo` 句柄存活，切歌时再关闭旧句柄。

## 后续阶段清单 (Roadmap)

> 2026-08-31 复核：第 2、3、4 项与第 6～9 项多数已落地或已有定案（第 5 项 USB 经 M9.1 spike 定案不移植），当前任务级状态以 `../docs/PORTING_EXECUTION_PLAN.md` 看板与 `../docs/FEATURE_MATRIX.md` 为准，下表保留为历史规划原文。

1. YouTube 取流：移植 yt-dlp EJS 引擎或集成 JS 运行时（签名/n、PoToken、HLS 回退）。
2. 下载管线：共享 HTTP 客户端上的分块 Range 续传、HLS 段索引、启动恢复、sidecar 元数据。
3. 同步验收：真实 PAT/WebDAV 写入、省流格式写出、双设备冲突和设备 smoke test。
4. 一起听：WebSocket 房间协议、Durable Objects 状态机、时钟偏移校正。
5. USB 独占：NAPI C++ 移植 UAC1/UAC2 传输与反馈时钟路径。
6. 歌词扩展：悬浮歌词、状态栏歌词、Lyricon/SuperLyric、歌词卡片生成、音译。
7. 动态取色与高级模糊：封面色提取、`componentSnapshot`/模糊材质。
8. 平台登录：网易云/Bilibili 二维码登录、YouTube Cookie 会话管理。
9. 崩溃诊断闭环：HiAppEvent 订阅、AppFreeze 日志、日志查看与导出。
