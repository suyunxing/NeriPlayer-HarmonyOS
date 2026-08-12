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
