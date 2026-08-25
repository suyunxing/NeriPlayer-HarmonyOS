# 前端视图层审查与 M11 编排（ArkUI 代码质量 + Android 等价性）

> 调研日期：2026-08-25。执行者：ZCode agent。结论消费者：`PORTING_EXECUTION_PLAN.md` §6 M11、
> `FEATURE_MATRIX.md`「主导航与多设备布局」「歌词解析与同步」「动态取色/高级视觉」三行，
> `RELEASE_CHECKLIST.md` §6 已知能力限制。
>
> 方法：`entry/src/main/ets/view/**`（34 文件 / 8901 行）+ `pages/Index.ets` + `entryability/EntryAbility.ets`
> 逐文件通读 + ArkUI API 使用面 grep 逐模式计数 + 与 `NeriPlayer-master/app/src/main/java/…/ui/` 对应
> Compose 实现对读（`NowPlayingScreen.kt` 4555 行、`LyricsScreen.kt` 1253 行、
> `ui/component/lyrics/*.kt` 3309 行、`ui/theme/NeriTheme.kt` 159 行）。
>
> **未做**：设备/模拟器运行验证、截图对比、性能实测、屏幕朗读实听。
> 本文全部结论为**静态审查级**，凡涉及运行时表现均标注「待设备验证」，
> 不得作为「已验证能力」引用或写入 FEATURE_MATRIX。

---

## 1. 结论

视图层（8901 行 / 34 文件）是全工程质量落差最大的一层。后端
（215 个 main 文件 + 本地单测 816/816）已非常扎实，但 UI 层几乎没有使用 ArkUI 平台的现代能力——
`LazyForEach`/`@Reusable`/`Toggle`/`bindSheet`/`stateStyles`/`expandSafeArea`/`Navigation` 在视图层全部命中 0。
全应用实体上只用了 `animateTo`（3 处）。

发现 **10 条真实缺陷**（❶–❿），其中 2 条（❹❺）会让用户以为功能可用而实际上设置无效，
属发布前必须处置的项目，且尚未在 `RELEASE_CHECKLIST.md` §6 中登记。

与 Android 原版的最大等价性缺口是**歌词视图**（❶，用户直接感知到）和**深色模式切换响应性**（❸）。

建议编排 **M11.1**（视图层缺陷清零 + 死设置处置）+ **M11.2**（歌词视图对齐）
作为本次交付，其余 M11.3–M11.7 作为路线留档。

---

## 2. 视图层现状测绘

### 2.1 文件清单与行数

| 文件 | 行数 | 说明 |
| --- | --- | --- |
| `view/pages/SettingsDetailPage.ets` | 1686 | 视图层最大文件，含 10 个 section 的完整实现 |
| `view/pages/NowPlayingPage.ets` | 669 | 播放页（含内嵌 QueueSheet/PlayerControlButton struct） |
| `view/pages/LibraryPage.ets` | 605 | 资料库，含 StatCard 副组件 |
| `view/pages/ListenTogetherPage.ets` | 504 | 一起听 |
| `view/pages/BiliFavPage.ets` | 365 | B 站收藏，本轮未走查（§5）|
| `view/pages/PlaylistDetailPage.ets` | 359 | 歌单详情 |
| `view/pages/DebugPage.ets` | 311 | 调试 |
| `view/pages/HomePage.ets` | 300 | 首页 |
| `view/pages/NeteasePlaylistPage.ets` | 298 | 网易云歌单页 |
| `view/components/Ui.ets` | 265 | SectionHeader/EmptyState/LoadingState/PlaylistCard/SettingRow/SongCountChip |
| `view/components/LyricShareSheet.ets` | 265 | 歌词卡片生成与分享 |
| `view/pages/ExplorePage.ets` | 257 | 探索/搜索 |
| `view/theme/Palette.ets` | 233 | HSL/RGB 工具 |
| `view/components/QrLoginPanel.ets` | 220 | QR 登录面板 |
| `view/pages/DownloadsPage.ets` | 207 | 下载管理 |
| `view/pages/SettingsPage.ets` | 203 | 设置入口 |
| `view/components/MiniPlayer.ets` | 181 | 迷你播放器 |
| `view/components/SongRow.ets` | 178 | 歌曲行（含 MenuItemRow） |
| `view/components/WaveformSlider.ets` | 174 | 波形进度滑块 |
| `view/Theme.ets` | 170 | 主题颜色 API |
| `view/theme/DynamicTheme.ets` | 165 | 动态调色板 HSL 计算 |
| `view/pages/StatsPage.ets` | 141 | 播放统计（含 StatTile） |
| `view/theme/CoverArtColorCache.ets` | 136 | 封面取色平台胶水层 |
| `view/pages/MainShell.ets` | 123 | 主壳（Tab 导航 + MiniPlayer 容器） |
| `pages/Index.ets` | 116 | 入口状态机（启动流程） |
| `view/components/LyricView.ets` | 112 | **歌词视图，缺陷核心** |
| `view/pages/SafeModePage.ets` | 111 | 安全模式（含 SafeActionRow） |
| `view/RouteStack.ets` | 102 | 路由栈代数（已有单元测试 RouteStack.test.ets） |
| `view/pages/RecentPage.ets` | 95 | 最近播放 |
| `view/theme/CoverColorCacheCore.ets` | 80 | 取色 LRU 核心逻辑 |
| `view/Router.ets` | 76 | 路由 API（基于 AppStorage） |
| `view/pages/OnboardingPage.ets` | 70 | 引导页 |
| `view/pages/DisclaimerPage.ets` | 57 | 免责声明 |
| `view/pages/LoadingPage.ets` | 23 | 启动加载 |

