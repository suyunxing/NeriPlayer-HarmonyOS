# NeriPlayer HarmonyOS 迁移工作区

本仓库用于研究并推进 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) 从 Android（Kotlin、Jetpack Compose、Media3）迁移到 HarmonyOS 6.0～7.0（ArkTS、ArkUI、Stage 模型）。它目前是迁移工作区，不是已完成的 HarmonyOS 发布版本。

## 当前结论

- Android 快照包含完整产品的大部分源码：`app/src/main` 约 634 个 Kotlin 文件、17.2 万行；另有约 285 个本地测试和 25 个设备测试。
- `NeriPlayer-HarmonyOS` 是可构建过的 ArkTS 原型，约 56 个 ArkTS 文件、7,142 行。已有页面、数据模型、网络和播放骨架，但与 Android 产品的功能、测试和异常处理规模仍有显著差距。
- `NeriPlayer-ASCF` 是元服务方向的独立试验。它不能替代普通 HarmonyOS 应用，尤其不适合作为本地媒体扫描、完整后台播放和 USB 独占能力的主迁移路线。
- 现有构建日志表明 ArkTS 原型曾于 2026-08-02 在 `6.1.1(24)` 配置下构建成功；当前机器配置指向已经不可访问的 `E:/DevEco Studio`，所以本次没有把历史日志当作可复现验证。
- 当前 Android 与 HarmonyOS 目录都是无 Git 元数据的文件快照。Android 快照基线已通过 GitHub blob SHA 交叉比对确认是上游 commit `d66d465f48a6ae911fef0de88d2d21937760f31d`（2026-07-31）；审计时上游最新 commit 已到 `bc4142bc9e9b0b88e27be8dbc19c85e548400709`（2026-08-12）。

## 目录角色

| 目录 | 角色 | 是否主线 |
| --- | --- | --- |
| `NeriPlayer-master/` | Android 上游源码快照与行为参照 | 参照基线 |
| `NeriPlayer-HarmonyOS/` | ArkTS / ArkUI 普通应用原型 | 是 |
| `NeriPlayer-ASCF/` | Atomic Service Compatible Framework 试验 | 否，保留作能力对照 |
| `ascf-support-plugin/` | 本机安装的第三方二进制工具 | 否，不进入 Git |
| `package/` | 本机解包的 ASCF 接口包 | 否，不进入 Git |
| `docs/` | 审计、功能矩阵与迁移路线图 | 是 |

## 从这里开始

1. 阅读 [项目审计](docs/PROJECT_AUDIT.md)，了解哪些结论已验证、哪些仍需复核。
2. 阅读 [功能迁移矩阵](docs/FEATURE_MATRIX.md)，按能力域核对 Android 与 ArkTS 的差距。
3. 按 [HarmonyOS 6.0～7.0 迁移路线图](docs/HARMONYOS_PORTING_PLAN.md) 推进垂直切片。
4. 安装与目标版本匹配的 DevEco Studio/SDK 后，修正 `NeriPlayer-HarmonyOS/local.properties`，再执行干净构建和测试。

## 版本与资料原则

- 当前可确认的工程配置是 HarmonyOS `6.1.1(24)`；HarmonyOS 6.0 与 7.0 的准确 SDK/API 映射必须以 DevEco Studio SDK Manager 和[华为开发者官方文档](https://developer.huawei.com/consumer/cn/doc/)为准。
- 每次同步 Android 上游时记录 commit SHA、同步日期、许可证和子模块状态；不要仅覆盖 `NeriPlayer-master` 文件夹。
- 在线媒体接口只作为适配器实现，并遵守第三方平台条款、账号授权、版权与应用市场审核要求。

## 许可证

原项目采用 GPL-3.0；本工作区中由原项目衍生的移植代码应继续遵守 GPL-3.0。原始许可证见 `NeriPlayer-master/LICENSE`。
