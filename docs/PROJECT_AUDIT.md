# 项目审计（2026-08-12）

## 审计范围与可信度

本审计基于当前工作区的源码、配置和历史构建产物。由于目录在审计前没有 `.git` 历史，且华为文档的版本化页面未能在当前环境中完成浏览器交互核对，结论分为三类：

- **已静态确认**：直接来自当前文件内容或计数。
- **有历史证据**：历史日志/产物能证明曾发生，但本次未能重现。
- **待复核**：必须在目标 SDK、模拟器或真机上重新验证。

## 快照清单

### Android 参照实现

- 路径：`NeriPlayer-master/`
- 技术栈：Kotlin 2.4、Jetpack Compose、Media3/ExoPlayer、OkHttp、DataStore、WorkManager、KSP，并含 C/C++ USB 音频实现。
- 主源码规模：`app/src/main` 下 634 个 Kotlin 文件，约 172,517 行。
- 测试规模：约 285 个 JVM 测试文件、25 个 Android 设备测试文件。
- 子模块：`.gitmodules` 声明歌词 UI/Core、MIUIX 和 Listen Together，但当前四个子模块目录为空。
- 上游地址：https://github.com/cwuom/NeriPlayer
- 上游基线已通过 GitHub Contents API 的 blob SHA 交叉比对确认：`d66d465f48a6ae911fef0de88d2d21937760f31d`（2026-07-31，`feat(settings): add searchable grouped settings`）。`README.md`、`AdvancedLyricsView.kt`、`AppFeedback.kt`、`gradle/libs.versions.toml` 等文件与该 commit 的 blob SHA 一致；这是文件快照基线，不代表目录包含该 commit 的 `.git` 元数据或子模块内容。
- 上游当前仍在活跃开发：默认分支 `master`；截至本审计，最新 commit 为 `bc4142bc9e9b0b88e27be8dbc19c85e548400709`（2026-08-12，`feat: implement playback progress prediction for WaveformSlider (#337)`）。后续同步必须以 commit 为单位，而不是直接覆盖目录。

### ArkTS 普通应用原型

- 路径：`NeriPlayer-HarmonyOS/`
- 工程模型：Stage 模型、单 `entry` HAP、ArkTS 严格模式、ArkUI。
- 当前配置：`compatibleSdkVersion` 与 `targetSdkVersion` 均为 `6.1.1(24)`。
- 设备类型：phone、tablet、2in1。
- 源码规模：56 个 `.ets/.ts` 文件，约 7,142 行。
- 主要 Kit：AbilityKit、ArkUI、MediaKit、AVSessionKit、NetworkKit、CoreFileKit、ArkData、PerformanceAnalysisKit。
- 自动化测试：未发现 ArkTS 单元测试或 `ohosTest` 测试源码。
- 已声明权限：Internet、网络状态、后台持续运行、本地音频读取。

### ASCF 元服务原型

- 路径：`NeriPlayer-ASCF/`
- 技术路线：ASCF 小应用页面（HXML/JS/CSS）嵌入 ArkTS 壳。
- 定位：验证元服务的网络播放和轻量 UI；不是普通应用主线。
- 已知限制：本地媒体、后台能力、播放速度、USB 等受到元服务形态约束。
- `entry/src/main/resources/rawfile` 是生成输出，已从根仓库排除；源文件位于 `ascf/ascf_src`。

## 已确认的架构差距

| 能力域 | Android 参照 | ArkTS 原型 | 结论 |
| --- | --- | --- | --- |
| UI/导航 | Compose 页面、组件、ViewModel 数量较多 | 17 个页面与少量共享组件 | 已有可演示骨架，尚非等价实现 |
| 播放核心 | Media3 服务、策略、预取、错误恢复、USB 路径 | AVPlayer 管理器、基础队列和会话 | 需以状态机和故障恢复为核心重构 |
| 在线来源 | 网易云、Bilibili、YouTube 多层解析/登录 | 三个平台的基础适配器 | 搜索/基础解析代码存在；登录、风控、YouTube 取流未闭环 |
| 下载 | 完整任务、目录、提交、恢复和迁移体系 | 任务模型/页面/简单仓库 | 传输、校验、恢复、存储事务未移植 |
| 数据与同步 | 设置、历史、统计、GitHub/WebDAV、多路合并 | preferences/JSON 型仓库 | 本地模型已有；同步与迁移策略缺失 |
| 一起听 | 独立协议、WebSocket、会话、校时 | 占位 | 未移植 |
| USB 独占 | 大量 C/C++ UAC1/UAC2 与测试 | 无 NAPI 模块 | 高风险独立里程碑 |
| 测试 | JVM、设备、C++ 测试均存在 | 未发现测试 | 是当前最大工程风险之一 |