### 2.2 ArkUI API 使用面（全 `main/ets` 范围 grep 计数）

每行数字为 **grep 命中行数**（逐模式单独运行，避免多模式 `|` 假阴性）。

| API / 能力 | 命中 | 影响 |
| --- | --- | --- |
| `LazyForEach` | **0** | 所有列表全量实例化，大列表内存与首帧代价高 |
| `@Reusable` | **0** | 无列表节点复用 |
| `Toggle(` | **0** | 布尔设置全用「行点击 + 副标题」模拟，无平台开关控件 |
| `bindSheet` | **0** | 5 处底部面板手写 `.position({y:'38%'}).height('62%')` + 遮罩层 |
| `bindMenu` / `bindContextMenu` | **0** | 菜单靠 `menuOpen` @State 内联展开，挤开列表行高 |
| `stateStyles` | **0** | 全应用无按压/焦点反馈状态 |
| `expandSafeArea` | **0** | 安全区靠 `padding({bottom:32})` 硬编码（`MainShell.ets:103`） |
| `Navigation(` / `NavPathStack` | **0** | 自研 Router（已登记 M10.4） |
| `TabContent` | **0**（`YtmSearchParser.ets` 中 2 次属误搜文本） | 无 ArkUI Tabs 组件 |
| `Refresh(` | **0** | 无下拉刷新，首页靠按钮（`HomePage.ets:89`）|
| `GridRow` / `onAreaChange` / 断点 | **0** | 无响应式，全应用唯一 Grid 写死 `columnsTemplate('1fr 1fr')`（`HomePage.ets:272`）|
| `Scroller()` / `scrollToIndex` / `scrollTo(` | **0** | **无任何列表可被程序化滚动** |
| `@ComponentV2` / `@ObjectLink` / `@Observed` | **0** | 全 V1；对象靠 JSON 字符串在组件间传递 |
| `@Extend` / `@Styles` | **0** | 无样式复用 |
| `Theme.isDark()` 内联调用 | **439 次 / 24 文件** | 因 ArkUI M7.4 盲区，动态主题变化时大部分页面不重绘（详见 ❸） |
| `animateTo` | **3**（MiniPlayer ×2、NowPlayingPage ×1）| 仅滑动与封面淡入有动画 |
| `transition(` / `.animation(` / `geometryTransition` | **0** | 无转场、无共享元素、无主题色过渡 |
| `accessibilityText` | **21 / 13 文件** | 与 RELEASE_CHECKLIST §3.3 一致，仅代码确认 |
| `accessibilityDescription` / `Level` / `Group` / `Selected` | **0** | 无角色/分组/状态语义 |

### 2.3 资源目录状态

| 资源 | 现状 |
| --- | --- |
| `base/element/string.json` | 5 条，均为系统面字符串，**零 UI 文案** |
| `base/element/color.json` | 1 条（`start_window_background`）|
| `dark/element/color.json` | 与 base **同值** `#121212` |
| `base/element/float.json` | **不存在** |
| `base/media/` | 60 个 SVG 图标，覆盖率约 70%（见 §3 ❿–附） |

全部 UI 文案与尺寸硬编码在 `.ets` 中——这是 `np.language` 永远只能弹
「语言切换待移植」toast 的根因（`SettingsDetailPage.ets:897`）。

---

## 3. 真实缺陷

### ❶ 歌词视图不跟随播放位置滚动（最大 UX 缺口）

**文件**：`view/components/LyricView.ets`

**根因**：`LyricView.ets:63` 是裸 `Scroll() { Column() { ForEach(...) } }`，
无 `Scroller` 控制器，全工程 `scrollToIndex`/`scrollTo` grep 命中 0。
当前行只改了字号/颜色/粗细（`:78-82`），**视口永不跟随**，用户必须手动滚动。

**Android 对照**：`ui/component/lyrics/SyncedLyricsView.kt`（1062 行）
+ `AdvancedLyricsView.kt`（415 行）+ `LyricsScreen.kt`（1253 行），
用 `animateScrollToItem` + 逐帧插值位置 + 按距离模糊 + `TextMotion.Animated`。
行数比是 112 : 2730（不含 `LyricsScreen`）。

**修法（M11.2）**：
- `LyricView` 新增 `private scroller = new Scroller()`，`Scroll(this.scroller)` 传入
- `@Watch('onPositionChanged')` + `onCoverSeedChanged` 范式（对齐 `MiniPlayer.ets:38-40` 已有写法），在 watch 回调里计算当前行的 Y 偏移后 `scroller.scrollTo({ yOffset })`
- 活跃行定位在视口 30%（对齐 Android `playedLyricViewportFraction = 0.30f`）
- ~~复用 `LyricLineTracker.getInstance().currentIndex()` 替代 `LyricView.currentIndex()`（`:23-34`）中的 O(n) 全量扫描（见 ❼）~~

