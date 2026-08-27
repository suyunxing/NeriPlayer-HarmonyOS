# NeriPlayer HarmonyOS 发布矩阵与合规清单（M9.3）

> 2026-08-24 编制。执行者：ZCode agent。本清单是发布门槛的**当前事实快照**：已验证项附证据，未验证项如实标注，不把历史验证当当前能力（AGENTS.md 事实优先级约定）。消费者：`PORTING_EXECUTION_PLAN.md` §6 M9.3、`FEATURE_MATRIX.md`。
>
> **2026-08-25 修订**：按少数派《鸿蒙上架指南》第一章完成设计/交互/生态规范自查与整改，源码已变更。受影响章节：§5.1（权限表原「全部 normal 级」的表述**是错的**，且 READ_AUDIO 已删除）、§5.5（首启弹窗拒绝路径与法务页已补齐）、§7（拆为 7.1 M9.3 门禁 / 7.2 本轮，798 pass 对当前源码降级为「待复核」）。逐条自查记录见 **`UX_COMPLIANCE_AUDIT.md`**。
>
> **2026-08-26 修订**：完成 phone / 2in1 / tablet 三形态设备验证。受影响章节：§1（tablet 与 2in1 由「阻塞：镜像不在盘」改为已回归，并明确这两档跑的是 API 26 Beta 而非目标 6.1.1(24)）、§7.2（UI 表现由「全部未验证」改为已实测，并记入实测发现并修复的 1 处深色模式缺陷、11 条大屏密度遗留，新增文件数 9 → 10）。
>
> **2026-08-26 第二次修订（ArkUI 标准组件改造轮）**：把手搓的顶层导航、硬编码避让量、写死列数的网格、自研路由分别换成 `Tabs`/`TabContent`（大屏 `.vertical(true)` 侧边栏）、`TYPE_NAVIGATION_INDICATOR` 动态避让、`GridRow`/`GridCol`、`Navigation`/`NavDestination` + `NavPathStack`，§8.2 登记的 11 条大屏密度问题全部整改。受影响章节：§1（tablet 行改后复测通过；phone 与 2in1 的**改后**回归转为未验证，断点切换结论待 2in1）、§5.5（「大屏三档响应式布局为未完成的强制项」→ 已完成）、新增 §7.3（本轮构建/静态/单测/设备数字，含首次实测到的本地单测基线 819 pass 与设备侧 49 中 29 pass）。逐条记录见 `UX_COMPLIANCE_AUDIT.md` §10.2、§11.5。
>
> **2026-08-27 修订（phone 复测轮）**：phone（唯一 API 24 形态）改后复测完成，`Tabs` 底部栏分支首次上设备即发现并修复两处底部导航条区渲染缺陷（指示器条带接缝与 NavDestination 深色白边，均为 `MainShell.ets` 行级改动），其余验收项全过；静态与单测基线复跑持平（codelinter 26 warn / 2 suggestion / 0 error，本地单测 819/819）。受影响章节：§1（phone 行改后复测通过）、§7.3（补 phone 轮数字）。**仍待 2in1 一档**（S2 动态避让核心验收 + 跨断点换栏）。记录见 `UX_COMPLIANCE_AUDIT.md` §11.6。

## 1. 设备矩阵与布局回归

密度换算用应用内已知 40vp 控件（返回按钮 `.width(40).height(40)`）实测像素反推，不依赖 `param get`（模拟器上 `const.display.density` 等键均 errNum 1002 不可读）。

| 形态 | 环境 | 逻辑宽度 | 状态 | 证据/说明 |
| --- | --- | --- | --- | --- |
| phone | Pura 90 模拟器（1320×2848，3.375 px/vp，API 24） | 391 vp（**SM 断点**） | 已回归（2026-08-24）；**ArkUI 改造后已复测（2026-08-27）** | 全页走查 × 字号 1.0/1.45/1.75 三档，溢出 0 / 重叠 0（§2、§3.1）。改造后复测：底部 `Tabs` 分支首次上设备，Tab 单格 97.8 vp 与改造前逐像素一致；首启/四 Tab/法务/详情全页四类缺陷 0；避让区 27.85 vp、Tab 底边与指示器重合；返回栈无一次双弹；内存 6 轮平台期 257–264 MB 无泄漏。**复测发现并修复两处底部条带缺陷**（指示器区接缝 + NavDestination 深色白边，见 §7.3）。注：行内旧值「377 vp（MD 断点）」系 08-24 时的另一份模拟器参数（1320×2856 @3.5），按当时阈值判档亦应为 SM，原文档笔误 |
| foldable（展开内屏） | Mate X7 模拟器（2210×2416，3.125 px/vp，API 24） | **707 vp（LG 断点）** | 已回归（2026-08-24） | 17 页 `dumpLayout` 度量，非滚动区溢出 0 / 裁剪 0 / 文本重叠 0（§2） |
| foldable（折叠外屏） | 同实例第二显示（1080×2444） | 346 vp | **未验证** | 折叠态由 Posture/Hall 传感器驱动（DMS 已订阅），仅模拟器 GUI 可切换；`hidumper -s DisplayManagerService` 无折叠开关参数，hdc 无法注入 → 无法在本自动化链路内走查 |
| tablet | MatePad Pro 13 模拟器（2880×1920，density 320 → 2.0 px/vp，**API 26 / OpenHarmony-7.0.0.32 Beta**） | 1440 vp | 已回归（2026-08-26）；**ArkUI 改造后已复测** | 6 页 `dumpLayout` 度量，非滚动区溢出 0 / 裁剪 0 / 文本重叠 0；深色模式通过；**挖孔避让实测通过**（本机唯一带挖孔形态）。改造后 7 页复测四类缺陷仍全 0，侧边导航栏固定 96 vp、列表栏宽 840 vp、正文栏宽 600 vp、底部抬升 28 vp。逐项见 `UX_COMPLIANCE_AUDIT.md` §8.2、§11.2、§11.5 |
| 2in1（PC 平板形态） | MateBook Pro 模拟器（3120×2080，1.9 px/vp，**API 26 / HarmonyOS 7.0.0-B1 Beta**） | 自由窗口 1100 vp，最大化 1642 vp | 已回归（2026-08-25）；**ArkUI 改造后未复测** | 5 组 `dumpLayout` 度量（含最大化态），四类缺陷全 0；深色模式通过（系统 `DecorBar` 跟随）。改造后**S2 的核心验收点（自由窗口避让区 0 → 抬升量 0，死区消失）与 1100 vp ↔ 1642 vp 断点切换均未实测**。逐项见 `UX_COMPLIANCE_AUDIT.md` §8.2 |
| 真机（物理手机/平板） | 无设备 | — | 未验证 | 全部设备证据来自 x86 模拟器；上架前必须真机回归（尤其签名/性能/蓝牙 AVRCP） |

