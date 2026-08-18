# GitHub 协作与分支整合

本文针对 NeriPlayer 从 Android 迁移到 HarmonyOS 的双人并行开发。目标不是让 Git 自动“选出正确代码”，而是让每次整合都有基准、审查、验证和回退点。

## 分支职责

| 分支 | 职责 | 合并规则 |
| --- | --- | --- |
| `main` | 已验证、可回退的稳定版本 | 只接受从 `dev` 发起的晋级 PR |
| `dev` | 双方日常开发的集成主线 | 只接受个人/功能/integration 分支 PR |
| `feature/*`、`fix/*`、`test/*` | 一个功能或问题的短期工作分支 | 完成 review 和验证后合入 `dev` |
| `integration/*` | 两个已有实现的差异分析与逐项吸收 | 只在分析完成后发 PR 到 `dev` |
| `su` | 当前迁移期已有开发线 | 暂时保留 CI；不要把它当长期协作主线 |

当前远端默认分支仍为 `su`。在 `main` 建立并完成保护前，继续使用 `su` 的现有代码；不要为了改变分支名称而强行重写历史。

## 两个已有实现的整合

### 1. 固定基准和回退点

双方先同步远端信息，并记录各自分支的 commit SHA：

```powershell
git fetch origin --prune
git log --oneline --decorate --all -20
git status --short
```

在双方分支上分别创建快照 tag。tag 名称应包含来源和日期，例如 `snapshot/su-2026-08-18`、`snapshot/friend-2026-08-18`。不要在没有记录 SHA 的情况下开始大规模整合。

### 2. 先做只读差异分析

假设 `dev` 是基准，`friend-port` 是待吸收分支：

```powershell
git log --left-right --cherry-pick --oneline dev...friend-port
git diff --stat dev...friend-port
git diff --name-status dev...friend-port
git diff --name-only dev...friend-port
```

先按功能整理结果，而不是按文件数量做结论：

- 双方都修改的构建、权限、生命周期、播放器、数据格式和网络鉴权文件属于高风险区。
- 只有一方新增且边界清楚的模型、适配器或测试通常可以单独吸收。
- Android 参照代码不能覆盖 `NeriPlayer-HarmonyOS/` 的 ArkTS/ArkUI 架构；冲突解决要以当前 HarmonyOS 行为、API 24 基线和可重复测试为准。

### 3. 在第三个分支整合

不要直接在 `dev`、`main` 或任一开发者分支上解决大型冲突：

```powershell
git switch dev
git pull --ff-only origin dev
git switch -c integration/friend-port
```

如果待吸收分支的提交边界清楚，可以在 `integration/friend-port` 上逐个 `git cherry-pick -x <commit>`；如果两个版本已经产生大面积设计差异，应按功能手工迁移，并为每个功能单独提交。不要用一次 `merge` 覆盖数百个文件后再猜测哪些行为丢失。

每完成一个功能，先运行对应的本地单测或 HAP 构建，再继续下一个功能。构建、权限、后台播放、AVPlayer、持久化和第三方网络接口变更必须记录失败路径和未验证项。

### 4. 让 Agent 做分析和迁移，而不是盲目选 ours/theirs

推荐的第一轮请求是只读分析：

> 比较 `dev` 与 `<source-branch>` 的提交、文件和功能差异。输出双方都修改的高风险文件、只在一方存在的功能、可能丢失的行为、测试缺口和拆分 PR 方案。不要修改文件、不要解决冲突、不要选择 ours/theirs。

确认分析报告后，再让 Agent 执行：

> 当前 `integration/*` 分支以 `NeriPlayer-HarmonyOS/` 的现有 ArkTS/ArkUI 架构为基准。请按已确认的功能清单逐项吸收 `<source-branch>` 的有效改动，保留必要的错误处理、降级路径和测试；遇到设计冲突先停止并列出取舍，不要机械选择 ours/theirs。完成后运行对应构建/测试并输出迁移报告。

Agent 生成的“已解决冲突”不等于行为正确。至少由另一位开发者检查启动、导航、权限、网络、文件读写、播放、后台生命周期和数据兼容性。

## 日常 PR 流程

```text
feature/fix/test branch
          |
          | PR + review + CI
          v
         dev
          |
          | 人工 smoke test + 稳定性检查
          v
         main
```

PR 必须说明：变更范围、关联 Issue、实际执行的命令、未执行的验证、已知风险以及是否影响权限、持久化、第三方接口或签名。大型整合使用 `integration/*` 到 `dev` 的多个小 PR，不使用一个“解决全部冲突”的黑盒 PR。

## GitHub 网页端设置

以下是仓库管理员需要在 GitHub 上完成的远端设置，本地文件无法替代这些设置：

1. 邀请朋友进入仓库，权限至少为 Write；不要共享个人 Token。
2. 建立 `main` 后，将默认分支切换到 `main`；保留 `dev` 作为开发分支。
3. 为 `main` 创建 ruleset：禁止直接 push、禁止 force push 和删除；必须通过 PR、至少 1 位另一位开发者批准，并要求 `HarmonyOS CI / build & test (API 24)` 成功。
4. 为 `dev` 创建较轻的 ruleset：必须通过 PR 和 CI；整合 PR 至少 1 位开发者 review。两人协作时不要允许作者自己批准自己的 PR。
5. 创建 GitHub Project，至少包含 `Todo`、`Doing`、`Review`、`Done`；Issue 用于任务，PR 用于代码变更。
6. 建议统一标签：`type: bug`、`type: feature`、`type: integration`、`area: ui`、`area: player`、`area: network`、`area: data`、`area: ci`、`status: needs-review`。

当前环境没有可用的 GitHub CLI 或连接器，因此本轮只修改了仓库内可版本化的配置和文档，没有替你创建远端分支、ruleset、Project、标签或推送提交。

## 完成整合的判定

只有同时满足以下条件，才把 `dev` 晋级到 `main`：

- 所有待吸收功能都有对应提交、PR 或明确的“不迁移”结论。
- 高风险共享文件经过人工 review，没有用 ours/theirs 掩盖设计冲突。
- HarmonyOS 主线 debug HAP 构建成功，相关本地单测通过。
- 涉及 Ability、权限、AVPlayer、AVSession、后台播放或系统 UI 的改动完成设备/模拟器 smoke test，或明确记录未验证原因。
- 旧数据、错误路径、第三方接口降级和敏感信息检查均有证据。
- `git diff --check` 通过，且保留可回退的快照 tag。
