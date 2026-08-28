# UI 动画开发计划（M11.6 动效专项编排）

> 调研日期：2026-08-28。执行者：ZCode agent。结论消费者：`PORTING_EXECUTION_PLAN.md` §6 M11.6、
> `FEATURE_MATRIX.md`「动态取色/高级视觉」行、`UI_REVIEW_M11.md` §7 M11.6 与 §9 设备复跑清单。
>
> 方法：先读 `PORTING_EXECUTION_PLAN.md` / `HARMONYOS_NATIVE_FEATURES.md` / `UI_REVIEW_M11.md` /
> `FEATURE_MATRIX.md` 确认已登记边界，然后逐文件通读 `NeriPlayer-HarmonyOS/entry/src/main/ets/view/`
> 动画相关实现（MiniPlayer / LyricView / NowPlayingPage / WaveformSlider / Theme / MainShell / Router），
> 对照 Android 侧动画行为清单（`NeriPlayer-master/ui/**`：NeriTheme.kt、NowPlayingScreen.kt 58 处动画 API、
> SyncedLyricsView.kt、AdvancedGlassNavigationTransition.kt、SettingsMotionSection.kt、NeriMiniPlayer.kt、
> WaveformSlider.kt，由子代理逐文件抽取），最后对本机 API 24 SDK（`E:\DevEco Studio\sdk\default`）
> 的 `.d.ts` 逐项核对拟用 ArkUI 动画 API 的真实可用性。
>
> **未做**：设备/模拟器运行验证（阻塞于 `NERIPLAYER_SIGNING_PASSWORD` 缺失，同 `UI_REVIEW_M11.md` §8）。
> 本文全部结论为**静态审查级**，凡涉及运行时表现均标注「待设备验证」。

---

## 1. 结论摘要

鸿蒙侧全工程动画仅有 4 处（3 处 `animateTo` + 1 处滚动动画），`.transition()` / `.animation()` /
`geometryTransition` / `keyframeAnimateTo` / `transitionEffect` **全部零命中**；Android 上游动画是全局性的
（仅 NeriApp.kt 就有约 26 处 tween + 20+ 处 enter/exit 组合）。差距最大的三块：

1. **主题色过渡**（M11.6 已登记）：Android `NeriTheme.kt:47,93-158` 对 48 个 ColorScheme 槽位做 420ms
   `FastOutSlowInEasing` 颜色动画；本移植 `Theme.palette()` 按 key 缓存后**瞬切**。M11.1 建立的
   「单一派生键 + 全量订阅」架构恰好为 `animateTo` 全局过渡提供了接线点。
2. **播放页↔歌词页转场**：Android 是 300ms 线性 fade + 9 组共享元素飞行（`SharedTransitionLayout`）；
   本移植是 `if/else` 瞬切。ArkUI `geometryTransition`（`@since 11`，SDK 已核对）是等价机制。
3. **歌词行动画**：Android 有行缩放 spring、±9° 3D 翻转、按距离的透明度/模糊、边缘渐隐遮罩、
   96ms 时间平滑；本移植 M11.2 只补了自动滚动与静态模糊，行切换仍是字号/颜色/字重瞬跳。

计划将 M11.6 拆为 **M11.6a–e 五个可独立验收的子任务**，按「价值/风险/依赖」排序（§4）。
拟用的全部 ArkUI 动画 API 均已在 API 24 SDK `.d.ts` 核对（§3），无凭记忆断言项。

---

## 2. 现状审查

### 2.1 鸿蒙侧已有动画（全部 4 处）