**断点切换（2026-08-26 ArkUI 改造引入的新回归项）**：改造后布局按 `ui.breakpoint`（`sm`/`md`/`lg`，阈值 600/840 vp，与 `GridRow` 默认断点 `['320vp','600vp','840vp']` 同源）分三档，且 `lg` 与 `sm/md` 走 `Tabs` 的**两个不同分支**（侧边栏 / 底部栏），跨断点会重建子树、四个 Tab 页的 `@State` 丢一次（靠 `ui.refreshTick` 重载）。当前证据只覆盖**静态落在某一档**的情形：tablet 恒为 `lg`（1440 vp）、phone 恒为 `sm`（391 vp，两个分支各有一档实测）。**动态跨档切换未验证** —— 唯一能在运行时改窗口宽度的形态是 2in1（自由窗口 1100 vp ↔ 最大化 1642 vp，两侧都在 `lg`，需手动缩窗到 840 vp 以下才能触发换栏），该形态改造后尚未启动复测。

> **2026-08-26 更正**：上面 tablet / 2in1 两行原记为「阻塞：镜像不在盘」，该说法**已被证伪**——镜像现已在盘并通过签名校验（`Tools/Sdk/system-image/HarmonyOS-7.0.0-B1/pc_all_x86`、`HarmonyOS-7.0.0-B2/tablet_x86`）。同时须明确一个口径差异：**这两个形态跑的是 API 26 / HarmonyOS 7.0.0 Beta（`os.isPublic=false`），不是项目目标的 6.1.1(24)**。本机**没有任何 6.1.1 的 tablet / pc 镜像**，`AppData/Local/Huawei/Emulator/deployed/` 下那两个 6.1.1 实例指向的镜像路径不存在。因此只有 phone 一档是在目标 API 上验证的，tablet/2in1 的结论属**向上兼容运行**，不能替代目标 API 回归——该缺口已登记在 `UX_COMPLIANCE_AUDIT.md` §11.4。
>
> tablet 实例的启动另有一道门禁：命令行 `Emulator.bat -start` 能把 guest 跑起来但检测不到启动完成（不发 `EmitGuestOSBootComplete`，因此不建 hdc 端口转发）；DevEco 内置的那份 `Emulator.exe` 则要求**华为账号处于登录态**（日志缺 `SnUtil.cpp(CheckLogin) The user has logged in.` 即落到 `can not read uuid file` 并弹「请在 DevEco Studio 中登录华为账号」）。可行路径只有：在 DevEco Studio 登录账号 → 从设备管理器启动实例。排查全过程见 `UX_COMPLIANCE_AUDIT.md` §11.3。

镜像获取的历史记录（2026-08-24 时的判断，保留以备复查）：DevEco 6.1.1(24) 镜像库**确有** Foldable/Tablet/2in1 设备型（`Emulator.bat -help` 列出 `Phone | Foldable | WideFold | TripleFold | Tablet | 2in1 | 2in1 Foldable | Wearable | WearableKid | TV`），四个 API 24 实例也都已创建；当时的障碍是本机只下载了 `phone_all_x86` 一份镜像，而命令行镜像管理器在无 GUI 会话下**静默失效**：

- `Emulator.bat -imageList [-deviceType Phone] [-downloaded true]` → 退出码 0、**零输出**，连已在盘的 phone 镜像都不列出；
- `Emulator.bat -install -deviceType 2in1 -osVersion "HarmonyOS 6.1.1(24)" -force`（`-license accept` 已先执行成功）→ 退出码 0、零输出、镜像目录无变化。

即"查不到/装不上"是工具链行为，不是镜像不存在。Mate X7 之所以能跑，是因为 foldable 复用 `phone_all_x86`。**该阻塞已于 2026-08-25/26 通过在 DevEco GUI 里下载 Beta 镜像解除**，但下到的是 7.0.0 Beta 而非 6.1.1，口径见上方更正说明。

横竖屏：播放页/主界面未声明固定方向，竖屏为主；横屏适配未系统走查（`module.json5` 无 orientation 锁定，跟随系统旋转，未验证横屏布局质量）——**未验证项**。

## 2. 布局回归记录（2026-08-24，M9.3）

方法不是看截图，而是**度量**：`hdc shell uitest dumpLayout` 取每页布局树，再按四类缺陷判定。判定依据 `bounds`（裁剪后可见矩形）与 `origBounds`（布局矩形）的区别：