> **2026-08-26 实施时更正（本条原文两处不准确）**：
> 1. `LyricLineTracker` 并**不**提供 O(1) 查询。`onPosition()` 自身就是线性扫描；只有 `currentIndex()` 这个取 `lastIndex` 缓存的 getter 是 O(1)，而 `lastIndex` 由 `PlayerManager.publishPosition` 单向喂数、且 `setLines()` 会重置为 -1。于是**暂停时打开歌词页会拿到 -1**（既不高亮也不滚动），把它当视图的真源会引入回归。
> 2. 交叉引用写错了：O(n×m) 的论述在 §5，不在 ❼（❼ 是 Tab 持久化）。
>
> 实际做法：抽出纯逻辑 `lyrics/LyricIndexResolver.ets`，`resolve(lines, displayTimeMs, hint)` 从上次结果续扫，常态每 tick 一次比较，回退 seek / 越界 hint 自动退化为整表扫描；配 11 条确定性单测。`LyricLineTracker` 保持其原职责（悬浮歌词栏 / AVSession 标题的「行是否变了」）不动。

**验证**：模拟器 Pura 90 开歌词视图，确认视口随播放位置自动滚动。

### ❷ 冷启动时深色模式失效（**本轮已改，未经设备验证**）

**文件**：`entryability/EntryAbility.ets:29-35`、`pages/Index.ets:33-37`

**根因**：两处都无条件 `AppStorage.setOrCreate('systemDark', false)`；
真值只在 `onConfigurationUpdate`（`EntryAbility.ets:72-76`）里写。
→ 系统处于深色模式时冷启动，应用以浅色渲染直到下次配置变更触发 `onConfigurationUpdate`。

**已改**：`EntryAbility.onCreate` 改为从启动配置播种：

```typescript
AppStorage.setOrCreate('systemDark',
  this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
```

`Index.aboutToAppear` 移除重复的 `setOrCreate('systemDark', false)`
（它会把 EntryAbility 刚播种的真值打回浅色）。

### ❸ 深色模式/动态取色切换后大部分页面不立即重绘（**本轮部分已改**）

**文件**：整个 `view/` 层

**根因**：`Theme.isDark()` 在渲染表达式里被内联调用 **439 次**，
而它内部读 `AppStorage`——正是 `docs/PORTING_EXECUTION_PLAN.md` M7.4 守则记录的
「ArkUI 依赖追踪盲区」（AppStorage 读取在 `build()` 表达式中不被追踪）。
全工程只有 `SettingsPage.ets:22` 一处 `@StorageProp('np.dark_mode')`；
`systemDark` 无任何组件订阅。

**已改**：`view/pages/MainShell.ets:22-33,49-52` 增加双订阅镜像
（范式照抄 `MiniPlayer.ets:17-40` 已验证写法）：

```typescript
@StorageProp('np.dark_mode') @Watch('onThemeChanged') darkModePref: string = 'auto';
@StorageProp('systemDark') @Watch('onThemeChanged') systemDark: boolean = false;
@State isDark: boolean = false;

private onThemeChanged(): void {
  this.isDark = Theme.isDark();
}
```

`tabItem` 内的 `Theme.isDark()` 已改读 `this.isDark`。

**未改（M11.1 剩余）**：同样处理 `NowPlayingPage`、`HomePage`、`LibraryPage`、`ExplorePage` 四页。
其余页面路由转场时重建，已自然刷新，暂不修。

> **2026-08-26 实施时更正 + 范围扩大（已征得用户确认）**
>
> 1. **上一轮 `MainShell` 本身只修了一半**：`tabItem` 改了，但同文件 `build()` 里 Tab 栏背景与页面背景两处 `Theme.isDark()` 未改，即"切深色 Tab 图标变了、Tab 栏底色不变"。本轮补齐。
> 2. **"只改四页"会产生撕裂**：`HomePage` 渲染的 `PlaylistCard`/`SectionHeader`/`EmptyState`（`Ui.ets`）与 `SongRow` 都是独立 `@Component`，其 `@Prop` 未变 → ArkUI 不会重渲染它们。只改页面的结果是"页面背景变深、卡片仍是浅色"，比不改更容易被察觉。
> 3. **"其余页面路由转场时重建，已自然刷新"这句话需要限定**：全屏路由页是 `MainShell.build()` 里的子组件，`MainShell` 的 `isDark` 变化不会重渲染它们；它们只在**下一次导航**时才刷新，在此之前保持旧配色。
>
> 因此改为**单一派生键**方案并覆盖全部 24 个文件 / 440 处调用：`Theme.IS_DARK_KEY = 'theme.isDark'` + `Theme.refreshIsDark()` 发布解析后的布尔值，每个 struct 只加一行 `@StorageProp('theme.isDark') isDark: boolean = false`，表达式里直读 `this.isDark`。相比"每组件 3 行 `@StorageProp×2 + @Watch + @State` 镜像"，样板代码少一个数量级，且彻底消除该类缺陷而不是逐页打补丁。
>
> 发布点仅 4 处：`EntryAbility.onCreate`（从启动配置播种）、`EntryAbility.onConfigurationUpdate`（系统切换）、`Index.aboutToAppear`（持久化的 `np.dark_mode` 异步加载完成后补发——`onCreate` 时 `SettingsRepository` 只塞了默认值）、`SettingsPage.cycleDarkMode`（用户手动切，读 `refreshIsDark()` 的返回值而非本地镜像，因为同一次同步调用内 `@StorageProp` 尚未传播）。
>
> 顺带：删除 `EntryAbility` 里与 `Theme.isDark()` 逻辑重复的私有 `isDark()`；并让系统栏跟随**解析后**的主题——原 `onConfigurationUpdate` 用的是裸系统 colorMode，用户把应用锁定浅色时系统切深色会让状态栏与应用表面不一致。

