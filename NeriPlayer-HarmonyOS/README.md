# NeriPlayer for HarmonyOS (鸿蒙原生移植)

> **状态说明（2026-08-31 更新）：** 本目录是持续开发中的 ArkTS 原型，不是已完成的 HarmonyOS 发布版本。本地单测已随里程碑累积到 874 用例（2026-08-29 记录全绿，见 `../docs/FEATURE_MATRIX.md`）；`entry@default` 与 `entry@ohosTest` 构建及 CodeLinter（0 error）在各里程碑复跑。设备侧和真实第三方凭据写入仍按下文标注。下方勾选项表示已实现并有验证证据的代码路径，不代表与 Android 上游功能等价；未完成项在"待移植"中如实列出。统一审计请看仓库根目录的 `docs/PROJECT_AUDIT.md` 与 `docs/FEATURE_MATRIX.md`。

**NeriPlayer（欢迎回来！）** 是一个把多源在线播放、本地管理、歌词体验和自建同步做进原生 Android 的音频播放器。本仓库将其**原封不动移植为 HarmonyOS NEXT 原生应用**：相同的功能定位、相同的启动流程、相同的多源架构，使用 ArkTS / ArkUI / AVPlayer 重新实现。

> 本项目仅供学习与研究使用，请勿用于任何非法用途。原项目为 GPL-3.0 许可，本移植同样遵循 GPL-3.0。

## 功能状态

- ✅ **多源在线播放**：网易云 / Bilibili / YouTube Music 搜索
- ✅ **播放核心**：队列、随机、循环、倍速、断点续播、AVSession 媒体控制、后台播放
- ✅ **网易云**：搜索（weapi 风控时自动回退旧版接口）、取流（多音质回退）、歌词（含翻译）、歌单详情
- ✅ **歌词**：LRC 解析、逐行高亮、点击跳转（LRCLIB + 网易云）
- ✅ **数据**：本地歌单、收藏、播放历史、播放统计（稳定歌曲身份，兼容原同步键格式）
- ✅ **同步核心**：GitHub/WebDAV 三路合并、条件写回退、冲突重试、`.sync-pending` 消费和同步报告；双实例 WebDAV 冲突验收已于 2026-08-22 经本地自建服务器通过（M5.6），真实云 PAT/WebDAV 写路径与省流格式写出（现降级 JSON）待复核
- ✅ **下载管线**：DIRECT Range/If-Range 续传、HLS checkpoint、重试退避、原子提交、启动恢复与离线播放短路（2026-08-16 全链模拟器实测）
- ✅ **一起听**：建房/加入/同步播放/断线重连/邀请分享核心链路（2026-08-22 双模拟器实例设备闭环，M7.5）；三项房间设置开关等增强项未做
- ✅ **动态取色/背景视觉**：封面 Palette 取色 + Theme 覆盖层 + 播放页 accent 背景与模糊强度/crossfade（2026-08-23 设备实证；AGSL 区域掩码玻璃无平台对应，按 D 级降级）
- ✅ **设置持久化**：免责声明/引导/深色模式等跨进程重启保留
- ✅ **UI 全量移植**：首页（继续收听/最近播放/推荐歌单）、探索、资料库、设置（10 个分区 + 二级页）、正在播放（模糊封面/进度/速度/睡眠/队列/双语歌词）、下载管理、播放历史、播放统计、歌单详情、3 步引导、安全模式、调试页
- ✅ **启动流程**：Loading → 免责声明 → 引导（3 步）→ 主界面；崩溃安全模式
- ✅ **ArkTS 单元测试**：`entry/src/test/` 覆盖队列状态机/睡眠定时/中断策略/加密/解析/下载/同步合并族等（hypium，2026-08-29 记录 874/874，见 `../docs/FEATURE_MATRIX.md`）

## 待移植（截至 2026-08-31）

以下项只有部分链路、UI 入口或占位实现，代码中均有明确标注（如设置页目录选择/更多语言/YouTube 登录三处占位只弹 toast），不得描述为已完成。状态明细见 `../docs/FEATURE_MATRIX.md`（任务级看板见 `../docs/PORTING_EXECUTION_PLAN.md`）：

