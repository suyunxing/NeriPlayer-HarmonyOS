# 上游增量分析与移植规划（2026-10-10 初版；2026-10-15 第二轮维护）

本文是 Android 上游（`github.com/cwuom/NeriPlayer`，master）相对鸿蒙移植基线的**全量增量分析**，产出待办清单与执行波次规划。数据来源：GitHub REST API 匿名拉取（2026-10-10，master 末次推送 2026-10-08 23:38）；鸿蒙侧现状经 5 项只读代码核查（2026-10-10，静态走查，非设备验证）。

**2026-10-15 第二轮维护**：重拉上游确认 §6 三个在途 PR（#506/#507/#508）已全部合并（#506 于 2026-10-10、#508 于 2026-10-12、#507 于 2026-10-13）；随后上游又新合入 #510/#516/#519/#522/#523/#524/#526（master HEAD `5c6aca42d`，2026-10-14）。本轮按 §0 三分工把这批增量归入 §3.3/§4/§5/§6，均只做元数据归类，**未做鸿蒙侧代码核查**（标「待审计」）。

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
| A-已核查·无同类缺陷 | 10 组 | 队列/随机四修、WebDAV 租约、删除墓碑合并、HLS checkpoint 兼容、下载歌曲远端身份、#508 legacy checkpoint（2026-10-15 复核）等（§7，防重复审计） |
| A-已核查·存在缺口 | 8 项 | WebDAV 非原子发布、404 分类、下载目录切换 4 缺口、离线恢复误判、音译无回退、封面编辑无门禁、统计计数口径、粘贴无尺寸防护（§2/§3，均已修复） |
| A-待审计 | 23 项 | 伞形 PR 与单点修复的逐项核对（§3.3；2026-10-15 新增 A-15~A-24 元数据归类） |
| B-功能移植候选 | 14 组 | 评论模块、队列编辑接线、歌词源偏好、网易云写回、一起听增强、DSP 电台站点等（§4） |
| C-不计划移植 | 9 组 | USB/DSP/Android Auto/OEM 歌词/CI/Room 迁移等（§5） |
| D-在途观察 | 4 PR | #511/#525/#527/#528（§6；#506/#507/#508 已合并并重筛完毕） |

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
| A-14 | #487 B站评论分页到底误报 | 已随 F-3 评论模块移植处理（BiliCommentRepository 全零分页与空页未读完按 API 错误抛），核对后销项 |
| A-15 | #506 `fix(sync): checkpoint merges at the remote observation time` | 同步合并 checkpoint 时间取远端观察时刻——鸿蒙合并基线/冲突重试的时间戳语义是否一致 |
| A-16 | #506 `fix(local): let a downgraded app re-read the remote instead of blocking on newer sync markers` | 遭遇更高版本同步标记时鸿蒙是否死锁拒绝读取；本地媒体目录扫描遇不可解码条目是否整单失败（#506 同伞 `skip undecodable playlist members`） |
| A-17 | #506 `fix(player): keep media session metadata publish from killing the service` + `refresh notification lyrics on stock system UI` | AVSession 元数据发布异常是否会击穿播放服务；通知栏歌词刷新（鸿蒙走 AVSession 桌面歌词通道，对照语义即可） |
| A-18 | #506 `fix(local): load usage, history and traffic stores off the constructor thread` + `stop id3 parsing at frame sizes that overflow the tag` | 数据仓库构造期同步 I/O 是否阻塞 UI 线程；本地 ID3 解析对超大帧尺寸的截断防护 |
| A-19 | #516 `perf(sync): speed up synchronization and restore startup readiness`（2 提交：加速同步+恢复启动就绪、usage 观察者恢复） | 鸿蒙同步协调器启动路径是否有同类慢启动/观察者丢失面；并行读测试稳定性教训对照 |
| A-20 | #519 `fix(playback): prevent silent transitions and stale recovery` | 播放状态「静默切换」（无声但状态机认为在播）与陈旧恢复——与 A-3 静默停顿同域，可合并审计 |
| A-21 | #522 `fix(lyrics): keep loaded lyrics when reopening now playing` | 重开播放页时鸿蒙是否重复请求/闪空歌词（F-2 歌词缓存先行应已覆盖，核对后可销项） |
| A-22 | #523 `fix(playback,sync): keep Bluetooth disconnects silent and sync with Nutstore`（2 提交） | 蓝牙断连是否触发误暂停/误报错（AVSession 输出切换语义）；迟到扬声器重路由后的二次确认 |
| A-23 | #524 `fix(sync): sync with WebDAV servers that lack strong ETags (Nutstore)`（2 提交：无强 ETag 同步、未加引号 ETag 条件发布） | **高优先**：鸿蒙 WebDAV 原子发布（5379bf5）依赖条件写/MOVE，坚果云类无强 ETag 服务器上条件校验是否退化失效；If-Match/ETag 引号形态处理 |
| A-24 | #510 `feat: add optional floating lyric previews and wrapping` | 悬浮歌词预览与换行——鸿蒙走 AVSession 桌面歌词系统能力（M10.2），应用内自绘悬浮窗路线与 OEM 限制一并评估，倾向 C 类 |

## 4. P2：功能移植候选（基线后上游新增）

