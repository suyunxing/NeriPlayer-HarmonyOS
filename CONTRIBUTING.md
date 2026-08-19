# 贡献指南

NeriPlayer 是 Android 到 HarmonyOS 的迁移工作区。日常开发以 `NeriPlayer-HarmonyOS/` 为主线，`NeriPlayer-master/` 只用于行为、协议、数据格式和测试语义对照；除非 Issue 明确要求，不要修改 Android 快照、ASCF 实验或本机工具目录。

## 分支与 Pull Request

- 目标分支模型是：`main` 保存可运行、可回退的稳定版本；`dev` 是双方日常集成与测试主线；个人分支和 `feature/*`、`fix/*`、`test/*` 分支通过 Pull Request 汇入 `dev`。
- 当前远端默认分支仍是 `su`。CI 在 push 到 `main`、`dev` 时运行，并检查目标为 `main`、`dev`、`su` 的 PR；直接 push 到 `su` 不触发。建立并保护 `main` 后，应把默认分支切换到 `main`，日常 PR 仍以 `dev` 为目标。
- 新功能、修复和文档从最新 `dev` 创建短分支，例如 `feature/lyrics-empty-state`、`fix/bili-playback`、`docs/ci-workflow`。两位开发者不要长期共用同一功能分支。
- `dev -> main` 只用于已经通过 CI、人工 smoke test 和双方 review 的稳定晋级；不要把普通功能分支直接合入 `main`。
- 两个已经独立开发较久的分支不要直接自动 merge。先打快照 tag、列出功能差异和高风险共享文件，再在 `integration/*` 分支逐项吸收；完整流程见 [GitHub 协作与分支整合](docs/GITHUB_COLLABORATION.md)。
- 一个 PR 聚焦一个可审查目标。涉及多个功能域时拆分 PR，或在描述中明确依赖关系。
- 标题沿用现有约定，使用 `feat:`, `fix:`, `test:`, `docs:`, `ci:` 或 `refactor:` 等前缀；标题简明说明结果，不写实现流水账。
- PR 描述必须说明变更范围、验证命令、未执行的验证和剩余风险。UI、权限、后台播放、第三方接口和持久化变更要特别说明兼容性影响。

## 本地验证

在 `NeriPlayer-HarmonyOS/` 执行与改动相匹配的检查：

```powershell
$cli = 'D:\HarmonyOS\Tools\command-line-tools\bin'
& "$cli\ohpm.bat" install --all
& "$cli\hvigorw.bat" test --mode module -p product=default -p buildMode=debug --no-daemon
& "$cli\hvigorw.bat" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

纯逻辑优先补 `entry/src/test/`；涉及 Ability、权限、AVPlayer、AVSession、后台播放或系统 UI 时补 `entry/src/ohosTest/`，并在设备或模拟器上执行对应 smoke test。提交前从仓库根目录运行 `git diff --check`。

Linux GitHub Runner 上的 hypium 本地 runner 当前存在已记录的挂死问题。CI 会先构建并上传 debug HAP，再将单测限制在 4 分钟作为诊断运行；单测超时或退出不会阻塞构建，也不等价于单测通过。PR 必须如实填写本地结果和 HAP 构建结果。

## 数据与安全

- 不提交签名材料、口令、Token、Cookie、设备 UDID、用户数据、日志、HAP/APK 或机器绝对路径。
- 改动持久化数据或跨端同步格式时，提供 schema/版本策略和旧数据 fixture，禁止静默丢弃用户数据。
- 第三方媒体接口改动必须保留错误分类、降级路径和必要的脱敏日志，并遵守服务条款、账号授权和版权要求。
- 复制或改写 Android 上游代码时保留 GPL-3.0 许可和来源说明。

## Review 关注点

审查优先关注行为回归、失败路径、数据兼容性、权限与后台生命周期、网络鉴权和测试证据。历史文档中的“已完成”不能替代当前可重复的构建或设备验证。
