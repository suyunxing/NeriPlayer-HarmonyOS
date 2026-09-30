# Android 原版功能对齐待办（ANDROID_PARITY_BACKLOG）

> 2026-09-14 编制，基于当日对 Android 快照（`NeriPlayer-master/`，约 126 个设置键、285 个 JVM 测试文件）与 HarmonyOS 主线（257 个源文件、69 个 `np.*` 设置键）的**代码级逐子系统对比审计**。所有「缺失」结论均经两侧源码路径核实（2026-09-14 定点 grep 复核），不采信文档声明。
>
> **定位**：本 backlog 是「把 HarmonyOS 版做成与 Android 原版功能等价」的完整工程缺口清单，**不设时间承诺、不阻塞开源发布**（发布门槛见 `OPEN_SOURCE_RELEASE_PREPARATION.md`）。执行时按 `PORTING_EXECUTION_PLAN.md` §1 的单任务工作循环（定位参照 → 核对 API → 实现 → 测试 → 验证 → 收尾）逐项推进。
>
> **基线数字**：第三方音源完整度约 Android 的 55-60%；设置键 69/126；子系统 9 项中 8 项「部分」、1 项「缺」（本地音乐库）。

---

## 0. 优先级分级

- **P0（跨端核心价值受损）**：SongIdentity 跨端不兼容、统计日桶 30 天截断、同步 Protobuf 只读不写、YTM 播放未闭环。
- **P1（用户可感知的功能缺口）**：YRC 逐字歌词、统计页深度、一起听房间管理、网易云登录与元数据、下载伴生内容。
- **P2（长尾完善）**：设置项细粒度、B 站高阶能力、i18n、本地音乐库。

## 1. 跨端数据与同步（P0）

### 1.1 SongIdentity 数值 ID 哈希算法跨端不兼容 ⚠️ 最高优先

> **✅ 已完成（2026-09-14，`android-parity` 分支 dcbc450）**：`SongIdentity.id` 改为十进制字符串并复用 sync 层既有 `stableSyncId`（SHA-256 前 8 字节大端有符号 Long，0→1 兜底），与 Android `stableYouTubeMusicId` 逐字节一致；旧 FNV 算法冻结为 `legacyFnvStableKey` 仅供迁移。存量数据经 `data/StableKeyMigration.ets` 一次性重算（歌单键按索引对齐重建、统计键冲突求和合并、下载编目按 songJson 重算，不可解析旧键原样保留），EntryAbility 在 loadContent 前等待迁移完成。跨端 fixture：`dQw4w9WgXcQ→6875601686285462142`、`bilibili|170001|234567→-6910934312082985118`（负数符号位路径）等 13 例（`SongIdentitySha256.test.ets`）。**残留**：云端历史 FNV 键条目不会被主动清除（将与 Android 键长期并存直至自然老化）；单测执行计数待 Windows 工作站。

- **事实**：Android 对 B 站/YTM 曲目用 SHA-256 摘要前 8 字节生成 64 位 Long（`NeriPlayer-master/.../data/platform/youtube/YouTubeMusicSupport.kt:469` `stableYouTubeMusicId`，LibraryHostScreen/ExploreHostScreen/HomeScreen 等 UI 层调用）；HarmonyOS 用 FNV-1a 32 位（`entry/src/main/ets/model/SongIdentity.ets:27`）。同一首歌两侧稳定键不同。
- **后果**：Android 设备与 HarmonyOS 设备云同步时，B 站/YTM 曲目被识别为两首歌，重复入库。网易云歌曲不受影响（id 用平台原生数字 id）。
- **做法**：`hashStableId` 改为 SHA-256 截断 64 位（ArkTS 手写或用 `@ohos.security.cryptoFramework`），并写跨端 fixture 测试（同一 bvid/videoId 两端产出相同 id）；已入库的 FNV id 需一次性迁移（按 `<id>|<album>|<mediaUri>` 重算并更新歌单/历史/统计中的引用）。
- **注意**：这是 AGENTS.md 兼容性红线区（稳定键语义变更），必须带迁移方案 + fixture + 回归测试，禁止静默改。

### 1.2 下载歌曲身份回退（sourceStableKey 未被消费）

