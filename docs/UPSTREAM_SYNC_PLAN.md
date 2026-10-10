# 上游增量分析与移植规划（2026-10-10）

本文是 Android 上游（`github.com/cwuom/NeriPlayer`，master）相对鸿蒙移植基线的**全量增量分析**，产出待办清单与执行波次规划。数据来源：GitHub REST API 匿名拉取（2026-10-10，master 末次推送 2026-10-08 23:38）；鸿蒙侧现状经 5 项只读代码核查（2026-10-10，静态走查，非设备验证）。

## 0. 基准与方法

- 移植基线：`d66d465f48a6ae911fef0de88d2d21937760f31d`（2026-07-31，本地 `NeriPlayer-master/` 只读快照，见 PROJECT_AUDIT.md）。
- 截至 2026-10-10：上游 master 领先基线 **275 提交**（约 90 个已合并 PR + 早期直推），另有 3 个 open PR（#506/#507/#508）。
- 分类规则（沿上游日报会话定稿）：
  1. 领域归属仅用 PR/commit 元数据（scope/标题），不做文件路径对照；
  2. 「鸿蒙是否有同类问题」以鸿蒙现行代码与 FEATURE_MATRIX 为准；
  3. 基线**之后**新增的功能即使领域相近也归「移植候选」，不算修复。
- 鸿蒙侧已覆盖模块锚点：播放器/队列、歌词、下载、GitHub/WebDAV 同步、一起听、网易云/B站/YTM 适配、歌单、本地媒体、设置（详见 FEATURE_MATRIX.md）。

## 1. 总览

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| A-已核查·无同类缺陷 | 9 组 | 队列/随机四修、WebDAV 租约、删除墓碑合并、HLS checkpoint 兼容、下载歌曲远端身份等（§7，防重复审计） |
| A-已核查·存在缺口 | 8 项 | WebDAV 非原子发布、404 分类、下载目录切换 4 缺口、离线恢复误判、音译无回退、封面编辑无门禁、统计计数口径、粘贴无尺寸防护（§2/§3） |
| A-待审计 | 14 项 | 伞形 PR 与单点修复的逐项核对（§3.3） |
| B-功能移植候选 | 13 组 | 评论模块、队列编辑接线、歌词源偏好、网易云写回、一起听增强等（§4） |
| C-不计划移植 | 9 组 | USB/DSP/Android Auto/OEM 歌词/CI/Room 迁移等（§5） |
| D-在途观察 | 3 PR | #506/#507/#508（§6） |

## 2. P0：数据安全与互操作（建议最先排期）

### 2.0 人话速览（非技术向）

**① 两边的「备份文件格式」分家了（ZSTD 互操作）**
NeriPlayer 有个备份同步功能：把你的歌单、播放历史打包存到你自己的网盘（WebDAV）或 GitHub 上，换手机、多设备就能互相同步。Android 上游 10 月初把这个「打包格式」整个换成了新格式（ZSTD 归档 v4），而鸿蒙版只会读写两种老格式。后果：一个人如果 Android 手机装新版、华为手机装鸿蒙版、两边用同一个网盘地址同步——Android 存的备份鸿蒙读不懂，鸿蒙存的 Android 新版也可能不认，就像一个用新版 Word 存 .docx、一个还在存老 .doc，互相打不开对方的文件。麻烦在于鸿蒙系统没有现成的 ZSTD 解压工具，得先去上游把新格式的细节摸清楚，再决定自己写解压、加底层库、还是至少做到「认出这是新格式并友好提示」——所以第一步是调研，不是直接改代码。

**② 网盘备份的两个毛病（WebDAV 发布与报错）**
- **传一半断掉会留坏备份**：鸿蒙版往网盘写备份是「直接对着正式文件覆盖写」。要是传到一半断网或 App 被杀，网盘上就留下半个坏文件，下次同步可能把它当真备份用。稳妥做法是「先传临时文件，传完再一步改名顶替正式文件」，中途断掉也不伤原备份。（「别人改过就不覆盖」的保护鸿蒙已有，缺的只是这层。）
- **报错张冠李戴**：连不上网盘有两种完全不同的情况——「目录地址填错了」和「还没同步过所以备份文件本来就不存在」。鸿蒙版现在两种都提示同一句「远端暂无备份文件（首次同步时将创建）」。用户明明是地址填错，看到的却是「正常现象」，被误导。

