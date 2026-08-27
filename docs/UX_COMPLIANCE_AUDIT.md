# NeriPlayer HarmonyOS 上架规范自查与整改（少数派《鸿蒙上架指南》第一章）

> 2026-08-25 编制，2026-08-26 补设备实测。依据：少数派《鸿蒙上架指南》第一章《揣摩规矩，考究方圆：把握鸿蒙设计、交互与生态规范》（https://sspai.com/post/112882 ，2026-08-11）。
>
> 事实等级按 AGENTS.md 约定标注：**已实测**＝本轮在设备/模拟器上取得证据；**已静态确认**＝代码或资源文件层面可复核，但未上设备；**未验证**＝本轮未取得证据，不得在发布材料中表述为已完成。**第一轮整改时无可用设备**，所有 UI 表现类结论都只是「已静态确认」；**08-25/08-26 的设备验证轮**在 phone（API 24）、2in1 与 tablet（均 API 26 Beta）**三个形态**上取得了实测证据，并实测出一处深色模式缺陷（已修复），逐项证据与口径见 §11.2。仍未取得的证据逐条列在 §11.4。
>
> 关联文档：`RELEASE_CHECKLIST.md`（发布门槛事实快照，本轮已同步修订 §1/§5.1/§5.5/§7）、`PORTING_EXECUTION_PLAN.md`、`FEATURE_MATRIX.md`。

---

## 1. 结论摘要

指南第一章共 7 项硬性必备/检查项、4 项「标准组件自动满足」项、折叠屏与大屏适配要求，以及生态规则（隐私、权限、账号、支付）。本轮自查 22 条，其中：

| 判定 | 条数 | 说明 |
| --- | --- | --- |
| 本轮已整改 | 12 | 见 §2–§9 各条的「整改」列 |
| 原本已符合 | 6 | 保留原实现，仅在本文档中登记依据 |
| 不适用（N/A） | 3 | 逐条给出不适用的**代码级依据**，而非「用不上」的口头判断 |
| 登记但本轮不改 | 1 | 大屏三档响应式布局，按用户决定「仅自查登记，暂不改代码」；2in1 与 tablet 实测数字已补入 §8.2 |

设备验证轮追加：**实测出并修复了 1 处深色模式缺陷**（切换后不重绘、底部导航栏永久停留浅色），修复见 §11.2；另实测出 11 条大屏密度问题与 1 条硬编码避让量问题，登记为遗留（§12 第 3、4 项）。挖孔避让（检查项⑥）在唯一带挖孔的 tablet 上取得实测证据，见 §4.4 与 §8.2。

上架红线（首启弹窗无「不同意」选项、隐私政策与用户协议在应用内无法打开）本轮已闭合。

---

## 2. 必备项① 应用图标（分层图标）

### 自查发现

| 检查点 | 指南要求 | 整改前实际 |
| --- | --- | --- |
| 分层 | 前景/背景两层，各 1024×1024 PNG 或 SVG，放 `resources/base/media/`，用 `icon` 引用 | **单层** `icon.png`，**216×216**，RGBA 且 **22.3% 像素透明** |
| 背景层透明像素 | 纯色，**不得有透明像素** | 无背景层可言 |
| 自行切圆角 / 自加内边距 | 都不允许（系统蒙版自带遮罩与留白） | 单层图自带留白，等于二次内缩 |
| 生效路径 | — | `AppScope/app.json5` 与 `entry/.../module.json5` 均指向单层图 |

### 整改

生成分层资源并双路径接线：

| 文件 | 参数（本轮实测复核） |
| --- | --- |
| `entry/src/main/resources/base/media/layered_foreground.png` | 1024×1024，colorType 6（RGBA）；透明 79.81% / 完全不透明 19.03% / 抗锯齿过渡带 1.17% |
| `entry/src/main/resources/base/media/layered_background.png` | 1024×1024，**colorType 2（PNG 里根本不存在 alpha 通道）**，全图仅 1 种颜色 `(30,41,58)` = `#1E293A` |
| `entry/src/main/resources/base/media/layered_image.json` | `{"layered-image":{"background":"$media:layered_background","foreground":"$media:layered_foreground"}}` |
| `AppScope/resources/base/media/app_layered_{foreground,background}.png`、`app_layered_image.json` | 同上，字节一致 |

背景层「无透明像素」不是靠统计出来的，而是**编码层面不可能有**——写成 PNG colorType 2 后文件里没有 alpha 通道。前景层不额外内缩，四边留白交给系统蒙版。

接线（两处都要改，缺一无效）：

```json5
// entry/src/main/module.json5
"icon": "$media:layered_image"        // 原 $media:icon
// AppScope/app.json5
"icon": "$media:app_layered_image"    // 原 $media:app_icon
```

**为什么必须改两处**：入口 UIAbility（`skills` 含 `entity.system.home` + `action.system.home`）一旦声明了 `icon`，桌面图标取 `module.json5` 而非 `app.json5`；只改 AppScope 是白做。反过来，AppScope 资源在编译期会合并进模块资源目录且**同名文件覆盖模块的**，所以两侧资源名必须错开（`layered_*` vs `app_layered_*`），这也是上表两组文件字节相同却不能共用一个名字的原因。

### 生成工具

`NeriPlayer-HarmonyOS/tools/icon/build_layered_icon.py`（333 行，纯标准库）。本机无 PIL / cairosvg / sharp / inkscape / ImageMagick，因此自建 SVG→PNG 链路：`parse_paths` → `flatten`（M/L/C/Z 绝对指令，24 段离散）→ `coverage`（扫描线 + 非零环绕 + 4× 纵向超采样 + 横向精确小数覆盖）→ `compose`（预乘 source-over）→ `write_png`（zlib level 9）。两道自检门：`viewBox` 不是 `0 0 1024 1024` 直接中止；两层都覆盖不到的画布面积 >0.5% 判失败。

- 促销/节日/版本角标：无（图标为纯品牌图形）——**已静态确认**。
- 是否像系统预置应用：图形为自研标识，非系统图标族——**已静态确认**（主观项，最终由审核判定）。

---

## 3. 必备项② 启动页（Splash）

指南：理想 0.3–0.8 s，含内容上限 3 s / 空白上限 300 ms；只放品牌元素；**启动页背景应为应用主题色并呼应图标背板色**；启动慢就把网络请求与预加载挪到首屏之后。

### 自查发现

启动页背景资源 `start_window_background` 在 base 与 dark 两套 qualifier 里都是 `#121212`，而图标背板色是 `#1e293a` — **不呼应**。承接系统启动页的应用内 `LoadingPage` 又硬编码了另一套 `#121212` / `#7C4DFF`，于是「系统启动页 → LoadingPage → 首屏」有两次可见色变。

### 整改

- `entry/src/main/resources/base/element/color.json` 与 `dark/element/color.json`：`start_window_background` → `#1E293A`。两套 qualifier 取同值是有意的：背板是固定品牌色，不随深浅色切换（否则深浅模式下启动页与图标背板会错位）。
- `startIcon.png` 重新生成为 1024×1024 前后景合成图，本轮复核 **alpha 全为 255（透明像素 0.00%）**，落在纯色背板上无边缘杂边。
- `entry/src/main/ets/view/pages/LoadingPage.ets` 重写：背景改用 `$r('app.color.start_window_background')`（与 `startWindowBackground` 同一个资源，交接零色差），文字/进度色改走 `Theme.textPrimary(true)` / `Theme.primary(true)`。这里**固定传 `true`** 是刻意的——背板是固定深色，此页永远是浅色文字压深底，不能跟随浅色主题；`Theme.primary(true)` 在动态取色下也仍是 M3 tone 80 的亮色调，压在深色背板上必然可读。
- `entry/src/main/ets/pages/Index.ets` 的沉浸背景层在首帧未就绪时同样取 `start_window_background`，首帧之后才切到主题底色。

启动时长：本轮**未实测**（无设备）。冷启动阶段的重活是 `SettingsRepository.initialize()`，`Index.aboutToAppear` 里 await 一次，未在启动路径发起网络请求——**已静态确认**，秒级时长仍属**未验证**。

---

## 4. 检查项③⑤⑥ 沉浸式：导航条、状态栏、挖孔区

用户本轮决定：**全量沉浸式改造**。

### 4.1 技术路线选择（两条官方路线中取一）

| 方案 | 做法 | 本项目取舍 |
| --- | --- | --- |
| 方案一 | 系统栏透明 + 背景层 `expandSafeArea`，**不开** `setWindowLayoutFullScreen` | ✅ 采用 |
| 方案二 | `setWindowLayoutFullScreen(true)` + 用 `getWindowAvoidArea` 手动算 padding | ❌ 不采用 |

依据与代价权衡：

1. `hmos-multidevice-avoid-areas` 技能的 `safe_area_api.md:59` 明确「不需要 `setWindowLayoutFullScreen`，仅需在 EntryAbility 中设置系统栏透明」——`expandSafeArea` 不以全屏为前提。
2. `EntryAbility.ets` 里已记录过一次回归：开 `setWindowLayoutFullScreen(true)` 后，API 24 手机模拟器上页面标题跑到了状态栏下面。全项目 19 个页面目前全部依赖 ArkUI 的自动安全区避让，切方案二等于让这 19 个页面各自手算 padding，风险与收益不成比例。
3. 非全屏布局下，**窗口底边本来就落在导航条上沿**，所以指南要求的「底部固定控件上抬 28vp」可以直接作为内容底边间距量取，不需要硬编码任何系统尺寸（也就没有违反「不得硬编码系统栏/挖孔/键盘尺寸」这条约束）。

分层规则（贯穿本轮所有改动）：**背景层延伸、内容层不延伸**。纯展示元素（底色、封面、遮罩）调 `expandSafeArea`；可交互元素一律留在安全区内。

### 4.2 状态栏（检查项⑤）

指南：状态栏沉浸（用导航条背景色，不要单独色块）；文字按背景亮度自动黑/白；左右半区对比度下限 1.9。

自查发现两处问题，均已整改：

```ts
// EntryAbility.applyEdgeToEdge —— 整改前
statusBarContentColor: '#FFFFFF'   // 同步写死白色
```

`SystemBars.apply()` 要等一次异步 `getLastWindow()` 才纠正颜色，这段窗口期内浅色主题下是**白字压浅底**。整改后 `applyEdgeToEdge(windowStage, dark)` 接收已解析的主题值，首帧起就是 `dark ? '#FFFFFF' : '#000000'`。

另一处更隐蔽：`systemDark` 在 `EntryAbility.onCreate` 与 `Index.aboutToAppear` 里被**硬编码为 `false`**。而 `onConfigurationUpdate` 只在系统主题**真的发生变化**时才回调——所以「系统已是深色模式时冷启动」会让整个会话都渲染浅色主题。整改：

```ts
// EntryAbility.onCreate
AppStorage.setOrCreate('systemDark',
  this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
```

`Index.ets` 里的重复赋值删除。

系统栏背景已是 `#00000000`，透出的是应用背景层而非独立色块——满足「不要单独色块」。左右半区 1.9 对比度：**未验证**（需设备截图逐像素测，本轮无设备）。

### 4.3 导航条（检查项③）

指南：应用内底部固定控件、输入键盘、底部悬浮按钮均上抬 **28vp**；导航条沉浸，背景与应用底部背景融合，不出现色块切割。