> **✅ 已完成（2026-09-14，dcbc450）**：`songIdentity()` 对本地歌曲优先解析 `sourceStableKey` 还原远端身份（对齐 Android `normalizedDownloadedSourceIdentity`，自引用守卫）；`LocalMediaScanner` 导入时经 `matchDownloadedEntry`（路径优先/文件名回退）回链下载编目并写入 `sourceStableKey`。单测覆盖「下载→编目→本地导入→识别为同一首」全链。注：HarmonyOS 下载播放本就走编目原始平台身份（DownloadsPage/PlayerManager 均未降级 platform），本项补齐的是本地媒体库导入侧的身份回链。

- **事实**：`SongItem.ets:35/79/135` 定义并序列化了 `sourceStableKey` 字段，但 `SongIdentity.ets` 不读取它；Android 侧 `SongIdentity.kt` 会从本地音频还原云端原始身份。当前下载后的歌曲在 HarmonyOS 端被判为纯本地曲目，身份脱钩（与 1.1 叠加影响跨端同步）。
- **做法**：`SongIdentity.fromSong` 检测本地歌曲时优先解析 `sourceStableKey` 还原平台身份；补单测覆盖「下载→同步→另一端识别为同一首」。

### 1.3 同步上传 Protobuf 写出（省流模式半实现）

> **✅ 已完成（2026-09-14，0c51898）**：新增 `sync/GzipDeflate.ets`（纯 ArkTS fixed-Huffman LZ77 gzip 压缩器，算法原型先经 CPython gzip 交叉解压验证）+ `ProtoWriter` 写入原语 + `encodeSyncDataProto`（字段号与解码器镜像、kotlinx encodeDefaults=false 语义）+ `serializeSyncDataBinary`=GZIP(Proto)。`SyncCoordinator` 注入序列化器，`SyncService` 按省流开关分流（GitHub 写 backup-raw.bin、WebDAV 同名文件共享全局开关并按 gzip 魔数切 octet-stream）。服务器端以 esbuild+Node 真实执行编码→gzip→解码全往返（gzip-proto 体积为 JSON 的 16.6%），CPython gzip 可解压产物；`SyncProtoEncode.test.ets` 6 例。**残留**：与真实 Android 端的双向互通待用户真机复核；默认仍关省流（避免静默切换远端格式）。

- **事实**：读侧三格式兼容（`SyncDataProtoCodec.ets` + `GzipInflate.ets` 可解码 Android 写出的 `backup-raw.bin`），但写侧无论省流开关与否一律 `serializeSyncDataJson`（`SyncCoordinator.ets:105`）；Android 省流模式写 Gzip Protobuf 体积仅 JSON 的 ~15%。
- **做法**：实现 Protobuf 编码器（`ProtobufWire.ets` 已有 wire 基础，补 encode 方向），`upload` 按 `np.sync_data_saver` 分流；用 Android 产出的 `backup-raw.bin` 做往返 fixture（HarmonyOS 写 → Android 读）。`GitHubConfigRepository.ets:12` 注释已自认此缺口。

### 1.4 统计日桶仅保留 30 天（Android 保留 8000 天）

> **✅ 已完成（2026-09-14，cd0976d）**：按 Android `PlaybackStatsDailyBuckets` 真实语义实现「400 天滑动窗口 + 8000 桶硬上限」（原文「8000 天」为桶数之误），`trimDailyBuckets` 移植其淘汰优先级（日期降序→次数降序→键降序）；`PlaybackStatsRetention.test.ets` 4 例。单 key 体积评估：8000 桶上限本身就是护栏，超限前已按优先级裁切。

- **事实**：`PlaybackStatsRepository.ets:26` `BUCKET_DAYS = 30`，超期日桶强制裁切；Android `PlaybackStatsDailyBuckets.kt:4` 为 8_000 桶。年度收听报告等长周期统计在当前实现下不可能。
- **做法**：评估把保留窗口提到与 Android 对齐（直接调常量即可），同时评估 preferences 单 key 体积与写入频率（8 千桶的 JSON 读写开销），必要时改分片存储；跨端同步时注意 Android 端已存在的多年数据合并。