**③ 下载换目录的坑 + 断网重启误报**
设置里可以改下载保存目录（比如从应用默认目录改到「下载/音乐」）。核查发现这块有一串坑：
1. 换目录时啥也不检查，目录能不能写入要等一次完整下载跑完才暴露；
2. 下载最后一步失败时，界面只显示「失败」两个字，不说原因、不弹提示；
3. 从目录 A 换到目录 B 后重启 App，A 目录的授权没被激活——之前下到 A 的歌点播放会悄悄失败、转头去走在线流量（你以为在播本地文件）；
4. 换了自定义目录后，同一首歌再下载会「不认得已经下过」又下一遍，旧文件还留着变垃圾。
另有一个独立坑：断网时正在「等网络」的下载任务，重启 App 后会直接变成「失败」，而不是继续等网络恢复。

### 2.1 同步格式 ZSTD v4 互操作 spike（上游 #475，`feat!` 破坏性）

上游把同步格式升级为 **ZSTD 归档（v4）**，含协议升级审批绑定同步目标与内容指纹、遗留数据保全（歌词/统计/无损 v4）、归档工作区回收、WebDAV 发布对账。鸿蒙侧现状（已核查）：只写 JSON / GZIP(Protobuf)，读 JSON / gzip-proto / legacy Base64(proto)，**全仓无任何 ZSTD 代码**；WebDAV 固定文件名 `neriplayer-sync.json`，GitHub 侧按 `backup.json`/`backup-raw.bin`/`backup.bin` 候选回退读取（`sync/SyncDataJsonCodec.ets:1665-1763`、`sync/github/GitHubSyncClient.ets:27-72`）。

- 风险：Android 新版与鸿蒙共用同一 WebDAV/GitHub 备份仓库时可能互不可读（具体取决于上游 v4 的文件名与容器细节，未核实）。
- 行动（调研 spike，不动代码）：
  1. 拉上游 #475 合并后源码，确认 v4 归档的文件名、容器结构、嗅探策略、旧格式读取回退顺序；
  2. 评估鸿蒙侧 ZSTD 解压路径：SDK 无 zstd API，选项为纯 ArkTS 解码器（zstd 解压复杂度高）或 native 模块（工程当前无 native 依赖）或「只保证写旧格式 + 读 v4 元数据识别并提示」的降级方案；
  3. 结论回填本文档并单独立项。
- 顺带核对 #475 内 `fix(player): bound the durable playback statistics journal`（统计 journal 上限）与 `fix(sync): preserve concurrent usage changes and lyric match state`（并发 usage 变更与歌词匹配态保全）在鸿蒙的对应面。

### 2.2 WebDAV 发布原子性与错误分类（上游 #495/#491/#468/#499）

**状态：已完成（2026-10-10，commit 5379bf5，分支 fix/upstream-sync-p0-p1）**。已核查的两个鸿蒙侧真缺口均已修复，实现要点与残余风险：

- **发布原子性**：`uploadBackup` 改为「GET 前置校验 → PUT 临时名（指纹前缀+计数器唯一化）→ MOVE 覆盖」两阶段发布；MOVE 被服务器拒绝（403/405/501）时清理临时文件并降级为原条件 PUT 路径。发布前 GET 校验远端指纹/并发令牌与合并基线一致，不一致照旧抛 `CONTENT_CONFLICT` 由协调器重试闭环消化（vanish/已存在/指纹变化三场景均有单测）。残余风险：并发校验窗口从「条件 PUT 原子校验」变为「验证→MOVE 间隔」（与旧指纹回退路径同量级），落败方的下次同步经指纹比对重新合并，不丢数据；另 OhosWebDavExecutor 方法路由已泛化（MOVE/DELETE 走 customMethod）。**未做真机 + 真实 WebDAV 服务器实测**（本机无设备），单测编译级 0 error。
- **404 分类**：新增 `DIRECTORY_INVALID` 错误类；PROPFIND 目录探测 404/409/410 单独归类（不再误入 `FILE_NOT_FOUND`/`CONTENT_CONFLICT`）；共享中文文案 `describeWebDavErrorForUser`；`syncWebDav` 与「检查远端备份」前置目录预检，目录配错时提示「请检查目录配置」。