- ⏳ **YouTube 取流**：搜索与匿名 IOS 直连取流已落地（M6.1/M6.2）；设备实测匿名直链仅整轨前约一分钟可播（M6.5），生产播放链路未接环回桥，完整取流仍需 PoToken/JS 运行时（M6.3 未开始）
- ⏳ **同步验收**：真实云 PAT/WebDAV 写路径与省流格式写出（现降级 JSON）待复核；双设备冲突验收已过本地自建服务器（见上文"同步核心"）
- 🚫 **USB 独占播放**：已定案**不移植**（M9.1 spike，2026-08-24，`../docs/USB_M91_SPIKE.md`）——ArkTS 单 JS 线程守不住 1ms 等时节拍、SDK 无公开 USB DDK 头；系统路径下 AVPlayer→USB Audio HAL 已能出声
- ⏳ **悬浮歌词**：应用内悬浮条（`np.floating_lyric`）与 AVSession 正规歌词字段已落地（M8.6/M10.1）；系统级桌面歌词 API 已验证到服务层，渲染层待真机确认（M10.2，`../docs/DESKTOP_LYRIC_M102_SPIKE.md`）
- ⏳ **YouTube 登录**：网易云 / Bilibili QR 登录与凭据存储已完成（2026-08-17），YouTube 登录待 M6.4

## 环境与构建

1. 工程基线为 **HarmonyOS 6.1.1 Release（API 24）**。本机工具链位于 `D:\HarmonyOS\Tools\`：API 24 SDK 与 `ohpm`/`hvigorw` 命令行工具在 `command-line-tools\`，DevEco Studio 26.0.0.621（Beta2）为主力 IDE。完整环境说明见仓库根目录 `AGENTS.md`。
2. `File → Open` 打开本目录，等待 ohpm 同步。
3. 命令行调试签名（签名材料放在已忽略的 `signing/` 中；需按 `AGENTS.md` 同时设置 `DEVECO_SDK_HOME` 与 `DEVECO_STUDIO_HOME`，脚本依赖 Studio 布局中的 jbr 与 hvigor）：

```powershell
$env:DEVECO_SDK_HOME = "D:\HarmonyOS\Tools\command-line-tools\sdk"
$env:DEVECO_STUDIO_HOME = "D:\HarmonyOS\Tools\devecostudio-windows-26.0.0.621\DevEco Studio"
$env:NERIPLAYER_DEVICE_IDS = "真实设备UDID"
$env:NERIPLAYER_SIGNING_PASSWORD = "至少32位的本地调试口令"
.\sign-local.ps1        # 构建 + OpenHarmony 调试签名 + hdc 安装
```

4. 真机/模拟器首次启动完成免责声明与引导；本地音乐扫描需 `READ_AUDIO` 权限；后台播放需保持 `KEEP_BACKGROUND_RUNNING` 授权。

> 说明：工程不保存签名口令、设备 UDID 或机器绝对路径；`sign-local.ps1` 只用于本地调试。发布到应用市场前请使用 AGC 的正式签名流程。

## 项目结构

```text
entry/src/main/ets/
├── entryability/     EntryAbility（启动、窗口、主题）
├── pages/Index.ets   启动状态机
├── app/              常量、日志与崩溃诊断
├── model/            数据模型（歌曲/歌单/歌词/队列）
├── data/             设置/历史/歌单/统计/本地媒体
├── download/         下载引擎（传输/断点恢复/编目）
├── network/          三平台 API + 歌词 + 流解析（含 Cookie 会话）
├── player/           AVPlayer 播放核心 + AVSession + 后台任务
├── lyrics/           LRC/TTML 解析与歌词分发
├── listentogether/   一起听（协议/会话/播放同步）
├── sync/             GitHub/WebDAV 三路合并同步
├── util/             通用工具（QR 编码/断点与窗口度量等）
└── view/             页面与组件（首页/探索/资料库/设置/正在播放/调试）
```

## 许可

GPL-3.0。原项目：https://github.com/cwuom/NeriPlayer
