# 播放页 UX 重做实施方案

> 范围：播放页「匹配歌曲信息」、设置项下拉菜单锚点与箭头联动、点歌即进播放页、底部标准图标、播放页↔歌词页横向分页。
> 立项日期：2026年08月28日 · 目标基线：HarmonyOS NEXT API 24（6.1.1 Release）

## 背景

`NeriPlayer-HarmonyOS` 是 Android/Compose 版 NeriPlayer 的 ArkTS/ArkUI 移植。设备实测后暴露 6 个与 Android 原版及鸿蒙设计规范的差距：

1. `⋯ → 获取歌曲信息` 只是个只读元数据面板，而原版是**跨平台搜索同名歌曲并把选中结果（含歌词）同步到当前歌曲**。ArkTS 侧有两处硬缺口：**没有 QQ 音乐 API**，且 `SongItem.matchedLyric/matchedSongId` 虽已定义、已参与 sync，但 `LyricDispatcher` 从不读它 —— 即使写进去也显示不出来。
2. 设置项下拉菜单打开时右侧箭头不动，用户看不出菜单的开合状态。
3. `OptionRow` 把 `bindMenu` 绑在整行上，菜单锚在行左端，与右侧箭头脱节。
4. 歌单类页面点歌只播放、不进播放页，用户还要再点一次 MiniPlayer。
5. 播放页底部「倍速/定时/歌词/分享/播放列表」是一排 `#33FFFFFF` 圆角胶囊 + `app.media` 位图图标，不是鸿蒙标准图标，也不符合参考稿的「无背景裸图标」。
6. 歌词靠一个「歌词」按钮切换（且 `showLyrics` 默认 `true`，一进页面就是歌词），没有左右滑动分页与转场动效。

目标：把这 6 点一次性对齐参考稿（匹配面板 / 歌词页 / 播放页三张设计稿），并补齐匹配歌词的存储—读取闭环。

已确认的决策：需求 4 只覆盖**列表里的单曲行**（6 处）；匹配结果的歌名/歌手/封面写 `custom*`、歌词写 `matched*`；歌词页底部控件**折叠成半透明胶囊**（收藏/上一首/播放/下一首/播放列表）；只读「歌曲信息」面板**删除**，菜单第一项换成「匹配歌曲信息」。

---

## 1. 匹配歌曲信息

### 1.1 新增 QQ 音乐 API：`entry/src/main/ets/network/QQMusicApi.ets`

移植 `NeriPlayer-master/.../core/api/search/QQMusicSearchApi.kt`。全部走现成的 `HttpClient.getText(url, headers)`（`network/HttpClient.ets:65`，已带 UA / 代理 / 超时）：

- **搜索**：`https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&n=20&p=1&w=<kw>&cr=1&g_tk=5381`
  取 `data.song.list[]` → `songmid` / `songname` / `singer[].name`（用 `/` 连接）/ `interval`（秒）/ 封面 `https://y.qq.com/music/photo_new/T002R800x800M000<albummid>.jpg`。
- **详情**：`https://u.y.qq.com/cgi-bin/musicu.fcg?data={"songinfo":{"method":"get_song_detail_yqq","module":"music.pf_song_detail_svr","param":{"song_mid":<mid>}}}` → `songinfo.data.track_info`。
- **歌词**：同 `musicu.fcg`，`format=json` + `data={"req":{"method":"GetPlayLyricInfo","module":"music.musichallSong.PlayLyricInfo","param":{"songMID":<mid>,"trans":1,"qrc":0,"crypt":0}}}`，**必须带 `Referer: https://y.qq.com`**；校验 `req.code === 0`，再取 `req.data.lyric` / `req.data.trans`。
- 三个纯函数逐字移植（Kotlin 里已经踩过坑，别自己发明）：
  - `decodeQQMusicLyricPayload`：HTML 反转义（`&#39; &apos; &quot; &amp;`）→ 若已含 `[mm:ss(.xxx)]` 时间戳直接返回 → 否则按 base64 解一次再校验时间戳。解码用 `new util.Base64Helper().decodeSync(...)`（`@kit.ArkTS` 的 `util`，用法见 `view/components/LyricShareSheet.ets:149`；`util/Base64.ets` 只有 `encodeBase64`，不够用）。
  - `stripUntranslatedPlaceholderLines`：整行只有 `/`（含全角 `／`）的翻译占位，压成 `[时间戳]//`。
  - 时间戳正则 `\[(\d{1,3}):(\d{2})(?:[.:]\d{1,3})?\]`。