### ❹ `np.lyric_blur` 是静默死设置（**未登记在 RELEASE_CHECKLIST §6**）

**文件**：`view/pages/SettingsDetailPage.ets:873-879`

**根因**：
- 用户可见开关「歌词模糊效果」显示「已开启/已关闭」，写 `np.lyric_blur`
- grep 全 `main/ets`：该键仅出现在 `SettingsRepository.ets:49`（声明）与 `SettingsDetailPage.ets:85`（读取用于回显）
- **无任何消费方**：`LyricView.ets` 不读此键，开关行为与结果完全断开

**处置（M11.1）**：二选一：
  - 方案 A（接线）：`LyricView` 增加 `@StorageProp('np.lyric_blur') lyricBlur: boolean = true`，
    ~~当前行文字做 `.blur(lyricBlur ? 4 : 0)`~~（对齐 `AdvancedLyricsView.kt` 的 `lyricBlurEnabled` 参数）
  - 方案 B（如实标注）：副标题改为「功能开发中，设置暂不生效」，同步补入 `RELEASE_CHECKLIST.md` §6

**推荐方案 A**，副作用为零（接线而非改功能），M11.2 歌词改造时同步落地更方便。

> **2026-08-26 实施时更正**：已按方案 A 落地，但**模糊对象与原文相反**。原文写「当前行文字做 `.blur(...)`」会把用户正在读的那一行糊掉；Android `AdvancedLyricsView` 是对**非活跃行**按距离模糊、活跃行保持清晰。实际实现：`.blur()` 仅作用于非活跃行，半径 = `min(4, |index - activeIndex|)` vp，活跃行恒为 0。表达式里直读 `this.lyricBlur` 与 `this.activeIndex`（不走辅助方法，否则同样撞 M7.4 追踪盲区）。**模糊观感与逐行 `.blur()` 的性能开销未经设备验证。**

### ❺ `np.show_lyrics` 是静默死设置（**未登记**）

**文件**：`data/SettingsRepository.ets:27`、`view/pages/NowPlayingPage.ets:41`

**根因**：`SettingsRepository` 声明 `KEY_SHOW_LYRICS` 默认 `true`，
grep 全 `main/ets` 无第二处引用。
`NowPlayingPage.ets:41` 用本地 `@State showLyrics: boolean = true`，
每次进播放页都重置为 `true`，持久化偏好被忽略。

**修法**：
```typescript
// NowPlayingPage.ets
@StorageProp('np.show_lyrics') showLyrics: boolean = true;
// 移除本地 @State showLyrics，改用持久化键
```

点击「歌词/封面」按钮时改为 `SettingsRepository.setBoolean(SettingsRepository.KEY_SHOW_LYRICS, !this.showLyrics)`。

### ❻ `SongRow` 两个菜单项静默无效（**未登记**）

**文件**：`view/components/SongRow.ets:136-151`

**根因**：「加入歌单」(`:138-141`) 与「分享」(`:146-151`) 的 `onTap` 只执行
`this.menuOpen = false`，无任何业务逻辑。
与已在 `RELEASE_CHECKLIST.md` §6 登记的三处 toast 占位性质相同，
但这两处**静默关闭菜单**，用户更难察觉。

**处置**：在菜单项旁显示「(暂不可用)」或改为弹 toast 提示，并补入 §6。

### ❼ `np.default_start_tab` 写法绕过持久化层（**本轮已改**）

**文件**：`view/pages/MainShell.ets:120-126`

**根因**：切换 Tab 时用 `AppStorage.setOrCreate('np.default_start_tab', index)` 直写，
绕过 `SettingsRepository.setNumber`，不落 `AppPreferences`，进程重启后归 0。
同时这是`SettingsRepository.KEY_DEFAULT_START_TAB`（`:20`）的语义键，
运行时导航行为会在会话内污染用户设置。

**已改**：

```typescript
private selectTab(index: number): void {
  this.currentTab = index;
  SettingsRepository.setNumber(SettingsRepository.KEY_DEFAULT_START_TAB, index);
}
```

`aboutToAppear` 里的字面量键一并换成 `SettingsRepository.KEY_DEFAULT_START_TAB` 常量。

### ❽ 两处「百分比 `.position()`」未清（违反已定案守则）

**文件**：
- `view/components/Ui.ets:138`：PlaylistCard 收藏角标 `.position({ x: '82%', y: '3%' })`
- `view/pages/DownloadsPage.ets:151`：完成对勾 `.position({ x: '70%', y: '2%' })`

**根因**：`RELEASE_CHECKLIST.md` §3.1 已把「百分比 `.position()` 在字体缩放下不稳定」
列为**已定案守则**（M9.3 据此修了 `SongRow` 角标）。两处与已修缺陷同类，
在 1.45× / 1.75× 字号下角标位置可能错位。

**修法**（对照 `SongRow.ets:49-77` 已验证写法）：

```typescript
// Ui.ets PlaylistCard 收藏角标
Stack({ alignContent: Alignment.TopEnd }) {
  // 封面内容
  Image(...)
  if (this.isFavorite) {
    Image($r('app.media.ic_baseline_favorite_24'))
      .width(16).height(16)
      .fillColor(Theme.warning(Theme.isDark()))
      .padding(5)
      .backgroundColor(Theme.scrim(Theme.isDark()))
      .borderRadius(8)
      .margin({ top: 4, right: 4 })  // 固定 margin 替代百分比 position
  }
}
// DownloadsPage 完成对勾同理
```