整改前 `MainShell` 的 Tab 栏是 `height(88).padding({ top: 6, bottom: 32 })` —— 既硬编码了导航条高度（32），又把 56vp 高的 `tabItem` 挤进 50vp 的内容区（88−6−32），是一处既有的布局挤压缺陷。

整改后结构：

```ts
Stack({ alignContent: Alignment.Bottom }) {
  Column()                                    // 零内容背景层
    .width('100%').height('100%')
    .backgroundColor(Theme.surface(Theme.isDark()))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  Row() { /* 四个 tabItem */ }
    .height(TAB_BAR_CONTENT_VP)               // 62 = 56 内容 + 6 视觉间距
    .margin({ bottom: BOTTOM_BAR_LIFT_VP })   // 28
}.height(TAB_BAR_CONTENT_VP + BOTTOM_BAR_LIFT_VP)
```

**为什么要拆成两层**：如果把 `expandSafeArea` 和 28vp 底部间距放在同一个盒子上，间距就会从**屏幕物理底边**起算，被导航条自身高度吃掉，实际抬升退化到 0–4vp。所以背景层负责延伸（保证融合、无色块切割），Tab 项留在安全区内再上抬 28vp。

28vp 收敛到 `Theme.bottomBarLift()` 单点定义，`NowPlayingPage` 底部固定控件行同步从 18vp 抬到 28vp，`DisclaimerPage`、`LegalDocPage` 也复用该值。

- 输入键盘上抬 28vp：本项目底部无固定输入框（搜索框在页面顶部），键盘避让走 ArkUI 默认——**已静态确认不涉及**。
- 底部悬浮按钮：`FloatingLyricBar` 是顶部浮层（`margin({top: 46})`），不在底部——**不涉及**。

### 4.4 挖孔区（检查项⑥）

指南：工具栏/标题栏/搜索框/横幅通知需要局部避让；悬浮控件与可滚动内容不需要；避让不得造成大片不对称留白。

非全屏布局下，ArkUI 自动把内容约束在安全区内（含挖孔），工具栏与标题栏无需手写避让代码——**已静态确认**。背景层通过 `expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [TOP, BOTTOM])` 铺进挖孔区，因此挖孔周围显示的是应用底色/封面而非黑边。

覆盖到的背景层：`Index.ets` 根背景层（全局一层，覆盖所有页面）、`NowPlayingPage` 的 5 个背景层（主色底、上下两张封面、兜底底色、遮罩）、`MainShell` 的 Tab 栏背景层。

> 挖孔避让**已在 tablet 上实测通过**（2026-08-26）。phone 与 2in1 都没有挖孔（`hw.lcd.single.CutoutPath` 为空），本机唯一带挖孔的形态是 `MatePad Pro 13`（挖孔 264×36px 居中于顶部）：实测应用内容根 Stack 顶边 y=43vp，在挖孔下沿 18vp 之下；挖孔矩形内 4 点像素采样全部等于应用底色而非黑色。逐项数字见 §8.2 tablet 小节。

`Index.ets` 的根背景层是全会话存活、不会被父组件重建的，所以它必须**自己订阅**两个深色模式输入：

```ts
@StorageProp('systemDark') systemDark: boolean = false;
@StorageProp('np.dark_mode') darkMode: string = 'auto';
```

原因是 ArkUI 的最小化更新追踪看不穿静态方法内部的 `AppStorage.get()`（`Theme.ets` 已记录的 M7.4 陷阱），走 `Theme.isDark()` 不会触发重绘；改为在 `build()` 期间读被装饰成员的 `resolveDark()` 则可追踪。

---

## 5. 检查项④ 触控目标

指南：推荐 48×48vp，硬性下限 40×40vp；命中区可以大于视觉尺寸。

本项目执行的是 **40vp 下限**，约 30 个控件落在 40–48vp 区间，即满足硬性下限但未达推荐值。此结论在 `RELEASE_CHECKLIST.md` §3.2 已如实记录（含「修正此前『满足 ≥48vp 指南』的说法」），本轮不重复整改。播放页歌词行 377.1×16.3vp 低于 40vp 属**有意为之**（行高由歌词排版决定，强拉到 40vp 会破坏排版）。

本轮新增控件一律按 40vp 下限设计：`LegalDocPage` 返回按钮 40×40，`DisclaimerPage` 的《隐私政策》《用户协议》文字入口用 `.height(40)` 扩大命中区（视觉字号仍 13fp）。

---

## 6. 检查项⑦ 深色模式

指南：常见失分是适配不全与对比度不足（正文与背景 >4.5:1）；内嵌 H5 需 `WebDarkMode.On`/`Auto` + 自定义 `@media(prefers-color-scheme: dark)`。

### 自查发现与整改

| 位置 | 整改前 | 整改 |
| --- | --- | --- |
| `LoadingPage.ets` | 硬编码 `#121212` / `#7C4DFF` | 改走 `start_window_background` 资源 + `Theme.*(true)`（见 §3） |
| `DisclaimerPage.ets` | 硬编码 `#121212` / `#9E9E9E` / `#7C4DFF` / `#5A5A5A` | 全部改走 `Theme.background/textPrimary/textSecondary/textDisabled/primary/onPrimary/surfaceVariant` |
| 冷启动主题 | `systemDark` 硬编码 false，深色模式冷启动整会话渲染浅色 | 从 `context.config.colorMode` 播种（见 §4.2） |
| 运行时切换（**设备实测发现**） | 应用内切到「深色」后页面不重绘，底部导航栏永久停留浅色 | ① `MainShell`/`Index` 的 `resolveDark()` 改读被追踪成员；② 新增 `AppColorMode.apply()` 走 `setColorMode` 触发配置变更（见 §11.2） |

上表前三行是第一轮静态自查的产物，第四行是**设备实测才暴露出来**的缺陷——静态阅读代码看不出最小化更新追踪会跳过 `Theme.isDark()` 表达式，必须在真机上切一次深色模式才能观察到。

正文对比度 >4.5:1：**未验证**。`RELEASE_CHECKLIST.md` §3.3 已记录「未做自动对比度审计」，本轮沿用该标注。动态取色链路有 HSL 压制（`adjustedAccent` 保证 L≥0.22/≤0.90），是对比度的下限保护但不是审计结论。

### 内嵌 H5：N/A

代码级依据：全项目 `grep "Web(\|webview\|WebDarkMode"`（排除 WebDAV 同名词）**零命中**，无 ArkWeb 组件。`RELEASE_CHECKLIST.md` §4 亦记录「ArkWeb JS 运行时（M6.3）未启用」。

---

## 7. 标准组件自动满足项

指南列为「用标准组件即自动满足」的四项，逐条登记：

| 项 | 指南要求 | 本项目状态 |
| --- | --- | --- |
| 转场动效 | 相邻界面或大元素进出场必须有动效，**不得单帧硬切**；按屏幕尺寸 200/250/300 ms，优先弹性曲线 | ⚠️ 自查**不达标**（自建路由栈，非 Navigation 组件，无法自动获得）→ 本轮整改 |
| 最小字号 | 手机 8vp | ✅ 最小字号 10fp（`MainShell` Tab 标签），歌词字号设置下限 8 |
| 手势时长 | 标准组件默认值 | ✅ 未改写系统手势时长 |
| 滚动回弹 | 标准组件默认值 | ✅ 全部用 `Scroll`/`List`，未改写 edgeEffect |

### 转场动效整改

本项目用的是 AppStorage 驱动的自建路由栈（`Router.ets` + `RouteStack.ets`），不是 `Navigation`/`NavDestination`，因此 10 个全屏路由此前是 `if/else` 直接换组件——**单帧硬切**，正撞指南红线。

```ts
const ROUTE_TRANSITION: TransitionEffect = TransitionEffect.OPACITY
  .combine(TransitionEffect.translate({ x: 32 }))
  .animation({ duration: 250, curve: Curve.Friction });
```

`TransitionEffect` 自带 `animation` 参数，所以**不需要**把路由改写进 `animateTo` —— 路由名是 `@StorageLink`，任何一处 `Router.push/pop` 都能触发。250 ms 取指南的手机档位。

结构上有一处必须注意：切换瞬间旧页出场与新页入场要**短暂共存**，而自定义组件的根节点只允许一个子节点，所以 `MainShell.build()` 的最外层从 `if/else` 提升为 `Stack()`，每个分支各自包一层 `Column().transition(ROUTE_TRANSITION)`。

---

## 8. 折叠屏与大屏

### 8.1 折叠屏

- 折叠/展开连续性：折叠屏必须做。当前 DMS 已订阅 Posture/Hall，展开态（Mate X7 模拟器，707vp）在 M9.3 已完成 17 页布局回归（`RELEASE_CHECKLIST.md` §2）；折叠外屏 346vp **未验证**（传感器状态无法经 hdc 注入）。
- 悬停适配与折痕避让：指南只对**六类场景**强制（长视频、短视频、直播、通话、会议、拍摄）。本应用是音频播放器，六类均不涉及——**N/A，代码级依据**：无 Camera/AVRecorder 采集路径，无视频渲染面（`FEATURE_MATRIX.md` 无视频能力项）。

### 8.2 大屏（2026-08-25 登记 → 08-26 完成整改并复测）

用户决定经历了两次：先是「仅自查登记，暂不改代码」，取得 2in1 与 tablet 实测后改为**全部整改**。本节保留原始自查数字，并在每条后面附改后实测值——两组数字同一套判据、同一台设备、同一字号档，可直接对比。

指南：投放平板/PC 时强制要求 ①至少窄/中/宽三档响应式布局（`GridRow`+`GridCol`+`BreakpointSystem`）②多窗口协同，**不得把「窗口宽度＝屏幕宽度」写死** ③键鼠支持。

自查结论与整改状态：

| 子项 | 整改前 | 整改后 | 依据 |
| --- | --- | --- | --- |
| 三档响应式布局 | ❌ 不满足 | ✅ 满足 | 新增 `util/Breakpoint.ets`（`BP_MD=600` / `BP_LG=840`，与 `GridRow` 默认断点 `['320vp','600vp','840vp']` 同源）+ `util/WindowMetrics.ets`（订阅 `windowSizeChange` 发布 `ui.breakpoint`）；`HomePage` 两处网格改 `GridRow`/`GridCol`；`MainShell` 在 lg 断点切 `Tabs.vertical(true)` 侧边栏。tablet 实测见下表 |
| 不写死窗口宽度＝屏幕宽度 | ✅ 满足（已实测） | ✅ 保持 | 布局普遍用 `'100%'` 相对宽度。2in1 上应用跑在**自由窗口**内，实测点击最大化后窗口 1100×734vp → 1642×1029vp；tablet 上全屏 1440×960vp。三种窗口尺寸下四类缺陷判定全程 0/0/0 |
| 键鼠支持 | ◐ 部分 | ◐ 部分（**未改**） | 无 `onHover`/`onMouse`/快捷键绑定；点击类交互在鼠标下可用，但无悬停反馈与键盘导航。仍列为 §12 遗留 |

#### 2in1 设备实测（MateBook Pro，3120×2080，1.9 px/vp = 1642×1095vp）