## 构建与安全发现

### 有历史证据

- `.hvigor/outputs/build-logs/build.log` 记录了 2026-08-02 的 `BUILD SUCCESSFUL`。
- `entry/build/default/outputs/default` 留有已签名与未签名 HAP。

这些只证明当时特定环境曾构建成功，不等于当前可重现；生成目录和 HAP 均不进入 Git。

### 当前阻塞

- `local.properties` 与旧脚本指向 `E:/DevEco Studio/sdk/default`，当前环境无法访问该位置。
- 本机 PATH 中没有 `hvigor`、`ohpm`、`hdc`。
- 当前无法完成干净同步、编译、模拟器安装和真机权限验证。

### 已采取的仓库防护

- 根 `.gitignore` 排除签名目录、密钥/证书、SDK 本地配置、依赖、缓存、HAP 与构建输出。
- 本地签名脚本不再保存硬编码口令；改为环境变量或安全输入。
- ASCF 插件二进制与解包依赖不进入仓库，后续应记录可验证的下载来源和版本。

## 需要尽快补齐的基线信息

1. 初始化四个上游子模块，或明确本迁移不引用其代码、只依据公开接口重写。
2. 评估从已确认基线 `d66d465f...` 到当前上游 `bc4142bc...` 的增量变化，再决定冻结迁移基线还是先更新快照。
3. 在可用的 DevEco 环境执行一次删除缓存后的干净构建，并保存命令、SDK 版本和结果摘要。
4. 在 HarmonyOS 6.x 与 7.x 各选至少一个真实目标版本，建立编译与设备测试矩阵。
5. 为数据模型、LRC、稳定歌曲键、队列状态机和网络解析器优先建立 ArkTS 单元测试。

## 勘误与进展（2026-08-14 复核）

正文为 2026-08-12 审计时点的事实，以下为 2026-08-14 复核后的更新，冲突时以本节为准：