### 1.5 后台自动同步（缺 WorkManager 等价物）

> **✅ 已完成（2026-09-14）**：API 26 官方文档核实后采用三层实现（`sync/AutoSyncScheduler.ets`）：① 数据变更 5 秒防抖静默同步（10 分钟窗口内合并，对齐 Android `scheduleDelayedSync`）；② 启动补偿同步（1 小时节流）；③ **后台延迟任务通道**——`workScheduler`（≥2 小时周期、允许网络、2 分钟回调上限、无需权限、活跃分组下最小 2h，官方文档核实）+ 新增 `SyncWorkSchedulerExtensionAbility`（module.json5 声明，扩展进程内自初始化 preferences/context 后复用同一静默管线）。总开关 `np.sync_auto`（默认关，对齐 Android），设置页 GitHub 分区新增「自动同步」开关并联动延迟任务注册。**未验证**：设备侧（延迟任务实际唤醒、扩展进程同步执行、后台网络），须真机/模拟器复核；长时任务/代理提醒/Push Kit 路线已由文档核实排除（DATA_TRANSFER 需实况窗进度、reminder 无代码回调、后台消息不拉起进程）。

- **事实**：Android 用 WorkManager 周期静默同步（`GitHubSyncWorker`/`WebDavSyncWorker`）；HarmonyOS 只能设置页手动触发。
- **做法**：调研 HarmonyOS 等价能力（`@ohos.resourceschedule.backgroundTaskManager` 的长时/延迟任务或提醒代理，注意平台对后台网络限制），不可行则降级为「应用启动时静默同步一次」并在 README 注明。

## 2. 播放与队列（P1）

### 2.1 在线流错误恢复策略（URL 过期重签与音质降级链）

> **✅ 主路径已完成（2026-09-14，0ed38a4）**：`StreamResolver.invalidateResolvedUrl`（对齐 Android `refreshCurrentSongUrl`）——清歌曲级缓存直链+按 videoId 逐出 YTM 解析缓存，`handleLoadFailure` 的 RETRY_SAME 分支重试前先重签。音质降级池仍为后续增强（网易云本就有 qualityLadderFrom 档位链）。

- **事实**：AVPlayer `on('error')` 不分类全量进 `handleLoadFailure()`（`PlayerManager.ets`），靠 `PlaybackFailurePolicy.ets` 重试 1 次+跳歌；Android 区分 403 防盗链/网络/解码错误，有 `refreshCurrentSongUrl` 重签、候选音质降级池（`trySwitchToNextPlaybackCandidateForRecovery`）。
- **做法**：至少实现「取流 URL 失效时重新调 resolve 取新直链再重试」一层（B 站/网易云直链均有 TTL），错误分类可先粗后细。

### 2.2 播放恢复细粒度设置（2 键）

> **✅ 已完成（2026-09-14，327d6a9）**：`np.keep_playback_mode_state`（默认开=原行为，关闭时启动恢复队列但循环/随机重置列表循环）。长音频独立进度记忆按清单建议不移植（使用面窄）。

- **事实**：HarmonyOS 无条件恢复播放模式；Android 有 `keep_playback_mode_state`（是否记忆循环/随机）、`remember_long_form_playback_progress`（长音频独立进度记忆）。
- **做法**：补 `np.keep_playback_mode_state` 键 + 设置项；长音频进度记忆视使用面决定是否移植。

### 2.3 交叉渐变（Crossfade）

> **⛔ spike 定案：平台限制不做（2026-09-14）**。双 AVPlayer 实例 A/B 轮换的硬阻碍：(1) 未开 `mix_audio` 时系统音频焦点将同应用两实例互斥（B 起播即向 A 投 HINT_PAUSE 强停）；(2) 单实例状态机（waitForState 全局等待锁/进度累加/localFile fd 句柄）与 AvPlaylistBridge 无缝衔接设施全部单实例假设，改造=核心播放架构重写；(3) 双路 IPC 25ms setVolume 插值有混音器抖动风险。已有替代：VolumeFader 切歌淡出淡入 + AvPlaylistBridge 本地零缝隙。与 §9 平台限制项同性质。