- 所有失败路径 `Logger.warn` + 返回空，不抛给 UI（与 `NeteaseApi` 的风格一致）。

### 1.2 新增匹配门面：`entry/src/main/ets/network/SongMatchApi.ets`

```text
export enum MatchSource { NETEASE = 0, QQ = 1 }
export class MatchCandidate     { source; id; name; artist; album; coverUrl; durationMs }
export class MatchedSongDetail  { source; id; name; artist; album; coverUrl; lyric; translatedLyric }
static async searchCandidates(source, keyword): Promise<MatchCandidate[]>
static async fetchDetail(candidate): Promise<MatchedSongDetail>
```

- 网易云分支直接复用 `NeteaseApi.search(keyword, 30)`（`network/NeteaseApi.ets:139`，weapi + 风控回落 legacy 已内置）与 `NeteaseApi.getLyric(id)`（:233，返回 `LyricPayload{lyric, translated, phonetic}`）。
- **不要动 `model/MusicPlatform.ets`**：给它加 `QQ_MUSIC` 会波及 `platformName()`、`sync/SyncDataJsonCodec`、`SongIdentity` 等一大片。匹配来源只是元数据来源，不是可播放平台，所以单独用 `MatchSource`。

### 1.3 新增面板：`entry/src/main/ets/view/components/MatchSongInfoSheet.ets`（替换 `SongInfoSheet.ets`）

复用 `BottomSheetPanel`（`view/components/BottomSheetPanel.ets`，玻璃底 + 标题 + 关闭）。结构按设计稿：

- `TextInput`（`@State keyword`，`aboutToAppear` 预填 `song().displayName`）+ 右侧搜索按钮（`sys.symbol.magnifyingglass`，若名不可用退回 `app.media` 现有放大镜资源），`.onSubmit` 也触发搜索。
- 平台切换用 `Tabs` + `TabContent`（`CLOUD MUSIC` / `QQ MUSIC`），或两枚 `Button` 做分段控件；切换即重搜，各自缓存结果避免抖动。
- 结果 `List`：48vp 圆角封面（`Image(coverUrl).borderRadius(8)`）+ 歌名 + 歌手/专辑/时长（时长用现成的 `formatDuration`，`view/components/Ui.ets:447`）。选中项加 `Theme.primary` 描边。
- 底部 `完成` 按钮：对选中项调 `fetchDetail` → 写回（见 1.4）→ `onApplied()` → `onClose()`。加载/空/失败三态复用 `LoadingState` / `EmptyState`（`Ui.ets`）。

写回逻辑（照抄 `EditSongInfoSheet.save()` 的模式，`view/components/EditSongInfoSheet.ets:39`）：

```ts
const base = this.song();
const updated = SongItem.fromJson(base.toJson());
updated.customName     = detail.name   !== base.name   ? detail.name   : '';
updated.customArtist   = detail.artist !== base.artist ? detail.artist : '';
updated.customCoverUrl = detail.coverUrl.length > 0 && detail.coverUrl !== base.coverUrl ? detail.coverUrl : '';
updated.matchedSongId          = `${sourceTag}:${detail.id}`;
updated.matchedLyric           = detail.lyric;
updated.matchedTranslatedLyric = detail.translatedLyric;
await LocalPlaylistRepository.updateSongMetadata(updated);
PlayerManager.applySongMetadataUpdate(updated);
```

### 1.4 三处必要的链路补齐

- **`data/LocalPlaylistRepository.ets:260 updateSongMetadata`**：现在只逐字段拷 `customName/customArtist/customCoverUrl`，**必须补上 `matchedSongId/matchedLyric/matchedTranslatedLyric`**（加进那三个 `!==` 比较与赋值），否则匹配歌词重启即丢。
- **`lyrics/LyricDispatcher.ets:24 loadLyrics`**：在方法最前面插入短路分支 ——
  `if (song.matchedLyric.trim().length > 0) { let parsed = LrcParser.parse(song.matchedLyric); parsed = LrcParser.mergeTranslation(parsed, song.matchedTranslatedLyric); return parsed; }`
  放在网易云分支之前，让用户的显式匹配优先于自动源。
