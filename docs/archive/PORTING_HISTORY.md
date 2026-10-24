# NeriPlayer HarmonyOS 历史轮次记录（S 阶段与缺陷修复）

> 从 `docs/PORTING_EXECUTION_PLAN.md` 外移于 2026-10-22（原 S 阶段、S 阶段续、缺陷修复五连共 6 节）。
>
> **这些是已经完结的历史轮次取证，不代表当前待办**。当前待办与进度看板仍在主线文档 `PORTING_EXECUTION_PLAN.md` §6 与「F 阶段」节；真机验证积压见 `FEATURE_MATRIX.md` 各行「下一验证点」。
>
> 内容概览：S 阶段 UI 重构+沉浸光感+动效（2026-08-29）｜S 阶段续 壳层沉浸与播放页转场（09-08~09-14，PR #20~#30）｜缺陷修复：网易云/B站杀进程掉登录（二次）｜扫码 803 后仍「登录校验失败」（三次）｜凭据落盘被 Asset 401 拒绝（四次）｜下载坏文件与本地播放 5400106 系列（五连）

---

## S 阶段：UI 重构 + 沉浸光感 + 动效（2026-08-29 会话，分支 glass_ui_opus）

- S0 HDS 摸底：✅ 编译全绿+运行时验证（docs/HDS_IMMERSIVE_SPIKE.md）。关键结论：
  HDS Attribute 类型须显式导入；HdsNavigation/HdsNavDestination 内容子树在模拟器
  不挂载（已回退标准 Navigation/NavDestination）；模拟器 getSystemMaterialTypes()=[]
  材质降级必须保留；HdsTabs barFloatingStyle/miniBar 运行时可用。
- S1 动态配色引擎：✅ ColorScience（Lab/LCh/ΔE00/色域映射，Sharma 参考值锁定）+
  SwatchCard（907 条 MIT 色卡，仅色号+hex）+ AccentScheme（打分→吸附→护栏→双模式
  ramp）+ effectKit 取色 + WithTheme/51 槽 CustomColors。单测 26 例。
- S2 官方光感：✅ ImmersiveLightScene（HdsVisualComponent 流光场景）接入播放页，
  15 处硬编码白字全部令牌化。
- S3 悬浮壳：✅ HdsTabs 双断点 + barFloatingStyle（lightColor/gradientMask/
  miniBar/systemMaterialEffect 降级）+ MiniPlayer 迁入官方 MiniBar 槽位 +
  FLOAT_TAB_CLEARANCE 四页避让。
- S4 播放列表：✅ 手工覆盖层（含被禁的百分比 position）删除，原生 bindSheet
  （detents 双档+dragBar+下滑关闭）。
- S6-core 动效：✅ 迷你条→播放页封面一镜到底（geometryTransition+animateTo+
  systemTransition NONE）+ clickEffect + 废弃 animateTo 清理。
- S5（第二次会话续）：✅ 每日推荐 Hero 卡（标签 pill+21fp 标题+播放 FAB）、
  探索页参考图搜索胶囊（symbol 放大镜+44vp 圆键）、三页歌单头抽取共用
  PlaylistHeader（120vp 封面/24fp 标题/透明底，B 站页顺带修 Flex wrap 溢出隐患）、
  SectionHeader 22fp、页标题 32fp。commit c0e384e/0c245fbf。
- S6 余项：✅ SongRow/PlaylistCard/SettingRow/平台 chips/搜索键全量 clickEffect、
  MiniPlayer 播放键 ReplaceSymbolEffect 交叉淡入（sys.symbol.play_fill/pause_fill，
  模拟器验证切换正常）。列表行封面共享元素（需逐行 id 联动）留作可选。
  commit bab2f0fa。
- 待续：字号 1.75x 布局复测（新字阶更大，上架硬性项）、真机 HDS 复核
  （材质能力/IMMERSIVE 档位/流光调参/WithTheme 整树重绘确认）、探针面板移除
  （真机复核后再删）。

## S 阶段续：壳层沉浸与播放页转场波次（2026-09-08～09-14，分支 `dev`，PR #20–#30）

S0–S6 结论的部分修正与延续（逐项证据见 `hm.md` §7.14 与 `FEATURE_MATRIX.md` 对应行）：