| 位置 | 动画 | 参数 | 对照 Android |
| --- | --- | --- | --- |
| `MiniPlayer.ets:159,165` | 横滑切歌释放回弹 `animateTo`（translate+scale） | 180ms `Curve.Friction`，阈值 72vp/峰值 52vp（指数阻力） | Android 为**两段式**：先 120ms 冲到 ±52vp 再 180ms 回 0，且切歌在动画后回调（`NeriMiniPlayer.kt:115-128`）；本移植**立即切歌**后单段回弹，行为不同（M11.6e 对齐） |
| `NowPlayingPage.ets:114` | 背景封面 crossfade（双层 Image 淡入后收拢） | 400ms `Curve.EaseOut` + 460ms 定时收拢（M8.4，token 防乱序） | Android 背景取色 bgColor 是 450ms `FastOutSlowIn` 颜色动画（`NeriApp.kt:1158-1162`），机制不同但意图一致 |
| `LyricView.ets:127` | 歌词自动滚动 `scroller.scrollTo` | 420ms `Curve.EaseOut`（M11.2） | Android `animateScrollToItem` 用 LazyList 默认 spring，无自定义时长 |
| `WaveformSlider.ets:49-57` | 波形相位循环 + 加载脉冲（Canvas `setInterval` 50ms 重绘） | 相位 2s 循环、脉冲 1.4s | Android 用 `withFrameNanos` 逐帧 + 振幅 500ms 线性渐变 + `areAnimatorsEnabled()` 检查（`WaveformSlider.kt:104-117`）；本移植无振幅渐变、暂停时仍 20fps 空转（M11.3 已登记门控） |

歌词逐词卡拉 OK 高亮（`LyricView.ets:171-180` Span 直读 positionMs）与背景模糊随距离变化
（`:229-231`）是**状态驱动但无时间维度**的瞬时切换。

### 2.2 静默缺失（Android 有、本移植无，且文档未逐项登记）

- 全屏路由进出无转场：`MainShell.build()` 的 `route.name` if/else 分支瞬切（Android 透明详情页
  220/240ms 垂直滑动 + 抽屉 300/280ms fade + 主 tab 70+330ms，见 §2.3 速查表）。
- 播放页「歌词/封面」切换无转场（Android 300ms fade + 共享元素，共享元素 key 清单见 §4 M11.6b）。
- MiniPlayer 显隐无动画：`MainShell.ets:85-87` `if (currentSongJson.length > 0) MiniPlayer()` 瞬现瞬隐
  （Android slideIn+fadeIn 220/180ms，slideOut+fadeOut 180/120ms，`NeriApp.kt:3641-3656`）。
- 歌词行切换瞬跳：字号 ±2、颜色、字重、模糊全部无过渡（Android 行缩放 spring(ζ=0.85)、
  ±9° 翻转 260ms、透明度/模糊按距离衰减、上下边缘 72dp 渐隐）。
- 主题色瞬切（M11.6 已登记，见 §1）。

### 2.3 Android 动画参数速查表（移植对齐基准）

来源与逐条 file:line 引用见子代理调研记录；此处只列计划将引用的参数。

| 用途 | duration | 曲线 | Android 来源 |
| --- | --- | --- | --- |
| 主题色过渡（48 槽位） | 420ms | FastOutSlowInEasing = CubicBezier(0.4,0,0.2,1) | `NeriTheme.kt:47,151-154` |
| 播放页↔歌词页整页 fade | 300ms | LinearEasing | `NowPlayingScreen.kt:290,1756-1771` |
| 透明详情页开/关（垂直滑动） | 220ms / 240ms | FastOutSlowInEasing | `NeriApp.kt:304-305` |
| 抽屉式转场开/关 | 300ms / 280ms | FastOutSlowInEasing | `NeriApp.kt:306-307` |
| NowPlaying 全屏层 enter/exit | 滑动 300/250ms + fade 150ms | FastOutSlowInEasing | `NeriApp.kt:3679-3689` |
| MiniPlayer 显隐 enter/exit | 滑动 220/180ms + fade 180/120ms | FastOutSlowInEasing | `NeriApp.kt:3641-3656` |
| MiniPlayer 滑动释放 | 120ms（冲向 ±52vp）→ 180ms（回 0）；取消回弹 160ms | FastOutSlowInEasing | `NeriMiniPlayer.kt:115-128,151-159` |
| 歌词行缩放 | spring（StiffnessLow, ζ=0.85） | — | `SyncedLyricsView.kt:262-269` |
| 歌词行 3D 翻转 | 260ms | 默认 tween | `SyncedLyricsView.kt:113,497-502` |
| 歌词时间平滑 | 96ms（>180ms 跳变直接 snap） | LinearEasing | `SyncedLyricsView.kt:98-99,290-297` |
| 歌词缩放值 | active 1.1、距离 1→0.9、≥2 每步 −0.02 下限 0.8 | — | `SyncedLyricsView.kt:102-114,1040-1046` |
| 歌词模糊/透明度（按距离） | 模糊 1/1.5/2/2.5/4×；透明度开模糊 0.72→0.40 每距离 −0.08 下限 0.16 | — | `SyncedLyricsView.kt:1048-1062` |
| 波形振幅渐变 | 500ms | LinearEasing | `WaveformSlider.kt:104-110` |
| 队列行拖拽缩放 | 180ms | CubicBezier(0.2,0,0,1) | `NowPlayingScreen.kt:1029-1043` |