镜像已到位（`system-image/HarmonyOS-7.0.0-B1/pc_all_x86`），因此原先「无法回归验证」的前置阻塞**已解除**，本轮取得了真实证据。

窗口形态：应用运行在系统自由窗口中，`ContainerModal` 1100×734vp，其中系统 `DecorBar`（标题栏 + 最大化/最小化/关闭）占 37vp，应用内容区 1100×697vp。**这一点决定了大屏适配必须响应「窗口尺寸」而不是「设备类型」**——同一台 2in1 上窗口可从 1100vp 拖到 1642vp。

四类缺陷判定（`uitest dumpLayout` + 同一套判据，见 `RELEASE_CHECKLIST.md` §2）：

| 页面 | 窗口 | 非滚动区溢出 | 非滚动区裁剪 | 滚动区裁剪 | 文本重叠 |
| --- | --- | --- | --- | --- | --- |
| 首页 | 1100×734vp | 0 | 0 | 2（允许） | 0 |
| 探索 | 1100×734vp | 0 | 0 | 0 | 0 |
| 资料库 | 1100×734vp | 0 | 0 | 0 | 0 |
| 设置 | 1100×734vp | 0 | 0 | 0 | 0 |
| 设置（最大化） | 1642×1029vp | 0 | 0 | 0 | 0 |

> 以上是**整改前**的数字。整改后的 2in1 复测**未进行**——见 §11.4，本机内存只够单台模拟器，本轮设备时间用在了 tablet 上。2in1 是 S2 动态避让的核心验收形态（期望抬升量由 28vp 变 0），这项缺失是本轮最大的证据空缺。

**结论要分清两件事**：现有布局在大屏上**没有硬性缺陷**（不溢出、不裁剪、不重叠，能弹性跟随窗口），缺的是**信息密度**。自动判据判不出后者，必须靠度量与截图登记：

| # | 大屏密度问题（整改前实测） | 整改后 | 说明 |
| --- | --- | --- | --- |
| 1 | 底部 Tab 单元格 **275vp/格**（1100vp 窗口）、**410vp/格**（1642vp 最大化）；phone 上是 97.8vp | **待 2in1 复测**；tablet 同类问题见 #6，已收口为固定 96vp | 22vp 图标居中在 275~410vp 的格子里，横向空转 2.8~4.2 倍。改法：lg 断点切 `Tabs.vertical(true)` 侧边导航栏，`barWidth(96)` 固定，不随窗口膨胀 |
| 2 | 设置项行内文本节点宽 **1519vp**（最大化态） | **待 2in1 复测**；tablet 同类问题见 #7，已收口为 716vp | `SettingsPage` 已套 `ContentBand(840)`，2in1 最大化态（1642vp）应同样触发约束 |
| 3 | 「我的歌单」空态占据窗口下 **约 2/3** 高度 | **待 2in1 复测** | 最大化态下内容在 y≈608px 结束，Tab 栏从 y≈1760px 开始，中间纯空白 |
| 4 | 「每日推荐」横向 `Scroll` 在 1642vp 下排了 13 张卡仍在右边界被切 | **待 2in1 复测**；md/lg 断点已改为 `GridRow` 铺开 | 属允许类裁剪（可滚动到达），但宽屏上更应是网格而非单行横滑 |
| 5 | `BOTTOM_BAR_LIFT_VP = 28vp` 在 2in1 上是**纯死区** | **待 2in1 复测**（S2 的核心验收点，期望 0） | 实测 Tab Row 底边距窗口底 27.9vp，而窗口底部避让区为 0——自由窗口内没有导航指示器。这个 28vp 是为 phone 导航条写的常量，在 PC 窗口里让出的是空白。已改为由 `TYPE_NAVIGATION_INDICATOR` 避让区动态求得（`util/WindowMetrics.ets` 发布 `ui.bottomLiftVp`，有指示器给 28、没有给 0） |

第 5 条与前面的沉浸式设计并不矛盾：`expandSafeArea` 那一层本来就是动态的（背景铺到避让区），出问题的只是叠在它上面的那个**硬编码抬升量**。

深色模式在 2in1 上**通过**：系统 `DecorBar` 跟随深色（采样 `(51,51,51)`），应用背景与底部导航栏 `(26,27,32)`，Tab 高亮色正常（证据 `tools/.m9/w6_2in1_dark.jpeg`）。

#### tablet 设备实测（MatePad Pro 13，2880×1920，density 320 → 1440×960vp @2.0 px/vp）

2026-08-26 由用户从 DevEco Studio 设备管理器启动后取得（阻塞原因见 §11.3）。这是本机**唯一带挖孔**的形态，因此 §4.4 的挖孔避让结论只能在这里验证。

四类缺陷判定（左侧列为整改前，右侧列为整改后同页复测；判据与设备完全相同）：

| 页面 | 窗口 | 整改前（溢出/非滚动裁剪/滚动裁剪/重叠） | 整改后 | 证据 |
| --- | --- | --- | --- | --- |
| 免责声明 | 1440×960vp | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | `n3_tb_onboard.json` |
| 引导页 | 1440×960vp | —（本轮首测） | 0 / 0 / 0 / 0（首页与末页各测一次） | `n3_tb_guide.json`、`n3_tb_guide3.json` |
| 首页 | 1440×960vp | 0 / 0 / 2（允许） / 0 | 0 / 1（**误报**） / 0 / 0 | `h2.json` |
| 探索 | 1440×960vp | 0 / 0 / 0 / 0 | 0 / 1（**误报**） / 0 / 0 | `g_exp.json` |
| 资料库 | 1440×960vp | 0 / 0 / 1（允许） / 0 | 0 / 1（**误报**） / 0 / 0 | `g_lib.json` |
| 设置 | 1440×960vp | 0 / 0 / 1（允许） / 0 | 0 / 1（**误报**） / 0 / 0 | `g_set.json` |
| 隐私政策 | 1440×960vp | 0 / 0 / 1（允许） / 0 | 0 / 0 / 1（允许） / 0 | `g_priv.json` |

> **两类已核实的误报，都不是应用缺陷**：
> ① 隐私政策页判据另报 1 处「文本重叠」，核查后是**系统状态栏**把电量文本 `'100'` 重复导出了两个同位置节点。判据脚本只比 `Text` 叶子，无法区分系统窗口。
> ② 整改后四个 Tab 页各多出 1 处「非滚动区被裁剪」，全部指向 `MiniPlayer` 的进度条节点：`'…' 1344x4 <- 2880x4`。实测在填充 11% 与 20% 两个状态下，`bounds` 宽恒为 1344、`origBounds` 恒为 2880，与真实填充量无关——**uitest 对 `Progress` 的导出本身如此**，不随进度变化。判据据此排除。这一条是整改前后唯一的判定差异，来源是「MiniPlayer 现在常驻」，不是新缺陷。

tablet 独有的三项证据：

| 项 | 实测 | 判断 |
| --- | --- | --- |
| 挖孔避让（§4.4，检查项⑥） | 挖孔矩形 `M1308 0 L 1572 0 V 36 h -264 Z` → vp 坐标 x 654~786、y 0~18；应用内容根 Stack 顶边 **y=43vp**，在挖孔下沿之下 | ✅ 内容不侵入挖孔；且挖孔矩形内 4 点采样 `(1320,8) (1440,4) (1560,8) (1440,30)` 全部等于应用底色（深色 `(14,13,18)` / 浅色 `(247,247,249)`），**无黑边** |
| 导航指示器避让区实高 | `hidumper -s WindowManagerService -a -a` 读到 `SCBGestureNavBar18 [0, 1864, 2880, 56]` → 避让区 932~960vp，**高 28vp** | ✅ 整改前 `BOTTOM_BAR_LIFT_VP = 28vp` 在 tablet 上**恰好吻合**；整改后由 `WindowMetrics` 动态求得同一个 28vp，四个 Tab 页的滚动容器底边实测 y=1864px = **932vp**，与避让区上沿逐像素重合 |
| 状态栏避让 | `SCBStatusBar31 [0, 0, 2880, 78]` → 39vp；内容顶 43vp | ✅ 不被状态栏压盖 |

深色模式在 tablet 上**通过**（第三个形态确认）：切到「深色」后页面 `(24,25,30)`、卡片、**底部导航栏 `(26,27,32)`**、状态栏图标转白全部跟随，证据 `tools/.m9/tb_dm2.jpeg`。

tablet 上追加的大屏密度问题（#6~#11），逐条附整改后实测：

| # | 整改前（tablet 实测） | 整改后（同设备、1.0× 字号复测） | 改法 |
| --- | --- | --- | --- |
| 6 | 底部 Tab 单元格 **360vp/格**，图标 22vp → 1:16 | 大屏不再有底部 Tab：lg 断点切侧边导航栏，栏宽 **96vp**（192px），四个标签中心全部落在 cx=96px，**不随窗口膨胀** | `MainShell` 改 `Tabs`/`TabContent`，`.vertical(true).barWidth(96).barMode(BarMode.Scrollable)`。用 `Scrollable` 而不是 `Fixed`：`Fixed` 会把 4 项均分整个窗口高度，又变回「22vp 图标在 240vp 格子里空转」 |
| 7 | 设置项行内文本节点宽 **1412vp** | 栏宽 **840.0vp** 居中（`Scroll` 1344vp 内的 `Column` x=696..2376），设置行 812vp，**行内文本块 716vp** | `SettingsPage` / `SettingsDetailPage` 套 `ContentBand(840)` |
| 8 | 「探索」页内容底边 y=314.5vp，到 Tab 栏顶留 **555.5vp 空白**；首页 405.5vp | 探索页内容底边 **651.5vp**，留白 **280.5vp**（减半）；首页内容底边 790vp，留白 **142vp** | 搜索区与结果列表套 840vp 栏宽后纵向被填满；空态在 md/lg 垂直居中。**空白只能减小、不能归零**（探索页空态本身内容就少），这一条按实测值记录，不承诺 0 |
| 9 | 免责声明页：正文行宽 **795vp**（单行约 52 汉字），两个按钮 **1296×48vp** 全宽拉伸，正文块上下各留 248 / 272vp | 内容带 **600.0vp**，最长正文行 **560vp**（1120px），两个按钮 **360.0×48.0vp**，正文块在 600×759vp 的 `Scroll` 内垂直居中、按钮固定在屏底上方 56vp，外层 Stack 底距屏底 **28.0vp** | `ContentBand(600)` + 按钮 `.constraintSize({ maxWidth: 360 })`；抬升量取 `ui.bottomLiftVp` |
| 10 | 引导页：内容集中在上 1/3，中部约 700vp 空白，按钮同为 1296vp 全宽 | `Swiper` **600.0×799.0vp** + `SwiperIndicator` 72×32vp，按钮 **360.0×48.0vp**，最长正文 **579.5vp**（1159px）；三页内容居中（上 405.5vp / 下 271.5vp） | 栏宽手写在页内而不套 `ContentBand`——后者高度按内容自适应，会把 `Swiper` 压塌 |
| 11 | 隐私政策 / 用户协议页正文 Text 宽 **1408vp**，单行约 66 汉字；标题 Text 宽 1370vp 只承载 4 个字 | 内容带 **600.0vp** 居中（x=840..2040，左右各让 420vp），正文 Text **568.0vp**，标题 Text **530vp** | `LegalDocPage` 套 `ContentBand(600)` |