无行动项：LOCK/UNLOCK 租约机制鸿蒙不用（上游 #491/#495 的锁清理问题不适用）。

### 2.3 下载目录切换与恢复缺口（上游 #473/#484/#499 同域）

**状态：已完成（2026-10-10，commit 2a072b0，分支 fix/upstream-sync-p0-p1）**。已核查的 6 个缺口全部修复：切换目录前写探针校验（不可写当场拒绝、保留原目录）；commit 失败经 failTask 带 reason+日志并在下载页显示中文原因；新增 `np.download_directory_history`（去重、上限 8 条）冷启动对当前+历史目录逐个 activatePermission；`fileSize`/`hasPlausibleAudioHeader`/`hasExcessiveFillerRuns` 入口统一 `resolveFilePath`（file:// 编目不再被 stat 成 0，同时修复设置页/DebugPage 存储统计）；离线冷启动与 URL 解析失败保持/转入 WAITING_NETWORK 而非 FAILED；netUnavailable 置等待后 hasNetwork 复核防事件乱序卡死。**真机行为（picker 探针、历史授权激活、离线恢复）未验证**，需 Windows 工作站 + 设备跑 ohosTest 与手工 smoke。原核查记录：

1. **新目录零校验**：切换下载目录只持久化授权+写设置，无写入探针，失败推迟到 commit 才暴露（`download/DownloadDirectoryManager.ets:52-90`）。
2. **commit 失败静默**：`finalPath` 为空直接置 FAILED，无 reason、无日志、无 toast（`download/DownloadEngine.ets:546-551`）。
3. **旧目录授权失效**：冷启动只激活当前 URI 的授权，自定义目录 A→B 后 A 下编目行打不开，离线播放静默回退网络流（`DownloadDirectoryManager.ets:97-109`）。
4. **缓存短路失效**：命中判断未过 `resolveFilePath`，自定义目录 `file://` URI 的 stat 归 0 → 重复下载 + 旧文件成孤儿（`DownloadEngine.ets:235-251`；同类遗漏还有 `SettingsDetailPage.ets:292`、`DebugPage.ets:147` 的存储统计）。
5. **离线冷启动误判失败**：`WAITING_NETWORK` 落盘后重启一律按 QUEUED 重入队，离线启动时 URL 解析失败直接 FAILED 而非继续等网（`DownloadEngine.ets:253-274`、`:424-436`）。
6. netUnavailable 事件与启动恢复存在竞态（`DownloadEngine.ets:622-658`）。

HLS checkpoint 恢复（上游 open PR #508 的 operationId 问题）已核查**鸿蒙无此缺陷**（纯内容派生键，`download/DownloadEngine.ets:450-458`）；「legacy 升级等待状态/目录索引」（#484）属 Android Room 迁移路径，鸿蒙无对应架构。

## 3. P1：修复同步项（核心体验对齐）

### 3.1 已核查·存在缺口，可直接立项

