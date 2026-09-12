# NeriPlayer for HarmonyOS (音理音理!)

<div align="center">

<img src="NeriPlayer-HarmonyOS/entry/src/main/resources/base/media/app_icon.png" width="128" height="128" alt="NeriPlayer Icon" />

<h3>✨ 一个把多源在线播放、本地管理、歌词体验和自建同步做进纯血鸿蒙的音频播放器 🎵</h3>

<p>
  <a href="https://github.com/suyunxing/NeriPlayer-HarmonyOS/releases">
    <img alt="Release" src="https://img.shields.io/github/v/release/suyunxing/NeriPlayer-HarmonyOS?include_prereleases&label=Release&color=0A59F7" />
  </a>
  <a href="https://developer.huawei.com/">
    <img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-26.0.0%20(API%2026)-0A59F7?logo=huawei&logoColor=white" />
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-GPL%203.0-blue.svg" />
  </a>
  <a href=".github/workflows/harmonyos-ci.yml">
    <img alt="CI Build" src="https://img.shields.io/badge/CI-Passing-brightgreen?logo=github-actions&logoColor=white" />
  </a>
  <a href="NeriPlayer-HarmonyOS/entry/src/test/">
    <img alt="Unit Tests" src="https://img.shields.io/badge/Unit%20Tests-935%20Passing-success?logo=checkmarx&logoColor=white" />
  </a>
  <img alt="ArkTS" src="https://img.shields.io/badge/Language-ArkTS%20%7C%20ArkUI-orange" />
</p>

<p>
本项目的名称及图标灵感来源于《星空鉄道とシロの旅》中的角色「风又音理」。
</p>

<p>
基于纯血鸿蒙（HarmonyOS NEXT 26.0.0 Release / API 26）Stage 模型全新打造，<br/>
全量采用 ArkTS 严格模式与 ArkUI 声明式范式重构，围绕「多源探索、在线播放、本地可控、数据自持」持续打磨。
</p>

🛠️ <strong>Active development / 持续迭代中</strong>

</div>

> [!WARNING]
> 本项目仅供学习与研究使用，请勿将其用于任何非法用途。
>
> 本项目及维护者不接受任何形式的赞助、捐赠或商业资助。

---

> [!NOTE]
> NeriPlayer 不提供公共云端曲库或媒体分发服务。
> 在线音频能力依赖用户在第三方平台上的账号授权，会员或受限内容仍需遵循原平台规则。
> 为保护用户账号免受第三方平台风控与行为采样风险，NeriPlayer 坚决**不向第三方平台回传本地播放历史与收听统计**；
> 云同步仅走用户自持的 GitHub 仓库或 WebDAV 服务。

---

## 快速定位 / Start here