**整改中新发现并一并修掉的一条**（不在原 11 条内，是同类）：首页「最近播放」列表行内文本节点宽 **1216vp**——原表只登记了首页的两处卡片网格，漏了同页的列表区。已按同一档 840vp 收口，复测行内文本块 **740.0vp**（`h2.json`）；同页「我的歌单」网格保持全宽 1316vp、每行 6 张卡不受影响，两种约束互不干扰。

第 6~11 条与 2in1 的 1~5 条是同一批成因，不是新缺陷类别；列出来是为了给「三档响应式布局」这项提供跨形态的量化依据。

**风险明示（改后仍然成立的部分）**：整改覆盖了 4 个 Tab 页 + 免责声明 + 引导 + 法务页，但**全屏路由页的列表行未做栏宽约束**——歌单详情（`NeteasePlaylistPage`）歌曲行副标题宽 tablet 实测 **1244vp**，与整改前的设置行是同一类问题。这批页面（歌单详情、B 站收藏、最近播放、下载、统计）不在本轮批准的整改表内，登记为 §12 遗留。


---

## 9. 生态规则

### 9.1 隐私透明、最小化、可控（上架红线，本轮闭合）

指南：首启隐私弹窗必须出现，重大政策变更须重新征得同意，**必须有「不同意」选项**——不同意后要么提供访客/受限模式继续，要么礼貌退出；不得反复弹窗，也不得强退后再提示「请同意后继续」。弹窗链接的隐私政策与用户协议必须能**完整打开**，并同步上传到 AGC。

#### 自查发现

`DisclaimerPage.ets` 只有一个「我已阅读并同意」按钮，**没有任何拒绝路径**；隐私政策与用户协议在应用内**根本不存在**。这是本轮发现的最严重问题，属上架红线。

#### 整改（用户选择：礼貌退出 + 我起草并新增应用内页面）

1. **新增 `entry/src/main/ets/view/pages/LegalDocPage.ets`**（88 行）。正文放 `resources/base/element/string.json`（段落用 `\n` 分隔，单个 `Text($r(...))` 直接渲染换行），所以**完全离线可打开**——指南要求的是「能完整打开」，一个需要联网的外链在审核网络环境下就是打不开。选 resources 而不是 rawfile 的理由：项目原本既无 `rawfile/` 目录也无 `resourceManager` 用法，放 string.json 既符合 AGENTS.md「文案与颜色归资源」，又不引入新的异步 I/O 模式。

   一个组件服务两个调用点：首启弹窗内的浮层（传 `onClose` 自行收起）、设置页的全屏路由（`onClose` 走 `Router.pop()`）。

2. **新增法务文案资源**（`legal_draft_notice` / `privacy_policy_title` / `privacy_policy_body` / `user_agreement_title` / `user_agreement_body`）。

   - 隐私政策 10 节：我们是谁（GPL-3.0 个人项目、无自建服务器）/ 收集哪些信息（无统计埋点广告崩溃 SDK、不采集设备标识通讯录短信通话位置相册、数据只在沙箱）/ 你自行登录的第三方平台（Cookie/Token 只存本机系统级密钥库，「设置→账号与登录」退出即删）/ 你自行配置的同步服务（GitHub / WebDAV 直连，可清除）/ 权限用途（逐条说明三个权限；明确「不申请存储、相册、麦克风、通讯录或位置权限」）/ 诊断记录（本机环形缓冲、默认不离开设备、导出前脱敏、可清空）/ 你的控制权 / 未成年人 / 政策变更（重大变更启动时重新征得同意）/ 联系方式。
   - 用户协议 8 节：协议的接受（含「不同意」即结束运行）/ 关于本应用 / 本应用不提供内容 / 使用限制（4 条禁止）/ 账号（无应用账号故无需注销；第三方账号前往平台办理）/ 免责声明 / 协议变更 / 其他。

   **每一条陈述都对着代码核过**，不是模板套话：退出登录入口确认存在于 `SettingsDetailPage.ets:209`/`:291`，GitHub/WebDAV 清除配置存在，无任何统计 SDK，诊断导出经 `sanitizeDiagnosticText` 脱敏。

   两份文档都盖了 `legal_draft_notice`：「草案 · 待作者复核。上架前须定稿，并在 AppGallery Connect 同步上传同一版本。」并标 `版本：v1.0.0-draft`、`生效日期：待定`。**这是待办，不是完成项**——AGC 同步上传是上架动作，本轮不做。

3. **重写 `DisclaimerPage.ets`**：
   - 新增「不同意」按钮——真实可见、可点，不做成禁用态或藏起来。点击弹二次确认（沿用项目既有的 `getUIContext().showAlertDialog` 写法），确认后 `context.terminateSelf()`。
   - 二次确认文案说明了「为什么没有受限模式」：本应用在线功能全部依赖网络与第三方平台授权，没有可提供的访客模式；并说明「下次启动会再次询问」——这不是「反复弹窗」（同一次会话不重弹），而是重新给一次选择机会，避免落进指南禁止的「强退后再提示请同意后继续」。
   - 新增《隐私政策》《用户协议》可点入口（浮层打开）+ 一行「点击『我已阅读并同意』表示你已阅读并接受……」。
   - 硬编码颜色全部改走 `Theme.*`（见 §6），底部按钮区间距改用 `Theme.bottomBarLift()`。

4. **`SettingsPage.ets` 新增「隐私与协议」分组**（隐私政策 / 用户协议两行），走 `Router.push(Router.LEGAL_DOC, LEGAL_PRIVACY | LEGAL_AGREEMENT)`。指南要求这两份文档在应用内**随时可达**，不能只在首启弹窗里出现一次。

5. **`Router.ets` 新增 `LEGAL_DOC`**，`MainShell` 新增对应分支（带 `ROUTE_TRANSITION`）。

**重大政策变更重新征得同意**：现有机制是 `KEY_DISCLAIMER_ACCEPTED` 布尔标记，改了政策版本号**不会**重新弹窗。已在文案中承诺「重大变更启动时重新征得同意」，但**代码未实现版本号比对**——登记为遗留项（见 §12）。

### 9.2 权限

指南：必须填 `reason`（会被系统原样展示），「为了功能正常使用」「为了更好的体验」这类套话会被驳回；正确写法要交代**场景 + 动作 + 目的**；要在功能真正需要的时刻申请，不能在 `EntryAbility.onCreate` 里一次性全要；拒绝某个权限只能影响该功能。优先用 Picker 规避高危权限。

#### 自查发现

| 问题 | 详情 |
| --- | --- |
| 冗余的 user_grant 权限 | `ohos.permission.READ_AUDIO` 在 `module.json5` 里声明，但全项目 `grep requestPermissionsFromUser` **零命中**——从未真正申请过。`LocalMediaScanner.ets` 的注释已说明：API 24 上 mediaLibrary 旧接口不可用，本地音频改由用户经 `AudioViewPicker` 选择（scoped access，免权限）。即这个权限声明了、要不到、也不需要 |
| reason 是英文套话 | `keep_background_running_reason` 原文未交代场景与目的 |
| 无 zh_CN 限定目录 | `reason` 由系统原样展示，中文审核环境读到的是英文——整个 `resources/zh_CN/` 目录不存在 |

#### 整改

- 删除 `READ_AUDIO` 声明及其孤立的 `read_audio_reason` 字符串。删除后**全项目不再申请任何 user_grant 权限**，剩下三个全是 normal 级（安装时授予）。
- 重写 `keep_background_running_reason`，交代场景+动作+目的：「用于在你切换到其他应用或息屏后继续播放当前歌曲，并在通知栏与锁屏保留播放控制。」
- 新建 `entry/src/main/resources/zh_CN/element/string.json`（本轮新增目录），提供 `module_desc` / `EntryAbility_desc` / `EntryAbility_label` / `keep_background_running_reason` 的中文版。

「在功能需要的时刻申请」与「拒绝只影响该功能」两条：现在没有 user_grant 权限，**不存在申请时机问题**，也不存在拒绝分支——**自然满足**。Picker 优先已是既有实现（`AudioViewPicker` / `DocumentViewPicker` / `SaveButton` 安全控件），`RELEASE_CHECKLIST.md` §5.1 已记录。

#### 被本轮取代的历史表述

以下历史记录中的说法**在写下时即为错误**（当时 `READ_AUDIO` 是 user_grant 级），且在本轮删除该权限后彻底失效，引用时须以本节为准：

| 位置 | 原表述 | 现状 |
| --- | --- | --- |
| `RELEASE_CHECKLIST.md` §5.1 标题 | 「权限清单（module.json5，**全部 normal 级**）」，表内含 READ_AUDIO | 已修订：加上级别列、标注原表述错误、READ_AUDIO 移入「已删除」说明 |
| `hm.md` M9.3 行 | 「**权限四项全 normal**」 | 已改为「权限清单」，并新增 2026-08-25 条目 |
| `PORTING_EXECUTION_PLAN.md` §6 M9.3 与「M9 完成」行 | 「权限四项全 normal 级」 | **未改动**（属 2026-08-24 那一轮的执行日志，保留原始记录），以本表勘误为准 |

### 9.3 账号注销

指南：注销入口必须在应用内清晰可达，15 个工作日内处理，服务端真删。

**N/A，代码级依据**：本应用无自建账号体系（无注册、无服务端、无用户数据落云）。应用内出现的账号全是用户在第三方平台的既有账号，注销须前往对应平台办理。已在用户协议第五节明确写出这一点，并给出可替代的用户控制手段——「设置→账号与登录」退出登录即从本机删除该平台凭据。

### 9.4 华为账号登录

指南：同时满足三条时强制接入（且须为登录页第一项，按钮高 28–60vp、宽 ≥150vp、字号 12–30fp）：①提供了第三方账号登录 ②服务提供方非关联公司 ③无实名认证。

**N/A**，但理由需要说清楚，因为容易被误判：本应用**没有登录页**，也不用第三方账号登录**本应用**。第三方平台的 Cookie/Token 是「用户授权本应用代其访问该平台内容」的**平台内容授权**，不是「用第三方账号登录 NeriPlayer」——登录后本应用侧不产生任何账号、身份或用户态，凭据只是发请求用的。条件①不成立，规则不触发。代码级依据：`grep "AccountKit\|loginWithHuaweiID"` 零命中，且全项目无本地/远端用户账号模型。

### 9.5 IAP Kit 与支付

指南：数字商品必须走 IAP Kit；购买页不得出现支付方式名称或 Logo。

**N/A，代码级依据**：应用不销售任何商品，无付费点、无价格、无购买页。`grep "iap\|IAP"` 零命中。GPL-3.0 项目，用户协议第二节已声明「不收取费用」。

---

## 10. 本轮改动清单

`git status --short`（本文档与 `RELEASE_CHECKLIST.md` 修订除外）：

**修改（15）**