1. **非滚动区溢出屏幕**：`origBounds` 越出根节点宽度或左边界为负 —— 元素被排到屏幕外，滚动也到不了（真实缺陷）；
2. **非滚动区被裁剪**：`origBounds` 比 `bounds` 大 >2px 且不在 Scroll/List/Grid/Swiper/WaterFlow 内 —— 内容被切掉；
3. **滚动区裁剪**：同上但在滚动容器内 —— 允许，靠滚动到达；
4. **文本重叠**：两个 `Text` 叶子的可见矩形相交 >2px —— 对应官方"组件不得叠加"要求。

屏宽取自根节点 `bounds`，不写死 1320，因此同一套判据可直接跑折叠屏/平板 dump。

**phone（Pura 90，377 vp）**：主导航四页、设置全部子页（播放/下载/歌词/外观与动效/流量与封面/存储与缓存/账号与登录/同步/一起听/开发者/关于/调试工具）、搜索结果、歌单详情（空态与含歌曲）、网易云歌单页、播放页（含 WaveformSlider/歌词）、播放历史、播放统计、下载管理、从播放历史添加面板、歌单管理/新建歌单对话框、QrLoginPanel。三档字号（1.0/1.45/1.75）下**非滚动区溢出 0、文本重叠 0**；字号档位下发现并修掉的 3 处真实缺陷见 §3.1。

**foldable 展开态（Mate X7，707 vp）**：同一份已签名 HAP 安装后走查 17 页——首页（首屏 + 滚动后歌单区）、探索、资料库、设置（顶部 + 滚到底）、播放页、歌单详情、播放设置、下载设置、歌词设置、外观与动效、流量与封面、存储与缓存、账号与登录、同步、一起听、关于。结果：**非滚动区溢出 0、非滚动区裁剪 0、文本重叠 0**；仅资料库/播放页/同步各 1 处滚动区裁剪（允许类）。宽屏响应式行为正常：首页歌单区渲染为双列（卡片右边界 2161 < 2210），歌单页按钮行 `[417,493,667,618]`/`[692,493,942,618]` 远未触边。每页走查均以 `keyEvent Back` 退出且下一页身份正确，顺带复验了返回栈。

反复出现在**每一份** dump 里的 `'12, :, XX' 139x81 <- 139x84` 一类裁剪是**系统状态栏时钟**，非应用内容，判定时应排除。

历史布局事实（非本轮重验）：
- M7.4/M8 期间 phone 实例全页面走查通过；
- M8 已知观察：恢复态返回栈单层（来自后台恢复时 Router 栈为初始态）、网络全坏期重试链 UI 争用，均已登记 PORTING_EXECUTION_PLAN M8 完成行。

## 3. 无障碍

### 3.1 文本缩放（本轮重点，发现并修复 3 处真实缺陷）

**首要事实：HarmonyOS 应用默认不跟随系统字体大小。** 默认值是 `nonFollowSystem`，即之前"UI 全用 fp 所以自动跟随"的推断是错的——fp 只保证换算单位，不保证订阅系统档位。必须显式声明：

```
AppScope/resources/base/profile/configuration.json
{ "configuration": { "fontSizeScale": "followSystem", "fontSizeMaxScale": "1.75" } }
```

并在 `AppScope/app.json5` 里以 `"configuration": "$profile:configuration"` 引用。本轮已加。`fontSizeMaxScale: 1.75` 是**实测兑现过**的承诺，不是抄来的数字（见下）。

系统档位与倍率对应（设备实测）：小 0.85 / 标准 1.0 / 大1 1.15 / 大2 1.3 / **大3 1.45** / 大4 1.75 / 大5 2.0 / 大6 3.2。「设置→显示和亮度→字体大小」滑杆只到 1.45×；要到 1.75× 必须走「设置→关怀和无障碍→关怀模式→放大显示」的「大 4 档」。基线校准踩过一个坑：滑杆拖到最左**不是**标准而是 0.85 档（应用内 `最近播放` 实测 215×63），标准档是右移一格（252×74）；1.75× 档实测 441×129 = 252×1.75，逐像素吻合。

按官方适配要求判定（≥1.75× 时布局不得错乱、**组件不得叠加**、文字不得截断），发现 3 处缺陷，均已修复并在 1.45×/1.75× 两档复测：

| # | 位置 | 缺陷（修复前实测） | 修复 | 修复后实测 |
| --- | --- | --- | --- | --- |
| 1 | `ExplorePage.ets` 平台切换 chip 行 | `YouTube Music` 落在 `[1000,827][1444,904]`，右边界 1444 > 屏宽 1320 —— **整块被排到屏外且不可点** | `Row` → 换行 `Flex({ wrap: FlexWrap.Wrap })` | 折到第二行 `[189,995][633,1072]`，可点 |
| 2 | `NeteasePlaylistPage.ets` 三按钮头部 | `导入` 在 `[1237,724][1471,864]`，234px 宽只剩 83px 可见 | 同上 | 1.45× `[469,892][703,1032]`；1.75× 折到第二行 `[903,964][1162,1106]` |
| 3 | `SongRow.ets` 序号角标 | `'1'` `[924,1006,984,1085]` 与时长 `'3:16'` `[948,1028,1068,1099]` **重叠 36×57px** | 见下 | `'1'` `[199,1147][259,1226]` 压在封面上，`'3:16'` `[948,1196][1068,1267]`，重叠 0 |

