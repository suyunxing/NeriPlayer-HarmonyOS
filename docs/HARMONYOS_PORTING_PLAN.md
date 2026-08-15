# HarmonyOS 6.0～7.0 ArkTS 迁移路线图

> 本文是战略路线图。任务级执行计划与跨会话进度看板见 `docs/PORTING_EXECUTION_PLAN.md`（2026-08-16 创建，含两侧审计基线、里程碑任务清单与验证协议）。

## 目标与约束

目标是把 NeriPlayer 迁移为 HarmonyOS 普通应用，主语言 ArkTS、UI 使用 ArkUI、应用模型使用 Stage 模型。迁移以行为兼容和可测试性为目标，不逐行翻译 Kotlin，也不把 ASCF 元服务当成主实现。

工程基线为 `6.1.1(24)`。官方版本映射已于 2026-08-14 复核（[所有 HarmonyOS 开发套件版本](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)）：HarmonyOS 6.0.0→API 20、6.0.1→21、6.0.2→22、6.1.0→23、6.1.1→24（当前最新稳定 Release），HarmonyOS 7.0→开发套件 26.0.0（API 26，Beta；版本号自 26.0.0 起改用 SemVer）。本机两套 SDK 均已安装：API 24 Release 位于 `D:\HarmonyOS\Tools\command-line-tools\sdk`，API 26 Beta2 随 DevEco Studio 26.0.0.621。各模块迁移前仍须按官方 API 差异页逐项确认废弃接口与行为变化，不能凭目录名或记忆推断。

## 建议架构

```text
entry/src/main/ets/
├── app/                 应用启动、依赖装配、日志、错误边界
├── domain/              与平台无关的实体、值对象、用例、接口
├── data/
│   ├── local/           preferences、关系型数据、文件和迁移
│   ├── remote/          HTTP/WebSocket、平台 API、鉴权
│   └── repository/      domain 接口实现
├── playback/
│   ├── engine/          AVPlayer 适配器
│   ├── session/         AVSession 与系统控制
│   ├── queue/           纯 ArkTS 队列状态机
│   └── background/      后台任务、音频中断与生命周期
├── download/            任务状态机、传输、校验、原子提交、恢复
├── sync/                GitHub/WebDAV、冲突合并、凭据抽象
├── feature/             按页面/业务域组织 UI 与状态
├── native/              USB 等 NAPI 边界（不把业务逻辑放入 C++）
└── shared/              小型通用组件、格式化、契约类型
```

关键原则：

- `domain` 不导入 `@kit.*`，从而可做快速、确定性的 ArkTS 单元测试。
- AVPlayer、HTTP、文件、时间和随机数均通过接口注入；测试使用 fake，而非访问真实平台。
- UI 只订阅不可变状态并派发意图，播放和下载状态机不依赖页面生命周期。
- 所有跨端数据都定义显式 schema 版本，保留 Android fixture 做兼容测试。
- HarmonyOS 7.0 增强能力通过小型 capability adapter 接入，不污染 6.x 公共核心。

## 平台能力映射（待目标 SDK 实测）

| Android | HarmonyOS 主方向 | 注意事项 |
| --- | --- | --- |
| Activity/Application | UIAbility/AbilityStage | 冷启动、恢复与多窗口生命周期不同 |
| Jetpack Compose | ArkUI 声明式 UI | 状态所有权、路由、列表复用需重新设计 |
| Media3 ExoPlayer | MediaKit AVPlayer | 支持格式、缓存、错误码和数据源能力并非一一对应 |
| MediaSession | AVSessionKit | 系统控制、元数据和后台行为必须真机验证 |
| Foreground Service | audioPlayback 后台模式/连续任务 | 权限、配额和系统回收策略不同 |
| OkHttp/WebSocket | NetworkKit HTTP/WebSocket | Cookie、重定向、证书、流式响应需封装 |
| DataStore/Room | preferences/关系型存储/文件 | 建立 schema、迁移与原子写策略 |
| WorkManager | 后台任务/延迟任务/任务池 | 依据任务时长和触发条件分别选型 |
| MediaStore/SAF | 用户文件与媒体访问相关 Kit | 权限和 URI 生命周期必须在真机确认 |
| JNI/USB Host | NAPI C++/USB 能力 | 先做 syscap 与设备支持调研，再移植协议层 |

## 分阶段实施

### 阶段 0：建立可复现基线

- 获取 Android 上游 commit 与子模块 commit。
- 安装目标 DevEco Studio，记录 SDK、Hvigor、ohpm、Node/JBR 版本。
- 建立 `hos6` 与 `hos7` 构建/设备矩阵；如果工具链要求不同工程模型，使用产品配置或小型兼容层，而不是复制整个项目。
- 执行干净构建；禁止以已有 `.hvigor` 和 `build` 缓存作为成功依据。
- 建立 unit test、ohosTest、lint 三条最小流水线。