- **`player/PlayerManager.ets:429 applySongMetadataUpdate`** 已经整体替换队列里的 `SongItem` 并 `publishCurrentSong` + `refreshSessionMetadata`，**不需要改**；只需在 `NowPlayingPage` 里通过 `onApplied` 回调调一次 `this.reloadSongData()` 让歌词立刻重载（`currentSongJson` 的 `@Watch` 目前只做封面淡入）。

### 1.5 入口改名 + 删除旧面板

`view/pages/NowPlayingPage.ets`：`songMenuBuilder()` 第一项文案 `获取歌曲信息` → `匹配歌曲信息`（图标 `sys.symbol.info_circle` 可保留或换 `sys.symbol.magnifyingglass`），`@State showSongInfo` → `showMatchInfo`，`if` 分支渲染 `MatchSongInfoSheet`。删除 `view/components/SongInfoSheet.ets`（已确认全项目只有 `NowPlayingPage` 引用它，无测试引用）。

---

## 2 + 3. 下拉菜单箭头联动与锚点（`view/components/Ui.ets` 的 `OptionRow`）

一处改动覆盖全部 9 个调用点（`SettingsDetailPage.ets:793/801/817/840/848/898/912/935`、`SettingsPage.ets:104`）。全项目只有 3 处 `bindMenu`，另两处在 `NowPlayingPage`（倍速菜单、⋯ 菜单），不受影响。

- 加 `@State menuShow: boolean = false;`
- **把 `.bindMenu(...)` 从 `Row`（`Ui.ets:430`）移到尾部箭头上**，用带 `MenuOptions` 的双向形式：
  `.bindMenu(this.menuShow!!, this.optionMenuBuilder, { placement: Placement.BottomRight, onDisappear: () => { this.menuShow = false; } })`
  行整体保留 `.onClick(() => { this.menuShow = true; })`，这样点行体和点箭头都能开菜单，但**锚点始终是箭头**。（若 `!!` 双向绑定在本工程编译不过，退回单参形式 `.bindMenu(this.optionMenuBuilder, { placement, onAppear, onDisappear })` 并去掉行级 `onClick` —— 此时只有箭头区可点，需把箭头包成 `≥40vp` 的热区。）
- 箭头本体沿用现有 `ic_chevron_right_24`，用旋转做联动，不新增资源：
  `.rotate({ angle: this.menuShow ? 90 : 0 }).animation({ duration: 180, curve: Curve.EaseInOut })`
  外层包一个 `Row(){}.width(40).height(40).justifyContent(FlexAlign.Center)` 作为锚点与热区，并给 `.accessibilityText(...)`（含标题与当前值）。
- `SettingRow`（`Ui.ets:219`）的静态箭头不动 —— 它是跳转箭头，不是菜单。

---

## 4. 点歌即进播放页（6 处单曲行）

在这 6 个「点单曲」路径的 `PlayerManager.playPlaylist(...)` 之后补一行 `Router.push(Router.NOW_PLAYING);`（页面若还没 import，加 `import { Router } from '../Router';`）：

| 文件 | 位置 |
| --- | --- |
| `view/pages/PlaylistDetailPage.ets` | :203 `SongRow.onPlay` |
| `view/pages/NeteasePlaylistPage.ets` | :232 `SongRow.onPlay` |
| `view/pages/BiliFavPage.ets` | :280 `SongRow.onPlay` |
| `view/pages/AlbumPage.ets` | :54 `playFrom(index)` |
| `view/pages/RecentPage.ets` | :22 `play(index)` |
| `view/pages/ExplorePage.ets` | :86 `play(index)` |

**不改**：各页头部的 `全部播放/随机播放`（`PlaylistDetailPage:44`、`NeteasePlaylistPage:60`、`BiliFavPage:109`、`LibraryPage:141`）、首页卡片（`HomePage:95/105`）、`DownloadsPage:80`（那一行的点击是取消/续传/播放三合一，不是纯单曲行）、`ListenTogetherPlayerBinding:52`（远端同步不该抢用户当前页面）。

安全性已核过：`RouteStack.routePushAction` 在栈顶已是同名路由时返回 `REPLACE_TOP`，所以在播放页里再触发也不会叠栈。

---

## 5. 底部图标标准化（`NowPlayingPage.ets:534-599`）

删掉整个胶囊 `Row`，换成 4 枚裸 `SymbolGlyph`（无背景、无圆角），`Row` 用 `justifyContent(FlexAlign.SpaceEvenly)`，保留末尾 `.padding({ top: 12, bottom: this.bottomLift })`（`bottomLift` 来自 `@StorageProp('ui.bottomLiftVp')`，别丢）。

