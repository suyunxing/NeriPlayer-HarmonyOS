# NeriPlayer HarmonyOS 历史验证记录（§7.4~§7.23）

> 从 `docs/hm.md` 外移于 2026-10-22（原 §7.4~§7.23）。**这些是逐轮验证取证记录，属历史证据，不代表当前能力**——引用时按 AGENTS.md「历史文档中的已完成/已实测只能视为历史记录」处理。
>
> 主线文档现只保留操作性的 §7.1~§7.3（环境准备/命令行构建/签名与 smoke test）与当前状态；需要复查某轮细节时读本文件。
>
> 章节号沿用原 `hm.md` 的 §7.x 编号，因此全仓对 `hm.md §7.4`~`§7.23` 的引用已批量改指 `docs/archive/HM_HISTORY.md §7.x`。

---

### 7.4 2026-08-13 可重复验证记录

| 项目 | 结果 |
| --- | --- |
| `ohpm install --all` | 成功 |
| `hvigorw clean --no-daemon` | `BUILD SUCCESSFUL` |
| Debug `assembleHap` | `BUILD SUCCESSFUL`，生成 unsigned HAP；6 条非阻塞异常处理警告 |
| ArkTS 单元测试 | `Tests run: 3, Failure: 0, Error: 0, Pass: 3` |
| 调试签名与覆盖安装 | 成功；仅用于本地调试 |
| 冷启动 | `EntryAbility` 和应用进程保持 `FOREGROUND` |
| 首页安全区 | 标题不再侵入状态栏；应用保留状态栏和导航栏 |
| 设置 → 账号与登录 | 网易云音乐、Bilibili、YouTube 三行正常渲染并可点击 |
| 登录能力 | 三个平台仍明确标注“待移植”，未声明为已完成 |
| 崩溃检查 | 未发现 `JS_CRASH`、`CPP_CRASH`、`FaultLogger`、Fatal 或未捕获异常特征 |

该 smoke test 只证明当前构建、启动、系统安全区和账号占位入口可用，不代表在线播放、登录、后台播放、AVSession、权限、下载或同步已完成设备验收。

