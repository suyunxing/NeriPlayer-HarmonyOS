---
applyTo: ".github/workflows/*.yml"
---

# GitHub Actions 工作流专项规则

- 发布红线：Release 产物永远是 unsigned HAP；签名材料、口令、设备 UDID 不得进入 workflow、缓存或 Secrets（含 `COPILOT_MCP_` 前缀之外的任何凭据注入）。出现即阻断。
- CI 工具链必须与工程 API 26 基线一致（`ErBWs/setup-ohos@v2` 的 version 使用 `26.0.0.821` 或更新的 26.x）；低于 26.0.0.821 会在 hvigor 配置校验报 00306042。
- 发布流水线写入 `AppScope/app.json5` 的规则：`versionName` = tag 去掉 `v` 前缀；`versionCode` = 三段乘权（如 1.0.1 → 1000001）。
- 不引入 AGC 正式发布证书；打正式 tag 属于须用户明确要求的操作，workflow 不应自动创建正式版本 tag。
- 测试验证用 `-rc` 后缀 tag，且 workflow 不应留下需要手工清理的产物。
