# ONETAKE（一镜到底）集成计划 —— @hmanimations/ezcustomtransition

> 建立日期：2026-09-27。基线：`dev` @ `9b550c4`（分支 `onetake-integration-plan`）。
> 目标：将新接入的一镜到底转场技能（三方库 `@hmanimations/ezcustomtransition`，ohpm 1.3.0，Apache-2.0）落实到 NeriPlayer-HarmonyOS，替换现有 `bindContentCover` 模态 + 自绘分阶段动画的播放页呈现方案。
> 本文档为执行计划，不含实现代码；所有现状结论均经源码核实（文件:行号），真机相关项一律标注「待真机验证」。

## 1 执行守则

1.1 每个里程碑独立成 commit（可多个），完成即提交推送，不攒批；PR 以 merge 方式汇入 `dev`，保留细分历史。

1.2 主线改动至少通过 `hvigorw assembleHap`（debug）+ codelinter（改动文件 0 error）；纯逻辑改动补 `entry/src/test/` 用例。本机单测只能编译级验证（Linux 缺 HMS Previewer，执行阶段挂死），真实用例结果交 Windows 工作站。

1.3 播放引擎（AVPlayer/AVSession/后台播放）与本计划完全解耦：只动呈现层与路由层，播放、队列、歌词分发逻辑不动。

1.4 涉及 UI 形态、手势、深浅色切换、宽屏断点的结论，未经真机验证一律写「待真机验证」，不得在 FEATURE_MATRIX 提升状态。

## 2 现状基线（已核实）

### 2.1 路由体系

- 根容器：`HdsNavigation`（UIDesign Kit 壳），`view/pages/MainShell.ets:503`；`.mode(NavigationMode.Stack)`（636）、`.navDestination(this.pageMap)`（637）。
- 栈共享：`MainShell.ets:53` `@Provide('NavPathStack') pageStack`，经 `Router.attach()`（`view/Router.ets:59-62`）交 Router 门面。
- 路由跳转：`Router.push()` → `stack.pushPathByName()`；页面注册走 navDestination builder，无 route_map.json。
- 转场回调能力：原生 `Navigation.customNavContentTransition` 见 SDK `navigation.d.ts:2613`；HdsNavigation 壳亦声明 `customNavContentTransition(delegate: CustomTransitionDelegate)`（`@hms.hds.hdsBaseComponent.d.ets:2464`，since 6.0.0(20)）。工程 API 26，满足。

### 2.2 播放页呈现（改造对象）

- **播放页不在路由栈上**：`MainShell.ets:658` `.bindContentCover(this.modalMounted, this.nowPlayingBuilder(), ...)` 全屏模态承载；开关是 AppStorage `'ui.nowPlayingShown'`（`Router.ets:47`，`Router.push(NOW_PLAYING)` 特殊分支只翻开关、return，不入栈，`Router.ets:63-67`）。
- 现有转场：单一进度 `panelAmount` 分阶段原生属性动画（`view/NowPlayingMotion.ets` 几何插值纯函数 + `view/NowPlayingCurves.ets` 曲线），miniBar 槽位交接经 dock 几何推导。`geometryTransition` 共享元素方案已删（历史 commit 908d9f2 系列打磨）。
- **历史包袱**：播放页内发起的子路由（专辑/一起听）必须先收模态再入栈，否则新页面渲染在模态之下不可见（`Router.ets:75-79` 注释）。
- 入口共 7 处 `Router.push(Router.NOW_PLAYING)`：`view/components/MiniPlayer.ets:326`（迷你条，主入口）、`view/pages/PlaylistDetailPage.ets:185`、`ExplorePage.ets:104`、`AlbumPage.ets:78`、`RecentPage.ets:77,86`、`BiliFavPage.ets:244`、`NeteasePlaylistPage.ets:191`。

### 2.3 Ability 层

- `entry/src/main/ets/entryability/EntryAbility.ets`：`onWindowStageCreate` 做沉浸式、系统栏、窗口度量后 `loadContent('pages/Index')`；`onConfigurationUpdate` 已存在（116 行，处理深色模式写 AppStorage）。
- `module.json5` **无 abilityStage 配置**（只有 abilities/extensionAbilities 的 srcEntry），无 AbilityStage 文件。

### 2.4 依赖与测试

- `oh-package.json5` 两级 dependencies 均为空；引入三方库为工程首个三方运行时依赖。
- 转场相关测试：`entry/src/test/.../RouteStack.test.ets`（路由 push 决策，**NOW_PLAYING 分支语义变化后必改**）、`NowPlayingMotion.test.ets`（动画几何纯函数，迁移后页面级用例需调整）。