**动效用户设置**：Android `SettingsMotionSection` 的 12 个键中，与动画直接相关的只有
`lyric_blur_enabled`/`lyric_blur_amount`（本移植已有布尔版 `np.lyric_blur`，M11.2 已接线）与
`coherent_feedback_enabled`（导航转场模式二选一，默认 false；依赖 Navigation，留 M10.4）。
**Android 无全局「减少动画」设置**，唯一的系统联动是 `WaveformSlider.kt:114` 的
`ValueAnimator.areAnimatorsEnabled()` 检查——鸿蒙 API 24 SDK 全量 grep `reduceMotion` 零命中
（2026-08-28 实测，含 hms 目录），**无公开等价 API，本计划不做该联动**，如实登记。

---

## 3. 平台能力核对（API 24 SDK，2026-08-28 逐项 grep 实证）

| API | 声明位置 | since | 用途 |
| --- | --- | --- | --- |
| `geometryTransition(id, options?)` | `component/common.d.ts:26947` | 11 | 共享元素转场（播放页↔歌词页等） |
| `TransitionEffect`（`OPACITY`/`IDENTITY`/`SLIDE`/`move()`、`.animation()`、`.combine()`） | `component/common.d.ts:7238-7593` | 10+ | 条件挂载/卸载的进出场转场（if/else 分支切换、MiniPlayer 显隐） |
| `curves.springMotion(response, dampingFraction, overlapDuration)` | `api/@ohos.curves.d.ts:730` | 11 | 物理弹簧曲线（歌词行缩放；dampingFraction 即阻尼比 ζ，默认 0.825） |
| `curves.cubicBezierCurve(x1,y1,x2,y2)` | `api/@ohos.curves.d.ts:578` | 9 | 精确复刻 FastOutSlowIn = (0.4, 0, 0.2, 1) |
| `keyframeAnimateTo(param, keyframes)` | `api/@ohos.arkui.UIContext.d.ts:4498` | 12 | 关键帧（MiniPlayer 两段回弹若需精确编排时的备选） |
| `@ohos.graphics.displaySync`（`setExpectedInterval` + `on('frame')`） | `api/@ohos.graphics.displaySync.d.ts:80` | 11 | 逐帧回调（歌词时间平滑、WaveformSlider 相位），替代 `setInterval(50)` |
| `AnimateParam.curve: Curve \| string \| ICurve` | `component/common.d.ts:3952` | 7 | 上述曲线可直入 `animateTo`/`animation` |
| `reduceMotion` 类减动效 API | **全 SDK 零命中** | — | 不做系统减动效联动（见 §2.3 末段） |

**一个关键的不确定点（必须设备探针）**：`animateTo` 闭包内执行 `AppStorage.setOrCreate`（主题派生键/
封面种子）时，全部 `@StorageProp` 订阅组件的属性变化是否被动画捕获。`.d.ts` 层无法证明，社区有成功
先例但无官方承诺。M11.6a 的验收顺序把这一点列为**第一个设备探针**，并准备确定性回退方案（§4 M11.6a）。

---

## 4. 里程碑编排（M11.6a–e）