**验证**：1.45× 与 1.75× 字号下运行 `uitest dumpLayout`，确认角标与封面无重叠。

### ❾ 删除歌单无二次确认

**文件**：`view/pages/PlaylistDetailPage.ets:335-339`

**根因**：「删除歌单」按钮直接调 `deletePlaylist()`（`:68-74`），
无确认对话框，删完 `Router.pop()`。破坏性操作一键完成，且歌单无回收站机制。

**修法**：在「确认/取消」对话框内放置删除按钮，对话框样式复用已有的 `showRenameDialog`
底部面板写法（`:310-353`）。

### ❿ 探索页两张入口卡片无 `onClick`

**文件**：`view/pages/ExplorePage.ets:199-247`

**根因**：「搜索歌曲」（`:199-222`）和「搜索歌单」（`:224-247`）两张卡片
带 `›` 指示符（`:215`、`:240`）却完全无点击处理。
点击无反应，用户会误以为 bug。

**修法**：「搜索歌曲」点击后聚焦搜索框（`TextInput` 的 `focusable(true)` + `requestFocus()`）；
「搜索歌单」点击后跳转网易云歌单搜索或 B 站收藏夹入口（现有逻辑已在 `ExplorePage.ets:80-104`）。

另：`ExplorePage.ets:180` 错误状态 `EmptyState({ icon: '!', title: this.error })` 无重试入口。
在错误 `EmptyState` 下面追加「重新搜索」按钮，调 `this.search()`。

---

## 4. Android 等价性缺口

本节只记录**直接影响用户感知**的缺口，完整移植清单见 `FEATURE_MATRIX.md`。

| 维度 | Android | 本移植 | 缺口 |
| --- | --- | --- | --- |
| **歌词** | `SyncedLyricsView.kt`(1062) + `AdvancedLyricsView.kt`(415) + 逐帧插值 + 按距离模糊 + 淡出遮罩 + 长按 + 触感 | `LyricView.ets`(112)，无自动滚动 | 见 ❶，M11.2 专项补齐 |
| **主题色过渡** | `NeriTheme.kt:93-158` 40+ ColorScheme 槽位全做 420ms `animateColorAsState` | `Theme.palette()` 按 key 缓存后**瞬切** | 换歌/换主题时配色硬切，丢失签名级观感 |
| **语义色** | material-kolor 从种子同时产出 `onSurface`/`outline` 等 | `textPrimary`/`textSecondary`/`divider`/`danger` 是纯 `dark ? A : B`，**不参与调色板** | 强色调表面上固定辅助色，有对比度风险（未做自动审计）|
| **Tab 状态保持** | 每 Tab 独立 NavHost，保滚动位置 | `MainShell.ets:82-90` `if/else if` 切 Tab，ArkUI 销毁未选分支 | 每次切回首页/资料库重跑全套网络加载（`HomePage.ets:26`、`LibraryPage.ets:43`），滚动位置与 `@State` 全丢失 |
| **MiniPlayer 位置** | 底部（Tab 栏之上） | `MainShell.ets:78-80` Column 首个子节点（**顶部**） | 是否有意？待产品侧确认后决定是否移入 M11.1 |
| **播放页转场** | `NowPlayingScreen.kt` 含共享元素转场（`rememberSharedContentState(key="progress_bar")`）| 无转场 | 留 M11.6 动效专项 |
| **下拉刷新** | 各列表有下拉刷新 | 首页靠右上角按钮（`HomePage.ets:89`）| M11.4 平台控件补全时处置 |

---

## 5. 渲染性能与状态管理债（静态分析，待性能实测）

以下为**已静态确认**的代码路径，运行时影响程度「待设备验证」。

**JSON 往返反模式（高频路径）**

- `SongRow.ets:17-19`：`song()` 在一次 build 里被调 8 次（`:50,51,81,88,98,108,109`），每次 JSON.parse；调用方还要先序列化（`ExplorePage.ets:186`）
- `MiniPlayer.ets:34`：`song()` 在 build 里调 6 次；`@StorageLink('player.positionMs')` 随播放进度每 tick 触发 build，即 6 次/tick 的 JSON.parse
- `NowPlayingPage.ets` 约 10 次；`QueueSheet`（`:600`）每次 build 解析整个队列 JSON

**LyricView 的 O(n×m) 代价**

- `currentIndex()`（`:23-34`）在 `ForEach` 里每行调 4 次（`:73,78,79,82`）→ 60 行歌词约 1.4 万次比较/重绘
- `wordState(word)` 每词调 2 次（`:53,54`）
- 已有 `LyricLineTracker`（`NowPlayingPage.ets:5` 已 import），提供 O(1) 当前行查询，**未被 LyricView 复用**

**WaveformSlider 无条件 50ms 刷新**

- `WaveformSlider.ets:16,49-57`：`setInterval(50ms)` 无条件调 `draw()`，暂停时仍 20fps 刷 Canvas
- `waveY`（`:79`）用 `Date.now()` 使加载脉冲与帧率耦合；暂停状态下 CPU 空转 20fps 与 M10.3 低功耗方向相悖

**SongRow 批量异步读**

- `SongRow.aboutToAppear`（`:21-23`）每行发一次异步仓库读（`isFavorite`）；`ForEach` 全量实例化 + 100 首歌单 = 挂载即 100 个并发读

**SettingsDetailPage 开局遍历下载编目**

- `SettingsDetailPage.aboutToAppear`（`:154-165`）无论打开哪个 section 都遍历整个下载编目逐个 `DownloadStorage.fileSize`；打开「关于」也会触发

