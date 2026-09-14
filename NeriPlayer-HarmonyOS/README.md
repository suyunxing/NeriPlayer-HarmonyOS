# NeriPlayer for HarmonyOS (主线应用工程)

本目录为 NeriPlayer 的 **HarmonyOS NEXT 原生主线应用工程**，基于纯血鸿蒙 Stage 模型、ArkTS 严格模式与 ArkUI 声明式组件开发。

> **工程基线**：HarmonyOS 26.0.0 Release（纯 SemVer API 26 基线，`compatibleSdkVersion: "26.0.0"`）。
> **协议声明**：遵循 [GPL-3.0 License](../LICENSE)。原版 Android 参照工程：[cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)。

---

## 模块架构与职责

工程采用单 Ability（`EntryAbility`）单 HAP 架构，核心源码位于 `entry/src/main/ets/`：

```text
entry/src/main/ets/
├── entryability/     # EntryAbility 实例生命周期、窗口配置与沉浸式沉淀
├── pages/Index.ets   # 根视图路由分发与启动状态机
├── app/              # 全局常量、日志规范与双通道崩溃诊断 (FaultLogger + hiAppEvent)
├── model/            # 纯业务领域模型 (Song, Playlist, Lyric, Task, SyncSnapshot)
├── data/             # 凭据保险箱 (@ohos.security.asset)、历史记录、播放统计与配置中心
├── download/         # 工业级断点续传引擎 (两阶段事务提交、Range/HLS 分块续传、断网自愈)
├── network/          # 网易云 (WEAPI)、哔哩哔哩 (WBI/DASH)、YouTube Music 与通用 HTTP 客户端
├── player/           # 播放控制器 (AVPlayer)、系统播控中心 (AVSession)、后台任务与音量淡入淡出
├── lyrics/           # AMLL TTML / 标准 LRC 歌词解析器、逐字跟随与自动评分匹配管线
├── listentogether/   # 一起听长连接 (纯 ArkTS WebSocket、时钟漂移平滑对齐与权威直链共享)
├── sync/             # 跨端因果云同步 (兼容 Android 端 Protobuf/JSON、三路因果合并与墓碑防复活)
├── util/             # ColorScience 动态色彩科学、二维码生成、响应式断点与窗口度量
└── view/             # ArkUI 声明式页面 (首页、探索、资料库、设置、正在播放一镜到底、安全模式)
```

---

## 质量工程与测试状态

本工程严格践行质量内建与测试护栏原则：

- **本地单元测试 (`entry/src/test/`)**：
  基于 `@ohos/hypium` 1.0.28，拥有 **980 个确定性测试用例（最近一次全量执行 874/874 全绿，2026-08-29）**，覆盖因果同步三路合并、Protobuf/JSON 双向编解码、色彩科学矩阵、二维码生成器、下载状态机等核心算法与业务逻辑。
- **静态代码检查 (`code-linter.json5`)**：
  遵循 ArkTS 严格语法规范，保持 **0 Error** 基线守护。
- **设备侧测试 (`entry/src/ohosTest/`)**：
  包含 `ActsAbilityTest` 等端侧自动化测试用例，覆盖真网 AVPlayer 取流、Asset 凭据安全存取、长时任务后台保活与断网重连。

---

## 本地编译与构建

### 1. 依赖与工具链要求

- **HarmonyOS SDK**：`26.0.0 Release` (API 26)
- **构建工具**：`command-line-tools` 26.0.0.821+ 或 DevEco Studio 26.0.0.621+
- **环境配置**：确保 `local.properties` 已正确指向 SDK 目录（如 `sdk.dir=/path/to/command-line-tools/sdk/default`，此文件为本地私有配置，不入库）。

### 2. 命令行构建命令

进入本目录后执行：

```bash
# 1. 安装/同步依赖
ohpm install --all

# 2. 执行 Release 构建 (生成 unsigned HAP)
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=release --no-daemon

# 3. 执行本地单元测试
hvigorw test --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

构建产物生成于：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

---

## 调试签名与安装

由于 HarmonyOS 系统强制校验应用签名，安装至真机或模拟器前须完成调试签名：

### 方式 A：Linux / 命令行自动化签名

在仓库根目录下，若已在 `signing/` 准备好 AGC 调试证书与 Profile，可直接执行根目录提供的构建脚本：

```bash
cd ..
./build-signed.sh
hdc install -r NeriPlayer-signed.hap
```

### 方式 B：Windows PowerShell 签名

在 Windows 环境下，通过设置环境变量并运行本地签名脚本：

```powershell
$env:DEVECO_SDK_HOME = "C:\path\to\command-line-tools\sdk"
$env:DEVECO_STUDIO_HOME = "C:\path\to\DevEco Studio"
$env:NERIPLAYER_DEVICE_IDS = "<真实设备UDID>"
$env:NERIPLAYER_SIGNING_PASSWORD = "<本地调试口令>"

.\sign-local.ps1
```

> **安全红线**：严禁将任何真实签名材料（`.p12`、`.cer`、`.p7b`）、密钥口令或设备 UDID 提交至 Git 仓库。

---

## 运行与权限说明

1. 首次启动应用时需完成免责声明确认与新用户引导流程。
2. 本地音乐库扫描依赖 `ohos.permission.READ_AUDIO` 用户授权。
3. 退出前台后继续播放音乐依赖 `ohos.permission.KEEP_BACKGROUND_RUNNING` 权限及系统长时任务授权。
