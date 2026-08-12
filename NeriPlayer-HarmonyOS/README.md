# NeriPlayer for HarmonyOS (鸿蒙原生移植)

> **状态说明（2026-08-12）：** 本目录是历史 ArkTS 原型快照。它有 2026-08-02 的 API 24 构建成功日志，但本次环境未能重现；下方勾选项表示曾实现或验证过相应代码路径，不代表与当前 Android 上游功能等价、已完成自动化测试或已满足发布质量。统一审计请看仓库根目录的 `docs/PROJECT_AUDIT.md`。

**NeriPlayer（欢迎回来！）** 是一个把多源在线播放、本地管理、歌词体验和自建同步做进原生 Android 的音频播放器。本仓库将其**原封不动移植为 HarmonyOS NEXT 原生应用**：相同的功能定位、相同的启动流程、相同的多源架构，使用 ArkTS / ArkUI / AVPlayer 重新实现。

> 本项目仅供学习与研究使用，请勿用于任何非法用途。原项目为 GPL-3.0 许可，本移植同样遵循 GPL-3.0。

## 功能状态

- ✅ **多源在线播放**：网易云 / Bilibili / YouTube Music 搜索
- ✅ **播放核心**：队列、随机、循环、倍速、断点续播、AVSession 媒体控制、后台播放
- ✅ **网易云**：搜索（weapi 风控时自动回退旧版接口）、取流（多音质回退）、歌词（含翻译）、歌单详情
- ✅ **歌词**：LRC 解析、逐行高亮、点击跳转（LRCLIB + 网易云）
- ✅ **数据**：本地歌单、收藏、播放历史、播放统计（稳定歌曲身份，兼容原同步键格式）
- ✅ **设置持久化**：免责声明/引导/深色模式等跨进程重启保留
- ✅ **UI 全量移植**：首页（继续收听/最近播放/推荐歌单）、探索、资料库、设置（10 个分区 + 二级页）、正在播放（模糊封面/进度/速度/睡眠/队列/双语歌词）、下载管理、播放历史、播放统计、歌单详情、3 步引导、安全模式、调试页
- ✅ **启动流程**：Loading → 免责声明 → 引导（3 步）→ 主界面；崩溃安全模式
- ⏳ 待移植：YouTube 取流（EJS 引擎）、下载管线、GitHub/WebDAV 同步、一起听、USB 独占、悬浮歌词、动态取色 —— 详见 [PORTING.md](./PORTING.md)

## 环境与构建

1. 安装 **DevEco Studio 6.1.1 Release**（API 24 SDK），本机版本 6.1.1.300。
2. `File → Open` 打开本目录，等待 ohpm 同步。
3. 命令行调试可使用安全参数运行（签名材料放在已忽略的 `signing/` 中）：

```powershell
$env:DEVECO_STUDIO_HOME = "D:\path\to\DevEco Studio"
$env:DEVECO_SDK_HOME = "D:\path\to\DevEco Studio\sdk"
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