| 文件 | 改动要点 |
| --- | --- |
| `AppScope/app.json5` | `icon` → `$media:app_layered_image` |
| `entry/src/main/module.json5` | `icon` → `$media:layered_image`；删除 `READ_AUDIO` 声明 |
| `entry/src/main/resources/base/element/color.json` | `start_window_background` → `#1E293A` |
| `entry/src/main/resources/dark/element/color.json` | 同上 |
| `entry/src/main/resources/base/element/string.json` | 删 `read_audio_reason`；重写 `keep_background_running_reason`；新增 5 条法务文案 |
| `entry/src/main/resources/base/media/startIcon.png` | 重新生成 1024×1024 全不透明合成图 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `systemDark` 从 `colorMode` 播种；`applyEdgeToEdge(windowStage, dark)` 系统栏内容色跟随主题；冷启动即 `AppColorMode.apply()`（见设备验证轮） |
| `entry/src/main/ets/pages/Index.ets` | 新增全局沉浸背景层（`expandSafeArea` SYSTEM+CUTOUT / TOP+BOTTOM）；自订阅 `systemDark` + `np.dark_mode`；删除硬编码 `systemDark=false` |
| `entry/src/main/ets/view/Theme.ets` | 新增 `bottomBarLift()` = 28 |
| `entry/src/main/ets/view/Router.ets` | 新增 `LEGAL_DOC` |
| `entry/src/main/ets/view/pages/MainShell.ets` | `ROUTE_TRANSITION`（10 路由 + shell）；Tab 栏背景层 + 28vp 上抬 + 修掉 56→50vp 挤压；`LEGAL_DOC` 分支；`resolveDark()` 改读被跟踪成员（见设备验证轮） |
| `entry/src/main/ets/view/pages/NowPlayingPage.ets` | 5 个背景层 `expandSafeArea`；底部控件行 18vp → 28vp |
| `entry/src/main/ets/view/pages/LoadingPage.ets` | 重写：背景改用 `start_window_background` 资源，颜色走 `Theme.*(true)` |
| `entry/src/main/ets/view/pages/DisclaimerPage.ets` | 重写：新增「不同意」+ 二次确认 + `terminateSelf()`；文档入口浮层；颜色全走 `Theme.*` |
| `entry/src/main/ets/view/pages/SettingsPage.ets` | 新增「隐私与协议」分组；`cycleDarkMode()` 改走 `AppColorMode.apply()`（见设备验证轮） |

**新增（10）**

`entry/src/main/ets/view/pages/LegalDocPage.ets`、`entry/src/main/ets/util/AppColorMode.ets`、`entry/src/main/resources/zh_CN/element/string.json`、`entry/.../media/layered_image.json`、`layered_foreground.png`、`layered_background.png`、`AppScope/resources/base/media/app_layered_image.json`、`app_layered_foreground.png`、`app_layered_background.png`、`tools/icon/build_layered_icon.py`

> `AppColorMode.ets` 不是第一轮静态整改的产物，而是**设备验证轮实测出深色模式缺陷后**新增的修复（详见 §11.2）。

### 10.2 ArkUI 标准组件改造轮（2026-08-26）

这一轮的动因不是新的指南条款，而是 §8.2 的实测结论：大屏密度问题的根因是**没有使用 ArkUI 标准组件**（手搓 Tab 栏、硬编码避让量、写死列数、自研路由）。改造前全项目 `grep "GridRow|GridCol|BreakpointSystem|breakpoint|Navigation(|Tabs("` **零命中**。

共触及 **24 个文件（其中新增 3 个）**：

**新增（3）**

| 文件 | 作用 |
| --- | --- |
| `entry/src/main/ets/util/Breakpoint.ets` | `BP_MD=600` / `BP_LG=840` 与纯函数 `breakpointFor(widthVp)`；栏宽档位常量 `BAND_TEXT_VP=600` / `BAND_LIST_VP=840` / `BAND_BUTTON_VP=360`。阈值与 `GridRow` 默认断点 `['320vp','600vp','840vp']` 同源 |
| `entry/src/main/ets/util/WindowMetrics.ets` | 单一订阅源：`window.getLastWindow` 首次采样 + `windowSizeChange` + `avoidAreaChange`，一次订阅同时发布 `ui.widthVp` / `ui.breakpoint` / `ui.bottomLiftVp` 到 AppStorage。`EntryAbility.onWindowStageCreate` 启动、`onWindowStageDestroy` 停止 |
| `entry/src/test/ets/test/Breakpoint.test.ets` | 5 条单测覆盖断点纯函数与抬升量判定规则 |

**修改（21）**

| 文件 | 改动要点 |
| --- | --- |
| `view/pages/MainShell.ets` | `Row` + `layoutWeight(1)` 手搓 Tab 栏 → `Tabs`/`TabContent`（lg 走 `.vertical(true).barWidth(96).barMode(BarMode.Scrollable)` 侧边栏，sm/md 走 `barPosition: End` + `barHeight(62+lift)`，两分支都 `.scrollable(false)` 保持不可滑动切页）；11 个全屏路由 `if/else` → `Navigation(pageStack).mode(NavigationMode.Stack).navDestination(this.pageMap)`；删自定义 `ROUTE_TRANSITION`，改用系统标准转场；每个 `NavDestination` 加 `.onWillDisappear(() => Router.notifyReturned())` |
| `view/Router.ets` | 公开 API 签名与语义**全部不变**（38 处调用点零改动），内部改为持有 `NavPathStack`；新增 `attach`/`detach`/`notifyReturned`；删除 `route.name`/`route.param`/`route.stack` 三个 AppStorage 镜像——镜像在 Stack 模式下是主动危险，下层 destination 仍存活会共享同一个 `route.param` |
| `view/RouteStack.ets` | 收敛为「push 决策」算法（栈顶同名替换、pushing MAIN 清栈、深度上限）；`parseRouteStack`/`serializeRouteStack`/`RouteEntry` 随镜像一起删除 |
| `view/components/Ui.ets` | 新增 `ContentBand`（`@Prop maxWidth` + `@BuilderParam content`）：`Row{ Column{content}.width('100%').constraintSize({maxWidth}) }.justifyContent(Center)`。`width` 先给满再由 `constraintSize` 收口——`Column` 默认按内容自适应宽度，而子节点普遍写 `width('100%')`，两边互相等对方定宽会拿到不确定结果 |
| `view/pages/HomePage.ets` | 「我的歌单」`Grid`+`columnsTemplate('1fr 1fr')` → `GridRow({columns:{xs:4,sm:4,md:8,lg:12}, gutter:{x:12,y:14}})` + `GridCol({span:2})`；「每日推荐」md/lg 切同款 `GridRow`、sm 保留横滑；「最近播放」列表套 `ContentBand(840)`；新增 `ui.refreshTick` `@Watch` 钩子 |
| `view/pages/LibraryPage.ets`、`ExplorePage.ets`、`SettingsPage.ets`、`SettingsDetailPage.ets` | 套 840vp 栏宽（前两者另加 `ui.refreshTick` 钩子）。`ExplorePage`/`SettingsDetailPage` 的约束手写在页内而非套 `ContentBand`：这两页内容区靠 `layoutWeight(1)` 撑满剩余高度，需要 `height('100%')` 一路传下去，而 `ContentBand` 高度按内容自适应 |
| `view/pages/LegalDocPage.ets` | 正文套 600vp 栏宽 |
| `view/pages/DisclaimerPage.ets`、`OnboardingPage.ets` | 正文 600vp、按钮 `constraintSize({maxWidth: 360})`、md/lg 下垂直居中；抬升量改读 `ui.bottomLiftVp`。`OnboardingPage` 的约束手写在页内——`ContentBand` 会把 `Swiper` 压塌 |
| `view/pages/NowPlayingPage.ets` | 抬升量 `Theme.bottomBarLift()` → `@StorageProp('ui.bottomLiftVp')` |
| `view/pages/PlaylistDetailPage.ets`、`NeteasePlaylistPage.ets`、`BiliFavPage.ets` | `@StorageLink('route.param')` → `@Prop`，参数由 `pageMap` builder 传入 |
| `view/Theme.ets` | `bottomBarLift()` 保留为指南常量与冷启动 fallback，注释改为说明实际抬升量由 `WindowMetrics` 动态给出 |
| `entryability/EntryAbility.ets` | `onWindowStageCreate` 调 `WindowMetrics.start(this.context)`，`onWindowStageDestroy` 调 `stop()` |
| `view/components/MiniPlayer.ets` | **功能缺陷修复（非本轮计划内）**：`Progress` 原来喂 0..1 比例且不给 `total`，进度条从未正确显示；改为 `value: positionMs, total: durationMs`。取证见 §11.5 |
| `entry/src/test/List.test.ets`、`entry/src/test/ets/test/RouteStack.test.ets` | 注册 `Breakpoint.test`；`RouteStack` 删 2 条、余 4 条按新签名重写 |

> **08-27 phone 复测追加的两处修复**（`MainShell.ets`，均与底部系统导航条区的渲染有关，取证与根因见 §11.6）：① 两个 `Tabs` 分支补 `.backgroundColor(bandColor())`——`Tabs` 容器自身延伸到窗口物理底边，此前该区域透明导致指示器条带回落为应用底色，与 Tab 栏形成 28vp 色差接缝（S1 风险表预见项的兑现）；内层原有的失效色带 `Column`（在 NavBar 内容区里 `expandSafeArea` 不延伸）随此删除。② `pageMap` 的 `NavDestination` 显式 `.backgroundColor(Color.Transparent)`——默认白背景会在深色模式的内容区以下露出白色条带。

---

## 11. 验证证据

### 11.1 静态验证（2026-08-25 首轮 / 08-26 ArkUI 标准组件改造后复跑）

| 项 | 命令 | 首轮结果 | 改造后结果 |
| --- | --- | --- | --- |
| 构建 | `hvigorw.bat assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon`（命令行工具链，非 DevEco 26 Beta2） | **BUILD SUCCESSFUL in 22 s** | **BUILD SUCCESSFUL in 17 s 235 ms** |
| 静态检查 | `codelinter.bat ./entry` | **warn 25 / suggestion 2 / error 0** | **Defects 28；error 0 / warn 26 / suggestion 2** |
| 本地单测 | `hvigorw.bat test --mode module -p module=entry@default -p product=default --no-daemon` | 未运行（基线文档声称 798 pass） | **Tests run: 819, Failure: 0, Error: 0, Pass: 819, Ignore: 0**；行覆盖 60.24%（11135/18485）、函数 53.92%、分支 56.51% |
| 设备侧测试 | `aa test -b moe.ouom.neriplayer -m entry_test -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 300000` | 未运行 | **Tests run: 49, Failure: 10, Error: 10, Pass: 29**，`TestFinished-ResultCode: 0` |
| 图标资源复核 | 纯标准库 PNG 解码器逐像素统计 | 前景层 1024² RGBA，透明 79.81%/不透明 19.03%/过渡带 1.17%；背景层 1024² colorType 2（无 alpha 通道），**distinct colors = 1**，值 `(30,41,58)`；`startIcon.png` alpha 全 255 | 未改动图标资源，不复跑 |