- **事实**：Android 有切歌交叉渐变（3 键：开关/淡入/淡出时长）；HarmonyOS 已有 `VolumeFader`（500ms 爆音防护），但无跨歌曲交叉渐变（AVPlayer 单实例限制）。
- **做法**：双 AVPlayer 实例轮换实现，或接受平台限制标注不做。**先做技术 spike 再承诺**。

## 3. 第三方音源（P0-P1）

### 3.1 YTM 播放闭环（回环代理未接入）⚠️

> **⏸ 阻塞于用户决策（2026-09-14 复核）**：D2 决策记录明确「在用户表态前不擅自接线」。现状：IOS 直出 URL 服务端只放行整轨前约 1 分钟（20 组实测 head=206/tail=403），三条路待用户抉择——(a) 接受 1 分钟试听并把回环桥接进生产链路；(b) 启用 M6.3 离屏 Web solver（约 200MB 常驻）追求完整播放；(c) 搁置 YTM 播放只留搜索/浏览。详见 `PORTING_EXECUTION_PLAN.md` D2/M6.5。

- **事实**：`YtmLoopbackStreamBridge.ets` + `YtmLoopbackHttp.ets`（为绕过 AVPlayer 对分块流 Range 限制自研）只被自身文件引用，播放器未接入；直连 googlevideo 直链约 1 分钟即 403。README 已如实标注演进中。
- **做法**：把 StreamResolver 对 YTM 的解析结果路由进回环桥；接通后真机验证 30 分钟以上连续播放；如仍不可行，评估 Android 的 PoToken/JS 解密路径在 ArkTS 的可行性（`YtmClientCatalog` 已有多客户端回退框架）。注意 `YTMUSIC_M60_SPIKE.md` 已有既有调研。

### 3.2 网易云 YRC 逐字歌词解析

> **✅ 已完成（2026-09-14，4038782）**：`LrcParser` 移植 `parseNeteaseYrc`（行级 `[start,dur]`+字级 `(ws,wd,0)` 自动识别、显式行尾、与 LRC 混排），`getLyric` 请求补 yv/ytv 并优先 yrc/ytlrc。Node 执行级验证+6 测试例。渲染端字级三态高亮本就存在（LyricView activeWordLine）。

- **事实**：全工程 grep `yrc` 零命中；Android `SyncedLyricsView.kt` 有 `parseNeteaseYrc`（正则 `[\d+,\d+](\d+,\d+,0)内容`）。HarmonyOS 逐字效果目前依赖 AMLL TTML 升级（`LyricDispatcher` 梯队 2），网易云原生逐字缺失。
- **做法**：`LrcParser` 或新文件补 YRC 行解析 → `LyricLine` 结构；补 fixture 单测；歌词请求处按可用性优先 YRC。

### 3.3 网易云登录补全（手机号+验证码）与 likeSong 双向同步

> **✅ 登录已完成（2026-09-14，5f6992b）**：`NeteasePhoneLogin`（验证码 verify→login / 密码 md5 登录）+ 设置页面板（模式切换/60s 倒计时/脱敏提示）。**未验证**：真实登录（需真机+真实手机号）。likeSong 红心同步仍留独立 spike（冲突策略需设计）。

- **事实**：HarmonyOS 仅扫码+Cookie 导入；Android 另有手机号密码/验证码（`loginByPhone`/`loginByCaptcha`）与红心同步（`likeSong`，`NeteaseLikeSyncPlan` 把本地收藏回写网易云）。grep 核实 HarmonyOS 侧均无。
- **做法**：手机号登录补 WeAPI 端点（weapi 登录加密已有基础）；likeSong 需要同步冲突策略设计（本地 favorites 与云端红心的双向合并），建议独立 spike。

### 3.4 网易云专辑/艺人详情页

> **✅ 已完成（2026-09-14，43c9d65）**：`getAlbumDetail`（weapi）/`getArtistSongs`/`getArtistHead` 三端点 + 新 `ArtistPage`（热门50/最新作品、点击起播、Router.ARTIST）+ AlbumPage 网易云专辑升级远端全曲 + SongItem.artistId 字段与「查看艺人」菜单入口。**未验证**：设备侧页面与接口。