- **单元测试**：正文"未发现 ArkTS 单元测试"已过时。`entry/src/test/` 已建立（`@ohos/hypium` 1.0.28），覆盖 LRC 解析/翻译合并/时间格式化 3 用例，2026-08-13 实测 3/3 通过；`ohosTest` 仍未建立。
- **源码规模**：56 个 `.ets/.ts` 文件、约 7,698 行（2026-08-14 实测），正文 7,142 行为审计时点数字。
- **Android 快照行数口径**：`cat|wc` 直接统计 `app/src/main` Kotlin 约 185,771 行（含空行），与正文 172,517 行存在口径差异，下次审计应统一统计方式。
- **"当前阻塞"三条的后续**：2026-08-13 已完成干净构建、单元测试、调试签名、模拟器安装与 smoke test（记录见 `hm.md` §7.4）；2026-08-14 工具链迁至 `D:\HarmonyOS\Tools\` 后完成修复与全链复验——用户级 PATH 与 `DEVECO_SDK_HOME`/`HOS_SDK_HOME`/`DEVECO_STUDIO_HOME` 已修正，`local.properties` 指向 `D:/HarmonyOS/Tools/command-line-tools/sdk/default`，`build-profile.json5` 显式补齐 `compileSdkVersion`，新建 `entry/src/ohosTest/` 设备测试骨架（模拟器实测 1/1 通过），签名口令重置并存于用户级环境变量；完整验证记录见 `hm.md` §7.5。
- **版本映射**：官方文档已复核（见 `hm.md` §2）：HarmonyOS 6.0.0→API 20、6.1.0→23、6.1.1→24（最新稳定 Release，即本项目基线）、HarmonyOS 7.0→开发套件 26.0.0（API 26，Beta）。正文"6.0 与 7.0 的 API Level 必须复核"的待办已落定。
- **Git 状态**：工作区根目录已初始化 Git（基线提交 `ef89b16`，2026-08-12，remote 指向上游且禁推）。正文"目录在审计前没有 `.git` 历史"仅描述审计时点；三个子工程目录本身仍是无 `.git` 的文件快照。
- **文档一致性**：2026-08-13 工作区中 `NeriPlayer-HarmonyOS/README.md` 与 `PORTING.md` 曾被改为声称"所有功能已完整移植"，与代码证据（`YouTubeMusicApi.ets` 取流抛错、下载传输未实现、无 WebSocket/NAPI 模块）矛盾，已于 2026-08-14 按本审计与 `hm.md` §3.2 的能力表更正。后续不得再将占位实现描述为功能闭环。

## 勘误与进展（2026-08-31 复核）

正文与 2026-08-14 勘误节均为当时点事实；以下按当前源码（HEAD `ad8b9450`）与提交记录复核更新，冲突时以本节与 `FEATURE_MATRIX.md` 为准：

- **源码规模**：`NeriPlayer-HarmonyOS/entry/src/main/ets` 下 239 个 `.ets` 文件、49,834 行（2026-08-31 实测）；2026-08-14 勘误节的 56 文件 / 7,698 行为当时数字。
- **测试**：`entry/src/test/` 已累积至 874 用例（2026-08-29 记录全绿），`entry/src/ohosTest/` 已从骨架长成覆盖播放/下载/同步/一起听/诊断等场景的设备测试族。正文"未发现 ArkTS 单元测试"与差距表"测试是当前最大工程风险之一"的结论已过时。
- **差距表多项已落地或定案**：下载传输/校验/恢复全链落地并模拟器实测（2026-08-16，M3）；GitHub/WebDAV 同步移植完成并过双实例本地服务器冲突验收（M5/M5.6，2026-08-22）；一起听核心链路双端设备闭环（M7.5）；动态取色与背景模糊/玻璃子集落地（M8.1/M8.4）；USB 独占经 M9.1 spike **定案不移植**；崩溃诊断闭环落地（M9.2）；YouTube 取流部分落地（搜索 + 匿名 IOS 直连，播放受上游约一分钟封顶，M6.1/M6.5）。
- **能力状态明细**一律以随里程碑回写的 `FEATURE_MATRIX.md` 与 `PORTING_EXECUTION_PLAN.md` §6/§8 为准，本审计不再逐项跟进。

## 勘误与进展（2026-09-08 复核）

正文与此前勘误节均为当时点事实；以下按当前源码（HEAD `41e5a89`）与提交记录复核更新，冲突时以本节与 `FEATURE_MATRIX.md` 为准：

- **工程基线**：根 `build-profile.json5` 的 `compatibleSdkVersion`/`targetSdkVersion` 已于 2026-09-07 迁移为 `26.0.0`（API 26，纯 SemVer；commit `59b65d6`，记录见 `hm.md` §7.12），26 以下设备不再可安装；2026-08-14 勘误节「6.1.1(24) 即本项目基线」已过时。
- **包名**：`AppScope/app.json5` 的 `bundleName` 已于 2026-09-01 改为 `moe.ouom.neriplayer.hmos`（commit `cfe3e8e`）。
- **源码规模**：`NeriPlayer-HarmonyOS/entry/src/main/ets` 下 251 个 `.ets` 文件、53,753 行（2026-09-08 实测）；2026-08-31 复核节的 239 文件 / 49,834 行为当时数字。
- **测试**：`entry/src/test/` 静态清点 935 个 `it(` 用例（2026-09-08）；最近一次全量执行仍为 2026-08-29 的 874/874 全绿，此后新增用例的真实通过计数待 Windows 工作站执行 `hvigorw test` 后回填。