---

## 6. 设计令牌与资源化债

**emoji 字形当图标**

`util/IconCatalog.ets`（119 行 / 约 40 个 `if`）把 emoji 映射到 `$r()`，
但调用点仍传 emoji 字面量（`SettingsPage.ets` 14 处、`SettingsDetailPage.ets` 38 处、
`LibraryPage.ets` 12 处等合计约 85 处）。

**未收录字形**（传入后静默落到 `ic_info_24` fallback）：
`'👓'`（`SettingsDetailPage.ets:883`）、`'✍'`(:855)、`'📡'`(:890)、
`'🔌'`(:1043, :1119)、`'📦'`(:1050)、`'🛰'`(:1057, :1126)、
`'📉'`(:1084)、`'🗑'`(:1092, :1140)。

资源里已有 60 个 SVG，直接传 `$r()` 即可；`util/IconCatalog.ets` 应在
统一改造完成后删除。

**重复组件**

- 封面「有图/占位」Stack：`grep 'app.media.ic_music_note_24'` = 17 处 / 11 文件；
  每处都手写 `if (url.length > 0) Image(url) else Image($r(...))` 逻辑
- `LibraryPage.ets:577` `StatCard` 与 `StatsPage.ets:115` `StatTile` 是同一组件的两份拷贝
  （图标尺寸 22 vs 20、数值字号 14 vs 16 的无意漂移）

**三参数图标陷阱**

`SectionHeader`/`EmptyState`/`SettingRow` 的图标 API 是
`icon: string`（emoji）+ `iconResource: Resource` + `showIcon: boolean`，
且 `showIcon` 默认 `false`——只传 `iconResource` 而不传 `showIcon: true` 会静默不渲染。

**字形作控件**（无障碍风险）

`'⋯'`（`NowPlayingPage.ets:275`）、`'‹'`（`SettingsDetailPage.ets:687` 等）、
`'›'`（`ExplorePage.ets:215,240`）、`'＋'`（`PlaylistDetailPage.ets:265`）、
`'✓'`（`DownloadsPage.ets:143`）——资源里都有对应 SVG。
被 Button 包住的已补 `accessibilityText`；裸 `Text` 的几处无障碍属性缺失。

---

## 7. M11 编排建议

> **边界说明（必须遵守）**：`HARMONYOS_NATIVE_FEATURES.md` §12 M10.4 已明确包含
> Navigation 迁移、触控 48vp、tablet/2in1/折叠悬停/横屏适配，且依赖 M9.3a（镜像阻塞）。
> M11 全部内容**不包含**以上项目，与 M10.4 正交，均不需要新镜像即可完成主体实施。

本次交付范围：**M11.1 + M11.2**（由用户确认）。

### M11.1 视图层缺陷清零（已完成，2026-08-26；构建+单测已过，设备未验证）

**目标**：闭合 ❷–❿ 所有已确认缺陷；处置全部死设置。

| 缺陷 | 文件 | 改动 | 状态 |
| --- | --- | --- | --- |
| ❷ | `entryability/EntryAbility.ets` | `systemDark` 从 `this.context.config.colorMode` 播种 | ✅ |
| ❷ | `pages/Index.ets` | 移除会把真值打回浅色的重复覆写；补发 `refreshIsDark()` | ✅ |
| ❸ | `view/Theme.ets` + `view/pages/*` + `view/components/*`（24 文件 / 440 处） | 新增派生键 `theme.isDark` + `Theme.refreshIsDark()`；每个 struct 一行 `@StorageProp`，表达式直读 `this.isDark` | ✅ 范围较原计划扩大，见 ❸ 更正框 |
| ❺ | `view/pages/NowPlayingPage.ets` | `@State showLyrics` → `@StorageProp('np.show_lyrics')`，切换走 `SettingsRepository.setBoolean` | ✅ |
| ❻ | `view/components/SongRow.ets` | 「加入歌单」「分享」加「（暂不可用）」+ toast 指向可用替代 | ✅ 功能本身仍未移植 |
| ❼ | `view/pages/MainShell.ets` | `selectTab` 改走 `SettingsRepository.setNumber`；键名换常量 | ✅ |
| ❽ | `view/components/Ui.ets`、`view/pages/DownloadsPage.ets` | 百分比 `.position()` → `Stack({alignContent: TopEnd})` + 固定 margin | ✅ |
| ❾ | `view/pages/PlaylistDetailPage.ets` | 新增 `showDeleteConfirm` 二次确认对话框 | ✅ |
| ❿ | `view/pages/ExplorePage.ets` | 「搜索歌曲」→ `focusControl.requestFocus()`；「搜索歌单」→ toast + 副标题如实说明；错误态补「重新搜索」 | ✅ |

**死设置 ❹ `np.lyric_blur`** 已随 M11.2 落地（见 ❹ 更正框：模糊对象与原文相反）。

**验证门槛实际结果**（2026-08-26，`hvigorw 6.24.4` / DevEco Studio 6.1.1.300 / SDK 6.1.1.125 API 24）：

