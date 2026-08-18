# NeriPlayer → HarmonyOS 原生移植说明 (PORTING.md)

本目录是 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)（Jetpack Compose + Media3 的 Android 原生音频播放器）到 **HarmonyOS NEXT 原生应用**的移植工程。

## 基线 (Baseline)

- **HarmonyOS 6.1.1 Release / API 24**（生产基线；本机 DevEco Studio 6.1.1.300，SDK 6.1.1.125）
- **Stage 模型**（UIAbility + 单入口），主语言 **ArkTS**（严格模式），UI 框架 **ArkUI**
- 包名沿用原项目：`moe.ouom.neriplayer`
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
| 下载管线 | Range 分块续传（206/200/416 回退）、并发队列、暂停/恢复/重试、启动自动恢复、.lrc/.song.json sidecar、离线播放（沙箱目录） |
| UI 图标 | 所有 emoji 占位图标已替换为 SVG（`util/IconCatalog.ets` + `resources/base/media/*.svg`） |
| 动态取色 | 封面 12×12 RGBA 采样 → 饱和度/亮度加权取 accent，应用于播放页滑杆与歌词高亮（CoverColorExtractor） |

⏳ 待完善（按优先级）：

1. **weapi 风控**：`weapi/cloudsearch/get/web` 在本模拟器网络环境返回 `{"code":50000005}`（无浏览器指纹/IP 风控），目前靠旧版接口回退可用；后续可补 eapi 路径或二维码登录后携带 `MUSIC_U` 重试。
2. **YouTube 取流**：仍缺 signature/n 参数、PoToken 与 EJS 引擎，仅搜索可用。
   <!--
3. **下载管线**：`DownloadsPage` 与任务目录已完成，需移植 Range 断点续传 + 实际文件落盘。
   -->
   3. ✅ **下载管线**：Range 续传、实际落盘、暂停/恢复/重试已完成，目录选择/导出待后续迁移。
4. **同步**：GitHub / WebDAV 同步待移植。
5. **一起听 / USB 独占 / 悬浮歌词**：待移植（USB 需 NAPI C++）。
   <!--
6. **动态取色与高级模糊**：设置页已有入口，引擎待实现。
   -->
   6. ✅ **动态取色**：封面取色引擎已完成并接入 NowPlaying；壁纸取色与全局主题联动待后续。

## 目录结构

```text
NeriPlayer-HarmonyOS/
├── AppScope/                     # 应用级配置（bundleName、图标、label）
├── build-profile.json5           # 工程级构建配置（compatibleSdkVersion 6.1.1(24)）
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
          │   ├── download/         # DownloadManager、Range 续传、沙箱落盘、sidecar
        │   ├── lyrics/           # LRC 解析
        │   └── view/             # 页面与组件（首页/探索/资料库/设置/正在播放/调试）
        └── resources/            # 字符串、颜色、图标、路由、网络安全配置
```

## 本地命令行构建与安装

DevEco Studio 6.1.1 的 `build-profile.json5` 不再接受明文签名口令（要求加密串 + material 目录），因此工程保持 `signingConfigs: []`，由脚本用 SDK 自带的 OpenHarmony 调试证书手动签名：

```powershell
# 前置：本机 DevEco Studio 6.1.1（含 SDK、Hvigor、ohpm、hdc），模拟器已启动
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
| 下载任务目录 | `DownloadTaskStore` | `data/DownloadsRepository.ets` + `model/DownloadTask.ets` | ✅ 目录/UI，传输管线待移植 |
| 搜索历史 | 探索页历史 | `data/SearchHistoryRepository.ets` | ✅ |
| 歌单/收藏 | `LocalPlaylistRepository` | `data/LocalPlaylistRepository.ets` | ✅ |
| 网络 | OkHttpClient | `network/HttpClient.ets`（@ohos.net.http + Cookie 罐） | ✅ |
| 网易云 | weapi 搜索/取流/歌词/歌单 | `network/NeteaseApi.ets` + `NeteaseCrypto.ets` | ✅ 搜索/歌词实测；weapi 有风控回退 |
| Bilibili | 搜索 + DASH 取流 | `network/BiliApi.ets` | ⏳ 待实测 |
| YouTube Music | innertube 搜索 | `network/YouTubeMusicApi.ets` | ⏳ 搜索待实测，取流待移植 |
| 歌词 | LRCLIB + 网易云 + LRC 解析 | `network/LyricApi.ets` + `lyrics/LrcParser.ets` | ✅ 实测 |
| 本地媒体 | `LocalAudioImportManager` | `data/LocalMediaScanner.ets` | ⏳ 待真机验证 |
| 主题 | Material3 色板（浅/深色） | `view/Theme.ets` | ✅ 浅/深色；动态取色待移植 |
| 下载 | `GlobalDownloadManager` | `view/pages/DownloadsPage.ets` + `DownloadsRepository` | ✅ UI/目录；传输管线待移植 |
| 同步/一起听/USB/悬浮歌词 | — | 设置页占位 | ⏳ 待移植 |

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

1. YouTube 取流：移植 yt-dlp EJS 引擎或集成 JS 运行时（签名/n、PoToken、HLS 回退）。
2. 下载管线：共享 HTTP 客户端上的分块 Range 续传、HLS 段索引、启动恢复、sidecar 元数据。
3. 同步：GitHub（Git Data API blob/tree/commit）、WebDAV（ETag/条件写 + SHA-256 指纹）三路合并。
4. 一起听：WebSocket 房间协议、Durable Objects 状态机、时钟偏移校正。
5. USB 独占：NAPI C++ 移植 UAC1/UAC2 传输与反馈时钟路径。
6. 歌词扩展：悬浮歌词、状态栏歌词、Lyricon/SuperLyric、歌词卡片生成、音译。
7. 动态取色与高级模糊：封面色提取、`componentSnapshot`/模糊材质。
8. 平台登录：网易云/Bilibili 二维码登录、YouTube Cookie 会话管理。
9. 崩溃诊断闭环：HiAppEvent 订阅、AppFreeze 日志、日志查看与导出。