- **事实**：HarmonyOS `AlbumPage` 仅聚合本地库；Android 有完整网络端艺人主页/单曲/专辑接口与页面（`NeteaseArtistDetailScreen` 等）。NeteaseApi.ets 无 artist/album 端点。
- **做法**：补 `/weapi/artist/{id}/song` 等端点 + 艺人页/专辑详情页路由。

### 3.5 下载伴生内容（歌词 sidecar + ID3 写入）

> **✅ 已完成（2026-09-14，aeb2031）**：`DownloadLyricSidecar` 下载完成后经 LyricDispatcher 全梯队取词写 `<audio>.lrc`（翻译同时间戳伴随行），删除下载同步清理伴生；`np.download_match_lyrics` 开关恢复（发布准备清单 2.4 恢复条件达成）。ID3 写入维持 sidecar 定案。

- **事实**：Android 下载完成后自动抓 `.lrc` 伴生歌词 + 封面，并用 TagLib 写回 ID3/FLAC 标签；HarmonyOS 仅下载音频本体 + `download_catalog.json` 编目。且 `np.download_match_lyrics` 开关存在但无消费者（见 `OPEN_SOURCE_RELEASE_PREPARATION.md` §2.4——该开关在发布准备轮先行隐藏）。
- **做法**：下载终态后调用 `LyricDispatcher` 抓歌词落 sidecar（`.lrc` 同名同目录），让 3.5 的开关真正生效；ID3 写入无公开 API（`RELEASE_CHECKLIST.md` §6 已定案 sidecar 承载），维持现状。
- **关联**：实现本项后恢复被隐藏的设置开关。

### 3.6 B 站高阶能力（合集/系列、SponsorBlock、匿名 buvid 防风控）

> **✅ buvid 已完成（2026-09-14，c811fc7+7a76f47）**：`ensureAnonymousFingerprint`（finger/spi 端点、登录态优先、1h 缓存）挂 search/resolveAudioUrl。合集/系列归档与 SponsorBlock 仍开放（低频）。

- **事实**：HarmonyOS 仅默认收藏夹（`resource/list`）+ 分页；Android 另有合集/系列归档（`getCollectionArchives`）、SponsorBlock 跳片段、未登录时自动种 buvid3/buvid4 防 -412 风控。grep 核实 HarmonyOS 侧均无。
- **做法**：buvid 注入优先（防风控是可用性问题）；合集解析补 endpoint + BiliFavPage 类型切换；SponsorBlock 评估社区 API 在 HarmonyOS 的接入成本。

### 3.7 QQ 音乐歌词偏移预设（2 键）

- Android 有 `cloud_music_lyric_default_offset_ms`/`qq_music_lyric_default_offset_ms` 平台级歌词基准偏移；HarmonyOS 仅有全局单一偏移。低频需求，P2。

## 4. 一起听（P1）

### 4.1 房间管理能力（3 项缺失）

> **✅ 已完成（2026-09-14，3f2d4e4）+ 审计澄清**：KICK_MEMBER/TRANSFER_HOST 在 Android 侧**并不存在**（本节原文为编制时误记，服务端亦从未支持）。真实缺口 UPDATE_SETTINGS 已实现：事件构造+房主守卫+下发+建房默认读偏好。

- **事实**：协议消息 `UPDATE_SETTINGS`（房主改权限）、`KICK_MEMBER`（踢人）、`TRANSFER_HOST`（转让）在 Android `ListenTogetherControlEventTypes.kt` 存在，HarmonyOS 对应文件无此三类（grep 核实）；服务端是否支持需同步确认（服务端为 Cloudflare Worker 独立部署，不在本仓库）。
- **做法**：客户端补消息类型 + `ListenTogetherPage` 房主操作 UI；服务端能力另行核对。

### 4.2 房间设置开关 UI（allow_member_control 等）

> **✅ 已完成（2026-09-14，3f2d4e4）**：房间页房主区三开关（乐观更新+UPDATE_SETTINGS 下发）+ 设置页「一起听房间默认设置」三开关（三个 np.listen_together_* 键自此有消费者）。**未验证**：设备侧与服务端（Worker 为外部部署）。