| # | 上游来源 | 鸿蒙现状（2026-10-10 核查） | 行动 |
| --- | --- | --- | --- |
| P1-1 | #483 音译回退网易云 | 首选源缺音译无任何回退：LRCLIB 路径翻译恒空且无音译；AMLL 升级是整体替换，丢掉网易云已取到的翻译+音译；`matchedLyric` 分支终生无音译（`lyrics/LyricDispatcher.ets:27-66`） | **已完成（2026-10-10，commit 2ad4ec2）**：matchedLyric 分支持久化并合并音译（matchedPhoneticLyric）；LRCLIB 缺翻译/音译或空命中时回退网易补齐（会话缓存 50 条，失败静默）。注意核查基线中 AMLL 升级一项已随 AMLL/TTML 模块删除而不复存在 |
| P1-2 | #417 时长匹配守卫 | 网易/LRCLIB 主结果无任何时长校验（仅 YTM→AMLL 严格模式有） | **已完成（2026-10-10，commit 2ad4ec2）**：跨源回退经 SongMatchScorer（±8s 容差+漂移拒绝+阈值 70）守卫；LRCLIB 响应 duration 偏差超 8s 丢弃 |
| P1-3 | #499 `keep counting listened time after a mid-track interruption` + 29c8d86e 统计口径 reconcile | `playCount` 每次 flush +1（暂停/恢复同曲记 2 次）；`listenedMs` 崩溃丢失窗口；「全部」与各区间口径天然不一致（`data/PlaybackStatsRepository.ets:35-70`、`sync/PlaybackStatsMergePolicy.ets`） | **已完成（2026-10-10，commit a26891a）**：recordPlay 拆中继（暂停/中断只落 listenMs）与终结（换曲/播完才计次）语义，ohosTest 补用例（待设备执行）；口径不一致维持「已知行为」不另行处理 |
| P1-4 | #499 `stop failure auto-advance at the consecutive limit` | PlaybackFailurePolicy 只有队列绕完一圈才停，连续多曲失败会逐曲跳完（`player/PlaybackFailurePolicy.ets`） | **已完成（2026-10-10，commit f9e8654）**：MAX_CONSECUTIVE_FAILURES=10（已核对上游 master modules/playback PlayerManager.kt 与 #499 提交 651bc570 的确切数值与「真正出声才清零」语义），长队列第 10 次连续失败停止；鸿蒙 playing 状态即出声，清零时机语义等效 |
| P1-5 | #368 封面替换仅限非远端歌 | `customCoverUrl` 编辑/匹配写回对所有平台歌曲生效，无本地门禁（`view/pages/NowPlayingPage.ets:465-472`、`data/LocalPlaylistRepository.ets:505-536`） | **已完成（2026-10-10，commit 4ac53b4）**：编辑面板对在线歌隐藏封面输入+文案引导走匹配；保存防线保留匹配流程写入值；匹配面板/自动匹配器不受影响 |
| P1-6 | 5fe1a3f8 超长载荷防护 | 粘贴 Cookie 对话框 TextArea 无 maxLength、parser 无总长上限（鸿蒙不读剪贴板，风险低于上游） | **已完成（2026-10-10，commit b20ea99）**：parser 上限 32768 超限解析为空 + 对话框 maxLength/导入拦截 + Token 输入 maxLength 1024 |
| P1-7 | #499 `honor the cache size setting` / #327 无上限缓存 | 播放缓存 LRU 固定 24 条，无容量设置（`player/PlaybackCacheLedger.ets`） | **已完成（2026-10-10，commit f4438d8）**：np.playback_cache_max_entries（默认 24、0=无上限）+ 设置页档位行 + 调低立即收缩；存储分析页仍留 F-8 |

### 3.2 功能缺口但属「候选」（转 §4）

- 搜索无分词/拼音排序（#371 camelCase 边界、bf50094e 拼音排名）；搜索历史已有但无滚动隐藏交互。
- 歌单删除无撤销（90ee4f46）；歌单导出确认防抖待核对。

### 3.3 待审计清单（未核查，立项前先核对鸿蒙是否有同类问题）

