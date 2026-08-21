# NeriPlayer for HarmonyOS (鸿蒙原生移植)

> **状态说明（2026-08-19 更新）：** 本目录是持续开发中的 ArkTS 原型，不是已完成的 HarmonyOS 发布版本。当前 API 24 工具链已复跑本地单测 378/378、`entry@default` 与 `entry@ohosTest` 构建及 CodeLinter（0 error）；设备侧和真实第三方凭据写入仍按下文标注。下方勾选项表示已实现并有验证证据的代码路径，不代表与 Android 上游功能等价；未完成项在"待移植"中如实列出。统一审计请看仓库根目录的 `docs/PROJECT_AUDIT.md` 与 `docs/FEATURE_MATRIX.md`。

**NeriPlayer（欢迎回来！）** 是一个把多源在线播放、本地管理、歌词体验和自建同步做进原生 Android 的音频播放器。本仓库将其**原封不动移植为 HarmonyOS NEXT 原生应用**：相同的功能定位、相同的启动流程、相同的多源架构，使用 ArkTS / ArkUI / AVPlayer 重新实现。

> 本项目仅供学习与研究使用，请勿用于任何非法用途。原项目为 GPL-3.0 许可，本移植同样遵循 GPL-3.0。

## 功能状态

- ✅ **多源在线播放**：网易云 / Bilibili / YouTube Music 搜索
- ✅ **播放核心**：队列、随机、循环、倍速、断点续播、AVSession 媒体控制、后台播放
- ✅ **网易云**：搜索（weapi 风控时自动回退旧版接口）、取流（多音质回退）、歌词（含翻译）、歌单详情
- ✅ **歌词**：LRC 解析、逐行高亮、点击跳转（LRCLIB + 网易云）
- ✅ **数据**：本地歌单、收藏、播放历史、播放统计（稳定歌曲身份，兼容原同步键格式）
- ✅ **同步核心**：GitHub/WebDAV 三路合并、条件写回退、冲突重试、`.sync-pending` 消费和同步报告；真实 PAT/WebDAV 写路径与双设备冲突验收待完成
- ✅ **设置持久化**：免责声明/引导/深色模式等跨进程重启保留
- ✅ **UI 全量移植**：首页（继续收听/最近播放/推荐歌单）、探索、资料库、设置（10 个分区 + 二级页）、正在播放（模糊封面/进度/速度/睡眠/队列/双语歌词）、下载管理、播放历史、播放统计、歌单详情、3 步引导、安全模式、调试页
- ✅ **启动流程**：Loading → 免责声明 → 引导（3 步）→ 主界面；崩溃安全模式
- ✅ **ArkTS 单元测试**：`entry/src/test/` 覆盖队列状态机/睡眠定时/中断策略/加密/解析/下载/同步合并族等（hypium，2026-08-19 实测 378/378）

## 待移植（截至 2026-08-19）

以下项只有 UI 入口或占位实现，代码中均有明确标注（`YouTubeMusicApi.ets` 取流直接抛错、设置/调试页标注"待移植"），不得描述为已完成。明细见 `PORTING.md` 路线图与 `../docs/FEATURE_MATRIX.md`：

- ⏳ **YouTube 取流**：缺 signature/n 参数、PoToken 与 EJS 引擎，当前仅搜索可用（M6 未开始）
- ⏳ **同步验收**：真实 PAT/WebDAV 写路径、省流格式写出和双设备冲突验收待完成
- ⏳ **一起听**：WebSocket 房间协议待移植
- ⏳ **USB 独占播放**：需 NAPI C++（UAC1/UAC2），未开始
- ⏳ **悬浮歌词 / 动态取色与高级模糊**：引擎待实现
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
├── app/              常量与日志
├── model/            数据模型（歌曲/歌单/歌词/队列）
├── data/             设置/历史/歌单/统计/本地媒体
├── network/          三平台 API + 歌词 + 流解析（含 Cookie 会话）
├── player/           AVPlayer 播放核心 + AVSession + 后台任务
├── lyrics/           LRC 解析器
└── view/             页面与组件（首页/探索/资料库/设置/正在播放/调试）
```

## 许可

GPL-3.0。原项目：https://github.com/cwuom/NeriPlayer