缺陷 3 的根因值得单独记住：角标用的是**百分比 `.position({ x: '72%', y: '2%' })`**，而百分比按父容器的**实测宽度**解析；字号放大后父 `Stack` 变宽，角标就被推到时长文字上。修法不是调百分比，而是去掉百分比依赖——`Stack({ alignContent: Alignment.TopEnd })` + 给 Stack 钉死 `.width(52).height(52)` + 用 `.margin` 微调，结果与字号无关。**结论：`.position()` 的百分比值在字体缩放下不稳定，布局代码里应避免。**

`PlaylistDetailPage.ets` 的两按钮行做了同样的预防性改造：1.45× 下它其实还在一行内（`[469,605][825,745]`/`[853,605][1209,745]`，右边界 1209 < 1320），换行 Flex 是留给 1.75× 的余量——而在 1.75× 下，正是这个换行让结构相同的网易云歌单页按钮留在屏内。

歌词字号另有独立设置 `np.lyric_font_size`（8–24，LyricView 消费），与系统档位叠加。

### 3.2 触控目标（度量审查，修正此前的静态结论）

代码层已把可点击元素**下限抬到 40vp**（典型手法：18vp 图标放进 40vp 盒子，用 `.padding(11)` 保持图标视觉尺寸不变而扩大命中区，见 `SongRow.ets` 的"更多操作"）。设备复测：首页/探索/资料库/播放设置 **<40vp 元素数 0**；播放页只剩歌词行 377.1×16.3vp 低于 40vp，属**有意为之**——歌词行高度由行高决定，点击行为是跳转到该句时间点，行高强行拉到 40vp 会破坏歌词排版。

**修正此前"满足 ≥48vp 指南"的说法**：实际约 30 个控件落在 40–48vp 区间，因此工程实际执行的是 **40vp 下限**，并未达到 48vp 推荐值。发布文案与后续审查应按 40vp 记录。

### 3.3 屏幕朗读语义（部分完成，且无法在本链路内验证）

已补 **21 处 `.accessibilityText`，覆盖 13 个文件**（MiniPlayer、SongRow、NowPlayingPage、HomePage、SettingsDetailPage、PlaylistDetailPage、NeteasePlaylistPage、BiliFavPage、DownloadsPage、RecentPage、StatsPage、DebugPage、ListenTogetherPage），重点是纯符号控件——`‹`/`⋯`/`＋` 这类字符对朗读器只是标点，必须显式命名动作（如 `.accessibilityText('返回')`）。`.accessibilityDescription` 用量 0。

**验证边界（如实标注）**：这 21 处只经**代码确认**，未经设备确认。原因是 `uitest dumpLayout -e accessibilityText` 被工具直接拒绝——报 `Invalid attribute name, currently supported names are 'uniqueId'`，即当前 uitest 不支持导出无障碍属性。要真验证需开屏幕朗读服务并人工听读，本自动化链路做不到 → **朗读实际效果未验证**。

色彩对比度：默认主题暗/亮两套，M8 动态取色有 HSL 压制（adjustedAccent 保证 L≥0.22/≤0.90）；未做自动对比度审计。

## 4. 功耗与内存

- 后台播放依赖 AVSession + AUDIO_PLAYBACK 长时任务（M1.5 实装）；熄屏 30 分钟连续播放冒烟**未执行**（模拟器熄屏策略与真机差异大）——**待真机复核**。
- 内存：HiAppEvent 正常运行无常驻开销（订阅仅故障回放）；YTM 环回桥仅测试路径引用未接入生产；ArkWeb JS 运行时（M6.3）未启用，无 200MB 常驻。
- **内存冒烟（已执行，2026-08-24，Pura 90）**：`hidumper --mem <pid>` 采样。冷启动 127082 kB → 6 轮全页导航峰值 150739 kB → 12 轮导航 + 5 分钟后台播放后 144579 kB。区间 127–151 MB，**无单调增长**（ark ts heap 31630 → 25744 kB，说明 GC 正常回收）；进程 pid 13119 跨 12 轮导航 + 5 分钟后台播放**未被重启**，即无 OOM 回收。
- **CPU 代理指标（已执行）**：前台空闲 0.017%，后台播放 0.74%。**必须标注这是代理指标而非功耗**：模拟器无电量计，Battery Kit 统计在 x86 模拟器上不反映真机耗电；真机功耗基线仍**未执行**。

## 5. 隐私声明与数据合规

### 5.1 权限清单（module.json5）

> 2026-08-25 修订（`UX_COMPLIANCE_AUDIT.md` §9.2）：原表标题「全部 normal 级」**是错的**——当时表内的 `ohos.permission.READ_AUDIO` 是 user_grant 级。该权限本轮已删除，删除后本表标题才真正成立。

| 权限 | 级别 | 用途 | 用户拒绝路径 |
| --- | --- | --- | --- |
| ohos.permission.INTERNET | normal | 网络音乐源、歌词、同步 | 系统安装时授予，无拒绝分支 |
| ohos.permission.GET_NETWORK_INFO | normal | 下载引擎断网感知（M3.5） | 无 UI 分支（功能性降级：任务挂起等网） |
| ohos.permission.KEEP_BACKGROUND_RUNNING | normal | 后台连续播放（M1.5 长时任务） | 后台播放被系统冻结，前台播放不受影响 |

**已删除（2026-08-25）**：`ohos.permission.READ_AUDIO`（user_grant）。删除依据——全项目 `grep requestPermissionsFromUser` 零命中，即该权限声明了但从未申请过；`LocalMediaScanner.ets` 注释已说明 API 24 上 mediaLibrary 旧接口不可用，本地音频改由 `AudioViewPicker` 由用户选择（scoped access，免权限），功能不依赖它。同时删除了其孤立的 `read_audio_reason` 字符串。**未做设备冒烟**（本轮无设备），残余风险见 `UX_COMPLIANCE_AUDIT.md` §11。