符号名已从 `previewer/common/resources/resources.index` 里核过存在（项目已实测可编译的有 `info_circle` / `square_and_pencil` / `download` / `timer` / `textformat_size_square` / `opticaldisc` / `share`）：

| 功能 | 首选 | 备选 |
| --- | --- | --- |
| 倍速 | `sys.symbol.speed_multiple` | `sys.symbol.double_speed` |
| 定时 | `sys.symbol.timer`（已验证） | — |
| 分享 | `sys.symbol.share`（已验证） | — |
| 播放列表 | `sys.symbol.music_note_list` | `sys.symbol.list_bullet` |
| 歌词页收起 | `sys.symbol.chevron_down` | — |

统一样式：`.fontSize(24).fontColor(['#FFFFFF'])`，容器 `.width(44).height(44)`，**无 `backgroundColor`**。

去掉背景后文字信息（`1.0x`、剩余分钟数）没地方显示，用状态色 + 无障碍文案补偿，不再加背景：

- 倍速：`bindMenu(this.speedMenuBuilder)` 原样保留；`fontColor` 在 `this.speed !== 1.0` 时用 `#FFFFFF`、否则 `#B8FFFFFF`；`.accessibilityText('播放速度 N 倍，点击选择')`。
- 定时：`sleepActive` 时 `#FFFFFF` 否则 `#B8FFFFFF`；`.accessibilityText(this.sleepButtonText())`（`sleepButtonText()` 已存在，:203，保留不删）。
- 「歌词」按钮**整个删除**（改由第 6 节的滑动接管）。

`PlayerControlButton`（:718）与传输键继续用现有 `app.media` 位图，本次不动 —— 需求只点名了底部那一排。

---

## 6. 播放页 / 歌词页横向分页（`NowPlayingPage.ets`）

### 6.1 状态

`@State showLyrics: boolean = true` → `@State pageIndex: number = 0;`（0 = 播放页，1 = 歌词页）+ `private paneSwiper: SwiperController = new SwiperController();`
**默认值从「歌词」改成「封面」**，与设计稿一致（这是一处有意的行为变更）。

### 6.2 结构

把现在的 `if (this.showLyrics) { LyricView } else { 封面+标题+歌手 }` 换成：

```ts
Swiper(this.paneSwiper) {
  Column() { /* 原 else 分支：封面 Stack + 标题/收藏 + 歌手/平台 */ }.width('100%').height('100%')
  Column() { LyricView({ lyrics: this.lyrics, onSeek: /* … */, onScrubLine: /* … */ }) }.width('100%').height('100%')
}
.index(this.pageIndex)
.loop(false)
.indicator(false)
.duration(320)
.curve(curves.interpolatingSpring(0, 1, 328, 34))   // 与 LyricView 的 springMotion 同族手感
.layoutWeight(1)
.onChange((index: number) => this.switchPane(index))
```

`LyricView` 根节点是 `Scroll(...).layoutWeight(1)`（`LyricView.ets:366`），所以**必须**包一层 `Column().height('100%')`，否则在 Swiper item 里塌成 0 高。

### 6.3 控制区形变（歌词页胶囊 ↔ 播放页完整控制区）

控制区留在 `Swiper` 外（单一数据源，不重复实现传输键）。`switchPane(index)`：

```ts
private switchPane(index: number): void {
  this.pageIndex = index;
  this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, () => {
    this.lyricsMode = index === 1;
  });
}
```

- `lyricsMode === false`：`WaveformSlider` + 时间标签 + 5 键传输行 + 新的 4 图标行，容器透明满宽（现状）。
- `lyricsMode === true`：隐藏 `WaveformSlider`、时间标签、4 图标行；容器变胶囊 ——
  `.backgroundColor('#33FFFFFF').backgroundBlurStyle(BlurStyle.COMPONENT_THIN).borderRadius(32).margin({ left: 24, right: 24, bottom: 12 })`，
  内容为 5 枚按钮：收藏（`this.favorite` 位图沿用，`toggleFavorite()`）/ 上一首 / 播放暂停 / 下一首 / 播放列表（`showQueue = true`）。传输键复用 `PlayerControlButton`，播放键 `buttonSize` 从 64 降到 52 以适应胶囊。