> 2026-08-14 复核注记：上述验证基于迁移前的旧目录布局（`D:\HarmonyOS\` 根与 `D:\Neriplayer` 工程）。工具链现已整体迁至 `D:\HarmonyOS\Tools\`、工程迁至 `D:\HarmonyOS\Project\Neriplayer`，`local.properties` 已同步更新；PATH 与签名脚本的跨版本组合（见 7.1/7.3）调整后尚未整链重跑，下次构建前按 7.2 执行并更新本表。

### 7.5 2026-08-14 迁移后全链验证记录

工具链迁移与新配置（显式 `compileSdkVersion`、新增 `entry/src/ohosTest/` 骨架、重置调试密钥口令、修复用户级 PATH 与环境变量）完成后的完整验证：

| 项目 | 结果 |
| --- | --- |
| `ohpm install --all` | 成功 |
| `hvigorw clean --no-daemon`（CLT hvigorw 6.24.4） | `BUILD SUCCESSFUL` |
| Debug `assembleHap`（entry@default，含显式 compileSdkVersion） | `BUILD SUCCESSFUL in 33s`，unsigned HAP 1,197KB；6 条既知非阻塞警告（LibraryPage/PlaylistDetailPage/DebugPage） |
| 本地单元测试 `hvigorw test` | `BUILD SUCCESSFUL`；LrcParser 覆盖率 44/48 行（3 用例实际执行，报告在 `entry/.test/.../reports/`） |
| ohosTest HAP 构建（entry@ohosTest，新骨架首次编译） | `BUILD SUCCESSFUL in 20s`，unsigned HAP 1,390KB |
| codelinter 静态扫描 | 可用；17 warn + 1 suggestion，无 error（top 规则：avoid-overusing-custom-component ×15、await-thenable ×2、effectkit-blur ×1） |
| 模拟器冷启动 + `hdc tconn 127.0.0.1:5555` | Pura 90（API 24）连上；UDID 经 `bm get --udid` 获取 |
| `sign-local.ps1 -HvigorwPath <CLT hvigorw>` | 5/5 全过：构建 → debug profile → 证书链 → 签名 → 安装 |
| 应用冷启动 smoke | `aa start` 成功；进程存活；无新增 faultlog；截图确认首页正常渲染（标题栏/推荐歌单空态/四 Tab 导航） |
| 设备 ohosTest（`aa test`，OpenHarmonyTestRunner） | `Tests run: 1, Failure: 0, Error: 0, Pass: 1` |

本轮发现并已解决的阻塞：① 用户级 PATH 与 `DEVECO_SDK_HOME` 等三个环境变量残留迁移前旧路径（已修）；② DevEco 26 Beta2 的 hvigor 不能构建 6.1.1(24) 工程（构建固定走 CLT hvigorw，26 Studio 仅提供 jbr java）；③ `sign-local.ps1` 加入中文注释后因 PowerShell 5.1 按 GBK 解析无 BOM UTF-8 而静默失效（仓库 `.ps1` 必须纯 ASCII，已写入 AGENTS.md）；④ 调试密钥旧口令未知（已用 SDK stock 密钥对重加密为新 33 位口令，存用户级 `NERIPLAYER_SIGNING_PASSWORD`，原文件有备份）。
仍未就绪：API 26 模拟器镜像未下载（鸿蒙 7.0 设备侧验证需先在 SDK Manager 补齐）；真机测试未执行。**2026-08-26 更新**：`tablet_x86`（7.0.0-B2）与 `pc_all_x86`（7.0.0-B1）两份 Beta 镜像已在 DevEco GUI 内下载并完成设备回归（见 §7.1 环境准备的镜像清单与 `RELEASE_CHECKLIST.md` §1）；**API 26 SDK 仍未装**（`compileSdkVersion` 保持 24 不动），真机测试仍未执行。

### 7.6 2026-08-16 M1 播放核心补强验证记录（Pura 90 模拟器，API 24）

- 本地单测 42 用例全绿（Lrc 3 + PersistedPlaybackState 5 + QueueEngine 21 + AudioInterruptPolicy 6 + SleepTimer 7），命令 `hvigorw.bat test --mode module -p product=default -p buildMode=debug --no-daemon`。
- entry@default 与 entry@ohosTest 构建 BUILD SUCCESSFUL；codelinter 与基线持平（17 warn + 1 suggestion，另 2 条 await-seek warn 为存量）。
- ohosTest 4/4（aa test）：ActsAbilityTest、ActsPlaybackStateRestoreTest×2（冷启动恢复队列+索引+位置+模式、损坏兜底）、ActsPlaybackSmokeTest（真实网络音频 `w3schools.com/html/horse.mp3`：initialized→prepared→audioInterruptMode=SHARE_MODE→playing→paused→release 全链通过，证明模拟器外网可达且 AVPlayer 中断模式可设置）。
- 冷启动 + force-stop 重启恢复 smoke：两次启动均打出 `PlayerManager restored queue: 3 songs at index 1`（应用级 preferences 跨进程/跨模块共享，AppPreferences 已改 getApplicationContext）。
- 平台事实（API 24 实证）：
  - preferences 的 UIAbilityContext 指向模块级 `haps/<module>/preferences`，必须 `context.getApplicationContext()` 才是应用级共享文件；`AbilityDelegator.getAppContext()` 构造的 context 被 preferences 判 invalid（stageMode=false）。
  - AVPlayer.on('audioInterrupt') 事件 `audio.InterruptEvent{hintType,forceType}`，SHARE_MODE 须在 prepared 后、首次 play 前设置；RESUME 恒为 SHARE 需应用主动 play（文档 https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/audio-playback-concurrency）。
  - `backgroundTaskManager.startBackgroundRunning` 在 API 24 必传 wantAgent（`(context, BackgroundMode, WantAgent)` 重载），权限 ohos.permission.KEEP_BACKGROUND_RUNNING；后台音频必须 AVSession + AUDIO_PLAYBACK 长时任务（https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-background-scene）。
  - AVSession off() 只接受字面量事件名；AVMetadata 封面字段为 mediaImage（string|PixelMap）。
  - hypium 1.0.28 不 await async beforeAll/it 钩子（beforeAll 内异步初始化不可靠，用例内自行 await 幂等 init）。
- 未自动化（模拟器 UI 自动化不可行，待人工/真机复核）：搜索→播放 UI 全流程、双媒体竞争中断、熄屏 30 分钟长播、锁屏/控制中心封面显示。

### 7.7 2026-08-16 M3 下载管线验证记录（Pura 90 模拟器，API 24）

- ActsDownloadSmokeTest 两次通过：网易云搜索「晴天」→DownloadEngine.enqueue→DIRECT 传输 5,889,065 字节→commit 至 `<filesDir>/Download/NeriPlayer/netease - 周杰伦*.m4a`→编目完整→文件只读可开→再次 enqueue 防重复短路。全套 ohosTest 8/8（Ability+Restore×2+PlaybackSmoke+SchemaRecovery×3+DownloadSmoke）。
- 主应用冷启动 smoke（含离线短路/双轨收口改动）无崩溃；本地单测通过（含 DownloadTaskStore 域 23 用例，两轮验证退出码 0）；entry@default/entry@ohosTest BUILD SUCCESSFUL；codelinter 18 warn+1 suggestion 与基线持平。
- ohosTest HAP 签名：与 sign-local.ps1 相同的 hap-sign-tool sign-app 命令手动签 `entry-ohosTest-unsigned.hap`（复用 signing/ 材料+同一 UDID），debug profile 无模块限制，entry/entry_test 共用可行。
- 平台事实（API 24 实证）：
  - **模拟器熄屏/锁屏跑 aa test 必失败**：TestAbility onForeground 后 ~90ms 被切后台销毁，输出 `TestFinished-ResultCode: -2 TestAbility onDestroy unexpectedly!`，hypium 无任何用例执行痕迹（hilog 特征：完整 onCreate→onWindowStageCreate→onForeground→onBackground→onDestroy 链）。跑设备测试前必须 `hdc shell "power-shell wakeup; power-shell setmode 602"`（唤醒+常亮），锁屏时另加 uinput 上滑解锁。
  - `http.requestInStream` 的 promise 与 dataEnd 事件时序不保证先后：传输成功（NETSTACK RespCode 206、字节完整）时 promise 可能晚于 dataEnd settle，若 dataEnd 固定 resolve(0) 会屏蔽真实响应码——流式下载成功判定应以「dataEnd 到达+接收字节校验」为准，响应码仅作错误分类（HttpStreamDownloader/DownloadEngine.transferSizeComplete 按此实现，对齐 Android isTransferSizeComplete）。
  - ArkTS 类字段须有初始化器（`x: string = ''`）+ constructor 赋值后才可靠参与 JSON.stringify(this)；`JSON.stringify(arr.map(e => e.toJson()))` 会产生 JSON 字符串数组的双重序列化，按对象数组解析时静默退化为全空条目（下载编目 bug 根因，已修复并加空行自愈过滤）。
- 未自动化（待复核）：下载中途杀进程→重启续传端到端（队列持久化+replace 恢复语义有单测）；断网暂停/恢复设备实测（模拟器禁网有断 hdc 风险，netUnavailable 路径有单测）；离线播放 UI 人工核验；编目单值超长（>8KB）场景。

### 7.8 2026-08-17 M4.1/M4.2 平台登录与凭据验证记录（Pura 90 模拟器，API 24）

| 项 | 结果 |
| --- | --- |
| entry@default / entry@ohosTest 构建 | 双 BUILD SUCCESSFUL（CLT hvigorw 6.24.4） |
| 本地单测 `hvigorw test` | 全绿（存量 42 + QrEncoder 5 + NeteaseAuth 7 = 54 用例） |
| codelinter | 18 warn + 1 suggestion，与基线持平，0 error，新增文件零缺陷 |
| 模拟器 ohosTest（全套） | **14/14**（原 8 + 新增 ActsCredentialStoreTest 3 + ActsNeteaseCookieRepositoryTest 2 + ActsNeteaseQrLoginTest 1） |
| 主应用冷启动 | force-stop 后 aa start 存活（EntryAbility 接 NeteaseCookieRepository.init() 无崩溃） |

要点与坑：

- **`@ohos.security.asset` 在 API 24 模拟器可用**：ActsCredentialStoreTest 实证 put→get→remove 往返与 backendName='asset'（add 用 CONFLICT_RESOLUTION=OVERWRITE 免 update 分支；query 用 RETURN_TYPE=ALL 取 SECRET Uint8Array 后 `util.TextDecoder.decodeToString`）。降级链路已实现但本环境未触发：服务不可用类错误码（24000001/10/11/12/13/17）→ 会话内存（设置页显示 backend 状态），明文 preferences 存凭据被红线禁止。
- **QR 生成器**（`util/QrEncoder.ets`，字节模式/ECC M/v1-10）：与 segno 参考实现字节级对齐是唯一验收标准。调试中确认的规范细节：v1 无定位图案；定位中心表 `ALIGNMENT_POS[version-2]`（v3=(6,22) 而非 (6,26)）；格式信息必须先于数据放置（否则数据位占用格式区）；segno `make()` 默认 `boost_error=True` 会静默升纠错级（夹具必须 `boost_error=False`）；码字流整字节对齐时 segno 补一个 0x00 再开始 EC/11 交替；自动掩码评分须在格式/版本信息未写入（视为亮）的矩阵上进行。4 夹具（v1/v3/v9/v10）+152 组合扫描+10 自动掩码载荷全部一致（开发用 Node 原型验证后转录）。
- **QR 登录真网 smoke**：createSession（weapi /weapi/login/qrcode/unikey）→ qrContent 含 codekey；checkLogin（/weapi/login/qrcode/client/login）对未扫码的 fresh key 返回 801。803 确认路径（jar cookie 经 /weapi/w/nuser/account/get 校验 + x-refresh-token 头兜底种 MUSIC_U）需真机扫码，未自动化。
- **ohosTest HAP 手动签名**（复用 §7.7 结论）：sign-local.ps1 生成 signing/ 材料后，对 `entry-ohosTest-unsigned.hap` 用相同 hap-sign-tool sign-app 命令（本记录实测 `-compatibleVersion 9`）签名安装即可。
- 模拟器跑 aa test 前仍须 `power-shell wakeup; power-shell setmode 602`（§7.7 坑）。

### 7.9 2026-08-18 GitHub Actions CI 上线记录

- 仓库根 `.github/workflows/harmonyos-ci.yml`（GitHub `suyunxing/NeriPlayer-HarmonyOS`，私有，记录时默认分支 `su`；**2026-08-31 复核已切换为 `dev`**，push/PR 触发规则未变）。触发：push 到 `main`、`dev`，PR 到 `main`、`dev` 或迁移期兼容分支 `su`（直接 push 到 `su` 不触发；paths 限定 `NeriPlayer-HarmonyOS/**` 与 workflow 自身）+ 手动 `workflow_dispatch`；同一 PR 或分支并发取消旧跑。dev 分支上早先手写的 `build-pr.yml` 草稿（npm install/hvigor 命令不可用）已删除，以本文件为准。
- 工具链：`ErBWs/setup-ohos@v2` action，从社区镜像仓库 `ErBWs/ohos-sdk` Releases 下载 Command Line Tools **6.1.1.280**（SDK 6.1.1.125 / API 24，与本机 CLT 6.1.1.300 同 SDK 基线；hvigorw/ohpm/Node 进 PATH，`cache: true` 缓存 `~/ohos-sdk`）。华为官网 CLT 下载需账号登录无法直链，镜像分卷资产带 sha256 校验。**不要用镜像里的 26.0.0.621**：其 hvigor 6.26.x 不能构建 6.1.1(24) 工程（同 7.1 的 00303031 限制）。
- 步骤：`apt libgl1-mesa-dev` → setup → `ohpm install --all` → debug `assembleHap` → 上传 debug unsigned HAP（PR 保留）→ push/手动运行时再构建并上传 release unsigned HAP（14 天）→ Linux 单测诊断。**hypium 本地 runner 在 Linux CI 上挂死**（`UnitTestArkTS` 编译完成后 `> hvigor Linux` 起零输出；本机 Windows 同命令可完成），故单测限时 4 分钟、保留退出码但不阻塞构建，打印 `.test` 目录树并上传 `test-output` artifact。缓存 `~/ohos-sdk`（action 自带）、`~/.ohpm`、`~/.hvigor`。
- 已知事实：hypium 断言失败不会使 `hvigorw test` 非零退出（本机 StreamHeaders 用例失败仍 BUILD SUCCESSFUL/EXIT 0），CI 的单测把关需解析报告而非依赖退出码；Linux 挂死根因未明，修复后应移除限时与非阻塞。
- 2026-08-18 首轮验证：run 32048335317（dev）单测步骤 40 分钟零输出超时取消；二轮 run 32083328097 通过（conclusion success）——单测 `exit=124` 挂死复现（`.test` 下仅 testability 骨架、outputs 从未生成），debug/release HAP 分别 19s/14s 构建成功，`hap-unsigned-2`（782KB）产物正常。工具链下载+解压约 3 分钟；被取消的 run 不写 actions/cache，需完整成功跑一次后后续 run 才命中缓存。

### 7.10 2026-08-19 M5.3 GitHub 传输层验证记录（Pura 90 模拟器，API 24）

- 本地单测 316/316（284 存量+32 新增，fake 执行器驱动 Git Data API 全流水线与错误分类）；entry@default / entry@ohosTest BUILD SUCCESSFUL；codelinter 24 warn+1 suggestion 基线持平 0 error；全套 ohosTest **25/25**，其中 **ActsGitHubTransportTest 5/5 真网**（octocat/Hello-World 匿名公开读：repo info→branch head→raw README；backup.json 缺失→null snapshot；匿名与无效 Bearer `/user`→401→TOKEN_EXPIRED；无效 token `updateBranchRef` PATCH→401，即 PATCH 请求行被 GitHub 认真接受而非 404/405）；冷启动 smoke 无 crash。
- **平台事实（API 24 实证 + netstack 源码/文档三重核对）**：
  - `@ohos.net.http` 的 `RequestMethod` 枚举无 PATCH（OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT），但 `HttpRequestOptions.customMethod?: string`（**@since 23**，本机 SDK d.ts:576）可发任意自定义方法：netstack `ParseMethod()` 优先读 customMethod、`CURLOPT_CUSTOMREQUEST` 写请求行、body 非空走 `CURLOPT_POST+POSTFIELDS`——`customMethod:'PATCH'` + `method:POST`（保证 body 上传）= 真 PATCH 带 body。M5.3 的 GitHub 同步乐观锁（PATCH /git/refs force:false）依赖此。
  - **GitHub REST「合并」端点不能当乐观锁用**（doc-researcher 私有仓库逐 case 实测，2026-08-19）：`POST /merges` base 未分叉时也必然创建双父 merge commit、无 fast-forward 校验、并发推进时若无文件冲突照样成功——无法表达「base 被推进则失败」；备选 GraphQL `updateRef` 的 `refId` 是 Ref 的全局 Node ID（非 "refs/heads/main" 字符串，需先 query 取 ID），非 ff 时返回 HTTP 200 + errors[].type=UNPROCESSABLE（message 原文拼错为 "fast-foward"，判定勿按正确拼写匹配）。最终定案用 customMethod PATCH 直连 REST，与 Android 语义完全一致。
  - 模拟器跑长 aa test：`power-shell setmode 602` 的常亮只维持 ~10s（覆盖时间被重置），必须再 `power-shell timeout -o 600000` 延长，否则测试中途熄屏仍触发 onDestroy unexpectedly（本轮 25 用例耗时约 3 分钟曾两度复现）；锁屏状态另需 uinput 上滑解锁（§7.7 坑不变）。
  - Emulator.bat 冷启动在部分 shell 环境下进程不驻留（无窗口即退），可用 `Emulator.exe -start 'Pura 90'` 直启（返回码 0 且 GUI+crash-service 进程驻留）。
  - Git Bash 下 hdc 对绝对路径参数会把 Git Bash cwd 拼成非法路径报假 fail，本地 HAP 路径用相对路径（install 用 `cd` 到产物目录后传文件名）。
  - `SyncDataJsonCodec.escapeJsonString()` 返回**带引号的完整 JSON 字符串字面量**（`'"'+escaped+'"'`），不是纯转义文本——拼接请求体时外层不要再手写引号（双重引号产出坏 JSON，GitHub 必 400；M5.3 单测拦截的真 bug）。
- 未自动化（待复核）：带真 PAT 的写路径端到端（真实 blob→tree→commit→PATCH ref 提交、设置页测试连接/创建仓库/远端检查 UI 流）需用户提供 PAT 人工验证；「立即同步」完整三路合并闭环属 M5.5。
- 产物为 unsigned HAP：CI 无签名材料，签名仍在本地走 7.3 的 `sign-local.ps1`（符合"证书与口令不入库"约定）。
- 未纳入 CI：codelinter（存量基线 **24 warn + 2 suggestion**，2026-08-24 M10.1 复核值；2026-08-18 CI 落地时为 17 warn+1 suggestion，差额来自此后新增模块的存量告警，0 error 始终未变——需过滤规则后才可门禁）、ohosTest（需模拟器+签名）、Release 自动发布。后续可选：tag 触发上传 unsigned HAP 到 GitHub Release。
- 2026-08-18 协作配置补齐：新增 `.github/PULL_REQUEST_TEMPLATE.md`、HarmonyOS Bug/Feature/分支整合 Issue Forms、`.github/dependabot.yml`、根目录 `CONTRIBUTING.md` 与 `docs/GITHUB_COLLABORATION.md`；workflow 增加 `contents: read`、关闭 checkout 持久凭据、按 lockfile 失效依赖缓存，并使用 PR 号/分支维度并发组。目标模型为 `main` 稳定、`dev` 集成、个人/feature 分支 PR 协作；`su` 在迁移期只保留 PR 检查，不响应直接 push。未修改 Android 参照工程与业务源码。

### 7.11 2026-09-07 下载目录选择落地记录（服务器 Linux CLT 26.0.0.821，无设备）

- 实现（分支 `feature/下载目录选择`）：设置→下载设置→「下载目录」行（原「目录选择待移植」占位替换）+ 自定义时追加「恢复默认目录」确认行。新增 `download/DownloadDirectory.ets`（纯逻辑，8 单测）与 `download/DownloadDirectoryManager.ets`（picker/fileShare 胶水）；`DownloadStorage` 目录解析改为「配置的 URI 优先，否则沙箱默认」，自定义目录 commit 从 `renameSync` 改为 fd 对拷（`FileUri(...).path` 转换后 `openSync(CREATE)`），`init` 对自定义目录跳过 `ensureDir`；`DownloadEngine.init` 追加冷启动 `activatePermission`；设置 key `np.download_directory_uri`/`np.download_directory_label`（空=默认，对齐 Android `download_directory_uri`/`_label` 双 key 语义）。
- 平台事实（官方文档 + 本机 SDK d.ts 核实，**非设备实证**）：
  - 文件夹选择现行 API 是 `DocumentSelectOptions.selectMode = picker.DocumentSelectMode.FOLDER`（API 11+，SC `SystemCapability.FileManagement.UserFileService.FolderSelection`；不存在 `documentViewMode`）。官方《选择用户文件》指南注明 **FOLDER 类型在 Phone 设备 26.0.0 起才支持**——本工程 6.1.1(24) 设备上 `canIUse` 预计 false，入口已做降级 toast。`select()` 直接返回 `string[]`（无 `DocumentSelectResult` 包装）。https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file
  - picker 返回的目录 uri 只有临时读写授权；跨重启须 `fileShare.persistPermission`（API 11+，需 `module.json5` 声明 `ohos.permission.FILE_ACCESS_PERSIST`，按 system_grant 方式声明即用、无运行时弹窗），且**每次冷启动须 `activatePermission` 重新激活**（持久化授权不会自动加载）。`PolicyInfo` 为 `{uri: string, operationMode: number}`，读写组合 `READ_MODE | WRITE_MODE`。https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission
  - fs 对目录 URI 的操作边界：`openSync(uri + '/<name>', READ_WRITE|CREATE)`（官方 DOWNLOAD 示例即此写法，建议先 `new FileUri(...).path` 转换）与 `fs.stat(path)`（path 参数 API 22+ 支持 URI）有文档承诺；`renameSync`/`mkdirSync`/`accessSync`/`unlinkSync`/`listFileSync` 参数文档只写「应用沙箱路径」，对 URI 不可依赖——这是 commit 改 fd 对拷、init 跳过 ensureDir 的依据。
- 验证（服务器，2026-09-07）：`hvigorw --no-daemon assembleHap` BUILD SUCCESSFUL；`hvigorw test` 编译级 0 error（执行阶段挂死为 §服务器已知限制，新用例已编入测试 abc，真实计数待 Windows 工作站）；codelinter 改动文件 **0 新增**（全仓现值 5 error + 23 warn + 3 suggestion，5 个 `await-thenable` error 均在 8 月存量文件——AmllLyricsResolver/AppPreferences/CoverColorCacheCore/YtmLoopbackStreamBridge，与 2026-08-24 基线「0 error」漂移，属基线漂移或 codelinter 版本变化，待单独复核，非本次引入）。
- 未验证（设备侧全部）：API 24 真机/模拟器上 `canIUse(FolderSelection)` 实际值；FOLDER 选择器实际拉起与返回 uri 形态；persist/activate 真实生效；uri 下创建文件/中文文件名/播放（catalog 存 uri 后 `openSync(READ_ONLY)`）冷启动可读；`FILE_ACCESS_PERSIST` 在真机的授予行为（华为在线权限列表页 JS 渲染未能核对该权限级别）。恢复默认后旧目录授权保留策略（保播放）未在设备回归。

### 7.12 2026-09-07 API 26 全量迁移记录（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/api26-migration`）

工程从 6.1.1(24) 整体迁移到 26.0.0(26)。所有结论以本机 SDK `.d.ts`（`/opt/command-line-tools/sdk/default`，apiVersion 26，releaseType Release）与官方文档为依据，**无任何设备实证**。

- 配置：根 `build-profile.json5` 的 `compatibleSdkVersion`/`targetSdkVersion` 均改为 `"26.0.0"`（纯 SemVer，带 `(26)` 后缀会被 hvigor 拒绝）。`module.json5`/`app.json5` 无需配套改动（minAPIVersion/targetAPIVersion 由打包工具自动注入）。
- 弃用接口修复（编译器在新基线暴露，全部替换为官方 `@useinstead`）：
  - `util.TextDecoder.decodeWithStream`（@deprecated since 12）→ `decodeToString`：`download/DownloadStorage.ets`、`ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets`。
  - 全局 `animateTo` → `UIContext.animateTo`：`view/pages/NowPlayingPage.ets:154`（封面 crossfade）。
  - `AlertDialog.show`（@useinstead `UIContext#showAlertDialog`）→ `this.getUIContext().showAlertDialog`：`view/pages/SettingsDetailPage.ets` 6 处确认对话框。
- 有意保留的弃用：`app/diagnostics/CrashEventWatcher.ets` 的 `FaultLogger.querySelfFaultLog` 拉取通道（faultLogger 模块 @deprecated since 18，官方指向 hiAppEvent，但新版 `@ohos.hiviewdfx.hiAppEvent` 仍**无历史故障查询接口**，addWatcher 只订阅不回放；`FaultLogExtensionAbility` 是需注册 ExtensionAbility 的延迟通知机制，架构改造代价大）。该组弃用告警为已知项。
- 新特性接入（均为既有功能的 API 26 升级）：
  - `player/AVSessionManager.ets`：`setMediaCenterControlType`（@since 26）向播控中心显式声明按钮集 `playNext/playPrevious/setSpeed/setLoopMode/toggleFavorite`（与 `on()` 注册命令一一对应；失败降级为系统默认布局，不阻塞会话）。
  - `player/BackgroundTaskRunner.ets`：`continuousTaskCancel` 日志接入 `detailedReason`（@since 26，`ContinuousTaskDetailedCancelReason`，可区分用户划除通知(3)与播放合规审计(6)等精确触发；字段缺省时留空兼容）。
- 评估后不接入（结论备查）：
  - `window.setImageForRecent`（多任务卡片自定义封面，@since 20 在 26 权限列表中开放权限名）：需 `ohos.permission.MANAGE_RECENT_SNAPSHOT`（system_basic 级，三方应用不可申请），跳过。
  - AVPlayer 原生播放列表（`addPlaybackMediaSource`/`playlistLoopMode`/`onPlaybackContentChanged`，@since 26）与 `createAVDownloaderManager` 流式下载（@since 26）：与既有 `QueueEngine` 状态机/自研下载引擎（Range+If-Range 指纹、HLS checkpoint）是整体替换关系而非增量升级，牵动播放恢复、一起听同步与 1300+ 单测，本轮不做，留待独立专项。
  - AVPlayer `seek` 在 26 仍为 `void`（无 Promise 重载），原样保留。
- targetSdk 26 行为变更核对（逐项走查，均不受影响）：后台「真播放」审计收紧——本工程暂停即 `stopBackgroundRunning`，已合规；沙箱 stat/access 收紧——无硬编码沙箱路径；剪贴板读取需 PasteButton/权限——工程只写不读；Dialog/Toast 默认沉浸材质——工程弹窗均走系统默认样式，与 glass UI 方向一致，**视觉实际效果待设备复核**；`WindowProperties.type` 更名 `windowType`、avSession `playFromAssetId`（since 20 废弃）——工程均未使用。
- 验证（服务器）：`hvigorw --no-daemon assembleHap` BUILD SUCCESSFUL 且无新增弃用告警；`hvigorw test` 编译级 0 error（执行阶段挂死为 Linux 已知限制，真实通过计数待 Windows 工作站）；codelinter 全仓 5 error + 23 warn + 3 suggestion，与迁移前 stash 基线**逐字节一致**（5 个 `await-thenable` error 为 CLT 26.0.0.105 codelinter 对 8 月存量文件的误报，见 §7.11），本次 8 个改动文件 0 error 0 warn。
- 未验证（设备侧全部）：播控中心按钮实际渲染；`detailedReason` 实际取值分布；26 镜像上全功能回归（播放/下载/同步/一起听）；弹窗沉浸材质视觉。`compatibleSdkVersion` 抬至 26.0.0 后 26 以下设备无法安装，属预期取舍（用户要求全量迁移）。

### 7.13 2026-09-07 API 26 原生播放列表桥接与播放缓存落地记录（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/api26-migration`）

§7.12 中「评估后不接入」的两项按既定定位落地：原生播放列表作为 QueueEngine 之下的**换源加速层**（不替换状态机），AVDownloaderManager 作为**播放缓存补充**（不替换下载引擎）。所有平台调用 8s 超时包裹 + 首次硬失败按进程闭锁（防 `setLoudnessGain` 式挂死桩），全部带回退路径。

- **原生播放列表桥（gapless 切歌）** `player/AvPlaylistBridge.ets` + 纯策略 `player/AvPlaylistPolicy.ets`：
  - 架构：`handleCompletion` 的全部仲裁（睡眠定时、一起听房间、单曲循环重播、TRACK_FINISHED 上报）保持应用侧；仅当仲裁决定前进时，才用内核 `advanceToNextMediaSource()` 换源（无 reset/prepare 空窗）。`playlistLoopMode` 钉死 `NONE`，系统永不自行前进。
  - 预热条件（AvPlaylistPolicy.shouldPrimeNext，5 门全查）：非单曲循环、队列 ≥2、无一起听会话、引擎会前进、**下一首可离线解析**（下载目录条目或本地文件）。网络流永不预热：预解析每首歌多打一次平台 API（B 站风控教训）且签名 URL 在前进时大概率过期。
  - 预测一致性：`peekNextIndex` 用 `QueueEngine.toJson()/fromJson()` 全量克隆（含种子随机态）预测 `next(force)` 落点；完成时若克隆预测 ≠ 桥内缓存索引（模式中途切换等）→ 弃用预热回退 loadSong。`QueueEngine` 补 `getQueueSize()`。
  - fd 生命周期：桥持有预热源的 fd，consume（前进已消费）/abandon（新加载、REPLAY、STOP、清空队列）/失败三条路径都恰好释放一次。
  - PlayerManager 接线：`loadSong` 前缀抽为 `beginTrackTransition`（原生前进复用同一套元数据/历史/统计/自动匹配副作用）；`ensurePlayer` attach；`clearQueue`/`loadSong` 开头 abandon。
- **播放缓存** `player/PlaybackCacheManager.ets` + 纯账本 `player/PlaybackCacheLedger.ets`：
  - 设置 `np.playback_cache` 默认关（opt-in，设置→播放设置→「播放缓存（实验）」）。语义：在线流播放成功后后台入队 `addAVDownloadTask`（带防盗链头），完成后系统缓存目录记入 LRU 账本（上限 24、SchemaStore 持久化、驱逐目录 best-effort rmdir、僵尸任务 5 分钟清扫）；下次 `loadSong` 在下载目录之后、房间权威链接之前查缓存命中（`createMediaSourceWithDirectory` 离线秒开；一起听会话中让位；失效命中自愈剔除）。Wi-Fi only（系统默认）。与文件下载引擎并存不替代。
- 单测：新增 `AvPlaylistPolicy.test.ets`（5 例：force 镜像、顺序/随机 peek 精确预测、不变更引擎、五门禁）+ `PlaybackCacheLedger.test.ets`（6 例：命中 touch、LRU 驱逐、刷新不驱逐、remove、JSON 往返、损坏降级），编入本地套件。
- 设备探针（ohosTest，待真机/Windows 跑）：`ActsNativePlaylistProbeTest`（2 例：API 可达性+advance 落点+contentChanged 回传 id、NONE 模式 5s 静默窗不自进）与 `ActsAvDownloaderProbeTest`（1 例：manager 创建→小 MP3 下载完成→getTaskCacheDirectory→目录源 prepare 全链）。
- 验证（服务器）：entry@default assembleHap **BUILD SUCCESSFUL 0 error**；entry@ohosTest assembleHap（含两个探针）**BUILD SUCCESSFUL 0 error**；`hvigorw test` 编译级 0 error（执行挂死为 Linux 已知限制，真实计数待 Windows 工作站）；codelinter 14 个改动文件 **0 新增缺陷**（全仓仍为基线 5 error + 23 warn + 3 suggestion）。
- 未验证（设备侧全部）：gapless 实效与 advance 是否跳过 prepare 周期（探针 1 回答）；NONE 模式是否真不自进（探针 2）；缓存目录跨进程存活与 prepare 可行性（探针 3）；B 站带 Referer 头的下载任务是否被 CDN 接受；缓存命中音频与在线流音质一致性。

### 7.14 2026-09-08～09-14 真机反馈修复与播放页转场波次记录（分支 `dev`，PR #20–#30）

本节为波次汇总；单事件取证在专项文档与看板，不在此重复。波次内各提交以服务器侧构建、改动文件 codelinter、`hvigorw test` 编译级检查为常规门禁（Linux 测试执行段挂死为已知限制），push/PR 由 CI（`harmonyos-ci.yml`）复核；**设备侧结论来自用户真机反馈**（日志/录屏/诊断输出），非本服务器取证。

- **网易云登录四连修复**（3f4dea0f→bd4d9c0→bc19926→fe101cf）：杀后台掉登录（凭据从未落盘 + 冷启动时序）→ 803 后 Set-Cookie 双来源捕获 → Asset `ASSET_TAG_SECRET` 1024 字节上限触发 `AssetError(401)`（自动分块存储 `AssetChunking`）。取证详见 `PORTING_EXECUTION_PLAN.md` 三节「缺陷修复：网易云……（2026-09-08～09）」；扫码链路真机诊断日志实证生效，落盘修复真机复测待验证。
- **下载完整性系列修复**（77a6745→3d655fc→c60dfb1→b8ff989→b5c136d）：分块写入 `offset` 误用致带零洞坏容器、播放失败重试风暴、5400106 双根因（下载源改 legacy 干净接口 + 本地源走 `fdSrc`）、完整性门禁与 8 条边界加固。取证详见 `PORTING_EXECUTION_PLAN.md`「缺陷修复：下载完整性……（2026-09-12～14）」节；坏文件 5400106 由真机日志实证。
- **播放页一镜到底转场整层重写**（654ca5d→26b49aa，PR #24–#28，九轮迭代记录见 `docs/NOW_PLAYING_TRANSITION_20260910.md`）：最终形态为 `bindContentCover` 全屏模态 + 单一进度 `panelAmount` 分阶段**原生属性动画**（S6-core 的 `geometryTransition` 共享元素方案已整层移除；展开 300ms/收起 400ms；`NowPlayingCurves.ets` 先慢后快/回弹自定义曲线）。`Router.push(NOW_PLAYING)` 不再入 NavPathStack，改为翻转 `ui.nowPlayingShown`；起止矩形按真机录屏逐帧标定（HdsTabs miniBar 槽位测量只反映槽位布局矩形，需标定偏移换算药丸视觉矩形）。审查跟进：计时器竞态/压暗跳变/宽屏锚点（26b49aa）、迷你条切页槽位重建时播放键符号动效误闪（552df87，`symbolTrigger` 初值改 -1）。观感经用户真机多轮反馈修正；折返打断、歌词页返回、宽屏形态仍待系统真机回归。
- **壳层沉浸改版**（f38205d→8958d16→073b852→4edac60→b9589db）：外壳改用 `HdsNavigation`（§S 阶段 S0「HdsNavigation 内容子树不挂载已回退」的模拟器结论被后续版本推翻，自建 `TitleBarBlurBackdrop` 等价实现随之删除）、标题栏 `ScrollEffectType.GRADIENT_BLUR` 渐变模糊并经 `expandSafeArea(SYSTEM/CUTOUT, TOP|BOTTOM)` 延伸到状态栏后；探索/资料库/设置页与首页统一内容穿透（`.clip(false)` + 列表顶部 `expandSafeArea`）；标题栏移除系统返回与「刷新推荐」按钮。**未验证**：渐变模糊材质在真机的实际渲染档位。
- **音量淡入淡出**（54fb31f→c3acdbd）：`VolumeFader` 纯状态机 25ms 插值接入 `PlayerManager` 三类路径，后设置化为 `np.playback_fade` 总开关 + 双向时长滑条；详见 `FEATURE_MATRIX.md` 对应行。设备端听感未验证。
- **资料库收尾**（d9b209c）：统计卡片图标/新建按钮/歌单图标随封面取色重染，消除主题色残留。
- **工程协作**（d68f4f3、cbef581、8de4ca1）：配置 Copilot 代码审查（`.github/skills/harmonyos-code-review/SKILL.md`、`.github/copilot-instructions.md`、`.github/instructions/` 按 ArkTS 与 CI workflow 两域分流）；根目录与工程 README 按上游风格重写；`NeriPlayer-master/` 解除 Git 追踪并加入 `.gitignore`（磁盘保留为只读参照快照；`NeriPlayer-ASCF/` 仍在版本控制中）。
- **审查工具切换**（2026-09-16）：应用户要求移除上一条的 Copilot 审查 4 个配置文件（GitHub 侧 `copilot-pull-request-reviewer` 与 `chatgpt-codex-connector` 两个审查 App 由用户网页端停用）；AI 审查改走 CodeRabbit（`.coderabbit.yaml`，App 待装、仓库转公开后免费）+ gitleaks 密钥扫描（`.github/workflows/gitleaks.yml`，已上线）。

### 7.15 2026-09-16 二、三级页沉浸渐变模糊标题栏统一（服务器 Linux CLT 26.0.0.105，无设备，分支 `settings-card-radius`）

将 §7.14「壳层沉浸改版」的 `HdsNavigation` GRADIENT_BLUR 标题栏模式下沉到全部 12 个路由页（本地歌单/网易云歌单/B 站收藏夹/专辑/艺人/播放历史/播放统计/下载管理/一起听/调试/设置详情/协议文档），按官方 UIDesignKit「组件导航-开发实例」（`ui-design-navigation-dynamic-blur-demo`）的 HdsNavDestination 写法：

- **共享配置** `view/components/HdsSubPage.ets`（新文件）：`subPageTitleBar(title, menu?, subTitle?)` 构造与外壳逐参数对齐的 titleBar（`ScrollEffectType.GRADIENT_BLUR` 0→8vp + `BlurStrategy.ADAPTIVE` + `systemMaterialEffect`（HdsLight 探测降级）+ `enableComponentSafeArea: true`）；`SubPageBottomFade` 组件复刻 MainShell 手势条渐变遮罩（页面底色 0xD9→透明，`@StorageProp('ui.bottomLiftVp')` 跟随避让区）。
- **MainShell.pageMap**：去掉共享 `NavDestination().hideTitleBar(true)` 包装层，各路由页自身以 `HdsNavDestination` 为根（官方允许与标准 NavDestination 混用；未知路由兜底分支保留标准 NavDestination）。`onWillDisappear → Router.notifyReturned()` 返回广播随之下沉到各页。
- **每页模式**：根 `HdsNavDestination().titleBar(...).bindToScrollable([scroller]).backgroundColor(Transparent).ignoreLayoutSafeArea([SYSTEM],[BOTTOM]).onWillDisappear(...)`；滚动容器 `.clip(false)`（内容滚入标题栏下方被渐变模糊覆盖）+ List 加 `.cachedCount(3, true)`（官方 FAQ：防穿透区列表项闪空）；`ignoreLayoutSafeArea` 底边延伸后列表尾部加 `bottomLift + 32` 让位 spacer、Scroll 类页面改 padding 尾部同高。
- **结构归一**：原「固定头部 + 内嵌 List」的页面（三个歌单页、艺人页、历史页）把头图/搜索框/胶囊等并入同一个 List/Scroll 作首组 ListItem，保证整页内容可穿到标题栏下；StatsPage 曲目榜（≤100 行）直接平铺进外层 Scroll 免嵌套滚动。原页内头部操作迁入 titleBar 菜单（RecentPage 排序+说明/导出/导入/清除 5 项、DownloadsPage 清空记录、PlaylistDetailPage 歌单管理；sys.symbol 资源名经 `toolchains/id_defined.json` 核实存在）。LegalDocPage 双模式：新增 `asRoute` 属性，全屏路由走 HdsNavDestination，免责声明浮层保留自绘头部。
- **模拟器风险**：S4 曾实测 HdsNavDestination 在模拟器只渲染标题栏 chrome 不挂载内容子树（8958d16 注释）；同类的 HdsNavigation 外壳问题真机不复现（2026-09-10 用户确认），子页按官方标准启用，**模拟器行为待复核、真机渲染未验证**。
- 验证（服务器）：entry@default assembleHap **BUILD SUCCESSFUL 0 error**（首轮 10 error 为 `.margin()` 链在带尾随闭包的 `PlaylistHeader{...}` 之后的 ArkTS 语法限制，改 Column 包裹后清零）；codelinter 14 个改动文件 **0 error / 8 warn**（其中 6 warn 为 BiliFav/Netease 存量性能提示、2 warn 为 custom-component 风格提示——SubPageBottomFade 因自带 `@StorageProp` 响应式跟踪保留组件形态）。
- **修订（2026-09-16 用户真机截图反馈后）**：首版照官方 demo 用 `enableComponentSafeArea: true` 让内容避开标题栏，真机实测标题栏底下没有页面内容，光感材质渲染出自己的暖色底板，顶部出现一条淡米黄断层（与内容区冷灰背景清晰分界）；底部渐变带过矮过黑（仅 bottomLift+8、起始即 0xD9），与首页观感差距大。修复：子页布局模型整体对齐首页外壳——titleBar 去掉 `enableComponentSafeArea`（其余参数与外壳逐字一致），`ignoreLayoutSafeArea` 补 `TOP` 把内容根拉到全窗 y=0（标题栏浮在自己页面内容之上，材质模糊采样页面自身），List 首加 56vp 让位 spacer / Scroll 内容 padding top 56（让位量随内容滚走，同首页）；底部 `SubPageBottomFade` 重做为首页复合遮罩同款（92vp 渐入 0x99 → 手势条上方 0xD9 → 屏幕底边归零，总高 92+bottomLift+8），尾部让位统一 `bottomLift + SUB_BOTTOM_CLEARANCE_VP(116)`。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 8 warn（无新增）**；真机观感待用户复测。
- **修订二（2026-09-16 二轮真机截图：歌词设置页/网易云歌单页）**：(1) 顶部重合——内容根已在 y=0 但让位只补了 56vp，标题栏实占「状态栏 topInset + 56vp」，首卡约 1/3 被压在标题栏下；首页无此问题是因为首页内容区从状态栏下沿起算。修复：12 页统一 `@StorageProp('ui.topInsetVp')`，让位改 `topInset + SUB_TITLEBAR_SPACE_VP`（StatsPage loading 骨架同步）。(2) 底部黑雾——渐变终止色 `0x00000000` 是**透明黑**，插值穿过半透明黑，浅色主题下底部呈黑雾（首页同写法但该区被悬浮 Tab 栏 + gradientMask 盖住不可见，子页无遮挡直接露出）；修复：`SubPageBottomFade` 全部色标改用页面底色透明变体（含终止色），峰值 0xD9 移到手势带上沿之上 40% 处。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 8 warn（无新增）**；真机观感待复测。
- **修订三（2026-09-16 三轮真机截图）**：修订二把渐变末端回退到透明后，导航指示条区域反而无覆盖，观感是「渐变从导航条上沿才开始」（避开导航条）。修复：`SubPageBottomFade` 色标简化为三段（0x00 → 92vp 处 0x99 → 屏幕最底边 0xD9），末段一路加深直达底边、不避让手势条。复验：assembleHap **BUILD SUCCESSFUL 0 error**、codelinter **0 error / 1 warn（存量）**。

### 7.16 2026-09-18 子页 dock 态迷你条：进入二级页后迷你条下沉为 Tab 栏形态（服务器 Linux CLT 26.0.0.105，无设备，分支 `minibar-dock`）

参照网易云 Android 客户端录屏（用户提供的参考视频）：迷你条常驻悬浮于子页之上，推入二级页时 Tab 栏被盖住，迷你条从药丸原位**扩大到 Tab 栏足迹并落到 Tab 栏位置**，返回时逆向归位。此前本工程子页是全屏 NavDestination，会把 HdsTabs 连同槽位迷你条一起盖住（子页上无任何播放条）。实现：

- **深度状态源**（`view/Router.ets`）：新增 `KEY_SUB_PAGE_DEPTH ('ui.subPageDepth')`，`publishDepth()` 在 push（含 CLEAR/REPLACE_TOP/EVICT 分支）/pop/reset 每次栈操作后同步发布 `NavPathStack.size()`。所有入栈都经 `Router.push`、所有返回都经 `Index.onBackPress → Router.pop`，Router 即深度唯一事实来源（`size()` 栈操作后即时可读——push 防重决策本就依赖该语义）。
- **MiniPlayer `embedded` 形态**（`view/components/MiniPlayer.ets`）：脱离 HdsTabs 槽位独立承载时非紧凑形态去掉自带 {10,10,8} 悬浮卡片外边距（几何由使用方给定），且 `followsBarMaterial()` 恒 false——沉浸光感材质只存在于悬浮栏内部，独立承载必须自绘玻璃。
- **MainShell dock 态覆盖层**（`view/pages/MainShell.ets`）：根 Stack 内 `HdsNavigation` 之上挂 `dockMiniBarOverlay()`（NavDestination 盖不住它，且位于一镜到底压暗层之下）。状态机 `syncDockBar()`（由 `subPageDepth`/`currentSong`/`breakpoint` 三路 @Watch 驱动）：下潜 = 以药丸矩形（已标定的 `miniRect`）挂载 → 延迟一帧翻转到 dock 矩形（悬浮 Tab 栏边距体系：左右 16 = `barSideMargin`、底部 `bottomLift+8` = `barBottomMargin`、高 62 = 非紧凑胶囊）做原生属性动画（350ms Friction）；返回 = 翻回药丸矩形 → 落定后卸载，与槽位内真实迷你条（同位同形，延迟淡入）无缝交还；返回动画中途再次入栈会清卸载计时器并反向重定目标。紧凑/展开两份内容按目标形态交叉淡入淡出（180ms，对读屏/命中同样互斥），规避 40↔62vp 内容重排跳变。悬浮 Tab 栏边距常量提取为 `FLOAT_BAR_SIDE_MARGIN_VP`/`FLOAT_BAR_BOTTOM_GAP_VP` 两处共用。
- **一镜到底锚点适配**：`onNowPlayingRequested` 展开起点在 `subPageDepth > 0` 时取 `dockRect()`（窗口坐标，与 `miniRect` 同系），面板从子页上可见的 dock 条起飞；dock 条透明度/命中沿用真实迷你条的模态开合同规格显隐（展开隐藏、收起后半段延迟淡入）。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（1 条非阻塞 throw 警告）；codelinter 3 个改动文件 **0 error / 0 warn**。**设备侧未验证**：dock 矩形与真实 Tab 栏足迹的像素级对齐（HdsTabs 内部栏高未知，按边距体系推导）、迁移动画与 NavDestination 系统转场的节奏手感、子页列表尾部与 dock 条的遮挡关系，均待真机复测。
- **修订一（2026-09-18 真机首测反馈，两张症状截图）**：(1) 子页上迷你条整层不显示——覆盖层容器透明度复用了 `miniBarHidden()`，而该方法为隐藏槽位真实迷你条新增了 `subPageDepth > 0` 条件，恰好把覆盖层在子页上（深度必 >0）永远置 opacity 0，自相矛盾；修复：覆盖层改用只跟随播放页模态的 `dockOverlayHidden()`（`modalMounted && !closing`）。(2) 返回主页后只剩空药丸壳（无封面/歌名/按钮）——侧滑返回手势与子页标题栏返回键由 Navigation 直接弹栈，不经过 `Router.pop()`，`ui.subPageDepth` 卡在 1，槽位 MiniPlayer 永久隐藏而 HdsTabs 自绘的槽位药丸背景（`enableMiniBarBackground`）仍可见；修复：`Router.notifyReturned()`（各 NavDestination `onWillDisappear` 统一回调，覆盖 Router.pop/系统返回键/侧滑/clear 四条路径）补发 `publishDepth()`，幂等无副作用。
- **修订二（2026-09-18 用户要求子页播放条使用沉浸光感材质）**：SDK 勘察结论——HDS `SystemMaterialParams`（`systemMaterialEffect`）只能在 HdsTabs 悬浮栏 / HdsNavigation/HdsNavDestination 标题栏两处宿主内生效，无独立材质容器组件（无 HdsGlass/HdsFloatBar 之类）；独立悬浮组件挂系统玻璃材质的正道是 ArkUI 底座通用属性 `.systemMaterial(SystemUiMaterial)`（`@ohos.arkui.uiMaterial`，API 26 起，`uiMaterial.ImmersiveMaterial` 默认参数 REGULAR 玻璃质感 + applyShadow 自带投影，官方告诫启用后系统接管背景色/边框/阴影）。实现：`HdsLight` 门面新增 `SystemMaterialCapability`（`isImmersiveMaterialSupported()` 进程内探测缓存 + `ImmersiveMaterial` 实例缓存），`MiniPlayer` embedded 形态背景改挂 `.systemMaterial()`（材质档：背景透明、模糊 NONE、卡片阴影关闭防叠加；不支持设备保持自绘玻璃兜底；HdsTabs 槽位形态行为不变）。首轮构建报 ArkTS 静态字段与静态方法同名 `supported` 标识符冲突，字段改名 `materialSupported` 后 assembleHap **BUILD SUCCESSFUL**、codelinter 2 改动文件 **0 error / 0 warn**；真机材质观感待复测（模拟器/不支持设备走兜底，无回归风险）。

### 7.17 2026-10-01 歌单类长列表滑动掉帧治理：LazyForEach + 封面降采样（服务器 Linux CLT 26.0.0.105，无设备，分支 `perf/cover-scroll-jank`）

用户反馈：进入歌单等大量封面的页面后滑动大幅掉帧（Android 上游与其他鸿蒙音乐应用无此问题）。根因（代码级定位，官方 Image 文档佐证）：

1. **长列表全量 ForEach**：歌单/专辑/艺人/B站收藏/播放历史/搜索结果 7 个页面的歌曲列表都是 `ForEach` 一次性建满全部行——千首级歌单进场即建数千组件、每行各发一次收藏检查异步 DB 查询、各 Image 立即发起网络请求，进场即拥塞。
2. **封面按原图解码**：官方文档明确 ArkUI `Image` 的 `autoResize` **默认 false，按原图尺寸解码**（网易云原图常见 1000px+，单张解码数十 MB 内存），52vp 缩略图也照单全收；且网易云 `picUrl` 存储时不带 `?param=` 尺寸参数，原图整张下载。
3. **SongRow 重复 JSON.parse**：入参是整只歌的 JSON 串，`build()` 内多次直读 `song()`，单行单次渲染触发 5+ 次完整解析，进场即数千次。

修复：

- **`view/components/SongListDataSource.ets`（新增）**：`IDataSource` 实现，`reset()` 整表替换 + `onDataReloaded` 通知；页面 `@State` 数组整体重赋值经 `@Watch` 同步进数据源。
- **7 个页面 ForEach → LazyForEach**：PlaylistDetailPage（歌曲 + 「从播放历史添加」弹窗两个列表）、NeteasePlaylistPage、AlbumPage、ArtistPage、BiliFavPage、RecentPage、ExplorePage；ExplorePage 顺带补 `.cachedCount(3, true)`（此前无，对齐其他页）。**key 含 index**（RecentPage 另含 playCount）：LazyForEach 中 key 未变的行不会重建，删歌/重排/过滤后行内缓存的 index（序号徽标、onPlay 定位）会过期，靠 key 变化强制重建受影响行。歌单按 stableKey 去重、播放历史按 stableKey 去重，key 唯一性成立。
- **SongRow**：`song()` 按 songJson 串比较做惰性缓存（@Prop 重同步自动失效），单次渲染只解析一次；52vp 封面 `Image.autoResize(true)` 按显示尺寸降采样解码 + `coverThumbnailUrl(url, 200)` 显示层拼 `?param=200y200`（`view/components/Ui.ets` 新增；只用于显示，不写回 SongItem、不落库不参与同步，Android 端读 URL 时本就剥 `?param=` 后缀）。
- **其余封面位同规格**：HomePage（118vp 每日推荐 hero/132vp 卡片 → 400、46vp 最近播放 → 200）、LibraryPage 歌单卡、Ui.ets PlaylistCard、DownloadsPage、StatsPage、MiniPlayer、PlaylistHeader 均 `autoResize(true)` + 网易云源拼缩放参数。NowPlayingPage 大封面/模糊背景/取色链路**有意不动**（质量与 S5 取色敏感，非本症状来源）。
- **未做**（记录为后续项）：`SongRow` 未加 `@Reusable`（codelinter `hp-arkui-use-reusable-component` 提示；本轮以行为保守为先，滚动重建成本已由 LazyForEach 界定在视口 + cachedCount 内）；播放队列面板（无封面、纯文本行）未改。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**；codelinter 16 个改动文件 **0 error**（新增 warn 均为存量规则提示，与基线 diff 对比确认为行号平移/建议类）；`build-signed.sh` 签名包已刷新。**设备侧未验证**：滑动帧率改善幅度、千首级歌单进场内存峰值、B 站/NetEase 云缩略图 CDN 兼容性（`?param=` 为网易云图片 CDN 标准参数）待真机复测。
- **修订一（2026-10-01 真机反馈：仍卡且更卡，下滑再上滑封面全部重载）**：首轮改造只做对了「进场不全量建行」，漏算了 LazyForEach 的行销毁语义——滚出视口+cachedCount 的行会被销毁，回滚重进时 aboutToAppear 与 Image 全部重跑：(1) `SongRow.aboutToAppear → LocalPlaylistRepository.isFavorite()` 每次都 `loadAll()` 全量读取+JSON.parse 整个歌单库（无任何内存缓存），ForEach 时代每行只跑一次（进场卡一阵就完），LazyForEach 时代每次行重进视口都跑，千首列表滚动=几百次主线程全量解析，比改造前更卡；(2) 系统 Image 随行销毁重建重新走网络加载/解码，表现为封面反复重载。修复：`LocalPlaylistRepository` 新增收藏键集合进程内缓存（`getFavoriteKeySet`，`saveAllSilent`/`replaceAllFromSync` 统一失效）；新增 `util/LruCache`（纯逻辑，4 条单测）+ `data/CoverCache`（进程级封面 LRU，256 张 × 156px 解码图 ≈25MB 上限，下载拼 `?param=312y312` 缩略、desiredSize 降采样解码、同 URL inflight 去重）+ `view/components/CoverImage`（渲染走缓存，行重建同步命中直接出图；@Prop url 变更重载并丢弃过期响应）；`coverThumbnailUrl` 从 `view/components/Ui.ets` 迁至 `util/CoverUrls.ets`（CoverCache 在 data 层，不反向依赖 view）。歌单/搜索等 7 页行为不变，其余页面（首页/资料库/下载页/迷你条/歌单头图）仍用系统 Image+autoResize，不在滚动高频路径。
### 7.18 2026-10-01 设置页「打赏作者」入口与关于页仓库链接外跳（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/donate-about-link`；本文件 §7.17 在 `perf/cover-scroll-jank` 分支，尚未合入 dev）

- **打赏入口**：设置页「其他」分区新增「打赏作者」（`SETTING_DONATE`，`view/pages/SettingsPage.ets`），二级页（`view/pages/SettingsDetailPage.ets`）顶部说明文案 + 并排两张收款码卡片（`donateCard` @Builder，`Theme.surface` 底、`aspectRatio(1)` + `ImageFit.Contain`）。收款码占位图 `entry/src/main/resources/base/media/donate_wechat.png` / `donate_alipay.png`（720×720 仿二维码样式 PNG，微信绿 #07C160 / 支付宝蓝 #1677FF，脚本生成）；作者把真实收款码图片按同名文件替换即可生效，无需改代码。
- **关于页链接外跳**：仓库链接由安卓原版 `github.com/cwuom/NeriPlayer` 改为鸿蒙移植仓库 `github.com/suyunxing/NeriPlayer-HarmonyOS`（`PROJECT_REPO_URL`），并从纯文本改为可点击。新增 `entry/src/main/ets/util/LinkLauncher.ets`：`openExternalLink(context, url)` 走 `UIAbilityContext.openLink`（API 12+，`OpenLinkOptions.appLinkingOnly: false`——无 App Linking 匹配应用时回落系统默认浏览器；官方本地文档 `OpenLinkOptions` 页确认签名），失败仅 Logger.warn 不打断 UI；调用侧经 AppStorage `abilityContext` 取上下文（本文件既有模式），上下文未就绪时 toast 兜底。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（dev 基线复验）；codelinter 3 个改动/新增文件 **0 error**（SettingsPage 1 warn 命中未改动的 struct 声明行，存量 @Builder 建议类）。**未验证**：真机浏览器外跳（openLink 回落路径）、收款码卡片显示效果；收款码真实图片待作者替换。
### 7.19 2026-10-01 长标题跑马灯（迷你条/播放页/一起听当前曲目）（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/marquee-song-title`；本文件 §7.18 在 `feature/donate-about-link` 分支，尚未合入 dev）

- **方案来源**：参照 HarmonyOS 官方示例仓库 animation-collection（`br_release_hmos` 分支 `pageMarqueeView` 模块 `Marquee.ets`）的跑马灯做法——`Text + textOverflow({ overflow: TextOverflow.MARQUEE })`，非独立 Marquee 组件亦非自绘动画。本工程 API 26 完整覆盖 `marqueeOptions`（`@since 18`）与 `MarqueeUpdatePolicy`（`@since 23`），SDK 头文件 `text.d.ts` 已核对字段（`start/step/spacing/loop/fromStart/delay/fadeout/marqueeStartPolicy/marqueeUpdatePolicy`）。
- **新增共享组件** `entry/src/main/ets/view/components/MarqueeText.ets`：`@Prop text/fontSize/fontWeight/fontColor`，内部 `maxLines(1)` + `TextOverflow.MARQUEE` + `marqueeOptions({ start: true, loop: -1, fadeout: true, marqueeUpdatePolicy: MarqueeUpdatePolicy.DEFAULT })`。行为要点：文本未超宽时静止（引擎自行判定，滚动期 textAlign 失效）；`fadeout` 为引擎两端真 alpha 渐隐（毛玻璃等非纯色背景成立，开启后 clip 锁定）；DEFAULT 更新策略保证切歌后从头重滚；`step` 不设走引擎默认 4vp（调速留待真机反馈）。
- **替换三处当前标题**：① `MiniPlayer.ets` 标题由手写离屏 DST_IN 静态渐隐蒙版（Stack+linearGradient+blendMode 约 27 行）改为 MarqueeText——长标题从「永远看不全的静态截断」变为可滚动读全；② `NowPlayingPage.ets` 标题（22/Bold）由 Ellipsis 改 MarqueeText；③ `ListenTogetherPage.ets` 房间卡「当前曲目」行由 Ellipsis 改 MarqueeText。播放队列弹窗列表项与分享面板副标题维持 Ellipsis（滚动列表内条件跑马灯是反模式，静态展示不滚动）。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL**（42s）；codelinter 4 个改动/新增文件 **0 error**（MarqueeText 1 条「@Builder 替代自定义组件」性能建议 warn，与项目同层组件均为 @Component 的现状一致；NowPlayingPage 2 条 suggestion 为存量 blur 建议，非本轮引入）。**未验证**：真机滚动速度与两端渐隐观感、跑马灯滚动与迷你条横滑切歌手势的叠加表现（本机无设备）。
- **修订一（2026-10-01 每轮滚动前在开头停留 2 秒，用户要求）**：调研确认（官方文档 + ACE 引擎 `text_content_modifier.cpp` 的 `ResumeTextRace`）原生 `delay` 只作用于**轮与轮之间**——引擎对首轮启动强制 `delay=0`（首轮立即滚），它是动画启动延迟而非步间隔。故首轮与切歌后的那一轮由组件自管：`MarqueeText` 挂载（`aboutToAppear`）与 `@Prop text` 变化（`@Watch`）时经 `scheduleStart()` 置 `start=false`（引擎停轮、文字回起点静止，超宽静止期右端仍有 fadeout 渐隐），停满 `MARQUEE_HOLD_MS=2000ms` 再放行 `start=true`；轮与轮之间的停顿交给原生 `delay: 2000`。`aboutToDisappear` 清理未到点的定时器（MiniPlayer 槽位随切 Tab 重建，定时器必须随组件销毁释放）。顺带确认 `onMarqueeStateChange`（API 18+）枚举为 `START/BOUNCE/FINISH`，`loop:1`+回调手动重启方案更耗弃用。验证：assembleHap **BUILD SUCCESSFUL**（26s，分支基线复验）；codelinter 改动文件 **0 defect**。**未验证**：真机上停留节奏观感（同上）。
### 7.20 2026-10-01～02 悬浮栏滚动自适应形变：miniBar 展开/折叠（官方原生联动），滚动位置驱动（服务器 Linux CLT 26.0.0.105，无设备，分支 `scroll-adaptive-floating-bar`）

目标效果（用户参考视频，与官方 Spatialization 示例 dev@25cf533「自适应悬浮导航」演示一致）：静止/回顶=上下堆叠（迷你条胶囊在上、全宽页签栏在下）；滚入正文=**两行并一行**——页签栏折叠成当前项小钮、迷你条展开占满余下行宽，形变过程系统原生动画。**方案沿革三轮**（0233a40 → 9a6aecc → aaa805e+本提交，其中 9a6aecc 自绘版已整体 revert）：

- **一版（applyHide/ShowAnimation，弃用）**：误把官方示例「沉浸光感」场景（`ImmersiveLightView`）的整组淡出 API 当成目标效果入口。真机实测（2026-10-01 用户反馈视频）：SCROLL_ANIMATION 为**原地半透明淡出**（栏组变幽灵叠在内容上，非形变收起），且滚动方向反复时实心/半透明**闪切**。教训：`applyHide/ShowAnimation` 管「整组显隐」，与「自适应悬浮导航」场景的 miniBar 形变是两套 API，不可混用。
- **二版（自绘两态栏组，9a6aecc，已 revert）**：为绕开黑盒自绘两枚胶囊 + barHeight(0) 隐藏自带栏。功能可达但弃用：官方原生形变（材质/光晕/联动动画）质量更高，且用户指认官方演示即目标效果——应走官方机制。
- **终版（官方 miniBar COLLAPSE↔EXPAND + 滚动驱动）**：SDK 语义（`@hms.hds.hdsBaseComponent.d.ets`）——`BarStyleChangeCallback` 同时回调 miniBarStyle 与 tabBarStyle；`HdsTabsBarChangeMode` 分 `USER_CLICK`（点击折叠态迷你栏/页签栏，系统内置切换）与 `APP_TRIGGER`（应用调 `applyMiniBarStyle`）；README 明言「miniBar展开的同时和tabsBar会折叠起来」——**迷你条展开 ↔ 页签栏折叠是 HdsTabs 原生联动形变**。官方示例靠点击触发，本工程按参考视频改为滚动位置驱动：
  - `handleTabBarScroll`：向下滚且滚过 `MINI_EXPAND_ON_OFFSET_VP(96)` → `applyMiniBarStyle(EXPAND)`；滚回 `MINI_COLLAPSE_ON_OFFSET_VP(48)` 以内 → `COLLAPSE`。双阈值滞回防抖（48~96 区间保持现态，杜绝一版的方向闪切）；无歌不展开（空玻璃壳）；触底报 -1 无操作（展开态在底部保持，同参考视频）。
  - `onBarStyleChange` 为形态事实源（`miniExpanded` 字段 + `AppStorage 'ui.miniBarExpanded'` 发布）：覆盖 USER_CLICK 与 APP_TRIGGER 两条变更路径；槽内 `SlotMiniBar` 经订阅切换紧凑(40vp)/非紧凑(62vp) MiniPlayer 内容（槽位闭包不响应壳层状态的老坑，仍走 AppStorage 订阅）。`miniBarStyle: COLLAPSE` 显式声明初值。
  - 衔接：切 Tab 目标页在顶部则收回展开态；切歌清空收回（`collapseMiniBarIfSongEmpty`）；一镜到底展开起点 `pillRect()` 增展开态分支（底部整行近似值：行高 56/钮宽 64，飞行起点偏差不敏感，真机可按 §7.16 同法精标）；四 Tab 页 `onBarScroll` 上报接线同一版保留。
- 验证（服务器）：assembleHap **BUILD SUCCESSFUL 0 error**；codelinter 改动文件 **0 error**。**设备侧未验证**（核心风险点）：VERTICAL 布局下 EXPAND 的真实形态是否为「两行并一行+页签小钮」（当前假设来自 README+视频对照）；展开态槽位药丸实际高度与非紧凑 MiniPlayer(62vp) 的匹配；USER_CLICK 系统点击切换与迷你条内容自身点击（开播放页/播放键）是否会同时触发；96/48vp 阈值手感。若真机 EXPAND 形态与预期不符，备选：HORIZONTAL 布局（静止态变单行小圆钮，形变同款）或恢复二版自绘。
- **修订一（2026-10-02 真机首测反馈视频，形变已验证 + 材质缺陷修复）**：真机确认 VERTICAL+EXPAND 形态正确——两行并一行、页签栏折叠为当前项小钮（其玻璃材质正常）、回顶恢复堆叠，核心假设全部成立。缺陷：**展开行迷你条呈深色平板、无沉浸光感**——`MiniPlayer.followsBarMaterial()`（背景透明透出栏身系统材质的档位）原带 `this.compact` 条件，展开态渲染的非紧凑形态走了自绘玻璃分支（surfaceGlass+卡片边距+阴影），整层盖住槽位壳的沉浸材质。修复（`view/components/MiniPlayer.ets`）：`followsBarMaterial()` 去掉 compact 条件（槽位形态两种紧凑度统一跟随栏材质），且跟随栏材质时零边距、无卡片阴影（几何由栏壳给定）。改动面安全：非 embedded 非紧凑形态全工程仅槽位展开态一处使用（dock 层两副本均 embedded）。不支持材质的设备（模拟器）回落行为不变。
- **修订二（2026-10-02 二轮真机反馈截图，光感已生效后的内容形态调整）**：展开行迷你条内容弃用上版的非紧凑形态切换，**两种形态统一紧凑样式**（用户决策：圆形封面 + 播放键外圈进度环，与堆叠态药丸同观感）——非紧凑内容的三处观感问题：62vp 内容在展开行壳内上下不居中、封面变圆角方形、播放键无进度环。`SlotMiniBar` 改为 Stack 垂直居中包裹（展开行壳高于 40vp 内容时居中，堆叠态同高无感）；`'ui.miniBarExpanded'` AppStorage 广播链删除（形态只在 MainShell 逻辑内消费：pillRect 展开态分支/切 Tab 收回判定）。
- **修订三（2026-10-02 三轮真机反馈截图 + 参考图，折叠行内容定版为 row 档）**：紧凑样式在折叠行的高药丸里暴露三问题——32vp 封面相对药丸弧度过小、标题过早截断、作者行贴底被裁。弃「统一紧凑」，MiniPlayer 新增第三形态 `row`（槽位折叠行专用，参考用户图二布局）：48vp 圆形封面（直径≈药丸高 85%）、标题/作者两行垂直居中、播放键保留外圈进度环（34vp 环 + 主色图标）、下一首 40vp，无线性进度条；内容行 48vp 由 SlotMiniBar 的 Stack 垂直居中包裹适配壳高。`'ui.miniBarExpanded'` 广播链恢复（SlotMiniBar 按形态切 compact↔row）。堆叠态药丸仍为紧凑档、dock 态仍为 embedded 档，均不变。
- **修订四（2026-10-02 四轮真机反馈截图，row 档两处精修）**：(1) **作者行消失**——当时归因为 `displayArtist` 空值塌陷，加了平台名回退；**该归因次轮被用户推翻**（见修订五），回退已撤。(2) **封面与药丸左端同心**——用户要求「封面左半边每一点与迷你条边缘距离一致」即封面圆心落在药丸左端半圆圆心；实现：SlotMiniBar 经 onAreaChange 实测槽位壳高下发给 MiniPlayer（新 prop `rowShellHeight`），row 形态封面左缩进 = (壳高−48)/2（未测量时按 56vp 标准壳取 4vp），不再用固定 padding。
- **修订五（2026-10-02 五轮用户指正，作者行越界的真实原因与修复）**：作者行并非数据缺失（撤回平台名回退），而是**固定 48vp 内容 + 外层 Stack 居中的两段式**在壳高与内容高不一致时把文字块排偏——作者行落到药丸可视范围之外。修复：row 形态内容行高度改为**填满实测壳高**（`rowContentHeight()` = rowShellHeight，未测量按 56），文字块（歌名+作者名）经 Row 默认垂直居中在壳内——歌名与作者名之间的中线与药丸中线齐平（用户要求）；封面同心缩进与 Stack 兜底包裹不变。
- **修订六（2026-10-02 六轮用户质疑「还是这样」——修订四/五的实测链路是循环测量，两轮修复均无效）**：用户截图佐证：封面与药丸左端间距≈0 → 修订四的同心缩进 (实测-48)/2 算出 0 → **实测值=内容自身高度 48**——槽位不约束 builder 高度，包装层 `height('100%')` 回落为包内容，onAreaChange 量到的永远是内容自己而非药丸。教训：**HdsTabs miniBar 槽位的 builder 高度由内容自然撑起（官方示例 miniBarBuilder 即不设高度、按 56vp 封面规格自然成形），任何「实测壳高」的尝试在该槽位内都是循环的**。修复：弃 rowShellHeight 链路，row 形态内容行**定高 56**（HDS 悬浮栏标准，官方示例规格）居中排版（文字块中线=行中线；封面同心缩进固定 (56-48)/2=4）；SlotMiniBar 保留 onAreaChange 仅作**临时调试读数**（row 形态药丸右下角 8fp 红字 `H=xx`），真机截图定版药丸真实几何后删除。
- **修订七（2026-10-02 七轮调试读数截图，几何模型定案：展开态内容区≈40vp、顶部对齐、底部裁切）**：调试读数显示 **H=0**——builder 盒是**零高度**（`height('100%')` 在无约束父级下解析为 0，此前所有「包内容」推断亦不成立），children 从零高锚点渲染。同张截图三处独立证据：文字块贴顶+下方大片留白、作者行完全消失、进度环只剩残弧——结合修订二~六全部现象，唯一自洽模型：**展开态药丸的 builder 内容区约 40vp 高（与堆叠态药丸同族同高），内容顶部对齐，超出 ~40vp 的部分被药丸底部裁切**。修订五/六的 48/56vp 内容的下半部（作者行、进度环下弧、封面下缘）均被此线吃掉；修订二的紧凑 40 内容因恰好贴合从未被裁（其「作者行贴底被裁」实为 40 行内文字块自身偏高）。修复：row 形态内容行回落**定高 40**（封面 34 同心圆（(40-34)/2=3 缩进）、两行文字 14/11fp 行内居中、进度环 30、播放键图标 16），标题弃渐隐蒙版改普通省略号（窄药丸里渐隐进一步压缩可读段）。**临时调试**：内容行加 1px 半透明红边框（可视化内容盒与裁切线关系），连同 H= 读数在真机确认后一并删除。
- **修订八（2026-10-02 八轮真机红框验证截图，模型证实、调试件移除、折叠行内容定稿）**：红框调试截图确认 40vp 模型——**红框完整落于药丸内**（顶边与药丸上缘重合、底边略高于药丸下缘），两行文字（标题+作者）、完整进度环、同心封面全部恢复显示。据此定稿：删除临时红框与 H= 读数（连同 SlotMiniBar 的 onAreaChange/shellHeight 链路）。已知边界：内容区顶部对齐使文字块相对药丸玻璃整体略偏上约 2-4vp——底部裁切线约束下不可再下移（下移即重新触发作者行裁切），为系统槽位约束内的最优解；若后续版本 HdsTabs 调整槽位几何，按修订七红框法重测。
- **修订九（2026-10-02 九轮用户定稿意见：大圆封面恢复 + 折叠行标题跑马灯）**：(1) **封面恢复 48vp 大圆**（用户指定回退 2d0cb29 观感）：顶边贴药丸上缘、底缘没入药丸下弧被自然裁切（该裁切即修订七定案的底部裁切线，用户认可此观感）；占位图标边距回 48 档。(2) **折叠行标题接跑马灯**：`MarqueeText` 组件自 `feature/marquee-song-title` 移植（该分支未合入 dev；Text 原生 MARQUEE + marqueeOptions，开头停留 2s（首轮/切歌自管）+ 轮间 delay 2000、切歌从头重滚、未超宽静止、fadeout 渐隐）——折叠行文字区最窄，省略号/渐隐均浪费可读段；堆叠态标题维持渐隐蒙版不动（跑马灯化属 marquee 分支既有工作，避免双分支改同一处）。后续两分支合入 dev 时 MarqueeText.ets 内容一致、冲突取任一侧即可。
- **修订十（2026-10-02 十轮用户反馈「封面歪了」——改用程序化像素测量定同心参数）**：视觉模型对亚像素几何描述反复自相矛盾，弃用；改 ffmpeg 解码截图 + Python 亮度/饱和度分类逐像素测量（可复现脚本见本次会话记录）。测量结果（1316×2832 截图）：展开药丸左缘 x308、上 y432、下 y623（高 191px≈55-56vp，与页签钮 195px 互证，HDS 56vp 标准在展开态成立）；封面圆赤道直径 168px≈48vp 渲染正确、左缘与药丸左缘重合（inset 0 生效）；**同心目标（左端半圆圆心 403.5,527.5）与封面实际圆心 (392,531) 偏差：横向 11.5px≈3.3vp、纵向 3.5px≈1vp**——左缘 0 间隙 vs 上缘 15px 间隙的不对称即用户所见「歪」。修复：`rowCoverInset` 定值 3.5vp、封面纵向 offset 4→3。修订九的封面定位描述（顶边贴上缘/inset 收敛 0）随本修订修正。
- **修订十一（2026-10-03 十一轮用户反馈「仍然偏下」——二轮像素复测，横向已准、纵向修正）**：新截图（浅色背景，玻璃不可见，改以页签钮图标中心 529.5 定药丸中线）复测：封面圆赤道左 320.5/右 487 → 圆心 x=403.5 与帽心（308+95.5）**精确重合**（修订十的 inset 3.5 定准，横向结案）；圆顶 455、圆心 y≈538.5（底 622 为药丸底裁切线），较药丸中线 529.5 **偏低 9px≈2.6vp**。修正修订十的一处推断误差：上轮「圆心 531」来自赤道行=圆心的假设（赤道 ±6px 内弦长差异不可辨），非直接测量；本轮以圆顶直接测量为准。修复：纵向 offset 3 → 0.5（上移 2.5vp，残差≈0.3px）。
- **修订十二（2026-10-03 十二轮用户反馈「仍有较小的向下偏移」——三轮像素复测，改以玻璃边线直测药丸中线）**：新旧两截图对比确认 offset 0.5 已生效（封面上移整 10px，与 -2.5vp 改动量吻合），残余偏差源于**中线估计量本身**：本轮发现浅色背景下药丸玻璃上/下边各有一条纯白高光线（255.0，水平范围 x≈376–1164），即药丸真实边界——顶边线 y=430.5、底边线 y=624.5 → 高 194px≈56vp、**真中线 y=527.5**；修订十一所用页签钮图标中心 529.5 系估计量偏高 2px。封面圆按亮度剖面直测（圆心 x 处暗区 y[446,614]，直径 168px 精确）：圆心 y=530.0，仍偏低 **2.5px≈0.7vp**。横向复测无退化（圆心 x=403.5，药丸左缘高光起于 x≈305，同心差 ≤0.4vp，维持 inset 3.5）。修复：纵向 offset 0.5 → **-0.2**（上移 0.7vp，残差 ≈0.2px）。本条同时修正：饱和度聚类抓不到真圆边（灰色封面艺术上半部低饱和，d_y=92≠168），圆缘必须按亮度剖面测。
- **修订十三（2026-10-03 十三轮用户反馈「上滑不展开，须回顶再上滑才恢复」——折叠态恢复由位置驱动改方向驱动）**：原恢复条件仅看位置（滚回 `MINI_COLLAPSE_ON_OFFSET_VP`=48vp 内），列表中部上滑（负增量）无分支命中，只有滚到顶部附近才恢复双行。修复：恢复条件改 `yDelta < 0 || yOffset < 48`——**任意上滚增量即恢复，与下滚收起方向对称**（用户指定参照下滑收起逻辑）；48vp 位置条件保留为兜底（内容缩短等无声增量场景）。连带清理：四 Tab 页「触底兜底报 -1」（HomePage/LibraryPage/SettingsPage 的 `onScrollEdge(Edge.Bottom)`、ExplorePage 的 `onReachEnd`）随之移除——方向驱动后该 -1 会伪造成一次上滑，导致触底瞬间错误展开；触底保持折叠态不变（同参考视频），上滑离开底部时自然有真实负增量触发恢复。防抖说明：展开/折叠各由 `miniExpanded` 状态闩锁，同方向连续帧不重复触发，方向交替才切换（与官方 ImmersiveLightView 示例 `isScrollUp` 闩锁同构）。

### 7.21 2026-10-04 网易云手机验证码登录「网络环境异常」复发修复：匿名设备凭证 MUSIC_A（服务器 Linux CLT 26.0.0.105，无设备，分支 `fix/netease-captcha-music-a`）

§7 记录外的前情：2026-09-27（commit 8931990）曾修过一次同报错（补 web 会话指纹 cookie + 首页预热取 `__csrf`/NMTID），2026-10-04 用户反馈**复发**。本轮为第二次风控对抗，结论：上轮的指纹方案已不够——登录族接口现在还要求**匿名设备凭证 `MUSIC_A`**。

- **社区证据链（2026-09～10，均为一手 issue/PR/源码直读）**：① QueMusic PR #79（2026-10-01 合入，同款 -460 回归的真机修复）：启动时调 `register_anonimous` 换 `MUSIC_A` 并注入后续所有请求 cookie，缺它则登录族接口必被风控拦截；附带 A/B 实证「UA 平台与 cookie `os` 矛盾即可独立触发 -460」（本工程上轮已自洽：桌面 UA + os=pc）。② api-enhanced（Binaryify 继任仓库，v4.41.0/2026-10-03）`util/request.js`：`processCookieObject` 对无 `MUSIC_U` 的每个 weapi/eapi 请求注入 `MUSIC_A=anonymous_token`（启动经 register_anonimous 落盘复用）。③ open-orpheus #17/#75（2026-04/05）：匿名态接口 2026 年起收紧，`MUSIC_A` 成为登录类接口隐式必填——「9 月能过、10 月不过」与凭证回收时间线吻合。④ api-enhanced PR #243（2026-08-24）：预置合成 NMTID 会阻止服务端下发真值（服务器只在请求不带 NMTID 时经 Set-Cookie 下发）。
- **register_anonimous 协议（QCloudMusicApi 源码直读，QueMusic 真机验证通过的 weapi 通道）**：`POST /weapi/register/anonimous`，payload `{username}`，`username = base64("<deviceId> <dllEncodeId(deviceId)>")`，`dllEncodeId = base64(MD5(deviceId 逐字符 XOR '3go8&$8*3*3h0k(2)2'))`；deviceId 为进程级随机 52 位大写 hex（api-enhanced `generateDeviceId` 同款）。响应 body 带 `token`，Set-Cookie 下发 `MUSIC_A`（本工程 `HttpClient` 的双来源 cookie 捕获自动入 jar，body token 仅作净栈丢头时的兜底，与 QueMusic 同款双源提取）。api-enhanced 现版该接口已迁自研 `xeapi` 通道（依赖服务端下发会话密钥），社区鸿蒙/桌面端实现的 weapi 通道仍有效。
- **本轮改动（`network/NeteasePhoneLogin.ets` 为主）**：① `ensureWebSession` 末尾新增 `ensureAnonymousDevice()`：进程内至多注册一次（失败降级为上轮的纯指纹会话、不阻断登录流程；重复注册本身会累积风控分），jar 已有 `MUSIC_A`/`MUSIC_U` 时跳过；注册成功后 `MUSIC_A` 经共享 jar 自动随发码/登录请求携带（扫码登录同 jar 亦受益）。② 发码 payload 补 `secrete: 'music_middleuser_pclogin'`（api-enhanced 2026-07 起的现行字段，缺省兼容但补齐为持平）。③ `fallbackNmtid` 形状修正：`00O`+19hex（22 位、与服务端下发 42 位形态不符）→ 32 位小写 hex（社区客户端自生成 NMTID 的真实形状），且仅在首页预热未取到时兜底（#243 教训：预置合成值阻止服务端下发真值）。④ 指纹 `appver` 8.10.35（2021 年代 web 播放器）→ **3.1.17.204416**（api-enhanced 现版 osMap pc 生产值），三处统一防共享 jar 内 appver 漂移：`buildWebSessionSeed`、`NeteaseApi.doEnsureSession` 种子、`NETEASE_FALLBACK_APPVER`（NeteaseAuth 粘贴 cookie 兜底）。⑤ `NeteaseCrypto.bytesToBase64` 转 public（username 构造需要），`NeteaseLoginResult` 增 `token` 字段。
- **单测**（`NeteasePhoneLoginSeed.test.ets` 重写为 5 例 + `NeteaseAuth.test.ets` 2 处断言随 appver 更新）：dllEncodeId 双已知答案向量（Node crypto 算得：`testdev`→`aUNnZQ4t4g9xOuS/lFXa7Q==`、52 位 deviceId→`AQnKVRmBziu7FJISAzbr6A==`）、`buildRegisterUsername` 完整向量、seed 指纹集、NMTID 新形状（32 hex + 随机性）。
- **未验证（本机无设备）**：真机发码/登录全链（用户验证路径：安装刷新后的签名 HAP）；若仍被拦，社区证据指向的下一嫌疑为出口 IP（机房/海外/VPN 触发 -462 人机验证，`realIP` 对此已证实无效）与账号级风控标记（换浏览器 cookie 或 frontrisk 验证兜底），届时按 go-musicfox #596 判例处理。扫码登录（NeteaseQrLogin）未主动接 `ensureAnonymousDevice`，仅经共享 jar 间接受益。
- **修订一（2026-10-04 真机反馈「当前环境存在安全风险」——判定为 10003/10004，补齐 QueMusic 配方剩余项）**：上版装上后报错从 -460「网络环境异常」变为 10003/10004「当前(登录)环境存在安全风险，请稍后再试」——**正是 QueMusic PR #79 修复前的中间态**（该 PR 自述：修复前 -460 → 10003/10004，修复后登录成功），说明方向对但配方缺件。与 QueMusic 终态配方的逐项 diff：①其 deviceId 持久化（`Account.ini: Netease/deviceId`，源码注释明言「每次启动随机换设备是扫码被判环境异常的主要嫌疑之一」）——本工程上版恰是每进程随机（本轮已改：`np.netease_device_identity` 落盘复用 nuid/wnmcid/tsMs/deviceId 四元组，`MUSIC_A` 亦经 `np.netease_anon_music_a` 落盘、重启后注入 jar 免重复注册）；②登录 payload 现版必带 `secureCaptcha: ''`（api-enhanced 2026-10-03 main，已补）；③验证码登录先过 `/captcha/verify` 再发 login（folia-major：「新版验证码登录必须先 verify，直接登录易触发风控」；第 1 轮删 verify 的教训保留——失败仅告警不阻断，已按软前置加回）。诊断增强：发码/登录 Toast 与日志均带数字 code（`登录失败[10004]: …`）、`postWeapi` 每请求 debug 行、匿名注册成败均落日志——用户下次反馈可直接定位环节与判决。另注：服务器侧（美西机房 IP）实测 weapi/eapi 经典匿名注册通道均不可用（weapi 恒 `{"code":400}`、eapi 空 body 200），与 QCloudMusicApi/QueMusic 国内真机可用矛盾，判定为地域/出口差异；api-enhanced 主线 2026-10-03 已迁 xeapi 注册（X25519+AES-GCM+`/api/bsr/sk/get` 公钥协商，纯 ArkTS 移植代价大），留作国内真机 weapi 注册仍失败时的下一梯队方案；eapi 版 `middle/captcha/sent/v1`（scene:'0'，interfacepc）为另一候选。本轮在并行会话占用主检出的情况下经 sparse worktree（`np-netease-fix`）完成。
- **修订二（2026-10-04 修订一后真机仍报 10004——落地社区终态方案：内嵌网页登录；xeapi 原型证据与暂缓决策）**：用户质疑「社区已有成熟方案为何不用」，本轮直接回答并落地。①**xeapi 原型（api-enhanced 现行注册通道）服务器实测**：握手引导 `POST interface.music.163.com/api/bsr/sk/get`（明文表单 + HMAC-SHA256(timestamp+nonce) 签名 + AES-ECB(staticKey `ab1d5a43…1b84`) 解 `encryptedData` 得 X25519 公钥/sk/version）从美西出口**完全可用**（200、签名校验通过、32 字节公钥解出）；但 `xeapi/register/anonimous`（C/S/R 信封：`C=b64url(ECB(dk, midTransform(ECB(staticKey, JSON))))`，midTransform=random16‖rot(xor(ct,random))；`S=eph‖iv‖AES-128-GCM(HKDF 单块推导密钥)(b64(dk)|os|sk)‖tag`；`R=b64(ECB(staticKey, version|))`；响应经 ECB(`e82ckenh8dichen8`) 解密 + gunzip）与 weapi/eapi 通道**一样恒返 `{"code":400}`**（8 组身份/域名/Cookie 变体全灭，信封被服务端正确解密回包、排除加密错误）——**注册端点对非中国大陆出口一刀切**。结论：从本服务器无法验证 xeapi 移植正确性，盲移约 600 行纯 TS 密码学（X25519/GCM/SHA-256/HMAC 族）让用户试错不负责任；**移植暂缓，判定依据 = 真机日志的注册成败行**（修订一已埋）。②**落地社区终态方案：网易云网页登录页**（go-musicfox 在协议方案 PR #617 被关后合入的终态即 WebView 登录；本工程 Bilibili 同款架构现成）：新增 `data/auth/NeteaseWebLogin.ets`（纯逻辑：`music.163.com/#/login`、`*.music.163.com` 主框架导航 https 白名单按 label 边界匹配（`notmusic.163.com`/`music.163.com.evil.x` 拒）、非空 `MUSIC_U` 完成判定；复用 BiliWebLogin 的 mergeCookieHeaderTexts——空值丢弃防过期覆写误判）+ `view/pages/NeteaseWebLoginPage.ets`（ArkWeb 镜像 BiliWebLoginPage：进入清 Cookie 池防残留误判、1.5s 轮询 + onPageEnd 双路径收割、命中即 `saveFromWebLogin` 走既有校验链落库、日志只记键名）+ `NeteaseCookieRepository.saveFromWebLogin` + 路由 `NETEASE_WEB_LOGIN`（MainShell 接线）+ 设置页网易云账号区入口（未登录时显示，置于手机号登录上方，副题「验证码登录被风控时最稳」）；单测 3 例（完成判定/白名单边界/空值合并不覆盖登录键）。风控语义：登录在真实浏览器上下文完成（滑块/短信/扫码官方页自理），凭据收割后与扫码/手机号登录同链落库，整条 10003/10004 协议对抗被绕开。**未验证**：真机 ArkWeb 全链（官方登录页在 ArkWeb 的渲染/交互兼容性、`fetchCookieSync` 对 MUSIC_U 的可见性——系统 Cookie 存储不受 httpOnly 限制，且 MUSIC_U 本就可通过 JS 读取，风险低）。
- **修订三（2026-10-04 真机反馈：网易云/B 站网页登录两页均白屏——加载模式改官方直连 src + 排障回调补齐）**：用户真机反馈两页打开后内容区纯白（标题栏正常、无报错、刷新无效），诊断报告因 Logger 环形缓冲被 SchemaStore 告警刷屏而无 web 登录日志（刷屏本身是另一独立问题，另案处理）。排查（官方本地文档库逐条核对 + SDK 26.0.0.105 d.ts 直读）定位两处与官方记载冲突的实现：①**加载模式**：`about:blank` 起步 + `onControllerAttached` 里 `loadUrl` 的两步模式存在导航竞态——官方生命周期序为 `onControllerAttached` 先于首次导航的 `onLoadIntercept`，attached 回调里 `loadUrl` 时初始 about:blank 尚挂在加载半路（网易云侧该次初始导航还会被白名单拦掉，`isAllowedNeteaseLoginNavigation` 原不放行 about:blank）；且官方文档（faqs-arkweb-129/164、《使用Web组件加载页面》）对已知 URL 的标准写法一律是直接 `Web({ src: url })`，无任何 about:blank 起步先例。②**缓存模式**：官方《定位与解决Web白屏问题》明确记载 `CacheMode.Default` 的协商缓存（If-None-Match）收到 412 不降级重试、直接判定主资源失败白屏，症状即「系统浏览器正常、App 内白屏」。**修复（两页镜像）**：改 `Web({ src: 登录页URL })` 直连加载；补 `.cacheMode(CacheMode.Online)`；网易云白名单放行 about:blank（对齐 B 站侧）；排障回调补齐官方白屏排查清单——`onControllerAttached`/`onPageBegin`/`onPageEnd`/`onErrorReceive`（补数字错误码+主/子资源+脱敏 URL）/`onHttpErrorReceive`（主框架响应码）/`onRenderExited`（渲染进程退出原因标签）/`onConsole`（页面 JS console 转发进应用日志，每次加载限 10 条防刷屏，超限不消费走系统默认）；新增 `sanitizeUrlForLog`（BiliWebLogin 纯逻辑，丢 query/fragment 防跳转链接凭据明文入日志，两页日志共用）。单测 +3：白名单 about:blank、sanitize 丢 query/fragment（网易云 `#/login` → host+path）。**未验证**：真机复测（用户验证路径：安装刷新后的签名 HAP；若仍白屏，新日志会给出 attached/pageBegin/错误码/渲染退出现场，按官方 web-white-screen 关键字 `StartRenderProcess failed`/`crashpad`/`final url` hilog 过滤可继续定位）。
- **修订四（2026-10-05 真机确认网页登录可用，登录入口收口）**：修订三签名包真机验证通过——网易云网页登录成功落库（用户：「成功登录后网易云的网页登录选项删去了，这很好」），白屏根因判定正确。同轮用户提出入口收口两条要求并落地：①**统一「对应渠道已登录即隐藏」**：网易云/B 站「粘贴 Cookie 导入」与 B 站「网页登录」入口补未登录条件（`@StorageLink('np.netease_logged')`/`('np.bilibili_logged')` 响应式驱动，与既有网页登录行为一致）；②**删去网易云手机号/密码登录入口**：账号区只保留扫码（账号行 + QrLoginPanel）、网页登录、粘贴 Cookie 三通道（Cookie 副题改「网页/扫码均不可用时的备用登录方式」，顺序调整为网页在前）。连带清理：`NeteasePhoneLoginPanel.ets` 组件（207 行，删后无引用）与 `NeteaseCookieRepository.saveFromPhoneLogin` 包装方法移除；**网络层 `network/NeteasePhoneLogin.ets` 保留**——`ensureWebSession`/指纹/匿名凭证是全部网易云通道共用的会话基础设施，验证码协议能力按 §7.21 修订一/二记录为暂缓而非删除，若日后恢复入口可复用。FEATURE_MATRIX 网易云/Bilibili 两行同步。**未验证**：真机 UI 显隐（本机无设备；显隐由 AppStorage 布尔驱动，与已验证的网页登录行同机制，风险低）。

### 7.22 2026-10-05 资料库改版：平台横向标签页——本地/网易云/B站三窗格，对齐安卓版媒体库（服务器 Linux CLT 26.0.0.105，无设备，分支 `feature/library-platform-tabs`）

用户以安卓版媒体库截图（顶部「本地/收藏/网易云-歌单/…」横向平台标签，每个平台页显示该平台歌单）为参照，要求鸿蒙版资料库同构。原 LibraryPage 为单页纵向长列表（统计卡 + 本地歌单/网易云歌单/B站收藏夹/本地音频/平台登录区依次平铺）。

- **页内结构（`view/pages/LibraryPage.ets` 全量重写）**：标准 `Tabs`（`BarPosition.Start` + `BarMode.Scrollable` + 自定义 tabBar @Builder，官方「选项卡」指南的标准写法；文档核实：`.tabBar(this.builder(…))` 官方示例模式、`currentIndex` 状态变化触发 tabBar 更新；BarMode.Scrollable 与自定义 tabBar 兼容见 faqs-arkui-580）。嵌套于外壳 HdsTabs 的 TabContent 内属官方「双层 Tabs」场景（faqs-arkui-19）：外层本就 `scrollable(false)`，内层同样 `scrollable(false)` 不开横滑（与外壳同策略，避免与列表横滑争手势）。TabContent 默认 clip(true)（官方 API 文档），窗格内容不会溢入标签行。选中高亮经 `onAnimationStart` 即时更新 + `onChange` 兜底（faqs-arkui-568：onChange 晚于切页动画）。标签行底部 hairline 分隔线用 Tabs `.divider`。
- **平台与内容映射**：标签 = 本地 / 网易云 / B站（本工程实际具备的三平台，标签常驻不随登录态增减）。安卓版的「收藏」标签是跨平台收藏聚合，鸿蒙版无此功能（不造空壳入口），不移植；本地收藏伪歌单对齐安卓 LOCAL 页「我喜欢的音乐」做法放本地页首行。本地窗格：「+ 新建歌单」整行入口、我的收藏行（顺带修复收藏伪歌单混在用户歌单列表里显示英文名「Favorites」的旧问题——现在过滤 `FAVORITES_ID` 单独成行）、用户歌单、本地音频组（目录/扫描/播放入口原样迁入）、「更多」组（已下载/播放历史/播放统计/一起听，接替被删的统计卡与平台区行；历史/一起听在设置页本就有入口）。网易云/B站窗格：未登录显示空态 + 「去登录」按钮（接替原「平台」分区登录行，设置页账号区入口不变），已登录为计数 + 刷新 + 错误重试/空态/列表（列表标记原样保留）。统计卡整组删除（信息并入行副标题）。
- **壳层滚动器换绑（`view/pages/MainShell.ets`）**：标题栏渐变模糊（`bindToScrollable`）与迷你条滚动阈值（`handleTabBarScroll`/`selectTab`）原按「每个底部 Tab 一个 Scroller」绑定；资料库现有三个窗格滚动容器，LibraryPage 经新增 `onPaneScroller` 回调上报激活窗格 Scroller，MainShell 侧 `shellScroller()` 统一三处读取。约束：状态装饰器不接受 Scroller（编译器报 `cannot be a 'Scroller' object`），实例放普通成员 + `libraryPaneTick` 计数 @State 在 `shellScroller()` 内被 build 路径读取注册依赖，上报即计数变化触发重渲染换绑——与 resolveDark/schemeBg 读被跟踪成员注册依赖同一手法。
- **验证**：`assembleHap` BUILD SUCCESSFUL；codelinter 改动两文件 0 问题；纯 UI 重构无新纯逻辑，未加单测。**未验证（本机无设备）**：真机三窗格切换/标签下划线观感、标题栏模糊随平台切换换绑的生效性、迷你条展开折叠阈值在窗格滚动上的手感、lg 断点（≥840vp 侧栏形态）下页内标签布局、文本缩放与横竖屏走查。安卓版「网易云-歌单/网易云-歌曲」二级标签拆分（对应安卓内部态）本版未做，网易云窗格暂为歌单单列表，专辑页已有独立路由入口。

### 7.23 2026-10-13 真机反馈五问题修复：卡片控制/网易翻页/本地音乐歌单/歌单搜索卡顿/短链（服务器 Linux CLT 26.0.0.105，无设备，分支 `fix/upstream-sync-p0-p1`）

用户基于本分支签名包的真机反馈，五个问题全部定位到确切根因并修复：

- **桌面卡片按钮无响应（F-12 缺陷）**：`PlaybackCard.ets` 的 `postCardAction` call 事件把 `method: 'playbackCardControl'` 误放 action 对象顶层——官方 `js-apis-postCardAction` 约定顶层仅 action/bundleName/moduleName/abilityName/uri/params 六字段，`call` 的 `method` 必须放 `params` 内；顶层多余字段被系统静默丢弃、事件根本到不了 `callee.on`，表现为按钮全无响应而主体 router 点击（只依赖 abilityName/params）正常。已把 method 移入 params（接收侧 `readString()` 解析 `action` 字段不受影响）。
- **网易云搜索滚到底无法加载更多（F-9 缺陷）**：`ExplorePage.loadMore()` 网易分支漏推进 `this.searchPage`（B 站分支有），每次触底都重拉第 2 页（offset=30），去重合并后原地踏步、上限约 60 首。已补 `this.searchPage = nextPage`。
- **本地扫描后无本地音乐歌单（§8 缺口）**：扫描结果只落 `local_music_catalog`/内存缓存，歌单体系零接线。补系统歌单「本地音乐」：`LocalPlaylistRepository.LOCAL_MUSIC_ID`（`local_music`）+ `buildLocalMusicPlaylist()`（上游 LocalFilesPlaylist SYSTEM_ID=-1002 / SystemLocalPlaylists.normalize 注入式对应物——**不落歌单库**，由扫描缓存即时装配，本地文件条目不进跨端同步）；资料库本地窗格「我的收藏」下固定入口行（扫描缓存非空才显示）；PlaylistDetailPage 只读视图（优先 LocalDirectoryScanner.loadCached 持久缓存、回退 LocalMediaScanner 进程缓存），隐藏改名/删除/添加/单曲移除（F-10 撤销快照侧同步拒绝该 id）。`playLocalLibrary` 立即播放入口保留。
- **歌单内搜索非常卡顿（F-9 缺陷）**：每 keystroke 对全歌单逐首重建 14 字段候选（NFKD 归一+分词/驼峰/缩写+逐字拼音解析）再打分，全部压 UI 线程。新增 `PreparedSearchEntries<T>`（SearchTextMatcher.ets）：候选只依赖歌曲本身，随歌单整体重建一次、每次按键仅打分；PlaylistDetailPage 接索引 + 200ms 输入防抖（aboutToDisappear 清定时器）。语义与 `filterAndRank` 完全一致（等价性单测）。
- **B 站短链无法进 UP 空间/无自动展开（F-7 缺陷，三处叠加）**：① `HttpClient.expandRedirectUrl` 创建 `HttpInterceptorChain` 后**漏调 `chain.apply(request)`**（SDK d.ts：apply 才把链挂到请求实例），REDIRECTION 拦截器从未触发、hops 恒空、原样返回短链 → 恒走「短链解析失败」toast——这是带完整 https:// 链接也失败的根因；② 识别器 `extractExploreHttpUrl` 只认带 scheme 链接，裸域名粘贴（`b23.tv/xxx`）落入关键词搜索分支——补已知平台主机（b23.tv/163cn.tv/bilibili.com/space.bilibili.com/music.163.com/y.music.163.com/youtu.be/youtube.com）行首正则回退，命中补 `https://`；③ 展开只在提交搜索时触发——TextInput 补 `onPaste`：整段粘贴内容（无空白）本身是可识别链接时自动 `openLink` 跳转（长文本内嵌链接不自动跳，仍走提交抽取）。


**修订（2026-10-13 二，真机反馈「本地歌单点歌错位 + 无法播放」）**：入口生效后暴露三处缺陷——① `playFromFiltered` 按 platform/audioId/id 三元组在原歌单定位点播歌曲，本地歌三者全同（LOCAL/''/0），点哪首都命中第 0 首——改 `stableKeyOf`（含 mediaUri，本地歌互不相同）定位；② `PlayerManager.play()` 只处理 PAUSED/COMPLETED，队列加载全失败停下（publishStatus ERROR）后播放键穿帮返回成死角——补 ERROR 分支重载当前曲；③ LOCAL 取流原为单路径 `openLocalFd(localFilePath || mediaUri)` 无兜底——改多候选（localFilePath、mediaUri 形态可能不同：目录扫描=沙箱路径、选择器导入=file:// URI）逐个尝试，全失败时 `LocalDirectoryScanner.ensureReadPermission`（新增可等待变体，activatePersistedPermission 改为其包装）激活扫描目录持久授权后重试一轮（系统回收权限场景）。LocalMusicPlaylist 测试补稳定键互异断言。真机待复验。

**验证**：`assembleHap` BUILD SUCCESSFUL；`hvigorw test` Unit 编译 0 error（Linux 执行阶段挂死如常，通过计数待 Windows 工作站，新增用例：ExploreLinkRecognizer 裸域名 1 组、SearchTextMatcher 预计算索引等价 1 组、LocalMusicPlaylist 2 例）；codelinter 改动文件 0 error（ExplorePage 1 条存量 reusable-component warn）。**未验证（本机无设备）**：卡片按钮真机复验、短链真机展开（REDIRECTION 拦截器 API 22+ 首次真机实证）、网易翻页连续加载、本地音乐歌单入口与播放、搜索手感——均待下一轮真机反馈。