- S0 结论修正：`HdsNavigation` 内容子树不挂载是当时模拟器/版本的观察，非平台定论——
  8958d16 起外壳稳定换用 `HdsNavigation`（`hideBackButton(true)`、标题随 Tab、
  `scrollEffectType: GRADIENT_BLUR` 渐变模糊标题栏、根节点 `expandSafeArea(SYSTEM/CUTOUT,
  TOP|BOTTOM)` 延伸状态栏），自建 `TitleBarBlurBackdrop` 等价实现随之删除；真机录屏
  （转场标定）证实外壳可用。`getSystemMaterialTypes()=[]` 材质降级结论维持。
- 沉浸扩展：4edac60 探索/资料库/设置与首页统一内容穿透状态栏（外层与页内列表
  `.clip(false)` + 列表顶部 `expandSafeArea`）；b9589db 移除标题栏系统返回与
  「刷新推荐」按钮。
- S6-core 整层替换：迷你条→播放页一镜到底废弃 `geometryTransition` 共享元素方案，
  改 `bindContentCover` 全屏模态 + 单一进度 `panelAmount` 分阶段原生属性动画
  （`NowPlayingCurves.ets` 先慢后快/回弹曲线，展开 300ms/收起 400ms，起止矩形按
  真机录屏逐帧标定）。九轮迭代与审查跟进（26b49aa/552df87）记录见
  `docs/NOW_PLAYING_TRANSITION_20260910.md`；折返/歌词页返回/宽屏真机回归待办。
- 波次内其余：音量淡入淡出及设置化（54fb31f/c3acdbd，矩阵行详载）、资料库取色
  重染收尾（d9b209c）、登录四连修复与下载完整性系列（见下方缺陷修复节）、
  Copilot 代码审查 CI 配置（d68f4f3）、README 重写与 `NeriPlayer-master/` 解除
  Git 追踪（8de4ca1）。

## 缺陷修复：网易云/B站杀进程重启后掉登录（2026-09-08，二次修复）

- 背景：`3f4dea0f`（fix(登录): 修复冷启动凭据恢复竞态）未生效——用户实测删除后台
  重启后登录态仍丢失。本轮重新取证定位出**四层叠加缺陷**，其中第一层是根因：
  1. **凭据从未落盘（根因）**：`NeteaseCookieRepository/BiliCookieRepository.saveInternal`
     把 `CredentialStore.putString`（跨进程 IPC 写 AssetStore）fire-and-forget 挂在
     后台、同步返回成功——UI 弹「登录成功」时写入尚未完成；且 Asset 真实写失败时
     仅 warn 日志、`np.*_logged` 仍被置 true。模拟器实测（NeriP26R）证伪了
     「Asset 服务降级」假设：冷启动无任何 FALLBACK 日志、Asset 查询无报错，但
     `netease_auth_bundle` 在存储中**根本不存在**——历次登录从未成功落盘。
  2. **冷启动首屏请求先于凭据恢复**：`EntryAbility.onCreate` 的 `init()` 未被等待，
     `onWindowStageCreate` 立即 `loadContent`，首页 `aboutToAppear` 即发 weapi 请求，
     `doEnsureSession` 以空 jar 访问网易云首页 → 服务端发匿名 `__csrf` →
     `sessionReady=true` 把匿名会话钉死整个进程，MUSIC_U 恢复后也不再进会话。
  3. **首次修复引入的倒洗**：`doInit` 无条件 `setBoolean(KEY_*_LOGGED,
     bundle.hasLoginCookies())`，恢复竞态期间把 preferences 里已存的 true 洗成 false。
  4. **调用点全是同步签名**：QrLoginPanel `onConfirmed: () => boolean`、粘贴导入
     回调、退出登录 `clear()` 均不等持久化结果。
- 修复（7 文件）：
  - `saveFromQrLogin/saveFromPastedText/saveInternal` 改 `async`，**await 落盘**；
    写失败时回滚内存 bundle 并返回 false（toast「登录校验失败」而非假成功）。
  - `NeteaseApi.doEnsureSession` 开头 `await NeteaseCookieRepository.init()`；
    `doInit` 恢复成功时 `resetSession()` 丢弃可能已飞的匿名会话。
  - `EntryAbility.onWindowStageCreate` 改为 `NeteaseCookieRepository.init() →
    BiliCookieRepository.init() → loadContent` 链——凭据先于一切页面 aboutToAppear
    就位（实测 restored 12:52:32.894 < Content loaded 12:52:33.032）；onCreate 的
    init() 保留让恢复与窗口创建并行，该链通常只等余下尾延。
  - QrLoginPanel `onConfirmed` 异步化（await 后才关面板/报失败）；SettingsDetailPage
    网易云确认/粘贴导入后补 `NeteaseApi.resetSession()`；退出登录 `.then()` 等
    clear 完成再 toast。
