# NeriPlayer HarmonyOS — Copilot 自定义说明

本仓库是 NeriPlayer 从 Android 迁移到 HarmonyOS 的实现仓库，主线代码在 `NeriPlayer-HarmonyOS/`（ArkTS / ArkUI / Stage 模型）。

生成与审查代码时：

- 仓库根目录 `AGENTS.md` 是权威项目约定（目录职责、兼容性关键点、安全红线、验证要求）；与其冲突的改动应标记为问题。
- 审查 PR 时请应用 `harmonyos-code-review` skill（`.github/skills/harmonyos-code-review/SKILL.md`）中的审查清单。
- ArkTS 代码（`**/*.ets`）的专项规则见 `.github/instructions/arkts.instructions.md`；GitHub Actions 工作流的规则见 `.github/instructions/ci-workflows.instructions.md`。
- 评论与提交信息使用中文；提交信息格式为 `<类型>: <中文简述>`（feat/fix/docs/refactor/chore/test）。
- 工程基线为 HarmonyOS API 26（SDK 26.0.0，`compatibleSdkVersion: "26.0.0"`，版本号不带 `(26)` 括号后缀）；不要建议仅在更高 API 上可用的写法，除非同时给出降级路径。