现状：**三个权限全部 normal 级，不存在任何 user_grant 权限**，因此不存在权限申请时机问题，也不存在拒绝分支。`KEEP_BACKGROUND_RUNNING` 的 `reason` 已按「场景+动作+目的」重写，并新增 `resources/zh_CN/element/string.json` 提供中文版（`reason` 由系统原样展示给用户与审核）。

无位置/相机/麦克风/通讯录等敏感权限；无 READ_IMAGEVIDEO（保存歌词卡片走 SaveButton 安全控件免权限，M8.5）。

### 5.2 数据收集与存储

- **无第三方统计/崩溃 SDK**（对齐 Android 侧自研，无 sentry/bugly/firebase 依赖）。故障数据仅经 HiAppEvent 订阅本地落盘（files/diagnostics/，环形 20 条），**不上传任何服务器**；导出（SafeMode/DebugPage→DocumentViewPicker/剪贴板）是唯一出设备路径且完全由用户主动触发，导出前经脱敏（URL query 剥离 + 长 token 折叠，M9.2 `sanitizeDiagnosticText`）。
- 凭据（网易云/B 站 Cookie、GitHub PAT、WebDAV 密码）全部存 `@ohos.security.asset`（M4/M5），不落明文 preferences；日志全链路不输出 Cookie/Token 值。
- 遥测：无。一起听/同步直连用户自配服务器，不经过任何中间服务。
- 隐私声明要点（上架文案需包含）：本地处理为主；账号凭据仅用于用户本人的平台登录；故障日志仅本地存储、用户主动导出；不收集设备标识符（deviceId 为本地随机生成用于同步冲突仲裁）。

### 5.3 第三方音乐源条款（**上架主要风险区**）

本项目是非官方第三方客户端，调用以下来源的**非公开接口**：

| 来源 | 接口性质 | 条款风险 |
| --- | --- | --- |
| 网易云音乐 | weapi 加密私有接口（逆向） | 违反服务条款风险；音质受限接口（VIP 内容仅元数据，取流按服务端授权）；不建议公开市场上架含此能力的版本 |
| 哔哩哔哩 | WBI 签名 web 接口（公开 web 端同栈） | 同上；收藏夹/搜索为登录用户自身数据 |
| YouTube Music | innertube IOS client 匿名接口 | ToS 明确禁止；当前仅约 1 分钟试听（上游封顶，D2 待决策） |
| AMLL 歌词库 / LRCLIB | 公开 HTTP API | 条款友好（LRCLIB 免费公开、AMLL 社区接口），标注来源即可 |

结论：**面向公开应用市场发布需剥离或降级三平台取流能力（或仅保留用户自建服务器/本地播放/同步），否则有下架与法律风险**；个人侧载/研究用途风险自担。此结论与 Android 上游一致（GPL-3.0 研究项目，未上架）。

### 5.4 许可证

- 本项目及其衍生移植遵循 **GPL-3.0**（继承上游 NeriPlayer）；复制/改写上游代码处已保留来源说明（各模块头注释与 PORTING 文档）。
- 自研纯 ArkTS 组件（QR 编码器、Palette、TTML 解析器、protobuf wire、gzip inflate 等）随项目以 GPL-3.0 发布。

### 5.5 其他市场门槛项

- 内容分级/版权声明页：应用内免责声明已有（首启 Disclaimer，`KEY_DISCLAIMER_ACCEPTED`）。**2026-08-25 补齐**：该弹窗此前只有「我已阅读并同意」、无任何拒绝路径，且隐私政策与用户协议在应用内不存在——两项都是上架红线，已整改（新增「不同意」+ 二次确认 + `terminateSelf()` 礼貌退出；新增 `LegalDocPage` 应用内离线可读，首启弹窗与「设置→隐私与协议」两处可达）。详见 `UX_COMPLIANCE_AUDIT.md` §9.1。
- **法务文案仍是草案**：隐私政策与用户协议为 agent 起草的 `v1.0.0-draft`，带「草案 · 待作者复核」横幅，生效日期待定。上架前须作者定稿并在 AGC 上传同一版本（应用内与 AGC 不一致是驳回项）。
- **重大政策变更未实现重新征同意**：文案里已承诺，代码仍是布尔标记 `KEY_DISCLAIMER_ACCEPTED`，改版本号不会重新弹窗——待办项。
- 账号注销：无自建账号体系（无注册、无服务端、无云端用户数据），第三方平台账号须前往对应平台办理，应用内提供「设置→账号与登录」退出登录（即时删除本机凭据）。已在用户协议第五节写明。
- 华为账号登录：不触发强制接入条件（无登录页、不以第三方账号登录本应用；平台 Cookie/Token 属「平台内容授权」而非「第三方账号登录」）。判定依据见 `UX_COMPLIANCE_AUDIT.md` §9.4。
- IAP Kit：无付费点、无数字商品、无购买页，不适用。
- 年龄分级：音乐播放类，无用户生成内容上传（分享卡片仅本地生成图片）。
- 一起听默认服务器：外部依赖（D7），客户端直连；发布文案需说明「需要自建或已知服务器」。
- **设计与交互规范自查**：少数派《鸿蒙上架指南》第一章 22 条逐条自查与整改记录见 `UX_COMPLIANCE_AUDIT.md`（分层图标、启动页背板、沉浸式三项、触控目标、深色模式、转场动效、折叠屏/大屏、隐私与权限）。其中**大屏三档响应式布局已于 2026-08-26 完成**（`Tabs` 侧边栏 + `GridRow` 分列 + `ContentBand` 栏宽 + 动态避让，§8.2 的 11 条密度问题全部整改），因此 `deviceTypes` 可保留 `tablet`/`2in1`，无需收窄为 `["phone"]`。**回归证据已覆盖 tablet 与 phone 两档**（08-26/08-27）；仍缺 2in1：其上「自由窗口避让区 0 → 抬升量 0」核心验收点与跨断点换栏仍无实测（见 §1 与 §7.3）。