> 移植任何一项前注意：`NeriPlayer-master/` 快照停在基线，**这些功能的 Android 源码不在本地参照里**，需先拉上游对应模块源并记录 SHA（见 §8）。

| # | 功能 | 上游来源 | 鸿蒙衔接点与备注 | 建议波次 |
| --- | --- | --- | --- | --- |
| F-1 | 「下一首播放」插入 + 队列拖拽排序 UI | 90ee4f46/#482 + 队列引擎死代码 | **已完成（2026-10-10，commit 6a140b8）**：QueueEngine.applyQueueEdit/currentIndexAfterRemoval 接线，PlayerManager insertNext/addToQueueEnd/moveQueueItem/removeQueueItem（语义镜像上游 d062d23ee9 addToQueueNextImpl/EndImpl 与 PlayerQueueEditOwner），队列面板 ForEach.onMove 原生拖拽 + 行尾 ⋮ 菜单，SongRow 菜单加「下一首播放」「加入队列」，8 个引擎单测；拖拽手势待真机冒烟 | 早（成本低、收益直接） |
| F-2 | 歌词域波次：源偏好设置（Kugou/LRCLIB/AMLL 默认偏移、偏好源先行、缓存先行显示）+ 翻译/音译快捷切换 + 歌词持久化缓存 | #417/#427/#349/#483/#507 | **已完成（2026-10-10，commit affc04c）**：LyricCacheStore（SchemaStore LRU 缓存表，200 条）+ loadLyricsResolved 缓存先行 + netease_first 优先源设置 + LRCLIB 源基准偏移 + 9 单测；#483 补齐与翻译/音译切换此前已在 P1-1/既有「多行歌词」胶囊覆盖；AMLL/Kugou 源鸿蒙不存在故不移植 | 早 |
| F-3 | 评论模块（网易云/B站原生评论、三态面板、楼中楼点赞） | #432/#476/#487 | **已完成（2026-10-11）**：评论域全量移植（上游 12351888/7588e073/2c68dbbb）——`model/CommentModels.ets` 统一模型（平台/排序/错误分类/SongComment/CommentPage/CommentSource）+ `network/comments/` 八文件：CommentSourceResolver（channelId 优先、album 前缀回退，B 站 resourceId=0 由仓库按 bvid 解析 avid）、NeteaseEmoteCatalog（59 项内置表情目录，URL 模板直译）、两 mapper（网易：data 包装/根对象双形状、hasMore 三级回退、replyCount 双位置回退、beReplied status=-5、楼中楼 data.time 游标回退、[名称] 表情手工扫描；B 站：#487 分页防御——全零分页与空页未读完按 API 错误抛、ctime 秒转毫秒、rcount/count 回退、emote/pictures、// 协议归一）、CommentMemoryCache（5 分钟 TTL + LRU 48，sort/page/cursor/sessionKey 五维键隔离）、NeteaseCommentRepository（列表 /api/v2/resource/comments 三排序游标语义 + 楼中楼 weapi floor/get + 分页推进校验）、BiliCommentRepository（bvid→wbi/view→avid 身份解析 LRU 32 + cid 分 P 校验 + 点赞/发评 /x/v2/reply/action|add）；UI：CommentPanelController（上游 VM 状态机直译，request-generation 代替协程取消、不可变快照广播）+ CommentSheetContent（bindSheet 三态面板：排序 chips/触底翻页/楼中楼展开分页/点赞三级写回/Span+ImageSpan 富文本/相对时间/配图网格）+ NowPlayingPage 顶栏评论入口（仅音源支持时显示）。**网易点赞/发评不移植**（依赖上游 WebView 易盾 checkToken，鸿蒙无该设施，仓库层以 PERMISSION 拒绝、UI 只读）；**B 站点赞/发评完整支持**。39 新单测；codelinter 0 缺陷 + assembleHap 成功 + 单测编译级 0 error（2026-10-11）；真机评论加载/交互未验证 | — | 完结 |
| F-4 | 网易云歌单写回（选择器+同步到自建歌单） | #322 | **已完成（2026-10-11）**：`network/NeteasePlaylistWriteback.ets` 纯编排（上游 57eaacd7 直译——resolveNeteaseSongId 鸿蒙子集：网易云 audioId + netease: 前缀 matchedSongId；manipulate/tracks 参数形状；批量 50 分批+失败二分下钻隔离坏歌；快照去重+失败复核捞回+按 song/detail 可解析性归因下架）+ NeteaseApi.addSongsToPlaylist（code 200 判成功、登录态 301 resetSession 重试一次）/playlistTrackIdSet/resolvableNeteaseSongIds + NeteasePlaylistSummary 补 creatorUserId（自建过滤）+ PlaylistDetailPage 标题菜单「同步到网易云歌单」→ 选择器弹层（仅自建歌单）→ 整单写回 toast 汇总。8 新单测（fake 子类注入）；codelinter 0 error + assembleHap + 单测编译级 0 error。**上游多选同步与跨平台搜索匹配管线、收藏夹→喜欢歌单路径不移植**（鸿蒙无多选模式；匹配复用既有手动/自动匹配写回的 matchedSongId）；真机写回未验证 | — | 完结 |
| F-5 | 网易云推荐扩展（雷达歌单、个性化元数据、每日推荐缓存） | #319/#338/390 | **已完成（2026-10-11）**：`network/NeteaseHomeRecommendations.ets` 纯逻辑直译（雷达歌单 5 定义+isNeteaseRadarPlaylist、歌曲/歌单来源枚举登录门槛与过滤、parseNeteaseHomeSongs/Playlists 多响应形状、歌单详情摘要回落、appendUnique 合并去重）+ NeteaseApi 六端点（/v1/discovery/recommend/resource、/v3/discovery/recommend/songs、/v1/radio/get、/personalized/newsong、/top/playlist、轻量 getPlaylistSummary；weapiHomeCall 登录态 301 resetSession 重试一次）+ 首页「雷达歌单」横滑区（静态定义先上屏、5 路详情摘要并发升级 #390 精神、单曲失败保留兜底）。6 新单测；codelinter 0 缺陷 + assembleHap + 单测编译级 0 error。**不移植**：上游 HomeViewModel 分区协调器/信号量预算与每日推荐持久缓存（鸿蒙首页轻量直载，无 ViewModel 缓存层，雷达区数据足够小）；真机观感未验证 | — | 完结 |
| F-6 | 一起听增强：权威取流/队列变更版本化/控制事件合并/成员离场自动暂停/卡死连接超时恢复/邀请链接加入 UI | #359（20 提交）/#318/89a8694c | **已完成（2026-10-11，#318+#359+89a8694c 客户端侧全部）**：#318 子项（听友路由丢失静音）此前已落地；本轮 #359（squash 3cfd7037，LTW 服务端子模块 1f476060→31d55c60——协议在服务端，鸿蒙只移植客户端消费侧）全量移植：① V2 队列变更协议——`protocol/ListenTogetherQueueMutation.ets` wire codec（schemaVersion 2、64 op 上限）+ `control/QueueMutationBuilder`（目标队列 diff→remove/remove_many/move/insert/reorder，超限或空 stableKey 回退全量快照）+ `control/QueueMutationApplier`（对象身份匹配、targetCurrent/current 候选序）；EventFactory SET_QUEUE/PLAYBACK_MODE/TRACK_FINISHED/SET_TRACK 带 mutation+内存 legacyQueueSnapshot（@Transient 不上 wire），旧服务器拒绝（4 种错误串）→ `trySendQueueMutationLegacyFallback` 改发快照；② 控制合并与发件箱——本地控制 100ms 窗口合并取最后（generation 数字替代协程 Job）+ `session/ControlOutbox`（roomId:intent 键控、LRU 8、ack 清除、重连 replay）；③ 连接稳健性——前台恢复三态（DISCONNECTED 重连/CONNECTED ping 探测 5s 零消息强制重建/CONNECTING 卡死>15s 强连）、WS 响应超时 35s 重连、ping 未答复不覆盖时间戳；④ 控制器链路不可用生命周期——3 次解析尝试（等待自身播放解析 200ms×40 轮）→LINK_UNAVAILABLE→听友两次不同 signalId 确认（`AuthoritativeStreamAvailability`）→停 REQUEST_LINK+本地回退每曲一次（StateApplier pending/lastUnavailable 记录、surface 三新方法经 binding→PlayerManager）；⑤ 静音显式恢复——路由丢失静音扩展到所有听友+requiresExplicitRestore（新设备接入不自动恢复），UI 三处播放键（NowPlaying 传输行/歌词页、MiniPlayer SymbolGlyph）+AVSession onPlay 静音态显示/触发「恢复音量」（AppStorage `player.ltMuteSuppressed`）；⑥ 房间关闭与成员——leaveRoom MEMBER_LEFT 自动暂停、room_closed 按最终 paused 态镜像暂停+closedReason 规范化优先、controller_reconnected 通知门控（observedControllerOffline）、ListenTogetherPage 通知码→中文文案映射；⑦ 同步与取流——软同步 rate≠1 每 500ms 复核（KEEP/RESET/FORCE）、权威队列更新回声豁免（更高版本+队列实际变化）、StreamUrlPolicy 平台上限（netease 3/bili 2/youtube 1）+mountaintoys.cn 白名单、快照 track strip 原始 streamUrls、EntryAbility onForeground/onBackground 钩子；单测 2 新文件（QueueMutation codec/builder/applier、Outbox/前台恢复/软同步复核/Availability/关闭暂停/通知归一化）+4 文件增量，编译级 0 error（真实通过计数待 Windows）；codelinter 0 缺陷 + assembleHap BUILD SUCCESSFUL。**明确不移植**：BackgroundKeepAlive/WakeLock（无鸿蒙对应）、QualityPolicy 音质协商/URL 质量片段（鸿蒙无 PlaybackUrlCandidate/audioInfo 体系）、shuffleRestoreQueue 生产（随机在索引层实现，仅解码字段）、SettingsScreen Join Room（ListenTogetherPage 已有等价入口）、resolveQueueCurrentIndexAfterReorder（鸿蒙 moveQueueItem 走 QueueEngine.currentIndexAfterMove 天然免疫）、RestoredPlaybackPolicy 接线（鸿蒙无启动自动恢复播放，纯函数已移植）；**已移植未接线纯函数**：shouldMuteListenTogetherListenerForOutputDisconnect 六参变体、suppress/prefer/preview 三谓词（取流层无 preview 概念）。⑧ **89a8694c（取流重试+全量队列同步，2026-10-11 第二轮）**——`player/SongUrlResolutionRetry.ets` 纯策略（5 次重试×250ms·n 递增延迟、isFailure 谓词注入替代 SongUrlResult 判别、resolveSongUrlOrWaitForAuthoritativeStream 等待哨兵）+ resolveStreamUrl 网络解析与房主分享链路（resolveShareableListenTogetherStreamUrls）接入重试 + 听友等待权威流时 loadSong 静默挂起（ResolvedStream.waitingForAuthoritativeStream，不再本地取流失败翻错误）；全量队列同步——PlayerManager.applyRemoteListenTogetherQueueUpdate（不重载热更新队列/空队列走 clearQueue+清 mediaUrl）+ emitQueueUpdateCommand 接入四个本地队列编辑（insertNext/addToQueueEnd/moveQueueItem/removeQueueItem，移除当前曲带 continuePlayback 语义）+ EventFactory.buildSetQueueEvent（master 合并形态：schema-V2 走 mutation transport、legacy 走全量快照、空队列房间清空信号、成员 REQUEST_SET_QUEUE）+ buildEventForPlaybackCommand SET_QUEUE 分支（空命令队列保留为清空信号不回退播放队列）+ ControlEventTypes 三项（REQUEST_SET_QUEUE 入心跳恢复/请求集、SET_QUEUE 入受控命令集）+ StateApplier 热更新路径（queueUpdatedWithoutReload→surface.applyRemoteQueueUpdate，不触发 reload/seek；SET_QUEUE 族空队列→本地清除）；上游同提交捆绑的 AdvancedGlass UI 实验与 LTW 服务端指针不在移植范围；新增 SongUrlResolutionRetry 单测文件 + factory 4 例 + applier 2 例（热更新/空队列清除）+ 类型分类增量，编译级 0 error、codelinter 0 error、assembleHap+签名成功。**余项**：无（F-6 客户端侧全部完成）；真机未验证（V2 mutation 与旧服务器互操作、双端一起听回归、拔耳机静音-恢复交互、队列编辑全量同步与不重载热更新） | M7 核心闭环后的稳健性波次 | 中 |
| F-7 | YTM 创作者主页 + B站 UP 主空间/合集/系列 + B站链接解析（分P/合集/season_id） | #341/4c085185 / e95b2ef9/507c22d7 / a8440275/1dbb2964 | **已完成（2026-10-11，链接解析+UP 空间/合集/系列+短链+YTM 创作者主页）**：`network/ExploreLinkRecognizer.ets` 上游直译（网易歌曲/歌单/艺人含 #/ 哈希路由与 163cn.tv、B 站 BV/av+p/cid+合集分享判定、space lists season（series→不支持）/favlist ml 前缀/medialist/UP 主、b23.tv、YouTube watch/youtu.be/shorts/live/list/channel）+ BiliApi.getVideoInfo（wbi/view 全摘要：标题/UP/封面/分P/ugc_season 单集，bvid 缺席按 aid）+ 探索页搜索框链接优先（网易歌直开播放、歌单/艺人/收藏夹跳页、B 站视频开播（多 P 播第 1P 并提示，分P定向播放暂无）、合集分享单集落结果区、短链/series/UP 空间/YTM 播放列表拦下 toast）+ NeteaseApi.getSongsByIds/YouTubeMusicApi.songFromVideoId；6 新单测；codelinter 0 error（1 warn 存量）+ assembleHap + 单测编译级 0 error。**UP 主空间/合集/系列 + 短链展开（2026-10-11 第二轮，e95b2ef9/507c22d7 核心子项）**：① `network/BiliUploaderSpace.ets` 纯解析直译（profile/投稿分页/合集系列分离/系列与合集归档条目/图片 https 归一/时长解析/SongItem 映射）；② BiliApi 五端点——acc/info（UP 资料）、arc/search（投稿分页 30/页）、seasons_series_list（合集+系列 20/页）、seasons_archives_list（合集内容 30/页）、x/series/archives（系列内容），经 requireSuccessfulData（code!=0 抛业务错）复用既有 WBI 签名；③ `BiliUploaderPage` UP 主空间页（头像/签名头部+播放 pills+投稿/合集/系列三 Tab，投稿 LazyForEach 触底加载，合集/系列卡片跳详情）+ `BiliCollectionPage` 合集/系列详情页（PlaylistHeader+分页列表+全部/随机播放，507c22d7 的 UP 名 acc/info 回填——归档接口不带 UP 名）；④ 链接接线——recognizer 新 BILI_SERIES kind（space lists?type=series 不再拦下），ExplorePage 短链展开（`HttpClient.expandRedirectUrl`：REDIRECTION 拦截器记录重定向链取末跳——平台 http 恒跟随重定向且无 effectiveUrl 字段，maxRedirects:0 会抛 2300047 故不可用）后重新识别分发，BILI_ARTIST/BILI_COLLECTION/BILI_SERIES 三分支跳新页；⑤ NowPlayingPage openArtist 的 bili 分支（bvid→getVideoInfo 反查 ownerMid 进空间页）；10 新单测（解析器 7+短链纯函数 2 归一 1）+ recognizer series 断言更新；codelinter 改动文件 0 error（9 warn 为 hp-arkui 建议类与存量同款）+ assembleHap + 单测编译级 0 error。**YTM 创作者主页（2026-10-11 第三轮，4c085185/#341）**：① `network/ytm/YtmCreatorParser.ets` 纯解析直译——Summary/Header/ItemType/Item/BrowseEndpoint/Section/Detail/ItemsPage 八模型 + parseYtmCreatorSearchResults（twoRow/responsive 双形状、browseId 去重、channelId UC 前缀/menu subscribeEndpoint 两路）、parseYtmCreatorDetail（immersive/visual/detail 三 header、strapline/描述架回退、shelf/carousel/itemSection 嵌套分区、moreEndpoint 四路提取）、parseYtmCreatorItemsPage（grid/carousel/playlistShelf/shelf 四源+continuation 仅非空条目保留）、parseYtmCreatorItemsContinuation（四 continuation 源+onResponseReceivedActions）、extractYtmSearchContinuation、itemKey/merge/PlaybackQueue 构建（loadYtmCreatorPlaybackQueue：moreEndpoint 缺席本地队列、否则首页+续页上限 80、token 环去抖）、ytmCreatorItemToSongItem（artist/album/cover 三级回退）；② YouTubeMusicApi 扩展——YtmSearchFilter 三档（songs 沿用鸿蒙已验证 params，videos/creators 用上游常量）+ search(filter) 重载 + searchCreators（collectSearchResults 语义：seenKeys 去重、页限 80、首页失败抛错续页失败中断）+ postMusicBrowse 私有通道 + getCreatorDetail/getCreatorItems/getCreatorItemsContinuation 三方法；③ UI——`YtmCreatorPage` 创作者主页（资料卡+月听众/订阅 chips+简介、分区可播行列表/混合横滑卡片、moreEndpoint 分区点歌走完整队列、Creator 卡递归跳转）+ `YtmCreatorItemsPage` 分区全量列表（continuation 触底加载+去抖收口+点击按当前列表起播）+ Router/MainShell 两路由注册 + ExplorePage YTM 源类型 chips（歌曲/视频/艺人）与创作者结果行（头像+订阅信息行点击跳主页）；④ 9 新单测（搜索双形状/continuation token/detail header 分区 moreEndpoint/twoRow 类型时长/itemsPage 多源回退/appendActions/SongItem 映射与 key 优先级/播放队列过滤定位/缩略图升档）；codelinter 改动文件 0 error（8 warn hp-arkui 存量同款）+ assembleHap + 单测编译级 0 error。**不移植**：上游同提交捆绑的本地媒体元数据回写（LocalMediaSupport/CustomSongCoverStorage/NowPlaying 写回 UI，非 F-7 范围）、Coil 封面视觉预载（鸿蒙 Image 自带缓存）、BiliArchiveCacheRepository 落盘缓存（页面级状态足够）、平板双栏/横幅模糊头部（按鸿蒙单列样式重设计）、YTM 登录态/cookie 刷新体系（鸿蒙全程匿名 bootstrap，与既有 search 一致）、创作者页 Album/Playlist 卡片跳 YTM 歌单详情（鸿蒙无 YTM 歌单页，toast 暂不支持）、NowPlaying artist 跳 YTM 创作者（依赖 browseId 元数据，鸿蒙 YTM SongItem 不携带）、YouTube channel/@handle 链接直跳创作者页（上游 recognizer 同为 Unsupported，创作者入口走搜索过滤）。**余项**：分P定向播放需播放器 cid 覆写支持，暂列不做 | 适配器层扩展，各自独立 | 中 |
| F-8 | 存储空间分析页 + 缓存容量档位（含无上限） | #328/#335/#327 | **已完成（2026-10-10，commit 14422e0；容量档位部分此前已随 P1-7 于 f4438d8 落地）**：StorageUsageAnalyzer 六桶分析 + 设置「存储与缓存」分区重写（分桶明细/重扫/清除播放缓存/歌词缓存/诊断记录），StorageBytes 单测；真机扫描数值待验证 | 中 |
| F-9 | 搜索 UX 波次：歌单现代搜索 UI+历史+拼音排序+分词、探索分页与链接识别、滚动隐藏历史、搜索结果歌曲操作 | dfa37db0/9a38f4c5/bf50094e/#371/e947409a/c5a95707/dddaa0b4/cecaa6df | **已完成（2026-10-12）**：① `util/search/SearchTextMatcher.ets`——上游 SearchTextMatcher 直译（NFKD 归一+Mn 剥离+全角空格、手写 Unicode 区间分词、驼峰拆分、首字母缩写、相等/前缀/包含/模糊子序列四级评分、字段 bias 阶梯、拼音候选经注入式 PinyinResolver seam，-1 哨兵替代 Int? null）+ `SongSearchValues.ets`（SongItem 14 字段 bias 化搜索值 + rankExploreSongSearchResults 匹配在前未匹配垫底 + mergeSongItemsDeduped platform+audioId 去重）；② **拼音方案评估落地**（三路调研：系统 i18n.Transliterator 无首字母 API 且 Local Test 不支持；自嵌表 43KB 无词组多音字；**ohpm pinyin-pro 3.26.0 胜出**——MIT/零依赖/纯 JS 可本地单测/本机实证 API 26 编译通过，release 包体 +约 620KB）——`SongPinyinSource.ets` 薄封装（单字无声调全拼，CJK 区间守卫）+ EntryAbility.onCreate 注入；③ 探索搜索分页（上游 c5a95707/e947409a）：NeteaseApi.search 加 offset、BiliApi 新 searchPage（wbi/search/type 带 page，返回 items/page/numPages），ExplorePage hasMore（网易满页规则/B 站 page<numPages）+ loadMore 触底与按钮双触发 + 合并去重后整体按查询词重排；④ 历史策略（dfa37db0/bf50094e）：`data/SearchHistoryPolicy.ets` 纯函数——updatedSearchHistory 忽略大小写去重接入 SearchHistoryRepository.add、resolveExploreSearchKeyword 历史强匹配别名（分数≤12 整串/前缀级替换查询词，输入框仍显示原词）；⑤ 歌单内搜索（dfa37db0 去动效形态）：PlaylistDetailPage「歌曲」行下内联搜索框（非空显示清除钮）+ SearchTextMatcher.filterAndRank 过滤重排 + 过滤视图点歌回原歌单定位起播（保持全单队列）+ 无匹配空态；11 新单测（归一/评分序/bias/缩写驼峰/拼音 fake+真实 resolver/filterAndRank/rank/merge/历史更新/别名）。**不移植**：歌单 docking 搜索条动画（Material 特性，用标准搜索框样式）、滚动隐藏历史（上游为已输入未搜索态的历史建议区滚失行为；鸿蒙历史区在搜索发起时已隐藏，结构等价）、cecaa6df 搜索结果歌曲操作菜单（鸿蒙 SongRow 内联菜单已有等价能力：收藏/下一首/加队列/下载）、dddaa0b4 浏览状态保留（鸿蒙 Tabs 页面常驻 @State 天然保留）、YTM 歌曲搜索分页（上游同样单页）、网易歌曲搜索歌单/艺人过滤类型（鸿蒙探索页仅歌曲搜索，类型分页待有需求再加）。codelinter 改动文件 0 error + assembleHap SUCCESSFUL（pinyin-pro 已打进 HAP 实证）+ 单测编译级 0 error；真机搜索分页/拼音输入/歌单过滤未验证 | 中 |
| F-10 | 歌单删除撤销 + 历史导出确认防抖复核 | 90ee4f46/b4075e10/2cd50545 | **已完成（2026-10-10，commit 240c7ca）**：仓库级快照/恢复（含跨端墓碑与镜像 skipKeys 回退）+ UndoBanner 横幅（歌单删除→资料库页、单曲移除→详情页）+ 备份导出/导入双击防抖（复核确认鸿蒙侧原无守卫）；撤销交互待真机验证 | 小型 UX 波次 | 晚 |
| F-11 | 多步引导/免责流程重做 | 01c57a11 等 | **已完成（2026-10-12，引导部分；免责/阶段机鸿蒙此前已完整）**：上游 9 步（Language/Platforms/PlaybackSources/Permissions/PlaybackControls/Lyrics/Personalize/BackupRestore/LearningGuide）按鸿蒙面裁剪为 **7 步实用向导**——欢迎（应用简介三要点）/外观（深色模式三选+动态取色）/播放源（YouTube 启用+Wi-Fi/蜂窝音质档）/歌词（字号滑杆+翻译/音译开关）/播放器（播放页+歌词页控件大小档）/账号与备份（说明卡+无平台提醒）/开始使用；步进制（按钮主导，弃 Swiper——设置项交互与横滑手势冲突），进度条=上游 calculateStartupOnboardingProgress 直译（(step+1)/7 夹 0..1），全部开关直写既有设置键（与设置页同存储立即生效，深色模式经 AppColorMode.apply 重建主题），账号/备份步只做说明引导（启动门阶段无 Navigation 不能跳设置，上游语义保留入口位置）。纯逻辑 `view/onboarding/StartupOnboardingPolicy.ets`（progress+shouldWarnNoPlatformConnected 两平台版）+3 单测；重写 `OnboardingPage.ets`（复用 Ui.ets ToggleRow/OptionRow/SliderRow，音质空串回退 legacy 键与设置页同规则）。**不移植**：语言步（鸿蒙仅 zh 占位）、权限步（鸿蒙无运行时权限——通知由 AVSession 托管、文件走 picker）、通知权限两次确认警告、docking 搜索条/歌词预览几何/播放器实时预览/主题 reveal 动画/StartupStageTransition 过渡门（上游 1500 行 Extras 特效主体，鸿蒙引导轻量直达）、播放源回退确认。免责页与 StartupPhase 阶段机（Loading→Disclaimer→Onboarding→SafeMode→Main+协议版本门控）此前已完整，本轮不动。codelinter 0/0/0 + assembleHap SUCCESSFUL + 单测编译级 0 error；真机引导流程未验证 | 晚 |
| F-12 | 桌面卡片（HarmonyOS FormKit，非直接移植 Android widget） | #472 | **已完成（2026-10-12，鸿蒙 Form Kit 独立设计，上游 #472/86ad5f82 仅功能参照）**：① 播放控制卡片 `widget/pages/PlaybackCard.ets`——ArkTS 卡片（@Entry(storage)+@LocalStorageProp，运行于 FRS 进程无 AppStorage/Theme，固定深色样式），2*2+2*4 双规格共用一页自适应布局：封面（formImages fd + memory://key）+歌名/艺人+上一首/播放暂停/下一首；② 控制路径 **call 事件**（官方文档音乐卡片推荐形态）：卡片按钮 postCardAction({action:'call', abilityName:'EntryAbility', method:'playbackCardControl', params:{formId,action}}) 把 singleton UIAbility 拉到后台执行（不弹界面；应用被杀时冷启动 onCreate 内 PlayerManager.initialize 已恢复队列再执行），EntryAbility.onCreate 注册 callee（rpc.Parcelable 应答）→ PlaybackCardBridge.handleControlCall（toggle/prev/next 纯参数解析）→ 播放状态机变化经 listener 再推卡片；③ 数据流 **updateForm 主动推送**（官方 FAQ：主动刷新无次数限制，三方应用禁止秒级刷新）：PlaybackCardBridge 监听 PlayerListener.onSnapshotChanged（切歌/暂停级频率，重入合并）→ formProvider.getPublishedRunningFormInfos() 拉活表 formId（16500100 无卡片静默）逐个推送 + 快照 JSON 落 cacheDir 纯文件（form 进程 preferences 单进程不可共享）供 EntryFormAbility.onAddForm 回放最新态；封面 URL 变化时 http 整包下载 cacheDir 覆盖写、formImages key 按代数换代（同 key 不刷新）、fd 用后关闭防累积；④ 配置——module.json5 新 EntryFormAbility（type form+metadata ohos.extension.form）、form_config.json（2*2/2*4、updateEnabled:false 纯主动推送、isDefault 必填）、4 新字符串；点击卡片主体 router 事件打开应用。⑤ 纯逻辑 `widget/PlaybackCardState.ets`（快照 fromSong/JSON 往返/payload 构造含无歌回退/coverKey 换代/call 参数解析）+5 单测。**不移植**（上游 Android widget 特性）：4*1 规格（鸿蒙无此尺寸）、进度文本/进度条（三方应用秒级刷新被官方明令禁止）、收藏与悬浮歌词开关按钮（鸿蒙无悬浮歌词；收藏态需跨进程查询成本高，列为后续候选）、升级后自动刷新（MY_PACKAGE_REPLACED 语义，鸿蒙无对应）、响应式尺寸计算族。codelinter 6 文件 0/0/0 + assembleHap SUCCESSFUL + 单测编译级 0 error；**桌面加卡/控制/推送全链路真机未验证**（本机无设备，卡片行为须真机：加卡显示、后台控制不弹界面、冷启动 call 路径、封面刷新） | 晚 |
| F-13 | 杂项 polish：MiniPlayer 字号自适应(#357)、波形进度预测(#337)、播放控制布局定制(2644267f)、歌词翻译行距 kana 检测(15f07073)、翻译折叠(#392) | **已完成（2026-10-11）**：①kana 检测行距 + 同时间戳翻译折叠（2026-10-10，commit 50ec7a1，6 单测）；②MiniPlayer 字号封顶（#357/b6911607）——`MiniPlayerTextSizing.resolveTextAutoSizeRange` 直译 + EntryAbility 播种 `systemFontScale`（Configuration.fontSizeScale，onCreate/onConfigurationUpdate），标题按 24vp 视觉行高封顶（跑马灯承接超宽）、副行 min/maxFontSize 向下自适应（下限 9 视觉字号），6 单测；③波形进度预测（#337/bc4142bc）——`WaveProgressPredictor` 直译（ms 时钟），positionMs 500ms 发布间隙由本地时钟外推，真实发布重锚、加载/拖动预览停预测、速率含一起听同步率，6 单测；④播放控件大小档位（2644267f 的 size 部分）——`PlaybackControlSizing`（小 0.9/中 1.0/大 1.2，按钮 40vp 触控下限/图标 18vp 下限 + resolveMainControlsLayout 窄宽同比压缩），`np.nowplaying_control_size`（顶栏/传输行/底部工具行）与 `np.lyric_control_size`（歌词页胶囊）两键 + 设置页播放分区两行，7 单测。**位置三档（中下/贴底/贴底含进度）不移植**：鸿蒙播放页控制区自始贴底（Swiper 吃掉弹性空间），无「中下」形态可切换。codelinter 0 缺陷 + assembleHap 成功 + 单测编译级 0 error（2026-10-11）；UI 交互待真机 | — | 完结 |
| F-14 | DSP/桌面电台站点（音乐电台聚合站接入） | #526（feat(site): add DSP and desktop stations） | **待立项（2026-10-15 元数据归类，未核查）**：上游新增 DSP 电台与桌面电台站点支持。需先拉上游源码确认为哪个站点、协议形态（是否自有 API/网页抓取），再对照鸿蒙适配器层评估；依赖网络适配器扩展，与 #511 Subsonic 同属「新增音源」波次 | 晚（新增音源波次） | 低 |

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

## 6. 在途 PR 观察（2026-10-15 复核）

**原观察项已全部合并并重筛完毕**（2026-10-15 第二轮维护）：

- ~~**#506**~~（已合并 2026-10-10，258 提交）：重筛结论——大部分为 Android 侧重构/test/USB/平板/预测返回（C 类不适用）；修复类已拆入 §3.3 审计项 A-15/A-16/A-17/A-18；`fix(sync): checkpoint merges at the remote observation time` 与统计 journal 归属 §2.1 顺带核对范围。
- ~~**#507**~~（已合并 2026-10-13，2 提交：翻译匹配容差 + 翻译槽位保留与匹配扫描上限）：拆入 §3.3 新增审计项（与 F-2 歌词域合并核对——鸿蒙 SongMatchScorer 已有 ±8s 容差，核对翻译行匹配路径是否有同等守卫与扫描上限）。
- ~~**#508**~~（已合并 2026-10-12）：§7.5 已核查鸿蒙无此缺陷，关闭观察。

**当前在途（open，合并后再筛）**：

- **#511**（feat(subsonic): 接入 Navidrome 账号、媒体库与基础播放）：全新音源（Subsonic API），合并后与 F-14 同属「新增音源」波次评估。
- **#525**（feat(home): 新增 Bilibili 音乐榜与音乐热门首页模块）：B 站首页推荐区扩展，合并后对照鸿蒙首页推荐/雷达歌单区块（F-5）评估。
- **#527**（feat(local): match and embed lyrics and artwork for local songs in batch）：本地歌批量匹配并内嵌歌词/封面——鸿蒙本地媒体无 ID3 写回设施，倾向 C 类，待合并后确认。
- **#528**（fix(audio): keep speaker optimization behind the effects master switch）：扬声器优化门控，属 Android 音频特调，倾向 C 类。

## 7. 已核查确认无需行动的记录（2026-10-10，防重复审计）

1. **队列/随机四修**（e1882e38/1b006589/14ae0dcf/f7d224a3）：鸿蒙随机在索引层实现、歌曲数组永不被置换、展示层从不排序，结构性免疫；Repeat All 重洗在普通/自然结束/失败重试/原生无缝四条路径均已实现且有单测。唯一遗留：插入/拖拽算法是死代码（→ F-1 接线，接线时需补集成层测试）。
2. **WebDAV LOCK 租约**（#491/#495 锁清理部分）：鸿蒙不用 LOCK，乐观条件写+指纹复核+冲突重试已完备。
3. **歌单/usage 删除墓碑与合并稳定性**（#350/37fbf74b）：墓碑+causal token+确定性比较器已实现，测试充分（undo 未移植属 F-10 候选）。
4. **「最后同步时间」播放期间刷新**（#480）：自动同步成功即刷新；鸿蒙侧该时间甚至无 UI 展示位（可作 F-8 顺带小改进）。
5. **HLS checkpoint 向前兼容**（#508）：纯内容派生键（playlistFingerprint+字节数），与 Android 基线同构，无 id 门禁。**2026-10-15 复核**：#508（legacy checkpoint 无 operationId 续传）合并后确认鸿蒙 checkpoint 键不含 operationId，无此缺陷，关闭观察。
6. **已下载歌曲保留远端身份**（fc013a94）：sourceStableKey 回链已实现且有跨端单测。
7. **载荷校验入库口**（#499 相关）：isPlausibleAudioHead + filler 扫描挂满三个入库口。
8. **本地 AAC/MP3 播放**（#469）：鸿蒙 5400106 系列（fdSrc 直赋）已修，标记待真机复核即可。
9. **一起听核心链路**：建房/加入/同步/重连/邀请已双端设备闭环（M7.5），#359 属增强而非缺陷（→ F-6）。

## 8. 参照快照升级策略

`NeriPlayer-master/` 停在基线 `d66d465f`。移植 §4 任一功能前需上游源码作行为参照，二选一：

- **方案 a（推荐）**：单项移植时临时 `git fetch upstream` 到工作区外目录读取对应模块，任务记录中注明 commit SHA（不动 `NeriPlayer-master/` 快照）；
- **方案 b**：一次性把快照升到指定 commit，按 AGENTS.md 记录 SHA/日期/许可证，并重跑快照只读性检查。**2026-10-15 更新**：原建议的「等 #506 合并」条件已满足（#506 已于 2026-10-10 合并），可随时选稳定点（建议 `5c6aca42d`，2026-10-14）执行升级，作为独立任务立项。

快照升级本身是独立任务，不与功能移植混做。

## 9. 维护规则

- 本文按「上游新增提交 → §0 三分工 → 对应章节增行」增量维护；每次维护在文首注明数据截止日期。
- 状态用词遵守仓库规范：「已核查（静态）」/「待审计」/「待真机复核」，不写「已验证」除非有设备证据。
- 完成一项 P0/P1 后：勾掉待办、在对应行补「已完成 + commit」、必要时同步 FEATURE_MATRIX。