### 2.5 分支漂移

`agreement-reconfirm` 相对 dev 有 5 个未合入提交，其中 3 个是 dock 落点/槽位交接打磨（076ca7a、a095933、b47d111），直接影响本计划改造的 miniBar 交接区域。**落地前先合入 dev（M0），避免在旧几何上做新转场。**

## 3 关键决策

| # | 决策 | 结论与理由 |
|---|------|-----------|
| D1 | 播放页从 `bindContentCover` 迁移为 **NavDestination 入栈** | 库的硬前提（目标页必须是 NavDestination）；顺带消除「播放页内子路由先收模态」的历史包袱，返回手势、生命周期走标准 Navigation 行为 |
| D2 | 一镜到底类型选 `CardLongTake` | 迷你条/卡片 → 全屏播放页是卡片展开形态；`ImageLongTake`（先缩放再退出）适用于封面看大图场景，当前无此场景，不引入 |
| D3 | 全局 `customNavContentTransition` 回调按参数过滤 | 回调对所有转场生效：仅当路由参数携带 `longTakeTransitionParam` 时交给库，否则返回 `undefined` 走系统默认转场，保证其他页面零影响 |
| D4 | 迁移期保留模态路径作为回退开关 | AppStorage 增 `'ui.nowPlayingAsRoute'`（默认 true 走路由；false 回退旧模态），真机验证通过一个里程碑周期后拆除（M5） |
| D5 | 播放页动态背景迁至子组件 + `expandSafeArea` | 库要求 NavDestination 背景在转场期由 `session.navDestinationBgColor` 管理；播放页封面主色/渐变/模糊背景整体迁到 ContentBuilder 根组件，NavDestination 只接 session 背景色 |
| D6 | 返回对齐目标 = miniBar 槽位 | 返回播放列表时经 `longTakeSession.updateSnapshotComponentId()` 对齐迷你条槽位矩形；槽位 id 需稳定（注意 HdsTabs miniBar 槽位切 Tab 会 remount，id 保持不变即可，触发时刻按当前挂载组件取） |

## 4 里程碑

### M0 前置对齐（分支操作，无代码）

- `agreement-reconfirm` 经 PR merge 进 `dev`（3 个 dock 落点提交必须先落地）；本分支 rebase 到新 dev。

### M1 Spike：HdsNavigation × ezcustomtransition 兼容性（真机，1 天）

目的：在动架构前验证最大风险（R1）。

- 新建 `spike/` 临时页：注册一个空 NavDestination，从 miniBar 点击经库全流程跳转（装依赖 → init → 回调 → generateLongTakeParam → 目标页 5 处）。
- 真机确认：HdsNavigation 壳下转场是否生效、有无布局错乱、返回手势是否正常。
- **通过** → 进 M2；**不通过** → 评估主容器换原生 Navigation 的代价，单独出决策文档，本计划挂起。
- spike 代码不进 dev，验证记录写 `docs/hm.md`。

### M2 播放页迁 NavDestination（P0 前置改造）

1. 注册 `now_playing` 为真实 NavDestination（pageMap 分支 + NowPlayingPage 改 NavDestination 结构，`hideTitleBar(true)`）。
2. `Router.push(NOW_PLAYING)` 从「翻 AppStorage 开关」改为真入栈（带 feature flag `ui.nowPlayingAsRoute` 分流：flag 关时走旧模态路径，旧代码暂留）。
3. 拆除「播放页内子路由先收模态」逻辑（`Router.ets:75-79` 分支在路由形态下天然不需要；flag 关时保留）。
4. 播放页根背景迁到子组件 + `expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP])`（D5，为 M3 做准备；迁移期间 NavDestination 背景用 `Color.Transparent` 保持现状观感）。
5. 更新 `RouteStack.test.ets`（NOW_PLAYING 入栈断言）+ 新增 flag 分流用例；播放引擎零改动（AGENTS.md §目录职责）。

验证：assembleHap + codelinter + Windows 单测；真机 smoke（模态路径回退可用、路由路径功能完整）。转场此阶段仍是系统默认，观感退步是预期内的中间态。

### M3 库正式接入（6 步集成）

按技能标准顺序：

