# ch → dev 合并记录（2026-08-29）

本文记录 `ch` 分支合并进 `dev` 的全过程：为什么不能机械合并、每个冲突怎么定的、
保留和丢弃了什么、验证到什么程度、以及怎么回滚。定位问题时先读 §5 的文件级清单，
回滚看 §2。

## 1. 结论与范围

`ch` 的 8 个提交（M11 视图层 + M11.6a-e 动效专项）合并进 `dev`。合并策略：
**dev 架构为准，只吸收 ch 中与 dev 架构不冲突的功能与动效**。

净结果相对 `dev`：**15 个文件，+694 / −43**。

按要求，**文档不合并，全部保留 dev 版**：11 个 `.md`、`NeriPlayer-ASCF/`（123 个文件）、
`.mcp.json` 与 dev 逐字节相同（本文件是新增的合并记录，不属于被合并的文档）。

## 2. 锚点与回滚

| 名称 | commit | 说明 |
| --- | --- | --- |
| 合并基点 | `13d2e01` | `merge-base(dev, ch)`，两分支的共同祖先 |
| dev 顶点 | `4af4737` | 合并前的 dev，tag `merge-safety/dev-tip` |
| ch 顶点 | `ea4e966` | 被合并的 ch，tag `merge-safety/ch-tip` |

回滚手段，从轻到重：

```bash
# a) 合并尚未提交时，整体放弃
git merge --abort

# b) 合并已提交，整体退回合并前的 dev
git reset --hard merge-safety/dev-tip

# c) 只回滚单个文件到合并前的 dev 版
git checkout merge-safety/dev-tip -- <path>

# d) 查看某文件在 ch 里原本的样子（对照移植是否走样）
git show merge-safety/ch-tip:<path>

# e) 合并已推送，用反向提交撤销（保留历史）
git revert -m 1 <合并提交>
```

`ch` 分支本身未被改动，本地与 `origin/ch` 都还在，随时可重新合并。

## 3. 为什么不能机械合并：三处互斥重写

`dev` 和 `ch` 从 `13d2e01` 各走了 8 个提交，在三个子系统上做了**互不兼容的重写**。
直接 `git merge` 的结果能通过文本合并，但**编译不过、且会静默回退 dev 的成果**。

### 3.1 路由

| | 实现 |
| --- | --- |
| dev | ArkUI `Navigation` / `NavDestination`，`RouteStack.ets` 导出 `RoutePushAction` + `routePushAction()` |
| ch | 手写 AppStorage 路由栈：`RouteEntry` / `pushRoute` / `popRoute` / `parseRouteStack` / `serializeRouteStack` / `routeTop`，M11.6d 的转场建在其上 |

自动合并把 ch 的 `directionForRouteChange()` 塞进了 `RouteStack.ets`，而它引用的
`RouteEntry` 和 `routeTop()` 已被 dev 删除 —— **这是编译不过的直接原因**。

### 3.2 歌词视图

| | 实现 | 时间 |
| --- | --- | --- |
| dev | PR #12：居中滚动 + 拖动预览（`scrubIndex` / `updateScrubFromOffset` / `revertToPlaying`）、逐行测高、卡拉 OK 逐字 | 2026-08-28 12:10 |
| ch | 较简单的跟随（`activeIndex` / `lineTops` / `scrollToActive`），但带**距离模糊/缩放/透明度**与 MotionSpec spring | 2026-08-26 03:47 |

两边是同一组件的独立重写，功能互补但实现互斥。dev 更新且更完整，ch 的视觉层是 dev 缺的。

### 3.3 主题重绘机制（最容易漏，影响最大）

同一个 bug（改深浅色后组件不重绘），两边的修法不同：

| | `Theme.isDark()` 静态调用 | `@StorageProp('theme.isDark')` 订阅 | 发布 `theme.isDark` |
| --- | --- | --- | --- |
| base `13d2e01` | 439 | 0 | 无 |
| dev `4af4737` | **501** | 0 | **从不** |
| ch `ea4e966` | 4 | **40** | 有（`refreshIsDark`） |

- dev：靠 `AppColorMode.apply()` → `setColorMode()` 触发配置变更、**重建整棵组件树**，
  静态调用自然拿到新值。附带好处是系统弹窗与 `sys.color.*` 资源一起跟随。
- ch：把 25 个文件从静态调用改成可观察订阅，由 `Theme.refreshIsDark()` 发布来驱动重绘。