如果你只是想体验应用，请看 [快速体验与安装](#-快速体验与安装--getting-started)。
如果你想了解项目能力，请看 [项目亮点](#-项目亮点--why-it-stands-out) 和 [移植现状与能力矩阵](#-移植现状与能力矩阵--feature-matrix)。
如果你想了解工程架构，请看 [系统架构与目录分工](#-系统架构与工程结构)。
如果你准备贡献代码，请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。

```text
NeriPlayer for HarmonyOS
├── 多源在线播放：网易云 (WEAPI/降级) / Bilibili (WBI/DASH) / YouTube Music
├── 鸿蒙原生声色：一镜到底转场 (Now Playing Transition)、ColorScience 动态取色流光、HDS 悬浮 Tab
├── 本地优先数据：Asset 凭据保险箱、缓存、下载、本地歌单、历史、统计、设置
├── 可选自有同步：GitHub / WebDAV 三路因果合并与删除墓碑防复活
├── 规范音频生态：AVPlayer / AVSession 播控中心联动、后台长时任务、AMLL TTML 逐字歌词
└── 可恢复运行：SafeMode、FaultLogger / hiAppEvent 崩溃捕获、调试诊断
```

---

## 📖 项目简介 / About

**NeriPlayer for HarmonyOS** 是源自优秀 Android 开源播放器 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) 的纯血鸿蒙原生移植工程。我们不只是机械搬运逻辑，而是以 HarmonyOS NEXT 原生设计规范（HDS）与 ArkTS/ArkUI 开发范式为底座进行全栈重塑，在保持多源聚合与数据自持特性的同时，打造出兼具鸿蒙系统美学与丝滑手感的现代流媒体音乐播放器。

### 核心定位与设计哲学

- **账号即能力**：通过第三方平台授权启用搜索、播放、歌单和收藏夹访问，不依赖任何中心化代理服务器。
- **本地优先**：播放缓存、下载文件、歌单、历史记录、设置与授权信息默认全部保存在设备本地沙箱中。
- **去中心化自主持有同步**：用户可将歌单、收藏、最近播放和播放统计同步到自持的 GitHub 仓库（支持私有仓库）或 WebDAV 远端，拒绝第三方托管。
- **尊重隐私与账号安全**：坚决不向第三方平台上传本地播放历史和听歌统计，避免触发流媒体平台的异常登录与行为采样风控。
- **Stage 纯血单 Ability 架构**：`EntryAbility` 作为统一入口，全界面基于 ArkUI `Navigation` + `NavPathStack` 路由栈组织，实现全屏内容穿透状态栏的顶部与底部沉浸式体验。
- **启动与恢复链路**：标准启动流程为 `Loading -> Disclaimer -> Onboarding -> Main`；若上次启动异常崩溃，自动进入 `SafeMode` 安全模式防止崩溃循环。
- **确定性工程测试护栏**：内建 935 个确定性单元测试（@ohos/hypium 全绿通过），严密覆盖数据合并、编解码、下载事务、色彩矩阵与播放状态机。

---

## ✨ 项目亮点 / Why it stands out

- **纯血鸿蒙一镜到底转场（Now Playing Transition）**：
  重构丢弃了易产生卡顿抖动的 JS 逐帧计时器，全面切换为 ArkUI 原生属性动画 `.animation()` 驱动。从底部 MiniPlayer（药丸药囊）展开至全屏播放页，实现封面尺寸与坐标的平滑飞行、控制按钮错峰淡入淡出、弹性阻尼回弹，并辅以自研 `TitleBarBlurBackdrop` 渐变模糊，让内容无缝穿透状态栏，兼具视听冲击力与极致手感。
- **多源探索与自动换源兜底**：
  `PlayerManager` 接管全流程音源调度与容灾。当网易云音乐遇到无版权、试听片段或解析失效时，自动触发音质降级；降级仍不可播时，通过内置算法按歌名、歌手与时长综合评分，**毫秒级自动切换至 Bilibili 对应音轨兜底**；遇到偶发网络故障时自动重刷直链，保障播放不中断。
- **ColorScience 动态取色与呼吸流光**：
  全自主纯 ArkTS 实现的色彩科学算法引擎，基于 CIE Lab / LCh 颜色空间、ΔE00 色差计算与真实色卡吸附，毫秒级提取专辑封面的核心主导色，动态注入播放器背景与全局组件，营造随音乐流动的光影氛围。
- **深度 AMLL TTML 与逐字动效歌词**：
  完整支持 Apple Music 级 AMLL TTML 格式与标准 LRC 双语歌词。支持逐字/逐词 Karaoke 发光高亮跟随、双语翻译对照、音译排版、单行/双行视差滚动与点击任意行精准 Seek 跳转；配合缺省歌词时基于 NLP 正则清洗与网易候选评分的自动匹配管线。
- **系统级 AVSession 与播控中心深度合规**：
  严格遵循 HarmonyOS 媒体规范，拒绝利用 `title` 蹭位的做法；将完整 LRC 写入系统 `lyric`（API 10+），将当前歌词行写入 `singleLyricText`（API 17+）；注册 `setLaunchAbility` 支持锁屏与通知播控卡片一键直达当前播放界面；接入 `toggleFavorite` 收藏联动并在 API 26 上规范声明媒体控制按钮集。
- **工业级断点续传下载引擎**：
  多任务受控并发调度，支持 DIRECT / RANGE（`.part` 偏移与 ETag 校验）与 HLS 分片多级恢复；采用**两阶段事务提交机制**（Staging 临时落盘校验 $\to$ 原子重命名归档 $\to$ 编目更新），彻底杜绝异常中断产生的损坏脏文件；支持脱机环境直读 fd 极速离线音频解码。
- **双端互通的因果一致性云同步**：
  与 Android 上游数据协议保持二进制级完全兼容，支持 Protobuf Wire 紧凑流、GZIP 压缩与 JSON 解析；内置基于逻辑时钟的三路因果合并（Three-way Merge）与删除墓碑（Tombstone）机制，彻底消除“一端删除、另一端同步后又复活”的顽疾；支持 GitHub Git Data API（树/提交/分支原子更新防冲突）与 WebDAV。
- **亚秒级时钟对齐「一起听」**：
  自研纯 ArkTS WebSocket 长连接客户端，实时估算网络 RTT 与服务端时钟漂移，动态平滑将端到端时钟对齐压制在 300ms 黄金同步窗口；支持房间主持权流转与受信任直链共享，房主音源直链经权威端点分发，避免听众端触发二次解析风控。
- **全形态响应式与无障碍关怀**：
  覆盖 Phone（直板机）、Foldable（折叠屏内屏展开 707vp LG 断点）、Tablet 与 2in1 自由悬浮窗口；基于 `GridRow` / `GridCol` 自动切换多列栅格与侧边栏布局；深度适配系统 0.85× ~ 1.75× 字体缩放（无文本溢出或截断）；全界面交互控件严格保障 $\ge 40\text{vp}$ 触控面积。
- **系统级凭据保险箱（Asset Store）**：
  所有敏感 Cookie、Token 与 GitHub PAT 均加密托管至 HarmonyOS 系统级安全底座 `@ohos.security.asset`；独创自适应 Chunk 分块透明重组机制，优雅规避系统单个 Asset 1024 字节上限。
- **全链路故障自愈与安全模式**：
  基于 `FaultLogger`（历史崩溃拉取）与 `hiAppEvent`（实时事件捕获）建立双通道诊断监控；当检测到上次异常退出或崩溃循环时，启动时直接挂起主流程并进入 `SafeMode`，提供日志查阅、脱敏导出与配置重置能力。

---

## 📊 移植现状与能力矩阵 / Feature Matrix

> 详细的任务排期与历史审计证据请参阅 [docs/FEATURE_MATRIX.md](docs/FEATURE_MATRIX.md) 与 [docs/PROJECT_AUDIT.md](docs/PROJECT_AUDIT.md)。

| 功能领域 | 特性模块 | 状态 | 实施说明与端侧现状 |
| :--- | :--- | :---: | :--- |
| **多源在线播放** | 网易云音乐 | ✅ 已闭环 | WEAPI 协议、QR 扫码登录、Cookie 导入、每日推荐、歌单无截断全量导入、音质降级取流 |
| | 哔哩哔哩 (B站) | ✅ 已闭环 | WBI 签名鉴权、QR 扫码登录、收藏夹全量并发分页加载、DASH 音轨优选、Referer 防盗链注入 |
| | YouTube Music | ⏳ 演进中 | 搜索与匿名移动端直连取流已通；受 Google 直链限制当前单轨约 1 分钟，后续待接入 PoToken/JS 逆向运行时 |
| | 多源自动换源 | ✅ 已闭环 | 网易云无版权/失效时，按匹配度算法自动换源至 Bilibili 对应音频兜底 |
| **播放核心与音频** | AVPlayer 核心控制 | ✅ 已闭环 | 队列、随机、循环、倍速（0.5x~2.0x）、断点恢复、VolumeFader 平滑淡入淡出、API 26 原生播放列表桥接 |
| | AVSession 媒体中心 | ✅ 已闭环 | 锁屏/通知栏/控制中心联动、双向元数据同步、逐行歌词、单曲收藏、拉起 Ability 回跳 |
| | 后台播放与保活 | ✅ 已闭环 | 申请 `AUDIO_PLAYBACK` 长时任务，进入后台稳定连续播放，暂停即释放合规治理 |
| | USB 独占输出 | 🚫 定案不移植 | SDK 缺公开 USB DDK 头文件且 ArkTS 单线程无法满足 1ms 等时节拍；系统 AVPlayer 经系统 HAL 已能正常 USB 输出 |
| **歌词与视觉** | AMLL TTML / LRC 歌词 | ✅ 已闭环 | 逐字发光跟随动画、双语翻译对照、单双行排版、点击时间戳跳转、NLP 缺省自动匹配 |
| | 一镜到底转场 | ✅ 已闭环 | MiniPlayer ↔ 正在播放页面属性动画展开/收拢、封面弹性位移、沉浸式状态栏渐变穿透 |
| | ColorScience 取色 | ✅ 已闭环 | 纯 ArkTS CIE Lab / LCh / ΔE00 算法，毫秒级封面取色并生成动态呼吸流光背景 |
| | 桌面悬浮歌词 | ⏳ 演进中 | 应用内悬浮条已完成；系统级桌面歌词已打通至系统服务层，图形上屏待真机验证 |
| **离线与数据** | 工业级下载引擎 | ✅ 已闭环 | Range/HLS 续传、两阶段事务提交、脱机短路读取 fd 极速解码 |
| | 本地音乐与沙箱 | ✅ 已闭环 | 沙箱媒体库、`READ_AUDIO` 授权扫描、元数据解析与封面提取 |
| | 凭据安全保险箱 | ✅ 已闭环 | 基于 `@ohos.security.asset` 的系统加密存储，Chunk 分块突破 1024B 上限 |
| **同步与协作** | 因果云同步 | ✅ 已闭环 | 兼容 Android 双端 Protobuf/JSON 格式，GitHub Git Data API / WebDAV 三路因果合并与墓碑防复活 |
| | 一起听 (Listen Together) | ✅ 已闭环 | WebSocket 长连接、网络 RTT 与时钟漂移控制在 300ms 内、权威直链共享 |
| **架构与容灾** | 响应式多形态适配 | ✅ 已闭环 | 直板机、折叠屏（Mate X7 707vp LG 断点）、平板、2in1 自由悬浮窗栅格自适应 |
| | 异常诊断与安全模式 | ✅ 已闭环 | `FaultLogger` + `hiAppEvent` 监控，启动失败自动进入 `SafeMode` 安全自愈 |

---

## 🏗️ 系统架构与工程结构

### 模块分工说明

```text
NeriPlayer-HarmonyOS/
├── NeriPlayer-HarmonyOS/          # 【核心主线】HarmonyOS NEXT 原生工程 (Stage 模型)
│   ├── AppScope/                 # 全局配置、多语言国际化与应用图标
│   └── entry/                    # 单 HAP 核心业务模块
│       ├── src/main/ets/         # ArkTS 业务源码
│       │   ├── app/              # EntryAbility 生命周期、系统常量与崩溃防御
│       │   ├── data/             # 数据持久化、Asset 凭据保险箱、历史与统计
│       │   ├── download/         # 下载引擎、任务状态机与两阶段编目落盘
│       │   ├── listentogether/   # 一起听 WebSocket 协议、会话管理与时钟同步
│       │   ├── lyrics/           # AMLL TTML / LRC 歌词解析器与渲染驱动
│       │   ├── model/            # 领域模型定义（Song, Playlist, Lyric, Task）
│       │   ├── network/          # HTTP 客户端、网易云/B站/YTM 平台适配器
│       │   ├── player/           # AVPlayer / AVSession 播放控制器与音量平滑
│       │   ├── sync/             # 双向因果云同步、Protobuf/JSON 编解码管线
│       │   ├── util/             # ColorScience 色彩科学、二维码引擎、断点度量
│       │   └── view/             # ArkUI 声明式页面、HDS 组件与一镜到底动画
│       ├── src/test/             # 本地确定性单元测试 (935+ Cases，全绿)
│       └── src/ohosTest/         # 设备端侧集成测试集 (Acts* 真实环境用例)
├── docs/                         # 架构规范、协议分析、安全审计与移植进展看板
├── NeriPlayer-master/            # 上游 Android/Kotlin 参考源码快照 (只读参照)
├── build-signed.sh               # Linux 服务端一键构建与 hap-sign-tool 签名脚本
└── .github/workflows/            # CI 持续集成与 Release 自动发布工作流
```

---

## 🛠️ 构建与开发环境

### 开发环境依赖

* **操作系统基线**：HarmonyOS `26.0.0 Release`（纯 SemVer API 26 基线）
* **开发工具链**：DevEco Studio 26.0.0.621+ 或 `command-line-tools` 26.0.0.821+
* **运行环境**：Node.js v18+（工具链内置）、Java JDK 17（签名工具依赖）

### 快速本地编译（生成未签名包）

在工程根目录下进入主工程目录执行：

```bash
cd NeriPlayer-HarmonyOS

# 1. 安装工程依赖
ohpm install --all

# 2. 执行 Release 构建 (生成 unsigned HAP)
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=release --no-daemon

# 3. 运行本地单元测试 (935+ 测试用例)
hvigorw test --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

构建产物将位于：`NeriPlayer-HarmonyOS/entry/build/default/outputs/default/entry-default-unsigned.hap`。

---

## 📦 快速体验与安装 / Getting Started

由于 HarmonyOS 系统强制要求应用具有有效的调试证书签名才能在设备上安装运行，**面向社区公开发行的 Release 包均为未签名安装包 (Unsigned HAP)**。

### 方式一：从 GitHub Releases 下载（推荐）

1. 前往本仓库 [Releases 页面](../../releases) 下载最新版的 `NeriPlayer-vX.Y.Z-unsigned.hap`。
2. 校验文件配套的 `SHA256SUMS.txt` 完整性。
3. 按照发布包内附带的 [INSTALL.md](INSTALL.md) 指南，使用您在华为开发者联盟（AGC）申请的个人调试证书对 HAP 签名并安装。

### 方式二：开发者一键签名与安装

如果你本地已在 `NeriPlayer-HarmonyOS/signing/` 目录下放置了 AGC 调试签名材料（`harmonyos_debug.p12`、`cer`、`NeriPlayerDebug.p7b`）：

**Linux / macOS 终端**：
```bash
# 根目录下执行一键构建并自动签名
./build-signed.sh

# 通过 hdc 推送到已连接的真机或模拟器
hdc install -r NeriPlayer-signed.hap
```

**Windows PowerShell**：
```powershell
$env:DEVECO_SDK_HOME = "C:\path\to\command-line-tools\sdk"
$env:DEVECO_STUDIO_HOME = "C:\path\to\DevEco Studio"
$env:NERIPLAYER_DEVICE_IDS = "<设备UDID>"
$env:NERIPLAYER_SIGNING_PASSWORD = "<本地调试口令>"

cd NeriPlayer-HarmonyOS
.\sign-local.ps1
```

首次在设备启动应用后，根据引导完成**免责声明**与**新用户引导**。本地音乐扫描需授权 `ohos.permission.READ_AUDIO` 权限，后台连续播放请确保保持 `ohos.permission.KEEP_BACKGROUND_RUNNING` 授权。

---

## 🧪 质量工程与测试护栏

本项目坚持测试驱动开发（TDD）与确定性自动化验证，构建了完备的质量保护网：

| 校验层级 | 工具与框架 | 当前状态 | 覆盖与保障范围 |
| :--- | :--- | :---: | :--- |
| **本地单测** | `@ohos/hypium` 1.0.28 | **935 / 935 全绿** | 覆盖同步三路合并、Protobuf/JSON 双向编解码、ColorScience 色彩矩阵、二维码生成器、下载状态机等 |
| **代码规范** | `CodeLinter` | **0 Error 基线** | 严格保障 ArkTS 规范、异步 Promise 处理机制与资源引用安全 |
| **设备端测** | `ohosTest` + `aa test` | **50+ 项设备用例** | AVPlayer 真实网络取流、Asset 凭据安全存取、长时任务后台保活、断网自愈与异常自愈 |
| **持续集成** | GitHub Actions | **自动化守护** | push / PR 自动拉起 HarmonyOS API 26 环境执行编译与自动化检查 |

---

## 🤝 参与贡献与开发

我们热烈欢迎开发者参与 NeriPlayer for HarmonyOS 的共建！

- 开发前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 了解代码规范与 PR 提交流程。
- 分支策略：
  - `main`：**稳定主干分支**，受保护分支，所有提交均需通过 CI 验证。
  - `dev`：**日常特性集成分支**，前沿特性的主工作区。
  - `feature/*` / `fix/*`：针对具体特性或缺陷修复的临时工作分支。

---

## 📄 开源协议与鸣谢 / License & Acknowledgements

* **开源协议**：本项目基于 **[GPL-3.0 License](LICENSE)** 协议开源。
* **上游项目**：衷心感谢原 Android 版作者与团队 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) 杰出的架构设计与开放分享精神。
* **社区生态**：感谢 OpenHarmony / HarmonyOS 开发者社区的开源工具支持，以及 AMLL 社区为歌词生态做出的卓越贡献。
