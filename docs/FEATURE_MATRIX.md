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
| 歌曲/歌单/稳定键 | `data/model`、本地歌单 | `model`、`data` | 部分 | 2026-08-16 stableKey 对齐测试+本地歌身份缺陷修复；Android fixture 跨端解析（历史/歌单）已测；「从 Android 导入」UI 入口待建 |
| 设置/历史/统计 | DataStore 与仓库 | preferences 仓库 | 部分 | 2026-08-16 SchemaStore 版本化+.bak 备份+损坏恢复（ohosTest 实证）；写防抖；Android 统计格式导入待补 |
| AVPlayer 基础播放 | Media3/ExoPlayer 服务 | `player/PlayerManager.ets` | 部分 | 2026-08-16 ohosTest 实测网络音频 initialized→prepared→playing→paused→release 全链；seek/切源/耳机事件待复核 |
| 播放队列/随机/循环 | 播放策略模块 | PlayerManager/QueueEngine | 部分 | 队列+位置+模式跨冷启动恢复与纯队列状态机（shuffle bag/history/future、种子化随机、remap）已有单测+ohosTest+模拟器实证（2026-08-16）；「下一首播放」插入/拖拽排序的 UI 接线待后续里程碑 |
| AVSession/系统控制 | MediaSession | `AVSessionManager.ets` | 部分 | 2026-08-16 补封面/时长/全状态映射/loop/speed 命令与 release 清理；锁屏/控制中心人工核验待复核 |
| 后台连续播放 | 前台服务 | 后台任务 + audioPlayback | 部分 | 2026-08-16 改为真实 AUDIO_PLAYBACK 长时任务申请/取消；熄屏长播 smoke 待复核 |
| 音频焦点/中断 | audio focus 策略 | `AudioInterruptPolicy.ets` | 部分 | 2026-08-16 瞬态/永久/duck/设备拔出策略+接线+6 单测；双媒体竞争真机验证待复核 |
| 网易云搜索/歌词/取流 | `core/api/netease` | `network/Netease*.ets` | 部分 | 登录态接入（2026-08-16 M4：QR 登录+MUSIC_U 种子 weapi 会话+301 刷新重试）；2026-08-17 M4.3 补 `/personalized/playlist` 推荐歌单（匿名回退 301/50000005）、`/user/playlist` 用户歌单、`/w/nuser/account/get` uid 解析（均 weapi+纯解析器单测+真网 ohosTest）；限流、会员内容待复核 |
| Bilibili 搜索/取流 | `core/api/bili` | `network/BiliApi.ets` | 部分 | 2026-08-17 M4.4：请求携带登录 cookie 或匿名 buvid 指纹（`/x/frontend/finger/spi` 内存缓存 1h，失败静默降级）；登录后收藏夹列表（`created/list-all`+分页兜底）与内容分页/全量拉取（`fav/resource/list`，has_more 终止+type:id:bvid 去重，纯解析器 10 单测）；DASH 仍只取最大带宽音轨（Android 音质偏好链待移植）；WBI 签名按 D6 暂不移植；区域/权限错误分类待补 |
| YouTube Music | API、EJS/解析器 | `YouTubeMusicApi.ets` | 部分 | signature/n、PoToken、HLS、登录态 |
| 歌词解析与同步 | lyric API/组件 | `LrcParser.ets`、`LyricView.ets` | 原型 | 双语、逐字、偏移、超长歌词性能 |
| 本地媒体导入 | MediaStore/DocumentFile | `LocalMediaScanner.ets` | 原型 | READ_AUDIO 授权、真机元数据、失效 URI |
| 下载与断点恢复 | `core/download` | `download/*.ets`、`network/HttpStreamDownloader.ets`、DownloadsPage | 部分 | 2026-08-16 全链落地并模拟器实测（搜索→下载 5.6MB→编目→防重复，ohosTest 8/8）：DIRECT Range/If-Range 续传、HLS checkpoint、重试退避、原子 commit、启动恢复、网络感知、离线播放短路、DebugPage 探针。断网暂停/恢复与杀进程中断恢复为单测覆盖、设备端未自动化；元数据 tag 写入降级为 sidecar 编目；空间不足处理未做 |
| 分享/文件访问 | FileProvider | HarmonyOS 文件/分享能力 | 未开始 | URI 授权、外部应用、隐私沙箱 |
| GitHub/WebDAV 同步 | `data/sync` | `sync/*.ets`（合并策略族+序列化+快照） | 部分 | 2026-08-18 M5.1/M5.2：纯合并策略族（歌单歌曲两路合并/元数据确定性选择/删除墓碑 legacy+causal/统计 max+shards+clear 屏障+lift/trim/变更检测/因果 token/SHA-256 稳定 id，107 单测）+ JSON 序列化器（kotlinx 语义手写复刻、自写 parser 解决 int64 大 id 精度保真 syncIdText、三格式嗅探、8/12/16MiB 上限、backup.json 全线互通）+ 快照构建（注入式 buildLocalSyncData：墓碑补位/500 截断/counterBase 先归一后算）+ displayOrder 迁移 + 墓碑/设备 id 偏好存储（39 单测）；2026-08-19 M5.2b：backup-raw.bin（GZIP+protobuf）与 backup.bin（legacy Base64+GZIP+protobuf）**读取**全链落地——纯 ArkTS gzip/DEFLATE 解压（stored/fixed/dynamic、多 member、CRC32/ISIZE 校验）+ protobuf wire 解码器（BigInt 保真 64 位 id、严格 wire-type 校验、未知字段跳过）+ Legacy schema 兜底（对齐 kotlinx 回退语义），字节级 fixture 含真实 java.util.zip.GZIPOutputStream 产物（11 单测）；省流格式写出（proto encode+deflate）、GitHub/WebDAV 传输、SyncCoordinator（M5.3~M5.5）未开始 |
| 平台登录（网易云） | auth activities/repositories | `data/auth/*`、`network/NeteaseQrLogin.ets`、`util/QrEncoder.ets` | 部分 | 2026-08-16 M4.1/M4.2：Asset Store 凭据基建（asset 后端模拟器实证；不可用时降级会话内存并暴露状态）、纯 ArkTS QR 生成器（segno 字节级夹具+152 组合扫描对齐）、QR 登录 UI+轮询+登出、粘贴 Cookie 备用导入、MUSIC_U 会话种子；2026-08-17 M4.3 登录态收益：资料库「网易云歌单」区（用户歌单列表/详情/批量导入本地歌单，stableKey 去重一次落盘）+ 首页「每日推荐」横滑区（匿名可用）；真机扫码确认（803→登录态歌单）仍待复核；B 站登录见下行；YouTube 登录未开始 |
| 平台登录（Bilibili） | `BiliQrLoginClient`/`BiliCookieRepository` | `data/auth/BiliAuth*.ets`、`network/BiliQrLogin.ets`、`view/components/QrLoginPanel.ets` | 部分 | 2026-08-17 M4.4：QR 登录（generate/poll 端点、86101/86090/0/86038 状态机、passport 域被动 Set-Cookie 累积）、cookie bundle asset 持久化（键名对齐 Android `bili_auth_bundle`，仅 SESSDATA 判定登录、无过期语义，11 单测）、共享 QrLoginPanel 组件（网易/B 站复用，轮询状态机去重）、粘贴 Cookie 备用导入、资料库「B 站收藏夹」区+BiliFavPage 详情；真网 ohosTest 3/3（QR session 生成+fresh poll 等待态、仓库往返+清除、缺 SESSDATA 拒绝）；扫码确认（0→SESSDATA 落库→收藏夹浏览）需真机+哔哩哔哩 App，待复核 |
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