自动合并悄悄把 ch 的重构吃进了 13 个文件，形成**订阅者是 ch 的、发布者是 dev 的混合体**。
若冲突按 dev 解，唯一残存的发布点是 `EntryAbility.ets:119`（只在**系统**深浅色翻转时触发），
冷启动和设置页切换都不发布 → 那 25 个组件的 `isDark` 恒为默认 `false`，**深色模式在 25 个组件上坏掉**。

因此主题机制**必须整体二选一**，不能拆。

## 4. 决策记录

| 子系统 | 决策 | 理由 |
| --- | --- | --- |
| 路由 | 全取 dev（`Navigation`） | dev 为主线；ch 的手写栈与之互斥 |
| 歌词 | dev 做底座 + 移植 ch 视觉层 | dev 更新更全；ch 的距离模糊/缩放是 dev 缺的，且能接上 dev 的死开关 |
| 设置 | 全取 dev | 量化后 ch 在设置页**没有**新增贡献（见 §5 的度量口径） |
| 主题机制 | **全面回到 dev 静态机制** | 见下 |
| 动效基建 | 全取 ch（`MotionSpec` / `MotionCurves` + 5 单测） | 纯新增，无架构耦合 |
| MiniPlayer | 取 ch 两段式滑动释放 | 纯新增 |
| 文档 | 全取 dev | 需求指定 |

### 4.1 主题机制为何选 dev（推翻了一次初步意向）

初步意向是保留 ch 的 `refreshIsDarkAnimated`（420ms 主题过渡）。深入后发现它不成立：

**`setColorMode` 的重建会吃掉这个动画。** 配置变更会销毁旧节点、按新值重建，
正在跑的属性动画随节点一起消失。而 `refreshIsDarkAnimated` 的两个调用点
（设置页切换、系统深浅色翻转）**恰好都会触发重建**。所以只要 dev 的 `setColorMode` 还在，
这个 420ms 动画在两条路径上都跑不起来。

反向（砍掉 `setColorMode` 保动画）则丢掉 dev 明确修好的系统弹窗 / `sys.color.*` / 首帧跟随，
覆盖面严格更窄。

补充证据：ch 自己在 `Theme.ets` 的注释里就承认这个动画从未被验证过 ——
*"whether AppStorage writes made inside an animateTo closure animate the subscriber
repaints could not be proven statically; if the probe fails, the fallback is a scoped
.animation()"*。它给自己留的降级方案，就是 §10 的待办项。

**注意**：「重建打断动画」这条是静态推理，未上机验证。

## 5. 文件级处理清单

冲突共 17 个文件，另有 20 个文件被 git 自动合并。判断"取 dev 会不会丢掉 ch 的东西"用的度量是：
**`git diff 13d2e01 MERGE_HEAD -- <file>` 中剔除含 `isDark` 的行后的改动量**，
即 ch 在该文件里真正**新增**了什么（不含它对主题机制的机械改写）。该值为 0 ⇒ 取 dev 零损失。

### 5.1 全取 dev（12 个冲突文件）

`EntryAbility.ets` `pages/Index.ets` `view/Router.ets` `test/ets/test/RouteStack.test.ets`
`SettingsPage.ets` `SettingsDetailPage.ets` `OnboardingPage.ets` `NeteasePlaylistPage.ets`
`LibraryPage.ets` `HomePage.ets` `BiliFavPage.ets` `MainShell.ets`

补充说明：

- `EntryAbility` / `Index`：ch 的 `systemDark` 冷启动播种修复 **dev 已独立做过**，只是注释不同；
  其余是主题机制，丢弃。
- `SettingsDetailPage`：ch 度量为 0。那段 `-250ms/+250ms/重置` 按钮是**从 base 继承**的，
  dev 主动换成了规范化的 `OptionRow` 选择器（它的"选项控件规范化"），ch 只是留着没动。
- `RouteStack.test.ets`：ch 新增的是 `directionForRouteChange` 的单测，随该函数一起丢弃。

### 5.2 dev 底座 + 贴回 ch 功能（4 个冲突文件）

| 文件 | 贴回的 ch 内容 |
| --- | --- |
| `PlaylistDetailPage.ets` | 删除歌单二次确认弹窗（`showDeleteConfirm` / `deleteWarning()`）。原来第一下点击就删且不可撤销 |
| `ExplorePage.ets` | 搜索失败加「重新搜索」；搜索卡片 `focusControl.requestFocus` 真的聚焦输入框；歌单搜索改诚实文案 + toast |
| `NowPlayingPage.ets` | `np.show_lyrics` 改持久化 `@StorageProp`；分享选行走 `LyricIndexResolver` 并计入 `np.lyric_offset_ms`；封面↔歌词 300ms fade（`contentTransition()` + 首帧布防）；切换按钮 `accessibilityText` |
| `LyricView.ets` | 距离模糊 / 缩放 / 透明度 ramp（`MotionSpec` 曲线）+ 接上 `np.lyric_blur` 死开关 |