- 验证（NeriP26R，API 26 Release 镜像）：粘贴导入测试凭据 → 日志
  `netease login saved: keys=MUSIC_U,__csrf,os,appver` + UI「已登录 · 凭据存储：
  asset」→ **两次 force-stop 杀进程冷启动**，均恢复 `netease auth restored` +
  UI 已登录；首页推荐接口正常返回。ohosTest：ActsCredentialStoreTest 3/3、
  ActsNeteaseCookieRepositoryTest 2/2、ActsBiliCookieRepositoryTest 2/2。
  过程坑：模拟器重启后停在**锁屏**会让 aa test 的 TestAbility 窗口被切后台、
  Delegator 以 -2「TestAbility onDestroy unexpectedly」终止——解锁（uinput 上滑）
  后同一套件全过，勿把锁屏假失败当成代码回归。codelinter 0 error。
- 遗留（如实记录）：`doInit` 无条件覆盖 logged 标志的语义保留（内存降级后端重启
  本就该显示未登录），依赖第 1 层修复保证「落盘成功才有 true」。

## 缺陷修复：网易云真机扫码 803 后仍提示「登录校验失败，请重试」（2026-09-08，三次修复）

- 背景：用户真机实测扫码确认（803）后仍提示「登录校验失败，请重试」。前两轮修复
  （08f9f18 Set-Cookie 解析归一化、bd4d9c0 凭据落盘等待）后，真机扫码路径始终未复测
  通过（矩阵行长期标注「真机扫码确认仍待复核」）。
- 协议事实（2026-09-08 外部调研，来源 NeteaseCloudMusicApiEnhanced issue #6 /
  PR #201、NeteaseCloudMusicApi login_qr_check 源码、知乎 HarmonyOS netstack
  set-cookie 形态实证）：
  1. 803 的 `MUSIC_U` **只通过 HTTP Set-Cookie 响应头**下发；body 无 `cookie` 字段
     （NeteaseCloudMusicApi 的 body.cookie 是其中间件人为拼接的，非官方原生）。
  2. `x-refresh-token` 响应头 ≠ MUSIC_U（SSO 刷新凭据，注入后 account/get 校验几乎
     必然失败）——现有兜底实际救不了场，仅保留与 Android 基线对称。
  3. 2025+ 风控要求（scanlogin 新二维码 URL、chainId、x-login-chain-id/x-loginmethod
     请求头、weapi 加密）本实现均已满足。
- 服务器直连取证（2026-09-08，Node weapi 等价实现实测 music.163.com）：unikey 创建
  返回 200+key、fresh key 轮询返回 801「等待扫码」（`ydDeviceToken:""` + unknown 随机
  chainId 可用）；匿名 account/get 返回 `{"code":200,"account":null}`——证实加密移植、
  端点行为与 `hasAccount` 判定语义均正确，服务端在 803 时确实会下发 Set-Cookie。
- 推定根因（真机无日志，未直接取证）：MUSIC_U 捕获仅依赖单一来源（`HttpResponse.header`
  的 set-cookie 归一化），真机 netstack 的 803 响应头上报形态与解析假设不符时无任何
  冗余路径。HarmonyOS SDK 自 API 8 起提供独立的 `HttpResponse.cookies` 字段（服务器
  原样 Cookie 字符串），本实现此前完全未消费。