- **事实**：Android `listen_together_prefs` 有 `allow_member_control`/`auto_pause_on_member_change`/`share_audio_links` 键；HarmonyOS 设置页无房间选项入口。
- **做法**：与 4.1 一并做（同属房主权限面）。

## 5. 统计与历史（P1）

### 5.1 统计页深度（时间筛选/排序/艺人聚合）

> **✅ 已完成（2026-09-14，d0e9c18）**：`PlaybackStatsAggregator`（今日/7天/30天/1年/全部本地日历窗+次数/时长双排序+艺人聚合，纯函数 9 测试例）+ StatsPage 重写（范围 chip/三卡/歌手榜/前 100 曲目榜点击起播）。

- **事实**：HarmonyOS `StatsPage.ets` 仅 3 张静态卡片 + 最近 20 首（非频次排序）；Android `PlaybackStatsScreen.kt` 有日/周/月/年/全部切换、按次数/时长排序、艺人聚合、点击起播。
- **做法**：数据层（1.4 扩容后）按日桶聚合；UI 层补时间范围 Picker、排序切换、艺人维度 Group；条目点击起播复用现有队列能力。

### 5.2 历史页排序增强

> **✅ 已被既有实现覆盖**：历史页 2026-09-07 重做时已含按次数排序（`sortByCount`）。

- 原记录：Android 额外按播放次数排序。

## 6. 歌词引擎（P1-P2）

### 6.1 逐字渲染平滑扫光

> **⛔ spike 定案：维持现状（2026-09-14）**。连续扫光需 ≥30fps 进度驱动，而 positionMs 以 500ms 节流发布；字级三态切色在该节拍下已是可达上限。要做连续扫光须 RenderNode/Canvas 全自绘整行文本（换行/翻译行/字号字重联动全丢 ArkUI 文本能力）+ 独立高频时钟，代价与收益不成比例——视觉增强非功能缺失，与 Android 的差距按产品差异表述。

- **事实**：HarmonyOS `LyricView.ets` 逐字为字级三态（未唱/唱/已唱）切色；Android 为浮点进度连续扫光（`AnimatedOutlinedLyricTextView`）。视觉体验差距，非功能缺失。
- **做法**：Span 粒度做文字划线遮罩动画（ArkUI `Text` 无部分着色 API，可能需 `RenderNode`/Canvas 自绘）——先 spike 再排期。

### 6.2 平台级歌词偏移预设

> **✅ 已完成（2026-09-14，a756de2）**：三平台基准偏移键+滑杆，LyricView 全局+平台叠加（选行/拖词/Seek 全路径）。QQ 音乐源本侧不存在，键按网易云/B 站/YTM 落地。

- 见 3.7，归并此处执行。

## 7. 设置项补全（P2，共约 19 键可移植）

Android 126 键 vs HarmonyOS 69 键，其中约 30 键属平台限制不可移植（USB 13 键、均衡器/音效 8 键、悬浮歌词 16 键中的大部分、音频律动等）。**可移植的工程缺口**（分散于上文各节）：

| 键（Android 名） | 归属任务 |
|---|---|
| `keep_playback_mode_state`、`remember_long_form_playback_progress` | **✅ 前者完成（327d6a9）**；后者不移植（使用面窄） |
| `playback_crossfade_next` 等 3 键 | **⛔ 平台限制不做（spike 定案）** |
| `mobile_data_netease/bili/youtube_audio_quality` 等 6 键 | **✅ 已完成（a756de2）**：蜂窝分平台音质（follow 默认开关+三平台档位，effectiveForPlatform） |
| `bili_sponsor_block_enabled` | §3.6 |
| `netease_auto_source_switch`、`netease_local_source_fallback` | **✅ 开关已有**（SETTING_TRAFFIC 分区「网易失效自动换源」） |
| `cloud_music/qq_music_lyric_default_offset_ms` | **✅ 已完成（a756de2）**：三平台基准偏移滑杆 |
| `home_card_continue/trending/radar/recommended` 4 键 | 首页卡片开关（HarmonyOS 首页为固定布局） |
| `download_file_name_template` | 下载命名模板（sidecar 模式下收益有限，P2 末位） |

## 8. 本地音乐库（P2，差距最大的子系统）

### 8.1 现状与差距