`NowPlayingPage` 第三个冲突是**两边合并**：dev 的 `onScrubLine` 拖动预览包进 ch 的 fade 容器。

> ⚠ **本行已被第二轮推翻，见 §11.2。** `NowPlayingPage` 里除"分享选行计入歌词偏移"以外的
> 三项（`np.show_lyrics` 持久化、300ms fade、切换按钮 `accessibilityText`）在整合
> PR #13 时被其横向 Swiper 分页取代并已移除。

### 5.3 自动合并后回退主题机制（13 个文件）

整文件回退到 dev（ch 的改动只有主题机制，无其他贡献）：

`FloatingLyricBar.ets` `LyricShareSheet.ets` `QrLoginPanel.ets` `DebugPage.ets`
`ListenTogetherPage.ets` `RecentPage.ets` `SafeModePage.ets` `StatsPage.ets` `Theme.ets`

回退主题机制但**保留** ch 的功能修复（逐处手工重贴）：

| 文件 | 保留的内容 |
| --- | --- |
| `MiniPlayer.ets` | 两段式滑动释放 `animateSwipeRelease` / `animateSwipeReturn` + `releaseGeneration` 代际守卫 |
| `Ui.ets` | M9.3 角标定位：百分比 `.position()` → `Alignment.TopEnd` + 固定 margin |
| `DownloadsPage.ets` | 同上 M9.3 角标定位（并给 Stack 补 50×50 显式尺寸） |
| `SongRow.ets` | 「加入歌单」「分享」标注「暂不可用」并给 toast，替代静默关菜单 |

`Theme.ets` 回退意味着删除 `IS_DARK_KEY` / `refreshIsDark()` / `refreshIsDarkAnimated()`。

### 5.4 其他

| 文件 | 处理 |
| --- | --- |
| `RouteStack.ets` | **剥掉**自动合并进来的 `directionForRouteChange()` + `RouteDirection`（悬空引用 `RouteEntry` / `routeTop`）。结果与 dev 完全一致，故不出现在最终 diff 中 |
| `List.test.ets` | **并集**：dev 的 `lyricScrollMathTest` / `shareLinksTest` / `albumSongsTest` + ch 的 `motionSpecTest`（`lyricIndexResolverTest` 已由自动合并带入） |
| `CoverArtColorCache.ets` | 取 ch：封面取色发布包进 420ms `animateTo`（带 try/catch 兜底） |
| `MotionSpec.ets` / `MotionCurves.ets` / `LyricIndexResolver.ets` + 2 个单测 | 取 ch，纯新增 |

## 6. 保留的 ch 内容清单

功能与安全修复：

- 删除歌单二次确认（不可撤销操作）
- 搜索失败可重试；搜索卡片可聚焦；歌单搜索诚实文案
- `np.show_lyrics` 持久化（原为本地 `@State`，每次进页面重置，而该设置项无人读取）
  —— **第二轮已被 PR #13 的横向分页取代并移除，见 §11.2**
- 分享选行计入歌词偏移（原来忽略偏移，配了偏移就选错行）
- M9.3 角标定位（系统字号放大后角标会漂出封面）
- 「加入歌单」「分享」诚实标注未移植

动效：

- `MotionSpec` / `MotionCurves` 动效参数层（Android 基准锁定，5 个单测）
- 歌词行距离模糊 / 缩放 / 透明度 + spring
- 封面↔歌词 300ms fade —— **第二轮已被 PR #13 取代并移除，见 §11.2**
- MiniPlayer 两段式滑动释放
- 封面取色 420ms 过渡

`np.lyric_blur` 开关自此**首次真正生效**：dev 有键（默认 `true`）、有 UI
（`SettingsDetailPage.ets:881`），但 `view/components/` 里零消费者。

## 7. 丢弃的 ch 内容及原因