- 修复（3 文件 + 测试）：
  - `HttpHeaderParser` 新增 `parseLooseCookiePairs`：`;`/`,` 混合分隔、属性碎片
    （Expires 日期/Path/Domain 等）过滤的宽松 Cookie 文本解析，与 `extractCookiePairs`
    共享碎片归一逻辑。
  - `HttpClient.captureCookies` 合并**双来源**：response.header 的 set-cookie 行
    （原路径）+ `response.cookies` 字段（新增；运行时 `String()` 归一防个别栈违反
    d.ts 返回数组）；`getText/postForm/postFormDetailed` 三个捕获点全部接入。
  - `NeteaseQrLogin.checkLogin` 在 803 后：输出诊断日志（响应头**名**清单、jar Cookie
    **键名**清单、refreshToken 有无，不落任何值）；若 jar 仍无 MUSIC_U，**同 key 单次
    补轮询**（803 幂等重读，Set-Cookie 有机会重发）再捕获一次。postCheck 抽取复用。
  - 新增 4 个 HttpHeaderParser 单测（分号/逗号拼接、属性与 Expires 碎片、空与垃圾输入）。
- 验证（2026-09-08 服务器）：codelinter 4 文件 0 error；entry@default debug 构建
  BUILD SUCCESSFUL；hvigorw test 编译（Unit 类型检查）0 error（执行阶段挂死属本机
  平台限制，用例计数待 Windows 工作站）。
- 遗留：真机 803 复测待用户执行；若仍失败，hilog 过滤 `netease qr` 三条日志即可定位
  断点（confirm 响应头名是否含 set-cookie → re-poll 后 jarKeys 是否出现 MUSIC_U →
  save rejected/backend rejected 哪个分支）。

## 缺陷修复：网易云真机扫码 803 凭据落盘被 Asset 401 拒绝（2026-09-09，四次修复）

- 背景：v1.0.2 真机复测。用户诊断日志证实三次修复的扫码链路已全部生效：803 响应
  头含 27 个 set-cookie，jar 捕获到 `os,appver,NMTID,MUSIC_R_T,MUSIC_A_T,__csrf,
  MUSIC_R_U,MUSIC_U`，refreshToken present——**网络侧闭环成功**。失败点后移到落盘：
  `CredentialStore.putString(netease_auth_bundle) failed: AssetError(401)` →
  `netease login not saved: credential backend rejected the write` → 仍提示
  「登录校验失败，请重试」。
- 根因（官方文档实证，Asset Store Kit「新增关键资产」属性约束表）：
  **`ASSET_TAG_SECRET` 单条上限 1024 字节**（ALIAS 上限 256 字节），超长即抛 401
  参数校验失败。现代网易 803 下发的完整 cookie 集（`MUSIC_U` ~176B + `MUSIC_R_U` +
  新式长 token `MUSIC_A_T`/`MUSIC_R_T` 各数百字节 + `__csrf`/`NMTID`/`os`/`appver`）
  序列化后 ~1.5-2.5KB，超限被拒。bd4d9c0 模拟器验证用的是精简测试凭据
  （`MUSIC_U,__csrf,os,appver`，<1KB）所以能过——凭据大小差异掩盖了该缺陷。
- 修复（2 文件 + 测试）：
  - 新增纯逻辑 `data/auth/AssetChunking.ets`：UTF-8 字节按 1000B 切片（≤64 块）、
    `#CHUNKED#{"count":N,"bytes":T}` 文本清单（前缀与旧 JSON 值无歧义）、块别名
    `alias#i`；分块在**字节边界**切、拼装后再 UTF-8 解码，多字节字符跨块安全。
  - `CredentialStore` 重构：>1024B 自动分块——先写块（alias#1..#N，OVERWRITE）、
    后写清单（撕裂写只会留下「旧状态或无清单」，绝不会出现清单指向半新半旧数据；
    覆盖旧分块数据前先删旧清单；块数减少时清理多余旧块；任一失败回滚已写块）。
    读侧：基础别名内容可解析为清单 → 按序拼块并校验总字节数；否则视为旧单条值
    原样返回（前分块数据完全兼容）。remove 清单化清理所有块。FALLBACK 降级语义
    不变（切内存后本条仍报成功入内存）；因 ArkTS 控制流收窄（早返回守卫把静态
    backend 收窄为 ASSET，异步写中再比较 MEMORY 报 no-overlap 编译错），降级判定
    改走 `backendName()` 不透明调用。
  - 测试：本地新增 `AssetChunking.test.ets` 6 用例（别名/清单往返与校验、1024
    边界、切片拼装、多字节跨块、空与小值）；ohosTest `ActsCredentialStoreTest`
    新增 `putGetOversizeStringRoundtrip`（~2.1KB 模拟现代 bundle 往返+清除，待
    设备执行）。