- 顶栏同步切换：`lyricsMode` 时左上角换成圆形 `sys.symbol.chevron_down`（点击 `this.paneSwiper.showPrevious()`），隐藏「正在播放」标题与「一起听」按钮，右上角 `⋯` 保留；否则保持现状。
- 系统返回键/侧滑仍然直接 pop 整个路由（`MainShell` 的 `NavDestination` 行为不动），这是已知取舍，不在本次范围内改。

### 6.4 手势冲突（必须处理）

`LyricView` 的根 `Scroll` 有 `.onTouch`（:368），`handleTouch` 在 `TouchType.Down` 就把 `userHold = true`（:217）。横向滑回播放页也会触发 Down，导致歌词自动跟随被误停 2 秒（`USER_HOLD_REVERT_MS`）。修法：**把 `userHold = true` 从 `Down` 挪到「第一次非程序化滚动」**——

- `handleTouch` 的 `Down` 分支只保留 `cancelRevert()` / `userTouching = true` / `stoppedWhileHolding = false` / `programmaticScroll = false`，并**去掉** `userHold = true` 与 `updateScrubFromOffset()`。
- `handleScroll()`（:231）改成：`if (this.programmaticScroll) return; if (!this.userHold) { this.userHold = true; } this.updateScrubFromOffset();`
- `handleScrollStop()` 逻辑不变（此时 `userHold` 只在真的滚过才为 true）。

副作用是正向的：单纯点一句歌词（`handleLineTap`）不再先进一次 scrub 态。

---

## 验证

1. **静态检查**：对改动过的每个文件调 `mcp__deveco-mcp__check`（ArkTS 诊断），重点看 `hp-arkui-no-state-var-access-in-loop`（`MatchSongInfoSheet` 的结果 `ForEach` 里别直接读 `@State`，照 `OptionRow.currentLabel()` 的手法先 hoist 到局部）。
2. **构建 + 安装**：按 `NeriPlayer-HarmonyOS/PORTING.md`，设好 `DEVECO_SDK_HOME` / `DEVECO_STUDIO_HOME`，跑 `sign-local.ps1` 打包签名并装到 `127.0.0.1:5555`。**符号名是唯一的编译期风险**：若 `speed_multiple` / `music_note_list` / `magnifyingglass` 报「资源未定义」，按第 5 节备选列逐个换。
3. **设备手测**（模拟器要先解锁屏幕；若之前跑崩过 ohosTest，先确认没进安全模式）：
   - 需求 1：播放一首网易云歌 → `⋯ → 匹配歌曲信息` → 关键字预填当前歌名 → `CLOUD MUSIC` 与 `QQ MUSIC` 都能出结果（封面/歌名/歌手齐全）→ 选一条 `完成` → 标题/歌手/封面立即变（含 MiniPlayer 与媒体控制中心）→ 左滑歌词页显示的是**新匹配的歌词**（QQ 源要能看到翻译行）→ 杀进程重进，歌词仍是匹配到的那份（验证 1.4 的落盘补齐）。
   - 需求 2/3：设置 → 任一 `OptionRow` 点开菜单，箭头 180ms 内转成向下、菜单出现在**箭头下方右对齐**；选一项或点外部收起后箭头转回向右。9 个调用点抽查 3 个。
   - 需求 4：歌单详情 / 网易云歌单 / B 站收藏夹 / 专辑 / 最近播放 / 探索结果，各点一首歌 → 播放且直接进播放页；返回键回到原列表；在播放页内再触发同一路由不叠栈。同时确认「全部播放/随机播放」与首页卡片**没有**跳转（回归项）。
   - 需求 5：底部 4 图标无背景色块、间距均匀；`hdc shell uitest dumpLayout` 确认无重叠/截断，热区 ≥40vp；用 `GetPixel` 采样确认图标区背景与页面遮罩同色（无 `#33FFFFFF` 残留）。
   - 需求 6：播放页左滑 → 歌词页（进度条与图标行淡出、胶囊淡入）；歌词页右滑 / 点左上 `chevron_down` → 回播放页；歌词页纵向拖动仍能 scrub 并在 2 秒后回弹，横向滑动**不**打断自动跟随（6.4 的验证点）；进页面默认停在封面页。
4. **回归**：`⋯` 菜单其余 6 项（编辑歌曲信息 / 下载 / 歌词偏移 / 字体大小 / 查看专辑 / 分享）仍可打开；倍速菜单仍是六档单选并打勾；深色/浅色切换下底栏无白边（`MainShell` 的 `resolveDark` 约束没被破坏）。