> 排序原则：先基建后效果、先自包含页面后全局结构、与 M11.3/M11.4/M10.4 的交叉边界在 §5 明确。
> 每个子任务的验收门槛统一为：`assembleHap`（entry@default + entry@ohosTest）双 BUILD SUCCESSFUL +
> 本地单测（**必须读 `coverage.log`**，基线 827 只增不减）+ 新增纯逻辑用例已注册进
> `entry/src/test/List.test.ets`。设备验证全部并入 `UI_REVIEW_M11.md` §9 复跑清单（阻塞于签名口令）。
> CodeLinter 命令行入口不存在，按 AGENTS.md 如实记「本轮未跑 lint」。

### M11.6a 动效基建 + 主题色过渡（最高价值，对应已登记缺口）

> **状态：已实施（2026-08-28）。构建（default+ohosTest）与本地单测 832/832 已过；R1 探针与观感未上设备。**
> 落地与原计划的差异：MotionSpec 拆成两个文件——`MotionSpec.ets`（常量+距离函数，零 @ohos 依赖，
> 本地可测）与 `MotionCurves.ets`（`curves.*` 工厂）——否则曲线 import 会让纯常量也脱离本地单测环境。

**目标**：主题色/动态取色切换从瞬切变为 420ms 全局过渡，并建立全工程统一的动效参数层。

1. 新增 `view/theme/MotionSpec.ets`（**纯逻辑、零 @ohos 依赖、可单测**）：
   - 常量：`THEME_COLOR_TRANSITION_MS = 420`、`PAGE_FADE_MS = 300`、`DETAIL_OPEN_MS = 220`、
     `DETAIL_CLOSE_MS = 240`、`DRAWER_OPEN_MS = 300`、`DRAWER_CLOSE_MS = 280`、
     `NOWPLAYING_ENTER/EXIT`（300/250 + 150 fade）、`MINIPLAYER_ENTER/EXIT`（220+180 / 180+120）、
     `SWIPE_RELEASE_STAGE_MS = 120` / `SWIPE_RELEASE_RETURN_MS = 180` / `SWIPE_CANCEL_MS = 160`；
   - 曲线工厂：`fastOutSlowIn()` 返回 `curves.cubicBezierCurve(0.4, 0, 0.2, 1)`（FastOutSlowIn 的
     精确等价），`lyricRowSpring()` 返回 `curves.springMotion(0.55, 0.85)`（ζ 对齐 Android 0.85，
     response 初值待设备调优）；
   - 纯函数：`lyricScaleForDistance(d)` / `lyricAlphaForDistance(d, blurOn)` /
     `lyricBlurForDistance(d)`（数值逐条对齐 §2.3 表，即 `SyncedLyricsView.kt:1040-1062`）。
   - 单测 `test/MotionSpec.test.ets`：常量与 Android 基准逐值断言 + 三个距离函数的边界断言。
   **曲线工厂与常量分离**：常量/纯函数进本地单测；`curves.*` 调用集中在此一处，视图层不散落魔法数。
2. 主题色过渡接线（`animateTo` 发布点方案）：
   - `Theme.ets` 新增 `refreshIsDarkAnimated()`：在 `animateTo({ duration: 420, curve: MotionSpec.fastOutSlowIn() })`
     闭包内执行现有 `AppStorage.setOrCreate(IS_DARK_KEY, dark)`；`refreshIsDark()` 保持纯发布语义不动画。
   - 替换 3 个**运行时**发布点为动画版：`EntryAbility.onConfigurationUpdate`（系统深浅色切换）、
     `SettingsPage.cycleDarkMode`（用户手动切换）。`Index.aboutToAppear` 的启动补发与
     `EntryAbility.onCreate` 播种**保持不动画**（首帧前动画无意义且可能闪变）。
   - 封面种子发布（`CoverArtColorCache` 写 `player.coverSeedHex` 处）同样包 `animateTo` 420ms——
     换歌时 `Theme.palette()` 缓存键变化即全局配色渐变，对齐 Android「换歌即换肤」的签名观感。
   - MiniPlayer / NowPlayingPage 背景等已有 `@Watch` 镜像的组件会随订阅自动进入动画范围，无需逐组件改动
     （M11.1 的派生键架构收益）。
