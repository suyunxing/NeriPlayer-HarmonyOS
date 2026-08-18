# NeriPlayer for HarmonyOS (鸿蒙原生移植)

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
<!--
- ⏳ 待移植：YouTube 取流（EJS 引擎）、下载管线、GitHub/WebDAV 同步、一起听、USB 独占、悬浮歌词、动态取色 —— 详见 [PORTING.md](./PORTING.md)
-->
- ✅ **下载管线**：Range 断点续传、并发队列、暂停/恢复/重试、启动恢复、歌词 sidecar、离线播放（应用沙箱）
<!--
- ⏳ 待移植：YouTube 取流（EJS 引擎）、GitHub/WebDAV 同步、一起听、USB 独占、悬浮歌词、动态取色、下载目录选择 —— 详见 [PORTING.md](./PORTING.md)
-->
- ✅ **动态取色**：当前歌曲封面取色，应用于播放页歌词高亮与滑杆
- ⏳ 待移植：YouTube 取流（EJS 引擎）、GitHub/WebDAV 同步、一起听、USB 独占、悬浮歌词、壁纸取色、下载目录选择 —— 详见 [PORTING.md](./PORTING.md)

## 环境与构建

1. 安装 **DevEco Studio 6.1.1 Release**（API 24 SDK），本机版本 6.1.1.300。
2. `File → Open` 打开本目录，等待 ohpm 同步。
3. 命令行调试可直接运行：

```powershell
.\sign-local.ps1        # 构建 + OpenHarmony 调试签名 + hdc 安装到模拟器
```

4. 真机/模拟器首次启动完成免责声明与引导；本地音乐扫描需 `READ_AUDIO` 权限；后台播放需保持 `KEEP_BACKGROUND_RUNNING` 授权。

> 说明：DevEco Studio 6.1.1 的 `build-profile.json5` 不再支持明文签名口令，工程默认不配置签名；`sign-local.ps1` 使用 SDK 自带 OpenHarmony 调试证书完成本地签名安装，适合开发调试。发布到应用市场前请改用 AGC 签名配置。

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
├── download/         下载队列、Range 续传、沙箱落盘、sidecar
├── lyrics/           LRC 解析器
└── view/             页面与组件（首页/探索/资料库/设置/正在播放/调试）
```

## 许可

GPL-3.0。原项目：https://github.com/cwuom/NeriPlayer