- 验证（2026-09-09 服务器）：codelinter 改动文件 0 error；entry@default 与
  entry@ohosTest debug 构建 BUILD SUCCESSFUL；hvigorw test 编译
  （Unit 类型检查）0 error。真机复测待用户执行（预期扫码确认后 toast 登录成功，
  杀进程冷启动恢复）。
- 连带效应：B 站 bundle（SESSDATA 等 ~500B）当前未超限，行为不变；未来超限同样
  自动分块，无需改动。

## 缺陷修复：下载坏文件与本地播放 5400106 系列（2026-09-12～14，五连修复）

- 背景：用户真机反馈「下载显示完成但文件无法播放（AVPlayer `5400106 Unsupported
  Format`）+ 迷你条重新加载闪烁风暴 + 清空记录后资料库计数不清零」。真机日志驱动
  五轮修复（77a6745→3d655fc→c60dfb1→b8ff989→b5c136d），细节同步登记
  `FEATURE_MATRIX.md` 下载行。
- **①分块写入错位与重试风暴（77a6745）**：`appendChunk` 给 `writeSync` 传
  `offset: chunk.byteLength`——官方 FAQ 明确 `WriteOptions.offset` 是**文件绝对位置**，
  追加必须 `OpenMode.APPEND`；每个分块都写到同一绝对位置，提交的是带零洞的坏容器。
  无 Content-Length 响应（`expected<=0`）时 `transferSizeComplete` 恒真，坏文件照常
  提交编目。修复为 APPEND + 无 offset 追加、416 视为完成时新增本地非空校验；播放
  失败恢复收敛为纯策略 `PlaybackFailurePolicy.ets`（重试 1 次→跳下一首；下一目标即
  当前曲或全队列已试完则停止并发布 ERROR；失败代守卫防 AVPlayer 错误回调与被拒
  加载链双计），catalog fd 源失败自愈（删行+删文件，计数回归真实、允许重下）；
  下载管理页改任务+catalog 合并行 `DownloadRow`（清空记录后已下载条目仍可见、
  可删、单条删除）。
- **②真机反馈三连（3d655fc）**：断网播已下载失败——重下曾被「catalog 有记录且
  size>0 即短路 COMPLETED」钉死在旧坏文件上；现短路与 commit 前均做载荷头校验
  `isPlausibleAudioHead`（NUL 空洞/HTML/JSON 错误页拒绝，m4a 允许 ≤3 个前导 NUL，
  7 单测），自愈改走 `deleteDownload` 连任务记录一起清；资料库页删重复「下载管理」
  入口；下载管理页删与删除键重叠的绿勾角标。
- **③本地播放 5400106 双根因（c60dfb1）**：其一，网易云 weapi 取流的 AAC CDN 存在
  周期性垃圾填充段，内容校验无法拦截——下载改走匿名 legacy 接口（`NeteaseApi.
  getSongUrlLegacy`）拿干净 320k MP3；其二，本地文件经 `createMediaSourceWithUrl
  ('fd://...')` 撞 AVPlayer 嗅探缺陷——改为打开文件后直赋
  `player.fdSrc={fd,offset:0,length}`（精确 length）。
- **④Copilot 一轮审查加固（b8ff989，7 条）**：下载日志脱敏、完整性门禁 fail-closed、
  下载 key 竞态、播放缓存填充段扫描、416 严格重验、请求签名头精准匹配、环回桥
  改走 fd 描述符。
- **⑤二轮复审边界加固（b5c136d，8 条）**：凭据域截断防泄漏、self-heal 与
  `currentMediaUrl` 配对防误删在线源、aborted 与失败清理区分、`file://` 路径
  归一化、分享直链离线短路防坏副本、快速路径取消检查、经已打开 fd 取 size、
  补充测试用例。
- 验证：各轮服务器侧构建 + codelinter 改动文件 0 error + `hvigorw test` 编译级
  0 error；新增 `PlaybackFailurePolicy`（6）/`DownloadRow`（4）等单测。坏文件
  5400106 与修复效果由用户真机日志实证（legacy 源 + fdSrc 后本地下载可播）；
  断网/杀进程恢复、自定义目录下载等设备侧自动化回归仍待真机。