3. **设备探针（首个 ohosTest，签名恢复后优先跑）**：切深色模式 → 断言订阅组件背景色在 420ms 内连续变化。
   若 AppStorage-in-animateTo 不被捕获：回退方案为给 MainShell 背景层 / Tab 栏 / MiniPlayer / NowPlaying
   背景 4 处顶层表面加 `.animation({ duration: 420, curve })`（属性级动画不依赖探针结果，观感降级但
   确定生效），并在本文档登记降级结论。

**验收**：构建 + MotionSpec 单测 + 静态确认 440 处 `this.isDark` 表达式无需改动。观感待设备验证。

### M11.6b 播放页↔歌词页转场（签名级动画）

> **状态：已实施（2026-08-28）。构建+单测已过；观感未上设备。**
> 实施补充：ArkUI transition 在首次挂载也会播放，而 Android AnimatedContent 只在状态变化时动画——
> 故加 `contentTransitionArmed` 首帧布防（进播放页不闪淡入，点「歌词」按钮才播）。

**目标**：`NowPlayingPage` 的 `if (this.showLyrics)` 分支切换获得 300ms 线性 fade（对齐 Android
`NowPlayingScreen.kt:1756-1771`）。

1. 两个分支根容器各挂 `.transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Linear }))`
   （`TransitionEffect` 已核对，`common.d.ts:7264`）。
2. **共享元素（geometryTransition）在当前布局下无处可飞，Phase 1 不做**，理由如实记录：Android 的
   共享元素对端（小封面 `cover_image`、标题 `song_artist`、按钮组）在 `LyricsScreen` 上都存在；
   本移植歌词模式是全屏歌词、无封面无标题区，`geometryTransition` 缺少落点。若后续产品决定给歌词模式
   加顶部小封面（Android `LyricsScreen.kt:296-306` 的 1→0.6 缩回布局），再启用
   cover/标题两组 geometryTransition——登记为可选项，不在本计划内强推。
3. 字号/颜色切换的顺带收益：fade 转场天然掩盖歌词行字号突变的一部分观感，但 M11.6c 仍需独立处理行内动画。

**验收**：构建 + 单测基线；转场帧表现待设备验证（若 M11.6a 探针确认 fade 类 transition 可用，此处风险同步消除——两者同为属性动画管线，可共用一条设备验证结论）。

### M11.6c 歌词行动画（构建于 M11.2 的 LyricView 之上）

> **状态：已实施（2026-08-28，除第 4 条边缘渐隐）。构建+单测已过；观感/性能未上设备。**
> 实施补充：①ArkUI ForEach item builder 体内只允许 UI 组件语法（局部 const 编译报
> `Only UI component syntax can be written here`），距离计算内联进属性表达式；MotionSpec 距离函数
> 为纯参数函数，`this.activeIndex` 读取在表达式实参处，依赖追踪可见（与 M7.4 盲区不冲突）。
> ②**边缘渐隐（第 4 条）延后**：ArkUI 无渐变 mask，需 `linearGradient` 多停靠点 + `blendMode(DST_IN)`
> 离屏合成，无设备验证盲改的失败形态是整块渐变色盖住歌词，登记待签名恢复后设备调参。
> ③模糊映射落地为 `min(4, 1.5 × 倍率)`（保留 M11.2 的 4vp 性能顶棚）。

**目标**：歌词行随活跃行迁移产生缩放/透明度过渡，视口边缘渐隐，模糊映射对齐 Android。

1. 行属性过渡：`LyricView.onPositionChanged` 中把 `this.activeIndex = next` 包进
   `animateTo({ curve: MotionSpec.lyricRowSpring() })`——fontSize/fontColor/scale/opacity 的变化即被
   弹簧曲线驱动（每行属性表达式已直读 `this.activeIndex`，天然可动画，无 M7.4 盲区）。
2. 新增行属性：`.scale()`（`MotionSpec.lyricScaleForDistance`）与 `.opacity()`
   （`lyricAlphaForDistance`），与既有 `.blur()` 同样在 ForEach 行表达式直读 `activeIndex`。
   `fontWeight` 动画支持不保证（可能仍瞬跳），不作为验收项。