退出条件：新机器按文档能完成同步、编译、安装和 smoke test。

### 阶段 1：领域契约与本地 fixture

- 固化 Song、Playlist、Queue、Lyrics、Download、Settings schema。
- 从 Android 测试中提取合法的匿名化 fixture。
- 移植稳定歌曲键、LRC 解析、队列随机/循环和序列化测试。
- 建立错误类型：网络、鉴权、受限内容、解析、存储、播放、系统策略。

退出条件：核心纯逻辑测试不依赖设备与网络，并与 Android fixture 一致。

### 阶段 2：播放垂直切片

- AVPlayer 生命周期与事件适配器。
- 队列状态机、seek、错误恢复、音频中断。
- AVSession 元数据与控制命令。
- 后台播放、熄屏、应用被回收后的恢复策略。
- 先使用本地或自有测试音频，避免第三方接口干扰定位。

退出条件：功能矩阵中的“首个可交付垂直切片”全部通过。

### 阶段 3：数据层与本地媒体

- preferences 与关系型/文件存储选型。
- 数据库/JSON schema 版本化、迁移、备份与损坏恢复。
- 本地媒体授权、扫描、元数据和失效文件处理。
- 播放历史、统计、收藏和歌单的事务一致性。

退出条件：升级、权限拒绝、空间不足和异常终止场景均有测试。

### 阶段 4：在线来源适配器

- 统一 `MusicSource` 接口，网易云/Bilibili/YouTube 分别实现。
- 搜索、详情、歌词、取流、登录态、限流和错误映射分层。
- 解析逻辑使用录制/脱敏响应做契约测试；少量在线 smoke test 单独运行。
- YouTube signature/n/PoToken 作为独立研究任务，不让其阻塞其他来源。

退出条件：每个平台在匿名/登录/过期会话/受限内容四类状态下行为明确。

### 阶段 5：下载、同步和凭据

- 下载状态机：Range/HLS、重试、校验、原子提交、恢复、清理。
- 使用系统安全能力保存 token/cookie；日志不得输出凭据。
- GitHub/WebDAV 使用 ETag/条件写和确定性三方合并。
- 提供从 Android 数据导入的显式工具，而不是隐式猜测旧格式。

退出条件：断网、进程终止、冲突、空间不足和凭据失效测试通过。

### 阶段 6：高风险能力

- Listen Together：协议兼容、时钟偏移、重连和主从切换。
- USB 独占：先验证 HarmonyOS 目标设备的 USB Host/syscap/NAPI 能力，再复用纯协议 C++；平台 I/O 层必须重写。
- 悬浮/状态栏歌词、动态取色、高级模糊按系统能力和审核政策分级降级。

退出条件：每项能力有支持矩阵、明确降级路径和独立开关。

### 阶段 7：6.x/7.x 发布门槛

- 在每个目标系统版本上执行构建、安装、升级、权限、后台、媒体控制、网络和存储测试。
- 对 7.0 新接口只在 capability 检测后启用；6.x 路径持续回归。
- 完成无障碍、平板/2in1、功耗、内存、隐私和应用市场合规检查。

退出条件：发布矩阵中的所有必选设备/系统组合通过，且没有签名材料或本地 SDK 路径进入 Git。

## 近期优先级

> 2026-08-14 复核：第 1 项已于 2026-08-13 完成（干净构建 + 单测 + 签名 + 模拟器 smoke test，见 `hm.md` §7.4；工具链迁至 `D:\HarmonyOS\Tools` 后需重跑一次确认）；第 3 项部分完成（已建 `entry/src/test/` 并通过 LRC 3 用例，其余模块待补）。

1. 恢复可用 DevEco SDK 并做干净构建。
2. 获取上游 commit/子模块基线。
3. 为 ArkTS 原型补测试目录和首批纯逻辑测试。
4. 将 PlayerManager 拆成可测试状态机与 AVPlayer 适配器。
5. 用本地 fixture 完成首个播放闭环，再继续第三方平台联调。

## 官方资料复核清单

在华为开发者文档中按目标 SDK 版本逐项确认：ArkTS 语言约束、ArkUI 状态管理与路由、AVPlayer、AVSession、音频中断、后台音频/连续任务、HTTP/WebSocket、preferences/关系型数据库、文件与媒体访问、权限申请、安全凭据、NAPI、USB、测试框架、API 差异与废弃说明。

每项调研应在 issue/文档中记录：官方页面 URL、页面更新时间、适用 API Level、最小示例、模拟器结果、真机结果和降级方案。

