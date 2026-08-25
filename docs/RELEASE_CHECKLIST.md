# NeriPlayer HarmonyOS 发布矩阵与合规清单（M9.3）

> 2026-08-24 编制。执行者：ZCode agent。本清单是发布门槛的**当前事实快照**：已验证项附证据，未验证项如实标注，不把历史验证当当前能力（AGENTS.md 事实优先级约定）。消费者：`PORTING_EXECUTION_PLAN.md` §6 M9.3、`FEATURE_MATRIX.md`。

## 1. 设备矩阵与布局回归

密度换算用应用内已知 40vp 控件（返回按钮 `.width(40).height(40)`）实测像素反推，不依赖 `param get`（模拟器上 `const.display.density` 等键均 errNum 1002 不可读）。

| 形态 | 环境 | 逻辑宽度 | 状态 | 证据/说明 |
| --- | --- | --- | --- | --- |
| phone | Pura 90 模拟器（1320×2856，3.5 px/vp，API 24） | 377 vp（MD 断点） | 已回归（2026-08-24） | 全页走查 × 字号 1.0/1.45/1.75 三档，溢出 0 / 重叠 0（§2、§3.1） |
| foldable（展开内屏） | Mate X7 模拟器（2210×2416，3.125 px/vp，API 24） | **707 vp（LG 断点）** | 已回归（2026-08-24） | 17 页 `dumpLayout` 度量，非滚动区溢出 0 / 裁剪 0 / 文本重叠 0（§2） |
| foldable（折叠外屏） | 同实例第二显示（1080×2444） | 346 vp | **未验证** | 折叠态由 Posture/Hall 传感器驱动（DMS 已订阅），仅模拟器 GUI 可切换；`hidumper -s DisplayManagerService` 无折叠开关参数，hdc 无法注入 → 无法在本自动化链路内走查 |
| tablet | MatePad Pro 13 实例已配置（2880×1920） | — | **阻塞** | 实例存在，但所需镜像 `system-image/HarmonyOS-6.1.1/tablet_x86/` 不在盘 |
| 2in1（PC 平板形态） | MateBook Pro 实例已配置（3120×2080） | — | **阻塞** | 实例存在，但所需镜像 `pc_all_x86/` 不在盘；强启后 `isRunning=true` 且有 2 个 `Emulator.exe`，然而 hdc 端口始终不出现（`list targets` 恒为 `[Empty]`，`tconn 127.0.0.1:5555..5560` 全部 `Connect failed`，netstat 无 555x 监听）——启动进入无镜像的死态 |
| 真机（物理手机/平板） | 无设备 | — | 未验证 | 全部设备证据来自 x86 模拟器；上架前必须真机回归（尤其签名/性能/蓝牙 AVRCP） |

镜像获取阻塞的**准确定性**（勿再复述为"镜像库无该设备"，该说法经实测证伪）：DevEco 6.1.1(24) 镜像库**确有** Foldable/Tablet/2in1 设备型（`Emulator.bat -help` 列出 `Phone | Foldable | WideFold | TripleFold | Tablet | 2in1 | 2in1 Foldable | Wearable | WearableKid | TV`），四个 API 24 实例也都已创建；真正的障碍是本机只下载了 `phone_all_x86` 一份镜像，而命令行镜像管理器在无 GUI 会话下**静默失效**：

- `Emulator.bat -imageList [-deviceType Phone] [-downloaded true]` → 退出码 0、**零输出**，连已在盘的 phone 镜像都不列出；
- `Emulator.bat -install -deviceType 2in1 -osVersion "HarmonyOS 6.1.1(24)" -force`（`-license accept` 已先执行成功）→ 退出码 0、零输出、镜像目录无变化。

即"查不到/装不上"是工具链行为，不是镜像不存在。补 tablet/2in1 回归的前置条件是在 DevEco GUI 的 SDK/模拟器管理器里下载这两份镜像。Mate X7 之所以能跑，是因为 foldable 复用 `phone_all_x86`。

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

### 5.1 权限清单（module.json5，全部 normal 级）

| 权限 | 用途 | 用户拒绝路径 |
| --- | --- | --- |
| ohos.permission.INTERNET | 网络音乐源、歌词、同步 | 系统安装时授予，无拒绝分支 |
| ohos.permission.GET_NETWORK_INFO | 下载引擎断网感知（M3.5） | 无 UI 分支（功能性降级：任务挂起等网） |
| ohos.permission.KEEP_BACKGROUND_RUNNING | 后台连续播放（M1.5 长时任务） | 后台播放被系统冻结，前台播放不受影响 |
| ohos.permission.READ_AUDIO | 本地音乐导入（picker 授权模型） | 本地导入不可用，其余功能正常 |

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

- 内容分级/版权声明页：应用内免责声明已有（首启 Disclaimer，KEY_DISCLAIMER_ACCEPTED）。
- 年龄分级：音乐播放类，无用户生成内容上传（分享卡片仅本地生成图片）。
- 一起听默认服务器：外部依赖（D7），客户端直连；发布文案需说明「需要自建或已知服务器」。

