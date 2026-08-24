# HarmonyOS 原生特性与设计规范落地需求（NeriPlayer）

> 成文日期：2026年08月24日
> 工程基线：HarmonyOS 6.1.1 Release / **API 24**（`build-profile.json5` 的 `compatibleSdkVersion` 与 `targetSdkVersion` 均为 `6.1.1(24)`）

## 0. 本文定位

此前 `docs/` 下的全部文档（`FEATURE_MATRIX.md`、`PORTING_EXECUTION_PLAN.md`、`RELEASE_CHECKLIST.md`、`hm.md`）都是**「Android 上游 → HarmonyOS 等价性」**导向：衡量标准是「Android 有的，鸿蒙侧做到了没有」。

本文是**另一个方向**的清单：**Android 侧没有、只有鸿蒙才有的系统级能力**，以及**上架前须满足的华为官方设计规范**。两类内容互补，不替代既有文档的任何结论。

### 证据分级

沿用 `PROJECT_AUDIT.md` 的分级，并新增一级用于标注 API 可用性来源：

| 级别 | 含义 |
| --- | --- |
| **SDK 确认** | 直接来自本机 API 24 SDK 的 `.d.ts` 声明（含 `@since` / `@permission` / `@systemapi` 标记）。这是关于「基线上能不能调」的最强证据，强于官网网页。 |
| **文档确认** | 来自 `devecocli docs` 本地文档库或官网页面正文，标注文档 ID 以便复查。 |
| **已静态确认** | 直接来自本工程当前文件内容或 grep 计数。 |
| **待设备验证** | API 存在且基线可用，但本轮**未在设备/模拟器上实际调用**，行为未观测。 |