| 门槛 | 结果 |
| --- | --- |
| `assembleHap entry@default` | ✅ BUILD SUCCESSFUL |
| `assembleHap entry@ohosTest` | ✅ BUILD SUCCESSFUL |
| 本地单测（基线只增不减） | ✅ **827/827 pass, 0 failure, 0 error**（816 基线 + 新增 11）。**必须读 `coverage.log`**：本轮实证 hvigor 在有用例失败时仍打印 `BUILD SUCCESSFUL` 且 `exit=0` |
| ArkTS 编译错误 | ✅ 0 |
| CodeLinter 与基线逐字一致 | ❌ **未跑** —— 命令行入口已不存在（只剩 IDE 插件）。历史上还记录过两个互相矛盾的基线（`AGENTS.md` 旧文 "17 warn + 1 suggestion" vs 本文原 "24 warn + 2 suggestion"），两者当前都无法从命令行复现 |
| `uitest dumpLayout` ×3 档字号验证 ❽ | ❌ **未跑** —— 需设备，见下 |

### M11.2 歌词视图对齐（已完成，2026-08-26；构建+单测已过，设备未验证）

**目标**：歌词自动滚动（❶）+ 接线 `np.lyric_blur`（❹）+ 消除 O(n×m)。

改动文件：
- `view/components/LyricView.ets`（主体重写）
- `lyrics/LyricIndexResolver.ets`（**新增**，纯逻辑，可单测）
- `entry/src/test/ets/test/LyricIndexResolver.test.ets`（**新增** 11 例，已注册进 `entry/src/test/List.test.ets`）
- `view/pages/NowPlayingPage.ets`（`currentLyricIndex()` 改走同一 resolver 并补上此前缺失的 `np.lyric_offset_ms`）

落地要点：
- **自动滚动**：`Scroll(this.scroller)` + `@Watch` 监听 `player.positionMs` / `np.lyric_offset_ms`；行 Y 偏移经每行 `onAreaChange` 实测缓存（存普通字段，避免在布局回调里写 `@State` 引发重入）；视口高存 `@State` 并带 1vp 死区，用于给首/末行留 30%/70% 内边距，使它们也能进入 30% 带位；`scrollTo` 动画 420ms EaseOut。手动触摸后 2.5s 内不抢滚动，点击行 seek 立即解除抑制。
- **性能**：`LyricIndexResolver.resolve(lines, time, hint)` 从上次结果续扫（常态每 tick 一次比较），取代原先每行 4 次的全表扫描。**未用 `LyricLineTracker`**，理由见 ❶ 更正框。
- **卡拉 OK 逐词高亮**：从 `wordState()` 辅助方法改为在 `Span` 表达式里直读 `positionMs`/`lyricOffsetMs`——原写法同样撞 M7.4 盲区，只在无关父级重建恰好重造整个视图时才碰巧刷新。

**验证门槛**：同 M11.1（构建 + 单测已过）。**模拟器确认歌词视口随播放位置自动滚动一项未执行**，原因见 §8。

### M11.3–M11.7 路线（后续里程碑，本次不实施）

| 编号 | 内容 | 关键技术点 |
| --- | --- | --- |
| M11.3 | 列表与状态性能 | `LazyForEach`+`IDataSource`+`@Reusable`；消除 JSON 往返（`@Observed`/`@ObjectLink` 或 V2 试点）；`WaveformSlider` 播放态门控 |
| M11.4 | 平台控件归位 | 布尔设置改 `Toggle(ToggleType.Switch)`；底部面板改 `bindSheet`；菜单改 `bindContextMenu`；`stateStyles` 按压反馈；`Search` 组件替换 TextInput；`Refresh` 下拉刷新 |
| M11.5 | 设计令牌与资源化 | 建 `float.json` + UI 文案进 `string.json`（多语言前置）+ 调用点直传 `$r()` 并删 `IconCatalog` + 收敛 `CoverThumb`/`StatTile` |
| M11.6 | 动效 | 主题色过渡（420ms，对齐 `NeriTheme.kt`）；路由转场（建议并入 M10.4 Navigation 落地后）；歌词行动画 |
| M11.7 | 拆分 SettingsDetailPage | 按 section 拆 10 个子组件 + 按需加载下载编目统计 |

---

## 8. 未验证项（如实登记）

> 2026-08-26 更新：M11.1/M11.2 的代码改动**已通过构建与本地单测**，但**全部 UI 行为仍未在设备上验证**。
> 下面第一条是上一轮（2026-08-25）的登记，现已可撤回；其余条目按当前状态重写。

- ~~**本轮的 4 个文件改动（❷❸❼）未通过任何门禁**~~ —— **2026-08-26 已补齐门禁**：`assembleHap entry@default` 与 `entry@ohosTest` 双双 BUILD SUCCESSFUL、ArkTS error 0、本地单测 **827/827**（0 failure / 0 error，816 基线只增不减）。**但 CodeLinter 与设备验证仍未执行**（见下）。
- **CodeLinter 本轮未跑**：DevEco Studio 6.1.1.300 不再提供 `codelinter` 命令行入口（只剩 IDE 插件 `E:\DevEco Studio\plugins\codelinter`）。历史上记录过两个互相矛盾的基线（`AGENTS.md` 旧文 "17 warn + 1 suggestion" vs 本文原 "0 error / 24 warn / 2 suggestion"），**两者当前都无法从命令行复现**，因此本轮既不能声称"与基线一致"，也无法判定新增代码是否引入新 warn。需在 IDE 内补跑并重新确立单一基线。
- **设备验证本轮未执行，且有明确前置阻塞**：模拟器本身可用（2026-08-26 实测 `hdc list targets` → `127.0.0.1:5555` 存活，`const.ohos.apiversion` = 24、`const.ohos.fullname` = `OpenHarmony-6.1.1.125`，与工程目标 SDK 一致，且 `moe.ouom.neriplayer` 已安装）。阻塞在签名：
  - `NERIPLAYER_SIGNING_PASSWORD`（33 位私有 keystore 口令）在本会话**未设置**，而 `sign-local.ps1` 强制要求 ≥32 字符；
  - SDK 自带 `OpenHarmony.p12`（公开默认口令 `123456`，含 `openharmony application profile debug` 别名，实测可打开）会被该校验直接拒绝；
  - 即便绕过校验，设备上已安装的包是用私有 keystore 签的，签名不一致会让 `hdc install -r` 失败，只能先 uninstall——**而 uninstall 会丢掉 `preferences/neri_player_data` 等用户数据**，故未执行。
  - 解除办法：在设置了 `NERIPLAYER_SIGNING_PASSWORD` 的会话里跑 `.\sign-local.ps1 -HvigorwPath 'E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' -DeviceIds <udid>`，再按 §9 清单复跑。