## 6. 已知能力限制（发布文案应如实描述）

- YTM 完整播放受限（匿名窗口约 1 分钟，D2 三选项待用户决策，M6.3/M6.4/M6.5 搁置中）。
- USB 独占音频不移植（M9.1 定案，USB DAC 走系统路径）。
- 悬浮歌词/状态栏歌词为应用内降级实现（D4）；AVRCP 远端刷新时机无官方承诺。
- 元数据 tag 写入无公开 API，下载曲目以 sidecar 编目承载。
- 省流同步写出降级为 JSON（读三格式全兼容）。
- **设置页三处功能占位**（点击只弹 toast，不是可用功能，发布说明必须列出）：下载目录选择 `SettingsDetailPage.ets:805`「目录选择待移植」、语言切换 `:897`/`:899`「简体中文（更多语言待移植）」、YouTube 登录 `:1022`/`:1024`「Cookie 会话待移植」。
- **另有三处「静默失效」的 UI，比上面三处更隐蔽**（2026-08-25 静态审查新增，来源 `docs/UI_REVIEW_M11.md` §3 ❹❺❻；上面三处至少弹 toast 告知用户，这三处不给任何反馈，用户会以为功能已生效）。**2026-08-26 M11.1/M11.2 已处置全部三处**（构建 + 单测已过，设备未验证）：
  - ~~歌词模糊效果开关 `SettingsDetailPage.ets:873-879` 写 `np.lyric_blur` 但无任何消费方~~ → **已接线**（M11.2）：`LyricView.ets` 新增 `@StorageProp('np.lyric_blur')`，按与活跃行的距离对非活跃行做 `.blur()`（0–4vp 饱和），对齐 Android `AdvancedLyricsView.lyricBlurEnabled`。注意审查原文建议"对当前行做 `.blur(4)`"方向相反（会把正在读的那行糊掉），未采纳。**模糊的实际观感与性能开销未经设备验证。**
  - ~~播放页「歌词/封面」切换不持久化（`NowPlayingPage.ets:41` 用本地 `@State showLyrics`）~~ → **已修**（M11.1）：改为 `@StorageProp('np.show_lyrics')`，切换走 `SettingsRepository.setBoolean` 落 `AppPreferences`。
  - ~~歌曲行菜单「加入歌单」「分享」的 `onTap` 只关菜单~~ → **已改为如实告知**（M11.1）：标签加「（暂不可用）」后缀，点击弹 toast 指向可用替代（收藏 / 播放页「分享」歌词卡片）。**这两项功能本身仍未移植**，发布说明仍须列出。
- **歌单搜索未移植**（2026-08-26 新登记）：探索页「搜索歌单」卡片此前带 `›` 指示符却无 `onClick`（点击无反应）。现已补 toast 并把副标题改为「待移植；可在「资料库」打开已导入的歌单与收藏夹」——没有歌单搜索 API，且 `NeteasePlaylistPage`/`BiliFavPage` 都要求具体 id 入参，无可诚实跳转的目标。
- B 站收藏页（`BiliFavPage`）本轮**未走查**：进入需 Bilibili 登录态，无可用账号 → 其布局在任何字号/形态下都未验证。
- ~~**歌词视图不随播放位置自动滚动**~~（2026-08-25 登记，2026-08-26 M11.2 已实现）：`LyricView.ets` 现持有 `Scroller`，按 `player.positionMs` 解析活跃行并把它滚到视口 **30%**（对齐 Android `playedLyricViewportFraction = 0.30f`），行几何经 `onAreaChange` 实测、首末行留 30%/70% 内边距以便同样能进入该带位，手动触摸后 2.5s 内不抢滚动（点击某行 seek 会立即重新接管）。**⚠️ 滚动流畅度、30% 落点、模糊开销均未在设备上验证**——门槛只过了构建与单测。Android 对照实现为 `SyncedLyricsView.kt`(1062) + `AdvancedLyricsView.kt`(415)。

## 7. 验证证据（本轮，2026-08-24）

构建与静态检查（源码自上次门禁后未变，本轮设备工作只新增 `tools/.m9/` 下的开发期脚本，不入仓、不进模块）：

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 构建 | `hvigorw.bat assembleHap`（命令行工具链，非 DevEco 26 Beta2） | BUILD SUCCESSFUL |
| 单测 | `aa test`（ohosTest 模块 `entry_test`） | **798 [pass]**，fail/error/ignore 各 0，`OHOS_REPORT_CODE: 0` |
| 静态检查 | `codelinter` | `warn 24 / suggestion 2 / error 0`，与基线一致 |

设备证据：§2（两形态布局度量）、§3.1（字号三档 + 3 处缺陷修复前后实测坐标）、§3.2（触控目标度量）、§4（内存/CPU 采样）。

**本轮未能取得的证据**（不得在发布材料中表述为已验证）：tablet 与 2in1 形态布局（镜像未下载，§1）、折叠外屏 346vp 布局（传感器无法注入，§1）、横屏布局、真机全部指标、屏幕朗读实际听读效果（§3.3）、熄屏 30 分钟功耗（§4）、BiliFavPage（§6）。