| 内容 | 原因 |
| --- | --- |
| 手写路由栈（`RouteEntry` / `pushRoute` / `popRoute` / `parseRouteStack` / `serializeRouteStack` / `routeTop`）与 `Router.KEY_STACK` / `KEY_DIRECTION` | 与 dev 的 `Navigation` 互斥 |
| M11.6d 全屏路由转场 + `directionForRouteChange` 及其单测 | 建在上述手写栈上；改用 `NavDestination` 重写的方案见 §10 |
| 25 个文件的 `@StorageProp('theme.isDark')` 重构 + `IS_DARK_KEY` / `refreshIsDark` / `refreshIsDarkAnimated` | 见 §4.1 |
| ch 版 `LyricView` 的滚动实现（`scrollToActive` / `lineTops` / `userScrollUntilMs`） | dev 的居中 + 拖动预览更新更全；只移植了视觉层 |
| ch 对 `NeriPlayer-ASCF/` 的删除（123 个文件） | 文档/参考工程保留 dev |
| ch 的文档改动（11 个 `.md`）与 `.mcp.json` | 需求指定保留 dev |

## 8. 移植期间修正的缺陷

**ch 的距离曲线调用点符号错误。** ch 传的是带符号的 `index - activeIndex`，而
`MotionSpec` 把 `distance <= 0` 视为"这就是当前行"（`lyricScaleForDistance` 返回
`LYRIC_ACTIVE_SCALE`，`lyricAlphaForDistance` 返回 `1.0`）。结果当前行**上方**所有歌词
都拿到 1.1 缩放和全不透明。ch 自己的 blur 用了 `Math.abs()`，scale / opacity 没用 ——
内部不自洽。移植时统一为 `Math.abs()` 并加注释说明。

`MotionSpec.test.ets` 只断言纯函数，抓不到调用点的符号错误。

**歌词行动画曲线统一。** dev 原本在 `Text` 上是 `.animation({ duration: 250, curve: Curve.EaseOut })`，
与新增 ramp 的 spring 是两条曲线，会出现"文字长完了而行还在回弹"。改为共用
`MotionCurves.lyricRowSpring()`，与 Android 把字号/颜色/缩放/透明度/模糊作为一次运动一致。

## 9. 验证情况

### 9.1 静态验证（全部通过）

- **跨文件 import/export 解析**：自写脚本作为编译近似，逐个校验命名导入是否真的能在目标文件
  找到导出 —— 正是抓出 `RouteStack.ets` 悬空引用的手段。
  纯净 dev 基线 **0 问题**，合并结果 **0 问题**（319 → 324 个文件，+5 为 ch 新模块）。
- **删除符号零残留**：`directionForRouteChange` `RouteDirection` `RouteEntry` `pushRoute`
  `popRoute` `parseRouteStack` `serializeRouteStack` `routeTop` `IS_DARK_KEY` `refreshIsDark`
  `refreshIsDarkAnimated` `KEY_STACK` `KEY_DIRECTION` 全仓无引用。
- **主题机制统一**：全仓 `@StorageProp('theme.isDark')` 计数为 0。
- 冲突标记零残留；改动文件花括号平衡；`git diff --check` 通过（该门禁曾在
  `c2a1629` 因行尾空白挂过 CI）。
- 文档 / `NeriPlayer-ASCF/` / `.mcp.json` 与 dev 逐字节相同。

### 9.2 构建与单测

本机工具链：`E:\DevEco Studio`（**6.1.1.300**，自带 SDK 与 node）。
注意 `AGENTS.md` 中"26.0.0 Beta2 的 hvigor 无法构建 6.1.1(24) 工程"的告警**不适用于此版本**。

```bash
export DEVECO_SDK_HOME="E:\DevEco Studio\sdk"
export NODE_HOME="E:\DevEco Studio\tools\node"
"/e/DevEco Studio/tools/ohpm/bin/ohpm.bat" install --all
"/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --mode module \
  -p module=entry@default -p product=default -p buildMode=debug --no-daemon
"/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" test --mode module \
  -p product=default -p buildMode=debug --no-daemon
```

构建与单测结果见 §9.3。**设备未验证** —— 本轮所有动效（歌词 ramp、fade、滑动释放、
封面取色过渡）都只做到编译级，观感与时序未上机确认。

### 9.3 本轮实测结果（2026-08-29，DevEco 6.1.1.300）

**构建：`BUILD SUCCESSFUL in 52 s`，0 error。**
16 条 `ArkTS:WARN` 全部落在 `SettingsDetailPage.ets`（"Function may throw exceptions"），
该文件本次 100% 取自 dev、不在最终 diff 中，故这些告警是既有的，**本次改动零新增告警**。

