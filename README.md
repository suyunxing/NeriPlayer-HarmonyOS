# NeriPlayer HarmonyOS 迁移工作区

本仓库用于研究并推进 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) 从 Android（Kotlin、Jetpack Compose、Media3）迁移到 HarmonyOS 6.0～7.0（ArkTS、ArkUI、Stage 模型）。它目前是迁移工作区，不是已完成的 HarmonyOS 发布版本。

## 当前结论

- Android 快照包含完整产品的大部分源码：`app/src/main` 约 634 个 Kotlin 文件、17.2 万行；另有约 285 个本地测试和 25 个设备测试。
- `NeriPlayer-HarmonyOS` 是可构建的 ArkTS 原型，`entry/src/main/ets` 下 239 个 ArkTS 文件、约 4.98 万行（2026-08-31 实测 49,834 行）。已有页面、数据模型、网络、播放、下载、同步、一起听与动态取色的核心链路，`entry/src/test/` 本地单元测试已随里程碑累积到 874 用例（2026-08-29 记录全绿），另有 `entry/src/ohosTest/` 设备测试；但与 Android 产品的功能与异常处理规模仍有显著差距，YouTube 完整取流、系统级桌面歌词渲染等仍受上游或平台限制，USB 独占已定案不移植（状态明细见 `docs/FEATURE_MATRIX.md`）。
- `NeriPlayer-ASCF` 是元服务方向的独立试验。它不能替代普通 HarmonyOS 应用，尤其不适合作为本地媒体扫描、完整后台播放和 USB 独占能力的主迁移路线。
- 2026-08-13 已在本机 6.1.1 Release 工具链完成可重复验证：依赖同步、干净构建、单元测试 3/3、调试签名、模拟器安装与冷启动 smoke test（记录见 `docs/hm.md` §7.4）。2026-08-14 工具链目录整体迁至 `D:\HarmonyOS\Tools\`，系统 PATH 与 `local.properties` 中的旧路径已按根目录 `AGENTS.md` 更新；下次构建前建议先按该文档复核环境。
- 工作区根目录已初始化 Git（基线提交 `ef89b16`，2026-08-12），三个子工程目录本身仍是无 `.git` 元数据的文件快照。Android 快照基线已通过 GitHub blob SHA 交叉比对确认是上游 commit `d66d465f48a6ae911fef0de88d2d21937760f31d`（2026-07-31）；审计时上游最新 commit 已到 `bc4142bc9e9b0b88e27be8dbc19c85e548400709`（2026-08-12）。

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
2. 阅读 [HarmonyOS 开发与迁移指南](docs/hm.md)，获取版本矩阵、构建命令与本机验证记录。
3. 阅读 [功能迁移矩阵](docs/FEATURE_MATRIX.md)，按能力域核对 Android 与 ArkTS 的差距。
4. 按 [HarmonyOS 6.0～7.0 迁移路线图](docs/HARMONYOS_PORTING_PLAN.md) 推进垂直切片。
5. 构建与验证的环境要求（工具链路径、签名脚本注意事项）见根目录 `AGENTS.md`。
6. 参与协作前阅读 [贡献指南](CONTRIBUTING.md) 和 [GitHub 协作与分支整合流程](docs/GITHUB_COLLABORATION.md)；提交 Issue 或 Pull Request 时使用仓库提供的模板。

## 版本与资料原则

- 工程配置基线为 HarmonyOS `26.0.0`（API 26，Release；2026-09-07 从 `6.1.1(24)` 全量迁移，版本号自 26.0.0 起改用纯 SemVer，不再带 `(26)` 括号后缀）。官方版本映射已于 2026-08-14 复核：HarmonyOS 6.0.0→API 20、6.0.1→21、6.0.2→22、6.1.0→23、6.1.1→24；HarmonyOS 7.0→开发套件 26.0.0（API 26）。`compatibleSdkVersion` 已抬至 26.0.0，26 以下设备不再可安装（迁移详情见 `docs/hm.md` §7.12）。以后仍以[华为开发者官方文档](https://developer.huawei.com/consumer/cn/doc/)的版本页为准。
- 每次同步 Android 上游时记录 commit SHA、同步日期、许可证和子模块状态；不要仅覆盖 `NeriPlayer-master` 文件夹。
- 在线媒体接口只作为适配器实现，并遵守第三方平台条款、账号授权、版权与应用市场审核要求。

## 许可证

原项目采用 GPL-3.0；本工作区中由原项目衍生的移植代码应继续遵守 GPL-3.0。原始许可证见 `NeriPlayer-master/LICENSE`。
