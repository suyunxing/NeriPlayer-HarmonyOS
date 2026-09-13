---
name: harmonyos-code-review
description: 审查 NeriPlayer HarmonyOS 仓库的 Pull Request 时使用。覆盖 ArkTS 严格模式、页面/业务分层、API 26 兼容性、下载/播放/同步高风险回归区、数据 schema 与稳定歌曲键兼容、日志与提交内容安全红线。Use when reviewing pull requests in this HarmonyOS (ArkTS/ArkUI) codebase.
---

# NeriPlayer HarmonyOS 代码审查清单

本仓库是 NeriPlayer 从 Android (Kotlin) 迁移到 HarmonyOS 的音乐播放器，主线实现位于 `NeriPlayer-HarmonyOS/`，行为参照是只读快照 `NeriPlayer-master/`。仓库根目录 `AGENTS.md` 是完整项目约定（以其为准），本清单是审查 PR 时的重点核对项。

## 1. 影响范围与只读区

- 改动应只落在主线工程 `NeriPlayer-HarmonyOS/`（或任务明确涉及的 `docs/`）。
- `NeriPlayer-master/`（Android 参照快照）、`NeriPlayer-ASCF/`、`ascf-support-plugin/`、`package/` 为只读/实验区：PR 中出现这些目录的改动而描述未说明理由时，标记为问题。
- 无关格式化、目录重排、依赖升级不应混入功能 PR。

## 2. ArkTS 严格模式

- 禁止 `any`、禁止无说明的类型绕过（滥用 `as` 断言）、禁止依赖隐式转换；参数、返回值、集合必须有明确类型。
- 异步 I/O 用 `Promise`/`async`/`await`；错误处理必须保留可诊断上下文，不允许空 `catch` 吞错。
- 资源释放：文件句柄、HTTP 请求、监听器、计时器在成功与失败路径（含 early return / throw 分支）都要释放。
- 面向用户的文案与颜色必须放入 `entry/src/main/resources/`，不允许在多个页面硬编码重复字符串。

## 3. 架构分层

- 页面（`view/`）只负责渲染状态与派发用户意图；播放、下载、同步、解析、持久化逻辑不得依赖页面生命周期，不得把业务状态机堆进页面文件。
- 新增代码放入职责最接近的目录：`app/`、`model/`、`data/`、`download/`、`network/`、`player/`、`lyrics/`、`listentogether/`、`sync/`、`util/`、`view/`。
- 第三方音乐平台必须经 `network/` 适配器封装，并区分网络、鉴权、限流、受限内容、解析、平台策略错误；不允许在 UI 层直连第三方接口。

## 4. 兼容性关键点（高严重度）

- `SongIdentity.ets` 的稳定歌曲键格式为 `<id>|<album>|<mediaUri>`：任何改变其语义、拼接或解析行为的改动都是阻断性问题，除非 PR 同时提供迁移方案、跨端 fixture 与回归测试。
- 持久化与跨端同步数据（设置/历史/统计/歌单/下载记录）必须有 schema/版本策略；读取旧格式再写新格式时不得静默丢弃字段；发现"直接覆盖旧数据"的写法要标记。
- 队列、随机/循环、播放恢复、下载恢复、冲突合并应实现为可确定测试的状态机，而不是分散的 UI 条件分支。
- HarmonyOS API/Kit/权限不得凭记忆推断可用性：新 API 需与工程基线 API 26（SDK 26.0.0）匹配，并提供兼容检测或降级路径；`module.json5` 权限变更必须同步检查用户提示与拒绝授权路径。

## 5. 高风险回归区（近期多次出问题，重点看）

- 下载引擎（`download/`）：任务状态机、分块写入偏移与完整性校验、原子提交、断点恢复；失败重试是否可能形成重试风暴或写坏文件。
- 播放链路（`player/`）：本地源（`fdSrc`）与网络源切换、AVSession/后台播放生命周期、播放失败后的重试逻辑。
- 同步（`sync/`）：合并策略与冲突处理是否会丢用户数据。

## 6. 安全红线（出现即阻断）

- 代码、日志、注释或测试中不得出现：密钥、签名材料、口令、Cookie、Token、设备 UDID、用户文件完整路径、机器绝对路径；日志涉及敏感信息时必须脱敏。
- 不得提交 `local.properties`、`signing/`、`oh_modules/`、`.hvigor/`、`build/`、HAP/APK、日志等生成物。
- 复制或改写 Android 上游（GPL-3.0）代码时需保留许可证与来源说明。

## 7. 测试与验证期望

- 纯模型/解析/队列/数据逻辑改动：应包含或更新 `entry/src/test/` 的确定性单元测试。
- Ability、权限、AVPlayer、AVSession、后台播放改动：应说明设备侧（`entry/src/ohosTest/`/真机）验证计划；若 PR 声明"未验证"，提醒遗留风险而不是当作已通过。
- 数据格式迁移：检查是否用旧版本 fixture 验证了读取→升级→再读取，以及异常终止和损坏数据路径。

## 8. 评审输出要求

- 用中文评论；问题按严重度标注（阻断 / 建议 / 疑问）。
- 指出问题时给出具体文件与行级修改建议。
- 涉及 Android 上游行为对照时，可参考 `NeriPlayer-master/` 中的同名实现核对行为差异，但不要要求逐行翻译 Kotlin。