## 6. 已知能力限制（发布文案应如实描述）

- YTM 完整播放受限（匿名窗口约 1 分钟，D2 三选项待用户决策，M6.3/M6.4/M6.5 搁置中）。
- USB 独占音频不移植（M9.1 定案，USB DAC 走系统路径）。
- 悬浮歌词/状态栏歌词为应用内降级实现（D4）；AVRCP 远端刷新时机无官方承诺。
- 元数据 tag 写入无公开 API，下载曲目以 sidecar 编目承载。
- 省流同步写出降级为 JSON（读三格式全兼容）。
- **设置页三处功能占位**（点击只弹 toast，不是可用功能，发布说明必须列出）：下载目录选择 `SettingsDetailPage.ets:805`「目录选择待移植」、语言切换 `:897`/`:899`「简体中文（更多语言待移植）」、YouTube 登录 `:1022`/`:1024`「Cookie 会话待移植」。
- B 站收藏页（`BiliFavPage`）本轮**未走查**：进入需 Bilibili 登录态，无可用账号 → 其布局在任何字号/形态下都未验证。

## 7. 验证证据

### 7.1 M9.3 门禁（2026-08-24）

构建与静态检查（该轮源码自上次门禁后未变，设备工作只新增 `tools/.m9/` 下的开发期脚本，不入仓、不进模块）：

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 构建 | `hvigorw.bat assembleHap`（命令行工具链，非 DevEco 26 Beta2） | BUILD SUCCESSFUL |
| 单测 | `aa test`（ohosTest 模块 `entry_test`） | **798 [pass]**，fail/error/ignore 各 0，`OHOS_REPORT_CODE: 0` |
| 静态检查 | `codelinter` | `warn 24 / suggestion 2 / error 0`，与基线一致 |

设备证据：§2（两形态布局度量）、§3.1（字号三档 + 3 处缺陷修复前后实测坐标）、§3.2（触控目标度量）、§4（内存/CPU 采样）。

**该轮未能取得的证据**（不得在发布材料中表述为已验证）：tablet 与 2in1 形态布局（镜像未下载，§1）、折叠外屏 346vp 布局（传感器无法注入，§1）、横屏布局、真机全部指标、屏幕朗读实际听读效果（§3.3）、熄屏 30 分钟功耗（§4）、BiliFavPage（§6）。

> 这是 M9.3 当时的快照，不代表当前状态：其中 **tablet 与 2in1 已于 2026-08-25/26 取得证据**（见 §1 与 §7.2/§7.3），其余各项截至 2026-08-26 仍未验证。

### 7.2 上架规范整改轮（2026-08-25 静态 / 08-26 设备验证）

**本轮改动了源码**（15 个文件修改 + 10 个新增，含 `module.json5` 权限声明与 `AppScope/app.json5`），因此 §7.1 的数字**不再等于当前源码的验证状态**：

| 项 | 结果 | 说明 |
| --- | --- | --- |
| 构建 | **BUILD SUCCESSFUL in 22 s** | 已实测 |
| 静态检查 | **warn 25 / suggestion 2 / error 0** | 基线 24 → 25。新增一条为 `LegalDocPage.ets:18 avoid-overusing-custom-component-check`，该规则项目内已有 15 处同类命中（每个页面都是 `@Component`），属既有已接受模式；error 仍 0 |
| 单测 | **未运行** | 设备时间用于 UI 取证，`aa test` 未执行 → §7.1 的 **798 pass 是对旧源码的测量，对当前源码属「有历史证据 / 待复核」**，不得表述为当前已验证。**2026-08-26 更正**：798 这个数字本身也从未在本机测量过（见 §7.3） |
| UI 表现（三形态设备实测） | **已实测**，并发现 1 处缺陷 | phone（API 24）/ 2in1 / tablet（均 API 26 Beta）。沉浸式顶底、浅色与深色配色、四类布局缺陷、分层图标、底部 Tab 几何、法务页入口均已取证；**tablet 上另取得挖孔避让实测**（本机唯一带挖孔形态）。逐项数字见 `UX_COMPLIANCE_AUDIT.md` §11.2 |
| 深色模式缺陷（实测发现→已修复） | **已修复并复测通过** | 现象：切换深色后当前页不重绘、底部导航栏永久停浅色。根因是 ArkUI 最小化更新跳过不引用可观察状态的颜色表达式（`Theme.isDark()` 读 preferences，27 文件 482 处均不可见）。修复：`MainShell`/`Index` 改读被跟踪成员 + 新增 `util/AppColorMode.ets` 走 `setColorMode` 触发配置变更。三形态复测均通过 |
| 大屏适配 | **已实测，登记为遗留（不改代码）** → **2026-08-26 已整改，见 §7.3** | 2in1 与 tablet 无硬性布局缺陷，但存在 11 条信息密度问题（底部 Tab 单格 275~410vp / tablet 360vp、设置行文本 1412~1519vp、正文行宽最多 1408vp≈66 汉字、全宽按钮 1296vp、竖向空白最多 555vp）。见 `UX_COMPLIANCE_AUDIT.md` §8.2 与 §12 第 3 项 |
| 目标 API 24 上的 tablet / 2in1 回归 | **未验证** | 本机无 6.1.1 的 tablet / pc 镜像，这两个形态跑的是 API 26 Beta（`os.isPublic=false`），属向上兼容运行，见 §1 更正说明 |
| 播放主路径 | **未验证** | 三形态都只走到列表与设置层，未实际起播；`NowPlayingPage` 的背景层与两个半模态面板的底部避让因此仍无实测 |
| 权限删除的设备冒烟 | **未验证** | 见 §5.1 与 `UX_COMPLIANCE_AUDIT.md` §11.4 的残余风险评估 |

