# NeriPlayer for HarmonyOS

<div align="center">

<img src="NeriPlayer-HarmonyOS/entry/src/main/resources/base/media/app_icon.png" width="128" height="128" alt="NeriPlayer Icon" />

### 现代、纯粹、沉浸的原生鸿蒙流媒体音乐播放器

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-26.0.0%20(API%2026)-0A59F7?logo=huawei&logoColor=white)](https://developer.huawei.com/)
[![License](https://img.shields.io/badge/License-GPL%203.0-blue.svg)](LICENSE)
[![CI Build](https://img.shields.io/badge/CI-Passing-brightgreen?logo=github-actions&logoColor=white)](.github/workflows/harmonyos-ci.yml)
[![Unit Tests](https://img.shields.io/badge/Unit%20Tests-935%20Passing-success?logo=checkmarx&logoColor=white)](entry/src/test/)
[![ArkTS](https://img.shields.io/badge/Language-ArkTS%20%7C%20ArkUI-orange)](#)

[功能特性](#-核心功能特性) • [系统架构](#-系统架构与工程结构) • [快速构建](#-构建与开发环境) • [安装与发行](#-安装与发行版) • [贡献与协议](#-开源协议与鸣谢)

</div>

---

## 📖 项目简介

**NeriPlayer for HarmonyOS** 是基于纯血鸿蒙（Next / 26.0.0+）Stage 模型全新打造的现代化开源音乐播放器。项目源于优秀 Android 开源播放器 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)，以 ArkTS 严格模式与 ArkUI 声明式范式全量重构，旨在为 HarmonyOS 终端用户带来融合官方设计美学（HDS）、动态流光声色体验与多源流媒体播放能力的旗舰级视听享受。

本仓库为主线稳定发行分支（`main`），代表当前经过严格工程化验收的稳定代码基线。

---

## ✨ 核心功能特性

### 🎵 现代播放与多源媒体融合
* **系统级音频生态集成**：基于 `@kit.AudioKit` (AVPlayer) 与 `@kit.MediaKit` (AVSession) 深度定制，支持锁屏播控通知、播控中心组件联动、系统媒体焦点响应与耳机插拔自适应挂起。
* **冷启动无缝会话恢复**：精确持久化播放队列、播放模式、循环队列状态及上次播放毫秒进度，冷启动毫秒级恢复无声无损。
* **网易云音乐生态**：
  * 基于安全 WEAPI 协议，支持原生 QR 二维码扫码登录与 Cookie 粘贴导入。
  * 用户歌单自动同步、批量导入本地自建库、官方每日推荐与热门雷达聚合流。
  * 高品质无损音频（Lossless / Hi-Res）智能解析与失败回退重试策略。
* **哔哩哔哩 (B站) 生态**：
  * 支持 WBI 动态混淆鉴权与 QR 扫码登录。
  * 个人收藏夹分页无损加载与一键入库播放。
  * DASH 音轨智能带宽自适应（标准 / 高清 / 超清 / 无损音质解析），智能注入流媒体防盗链 Referer 头与 bilivideo CDN 优选。
* **本地与沙箱媒体管理**：无网离线环境自动短路识别，提供直读 fd 极速离线音频解码播放。
* **YouTube Music**：支持移动端协议取流链路、版本健康度追踪与降级机制。

### 🎨 沉浸式流光视觉（Glass UI & HDS）
* **HarmonyOS Design System (HDS) 深度融合**：全面适配官方设计规范，提供悬浮式导航 Tab、原生 MiniBar 底部托盘槽位及自适应避让系统。
* **ColorScience 动态取色引擎**：自研基于 CIE Lab / LCh / ΔE00 算法与真实色卡吸附的高精度取色系统，从专辑封面毫秒级提取主色调，注入播放界面形成动态呼吸的流光背景（Immersive Light Scene）。
* **动态歌词系统**：
  * 深度支持 AMLL TTML 格式与标准 LRC 双语歌词。
  * 精准毫秒级逐字 Karaoke 发光跟随动画与双行翻译对照排版。
* **一镜到底无感转场**：基于 `geometryTransition` 与 `bindSheet` 架构，实现 MiniPlayer 至全屏播放页面的封面飞行一镜到底与丝滑歌单抽屉呼出。

### 📥 工业级断点续传下载引擎
* **多任务并发调度器**：严格受控的并发线程池管道，支持后台静默下载与优先级编排。
* **全场景断点续传**：针对 DIRECT / RANGE（`.part` 偏移与 ETag 校验）与 HLS 分片流提供双重指纹恢复策略。
* **网络自感知挂起/恢复**：感知系统网络连接与断网事件，自动保护暂存临时文件并在网络恢复时自动重新入队。
* **沙箱编目原子落盘**：两阶段事务提交（Staging 校验 $\to$ 重命名归档 $\to$ 更新元数据编目），避免因异常中断导致的脏数据。

### 🔄 跨端因果云同步 (Cloud Sync)
* **Android / HarmonyOS 双端互通**：完全兼容上游 Android 版的数据序列化标准，支持 Protobuf Wire 格式、GZIP 压缩流与高保真 JSON 备份解析。
* **因果一致性三路合并**：实现歌单、曲目元数据、播放统计与删除墓碑（Tombstone）的确定性版本判定收敛，彻底杜绝已删曲目跨端“复活”。
* **双存储后端支持**：
  * **GitHub 备份**：支持 Contents 与 Git Data API 流水线（Tree/Blob/Commit/Ref PATCH 乐观锁防冲突提交）。
  * **WebDAV 备份**：支持标准 PROPFIND、条件 PUT 与强 ETag / 指纹并发防护。

### 👥 实时「一起听」(Listen Together)
* **高可靠长连接架构**：自研 WebSocket 客户端，集成动态心跳检测、指数退避重连与 HTTP 状态二次兜底。
* **亚秒级时钟对齐**：智能估算端到端网络 RTT 与服务器时钟漂移，漂移严格控制在 300ms 黄金窗口内，平滑调整倍率与动态 Seek。
* **权限与受信任通道**：主持权切换、成员在线状态监控、安全直链鉴权转发机制（防直链被篡改与恶意投毒）。

### 📱 全场景响应式与关怀体验
* **多形态屏幕自适应**：
  * 完美适配 Phone（直板机）、Foldable（折叠屏内屏 707vp LG 断点）、Tablet（平板）与 2in1（PC 自由悬浮窗）。
  * 基于 ArkUI `GridRow` / `GridCol` 响应式断点栅格重排，大屏自动展开侧边栏与双列歌单布局。
* **系统关怀与无障碍保障**：
  * 深度适配系统字体缩放（0.85× ~ 1.75× 字阶），全界面无溢出、无折叠遮挡、消除不稳固百分比定位。
  * 交互控件严格保障 $\ge 40\text{vp}$ 触控命中区域，全量标注文案无障碍朗读语义。

### 🛡️ 金融级凭据安全与合规
* **系统级凭据保险箱**：所有第三方账户 Cookie、访问 Token 与 PAT 均加密托管至系统底座 `@ohos.security.asset`。
* **自适应分块存储机制**：针对网易云等超长 Cookie，创新自研 Chunk 分块透明拼接方案，完美规避系统 Asset 1024 字节物理上限。
* **全面隐私脱敏**：应用全生命周期日志全程脱敏，零外部未审查三方闭源 SDK。

---

## 🏗️ 系统架构与工程结构

### 目录角色分工

```text
NeriPlayer-HarmonyOS/
├── NeriPlayer-HarmonyOS/      # 【主线实现】HarmonyOS Stage 原生应用工程
│   ├── AppScope/             # 全局配置、多语言资源与应用图标
│   └── entry/                # 核心功能模块 (ArkTS/ArkUI)
│       ├── src/main/ets/     # 源码实现
│       │   ├── app/          # 全局生命周期、系统常量与崩溃防御
│       │   ├── data/         # 数据持久化、凭据管理、历史与统计
│       │   ├── download/     # 下载引擎、任务状态机与编目落盘
│       │   ├── listentogether/# 一起听网络、协议、会话与播放同步
│       │   ├── lyrics/       # AMLL TTML / LRC 歌词解析与渲染管线
│       │   ├── model/        # 领域数据模型定义
│       │   ├── network/      # HTTP 客户端、网易云/B站/YTM 平台适配器
│       │   ├── player/       # AVPlayer / AVSession 播放控制器
│       │   ├── sync/         # 双向云同步合并策略、Protobuf/JSON 编解码
│       │   ├── util/         # 纯 ArkTS 算法、色彩科学、二维码引擎
│       │   └── view/         # ArkUI 声明式页面、组件与转场路由
│       ├── src/test/         # 本地确定性单元测试 (935+ Cases，全绿)
│       └── src/ohosTest/     # 模拟器/真机设备端测试 (Acts* 用例)
├── docs/                     # 架构设计、协议逆向、安全规范与迁移审计文档
├── NeriPlayer-master/        # 上游 Android/Kotlin 源码快照与行为参照 (只读)
└── .github/                  # CI 持续集成与自动化 Release 发布流水线
```

---

## 🛠️ 构建与开发环境

### 环境要求

* **HarmonyOS SDK**：`26.0.0` (API 26 Release，纯 SemVer 基线)
* **编译工具链**：`command-line-tools` 26.0.0.821+ 或配套最新 DevEco Studio
* **Node.js**：v18+ (自带于 CLT `tool/node/bin`)
* **Java**：JDK 17 (用于 hap-sign-tool 签名工具)

### 快速本地编译

进入主线工程目录执行构建：

```bash
cd NeriPlayer-HarmonyOS

# 1. 安装工程依赖
ohpm install --all

# 2. 执行 Release 构建 (生成 unsigned HAP)
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=release --no-daemon

# 3. 运行本地单元测试 (900+ 用例)
hvigorw test --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

产物将生成在：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

---

## 📦 安装与发行版

由于 HarmonyOS 平台的签名机制，面向社区分发的 Release 产物均为**未签名安装包 (Unsigned HAP)**。用户只需配置自己的 AGC 个人调试证书即可极速安装到设备。

### 方式一：从 GitHub Releases 下载
1. 前往本仓库 [Releases 页面](../../releases) 获取最新版本的 `NeriPlayer-vX.Y.Z-unsigned.hap`。
2. 校验文件配套的 `SHA256SUMS.txt` 完整性。
3. 参考发布包内的 [INSTALL.md](INSTALL.md) 使用配套工具对 HAP 进行签名并推送到真机。

### 方式二：本地一键签名脚本（开发者）
若本地拥有已配置的 AGC 调试证书与配置文件（`p12` / `p7b` / `cer`），可在工程根目录直接执行：

```bash
# 执行本地构建与签名
./build-signed.sh

# 通过 hdc 推送到已连接的真机或模拟器
hdc install -r NeriPlayer-signed.hap
```

---

## 🧪 质量与测试工程

本项目坚持“测试驱动与确定性验证”的开发原则：

| 测试层级 | 框架 / 工具 | 规模与状态 | 覆盖范围 |
| :--- | :--- | :--- | :--- |
| **本地单测** | `@ohos/hypium` 1.0.28 | **935 / 935 用例通过** | 同步三路合并策略、JSON/Protobuf 双向编解码、色彩科学矩阵、二维码生成器、下载调度器、一起听状态机等 |
| **静态分析** | `CodeLinter` | **0 Error** 基线守护 | ArkTS 严格模式、异步 Promise 规范、资源引用安全 |
| **端侧测试** | `ohosTest` + `hdc aa test` | **50+ 项设备端测** | AVPlayer 真网取流播放、Asset 凭据跨进程落盘、后台保活、断网重连、双端实例同步 |
| **持续集成** | GitHub Actions | 自动化触发 | 每次提交自动拉起 API 26 环境验证编译与代码静态规范 |

---

## 🤝 贡献与协作

欢迎参与 NeriPlayer for HarmonyOS 的共建！

1. 在开发前请仔细阅读 [贡献指南](CONTRIBUTING.md) 与 [GitHub 协作与分支整合流程](docs/GITHUB_COLLABORATION.md)。
2. 本仓库分支分工：
   - `main`：**稳定发行分支**（默认分支），受严格保护，仅接受经过完整验证的合并。
   - `dev`：**主日常开发分支**，汇集各类特性分支与功能迭代。
   - `feature/*` / `fix/*`：针对具体任务的细分工作分支。
3. 提交 PR 时请关联相关的 Issue 并附带验证证据。

---

## 📄 开源协议与鸣谢

* **开源协议**：本项目基于 **[GPL-3.0 License](LICENSE)** 协议开源。
* **上游项目**：特别感谢原 Android 版作者及维护团队 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) 优秀的架构设计与开源贡献。
* **开源生态**：感谢 OpenHarmony / HarmonyOS 开发者社区与 AMLL 歌词社区提供的开放文档与格式参考。