3. 模糊映射对齐：现有 `Math.min(4, |d|)` 线性改为 `MotionSpec.lyricBlurForDistance`（1/1.5/2/2.5/4×
   饱和），保持 `np.lyric_blur` 布尔语义不变（amount 滑条升级为可选后续项，见 §6）。
4. 视口上下边缘渐隐：`LyricView` 外层 Stack 叠加两条 `linearGradient` 遮罩（高度 72vp 对齐 Android），
   渐隐到播放页 scrim 色（歌词区当前叠于模糊背景 + scrim 之上，直接透明渐隐无背景色可对齐，需按
   `Theme.scrim` 近似；具体观感待设备验证后定）。
5. **3D 翻转（±9° rotationX）默认不做**：Android 该效果与其「行进入视口的滚动方向感」耦合，ArkUI 下
   对每行 `.rotate({ x: 1, angle })` 的大规模应用性能未知，且 M11.3 LazyForEach 未落地前 60+ 行全部
   挂载。登记为可选项，与 §5 的 M11.3 依赖一并评估。
6. **卡拉 OK 词内渐变填充（Android `multilineGradientReveal`）与 96ms 时间平滑不纳入本里程碑**：
   前者需要 Canvas 自绘文本或逐字 Span 几何裁剪（ArkUI Text 无渐变填充 API），后者需要
   `displaySync` 逐帧外推 `positionMs`（当前 500ms tick 粒度对逐词高亮偏粗）。两者合并登记为
   **研究项 R1**，先在设备上评估现有 500ms 三态高亮的实际观感再决定投入。

**验收**：构建 + MotionSpec 距离函数单测（本任务消费 M11.6a 产物）。行过渡流畅度、60 行 + blur 节点
的性能（`UI_REVIEW_M11.md` §8 已警示）待设备验证；若卡顿，利用已有 `lineTops` 几何缓存把 scale/blur
限定在活跃行 ±N 行的可见窗口内（该优化纯表达式逻辑，可后补）。

### M11.6d 全屏路由转场（轻量子集，先于 Navigation 落地）

**目标**：`MainShell` 的路由 if/else 分支切换获得方向感知的垂直滑动转场；Navigation 整体迁移
（M10.4，镜像阻塞）不做，但其时长/曲线参数提前固化进 MotionSpec，届时只换挂接机制不换参数。

> 与 `UI_REVIEW_M11.md` §7 M11.6 原文「路由转场建议并入 M10.4 Navigation 落地后」的差异说明：
> 原建议针对的是完整 NavHost 转场体系（含主 tab 转场、抽屉模式、coherent feedback 二选一模式）。
> 本计划只做**透明详情页的垂直滑动**这一个子集——它价值最高（NowPlaying/歌单详情是高频路径）、
> 实现机制（if/else + `transition`）与 Navigation 迁移正交、且 MotionSpec 参数可整体平移。主 tab
> 转场（Android 70+330ms）明确**不做**：`MainShell` 的 tab 分支切换当前销毁重建页面（M11.3 已登记
> 状态丢失债），给销毁重建加转场只会掩盖问题并多付一层动画成本，必须等 M11.3 状态保持落地后再议。

1. `RouteStack.ets`（纯逻辑）增加方向信号：`pushRoute/popRoute` 记录 lastOp（push/pop/reset），
   经 `Router` 暴露 `Router.lastDirection()`；补 `RouteStack.test.ets` 用例（push 后为 forward、
   pop 后为 back、reset 归 none）。
2. `MainShell` 每个全屏路由分支包一层容器挂 `.transition(TransitionEffect.asymmetric(...))`：
   - push（进详情）：从底部滑入 220ms + fade（`DETAIL_OPEN_MS`，FastOutSlowIn）；
   - pop（返回）：滑向底部 240ms（`DETAIL_CLOSE_MS`）；
   - `NOW_PLAYING` 单独用整高滑入 300ms / 滑出 250ms + 150ms fade（对齐 Android NowPlaying 层）。
   自定义组件不能直接链 `.transition`，需容器包裹——机械改动，逐分支执行。