**两套测试是不同的东西，不能混记**：`entry/src/test/`（819 条，`List.test.ets` 注册 162 个 `describe`）是本地单测，由 `hvigorw test` 构建成 testability HAP 后执行，结果落在 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`；`entry/src/ohosTest/`（49 条，模块 `entry_test`）是设备侧测试，须单独 `assembleHap --mode module -p module=entry@ohosTest` + 签名 + 安装后用 `aa test` 跑。**文档此前记的 798 是历史声称值，从未在本机取得过**；819 是本轮首次实测数，两者不可作差解读。

本轮对测试代码的改动是：`RouteStack.test.ets` **删 2 条、余 4 条按新签名重写**（被删的是 `serialize/parse round trips` 与依赖数组语义的那部分——`route.stack` AppStorage 镜像随 `NavPathStack` 迁移一起删除，被测行为不存在了，不是为了让测试通过而删）；**新增 `Breakpoint.test.ets` 5 条**（断点映射、与 `GridRow` 默认阈值同源、宽度缺失不误判为大屏、只有 lg 算宽屏布局、只在有导航指示器时抬升底部控件）。

设备侧 49 条中 20 条失败**全部是实网测试**：`searchesResolvesAndPlaysWithBiliHeaders`、`searchesResolvesAndPlaysIosDirectStream`、`neteaseSongDownloadsCommitsAndReplaysFromCatalog`、`createSessionBuildsScanUrlAndFreshCheckIsWaiting`（两个平台各一次）、`recommendPlaylistsFetchOverRealNetwork`、`userPlaylistsRejectedWhenLoggedOut`、`playlistOverviewFetchesSongsOverRealNetwork`、`anonymousPublicRepoReadWorks`、`missingFileYieldsNullSnapshot`、`anonymousUserCallClassifiesAsTokenExpired`、`invalidBearerTokenClassifiesAsTokenExpired` 等，失败原因均为 `Operation timeout` 或实网返回与断言不符。**没有一条触及本轮改动的 UI / 路由层**，但也因此**不能用它们证明改动无回归**——这 20 条属于「模拟器无外网的既有噪声」，不是本轮引入。

codelinter 从基线 25 增到 26 warn，**新增的一条**是 `Ui.ets` 里新加的 `ContentBand` 命中 `@performance/avoid-overusing-custom-component-check`（建议用 `@Builder` 替代自定义组件）。该规则本轮共命中 **17 处**，其余 16 处是既有的（`Ui.ets` 其余 ×6、`NowPlayingPage` ×2、`SafeModePage` ×2、`LegalDocPage`、`LibraryPage`、`LoadingPage`、`SettingsPage`、`SongRow`、`StatsPage` 各 ×1）——本项目每个页面都是 `@Component`，属既有已接受模式。`ContentBand` 必须是组件而非 `@Builder`：它要接 `@BuilderParam` 承载调用方的子树，`@Builder` 做不到这层嵌套。error 仍为 0。

其余告警规则分布（均为既有）：`hp-arkui-use-local-var-to-replace-state-var` ×6、`hp-arkui-suggest-use-effectkit-blur` ×2（suggestion）、`await-thenable` ×2、`bad-deep-clone-check` ×1。

**2026-08-27 phone 复测轮复跑**（代码在两处色带修复后，见 §11.6）：构建 BUILD SUCCESSFUL（20–21 s）；codelinter **26 warn / 2 suggestion / 0 error，与上表改造后数字完全持平**；本地单测 **819/819 全过**（`test_result.txt` 819 Success / 0 Failure / 0 Error）。

### 11.2 设备实测（2026-08-25 / 08-26）

> **口径声明**：项目 `compatibleSdkVersion` 是 **6.1.1(24)**，但本机可用的 tablet / 2in1 镜像只有 **HarmonyOS 7.0.0 Beta（API 26）**（B1 `pc_all_x86` / B2 `tablet_x86` / B2 `phone_all_x86`，`os.isPublic=false`），仅 phone 有 6.1.1 镜像。因此除 phone 外的结论都属**向上兼容运行**，不能替代目标 API 上的回归。

已完成的形态：

| 形态 | 实例 / 镜像 | 分辨率与密度 | 结论 |
| --- | --- | --- | --- |
| phone | `Pura 90` / `HarmonyOS-6.1.1 phone_all_x86`（**API 24，与目标一致**） | 1320×2848，3.375 px/vp → 391.1×843.9vp | 通过，并暴露出深色模式缺陷（见下） |
| 2in1 | `MateBook Pro` / `HarmonyOS-7.0.0-B1 pc_all_x86` | 3120×2080，1.9 px/vp → 1642×1095vp；应用跑在自由窗口 1100×734vp，最大化 1642×1029vp | 无硬性缺陷，但存在大屏密度问题（见 §8.2） |
| tablet | `MatePad Pro 13` / `HarmonyOS-7.0.0-B2 tablet_x86` | 2880×1920，density 320 → 1440×960vp @ 2.0 px/vp；挖孔 `M1308 0 L 1572 0 V 36 h -264 Z`（顶部居中 264×36px） | 通过；**唯一取得挖孔避让实测**，另有大屏密度问题（见 §8.2） |

已取证的项：

| 项 | 方法 | 结果 |
| --- | --- | --- |
| 沉浸式顶部/底部 | `snapshot_display` + `System.Drawing.Bitmap.GetPixel` 逐点采样 | 状态栏与导航条区域取到的都是应用背景色，无独立色块切割 → `expandSafeArea` 背景层生效 |
| 挖孔区避让（**仅 tablet 可测**） | 同上，采样挖孔矩形内 4 点 + `dumpLayout` 量内容根顶边 | 内容顶 43vp 在挖孔下沿 18vp 之下；挖孔内 4 点全为应用底色，无黑边 |
| 浅色配色 | 同上 | 背景 `(247,247,249)`、卡片面 `(255,255,255)` |
| 深色配色 | 同上 | 背景 `(14,13,18)`、卡片面 `(26,27,32)`；2in1 上系统 `DecorBar` 也跟随深色 `(51,51,51)` |
| 四类布局缺陷 | `uitest dumpLayout` + `tools/.m9/overflow.py`（判据见 `RELEASE_CHECKLIST.md` §2）；`bounds` 为扣除高层窗口后的可见矩形，`origBounds` 为布局矩形，两者都取 | phone 四页、2in1 四页、tablet 六页均无非滚动区溢出/裁剪、无文本重叠；仅横滑卡片与长列表有「允许类」滚动区裁剪 |
| 分层图标落地 | 桌面截图 | 启动器上显示为分层图标，前景居中、无裁切 |
| 底部 Tab 几何 | `dumpLayout` 量 `origBounds` | phone 单格 97.8vp；2in1 窗口态 275vp、最大化 410vp；tablet 360vp |
| 导航指示器避让区实高 | `hidumper -s WindowManagerService -a -a` 读系统窗口矩形 | tablet `SCBGestureNavBar18 [0,1864,2880,56]` → 28vp，与 `BOTTOM_BAR_LIFT_VP` 吻合；2in1 自由窗口内为 0，同一常量成为死区 |
| 应用内法务入口 | tablet 上从「设置 → 隐私与协议」逐个打开 | 「隐私政策」「用户协议」两个入口存在且可打开，`LegalDocPage` 正常渲染（含「草案 · 待作者复核」横幅），返回按钮 40×40vp |

**实测发现并已修复的缺陷（深色模式，指南检查项⑦）**：

切换深色模式后**当前页保持原配色不重绘**，且 `MainShell` 底部导航栏背景**永久停在浅色**——切页也修不回来。

根因是 ArkUI 的最小化更新：不引用 `@State`/`@StorageProp`/`@StorageLink` 的属性表达式在重建时会被跳过。`Theme.isDark()` 读的是 `SettingsRepository`（preferences），不是可观察状态，所以全项目 **27 个文件 482 处**颜色表达式对更新跟踪器**完全不可见**（`Theme.ets` 注释里记作 M7.4 renderer pitfall）。

修复取两层：

1. `MainShell` / `Index` 增加 `resolveDark()`，改读被跟踪成员（`@StorageProp('np.dark_mode')` + `@StorageProp('systemDark')`），让这两处骨架能响应切换；
2. 新增 `entry/src/main/ets/util/AppColorMode.ets`，调 `ApplicationContext.setColorMode(ConfigurationConstant.ColorMode)`（`@since 11`）。这是应用级深色覆写的标准做法：它触发一次**配置变更**，整棵组件树重建，482 处 `Theme.isDark()` 一次性重新求值，系统弹窗与 `sys.color.*` 资源也跟到同一档配色——不需要逐个改调用点签名。`EntryAbility.onCreate` 冷启动即调一次，`SettingsPage.cycleDarkMode()` 切换时调一次（`'auto'` → `COLOR_MODE_NOT_SET`，即交还系统）。

修复后在 phone、2in1、tablet 三个形态上复测，两处缺陷均消失（证据 `tools/.m9/va_phone_dark_fixed.jpeg`、`w6_2in1_dark.jpeg`、`tb_dm2.jpeg`）。

### 11.3 tablet 形态的启动阻塞（已定位根因，2026-08-26 由用户解除）

这一节保留排查结论，因为下次换机或会话过期还会再遇到。

镜像**在盘且签名校验全部通过**（`D:/HarmonyOS/Tools/Sdk/system-image/HarmonyOS-7.0.0-B2/tablet_x86`，`finish check image ... result 0`）。卡点在**宿主侧的模拟器启动链路**，排查结论如下：

- 本机存在**两份** `Emulator.exe`：DevEco 内置的 `.../DevEco Studio/tools/emulator/Emulator.exe`，以及命令行工具链的 `Tools/command-line-tools/emulator/Emulator.exe`（`Emulator.bat` 包装，版本 26.0.0.300）。
- **CLT 那份能把 guest 跑起来但检测不到启动完成**：guest 侧 33 秒就写出 `bootevent.launcher.ready` / `All boot events are fired, boot complete now` / `usual.event.BOOT_COMPLETED`，但宿主从不发 `QemuManager::EmitGuestOSBootComplete`，于是开机动画不散、也不建 hdc 端口转发，`hdc list targets` 恒为 `[Empty]`（宿主上无任何该进程持有的监听端口）。补 `-hdcPort 10500` 无效——hdc 连接是在 BootComplete **之后**才建立的。
- **DevEco 那份被华为账号门禁挡住**：日志缺失 `SnUtil.cpp(CheckLogin) The user has logged in.` 一行，直接落到 `can not read uuid file` → `can not read sn` → 弹窗「模拟器启动失败 / 请在 DevEco Studio 中登录华为账号，并从设备管理中启动模拟器」。
- 已排除的误导项：① `Commit charge is not enough!` 只在同时跑两台模拟器时出现，与此无关；② trace 管道**不是**原因——`-t trace_<pid>_commandPipe` 能让日志打出正确管道名并 `connect successed`，但 `CheckLogin` 依旧不出现；③ `hdcDisable=1`（`usb_config.c`）说的是 USB hdc，模拟器走 TCP，属正常；④ 8-25 13:20–13:27 三台实例都成功启动过，日志里都有 `CheckLogin: The user has logged in.` → 判定为**账号会话过期**，不是参数写错。

结论：**tablet 形态的验证前置条件是在 DevEco Studio 内登录华为账号并从设备管理器启动实例**，这一步需要用户凭据，无法在命令行侧绕过。2026-08-26 用户按此操作后实例正常上线（`hdc list targets` 返回 `127.0.0.1:5555`），本轮 tablet 证据即由此取得。

### 11.4 本轮仍未取得的证据（不得表述为已验证）

| 项 | 原因 |
| --- | --- |
| **整改后的 2in1 复测** | phone 复测已于 2026-08-27 完成（§11.6，含两处色带缺陷的发现与修复），**剩 2in1 一档**：它是 S2 动态避让的核心验收形态（自由窗口避让区 0 → 期望抬升量 28vp → 0），也是唯一能在运行时拖动窗口宽度做跨断点切换的形态。tablet 已验证侧边栏分支、phone 已验证底部栏分支，`Tabs` 两个分支的设备证据齐了，缺的只有 2in1 上的动态换栏 |
| 断点切换（1100vp ↔ 1642vp 拖动） | 需 2in1。跨断点时 `Tabs` 会走另一个分支重建，四个 Tab 页的 `@State` 丢一次——这个行为变更**未实测** |
| 目标 API 24 上的 tablet / 2in1 回归 | 本机无 6.1.1 的 tablet / pc 镜像，只有 phone 有；这两个形态的结论都是 API 26 Beta（`os.isPublic=false`）上的向上兼容运行 |
| `mcp__deveco-mcp__check` 静态诊断 | 计划里列为验证步骤 3，**无法执行**：相对路径报「文件不存在」，绝对路径报 `no diagnostics within 20000ms from LSP`。该工具对本工程始终不可用，改用 `codelinter` + 构建期 ArkTS 严格模式检查替代 |
| 侧滑返回手势 | **被系统占用，无法测**。左边缘（`swipe 2 900 → 900 900`）与右边缘（`swipe 2878 900 → 2100 900`）都会拉出平台**侧边应用栏（Dock）**；截图显示 Dock 浮层覆盖在 `NowPlayingPage` 之上，`hidumper -s WindowManagerService` 确认 `neriplayer0` 仍是前台（ZOrd 102）、`SCBGestureDock42` ZOrd 1900。要测须先在系统设置里关掉侧边应用栏。**系统返回键路径已验证**（见 §11.5），侧滑走的是同一个 `onWillDisappear` 钩子，但这属推断不属实测 |
| 权限变更的设备冒烟 | AGENTS.md 要求权限改动做设备验证；上一轮删除了一个权限声明，**未做设备冒烟**。残余风险评估为低：被删的是从未申请、也无 `requestPermissionsFromUser` 调用的 user_grant 权限，本地音频路径走 Picker scoped access 不依赖它。仍应复跑一次「资料库→导入本地音乐」 |
| 播放主路径（选歌 → 播放 → 播放页 → 通知栏） | **部分补齐**：本轮为定位 `MiniPlayer` 进度条缺陷实际起播过（见 §11.5），`NowPlayingPage` 也打开并返回过。但通知栏/锁屏控制、`QueueSheet`/`LyricShareSheet` 的底部避让仍**无实测** |
| 启动页时长（0.3–0.8 s 目标） | 未计时 |
| 状态栏左右半区对比度 ≥1.9、正文对比度 >4.5:1 | 已确认系统栏显示应用背景色，但**未做左右半区分区对比度计算** |
| 折叠外屏 346vp | 传感器状态无法经 hdc 注入 |
| 横屏布局 | `module.json5` 无 orientation 锁定，跟随系统旋转，未系统走查 |
| 屏幕朗读听读效果 | 只静态核对了 `accessibilityText`，未开朗读实听 |
| 1.75× 字号档 | 该档需开「关怀模式」，而那个设置页会同时开启星盾防诈与骚扰拦截（涉及网络、通讯录权限、通话录音），**已放弃**。改用「特大字号 + 显示大小缩放 3」组合达到**等效 1.8125×**（超过目标档），结论见 §11.5 |

### 11.5 ArkUI 标准组件改造的设备验证（2026-08-26，tablet）

改造内容与四个阶段的对应关系：

| 阶段 | 改法 | 新增/改动文件 |
| --- | --- | --- |
| S1 顶层导航 | 手搓 `Row` + `layoutWeight(1)` → `Tabs`/`TabContent`；lg 断点 `.vertical(true).barWidth(96)` 侧边栏 | `view/pages/MainShell.ets` |
| S2 动态避让 | 硬编码 `BOTTOM_BAR_LIFT_VP = 28` → `TYPE_NAVIGATION_INDICATOR` 避让区求值，经 AppStorage `ui.bottomLiftVp` 发布 | 新增 `util/WindowMetrics.ets`、`util/Breakpoint.ets`；4 处消费点改 `@StorageProp` |
| S3 断点与栏宽 | `Grid`+`columnsTemplate('1fr 1fr')` → `GridRow`/`GridCol`；新增 `ContentBand` 栏宽容器（正文 600vp / 列表 840vp / 按钮 360vp） | `components/Ui.ets`、`HomePage`、`LibraryPage`、`ExplorePage`、`SettingsPage`、`SettingsDetailPage`、`LegalDocPage`、`DisclaimerPage`、`OnboardingPage` |
| S4 路由 | 自研 `Router` 静态类 + 11 个 `if/else` → `Navigation`/`NavDestination` + `NavPathStack`；删 `route.name`/`route.param`/`route.stack` 三个 AppStorage 镜像 | `view/Router.ets`、`view/RouteStack.ets`、`MainShell.ets`；4 个读 param 的页面改 `@Prop` |

`Router` 的公开 API 签名与语义全部不变，因此全项目 **38 处 `Router.push`/`pop` 调用点一行都没改**。

已取得的验证：

| 项 | 方法 | 结果 |
| --- | --- | --- |
| 侧边导航栏几何（S1 验收点） | `dumpLayout` 量四个标签的 `bounds` | 四个标签中心全部 cx=**96px**，栏宽 96vp 固定；标签文字 `'资料库'` 在 1.81× 字号下宽 116px，仍在 240px 栏内不溢出 |
| 动态抬升量（S2 验收点，tablet 侧） | `hidumper -s WindowManagerService -a '-a'` + `dumpLayout` | `SCBGestureNavBar18 [0,1864,2880,56]` → 28vp；四个 Tab 页滚动容器底边实测 y=1864px = **932vp**，与避让区上沿重合。安全区色带层实测 `[0,1684,2880,1864]` = 高 **90vp** = `TAB_BAR_CONTENT_VP(62) + lift(28)`，宽屏取 `Theme.background()` 与页面同色，视觉不可见 |
| 栏宽约束（S3 验收点） | `dumpLayout` 量各页内容带宽度 | 设置/资料库/探索/首页列表区 = **840.0vp** 居中；法务页 = **600.0vp**；按钮 = **360.0vp**。逐条数字见 §8.2 |
| 网格分列（S3 验收点） | 同上 | 首页「我的歌单」`GridRow` lg 12 列 / `GridCol span 2` → **每行 6 张**，实测单卡 208.5vp、gutter 12vp；网格保持全宽 1316vp，不被同页的 840vp 列表约束波及 |
| 返回栈（S4 风险点：是否双弹） | 隐私政策全屏页 → `uitest uiInput keyEvent Back` → `dumpLayout` | **一次按键退一层**，落回设置 Tab（`TITLE` 从 `'隐私政策'` 变回 Tab 骨架），未越级弹到根。`Index.onBackPress` 与 `Navigation` 没有重复消费 |
| Tab 页刷新语义（S4 行为变更） | 切 Tab / 从全屏页返回后 `dumpLayout` 比对内容 | 数据在，未出现空列表。`ui.refreshTick` + `@Watch` 钩子生效（三个数据页各加 4 行，用已有的 `np.default_start_tab` 过滤当前页） |
| 四类布局缺陷（改后全页复测） | `uitest dumpLayout` + `tools/.m9/overflow.py` | 7 个页面全部通过，唯一差异是 `MiniPlayer` 进度条的 uitest 导出误报，见 §8.2 表下说明 |
| 字号回归（§3.1 已修 3 处缺陷不得回归） | 系统设置拉到「特大字号 + 显示大小缩放 3」，实测 px/vp = **2.5** → 等效字号 **1.8125×**、逻辑宽 1152vp（仍 lg 档） | 全部**未回归**：探索页三个平台 chip 仍在一行（网易云 `[593..744]`、Bilibili `[909..1045]`、YouTube Music `[1209..1547]`）；网易云歌单三按钮仍在一行（全部播放 `[356..626]`、随机播放 `[647..917]`、导入 `[939..1116]`）；歌曲序号角标 `'1' [151,627,196,687]` 与标题起点 x≥233 无重叠。判定：网易云歌单页 0/0/0/0，首页 0/1/6/0（6 处滚动区裁剪是 `Scroll` 视口边缘的正常截断，`GridRow b=[293,1354,2843,1864] h=510 obh=2893`），资料库 0/1/0/0，设置 0/1/1/0——非滚动区那 1 处全部是进度条误报 |
| 内存（S4 风险点：四页常驻） | `hidumper --mem <pid>` | tablet 实测 Pss **378 MB**（dev 244 MB / native heap 67 MB / ark ts heap 14 MB）。**不能与 §4 的 127–151 MB 基线对比**——那是 phone 形态、更小的窗口与位图。同形态对比需 phone 复测，属未取得的证据 |

**改造过程中发现并修复的一个功能缺陷（不在计划范围内）**：`MiniPlayer` 的进度条**从来没有正确显示过**。原代码写 `Progress({ value: positionMs / durationMs, type: Linear })`——喂进去的是 0..1 的比例，而 `total` 未指定。`progress.d.ts` 只声明了 `total?: number`，没有文档化的默认值；项目内正确用法在 `DownloadsPage.ets:172`（`value: percentage(), total: 100`）。实测取证：播到 11% 时对 x=20…2860 整条采样得到的全是轨道色 `(209,210,214)`，无任何填充。已改为直接把毫秒喂给 `value`/`total`（单位自洽）。修复后原子化 dump+截图交叉验证：节点值 `'35727.000000'`（ms），曲目时长 2:57 = 177s → 应填充 20.2%；对 y=80 整条扫描找到颜色跃变边界在 x=584（进度条横跨 x=18..2862）→ 实际填充 **19.9%**。**这是设备取证顺带发现的，与本轮四个阶段无关，但属于用户可见缺陷，故一并修掉。**

### 11.6 phone 形态复测（2026-08-27）

唯一在**目标 API 24** 上运行的形态，也是「窄屏布局逐像素不变」承诺的唯一验证场；tablet 轮没跑过的**底部栏分支（sm/md）**在这里首次上设备。设备 `Pura 90` 模拟器（1320×2848，3.375 px/vp → 391.1×843.9vp），证据前缀 `tools/.m9/pa*`。

本轮**发现并修复了两个真实缺陷**（都是 tablet 轮漏掉的——tablet 色带取 `Theme.background()` 与页面同色、视觉不可见，所以接缝在那里不显形）：

1. **Tab 栏底部 28vp 色差接缝**（S1 风险表「Tabs 安全区色带」条目的兑现）。原实现把 surface 色带 `Column` 放在 `Navigation > NavBarContent` 内层并依赖 `expandSafeArea` 延伸——实测 **Navigation 的 NavBar 内容区自带安全区裁剪，内层子节点的 `expandSafeArea` 不会延伸进系统导航条**（同层级的 Index 沉浸背景层就能正常延伸，对照见下）。结果指示器条带回落为应用底色：深色下 Tab 栏 `(26,27,32)`、条带 `(14,13,18)`，与 08-25 基线「surface 一直铺到屏幕底」出现 28vp 接缝。修复过程中先试了「色带提升到 Navigation 外层」——**同样不延伸**（说明不是层级深度问题，而是 Navigation 之外的普通 Stack 子层也只在特定条件下延伸）；最终利用布局 dump 里的另一个事实：**`Tabs` 容器自身天然延伸到窗口物理底边**（bounds 到 2848，无需任何 expandSafeArea），给它设 `.backgroundColor(bandColor())` 后条带跟随 Tab 栏同色。四个 Tab 页根节点都不透明，surface 只在条带处可见。修复后深浅两档底部 2500→2840px 采样全程等于 `Theme.surface`（`(26,27,32)` / `(255,255,255)`），与改造前基线一致（`pa_home_fix2.jpeg`、`pa_light.jpeg` vs `va_phone_dark_fixed.jpeg`）。
2. **NavDestination 默认白背景在深色下露边**。`pageMap` 的 `NavDestination` 未设背景，默认白色；destination 内容止于安全区底边（2754px），系统导航条区那条带渲染为 `(255,255,255)`——深色法务页底部一截刺眼白边（`pa_privacy_dark.jpeg`）。最初按路由补同色背景，但页面根背景是**动态取色**的（`Theme.surfaceVariant` 读 palette），单一颜色永远对不齐所有页面；最终改为 `.backgroundColor(Color.Transparent)`，条带回落到 Index 沉浸层（应用底色），与改造前全屏路由的行为一致。修复后深色条带 `(14,13,18)` vs 正文 palette 底 `(16,14,15)`（ΔRGB≤3，视觉连续）、浅色条带与正文完全同色 `(247,245,246)`（`pa_privacy_dark_fix2.jpeg`、`pa_privacy_light.jpeg`）。

其余验收项（全部通过）：

| 项 | 方法 | 结果 |
| --- | --- | --- |
| 结构与底部栏分支 | `dumpLayout` | `Navigation(NavBar)>Tabs>Swiper+TabContent+TabBar` 齐备；四格各 **97.8vp**（[0-330]/[330-660]/[660-990]/[990-1320]px），与改造前基线逐像素一致——「窄屏布局不变」承诺成立；图标 21.9×22.2vp≈22vp |
| 动态抬升量（S2，phone 侧） | `hidumper -s WindowManagerService -a '-a'` + dump 几何 | `SCBGestureNavBar16 [0,2754,1320,94]` → 94px = **27.85vp ≈ 28**；TabBar 高 90.1vp = 62+28，底边 y=2754 与指示器上沿**精确重合**；`ui.bottomLiftVp` 判定规则（有指示器给 28）在唯一目标 API 形态上成立 |
| 四类布局缺陷（修复后构建） | `uitest dumpLayout` + `overflow.py` | 4 个 Tab 页、隐私政策、用户协议、播放设置详情、调试页、播放页、**免责声明、引导页**（清数据重走首启）全部 0 溢出 / 0 非滚动裁剪 / 0 重叠；滚动区允许类裁剪 0–3 处（视口边缘正常截断） |
| 密度（S3，phone 侧） | dump 几何 | 首页「我的歌单」`GridRow` xs/sm 4 列 + span 2 → **每行 2 卡、单卡 173.9vp**（与旧 `1fr 1fr` 视觉等价，新建歌单实测）；法务正文 359.1vp、设置行文本 267.3vp（均受屏宽 391vp 限制，600/840 栏宽在窄屏不触发——符合设计）；免责声明/引导按钮 **352vp / 306vp ≤ 360** 按钮约束生效 |
| 返回栈（S4 风险点） | `uitest uiInput keyEvent Back` 逐页 | 隐私政策、播放设置详情、调试页、网易云歌单、播放页（MiniPlayer 双击进入）**单次返回单层**，无一例双弹；`Index.onBackPress` 与 `Navigation` 没有重复消费；根 Tab 上再按返回退出应用（系统标准行为）。注：本项目**没有可达的两层 Navigation 链**（扫码登录是页内 Sheet、`SETTING_DEBUG` 详情段无入口），最深就是 Tabs→destination 一层 |
| 深浅色与 auto | `snapshot_display` + `px.ps1` | 深色背景 `(14,13,18)`/底部栏 `(26,27,32)`、浅色 `(247,247,249)`/`(255,255,255)`，含修复后条带全部无缝；`auto` 档正确交还系统（系统当前浅色 → 应用浅色） |
| 字号回归（§3.1 三缺陷） | 系统设置 特大字号(1.45×) 与 特大+显示缩放3(等效 1.8125×) | 探索页三平台 chip 换行收纳在屏内（wrap 是当初修复行为，原缺陷是溢出屏外）；网易云歌单三按钮 1.45× 两行、1.8125× 纵排，全部在屏内；`SongRow` 序号角标与标题间隙 56px 无重叠；三档字号下首页/探索/歌单 overflow 全 0 |
| 内存（S4 风险点：四页常驻） | `hidumper --mem`（冷启 + 6 轮全页导航） | 冷启 220 MB → 首轮 256 MB → 6 轮平台期 **257–264 MB，无单调增长**。比 §4 的 127–151 MB 基线高约 110 MB：S4 四页常驻的代价确实存在，但两次测量的数据量不同（本轮网易云实网数据 + 封面在缓存），**不能作严格对比**；无泄漏趋势与 08-24 轮结论一致 |
| 静态/单测基线（含上述两处修复） | `codelinter` / `hvigorw test` | codelinter **26 warn / 2 suggestion / 0 error**（与 08-26 基线持平）；本地单测 **819/819 全过**（`test_result.txt` 819 Success / 0 Failure / 0 Error）；构建 BUILD SUCCESSFUL |

**一个未复现的观察项**：一次在「应用后台 → 系统改显示密度（1.0→3.0）→ aa start 恢复」的边缘场景下，歌单页单次 Back 直接退到桌面。同一路径立即重试（冷启 → 开歌单 → Back）**正常单层返回**，常规流程未能复现；疑与配置变更重建 Navigation 状态有关，登记待观察，不列为缺陷。

---

## 12. 遗留项与后续待办

按优先级排列。前三项是上架前必须处理的。

1. **法务文案定稿并同步 AGC**。当前是我起草的 `v1.0.0-draft`，两份文档都带「草案 · 待作者复核」横幅。上架前须由作者定稿、填写生效日期，并在 AppGallery Connect 上传**同一版本**（应用内与 AGC 不一致是驳回项）。
2. **重大政策变更重新征得同意**：文案里已承诺，代码里**未实现**。现有 `KEY_DISCLAIMER_ACCEPTED` 是布尔标记，改政策版本号不会重新弹窗。建议改为存已同意的版本号，与当前版本比对。
3. **大屏三档响应式布局**（§8.2）——**已整改，tablet 与 phone 两档已有回归证据，剩 2in1 一档**。整改内容见 §11.5/§11.6：`Tabs` 侧边导航栏、`GridRow`/`GridCol` 分列、`ContentBand` 栏宽三档、`WindowMetrics` 断点发布。tablet（lg/侧边栏分支）逐条数字已复测（Tab 单格 360vp → 侧栏固定 96vp；设置行文本 1412vp → 716vp；法务正文 1408vp → 568vp；按钮 1296vp → 360vp；竖向空白 555.5vp → 280.5vp）；phone（sm/md/底部栏分支、唯一 API 24 形态）于 08-27 复测通过（§11.6，含两处色带缺陷修复）。**剩余待办只有 2in1**：自由窗口避让区 0 → 抬升量应为 0，以及 1100vp ↔ 840vp ↔ 1642vp 拖动跨断点换栏。在此之前，「三档响应式布局已验证」的表述应限定为 tablet + phone 两档。
4. **`BOTTOM_BAR_LIFT_VP` 动态求值**——**已实现，tablet 与 phone 侧已验证，2in1 侧未验证**。新增 `util/WindowMetrics.ets` 订阅 `windowSizeChange` + `avoidAreaChange`，按 `TYPE_NAVIGATION_INDICATOR` 的 `bottomRect.height > 0` 决定给 `Theme.bottomBarLift()`（28）还是 0，经 AppStorage `ui.bottomLiftVp` 发布，4 个消费点改 `@StorageProp`（用 `@StorageProp` 而非直接调函数，是因为 ArkUI 最小化更新会跳过不引用可观察状态的表达式——与深色模式那个缺陷同一个坑）。tablet 实测仍取到 28vp、滚动容器底边落在 932vp 与避让区上沿重合；phone（API 24）实测避让区 94px = 27.85vp、Tab 底边与指示器上沿精确重合（§11.6）。**2in1 上「避让区 0 → 抬升 0、死区消失」这个核心验收点尚未取得实测**。`Theme.bottomBarLift()` 保留为指南常量与冷启动 fallback。
5. **全屏路由页的列表行没有栏宽约束**（本轮新发现）。整改表只覆盖了 4 个 Tab 页与 3 个正文页；歌单详情（`NeteasePlaylistPage`）歌曲行副标题 tablet 实测宽 **1244vp**，与整改前的设置行（1412vp）是同一类密度问题。同类未改的还有 `PlaylistDetailPage`、`BiliFavPage`、`RecentPage`、`DownloadsPage`、`StatsPage`。改法与已改页面一致（套 `ContentBand(840)`），需逐页复测，本轮未纳入批准范围。
6. **`NavigationMode.Stack` 下全屏页会盖住侧边栏**，导致从 Tab 页 push 到全屏页时内容中心从 1536px 移到 1440px（**48vp 的横向位移**）。这是 Stack 模式的固有行为（destination 铺满整个 `Navigation` 区域，包括 navBar 占的 96vp），不是缺陷；记录在此是因为它在大屏上是可感知的视觉跳动。若要消除，须让全屏页也留出侧栏宽度，或改用 Split 模式——后者与本项目 navBar 承载整个 Tab 骨架的结构不匹配（见计划的「明确不做」）。
7. **半模态面板底部避让未抬到 28vp**：`NowPlayingPage` 的 `QueueSheet`（`height('62%')` + `position({x:0, y:'38%'})`）与 `LyricShareSheet` 本轮未改。这两个是页内浮层而非底部固定控件，指南条款的适用性存疑，但其内部底部按钮距导航条的实际间距**未测**。另注意 `RELEASE_CHECKLIST.md` §3.1 的结论——`.position()` 的百分比值在字体缩放下不稳定，这两个面板正在用百分比定位。
8. **可滚动内容无法延伸到导航条下方**：非全屏布局的固有限制。指南把「可滚动内容延伸到导航条下」列为不需要局部避让的情形（即允许延伸），本项目做不到（滚动容器止于安全区）。这是方案一的已知代价，视觉上不违规，但不是最沉浸的形态。若将来要做，须整体切换到方案二并重做 19 个页面的避让。
9. **键鼠支持**：无 `onHover`/`onMouse`/快捷键。若保留 2in1 投放则为强制项。
10. **触控目标 40vp → 48vp**：约 30 个控件在 40–48vp 区间，满足硬性下限、未达推荐值。非驳回项，但审核可能提示。
11. **第三方音乐源条款风险**（本文档范围外，但优先级最高）：`RELEASE_CHECKLIST.md` §5.3 的结论仍然成立且未变——面向公开市场发布需剥离或降级三平台取流能力。**本轮所有 UI 与合规整改都不改变这个结论**：设计规范全部合格也不能让一个调用非公开接口的客户端通过审核。