SDK 路径：`D:\HarmonyOS\Tools\command-line-tools\sdk\default\openharmony\ets\api\`。

### 一条重要的自我修正

起草本文过程中，先前「`PlayerManager` 未设 `audioRendererInfo` 即违反音乐低功耗规则」的判断被 SDK 原文推翻，已在 §4 如实降级为「防御性加固」而非「当前违规」。详见 §4.1。

---

## 1. 结论摘要

优先级判据（三者同时看）：① 是否在 API 24 基线内可用；② 是否需要 AGC 审批或受限开放；③ 是否属官方明文要求 / 修正既有 hack，而非纯增量。

P0 的定义是：**基线内可用 + 零审批 + 属官方明文要求或修正现有 hack**。这批的共同特点是改动小、风险低、收益确定。

| 优先级 | 事项 | 基线可用 | 需审批 | 现状 | 章节 |
| --- | --- | --- | --- | --- | --- |
| **P0** | 歌词改用 `AVMetadata.lyric` / `singleLyricText` 正规字段 | ✅ @since 10 / 17 | 否 | 用 `title` 蹭位 | §2.1 |
| **P0** | `setLaunchAbility` 播控卡片点击跳转 | ✅ @since 9 | 否 | 零命中 | §2.2 |
| **P0** | `on('toggleFavorite')` 播控收藏 | ✅ @since 10 | 否 | 未注册 | §2.3 |
| **P0** | 系统级桌面歌词（`enableDesktopLyric` 全套） | ✅ @since 23 | 否 | 零命中，且被 D4 误判为「无平台对应」 | §3 |
| **P0** | 音频低功耗加固（显式 `usage` + 静音 `EFFECT_NONE`） | ✅ @since 12 | 否 | 只设了 `audioInterruptMode` | §4 |
| **P1** | 服务卡片（音乐播控卡片） | ✅ @since 9 | 否 | 无 `extensionAbilities` | §5 |
| **P1** | `Navigation` 迁移（官方已将 `router` 标为不推荐） | ✅ | 否 | 自研 Router + 单页 | §6 |
| **P1** | 折叠屏悬停态（官方点名「听歌」场景） | ✅ | 否 | 未适配 | §7.1 |
| **P1** | 分层图标 | ✅ | 否 | 只有 `app_icon.png` | §8.1 |
| **P1** | 触控目标 40vp → 48vp | ✅ | 否 | 实测 40vp 下限 | §7.3 |
| **P2** | 投播（AVCastPicker / Cast+ / DLNA） | ✅ | 否 | 零命中 | §9 |
| **P2** | 多语言资源限定词目录 | ✅ | 否 | 只有 `base` + `dark` | §8.2 |
| **P2** | `setLoudnessGain` 响度增益 | ✅ @since 21 | 否 | 零命中 | §4.3 |
| **P3** | 实况窗（Live View Kit） | ✅ | **是**（AGC 评审 7 工作日） | 零命中 | §10.1 |
| **P3** | 播控推荐服务 | ✅ | **是**（受限开放，仅中国大陆） | 零命中 | §10.2 |
| **P3** | 意图框架 `PlayMusicList` | ✅ @since 20 | 联调依赖 | 零命中 | §10.3 |
| **不可用** | `setMediaCenterControlType` 自定义播控布局 | ❌ **API 26** | — | 基线 24 SDK 无此声明 | §10.4 |
| **不适用** | `AVMusicTemplate` 音频模板 | ❌ 仅 Car 工程 | — | 本工程无 Car 形态 | §10.5 |

**P3 全体的现实约束**：`RELEASE_CHECKLIST.md` §5.3 的结论是「面向公开市场需剥离或降级三平台取流能力」。凡需 AGC 上架审批的能力（实况窗正式权限、播控推荐服务）都以「应用能上架」为前置，而上架本身在本项目是未决问题。因此 P3 不是「以后再做」，而是**依赖一个尚未成立的前提**，不建议在前提落定前投入。

---

## 2. P0 播控（AVSession）：官方自检表逐项对照

官方为音乐类应用提供了明确的接入自检表（文档 ID `开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控自检表/playback-control-access-checklist`），逐项列出音乐应用的必接项。

工程现状（**已静态确认**，`entry/src/main/ets/player/AVSessionManager.ets`，共 244 行）：

- 第 37 行 `createAVSession(context, 'NeriPlayer', 'audio')`，第 39 行 `activate()`
- 第 40–61 行共注册 **8 个**命令：`play` / `pause` / `stop` / `playNext` / `playPrevious` / `seek` / `setSpeed` / `setLoopMode`
- 第 113–121 行、157–165 行的 `AVMetadata` 只设 `assetId` / `title` / `artist` / `album` / `duration` / `mediaImage`

### 2.1 歌词字段用错：`title` 蹭位 → `lyric` / `singleLyricText`

**这是本次检索发现的最直接的一处「用错 API」。**

工程当前做法（`AVSessionManager.ets`）：

```
27:  // Last lyric line pushed via metadata title (Android "bluetooth lyrics"
131: /** Publishes the current lyric line through the session title (and the
136:  * the feature is user-toggled (np.bt_lyric), see FEATURE_MATRIX.
157:        assetId: `${song.platform}:${song.id}:${song.mediaUri}`,
158:        title: lineText,                                    // ← 歌词塞进标题
159:        artist: `${song.displayName} - ${song.displayArtist}`,  // ← 歌名被挤到艺术家位
```

即：把当前歌词行写进 `title`，把「歌名 - 艺术家」挤到 `artist`。代价是播控中心/锁屏/蓝牙 AVRCP 上**主副标题语义全部错位**，且滚动歌词无法工作（系统拿不到带时间轴的歌词）。

官方在 API 24 基线内提供了两个专用字段（**SDK 确认**，`@ohos.multimedia.avsession.d.ts` 的 `AVMetadata`）：

| 字段 | `@since` | SDK 原文 | 用途 |
| --- | --- | --- | --- |
| `lyric?: string` | **10** | "The lyric of the media, it should be in standard lyric format" | **带时间轴的完整歌词**，供系统渲染滚动歌词 |
| `singleLyricText?: string` | **17** | "The single lyric text of the media, not including time prefix" | **单行歌词文本，不含时间前缀** |

两个字段都在基线 24 内可用，无权限要求。

`singleLyricText` 的语义（单行、不含时间前缀）与工程 `np.bt_lyric` 想要的效果**完全一致**——官方在 API 17 就给了专门字段，工程用 `title` 蹭位是在没有发现该字段的情况下做的变通。

FAQ `FAQ/音频和视频/音视频播控_AVSession/如何在播控中心显示歌词/faqs-avsession-5`（**文档确认**）说明播控中心显示歌词的方式是设置 AVMetadata 的歌词内容，且**格式必须为标准 lyric 格式**。

**建议改动**：

1. 恢复 `title` / `artist` 的正确语义（歌名 / 艺术家），不再错位。
2. 完整歌词写入 `lyric`（标准 LRC 格式）。工程已有 `lyrics/LrcParser.ets` 与 TTML 解析器，且 `LyricDispatcher` 持有完整歌词，序列化回标准 LRC 的成本很低。
3. 当前行写入 `singleLyricText`，替换现有 `title` 蹭位路径，`np.bt_lyric` 开关继续控制是否推送。

**副作用提示**：修正后 `np.bt_lyric` 的行为会变——原本靠改 `title` 强推给 AVRCP，改用正规字段后**远端设备是否显示、如何显示由系统与对端决定**。`FEATURE_MATRIX.md` 第 33 行已记录「AVRCP 远端刷新时机无官方承诺」，这条不确定性依然存在，不因改用正规字段而消除。建议改动后保留开关，并在设备上对比两种路径的实际表现再定默认值。

**M10.1 已落地并设备实测（2026年08月24日，Pura 90 模拟器）**

改动全部落在 `AVSessionManager.ets`：四个 metadata 入口（`updateMetadata` / `updateLyrics` / `updateDuration` / `updateLyricLine`）收敛到共享的 `pushMetadata` → `buildMetadata`，`title`/`artist`/`album` 恢复正确语义，完整 LRC 入 `lyric`，当前行入 `singleLyricText`。序列化方向按本节建议在 `LrcParser` 补了反向函数（9 个新单测）。

`hidumper -s AVSessionService -a "-show_metadata"` 实测输出：

- `title: 一半一半` / `artist: Top Barry / INDEcompany` / `album: 一半一半` / `assetid: 1:3333988321:` / `media image url: https://p1.music.126.net/...` —— 语义全部归位，不再错位
- 同一条 metadata 内 `duration: 235286` 与 `lyric: [00:00.000] 作词 : Top Barry...` **共存**
- 换歌复验（「海屿你」）：`title: 海屿你` / `artist: 马也_Crabbit` / `assetid: 1:1973665667:`

播控中心展开卡片实测：主标题「其实-薛之谦」、副标题「你也没说平静的交错」——副标题即 `singleLyricText`，随播放位置逐行刷新。

**顺带修掉一个既有缺陷**：`setAVMetadata` 是**整条替换**语义，因此每次局部更新（推歌词、推单行）都必须重发 `duration`，否则进度条时长被打回 0。为此 `AVSessionManager` 用静态字段缓存了 `durationMs`/`currentLyric`/`lastLyricLine`。同时发现 `PlayerManager.publishDuration()` 以往只写 `AppStorage`、从不回灌 AVSession——播控进度条一直用的是**歌单声明的时长**而非播放器解析出的真实时长，本次接上 `AVSessionManager.updateDuration`（上面 `duration: 235286` 与 `lyric` 共存即为该修复的直接证据）。

**`np.bt_lyric` 的不确定性未消除**：本轮只在播控中心侧验证，无蓝牙 AVRCP 远端设备，开关按本节建议保留。

### 2.2 缺 `setLaunchAbility`：播控卡片点击无法跳转

自检表要求「点击播控卡片跳转指定页面」。

**SDK 确认**（`@ohos.multimedia.avsession.d.ts` 第 489 / 513 行）：

```
setLaunchAbility(ability: WantAgent, callback: AsyncCallback<void>): void;
setLaunchAbility(ability: WantAgent): Promise<void>;
```

**已静态确认**：全工程 `setLaunchAbility` grep **零命中**。用户从播控中心点卡片无法回到播放页。

改动量小（构造一个 `WantAgent` 指向 EntryAbility，可携带参数直达 NowPlaying），属低成本必接项。

**M10.1 已落地并设备实测（2026年08月24日）**：`AVSessionManager.bindLaunchAbility` 在 `init()` 内构造 `WantAgent`（`OperationType.START_ABILITY` + `UPDATE_PRESENT_FLAG`，`parameters` 带 `np.launch_from: 'avsession'`），`await session.setLaunchAbility(agent)`，失败仅告警不致命。实测：应用退后台后点展开卡片封面 → `aa dump -l` 显示 `state #FOREGROUND` / `app state #FOREGROUND`，截图确认直达播放页。

### 2.3 缺 `on('toggleFavorite')`：播控中心无法收藏

自检表把「收藏」列为音乐类必接项。

**SDK 确认**（第 1699 行）：`on(type: 'toggleFavorite', callback: (assetId: string) => void): void;`

**已静态确认**：`toggleFavorite` 在工程有 4 处命中，但**全部是工程自己的 UI 方法**，与 AVSession 无关：

- `view/components/SongRow.ets:25`（方法定义）、`:134`（菜单项 onTap）
- `view/pages/NowPlayingPage.ets:152`（方法定义）、`:342`（按钮 onClick）

AVSession 侧从未注册该命令。工程已有完整的收藏仓库（`data/LocalPlaylistRepository.ets`）和稳定歌曲身份（`stableKeyOf()`），接线只需把 `assetId` 映射回歌曲身份即可——而 `assetId` 当前格式是 `${song.platform}:${song.id}:${song.mediaUri}`（第 113 / 157 行），本身已包含还原所需的全部信息。

配套还需在 `AVPlaybackState` 中上报当前收藏态，否则播控中心的收藏图标无法反映真实状态。

**M10.1 已落地并设备实测（2026年08月24日）**：`session.on('toggleFavorite')` → `PlayerManager.toggleFavoriteByAssetId(assetId)`（先校验 assetId 与当前曲一致，不一致则丢弃并告警，防止陈旧卡片的迟到回调误改别的歌）→ `toggleFavoriteForCurrentSong()` 读 `LocalPlaylistRepository.isFavorite` 后 add/remove → `publishFavorite()` 同时写 `AppStorage('player.favorite')`、`AVSessionManager.setFavorite()` 与状态流，`AVPlaybackState.isFavorite` 随每次 `updatePlaybackState` 上报。`release()` 里配套 `session.off('toggleFavorite')`。

双向同步实测：应用内点收藏 → `hidumper` 的 `is favorite` false→true，播控卡片心形转为填充；播控卡片点心形 → true→false，应用内图标同步转空心。回调能触发本身也印证命令已注册（未注册的命令按 §2.4 会置灰）。

**顺带修掉一个全应用范围的资源缺陷**：`ic_baseline_favorite_24.svg` 与 `ic_outline_favorite_24.svg` 是 98 字节的空壳 svg（只有 `<svg>` 标签、无 `<path>`），58 个 svg 里唯此 2 个为空——收藏图标此前在应用内**完全不可见**。补齐 Material Design path 后设备截图确认：未收藏为空心、收藏后为实心红（`Theme.danger(false)` = `#C62828`）。影响面为 `IconCatalog.ets:52`、`Ui.ets:131`、`NowPlayingPage.ets:331/332` 三处。

### 2.4 按钮置灰的成因（对照自检表的「按钮置灰」项）

FAQ `FAQ/音频和视频/音视频播控_AVSession/为什么接入播控后_播控中心部分按钮是灰色的_不可点击/faqs-avsession-3`（**文档确认**）说明：播控中心依据应用**实际注册的控制命令**决定哪些元素可交互。

因此 §2.2 / §2.3 不只是「少了功能」，而是**播控中心会把这些按钮显示为灰色不可点击**——用户直接看到的是「这个播放器功能不全」。这是自检表把它们列为必接项的原因。

### 2.5 自检表全项对照

| 自检项 | 工程现状 | 差距 |
| --- | --- | --- |
| 媒体封面 | ✅ `mediaImage`（第 121 / 165 行） | — |
| 主标题 / 副标题 | ✅ **M10.1 已修**（§2.1，语义归位设备实测） | — |
| 进度与时间 | ✅ `duration` + `setAVPlaybackState`（另 M10.1 修复真实时长回灌） | — |
| **滚动歌词** | ✅ **M10.1 已补** `lyric`（§2.1，与 duration 共存实测） | — |
| 播放 / 暂停 | ✅ | — |
| 上一首 / 下一首 | ✅ | — |
| **按钮置灰** | ✅ **M10.1 后收藏命令已注册转可用**（§2.4） | — |
| **点击卡片跳转指定页面** | ✅ **M10.1 已补** `setLaunchAbility`（§2.2 设备实测直达播放页） | — |
| **收藏** | ✅ **M10.1 已补** `toggleFavorite`（§2.3 双向同步实测） | — |
| 循环模式 | ✅ `setLoopMode`（第 61 行） | — |
| **Cast+ 投播** | ❌ 零命中 | §9 |
| **DLNA 投播** | ❌ 零命中 | §9 |
| **应用内投播组件（半模态）** | ❌ 无 `AVCastPicker` | §9 |
| **一键冷启动播放** | ❌ 无意图注册 | §10.3 |
| **历史歌单** | ❌ 无意图注册 | §10.3 |
| **歌单推荐** | ❌ 需受限开放申请 | §10.2 |

前 10 项**已全部闭合**（M10.1 补齐了主副标题语义、滚动歌词、按钮置灰、卡片跳转、收藏 5 项差距，全部设备实测通过）。后 6 项分别属 §9 / §10。

---

## 3. P0 系统级桌面歌词：需修正 `FEATURE_MATRIX` 的 D4 结论

**这是本次检索价值最高的一项发现。**

`FEATURE_MATRIX.md` 第 33 行当前记录：

> **悬浮/状态栏歌词 D4 降级**（应用内悬浮条 `np.floating_lyric` + AVSession title 蹭位 `np.bt_lyric`——Android 仅蓝牙输出时生效的差异：鸿蒙由开关全局控制，AVRCP 远端刷新时机无官方承诺）

该结论的隐含前提是「鸿蒙没有系统级悬浮歌词能力，只能在应用内自己画一条」。**这个前提对 API 23 及以上不成立。**

**SDK 确认**（`@ohos.multimedia.avsession.d.ts`，全部 `@since 23`，基线 24 可用）：

| API | 位置 | 作用 |
| --- | --- | --- |
| `avSession.isDesktopLyricSupported(): Promise<boolean>` | 模块级函数 | 查询当前设备是否支持桌面歌词 |
| `session.enableDesktopLyric(enable: boolean): Promise<void>` | AVSession 实例 | 为本会话启用系统桌面歌词 |
| `session.setDesktopLyricVisible(visible: boolean): Promise<void>` | 同上 | 控制歌词窗显隐 |
| `session.isDesktopLyricVisible(): Promise<boolean>` | 同上 | 查询显隐态 |
| `session.onDesktopLyricVisibilityChanged(callback: Callback<boolean>)` | 同上 | 订阅显隐变化（用户可能自己关掉） |
| `session.offDesktopLyricVisibilityChanged(callback?)` | 同上 | 取消订阅 |
| `session.setDesktopLyricState(state: DesktopLyricState)` | 同上 | 设置状态，`DesktopLyricState.isLocked: boolean` 表示锁定态 |

关键标记（决定普通应用能否用）：

- **无 `@permission`** —— 不需要申请任何权限，包括不需要 Android 侧的 `SYSTEM_ALERT_WINDOW` 类悬浮窗权限
- **无 `@systemapi`** —— 不是系统应用专属
- `@stagemodelonly` —— 仅 Stage 模型，本工程正是 Stage 模型
- `@syscap SystemCapability.Multimedia.AVSession.Core`

配套错误码：`6600110`（本应用未启用桌面歌词）、`6600111`（设备不支持桌面歌词）。

**已静态确认**：全工程 `DesktopLyric` grep **零命中**。

### 3.1 这意味着什么

工程当前的应用内悬浮歌词条（`np.floating_lyric`）只能在**应用自身界面内**显示，一旦切到别的应用就消失——这正是 Android 侧用悬浮窗权限解决的问题，也是 D4 判定「降级」的实质。

系统桌面歌词是**系统绘制的独立歌词窗**，跨应用可见，且由系统管理显隐与锁定。这在能力上**不是应用内悬浮条的替代，而是它做不到的那部分**。

`isDesktopLyricSupported()` 这个查询函数本身的存在，说明这是**设备可选能力**——不同机型/形态可能返回 `false`，`6600111` 就是为此准备的。因此接入时必须先查询再调用，不能假定可用。

### 3.2 建议改动

1. 在 `AVSessionManager` 中先调 `isDesktopLyricSupported()`，结果缓存。
2. 支持时，把 `np.floating_lyric` 开关的语义扩展为三态或分成两个开关：应用内悬浮条 / 系统桌面歌词。
3. 系统桌面歌词依赖 `AVMetadata.lyric` 提供带时间轴的歌词内容 —— 与 §2.1 是**同一处改动的两个消费者**，建议合并实施。
4. 订阅 `onDesktopLyricVisibilityChanged` 以同步 UI 开关状态（用户可能从系统侧关闭）。

### 3.3 诚实标注

> **本节的「待验证」已于 2026年08月25日 M10.2 spike 执行完毕，结论见下方 §3.4。以下三条保留为调研当时的原始判断，其中第二条已被设备结果推翻。**

- **待设备验证**：以上全部基于 `.d.ts` 声明，本轮**未在模拟器或真机上实际调用过任何一个桌面歌词 API**。「API 存在且基线可用」只到 SDK 声明一级，**未到行为观测一级**。
- 模拟器很可能 `isDesktopLyricSupported()` 返回 `false`（与 `FEATURE_MATRIX.md` 第 32 行 USB 探针「模拟器无 USB host 属预期」同类情形），真机验证不可省。
- 沿用 `USB_M91_SPIKE.md` 的做法，建议先做一个 spike：查询支持性 → `enableDesktopLyric(true)` → 推一段 `lyric` → 观测系统歌词窗是否出现 → 记录结论，再决定是否投入产品化。

**在 spike 出结论前，不应把 `FEATURE_MATRIX.md` 第 33 行的 D4 结论改写为「已解决」**，但应当立即补一条注记说明该结论的前提已被 SDK 证据动摇。

### 3.4 M10.2 spike 结果（2026年08月25日，Pura 90 模拟器）

完整证据链见 `docs/DESKTOP_LYRIC_M102_SPIKE.md`；此处只记对本节判断的修正。

**已确认**：D4 的前提「鸿蒙无系统级悬浮歌词能力」不成立。ohosTest 探针 `ActsDesktopLyricProbeTest` 3/3 通过，服务层链路整条打通——正向 10 步全 ok（含 `activate` + `setAVPlaybackState`），可见性双向往返（`true`→回调→查询，`false`→回调→查询，共 2 次回调）。系统侧 `com.huawei.hmos.mediacontroller`(v6.1.0.512) 被真实拉起，日志逐字回显我们经 §2.1 改动推送的完整 LRC，并**自己解析出 2 行**（`MDL_Util, analyzeLyric end, length = 2`）——即**系统桌面歌词与 §2.1 的 `AVMetadata.lyric` 确实是同一处改动的两个消费者，§3.2 第 3 条的判断得到证实**。

**推翻了上面第二条**：`isDesktopLyricSupported()` 在**模拟器上返回 `true`**，不是预想的 `false`。

**排除了 stub 可能**：负向用例故意跳过 `enableDesktopLyric` 直接调 `setDesktopLyricVisible`，被 `6600110` 拒绝且错误文本来自 native 侧（`native desktop lyrics feature of this application is not enabled`）——系统在真实追踪每应用启用态。这一步很关键，否则「10 步全 ok」无法排除「API 是无条件返回成功的空实现」。

**未取得的证据**：窗口存活期内截图 3 次全为纯桌面；完整窗口树 30 个窗口全属 SceneBoard，无 mediacontroller 条目；图形栈报 `TakeSurfaceCapture failed, node is nullptr` 与 `isSupportHdsMaterial: false`。指向模拟器图形栈限制，但这是**推断而非证明**。

**因此 §3.2 的建议改动维持有效，但排期不变**：真机复跑确认渲染层之前，不投入产品化。真机清单见 spike §6。

---

## 4. P0 音频低功耗与音质加固

官方音乐播放低功耗规则（**文档确认**，文档 ID `最佳实践/应用功耗优化/前台任务低功耗/前台资源合理使用/音乐播放场景低功耗规则/bpta-music-playback-scenarios`）给出三条：

1. 静音时设 `setAudioEffectMode(audio.AudioEffectMode.EFFECT_NONE)`
2. `audioRendererInfo.usage = audio.StreamUsage.STREAM_USAGE_MUSIC` 才能走系统音乐低功耗方案
3. 后台播放只需向 AVSession 上报 duration / 播放状态 / position / 倍速，**不要实时刷进度**（避免 binder 负载）

工程现状（**已静态确认**，`player/PlayerManager.ets`，共 1318 行）：

```
803: player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
```

`audioRendererInfo` grep 零命中、`StreamUsage` 零命中、`audioEffectMode` 未设置。

> **以上是调研当时（2026年08月24日）的现状快照，M10.3 已于 2026年08月25日落地，`audioRendererInfo` / `StreamUsage` 现已命中。三条规则的最终结论见下方 §4.1 / §4.2 / §4.3 各自的落地记录，与调研时的判断有两处出入：规则 1 改判为不适用，规则 2 的价值下调为纯防御。**

### 4.1 关于规则 2 的自我修正

**先前判断有误，此处按 SDK 原文修正。**

SDK 原文（**SDK 确认**，`@ohos.multimedia.media.d.ts` 第 2714–2725 行）：

> Describes audio renderer info. **If the media source contains videos, the default value of usage is STREAM_USAGE_MOVIE. Otherwise, the default value of usage is STREAM_USAGE_MUSIC.** This parameter can be set only when the AVPlayer is in the initialized state.

也就是说：**纯音频源的 `usage` 默认就是 `STREAM_USAGE_MUSIC`**。工程未显式设置，**不等于违反规则 2**。先前把这条列为「合规缺口」是错的。

那么显式设置的价值在哪？在于**防御性**：

- 工程播 Bilibili 时走 `fnval=272` DASH 的 audio 数组 `baseUrl`（`FEATURE_MATRIX.md` 第 22 行，M4.6/M4.7），是纯音频 URL，默认值成立。
- 但一旦**任何**取流路径返回含视频轨的容器（B 站接口形态变化、YTM 某些 itag、将来新增源），`usage` 会**静默变成 `STREAM_USAGE_MOVIE`**，从而**静默退出音乐低功耗方案**，且没有任何日志或报错提示。

因此建议：在 `initialized` 状态显式设 `audioRendererInfo.usage = STREAM_USAGE_MUSIC`，把「依赖容器内容推断」变成「显式声明」。**这是加固，不是修 bug。**

注意状态机约束：SDK 明确 `audioRendererInfo` **只能在 `initialized` 状态设置**，且需在首次 `prepare()` 之前设置才生效。工程 `PlayerManager.ets` 第 920 行 `createAVPlayer()` 之后、`setMediaSource()`（第 794 行）与 `prepare()` 之间是正确的插入点。

**M10.3 已落地并设备实测（2026年08月25日，Pura 90 模拟器）**：`PlayerManager` 载源序列在 `await PlayerManager.waitForState(['initialized'])` 之后、`await player.prepare()` 之前插入 `player.audioRendererInfo = { usage: STREAM_USAGE_MUSIC, rendererFlags: 0 }`，失败仅 `Logger.warn` 不致命。

**设备实证把「加固」这个定性钉死了，同时也确认它没有变成修 bug**。新增 ohosTest 探针 `entry/src/ohosTest/ets/test/AudioRendererProbe.test.ets` 用例 `audioOnlySourceDefaultsToMusicUsage`，在 `initialized` 态先读默认值再设置，`prepare()` 后回读生效值：

```
AudioRendererProbe defaultUsage=1 (initialized)
AudioRendererProbe setAudioRendererInfo=ok
AudioRendererProbe effectiveUsage=1 expected=1
AudioRendererProbe defaultWasAlreadyMusic=true
```

`1` 即 `STREAM_USAGE_MUSIC`。**SDK 那句默认值声明在本设备上成立，所以这次改动对今天的所有音源都不改变任何行为** —— 价值只在于「容器含视频轨时不会静默退出音乐低功耗方案」这条未来防御，以及满足 §4.4 `setLoudnessGain` 的 `usage` 前置条件。代码注释同样逐字写了 `It is not a bug fix`，避免后来者把它读成缺陷修复。

真实产品路径也一并验证：真机操作播放三首曲目，hilog 每次都出现完整的 `AVPlayer state: initialized → prepared → playing`，说明插入的赋值没有阻断载源序列（该 API 在 `initialized` 态之外调用会抛错，这是唯一的实际风险）。

### 4.2 规则 1：静音时 `EFFECT_NONE`（真实缺口）

**SDK 确认**：`audioEffectMode?: audio.AudioEffectMode`（`@since 12`），`EFFECT_NONE = 0` / `EFFECT_DEFAULT = 1`。

SDK 原文补充了一条**容易踩的坑**：

> The audio effect mode is a dynamic attribute and is **restored to the default value EFFECT_DEFAULT when usage of audioRendererInfo is changed**. It can be set only when the AVPlayer is in the **prepared, playing, paused, or completed** state.

两个约束都要落到实现里：

- 音效模式是**动态属性**，`usage` 变更时会被复位为 `EFFECT_DEFAULT` —— 若与 §4.1 同时实施，需注意设置顺序。
- 只能在 `prepared` / `playing` / `paused` / `completed` 状态设置，不能在 `initialized` 设。

工程当前未设置该属性，静音场景下仍走默认音效链路。这条是**真实缺口**，但影响面窄（仅静音时省电），改动也小。

**M10.3 结论：不适用，未实施（2026年08月25日）**。落地时才发现前提不成立 —— **工程根本没有静音这个场景**：

- `setVolume` 在 `entry/src/main` 下 **零命中**（AVPlayer 的音量 API 一次都没调用，音量完全交给系统音量键）
- `mute` / `Mute` 的全部命中都是色彩术语（`Palette` 的 `muted` 色板）与一处无关注释，没有任何静音开关
- `audioEffectMode` 在 `main` 下零命中（这本来就是缺口的定义）

规则 1 的原文条件是「静音时」设 `EFFECT_NONE`。没有静音入口，就没有可以挂钩的时机点 —— 在播放中无条件设 `EFFECT_NONE` 是关闭音效，那是产品决策而非低功耗合规，不能借这条规则的名义做。

所以这条从「真实缺口」改判为**不适用**。若将来加入应用内音量/静音控制（Android 版也没有），此条自然复活，届时须注意 §4.1 的 `usage` 设置会把该属性复位为 `EFFECT_DEFAULT`，顺序上必须后设音效模式。

### 4.3 规则 3：后台不实时刷进度（需走查）

**待复核**。工程 `AVSessionManager.ets` 第 197 行 `setAVPlaybackState(playbackState)` 的调用频率与前后台状态的关系，本轮未走查。规则 3 的要求是后台**不要**实时刷进度（系统会自行按 duration/position/倍速外推）。

建议走查 `PlayerManager` 的进度发布路径，确认后台时是否降频或停止上报。这项属于「可能已合规也可能不合规」，需读代码确认，不宜先下结论。

**M10.3 走查完毕并设备实测（2026年08月25日，Pura 90 模拟器）：频率本身早已合规，但走查顺带抓出两个真缺陷，且它们的方向与规则 3 相反 —— 不是推太多，是漏推。**

先说频率。`onTimeUpdate` 回调里没有任何 `setInterval`，且已有两级节流：进度发布 500ms、持久化 15s。更关键的是 **500ms 那级只写 `AppStorage`，从不进 AVSession**，所以规则 3 关心的 binder 负载压根不存在。设备侧直接证实了这一点 —— 一首曲子从 03:35:40 播到 03:38:36（176 秒），期间 `hidumper -s AVSessionService -a '-show_controller_info'` 读到的基准**一次都没变**：

```
state        : playing
speed        : 1.000000
elapsed time : 0
update time  : 1787600140482      ← 恒等于 03:35:40.482，即 playback started 时刻
```

这就是规则 3 背后的机制被看见了：系统不轮询我们，它用 `position.elapsedTime` + `updateTime` + `speed` 三个数**外推**播控中心（以及桌面歌词窗）的进度。**所以正确的上报时机是「外推基准发生变化时」，而不是「定时」。**

按这个判据重新审视，工程漏了两处基准变化：

1. **`seekTo` 从不回灌 AVSession**（真缺陷）。seek 改变了基准，但 `status` 不变，于是没有任何路径把新基准推给系统 —— 播控中心会一直从 seek 前的旧基准继续数，直到下一次 play/pause 才纠正。
2. **上报的是请求倍速而非量化后的实际倍速**（真缺陷）。API 24 只接受固定档位，`toPlaybackSpeed()` 会量化；上报请求值则外推斜率与真实播放速率不一致，必然持续漂移。

修法：抽出统一入口 `publishSessionPlaybackState()`，由 `publishStatus()` / `seekTo()` / `applyEffectiveSpeed()` 三处调用；倍速经 `effectivePlaybackSpeed()` 走量化后的值。`seekTo` 里同时把 `positionMs` 与 `lastTimeMs` 一起重基准 —— 后者是因为 `onTimeUpdate` 按 `timeMs - lastTimeMs` 累计"已听时长"，向前 seek 会把跳过的区间当成听过的记进去。

设备取证（三次 seek + 一次改倍速，全程 `paused` 且 hilog 无任何新的 `stateChange`，所以两次 dump 之间唯一的动作就是被测操作，归因干净）：

| 操作 | elapsed time | update time | speed |
| --- | --- | --- | --- |
| 暂停后（基准 A） | 24006 | 1787600401896 | 1.000000 |
| 后退 seek 后（B） | 0 | 1787600428075 | 1.000000 |
| 向前 seek 后（C） | 30040 | 1787600750133 | 1.000000 |
| 切 1.25x 后（D） | 30040（不变） | 1787600792375 | **1.250000** |

`elapsed` 精确跟随每次 seek 落点、`update time` 每次刷新到操作时刻；改倍速只动 `speed` 与 `update time` 而不动 `elapsed`。修复前 B/C/D 三行的三个字段都会停留在 A 行的值。

**附带修掉的第三个缺陷（单测抓出，非走查）**：倍速量化的边界用的是档位值本身而非中点，导致 `0.75 × 1.05 = 0.7875` 落到 1.00x —— 一次一起听的 5% 漂移修正被静默放大成 **33% 加速**。量化逻辑连同其逆映射抽到新文件 `player/PlaybackSpeedMap.ets`（纯逻辑、无 `@kit` 依赖，与 `AudioInterruptPolicy.ets` 同一安排）以便单测，边界改为中点，由 `PlaybackSpeedMap.test.ets` 的 `keeps UI steps lossless across the whole sync-rate clamp` 钉死全部六个 UI 档位在 `[0.95, 1.05]` 钳制区间内的无损性。

### 4.4 附带发现：`setLoudnessGain`（P2 增值）

**SDK 确认**（`@ohos.multimedia.media.d.ts`，`@since 21`）：

```
setLoudnessGain(loudnessGain: number): Promise<void>;
```

- 范围 −90.0 dB ~ +24.0 dB，默认 0.0 dB
- 可在 `prepared` / `playing` / `paused` / `completed` / `stopped` 状态调用
- **要求 `audioRendererInfo.usage` 为 `STREAM_USAGE_MUSIC` / `STREAM_USAGE_MOVIE` / `STREAM_USAGE_AUDIOBOOK`** —— 与 §4.1 显式设置 `usage` 形成依赖：做了 §4.1 才能稳定用这个 API

对音乐播放器而言这是实用能力（音量归一化 / 响度对齐 / 用户增益），基线 24 内可用，零审批。列 P2 因为它是增值而非规范要求。

**M10.3 设备实证：该 API 在此设备类上是永久挂起的桩，判定不接入（2026年08月25日，Pura 90 模拟器）。**

`@since 21` 在基线 24 之内、`.d.ts` 声明齐全、§4.1 的 `usage` 前置条件已满足 —— 纸面上全部条件成立。但探针用例 `loudnessGainIsReachableWithMusicUsage` 四次调用**全部既不 resolve 也不 reject**：

```
AudioRendererProbe setLoudnessGain(-6.0)=hung(>10000ms)
AudioRendererProbe setLoudnessGain(100.0)=hung(>10000ms)
AudioRendererProbe setLoudnessGain(-6.0)/playing=hung(>10000ms)
AudioRendererProbe setLoudnessGain(0.0)=hung(>10000ms)
```

第二行是判据里最硬的一条：`100.0` 超出文档的 `-90.0 ~ +24.0` 范围，本该立刻返回 `401` 参数校验失败，**连它都不返回**，说明调用根本没走到参数校验，即整条实现是空的而非"不生效"。第三行排除了「只在 `prepared` 态无效」的解释 —— `playing` 态同样挂起。

**接入的后果不是"没效果"，而是吊死调用链**：`await player.setLoudnessGain(...)` 会永久挂起在那一行。探针本身第一次运行就是这么撞上的：卡满 hypium 的 120s 超时，且因为卡在 `await` 上，连它之前的 `Logger` 都没冲出来，日志完全空白。这也是探针里那个 `withTimeout()` 包装的由来 —— 挂起要能被归因到具体某一次调用才算发现，否则只是一次无输出的超时。

结论：`@since` 标记不等于有实现。此项从 P2 移出待办，改为**已否决**；若将来在真机上复验为可用，接入时**必须**带超时包装，不得裸 await。

---

## 5. P1 服务卡片（Form Kit）

官方为音乐场景提供了专门的卡片指导（**文档确认**）：

- `最佳实践/服务卡片/音乐服务卡片/bpta-music-card`
- `开发指南/Form_Kit_卡片开发服务/ArkTS卡片开发_推荐/ArkTS卡片最佳实践/音乐服务卡片/arkts-ui-music-service-form`

官方列出音乐类四种卡片形态：**音乐播控**、**动态歌词**、**歌单推荐**、**心动歌词**。

### 5.1 工程现状

**已静态确认**（`entry/src/main/module.json5`）：只有一个 `EntryAbility`，**没有 `extensionAbilities` 段**。

```json5
"mainElement": "EntryAbility",
"pages": "$profile:main_pages",
"abilities": [{ "name": "EntryAbility", ... "backgroundModes": ["audioPlayback"] }],
"requestPermissions": [ INTERNET, GET_NETWORK_INFO, KEEP_BACKGROUND_RUNNING, READ_AUDIO ]
```

`FormExtensionAbility` / `formBindingData` / `postCardAction` grep 全部零命中。桌面上没有任何 NeriPlayer 卡片。

### 5.2 SDK 可用性

**SDK 确认**：

| API | `@since` | 说明 |
| --- | --- | --- |
| `@ohos.app.form.FormExtensionAbility` | **9** | 静态卡片提供方，基线可用 |
| `@ohos.app.form.formProvider` | — | `updateForm()` 主动刷新 |
| `@ohos.app.form.formBindingData` | — | 卡片数据绑定 |
| `@ohos.app.form.LiveFormExtensionAbility` | **20** | **动态卡片**（支持通用事件与自定义动效），基线可用 |

### 5.3 静态 vs 动态的取舍

**文档确认**：动态卡片支持通用事件与自定义动效，但**内存开销大**；静态卡片通过 `FormLink` 跳转，**内存可控**。

对 NeriPlayer 的建议：**先做静态播控卡片**。理由：

- `RELEASE_CHECKLIST.md` 记录内存实测 127–151MB。动态卡片会额外增加常驻开销，而卡片进程的内存问题不体现在应用自身的内存曲线里，容易失控且难归因。
- 播控卡片的核心价值是「不进应用就能控制播放 + 点击回到播放页」，静态卡片配 `FormProvider.updateForm()` 已经足够。
- 动态歌词卡片虽然对音乐应用很有吸引力，但它与 §3 的系统桌面歌词**功能重叠**（都是「不在应用内也能看歌词」）。既然系统桌面歌词零权限、零额外进程，应当**先验证 §3，再决定是否需要动态歌词卡片**。

### 5.4 生命周期与刷新

**文档确认**：`FormExtensionAbility` 生命周期为 `onAddForm` / `onUpdateForm` / `onFormEvent` / `onRemoveForm`；主动刷新用 `FormProvider.updateForm()`；官方推荐用 `relationalStore` 持久化卡片数据。

**这里有一个与工程现状的冲突需要注意**：卡片运行在**独立进程**中，无法直接读取应用进程的 `AppStorage`。而工程的播放器状态发布机制正是 `AppStorage`（`PORTING.md` 关键设计决策第 2 条：「`PlayerManager` 通过 AppStorage（`player.*`）发布快照」）。

因此接入卡片必须**新增一条跨进程的状态通道**。工程当前用 `preferences`（`data/SettingsRepository.ets`），官方推荐 `relationalStore`。这是一项实打实的架构改动，不是「加个卡片布局」那么轻——需求评估时不应低估。

### 5.5 沉浸式卡片取色

**文档确认**：官方建议用 `@ohos.effectKit` 的 `ColorPicker.getMainColor()` 提取封面主色做沉浸式卡片背景。

工程已有自研纯 ArkTS 取色（`view/theme/Palette.ets`，`FEATURE_MATRIX.md` 第 33 行：「vibrant→muted→dominant 嵌套回退 + LRU/单飞，`adjustedAccent` 1:1 对齐 Android HSL 压制」），`effectKit` grep 零命中。

**建议不替换自研 Palette**。理由：自研实现的价值在于**与 Android 上游 1:1 对齐**（这是等价性移植的核心诉求），换成 `effectKit` 会引入取色差异，得不偿失。若做卡片，可在卡片侧单独用 `effectKit`（卡片进程内无法复用应用进程的 LRU 缓存，自研实现搬过去也要重算），或把主色随卡片数据一起传过去。

---

## 6. P1 `Navigation` 迁移

**文档确认**：官方推荐 `Navigation` + `NavDestination` + `NavPathStack`，并已将 `router` 标为**不推荐**。响应式规则：<600vp 单栏、≥600vp 分栏、`NavigationMode.Auto`。

### 6.1 工程现状

**已静态确认**：

- `entry/src/main/resources/base/profile/main_pages.json` 内容为 `{"src": ["pages/Index"]}` —— **单页应用**
- 路由是自研的：`view/Router.ets` + `view/RouteStack.ets`，基于 `AppStorage` 的 `route.stack` / `route.name` / `route.param`，11 个路由常量
- `Navigation(` grep 零命中

工程自研路由目前是**可用且已验证**的：`FEATURE_MATRIX.md` 第 13 行记录 M9.3 完成「17 页逐页 `keyEvent Back` 退出且下一页身份正确」的设备验证，第 13 行另记录返回栈遗留缺陷已修并验证。`Router.ets` 注释还记录了一个设备实测结论：

> Index.onBackPress consumes the system back key while canPop() is true. Without that, back on any detail page backgrounded the whole ability (device-observed 2026-08-24)

### 6.2 建议：列 P1 但不急于动

`hm.md` §6.2 早已建议迁 `Navigation`（未落地）。本文维持该建议，但要如实说明**收益与风险的对比**：

**收益**：

- 官方推荐路径，`router` 已标不推荐，长期看有维护风险
- `NavigationMode.Auto` 自带 ≥600vp 分栏 —— 这对 §7.2 的 tablet / 2in1 适配是**直接收益**，自研路由要自己实现分栏
- 系统级转场动画与手势返回，体验更「鸿蒙」

**风险**：

- 自研路由已通过 17 页 × 3 档字号 × 2 形态的设备回归（M9.3），迁移意味着**这批验证全部作废并需重做**
- `Index.onBackPress` 那条设备实测结论说明返回键交互存在过真实踩坑，`Navigation` 的返回语义不同，可能引入新的同类问题
- 迁移不产生任何**用户可见的新功能**

**结论**：建议在**下一次需要动布局的里程碑**（例如 M9.3a 解封做 tablet/2in1 适配时）**顺带迁移**，让分栏收益抵掉迁移成本；不建议单独立项做纯迁移。这也与 §7.2 天然合并。

---

## 7. P1 一多与设计规范

官方设计最佳实践（**文档确认**，官网页面 `https://developer.huawei.com/consumer/cn/doc/design-guides/practices-overview-0000001746498066`）呈三层结构：

1. **基础要求**：导航适配 / 横竖屏与挖孔 / 多窗 / 弹出框（≤400vp 且高度 ≤手机 1.5 倍）/ 键鼠 / 体验评估标准
2. **响应式布局**：形变 / 延伸 / 重复 / 挪移 / 宫格 / 瀑布流
3. **增值体验**：沉浸、分栏（8 栅格以上）、应用内分屏、双指缩放、浅层窗口半模态、侧边面板、长按预览、跟手弹框、**折叠屏悬停态**

### 7.1 折叠屏悬停态（官方点名「听歌」场景）

**文档确认**（文档 ID `最佳实践/多设备界面开发/特殊界面布局场景/折叠屏悬停态/bpta-folded-hover`）：官方明确把**「听歌」**列为适合悬停态的场景。

规格要点：

- 上半屏内容由中线**向上避让 16vp（约 3mm）**
- 下半屏内容**向下避让 40vp（约 7mm）**
- **操作型控件建议放在下半屏**
- 相关组件：`FoldSplitContainer`

对 NeriPlayer 的映射很自然：**上半屏封面 + 歌词，下半屏播控按钮 + 进度条**。这正是悬停态最典型的音乐应用形态。

**工程现状**：`FEATURE_MATRIX.md` 第 13 行记录 M9.3 已覆盖「foldable 展开内屏 707vp（Mate X7 2210×2416@3.125）17 页全清」——即**展开态**布局已验证，但**悬停态未适配**（悬停是折叠角度介于中间的独立状态，非展开也非折叠）。

同一行还记录了一条重要约束：

> 折叠**外**屏 346vp（折叠态由 Posture/Hall 传感器驱动，hdc 无法注入）

即**折叠状态无法用 hdc 注入模拟**。悬停态同理依赖 Posture 传感器，所以悬停态适配**必须真机验证**，模拟器不可替代。这与 `PORTING_EXECUTION_PLAN.md` M9.3a 的阻塞性质相同（缺设备/镜像），需一并规划。

补充：`devecocli emulator fold <state>` 支持 `foldable` 的 `open|half-open|close`（其中 `half-open` 即半开/悬停），**这可能是一条绕过真机限制的路径**，但本轮未验证该命令对 Posture 传感器的注入是否能被应用侧的折叠态监听真正感知到。列为待验证项。

### 7.2 断点与响应式：tablet / 2in1 仍未验证

**已静态确认**：`module.json5` 的 `deviceTypes` 为 `["phone", "tablet", "2in1"]` —— 已声明支持三种形态。

**但 `FEATURE_MATRIX.md` 第 13 行明确记录未验证**：

> **未验证**：tablet 2880×1920 与 2in1 3120×2080（镜像未下载，见执行计划 M9.3a）、折叠外屏 346vp、横屏（`module.json5` 未锁方向但未走查）、真机

这里存在一个**上架风险**：`deviceTypes` 声明了 tablet 与 2in1，意味着这两种设备的用户能装到应用，但布局从未验证过。要么补验证，要么在验证前收窄 `deviceTypes`。**声明支持而未验证，比不声明更糟。**

`PORTING_EXECUTION_PLAN.md` M9.3a 的阻塞原因已查明：本机只有 `phone_all_x86` 镜像，需 GUI 下载 `tablet_x86` 与 `pc_all_x86`，而 `Emulator.bat -imageList/-install` 在无 GUI 会话下退出码 0、零输出、无副作用。

**建议**：M9.3a 解封时，把 §6（Navigation 迁移，`NavigationMode.Auto` 自带分栏）与 §7.1（悬停态）**合并为一个「一多适配」里程碑**，一次性完成布局改动 + 回归。分三次做会导致布局回归重复三遍。

另需注意官方基础要求中的**横竖屏**与**多窗**：`module.json5` 未锁方向且未走查横屏，2in1 形态下多窗（自由窗口缩放）也未验证。这两项与 tablet/2in1 镜像是同一批工作。

### 7.3 触控目标 40vp → 48vp

**已静态确认**（`RELEASE_CHECKLIST.md` §3.3–§6）：触控目标实测为 **40vp 下限，未达 48vp 推荐值**。

这是官方基础要求中明文的推荐值。改动本身机械（调整组件最小尺寸），但会**影响既有布局**——`FEATURE_MATRIX.md` 第 13 行记录 M9.3 修过 3 处字号缺陷，其中「SongRow 序号角标与时长真重叠」的根因是「百分比 `.position()` 按父容器实测宽度解析、字号放大即失稳」。把触控目标从 40vp 提到 48vp 会再次改变行高与间距，**需重跑布局树度量回归**。

因此这项虽然简单，也应并入 §7.2 的「一多适配」里程碑统一回归，而不是单独改。

### 7.4 无障碍现状

**已静态确认**（`RELEASE_CHECKLIST.md` §3.3）：21 处 `.accessibilityText` 覆盖 13 个文件，**但仅代码确认**——`uitest dumpLayout -e accessibilityText` 被拒绝，报 `Invalid attribute name, currently supported names are 'uniqueId'`，无法从 dump 侧核验。

即无障碍标注**只到源码一级，未到运行时一级**。这条不是新发现，此处记录以说明它与官方「体验评估标准」的关系：屏幕朗读是体验评估的检查项，而当前缺少可自动化的核验手段。若要闭环，需真机开屏幕朗读人工走查。

---

## 8. P1 应用外观规范

### 8.1 分层图标

**文档确认**（文档 ID `开发指南/开发基础知识/典型场景的开发指导/配置应用图标和名称/layered-image`、`最佳实践/程序包结构/应用图标配置与开发/bpta-app-icon-configuration`、`开发指南/UI_Design_Kit_UI设计套件/图标处理/推荐_分层图标处理/ui-design-layered-process`）。

分层图标（前景层 + 背景层）是 HarmonyOS 桌面图标的标准形态，支持系统的图标动效、主题化与形状裁切。UI Design Kit 提供 `hdsDrawable` 辅助处理。

**已静态确认**：`AppScope/resources/base/media/` 下只有 `app_icon.png`，**无分层图标配置**。

后果：桌面图标无法参与系统图标动效与主题化，视觉上与原生应用有差异。这是**上架前的外观规范项**，改动量小（补前景/背景资源 + `app.json5` 配置），无代码风险，建议尽早做。

### 8.2 多语言资源

**已静态确认**：`entry/src/main/resources/` 下只有 `base` 和 `dark` 两个目录，**无任何多语言限定词目录**（无 `en_US` / `zh_CN`）。

**文档确认**：`最佳实践/多设备资源文件/bpta-multi-device-resource`。

现状与既有记录一致：`RELEASE_CHECKLIST.md` §6 已登记设置页三处占位，其中 `SettingsDetailPage.ets:897` / `:899` 正是**语言切换占位**。即工程已有语言切换入口但无实际资源。

**建议**：列 P2 而非 P1。理由是「加语言」是范围可无限扩张的工作（全部 UI 文案外化 + 翻译 + 各语言下重跑布局回归，而 §7.2 记录布局对字号/宽度已经很敏感），而当前工程的核心矛盾不在国际化。但**设置页的语言切换占位应当明确标注为未实现**，不能让用户看到一个点了没反应的开关——这条已在 `RELEASE_CHECKLIST.md` §6 登记，维持。

---

## 9. P2 投播（Cast+ / DLNA / AVCastPicker）

自检表把三项投播列为音乐类检查项：**Cast+ 投播**、**DLNA 投播**、**应用内投播组件（半模态）**。

**文档确认**（文档 ID `最佳实践/多端协同/音频投播/bpta-audio-cast`、`开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控检查项详细说明/音视频投播/avcastpicker`）：官方建议封装三个模块——本端音频控制器 / 媒体会话控制器 / 音频投播控制器；组成为 AVSession（设备连接）+ AVCastPicker（系统级投播 UI 组件，可内嵌应用界面）+ AVCastController（控制远端播放）。

**SDK 确认**：

| API / 模块 | 位置 | 说明 |
| --- | --- | --- |
| `session.getAVCastController()` | avsession.d.ts 第 826 / 846 行 | 获取投播控制器 |
| `session.on('outputDeviceChange', (state: ConnectionState, device: OutputDeviceInfo) => void)` | 第 1799 行 | 输出设备变化 |
| `session.stopCasting()` | 第 2157 / 2173 行 | 停止投播 |
| `AVCastControlCommandType` | 第 2259 行 | 含 `'toggleFavorite'` / `'toggleMute'` / `setVolume` / `setSpeed` / `setLoopMode` 等 |
| `@ohos.multimedia.avCastPicker.d.ets` | SDK 中存在 | AVCastPicker 组件 |
| `@ohos.multimedia.avCastPickerParam.d.ts` | SDK 中存在 | 组件参数 |
| `on('castControlGenericError')` | 第 2991 / 3014 行 | 投播错误回调 |

**已静态确认**：`getAVCastController` 零命中、`AVCastPicker` 零命中。

### 9.1 为何列 P2 而非 P0

投播是自检表检查项，按理应与 §2 同级。但对本项目降级为 P2，理由如下：

- **验证成本高且当前无法满足**：投播必须有**接收端设备**（智慧屏 / 支持 Cast+ 的音箱 / DLNA 设备）。模拟器无法验证，`FEATURE_MATRIX.md` 记录的双设备验收（Pura 90 + Mate X7）也不构成投播接收端。这与 §3 桌面歌词只需一台真机不同——投播需要**额外的硬件品类**。
- **与取流方案存在潜在冲突**：工程三平台取流都依赖注入请求头（`network/StreamHeaders.ets`：Referer + 桌面 UA + 登录 Cookie，`FEATURE_MATRIX.md` 第 22 行记录「无 Referer CDN 403」）。投播把 URL 交给**远端设备**去拉流，远端设备**不会带这些头**。这意味着 B 站/YTM 的流**大概率投播不出去**。这个冲突需要先做技术验证才知道范围，不能假定投播接进来就能用。
- 相比之下 §2 / §3 / §4 全部零硬件依赖、零外部条件。

**建议**：先做一个**可行性 spike** 而非直接实现——重点验证「注入请求头的流能否被远端拉取」。若结论是不能，那么投播对本项目只能覆盖本地音乐（`data/LocalMediaScanner.ets` 路径），价值大幅缩小，届时再定优先级。这个结论应当在投入 UI 实现**之前**拿到。

---

## 10. P3 需申请或超基线的能力

本节全部能力的共同前置是「应用能在 AGC 上架」，而这在本项目是未决问题（见 §1 末尾与 `RELEASE_CHECKLIST.md` §5.3）。

### 10.1 实况窗（Live View Kit）

**文档确认**（文档 ID `开发指南/Live_View_Kit_实况窗服务/实况窗设计规范/liveview-design-formula`、`.../开发准备/申请实况窗正式权限/liveview-formal-authority`、`FAQ/实况视图服务_Live_View_Kit/哪些系统服务会自动接入实况窗/faqs-liveview-5`）。

**SDK 确认**：`@hms.core.liveview.liveViewManager.d.ts`、`@hms.core.liveview.LiveViewLockScreenExtensionAbility.d.ts` 在 SDK 中存在。

关键信息，逐条如实记录：

- **FAQ 明确 AVSession Kit 会自动接入实况窗** —— 这意味着工程接了 AVSession，**可能已经间接获得部分实况窗能力**而无需自己调 `liveViewManager`。这条值得在真机上先观察一下现状，再决定是否需要主动接入。
- 正式权限需 **AGC 申请 + 评审 7 工作日**
- 单实况窗生命周期 **≤8 小时**
- **超 2 小时未更新则状态栏/锁屏胶囊隐藏**
- 官方**推荐用 Push Kit 更新**，因为本地更新依赖应用进程存活

最后两条对音乐播放器不太友好：音乐播放会话可以很长（超 8 小时上限），而「本地更新依赖进程存活」与工程的后台播放模型耦合。若走 Push Kit 更新，则需要**服务端**——本项目没有自建服务端（「一起听」用的是上游的 worker，见 `FEATURE_MATRIX.md` 第 31 行）。

**结论**：不建议主动接入。建议只做一件事：**在真机上观察 AVSession 是否已自动带来实况窗表现**，把观察结果记录下来。这是零成本的。

### 10.2 播控推荐服务

**文档确认**（文档 ID `开发指南/AVSession_Kit_音视频播控服务/播控推荐服务/avsession-recommendation`）：

- **受限开放**，需发邮件至 `support@huawei.com` 申请，约 5 个工作日
- **仅中国大陆**
- 面向应用市场「影音娱乐 - 音乐/电台」分类
- 按最近 30 天使用时长分配资源位

这对应自检表的「歌单推荐」项。

**结论**：完全依赖上架 + 分类归属 + 使用量，与当前项目阶段不匹配。**不建议投入**，仅记录以说明自检表该项为何无法完成。

### 10.3 意图框架（Intents Kit）：快捷播放

**文档确认**（文档 ID `开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控检查项详细说明/快捷播放/quick-playback`）：注册 `PlayMusicList` 意图（音乐类）或 `PlayAudio` 意图（听书类），即**同时获得**三项自检表能力：

- 播放按钮一键**冷启动播放**
- **历史歌单**
- **歌单推荐**

**SDK 确认**：`@ohos.app.ability.InsightIntentDecorator.d.ts`（`@since 20`，声明式意图装饰器）、`@ohos.app.ability.InsightIntentExecutor.d.ts`、`@ohos.app.ability.insightIntentProvider.d.ts`、`@hms.ai.insightIntent.d.ts` 均在 SDK 中存在，基线 24 可用。

**已静态确认**：`insightIntent` grep 零命中。

**评估**：这是本节中**唯一在基线内、无需 AGC 审批、且一次改动换三项自检表能力**的项。技术上并不依赖上架。

但它有一个隐含依赖：意图注册后的实际效果（小艺唤起、桌面快捷播放、历史歌单展示）**需要系统侧配合**，而这些入口的行为在模拟器上很可能无法完整观测。工程已有的冷启动续播能力（`FEATURE_MATRIX.md` 第 17 行：「队列 + 位置 + 模式跨冷启动恢复」已有单测 + ohosTest + 模拟器实证）是意图框架「一键冷启动播放」的**现成基础**，接线成本不高。

**建议**：从 P3 中**单独提出，实际按 P2 对待**。它是本节唯一值得投入的一项。列在 P3 是因为效果验证依赖系统侧入口，存在「做完了但看不到」的风险——与 `FEATURE_MATRIX.md` 第 31 行 M7.3a 的教训相同（「在生产侧尚无引用者，设备上无新行为可观测」）。

### 10.4 `setMediaCenterControlType`：基线不可用

**文档确认**（文档 ID `开发指南/AVSession_Kit_音视频播控服务/自定义播控中心控制按钮显示布局/avsession-mediacentercontroltype-scene`）：`setMediaCenterControlType` + `setSupportedLoopModes` + `setSupportedPlaySpeeds` 三者配合，可自定义播控中心的三元组/五元组按钮布局。文档标注 **API 26.0.0 起**。

**SDK 确认（反向证据）**：在本机 API 24 SDK 的 `@ohos.multimedia.avsession.d.ts` 中 grep `setMediaCenterControlType` / `setSupportedLoopModes` / `setSupportedPlaySpeeds` **全部零命中**，与文档标注的 API 26 一致。

**结论**：**基线 24 不可用**。且 `PORTING_EXECUTION_PLAN.md` M9.4（API 26 前瞻）当前**阻塞**——无 API 26 SDK/镜像，HarmonyOS 7 以 Developer Beta 招募形式分发。此项归入 M9.4 待办，不在当前基线规划。

### 10.5 `AVMusicTemplate`：形态不适用

**文档确认**（文档 ID `开发指南/AVSession_Kit_音视频播控服务/音频模板/使用音频模板/using-avsession-avmusictemplate`）：API 23+ 可用，但**仅支持 Car 设备工程**。

本工程 `deviceTypes` 为 `phone` / `tablet` / `2in1`，无 Car 形态。**不适用**，记录以免后续误判为可用能力。

---

## 11. 明确不建议做

以下项经评估后**主动否决**，记录理由以免重复讨论：

| 项 | 理由 |
| --- | --- |
| 用 `effectKit.ColorPicker` 替换自研 `Palette` | 自研实现的核心价值是与 Android 上游 **1:1 对齐**（`adjustedAccent` HSL 压制逐值对齐），替换会引入取色差异，违背等价性移植目标。仅在卡片进程内可考虑单独使用。见 §5.5 |
| 动态歌词卡片（`LiveFormExtensionAbility`） | 与 §3 系统桌面歌词功能重叠，而后者零权限、零额外进程、无内存开销。应先验证 §3。见 §5.3 |
| 播控推荐服务 | 受限开放 + 仅中国大陆 + 依赖上架分类与 30 天使用量，与项目阶段不匹配。见 §10.2 |
| 主动接入实况窗 | 8 小时生命周期上限与音乐长会话冲突；Push Kit 更新需服务端而本项目无自建服务端；且 AVSession 可能已自动带来部分能力。见 §10.1 |
| `AVMusicTemplate` | 仅 Car 工程，本工程无此形态。见 §10.5 |
| 单独立项做 `Navigation` 纯迁移 | 迁移不产生用户可见新功能，且会作废 M9.3 已完成的 17 页 × 3 档字号 × 2 形态回归。应与一多适配合并。见 §6.2 |
| 自由流转 / 跨端接续 | 官方要求「功能和数据在两端兼容，接续内容完整，位置状态一致」。工程的三平台取流依赖本机 Cookie 与登录态（`data/auth/*` 的 Asset Store 凭据），跨端接续会牵出凭据跨设备同步问题，而这与 `RELEASE_CHECKLIST.md` §5.3 的取流剥离结论方向相反。**暂不评估**，待取流方案定案后重议 |

---

## 12. 建议里程碑编排

按「零外部依赖优先、共享回归成本的合并」两条原则编排。

### M10.1 播控合规补齐（✅ 已完成，2026年08月24日）

零硬件依赖、零审批、改动集中在 `AVSessionManager.ets` 一个文件。

1. `AVMetadata` 字段语义修正：`title`/`artist` 恢复正确语义，完整歌词入 `lyric`，当前行入 `singleLyricText`（§2.1）
2. `setLaunchAbility` 播控卡片跳转（§2.2）
3. `on('toggleFavorite')` + `AVPlaybackState` 收藏态上报（§2.3）
4. 验收：播控中心显示滚动歌词、点卡片进播放页、收藏按钮可点且状态正确、原先置灰的按钮转为可用

配套需要一个「完整歌词 → 标准 LRC 字符串」的序列化函数。工程已有 `LrcParser.ets`（解析方向），需补反向序列化，适合加单测。

**完成记录（设备实测证据见 §2.1 / §2.2 / §2.3）**：三项全部落地并在 Pura 90 模拟器实测通过——字段语义归位、`lyric` 与 `duration` 共存、`singleLyricText` 逐行刷新、卡片跳转直达播放页、收藏双向同步。顺带修复两个既有缺陷：① `publishDuration` 从不回灌 AVSession（进度条一直用歌单声明时长）；② 两个空壳收藏 svg 致图标全应用不可见。`LrcParser` 补反向序列化 + 9 新单测。全套把关复跑全绿：本地单测 **809/809**（0 failure 0 error）、CodeLinter **0 error / 24 warn / 2 suggestion**（命中改动文件的 6 条全为存量）、`entry@default` 与 `entry@ohosTest` 均 BUILD SUCCESSFUL、`devecocli run` 部署成功。

### M10.2 桌面歌词 spike（✅ 模拟器部分已完成，2026年08月25日；渲染层待真机）

依赖 M10.1 的 `lyric` 字段。**原判「需真机」——实际模拟器上服务层链路全通，真机只剩渲染层一步待验。**

1. `isDesktopLyricSupported()` 查询，记录模拟器与真机的返回值差异
2. `enableDesktopLyric(true)` → `setDesktopLyricVisible(true)` → 推 `lyric` → 观测系统歌词窗
3. 订阅 `onDesktopLyricVisibilityChanged`，观测用户从系统侧关闭时的回调
4. 产出：spike 结论文档（参照 `USB_M91_SPIKE.md` 的写法），并据此更新 `FEATURE_MATRIX.md` 第 33 行的 D4 结论

**完成记录（完整证据见 `docs/DESKTOP_LYRIC_M102_SPIKE.md`，摘要见 §3.4）**：新增 ohosTest 探针 `entry/src/ohosTest/ets/test/DesktopLyricProbe.test.ets`（3 用例，注册进 `List.test.ets`），Pura 90 模拟器 `Tests run: 3, Failure: 0, Error: 0, Pass: 3`。

- 第 1 项 ✅：模拟器返回 **`true`**（推翻 §3.3「模拟器很可能返回 false」的原判）。真机值待补。
- 第 2 项 ⚠️ 部分：API 侧 10 步全 ok；系统侧 `mediacontroller` 真实拉起、逐字回显我方 LRC、**自行解析出 2 行**、算出窗口几何并走完 `openWindow start show`→`page show`；**但窗口未进合成树，3 次截图无像素**（`TakeSurfaceCapture failed, node is nullptr`）→ 判为模拟器图形栈限制（推断），真机复验。
- 第 3 项 ⚠️ 部分：回调机制成立且双向（共 2 次，`true`/`false` 各一），但两次均由我方调用触发；「用户从系统侧手动关闭」路径因模拟器无窗口可点而未走到。
- 第 4 项 ✅：产出 `DESKTOP_LYRIC_M102_SPIKE.md`，`FEATURE_MATRIX.md` 第 33 行 D4 已据实改写为「能力存在且已验证到服务层，渲染层待真机确认」——**未改写为「可用」**。
- 额外产出（原清单未列）：负向反证用例 `desktopLyricVisibleWithoutEnableIsRefused`，以 `6600110` + native 侧错误文本排除「整套 API 是空实现」的可能。没有这一条，「10 步全 ok」不足以支撑任何结论。

**尚未开始产品化接入**（§3.2 的四条建议改动一条未做）：等真机确认渲染层后再动，避免为一个可能不上屏的能力改 `np.floating_lyric` 的开关语义。

### M10.3 音频低功耗加固（✅ 已完成，2026年08月25日）

零依赖，改动集中在 `PlayerManager.ets`。

1. `initialized` 状态显式设 `audioRendererInfo.usage = STREAM_USAGE_MUSIC`（§4.1），注意须在首次 `prepare()` 前
2. 静音时设 `audioEffectMode = EFFECT_NONE`（§4.2），注意 `usage` 变更会复位该属性、且只能在 `prepared`/`playing`/`paused`/`completed` 设
3. 走查后台进度上报频率是否符合规则 3（§4.3）
4. 可选：`setLoudnessGain` 接入（§4.4），依赖第 1 步

**完成记录（逐项证据见 §4.1 / §4.2 / §4.3 / §4.4）。四项的结果差异很大，如实分列：**

- 第 1 项 ✅ 已实施，**但定性下调为纯防御**：设备探针实测 `defaultUsage=1` / `defaultWasAlreadyMusic=true` / `effectiveUsage=1`，即 SDK 的「纯音频源默认 `STREAM_USAGE_MUSIC`」声明在本设备成立，**这次改动对今天的所有音源都不改变行为**。记为加固与 §4.4 的前置条件，**不记为修复缺陷**（代码注释同样写明 `It is not a bug fix`）。
- 第 2 项 ⛔ **不适用，未实施**：落地时才确认工程**没有静音场景**（`setVolume` 零命中，`mute` 命中全是 `Palette` 的色彩术语）。规则 1 的条件是「静音时」，没有静音入口就没有挂钩点；无条件关音效属产品决策，不能借合规名义做。原「真实缺口」判断作废。
- 第 3 项 ✅ 走查完毕，**频率本身早已合规，但反向抓出两个真缺陷并已修复**：`onTimeUpdate` 无 `setInterval`，500ms 那级节流只写 `AppStorage` 从不进 AVSession（设备实测 176 秒播放期间 AVSession 基准一次未变）。问题不在推太多而在漏推 —— ① `seekTo` 从不回灌 AVSession，播控中心会从 seek 前的旧基准继续数；② 上报请求倍速而非量化后的实际倍速，外推斜率必然漂移。抽出 `publishSessionPlaybackState()` 统一入口修复，三次 seek + 一次改倍速的 dump 对比取证（表格见 §4.3）。
- 第 4 项 ⛔ **已否决，不接入**：`setLoudnessGain` 四次调用全部 `hung(>10000ms)`，连越界的 `100.0` 都不返回 `401`，判为该设备类上的永久挂起桩。接入的后果是吊死调用链而非无效果。
- 额外产出（原清单未列）：单测抓出倍速量化边界用档位值而非中点，`0.75 × 1.05 = 0.7875` 静默落到 1.00x，即一起听的 5% 漂移修正被放大成 **33% 加速**。量化逻辑抽到 `player/PlaybackSpeedMap.ets` 并改用中点边界。

改动文件：`player/PlayerManager.ets`（5 处）、新建 `player/PlaybackSpeedMap.ets`、新建 `entry/src/test/ets/test/PlaybackSpeedMap.test.ets`（7 用例）、新建 `entry/src/ohosTest/ets/test/AudioRendererProbe.test.ets`（2 用例），两个 `List.test.ets` 配套注册。

全套把关复跑全绿：本地单测 **816/816**（809 基线 + 7 新增，0 failure 0 error）、CodeLinter **0 error / 24 warn / 2 suggestion**（与基线逐字一致，命中 `PlayerManager.ets` 的 2 条为存量）、`entry@default` 与 `entry@ohosTest` 均 BUILD SUCCESSFUL、设备侧 `ActsAudioRendererProbeTest` **2/2 Pass**（41s）。

### M10.4 一多适配（合并里程碑，依赖 M9.3a 解封）

**前置阻塞**：需 GUI 下载 `tablet_x86` 与 `pc_all_x86` 镜像（`PORTING_EXECUTION_PLAN.md` M9.3a）；悬停态需真机。

合并以下四项，共享一次布局回归：

1. `Navigation` 迁移，用 `NavigationMode.Auto` 拿 ≥600vp 分栏（§6）
2. tablet 2880×1920 / 2in1 3120×2080 布局回归（§7.2）
3. 折叠屏悬停态适配，`FoldSplitContainer` + 16vp/40vp 避让（§7.1）
4. 触控目标 40vp → 48vp（§7.3）
5. 横屏走查与 2in1 多窗验证（§7.2 末）

合并的理由：这四项**每一项都会改变布局**，而 M9.3 建立的布局树度量回归（`uitest dumpLayout` 的 `bounds` vs `origBounds` 四类判据）需要在改动后重跑。分四次做要跑四遍。

### M10.5 分层图标（可随时插入）

零依赖、零代码风险、改动最小（§8.1）。可在任意里程碑间隙完成。

### M10.6 意图框架 `PlayMusicList`（视 M10.1–M10.3 结果决定）

一次注册换三项自检表能力（§10.3）。基线内、零审批，但效果验证依赖系统侧入口，存在「做完看不到」风险。建议在 M10.2 拿到真机验证经验后再评估。

### 待条件成熟

- 投播 spike（§9，需接收端硬件；且需先验证注入请求头的流能否被远端拉取）
- 服务卡片（§5，需先解决卡片进程与 `AppStorage` 的跨进程状态通道问题，建议在 M10.2 明确桌面歌词结论后再定卡片形态）
- 多语言（§8.2）
- `setMediaCenterControlType`（§10.4，归入 M9.4 API 26 前瞻）

---

## 13. 官方依据索引

本文引用的全部官方文档 ID（均已在本机 `devecocli docs` 验证可读）与 SDK 位置。

### 服务卡片

- `最佳实践/服务卡片/音乐服务卡片/bpta-music-card`
- `开发指南/Form_Kit_卡片开发服务/ArkTS卡片开发_推荐/ArkTS卡片最佳实践/音乐服务卡片/arkts-ui-music-service-form`

### AVSession 播控

- `开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控自检表/playback-control-access-checklist`
- `开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控检查项详细说明/快捷播放/quick-playback`
- `开发指南/AVSession_Kit_音视频播控服务/应用接入播控自检/应用接入播控检查项详细说明/音视频投播/avcastpicker`
- `开发指南/AVSession_Kit_音视频播控服务/自定义播控中心控制按钮显示布局/avsession-mediacentercontroltype-scene`（API 26）
- `开发指南/AVSession_Kit_音视频播控服务/播控推荐服务/avsession-recommendation`（受限开放）
- `开发指南/AVSession_Kit_音视频播控服务/音频模板/使用音频模板/using-avsession-avmusictemplate`（仅 Car）
- `FAQ/音频和视频/音视频播控_AVSession/如何在播控中心显示歌词/faqs-avsession-5`
- `FAQ/音频和视频/音视频播控_AVSession/为什么接入播控后_播控中心部分按钮是灰色的_不可点击/faqs-avsession-3`
- `FAQ/音频和视频/音视频播控_AVSession/播控中心的进度条展示错误_与应用内的进度条不一致/faqs-avsession-17`

### 功耗

- `最佳实践/应用功耗优化/前台任务低功耗/前台资源合理使用/音乐播放场景低功耗规则/bpta-music-playback-scenarios`

### 一多与设计规范

- 官网设计最佳实践总览：`https://developer.huawei.com/consumer/cn/doc/design-guides/practices-overview-0000001746498066`
- `最佳实践/多设备界面开发/多设备界面开发案例/多设备音乐界面/bpta-multi-music-app-overview`
- `最佳实践/多设备界面开发/特殊界面布局场景/折叠屏悬停态/bpta-folded-hover`
- `最佳实践/多设备资源文件/bpta-multi-device-resource`
- `最佳实践/电脑/电脑应用开发/bpta-pc-guide`
- `最佳实践/平板/平板应用开发/bpta-pad-guide`
- `最佳实践/手机/双折叠应用开发/bpta-foldable-guide`

### 投播与流转

- `最佳实践/多端协同/音频投播/bpta-audio-cast`
- `最佳实践/多端协同/视频投播/bpta-vdeocast`
- `最佳实践/自由流转概述/bpta-hopping`
- `开发指南/应用基础功能和兼容性体验建议/系统特性与基础功能/自由流转规格/distributed-capability-specification`

### 实况窗

- `开发指南/Live_View_Kit_实况窗服务/实况窗设计规范/liveview-design-formula`
- `开发指南/Live_View_Kit_实况窗服务/开发准备/申请实况窗正式权限/liveview-formal-authority`
- `FAQ/实况视图服务_Live_View_Kit/哪些系统服务会自动接入实况窗/faqs-liveview-5`

### 图标

- `开发指南/开发基础知识/典型场景的开发指导/配置应用图标和名称/layered-image`
- `最佳实践/程序包结构/应用图标配置与开发/bpta-app-icon-configuration`
- `开发指南/UI_Design_Kit_UI设计套件/图标处理/推荐_分层图标处理/ui-design-layered-process`

### 意图框架

- `开发指南/Intents_Kit_意图框架服务/本地搜索方案/场景体验/intents-search-rec-scene-experience`
- `最佳实践/意图框架习惯推荐场景/bpta-intent-recommend-practice`

### SDK 声明位置

根路径 `D:\HarmonyOS\Tools\command-line-tools\sdk\default\`：

| 能力 | 文件 |
| --- | --- |
| AVSession（含桌面歌词、投播、`AVMetadata`） | `openharmony/ets/api/@ohos.multimedia.avsession.d.ts` |
| AVCastPicker 组件 | `openharmony/ets/api/@ohos.multimedia.avCastPicker.d.ets` |
| AVCastPicker 参数 | `openharmony/ets/api/@ohos.multimedia.avCastPickerParam.d.ts` |
| AVPlayer（`audioRendererInfo` / `audioEffectMode` / `setLoudnessGain`） | `openharmony/ets/api/@ohos.multimedia.media.d.ts` |
| 音频（`StreamUsage` / `AudioEffectMode`） | `openharmony/ets/api/@ohos.multimedia.audio.d.ts` |
| 服务卡片（静态） | `openharmony/ets/api/@ohos.app.form.FormExtensionAbility.d.ts` |
| 服务卡片（动态） | `openharmony/ets/api/@ohos.app.form.LiveFormExtensionAbility.d.ts` |
| 卡片刷新 / 数据 | `openharmony/ets/api/@ohos.app.form.formProvider.d.ts`、`@ohos.app.form.formBindingData.d.ts` |
| 意图框架 | `openharmony/ets/api/@ohos.app.ability.InsightIntentDecorator.d.ts` 等 |
| 取色 | `openharmony/ets/api/@ohos.effectKit.d.ts` |
| 实况窗 | `hms/ets/api/@hms.core.liveview.liveViewManager.d.ts` |

---

## 14. 本文未覆盖与待核实

如实列出本轮**没有查到**或**没有核实**的内容，避免本文被当成穷尽清单：

### 未取到正文的官方页面

- 官网「播控中心」设计规范页 `https://developer.huawei.com/consumer/cn/doc/design-guides/broadcasting-control-0000001957017133` 抓取只返回 `{"title":"文档中心","content":"文档中心"}` —— 该页为纯 JS 渲染且无 `.md` 备份。§2 的播控要求全部来自**开发指南侧的自检表**（已取到正文），**设计规范侧的视觉/交互要求未取到**。若要完整对齐播控中心设计规范，需人工浏览器访问该页。

### 未检索的可能相关项

- **Share Kit 系统分享** —— 工程当前只有歌词卡片保存图库 + 复制文本（`FEATURE_MATRIX.md` 第 27 行明确「通用文件导出/外部应用分享（对应 Android FileProvider ACTION_SEND）未做」）。系统分享面板是鸿蒙的标准能力，值得单独检索。
- **UDMF 拖拽 / 超级中转站** —— 跨应用拖拽歌曲/歌单，2in1 形态下尤其相关。
- **Wear / HiCar / 智慧屏扩展形态** —— 音乐应用的典型扩展形态，本文只覆盖 phone/tablet/2in1/折叠。
- **ArkUI 状态管理 V2**（`@ComponentV2` / `@ObservedV2` / `@Local`）—— 工程 grep 零命中，仍全用 V1。属架构现代化项，与本文的「特性/规范」主题相邻但不同。
- **性能规范** —— 冷启动耗时、丢帧率的官方指标与检测方法。`RELEASE_CHECKLIST.md` §4 记录了内存（127–151MB 无单调增长）但未覆盖启动与流畅度指标。
- **AudioHaptic** —— 音振协同，对音乐应用可能有增值空间。

### 需走查而非检索的项

- §4.3 后台进度上报频率是否符合低功耗规则 3 —— 需读 `PlayerManager` 与 `AVSessionManager` 的进度发布路径。
- §7.2 横屏适配 —— `module.json5` 未锁方向，但未走查各页在横屏下的表现。

### 设备验证空白

本文所有「SDK 确认」级结论都只到 `.d.ts` 声明一级。以下**全部未在设备上调用过**：桌面歌词全套、`setLaunchAbility`、`on('toggleFavorite')`、`AVMetadata.lyric` / `singleLyricText`、`audioRendererInfo` / `audioEffectMode`、投播全套、卡片全套、意图框架全套。

沿用 `FEATURE_MATRIX.md` 第 32 行 USB spike 的表述方式：**「API 可行」只到 d.ts 一级，未到行为观测一级。**

---

## 附：与既有文档的关系

| 既有文档 | 本文的关系 |
| --- | --- |
| `FEATURE_MATRIX.md` | 该表是「Android → HarmonyOS 等价性」矩阵，本文是「鸿蒙独有特性 + 官方规范」清单，互补。**本文 §3 的桌面歌词发现动摇了该表第 33 行 D4 降级结论的前提**，需在 M10.2 spike 后更新该行。 |
| `PORTING_EXECUTION_PLAN.md` | 本文 §12 的 M10.x 编排接在 M9 之后。M10.4 依赖 M9.3a 解封（tablet/2in1 镜像），§10.4 归入 M9.4（API 26 前瞻）。 |
| `RELEASE_CHECKLIST.md` | §5.3「面向公开市场需剥离或降级三平台取流」是本文全部 P3 项的前置约束。§3.3 无障碍、触控目标 40vp、§6 设置页占位在本文 §7.3 / §7.4 / §8.2 中引用。 |
| `hm.md` | §6.2 早已建议迁 `Navigation`（未落地）。本文 §6 维持该建议并补充「不单独立项、与一多适配合并」的理由。 |
| `USB_M91_SPIKE.md` | 本文 §3.3 / §14 沿用其「API 可行 ≠ 硬件回环可行」的分级表述；§12 的 M10.2 建议参照其 spike 文档写法。 |