3. 出场转场期间旧页组件的 `aboutToDisappear` 清理逻辑（计时器/监听器）不受转场延后影响的前提
   是「卸载即回调、转场只是视觉残留」——该时序**待设备验证**（风险登记 §7 R5）。

**验收**：构建 + RouteStack 方向单测 + 17 页返回栈行为不回归（设备复跑时逐页 back 键验证，沿用
M9.3 的 `keyEvent Back` 逐页退出法）。

### M11.6e 组件级动画收尾（MiniPlayer 优先，WaveformSlider 与 M11.3 合并执行）

> **状态：MiniPlayer 两项已实施（2026-08-28，构建+单测已过，手感未上设备）；WaveformSlider 三项仍归 M11.3。**
> 实施补充：①显隐同样带首帧布防——冷启动恢复歌曲时不播入场动画（Android AnimatedVisibility
> 初始为 true 不动画，ArkUI transition 首次挂载会播）。②两段式切歌时序为「两段动画全部完成后」
> （对齐 `NeriMiniPlayer.kt:115-128` 的 coroutine 末尾 onComplete，本计划原文「第一段后」有误已更正）；
> `releaseGeneration` 代际守卫防中断动画的 onFinish 串扰。③原文「未达阈值取消回弹 160ms」保持。

1. **MiniPlayer 显隐**：`MainShell.ets:85-87` 的 `if` 分支挂 `.transition`——enter 滑入 220ms +
   fade 180ms，exit 滑出 180ms + fade 120ms（对齐 `NeriApp.kt:3641-3656`）。
2. **MiniPlayer 滑动释放两段式对齐**：现状是达阈值立即切歌 + 单段 180ms 回弹；改为 Android 语义——
   达阈值后先 120ms 冲向 ±52vp，再 180ms 回 0，**两段动画全部完成后**切歌；未达阈值取消回弹 160ms
   （`NeriMiniPlayer.kt:115-128,151-159`）。`animateTo` 的 `onFinish` 回调即可编排，无需 keyframe。
3. **WaveformSlider**：振幅播放/暂停 500ms 线性渐变 + `displaySync` 替代 50ms `setInterval` +
   播放态门控。门控项已在 M11.3 看板登记，为避免双登记，**建议把 WaveformSlider 三项整体挪入 M11.3
   一次做完**（displaySync 句柄需在 `aboutToDisappear` 释放，与 M11.3 的低功耗目标同向）；
   M11.6e 只保留 MiniPlayer 两项。
4. QueueSheet / 睡眠面板 / 歌词分享面板的显隐动画**不做**——M11.4 将把它们迁移到 `bindSheet`/
   `CustomDialog`，系统自带转场，手写动画会白做（§5 交叉边界）。

**验收**：构建 + 单测基线；两段回弹的手感（120/180ms 与切歌时序）待设备验证。

---

## 5. 与既有里程碑的边界（防重复登记 / 防互相踩踏）

| 相邻任务 | 边界约定 |
| --- | --- |
| M11.3 列表与状态性能 | WaveformSlider 定时器门控（看板已登记）**归 M11.3**；本计划建议连 displaySync 升级与振幅渐变一并挪入 M11.3。歌词行动画若实测卡顿，可见窗口裁剪依赖 M11.3 的 LazyForEach 落地，届时联动 |
| M11.4 平台控件归位 | 底部面板（QueueSheet 等 5 处）的**显隐动画归 M11.4 的 bindSheet 迁移**（系统转场免费），本计划不手写；`stateStyles` 按压反馈亦归 M11.4 |
| M10.4 Navigation（M9.3a 镜像阻塞） | 完整路由转场体系（主 tab 转场、抽屉 fade、coherent feedback 模式、≥600vp 分栏）归 M10.4；M11.6d 只做透明详情页垂直滑动子集，MotionSpec 参数届时平移复用 |
| M8.4 已有的背景 crossfade | 保持不动（机制不同但意图已覆盖）；换歌时背景与全局主题色过渡（M11.6a 的种子动画）叠加后的观感需设备复核 |
| M10.3 低功耗 | displaySync 逐帧回调（R1 研究项）必须播放态门控 + 暂停即停，方向与低功耗规则一致 |