**单测：全部通过（0 `ERROR` / 0 `AssertException`）。**
测试确实执行了（而非仅编译）——覆盖率报告覆盖 177 个文件、18742 行中 11246 行被执行（60%）。
本次保留的 ch 逻辑覆盖情况：

| 文件 | 行覆盖 |
| --- | --- |
| `MotionSpec.ets` | **32/32（100%）** |
| `LyricIndexResolver.ets` | **15/15（100%）** |
| `RouteStack.ets` | **8/8（100%）** —— 说明 §5.4 的剥离没留下不一致 |
| `MotionCurves.ets` | 0/5 —— 它包装 `curves.*`，hypium 无 ArkUI 运行时，设计上不可测 |
| `CoverArtColorCache.ets` | 0/86 —— 无单测，既有状况 |
| `LyricView.ets` / `MiniPlayer.ets` | 未进报告 —— `@Component` UI 结构不被插桩 |

### 9.4 ⚠ 重要：`hvigorw test` 的退出码不能作为单测门禁

做负对照时发现的坑，**与本次合并无关但会误导后续所有人**：

把 `MotionSpec.test.ets` 里 `assertEqual(420)` 故意改成 `assertEqual(99999)` 后重跑：

- 日志出现 `ERROR: Error in transition durations match the Android reference, expect 420 equals 99999`
  以及 `AssertException` 栈；
- 但 hvigor 仍然打印 **`BUILD SUCCESSFUL`**，**退出码仍然是 `0`**。

**结论：`hvigorw test` 的退出码恒为 0，判定单测是否通过必须 grep 日志里的 `ERROR:` /
`AssertException`，不能看退出码。** 本文 §9.3 的"全部通过"就是按这个口径判定的
（负对照已还原，`assertEqual(420)` 完好）。

推荐口径：

```bash
"/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" test --mode module \
  -p product=default -p buildMode=debug --no-daemon 2>&1 | tee /tmp/ut.log
grep -c 'AssertException' /tmp/ut.log   # 必须为 0
```

**这直接影响 CI**：`.github/workflows/harmonyos-ci.yml:123-128` 正是用
`timeout ... hvigorw test ...` 的退出码作为信号（`exit "$code"`），而第 140 行还把单测标注为
"诊断性，不阻塞构建"。也就是说**当前 CI 不可能捕获任何单测失败**。历史提交信息里的
"单测 833/833" 应按此重新审视。建议后续把 CI 该步改成 grep `AssertException` 计数。

## 10. 后续待办

1. **M11.6d 路由转场（未做）。** 目标是 push 底部滑入 220ms / pop 顶部滑出 240ms。
   查证结论（API 24 可用性已确认）：
   - `customNavContentTransition`（API 11+）需要按 `navDestinationId` 建回调注册表，且**每页要有自己的
     `@State`**。dev 现在是**单个共享 `@Builder`** 给 11 条路由产出同一个 `NavDestination`，
     动画状态全在 `MainShell` 上 —— 这种形状下**无法**让进/出两页独立动画，必须先把
     每条路由拆成自带 `@State` 的 `@Component`。
   - 更简单的选择是 `NavDestination.customTransition`（**API 15+**，本工程 API 24 可用）：
     按目标页声明，`duration` / `curve` 是一等字段，无需注册表和 `finishTransition()`。
   - **额外限制**：dev 的 Tab 骨架是 `Navigation` 的**内容区（NavBar）**，其 `NavContentInfo`
     的 `index === -1` 且无 `navDestinationId`，官方示例对这种情况一律 `return undefined`。
     也就是说「Tab 骨架 ↔ 详情页」这条最显眼的转场**无法被自定义**，除非把首页也压入路由栈。
   综上：这项需要动我们本次刻意保持不变的路由层，建议**单独提交/PR**，不要混进本次合并。
2. **420ms 主题过渡（未做）。** 按 ch 自己写的降级方案，在顶层 surface 上加作用域内的
   `.animation({ duration: MotionSpec.THEME_COLOR_TRANSITION_MS, curve: MotionCurves.fastOutSlowIn() })`，
   消费已保留的 `MotionSpec.THEME_COLOR_TRANSITION_MS`。需能上机验证时再做。
3. **上设备验证本轮动效**，并按 `AGENTS.md` §"构建与验证"补 `entry/src/ohosTest/` 用例。
4. `SettingsDetailPage` 中 `adjustLyricOffset()` 是否随 `-250ms/+250ms` 按钮下线而成为死代码，
   由 dev 侧自行决定清理。