- **现状**：`LocalMediaScanner.ets` 仅 `AudioViewPicker` 手动多选（限 500 文件），`AVMetadataExtractor` 只读 title/artist/album/duration，**封面字段置空**，不找同级歌词/封面文件。
- **Android**：SAF/MediaStore 全盘扫描、TagLib 精读 ID3/FLAC/MP4 标签与内嵌封面、同级 `.lrc`/`folder.jpg` 匹配、黑名单/时长过滤、MediaStore 观察者增量刷新。

### 8.2 平台可行性（先 spike 再承诺）

- 全盘扫描：HarmonyOS 沙箱下无公开通用存储读权限；`fileAccess`（用户授权 fileManager 域）或 `Picker` 目录授权（`DocumentViewPicker` 选目录 → 持久授权遍历）是两条候选路径，**须核对 API 26 可用性**（AGENTS.md：新 Kit/权限先查官方文档）。
- 内嵌封面：`AVMetadataExtractor` 是否暴露 `albumCover`/`userData`（API 26 `avMetadataExtractor.fetchMetadata` 键名需核对）；不可行则封面留空 + 首页占位图。
- 同级歌词：拿到目录句柄后 fs 读取同名 `.lrc`，纯逻辑可测。

### 8.3 任务拆分（按收益排序）

> **执行状态（2026-09-14，7b2cb18）**：①③④ 已完成——`LocalDirectoryScanner`（目录授权+递归枚举+同级 .lrc 挂载+下载编目回链+SchemaStore 持久化）与 LibraryPage 目录设置/扫描/播放入口；② 内嵌封面（`fetchAlbumCover`→PixelMap 落盘缓存）与观察者级实时刷新留后续。**未验证**：设备侧目录遍历（fileIo 对授权 URI 的 listFileSync 文档只承诺沙箱路径，需真机复核）。

1. 目录授权扫描（DocumentViewPicker 选目录 → 递归枚举音频 → 复用现有编目缓存）；
2. 内嵌封面提取（先探测 AVMetadataExtractor 能力）；
3. 同级 `.lrc`/封面匹配；
4. 增量刷新（重进页面 diff，不追求观察者级实时）。

## 9. 明确不移植项（平台限制，长期不做）

以下能力在 HarmonyOS 无公开等价物，**除非平台政策变化否则不进 backlog**（发布文案按「产品差异」表述）：

| Android 能力 | 不可移植原因 |
|---|---|
| USB DAC 独占输出 / Bit-Perfect（C++/libusb） | 无公开 USB DDK 等时传输；已定案（`USB_M91_SPIKE.md` 调研） |
| 系统级桌面悬浮歌词 / 状态栏歌词 | 无悬浮窗权限与状态栏 API；已有应用内降级（D4 决策） |
| 均衡器 / 响度归一化 / 声道平衡 / 变调不变速 | AVPlayer 无音频处理管线（`playback_pitch` 变调亦依赖此） |
| 音频律动响应背景（AudioReactive） | 同上，无 PCM 抓取通道 |
| 蓝牙 AVRCP 歌词推送到车机 | 系统蓝牙栈不暴露；AVSession 歌词字段是现有等价物 |
| FFmpeg 扩展解码（小众格式） | AVPlayer 硬解覆盖面已足；引入 native FFmpeg 违背零依赖架构 |

## 10. 执行建议（排期序）

1. **第一波（跨端价值）**：1.1 SongIdentity → 1.2 sourceStableKey → 1.4 日桶扩容 → 1.3 Protobuf 写出。这一波做完，「GitHub/WebDAV 跨端同步」这个核心卖点才真正成立。
2. **第二波（体验补齐）**：3.2 YRC → 2.1 URL 重签 → 5.1 统计页 → 3.5 下载歌词 sidecar → 4.1/4.2 一起听房间管理。
3. **第三波（长尾）**：3.6 B 站高阶 → 3.3/3.4 网易云补全 → §7 设置键 → §8 本地音乐库（含 spike）→ i18n。
4. 每项完成按 `PORTING_EXECUTION_PLAN.md` §6 惯例登记证据行，`docs/FEATURE_MATRIX.md` 同步更新状态。