---

## 6. 可选项与研究项（明确不在本次范围，防 scope creep）

- **R1 歌词逐字渐变填充 + 96ms 时间平滑**（Android `multilineGradientReveal` / `rememberSmoothedLyricTimeMs`）：
  需要 Canvas 文本自绘或逐字几何裁剪 + displaySync 外推；先设备评估现有 500ms 三态高亮观感，再决定立项。
- **歌词 3D 翻转（±9°/260ms）**：性能未验证，且与滚动方向感耦合，M11.3 后评估。
- **歌词模式顶部小封面**（解锁 geometryTransition 共享元素的前提）：产品决策项。
- **`np.lyric_blur` 布尔 → amount 滑条（0–8）**：Android 有 `lyric_blur_amount`，本移植布尔已接线；
  升级属设置项扩充，非动画缺口。
- **`coherent_feedback_enabled` 导航模式开关**：依赖 M10.4。
- **主 tab 切换转场（70+330ms）**：依赖 M11.3 的 tab 状态保持。
- **队列行拖拽缩放（180ms）**：本移植队列尚无拖拽排序功能，无动画可挂。

---

## 7. 风险与未验证项（如实登记）

- **R1 · AppStorage-in-animateTo 捕获**（M11.6a 核心）：`.d.ts` 层无法证明；探针失败则按 §4 回退方案
  降级为顶层表面属性动画，并在本文档与 FEATURE_MATRIX 登记「主题色过渡为部分能力」。
- **R2 · 长歌词动画开销**：无 LazyForEach 时 60+ 行同时挂 scale/opacity/blur 属性动画的性能未实测
  （`UI_REVIEW_M11.md` §8 对 blur 已有同类警示）；缓解手段为 lineTops 可见窗口裁剪。
- **R3 · `fontWeight`/`fontSize` 属性动画支持面**：fontSize/fontColor 属性动画可用性较高，fontWeight
  可能瞬跳——不列为验收项，设备复跑时观察。
- **R4 · springMotion response 初值**：Android StiffnessLow 到 ArkUI response 无解析换算，0.55 为
  估计初值，标注「待设备调优」。
- **R5 · 出场转场与页面清理时序**：`aboutToDisappear` 释放的计时器/监听器在转场残留帧内是否已被回收
  待设备验证；若有问题，转场期间冻结旧页交互（`.hitTestBehavior(HitTestMode.None)`）是兜底。
- **R6 · 边缘渐隐遮罩配色**：歌词区叠于模糊背景上，无纯色背景可对齐，遮罩观感需设备调。
- **设备验证整体阻塞**：签名口令缺失（同 `UI_REVIEW_M11.md` §8），本计划全部子任务在设备侧只能标记
  「未验证」；恢复后按 §8 清单并入 UI_REVIEW_M11 §9 一次复跑。

## 8. 设备复跑清单（签名恢复后，并入 `UI_REVIEW_M11.md` §9）

1. 【探针】设置页切深色/浅色：全局背景/卡片/Tab 栏 420ms 渐变，无撕裂、无瞬切残影（M11.6a）。
2. 换歌（不同封面色）：全局配色随种子 420ms 过渡，NowPlaying 背景与全局过渡叠加观感正常（M11.6a）。
3. 播放页点「歌词」按钮：内容区 300ms fade，无闪白（M11.6b）。
4. 歌词播放中：活跃行迁移时缩放/透明度弹簧过渡、边缘渐隐可见、模糊随距离衰减（M11.6c）。
5. 首页 → 歌单详情 / 正在播放：push 底部滑入 220/300ms，返回键 pop 滑出 240/250ms，逐页 back
   17 页返回栈身份正确（M11.6d，沿用 M9.3 验证法）。
6. 首次播放出现 MiniPlayer：滑入+淡入；清空队列消失：滑出+淡出（M11.6e）。
7. MiniPlayer 横滑达阈值：先弹向 ±52vp 再回弹，切歌发生在第一段动画后（M11.6e）。
8. 暂停状态停留播放页 60s：无逐帧动画空转（displaySync 门控，若已随 M11.3 落地）。
