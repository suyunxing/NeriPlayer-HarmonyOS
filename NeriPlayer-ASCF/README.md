# NeriPlayer-ASCF

> **状态说明（2026-08-12）：** 本目录是元服务方向的历史试验，不是 ArkTS 普通应用主线，也未在本次环境中重新构建验证。能力描述表示已有代码路径，不代表发布质量或与 Android 版本功能等价。

[cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)（Android 原生音乐播放器）的 **HarmonyOS 元服务（Atomic Service）** 移植版。

本工程基于 **ASCF（Atomic Service Compatible Framework）1.0.4.306 插件 + ASCF Toolkit 1.0.17** 构建，
UI 层采用 ASCF 小应用范式（`hxml / js / css / json`），底层通过 `has.getBackgroundAudioManager()` 等 ASCF 框架 API
实现全局背景音频播放。

## 工程结构

```
NeriPlayer-ASCF/
├── AppScope/                  # 元服务应用配置（bundleType: atomicService）
├── ascf/ascf_src/             # ASCF 小应用源码（全部 UI 与业务逻辑）
│   ├── app.json               # 页面路由 + tabBar
│   ├── common/                # 业务逻辑（播放器/网络/加密/歌词/数据仓库）
│   ├── components/            # 自定义组件（迷你播放器/歌曲行/空态）
│   └── pages/                 # 页面
├── entry/                     # eTS 壳工程（AscfUIAbility 承载小应用）
└── hvigor/                    # 构建配置（ASCF toolkit hvigor 插件）
```

## 已实现功能

- 首页：问候语、搜索入口、最近播放
- 探索：网易云 / 哔哩哔哩 / YouTube Music 三平台搜索与播放
- 网易云：weapi 签名（纯 JS AES-128-CBC + RSA-1024 PKCS#1，无需外部库）、歌曲地址（多音质回退）、歌词（含翻译）、歌单搜索与歌单详情
- 哔哩哔哩：搜索 + DASH 音频流解析
- 播放器：队列播放、随机、单曲/列表循环、失败重试后自动切歌、后台音频（`getBackgroundAudioManager`）、进度拖动
- 曲库：播放列表（新建/添加/移除/删除）、播放历史、常听统计、下载记录
- 设置：默认平台、音质、播放速度（实验性）、历史/统计开关、免责声明、调试信息
- 首次启动：免责声明 → 平台引导

## 构建

环境要求：

- DevEco Studio 6.1.1 Release（HarmonyOS SDK）
- ASCF Support 插件 1.0.4.x
- 网络可访问 `repo.harmonyos.com/ohpm`（安装 `@atomicservice/ascfapi`）与 npm registry（安装 ASCF toolkit）

```bash
# 1. 配置 SDK（与 DevEco 一致）
#    在 local.properties 中写入 sdk.dir=E:/DevEco Studio/sdk/default

# 2. 安装 ohpm 依赖
ohpm install --registry https://repo.harmonyos.com/ohpm/

# 3. 构建 HAP
hvigorw.bat assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

也可直接用 DevEco Studio 打开工程，Sync 后 Run。首次 Sync 时 hvigor 会自动从 npm 下载
`@atomicservice/ascf-toolkit-hvigor-plugin` 及其依赖（约 800+ 个包，耗时较长）。

## 平台限制说明

- **本地音乐扫描**：元服务受系统能力限制，无法直接读取手机媒体库。`READ_AUDIO` 属于受限 ACL 权限，
  本版以「下载管理 + 网络播放」替代本地扫描。
- **YouTube Music 播放**：`resolveStream` 需要 YouTube 签名/`n` 参数解密与 EJS 引擎，本版仅实现搜索，
  流解析标记为待移植（见 `PORTING.md`）。
- **播放速度**：ASCF 的 `BackgroundAudioManager` 未暴露 `playbackRate`，速度设置当前仅持久化，实际变速需要
  换用 `InnerAudioContext`（前台播放）或等待框架支持。
- **请求域名**：若发布到应用市场，需要在 AGC 侧配置 request/download 合法域名（music.163.com、
  api.bilibili.com、music.youtube.com、lrclib.net 等）。

## 免责声明

本项目为开源学习项目，不提供任何音乐内容；歌曲/歌词/封面来自第三方平台公开接口，版权归原作者所有。