| # | 上游来源 | 审计问题 |
| --- | --- | --- |
| A-1 | #499（100 提交伞形，本表只列已知相关的） | `fix(download): tolerate whole-second source durations in integrity check`——鸿蒙 isPlausibleAudioHead 只查魔数，时长容差是否需要？ |
| A-2 | #499 | `fix(auth): keep credentials when the Keystore master key is unusable`——鸿蒙 Asset 分块存储解密/恢复失败时是否会丢凭据？ |
| A-3 | #401 静默流停顿恢复 | 鸿蒙是否检测「播放中进度长期不推进」的静默停顿（PlaybackFailurePolicy 只处理显式失败）？ |
| A-4 | #408 缓存描述符 null 保留 | 播放缓存账本字段 null/缺省的往返是否保真？ |
| A-5 | #345 DataStore 陈旧快照优先级 | 设置读取路径是否存在「内存缓存值覆盖已落盘新值」的竞态？ |
| A-6 | da072b1a/53e44b54/#312 网络状态判定 | hasNetwork 只在传输失败后查询（已见 DownloadEngine）；离线模式误判、直连传输豁免类问题需统一审计 |
| A-7 | #383 网易云搜索可用性与 cookie 使用 | 搜索接口带不带登录 cookie 的策略与上游对齐度 |
| A-8 | 37535ea0 QR 轮询后台暂停 | QrLoginPanel 页面隐藏/后台时轮询是否暂停 |
| A-9 | d5435320 网易云 QR 对齐官方流程 | 鸿蒙 QR 链路已多轮重做（见 FEATURE_MATRIX），仅复核 unikey 端点/轮询节奏与上游当前实现的差异 |
| A-10 | #389 歌词分享位图复制 | LyricShareSheet 的 PixelMap 生命周期（Canvas 绘制后是否被提前回收） |
| A-11 | #351 Continue 区封面解析持久化 | 本地歌单封面解析结果是否落盘，重启是否重算 |
| A-12 | b623f200/e1ea77be 同步封面映射 | 本地文件引用是否会被错误写进同步的 coverUrls/下载候选 |
| A-13 | #396 本地媒体加固伞 | 目录扫描的恢复/元数据边界（sidecar 已做，其余逐项对） |
| A-14 | #487 B站评论分页到底误报 | 随评论模块移植时一并处理（模块未移植，暂无对应面） |

## 4. P2：功能移植候选（基线后上游新增）

> 移植任何一项前注意：`NeriPlayer-master/` 快照停在基线，**这些功能的 Android 源码不在本地参照里**，需先拉上游对应模块源并记录 SHA（见 §8）。