设备验证轮实际执行的命令（结果均如上表）：`sign-local.ps1`（重签并安装，UDID 经 `NERIPLAYER_DEVICE_IDS` 环境变量传入，不落盘不入日志）→ `aa start` → `uitest dumpLayout` + `tools/.m9/overflow.py` → `snapshot_display` + `System.Drawing.Bitmap.GetPixel` 采样 → `hidumper -s WindowManagerService -a -a` 读系统窗口矩形。

完整的本轮自查结论、判定依据与遗留项见 `UX_COMPLIANCE_AUDIT.md`（§11 验证证据、§12 遗留项）。

### 7.3 ArkUI 标准组件改造轮（2026-08-26）

**本轮又改动了源码**：触及 **24 个文件（其中新增 3 个）**——顶层导航 → `Tabs`/`TabContent`（lg 走 `.vertical(true).barWidth(96)` 侧边栏）、路由 → `Navigation`/`NavDestination` + `NavPathStack`、固定网格 → `GridRow`/`GridCol`、硬编码 28vp → `TYPE_NAVIGATION_INDICATOR` 避让区动态求值、新增 `ContentBand` 栏宽约束。文件清单与逐条改法见 `UX_COMPLIANCE_AUDIT.md` §10.2。

| 项 | 结果 | 说明 |
| --- | --- | --- |
| 构建 | **BUILD SUCCESSFUL in 17 s 235 ms** | `hvigorw.bat assembleHap --mode module -p module=entry@default -p product=default`（命令行工具链；DevEco 26 Beta2 构建不了 6.1.1(24) 工程） |
| 静态检查 | **Defects 28 / error 0 / warn 26 / suggestion 2** | 基线 25 warn → 26。新增的那一条是 `Ui.ets` 的 `ContentBand` 命中 `@performance/avoid-overusing-custom-component-check`（该规则现共 17 处命中，均为「每个页面都是 `@Component`」的既有已接受模式）。`ContentBand` **必须**是自定义组件——它要靠 `@BuilderParam` 接收内容，`@Builder` 全局函数拿不到调用方的尾随闭包。error 仍 0 |
| 本地单测（`entry/src/test/`） | **Tests run: 819, Failure: 0, Error: 0, Pass: 819, Ignore: 0** | `hvigorw.bat test --mode module -p module=entry@default -p product=default`；162 个 `describe`。结果落在 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`（**不在** `outputs/test/reports/`，后者只有覆盖率产物），默认与 `--debug` 输出都不打印计数。覆盖率：行 60.24%（11135/18485）/ 函数 53.92% / 分支 56.51% |
| 设备侧单测（`entry/src/ohosTest/`，module `entry_test`） | **Tests run: 49, Failure: 10, Error: 10, Pass: 29**（`ResultCode 0`） | tablet 上 `assembleHap --mode module -p module=entry@ohosTest` → 手动签名 → 安装 → `aa test`。20 个失败**全部**是实网请求超时（网易云/B 站/YTM 的搜索、歌单、音频直链等），与本轮改动无关；但也因此**不能用它证明「无回归」** |
| **819 与 798 的关系** | **不是增量** | 两套 suite 完全不同：`entry/src/test/`（本地，819 例）与 `entry/src/ohosTest/`（设备侧，49 例）。§7.1/§7.2 引用的 798 是历史文档中的说法，**本机从未测量过该数字**，因此 819 不可读作「798 + 21」。本轮对 suite 的实际改动是：`RouteStack.test.ets` **删 2 条**（`serialize/parse` 往返与依赖数组语义的部分——被测行为随 `route.stack` AppStorage 镜像一起删除，不是为了让测试通过而删）、新增 `Breakpoint.test.ets` **5 条** |
| UI 表现（tablet 复测） | **已实测，四类缺陷全 0** | 7 页 `dumpLayout`：首页 / 探索 / 资料库 / 设置 / 隐私政策 / 免责声明 / 引导页。侧边导航栏固定 **96 vp**（192 px，四个标签中心 cx 均为 96 px）、列表与设置栏宽 **840.0 vp**（行内文本块 716~740 vp）、法务正文 **568.0 vp**（原 1408 vp）、按钮 **360.0×48.0 vp**、竖向空白探索页 280.5 vp（原 555.5）/ 首页 142 vp（原 405.5）、`GridRow` lg 12 列 span 2 → 每行 6 张卡（单卡 208.5 vp，原 700 vp）。逐条数字见 `UX_COMPLIANCE_AUDIT.md` §8.2 |
| 动态抬升量（S2 核心） | **tablet 与 phone 已验证；2in1 未验证** | tablet：`SCBGestureNavBar18 [0,1864,2880,56]` → 避让区 28 vp，滚动区底边落在 y=1864 px（932 vp）与避让区上沿重合 → 动态抬升 28 vp 与硬编码值一致。phone（API 24）：`SCBGestureNavBar16 [0,2754,1320,94]` → 避让区 27.85 vp，TabBar 高 90.1 vp = 62+28、底边与指示器上沿精确重合。**2in1 自由窗口「避让区 0 → 抬升 0，死区消失」这一条是本阶段真正的验收点，尚未实测** |
| 返回栈（S4 的双弹风险） | **已验证，未双弹** | 从全屏法务页发一次 `uitest uiInput keyEvent Back`，恰好回退一层到 Tab 骨架 → `Index.onBackPress` 与 `Navigation` 没有同时消费返回键，该 override 保留 |
| 播放进度条缺陷（实测发现→已修复，**计划外**） | **已修复并像素复测** | `MiniPlayer` 的 `Progress` 原来喂 0..1 比例且不给 `total`（`progress.d.ts` 只声明 `total?: number` 且无文档化默认值），进度条从未正确显示：播到 11% 与 20% 时像素采样整条都是轨道色。改为 `value: positionMs, total: durationMs`（与 `DownloadsPage.ets:172` 同一写法） |
| phone / 2in1 改后复测 | **phone 已复测（2026-08-27，全过）；2in1 未验证** | phone（唯一 API 24 形态）：四 Tab + 隐私/用户协议/播放设置/调试/播放页 + 清数据重走的免责声明/引导，四类缺陷全 0；Tab 单格 97.8 vp 与改造前逐像素一致；深/浅/auto 三档底部采样无缝；字号 1.45× 与等效 1.8125× 三处已修缺陷无回归；返回栈单次单层无一次双弹。**复测发现并修复两处缺陷**：① 底部 28 vp 指示器条带与 Tab 栏色差接缝——`Tabs` 容器自身延伸到窗口底边，补 `.backgroundColor(bandColor())` 即连续（原内层色带在 `NavBarContent` 里 `expandSafeArea` 不延伸，已删）；② `NavDestination` 默认白背景在深色模式露白边——显式置 `Color.Transparent` 回落 Index 沉浸层。证据前缀 `tools/.m9/pa*`，逐项见 `UX_COMPLIANCE_AUDIT.md` §11.6。2in1 需用户在 DevEco 设备管理器启动实例后串行复测 |
| `mcp__deveco-mcp__check` 静态诊断 | **未运行** | 该 MCP 对本工程不可用（沿用前轮结论），计划里的静态验证第 3 步声明为未执行 |
| 内存 | **phone 复测已取得（08-27）** | 冷启 220 MB → 首轮全页导航 256 MB → 6 轮平台期 **257–264 MB，无单调增长**。较 08-24 phone 基线 127–151 MB 高约 110 MB——「Tab 页常驻推高内存」的方向得到确认，但两次测量数据量不同（本轮含网易云实网数据与封面缓存），**不可作严格对比**；无泄漏趋势与旧结论一致。tablet 侧 378 MB（窗口与位图更大，另行记录） |

**本轮行为变更（发布说明须列出）**：

1. **四个 Tab 页由「销毁重建」改为「常驻」**。原先 push 全屏路由会替换整个 Tab 骨架，返回时子树重建 → `aboutToAppear` 重跑 → 数据自动刷新；`Navigation` 的 Stack 模式下 navBar 不销毁，这个隐式刷新消失。补的显式钩子：每个 `NavDestination` 的 `.onWillDisappear` → `Router.notifyReturned()` → 自增 `ui.refreshTick`，三个数据页 `@Watch` 该值并按 `np.default_start_tab` 过滤（避免隐藏页白跑网络请求）。
2. **跨断点会重建 `Tabs` 子树**，四个 Tab 页的 `@State` 丢一次（2in1 拖动窗口可感），靠 `ui.refreshTick` 重载。
3. **全屏路由页在大屏上覆盖侧边导航栏**（`NavigationMode.Stack` 的固有行为），内容水平中心从 1536 px 移到 1440 px，偏移 48 vp。同时侧边栏在全屏页打开时不可点击，只能用返回键/手势退出。
4. **删除 `route.name`/`route.param`/`route.stack` 三个 AppStorage 镜像**，读 param 的 4 个页面由 `@StorageLink` 改 `@Prop`。`Router` 公开 API 签名与语义不变，38 个调用点零改动。
5. **`MiniPlayer` 进度条从「始终不动」变为正常推进**（此前是缺陷，见上表）。

本轮实际执行的命令：`hvigorw.bat assembleHap` → `codelinter.bat ./entry` → `hvigorw.bat test`（本地 suite）→ `hvigorw.bat assembleHap --mode module -p module=entry@ohosTest` + `hap-sign-tool.jar sign-app` + `hdc install -r` + `aa test`（**须 `MSYS_NO_PATHCONV=1` 且屏幕已解锁**，否则 ResultCode -1/-2）→ `sign-local.ps1`（重签 default HAP 并安装）→ `aa start` → `uitest dumpLayout` + `tools/.m9/overflow.py` → `snapshot_display` + `GetPixel` 采样 → `hidumper -s WindowManagerService -a -a` / `hidumper --mem <pid>`。签名口令经 `NERIPLAYER_SIGNING_PASSWORD`、UDID 经 `NERIPLAYER_DEVICE_IDS` 传入，均不落盘不入日志。

> **取证时的一个已确认误报**：`uitest` 导出 `Progress` 节点时，`bounds` 恒为 1344、`origBounds` 恒为 2880，与实际填充量无关（在 11% 与 20% 两个进度各测一次，数字不变）→ 四个 Tab 页上反复出现的「非滚动区被裁剪 1」全部落在 MiniPlayer 那条 `Progress` 上，属**导出侧的固定值**，与系统状态栏 `'100'` 重复导出造成的「文本重叠」同类。判定四类缺陷时按人工核查排除。