- **❷❸ 深色模式行为**：冷启动播种与派生键重绘为静态推断 + 编译期保证（每个读 `this.isDark` 的 struct 都必须声明该 `@StorageProp`，否则编译失败——本轮确实用这一点抓到了 `SettingsPage` 漏声明），但"切深色后整屏是否真的立即、且**无撕裂**地重绘"未在设备确认。派生键在 `EntryAbility.onCreate` 播种，若某条启动路径先于它渲染，`@StorageProp` 会用组件默认值 `false` 建键——此风险未在设备排除。
- **❶ 歌词滚动**：滚动流畅度、活跃行是否真的落在视口 30%、`onAreaChange` 实测行高在换行/翻译/音译行存在时是否准确，均未验证。首/末行的 30%/70% 内边距在极短歌词（1–2 行）下的观感未验证。
- **❹ 歌词模糊**：逐行 `.blur()` 的**性能开销未实测**。当前无 `LazyForEach`（M11.3），`ForEach` 会实例化全部行，长歌词（60+ 行）下同时挂载数十个模糊节点的代价未知；若实测卡顿，应改为只对活跃行附近若干行施加模糊。
- **❽ 角标缩放稳定性**：改法与 M9.3 字号回归结论同向（已在 `SongRow` 验证过同一写法），但本轮未在新角标写法下重跑 `uitest dumpLayout`（1.0 / 1.45 / 1.75 三档）。
- **❿ `focusControl.requestFocus()`**：API 存在于 `component/common.d.ts`（全局 ambient namespace，无需 import，已编译通过），但**点击卡片后软键盘是否真的弹出、焦点是否真的落到 `TextInput`** 未在设备验证。
- **❾ 删除确认**：对话框沿用了同文件 `showRenameDialog` 的写法，包括其"外层 `Column.onClick` 关闭遮罩"结构——点击对话框内的非交互区域（如说明文字）会冒泡到遮罩而关闭对话框。这是**沿袭既有实现的已知小瑕疵**，非本轮引入，未修以保持局部一致。
- **`BiliFavPage`**：仍未走查（需 B 站登录态，`RELEASE_CHECKLIST` §6 已记录）。本轮只对它做了 ❸ 的机械替换（`Theme.isDark()` → `this.isDark`），未做布局走查。
- **MiniPlayer 顶部位置**：仍未处置。产品侧未确认是笔误还是有意，按边界约定不作改动。
- **性能数据**：§5 所有项在本轮仍无实测支撑（`WaveformSlider` 50ms 空转、`SongItem` JSON 往返、`SongRow` 批量异步读、`SettingsDetailPage` 开局遍历下载编目均未动，已登记 M11.3/M11.7）。
- **对比度审计**：语义色不参与动态调色板的对比度风险尚未量化（未动）。
- **§2 计数表**：`Theme.isDark()` 一行原记 "439 次 / 24 文件"，本轮按**出现次数**（非命中行数）实测为 **440 处 / 24 文件**，差异来自同一行出现两次的情况；该行现已全部消除，仅 `Theme.refreshIsDark()` 内部保留一处对 `Theme.isDark()` 的调用。其余计数未复核。

---

## 9. 后续（设备复跑清单）

M11.1 / M11.2 实施完成后，在 Pura 90 API 24 模拟器复跑：

1. 冷启动时系统处于深色模式，确认应用以深色渲染（❷）。
2. 在设置页切换「深色模式 → 浅色 → 跟随系统」，确认主界面立即跟随（❸）。
3. 开一首有歌词的曲目，确认歌词视图自动滚动且活跃行位于视口约 30% 处（❶）。
4. 开启/关闭「歌词模糊效果」，确认当前行模糊效果实际变化（❹）。
5. 播放页切封面模式再退出，重进确认仍为上次保存的封面/歌词状态（❺）。
6. 切 Tab 若干次再重启，确认恢复到上次选中的 Tab（❼）。
7. 在 1.0/1.45/1.75 三档字号下打开含收藏歌单的首页，
   确认 PlaylistCard 收藏角标无重叠（❽ `uitest dumpLayout`）。
8. 打开歌单详情，尝试删除歌单，确认出现确认对话框（❾）。
9. 探索页点「搜索歌曲」「搜索歌单」两张卡片，确认有响应（❿）。
10. 据结果更新 `FEATURE_MATRIX.md`「歌词解析与同步」行的「下一验证点」列，
    并在 `PORTING_EXECUTION_PLAN.md` §8 追加 M11.1/M11.2 完成行。