| # | 功能 | 上游来源 | 鸿蒙衔接点与备注 | 建议波次 |
| --- | --- | --- | --- | --- |
| F-1 | 「下一首播放」插入 + 队列拖拽排序 UI | 90ee4f46/#482 + 队列引擎死代码 | **已完成（2026-10-10，commit 6a140b8）**：QueueEngine.applyQueueEdit/currentIndexAfterRemoval 接线，PlayerManager insertNext/addToQueueEnd/moveQueueItem/removeQueueItem（语义镜像上游 d062d23ee9 addToQueueNextImpl/EndImpl 与 PlayerQueueEditOwner），队列面板 ForEach.onMove 原生拖拽 + 行尾 ⋮ 菜单，SongRow 菜单加「下一首播放」「加入队列」，8 个引擎单测；拖拽手势待真机冒烟 | 早（成本低、收益直接） |
| F-2 | 歌词域波次：源偏好设置（Kugou/LRCLIB/AMLL 默认偏移、偏好源先行、缓存先行显示）+ 翻译/音译快捷切换 + 歌词持久化缓存 | #417/#427/#349/#483/#507 | **已完成（2026-10-10，commit affc04c）**：LyricCacheStore（SchemaStore LRU 缓存表，200 条）+ loadLyricsResolved 缓存先行 + netease_first 优先源设置 + LRCLIB 源基准偏移 + 9 单测；#483 补齐与翻译/音译切换此前已在 P1-1/既有「多行歌词」胶囊覆盖；AMLL/Kugou 源鸿蒙不存在故不移植 | 早 |
| F-3 | 评论模块（网易云/B站原生评论、三态面板、楼中楼点赞） | #432/#476/#487 | 全新模块（数据层+UI），体量大，独立立项 | 中 |
| F-4 | 网易云歌单写回（选择器+同步到自建歌单） | #322 | 与既有镜像歌单（单向读）互补为双向 | 中 |
| F-5 | 网易云推荐扩展（雷达歌单、个性化元数据、每日推荐缓存） | #319/#338/390 | 首页/探索页扩展；390 的并行加载 perf 一并参考 | 中 |
| F-6 | 一起听增强：权威取流/队列变更版本化/控制事件合并/成员离场自动暂停/卡死连接超时恢复/邀请链接加入 UI | #359（20 提交）/#318/89a8694c | M7 核心闭环后的稳健性波次；#318 音频路由丢失时静音而非暂停对 AudioInterruptPolicy 有直接参考 | 中 |
| F-7 | YTM 创作者主页 + B站 UP 主空间/合集/系列 + B站链接解析（分P/合集/season_id） | #341/4c085185 / e95b2ef9/507c22d7 / a8440275/1dbb2964 | 适配器层扩展，各自独立 | 中 |
| F-8 | 存储空间分析页 + 缓存容量档位（含无上限） | #328/#335/#327 | **已完成（2026-10-10，commit 14422e0；容量档位部分此前已随 P1-7 于 f4438d8 落地）**：StorageUsageAnalyzer 六桶分析 + 设置「存储与缓存」分区重写（分桶明细/重扫/清除播放缓存/歌词缓存/诊断记录），StorageBytes 单测；真机扫描数值待验证 | 中 |
| F-9 | 搜索 UX 波次：歌单现代搜索 UI+历史+拼音排序+分词、探索分页与链接识别、滚动隐藏历史、搜索结果歌曲操作 | dfa37db0/9a38f4c5/bf50094e/#371/e947409a/c5a95707/dddaa0b4/cecaa6df | 需拼音库评估（纯 ArkTS 拼音表或系统 API） | 中 |
| F-10 | 歌单删除撤销 + 历史导出确认防抖复核 | 90ee4f46/b4075e10/2cd50545 | **已完成（2026-10-10，commit 240c7ca）**：仓库级快照/恢复（含跨端墓碑与镜像 skipKeys 回退）+ UndoBanner 横幅（歌单删除→资料库页、单曲移除→详情页）+ 备份导出/导入双击防抖（复核确认鸿蒙侧原无守卫）；撤销交互待真机验证 | 小型 UX 波次 | 晚 |
| F-11 | 多步引导/免责流程重做 | 01c57a11 等 | 鸿蒙启动/免责当前为「原型」级，参照上游多步设计 | 晚 |
| F-12 | 桌面卡片（HarmonyOS FormKit，非直接移植 Android widget） | #472 | 需按鸿蒙卡片体系独立设计，Android 侧仅作功能参照 | 晚 |
| F-13 | 杂项 polish：MiniPlayer 字号自适应(#357)、波形进度预测(#337)、播放控制布局定制(2644267f)、歌词翻译行距 kana 检测(15f07073)、翻译折叠(#392) | 各分散 | 择机合并入相邻波次 | 晚 |

已在鸿蒙独立完成、上游同类改动仅作对照（不立项）：音量淡入(#313，鸿蒙默认开属有意偏离)、跑马灯(91e674c0/466b6dff)、动态取色(2dc63b97/f0c0b64c)、.lrc 伴生歌词(#343/#323 已覆盖主路径，翻译伴生文件可并入 F-2)、平板适配(#493，鸿蒙方案独立)、桌面歌词（走 AVSession 系统能力，M10.2）。

## 5. 不计划移植（C 类）

| 项 | 上游来源 | 理由 |
| --- | --- | --- |
| USB 独占输出强化 / USB DAC / UsbExclusiveAudioSink | #502/#386/bba09cbf/`perf(usb)` | M9.1 spike 定案不移植（docs/USB_M91_SPIKE.md） |
| 原生 DSP 音效（10-band EQ/AutoEq/per-output profiles） | #502 | AVPlayer 不暴露 DSP 链；若远期做需 AudioRenderer/native 路线，成本高收益窄，挂远期不排期 |
| Android Auto / 车载蓝牙浏览 | #488 | 平台无对应（蓝牙元数据经 AVSession 已覆盖） |
| OEM 状态栏歌词（小米超级岛/魅族/Lyricon/灵动岛） | #434/#474/#393/#377/#369/188daf8f | 鸿蒙走 AVSession 桌面歌词系统通道（M10.2 已验证到服务层），OEM hack 不适用 |
| 预测返回手势 | #506（部分） | Android 13 特性；鸿蒙返回由系统 Navigation 栈管理 |
| 官网/CI/Gradle/模块化重构/CRAP 门禁 | #501/#443/#444/#450/#464/#467/#447/#446/#441/#439/#440/#478(部分)/#465/#466 | 构建与工程基建，鸿蒙侧有自己的 CI 与架构约定 |
| Room 持久化迁移波（约 20 提交）与 legacy JSON 升级 | 2026-08-08 系列/#316/#484 | Android 存储架构迁移；鸿蒙用 SchemaStore/preferences，语义教训（增量写、审计式清理）已在鸿蒙数据层设计中考量 |
| i18n 中文本地化 | #380 | 鸿蒙侧中文优先 |
| OnePlus 缩放/高刷新率等设备特调 | b3e03fd1/d5959892 等 | Android 设备碎片化适配 |
| Android 玻璃/overscroll/主题动效细节 | #306/#308/#311/overscroll 系列 | 鸿蒙有 HDS 光感体系，自成一派 |

## 6. 在途 PR 观察（合并后再筛）

- **#506**（open，258 提交/580 文件）：稳定性大杂烩——下载看门狗（f16c8ac39）、SAF 双后缀修复（f6e246a52）、同步/一起听修复、通知栏歌词（3a3f97c7c）、预测返回、平板 polish。合并后按 §0 规则重筛一遍，下载看门狗/双后缀与鸿蒙下载引擎可对照。
- **#507**（open）：歌词翻译匹配容差——并入 F-2 歌词波次跟踪。
- **#508**（open）：legacy HLS checkpoint 续传——已核查鸿蒙无此问题，关闭观察。

## 7. 已核查确认无需行动的记录（2026-10-10，防重复审计）

1. **队列/随机四修**（e1882e38/1b006589/14ae0dcf/f7d224a3）：鸿蒙随机在索引层实现、歌曲数组永不被置换、展示层从不排序，结构性免疫；Repeat All 重洗在普通/自然结束/失败重试/原生无缝四条路径均已实现且有单测。唯一遗留：插入/拖拽算法是死代码（→ F-1 接线，接线时需补集成层测试）。
2. **WebDAV LOCK 租约**（#491/#495 锁清理部分）：鸿蒙不用 LOCK，乐观条件写+指纹复核+冲突重试已完备。
3. **歌单/usage 删除墓碑与合并稳定性**（#350/37fbf74b）：墓碑+causal token+确定性比较器已实现，测试充分（undo 未移植属 F-10 候选）。
4. **「最后同步时间」播放期间刷新**（#480）：自动同步成功即刷新；鸿蒙侧该时间甚至无 UI 展示位（可作 F-8 顺带小改进）。
5. **HLS checkpoint 向前兼容**（#508）：纯内容派生键（playlistFingerprint+字节数），与 Android 基线同构，无 id 门禁。
6. **已下载歌曲保留远端身份**（fc013a94）：sourceStableKey 回链已实现且有跨端单测。
7. **载荷校验入库口**（#499 相关）：isPlausibleAudioHead + filler 扫描挂满三个入库口。
8. **本地 AAC/MP3 播放**（#469）：鸿蒙 5400106 系列（fdSrc 直赋）已修，标记待真机复核即可。
9. **一起听核心链路**：建房/加入/同步/重连/邀请已双端设备闭环（M7.5），#359 属增强而非缺陷（→ F-6）。

## 8. 参照快照升级策略

`NeriPlayer-master/` 停在基线 `d66d465f`。移植 §4 任一功能前需上游源码作行为参照，二选一：

- **方案 a（推荐）**：单项移植时临时 `git fetch upstream` 到工作区外目录读取对应模块，任务记录中注明 commit SHA（不动 `NeriPlayer-master/` 快照）；
- **方案 b**：一次性把快照升到指定 commit（建议等 #506 合并后选稳定点），按 AGENTS.md 记录 SHA/日期/许可证，并重跑快照只读性检查。

快照升级本身是独立任务，不与功能移植混做。

## 9. 维护规则

- 本文按「上游新增提交 → §0 三分工 → 对应章节增行」增量维护；每次维护在文首注明数据截止日期。
- 状态用词遵守仓库规范：「已核查（静态）」/「待审计」/「待真机复核」，不写「已验证」除非有设备证据。
- 完成一项 P0/P1 后：勾掉待办、在对应行补「已完成 + commit」、必要时同步 FEATURE_MATRIX。