1. `ohpm install @hmanimations/ezcustomtransition`（锁定 1.3.0；CI 跑一次确认 setup-ohos 可拉包）。
2. `EntryAbility.onWindowStageCreate` 加 `ezCustomTransition.init(windowStage)`。
3. 新建 AbilityStage（`module.json5` 配 srcEntry）`onConfigurationUpdate` 调 `ezCustomTransition.onConfigurationChanged()`；EntryAbility 既有深色处理保持（本次同步改 AppStorage 深色键的链路不受影响，待真机验证深浅切换时转场参数正确）。
4. `MainShell.ets` HdsNavigation 挂 `customNavContentTransition`（回调内过滤：param 无 `longTakeTransitionParam` 返回 undefined，D3）+ `.enabled(isEnabled)` 转场期禁交互。
5. 触发页：7 处入口统一收敛到一个封装函数（Router 层新增 `pushNowPlaying(param)`），函数内 `generateLongTakeParam(uiContext, 组件id, 圆角)`；触发组件补 `.id()`（miniBar 槽位、歌单卡片等）并核对 `.borderRadius()` 与参数一致。
6. 播放页 5 处修改：onReady 解析 param → `longTakeSession.init(navDestContext, param, { pop, alignTargetId: miniBar 槽位 id })`；`LongTakeTransitionDelegate` 包裹 ContentBuilder；NavDestination 背景接 `session.navDestinationBgColor`；`onSizeChange` 调 `setNewSize`（宽屏/旋转）。

验证：assembleHap + lint + Windows 单测；真机回归转场节奏、折返、返回对齐、深浅色切换、宽屏形态。

### M4 打磨与旧路径拆除

- 返回对齐：返回前列表若切歌/换槽位，调 `updateSnapshotComponentId`（D6）。
- 手势与曲线：`useSpringCurve` 真机对比评估；`isGestureEnabled` 与播放页内横向手势（歌词页/切歌）冲突排查。
- 拆除旧模态路径与 `ui.nowPlayingShown` 开关（D4 到期）；`NowPlayingMotion.ets`/`NowPlayingCurves.ets` 中页面级转场函数废弃删除，页内布局动画保留；对应单测同步清理。
- 「首页穿透」类旧问题随模态拆除自然消失，回归确认即可。

### M5 收尾与文档同步

- `docs/hm.md` 新增 §7.15 记录（迁移动机、6 步落点、真机验证记录）。
- `docs/FEATURE_MATRIX.md` 播放页转场状态更新（真机验证通过后才可标「已验证」）。
- 清理 feature flag；gitleaks/CI 全绿后 PR merge 进 dev。

## 5 风险清单

| # | 风险 | 等级 | 缓解 |
|---|------|------|------|
| R1 | HdsNavigation 壳对自定义转场的实际兼容性未知（d.ets 有 API ≠ 壳内部无额外转场处理） | 高 | M1 spike 先行，不通过则主容器换原生 Navigation 另行决策 |
| R2 | 全局转场回调误伤其他页面 | 中 | D3 参数过滤 + 路由白名单；回归全部二级页转场 |
| R3 | CI 拉不到三方包 | 低 | M3 首个 commit 即观察 CI；registry 为 ohpm 公共源 |
| R4 | miniBar 槽位 remount 导致触发 id 失效 | 中 | id 常量化；generateLongTakeParam 在点击时刻取当前挂载组件；真机覆盖切 Tab 后点击场景 |
| R5 | 播放页生命周期变化误伤后台播放/AVSession | 高 | 播放引擎零改动红线（守则 1.3）；真机回归后台播放、耳机断开暂停（a971da3 行为） |
| R6 | 深浅色/宽屏下转场背景异常 | 中 | D5 背景迁移 + onConfigurationUpdate；真机覆盖深浅切换与旋转 |
| R7 | 本机无模拟器，UI/转场结论均无真机证据 | — | 全程标注「待真机验证」；M1/M3/M4 各设真机关卡 |

## 6 验证矩阵（每里程碑收尾跑）

| 项 | 命令/方式 | 环境 |
|----|----------|------|
| 构建 | `hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon` | 本机 |
| 静态检查 | `codelinter`（改动文件 0 error，全量基线 5 个 await-thenable 属工具漂移） | 本机 |
| 单元测试 | `hvigorw test ...`（编译级）→ Windows 工作站全量（RouteStack/NowPlayingMotion 用例更新） | 双机 |
| 真机 smoke | `./build-signed.sh` → `hdc tconn` 安装；转场/折返/返回对齐/深浅色/宽屏/后台播放/耳机断开 | 手机 |
| 密钥扫描 | gitleaks CI（新依赖锁版本，不引入 token） | CI |

## 7 进度记录协议

- 每里程碑完成：在本文件 §8 追加一行记录（日期、commit、验证状态、未验证项），随代码同 commit 提交。
- 受阻：按全局规则发介入邮件，本文件记录受阻原因与已试措施。