5. **修 CI 单测门禁（与本次合并无关，但优先级高）。** 见 §9.4：
   `.github/workflows/harmonyos-ci.yml:123-128` 用退出码判定单测，而该退出码恒为 0，
   当前 CI 无法捕获任何单测失败。改为统计日志里的 `AssertException` 条数。
6. **更新 `AGENTS.md` 的工具链章节。** 现文档只记录 `D:\HarmonyOS\Tools\`（本机不存在），
   并称"构建必须用 command-line-tools 的 hvigorw"。实测 `E:\DevEco Studio`（6.1.1.300）
   自带的 hvigorw **可以**构建本工程（该告警只针对 26.0.0 Beta2）。建议补记本机路径与
   §9.2 的环境变量写法。

## 11. 第二轮：整合 origin/dev 的 PR #13

推送第一个合并提交（`a78e488`）时被拒：`origin/dev` 已前进到 `b23a1c7`
（PR #13 `feat/nowplaying-ux-rework`，"匹配歌曲信息、菜单锚点箭头联动、点歌进播放页、
底部标准图标与歌词页横向分页"）。**未强推**，改为把 `origin/dev` 合并进来。

新增锚点：

| 名称 | commit | 说明 |
| --- | --- | --- |
| 第一轮合并 | `a78e488` | tag `merge-safety/my-merge` |
| PR #13 落地后的 origin/dev | `b23a1c7` | tag `merge-safety/origin-dev-pr13` |

PR #13 与本次合并重叠 8 个文件，但只冲突 2 个，其余自动合并，且**歌词视觉层 graft 完好**
（PR #13 对 `LyricView.ets` 只有 +18/−6，`activeIndex()` / `onRowMeasured` / `handleLineTap` /
`scrubIndex` / `FOLLOW_SPRING` 等 graft 锚点全部保留）。

### 11.1 `List.test.ets`

并集：保留 `motionSpecTest()` 与 PR #13 的 `qqMusicLyricCodecTest()`。

### 11.2 `NowPlayingPage.ets`：PR #13 取代 ch 的封面↔歌词模型

PR #13 把「`showLyrics` 布尔切换 + 300ms fade」整体换成了**横向 Swiper 分页**
（`pageIndex` / `lyricsMode` / `paneSwiper`），并在注释里明确写了"取代旧的
`showLyrics=true` 一进页面就是歌词"。四个冲突块中 git 的边界与 PR #13 的重构错位
（它同时删掉了含「歌词」切换按钮的整行控件），逐块手工对齐风险高，因此**整文件取
`origin/dev` 版**，再只贴回 PR #13 未取代的那一项。

因此**被 PR #13 取代、本轮主动放弃**的 ch 内容：

- `np.show_lyrics` 持久化（已无切换按钮，分页状态由 Swiper 承载）
- 封面↔歌词 300ms fade（`contentTransition()` / `contentTransitionArmed`）与其首帧布防
- 切换按钮的 `accessibilityText`（按钮已不存在）
- 该文件里的 `MotionSpec` 引用（只服务于上面的 fade）

**保留并重新贴回**的一项：

- `currentLyricIndex()` 改走 `LyricIndexResolver.resolve(lyrics, positionMs + lyricOffsetMs, -1)`，
  并补回 `@StorageProp('np.lyric_offset_ms')`。`origin/dev` 那版仍是忽略偏移的内联扫描
  （`this.lyrics[i].timeMs <= this.positionMs`），配了歌词偏移后分享卡片会选错行 ——
  这个缺陷 PR #13 没修，仍然需要 ch 的修复。

`SongInfoSheet.ets` 随 PR #13 删除（改为 `MatchSongInfoSheet.ets`），本轮已确认全仓无残留引用。

### 11.3 第二轮验证

见 §11.4。口径与 §9 相同（单测必须 grep `AssertException`，不看退出码）。

### 11.4 第二轮实测结果（2026-08-29，DevEco 6.1.1.300）

- `assembleHap`：**`BUILD SUCCESSFUL in 53 s`，0 `ERROR`**
- 单测：**0 `AssertException`、0 `ERROR`** → 全部通过（退出码 0 不作为判据，见 §9.4）
- 跨文件 import/export 解析：**328 个文件、0 问题**
- 冲突标记零残留；`SongInfoSheet` 删除后全仓无残留引用

设备仍未验证：歌词行距离 ramp、MiniPlayer 滑动释放、封面取色过渡的观感与时序未上机确认；
PR #13 的横向分页也在同一条船上。
