# Android → HarmonyOS 功能迁移矩阵

状态定义：

- `原型`：已有代码路径，但未完成等价性与设备验证。
- `部分`：已覆盖主要场景，仍缺关键分支。
- `未开始`：只有 UI 入口、文档描述或空实现。
- `待复核`：历史上声称可用，本次环境无法重现。

| 能力 | Android 参照位置 | ArkTS 目标位置 | 当前状态 | 下一验证点 |
| --- | --- | --- | --- | --- |
| 启动/免责声明/引导 | `core/startup`、相关 UI | `pages/Index.ets`、启动页面 | 原型 | 冷启动、升级、崩溃恢复状态测试 |
| 主导航与多设备布局 | `navigation`、`ui/screen` | `view/Router.ets`、`MainShell.ets` | 原型 | phone/tablet/2in1 断点与返回栈 |
| 歌曲/歌单/稳定键 | `data/model`、本地歌单 | `model`、`data` | 部分 | 用 Android fixture 做跨端序列化契约测试 |
| 设置/历史/统计 | DataStore 与仓库 | preferences 仓库 | 原型 | 版本迁移、并发写、损坏恢复 |
| AVPlayer 基础播放 | Media3/ExoPlayer 服务 | `player/PlayerManager.ets` | 待复核 | 本地/HTTP/HLS、seek、切源、耳机事件 |
| 播放队列/随机/循环 | 播放策略模块 | PlayerManager/QueueState | 原型 | 确定性队列状态机测试 |
| AVSession/系统控制 | MediaSession | `AVSessionManager.ets` | 原型 | 锁屏、耳机、控制中心、应用被杀 |
| 后台连续播放 | 前台服务 | 后台任务 + audioPlayback | 原型 | 权限拒绝、熄屏、长时运行、系统回收 |
| 音频焦点/中断 | audio focus 策略 | 待完善 | 未开始 | 来电、导航播报、其他播放器竞争 |
| 网易云搜索/歌词/取流 | `core/api/netease` | `network/Netease*.ets` | 原型 | 登录态、风控、限流、会员内容 |
| Bilibili 搜索/取流 | `core/api/bili` | `network/BiliApi.ets` | 原型 | DASH 格式、Cookie、区域/权限错误 |
| YouTube Music | API、EJS/解析器 | `YouTubeMusicApi.ets` | 部分 | signature/n、PoToken、HLS、登录态 |
| 歌词解析与同步 | lyric API/组件 | `LrcParser.ets`、`LyricView.ets` | 原型 | 双语、逐字、偏移、超长歌词性能 |
| 本地媒体导入 | MediaStore/DocumentFile | `LocalMediaScanner.ets` | 原型 | READ_AUDIO 授权、真机元数据、失效 URI |
| 下载与断点恢复 | `core/download` | 下载仓库/页面 | 未开始 | Range/HLS、校验、原子提交、空间不足 |
| 分享/文件访问 | FileProvider | HarmonyOS 文件/分享能力 | 未开始 | URI 授权、外部应用、隐私沙箱 |
| GitHub/WebDAV 同步 | `data/sync` | 待建 `sync` 层 | 未开始 | ETag、条件写、冲突合并、凭据存储 |
| 平台登录 | auth activities/repositories | 待建 `auth` 层 | 未开始 | QR/Web/Cookie、安全存储、注销 |
| 一起听 | `listentogether` | 待建独立模块 | 未开始 | WebSocket、校时、重连、主持权 |
| USB 独占 | C++ UAC1/UAC2 | 待建 NAPI C++ 模块 | 未开始 | USB Host、等时传输、反馈时钟、机型矩阵 |
| 动态取色/高级视觉 | Compose/Palette/着色器 | ArkUI 主题与效果 | 未开始 | 性能、无障碍、低端设备降级 |
| 崩溃/ANR/日志 | crash/diagnostics | Logger/HiAppEvent 路径 | 原型 | 真崩溃采集、导出、隐私脱敏 |

> 注（2026-08-14）：`LrcParser` 已有 3 个 hypium 单元测试通过（`entry/src/test/`，2026-08-13 实测），是本矩阵中首项有自动化验证证据的能力；2026-08-13 另完成主线干净构建、调试签名与模拟器冷启动 smoke test（`hm.md` §7.4），但不改变上表各能力的"原型/未开始"评级。

## 首个可交付垂直切片

首个里程碑不追求页面数量，而要求以下闭环全部自动化验证：

1. 启动并进入主界面。
2. 使用本地 fixture 搜索并显示歌曲列表，不依赖第三方网络。
3. 播放一个随仓库提供或测试时生成的短音频 fixture。
4. 支持播放/暂停/seek/下一首和队列恢复。
5. 系统媒体控制能读取元数据并控制播放。
6. 重启应用后恢复设置、队列和播放位置。
7. ArkTS 单元测试与设备 smoke test 同时通过。

