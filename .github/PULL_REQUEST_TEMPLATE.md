## 变更目的

<!-- 说明这次变更解决的问题，以及为什么需要在 HarmonyOS 主线处理。 -->

## 变更范围

- [ ] `NeriPlayer-HarmonyOS/` 主线实现
- [ ] `.github/` 或仓库协作配置
- [ ] `docs/` 文档或迁移记录
- [ ] 其他（请说明）：

<!-- `NeriPlayer-master/` 是 Android 参照快照。除非任务明确要求，不要把它作为本 PR 的改动范围。 -->

## 目标分支

- [ ] `dev`：功能、修复、测试或文档的日常集成
- [ ] `main`：已经在 `dev` 验证后的稳定版本晋级
- [ ] `su`：迁移期兼容或维护变更（请说明不能先进入 `dev` 的原因）

<!-- 不要把大型独立实现直接合入 main；先在 integration/* 分支分析并拆成可验证的 PR。 -->

## 关联 Issue

<!-- 使用 Closes #123、Fixes #123 或 Related #123；没有可留空。 -->

## 验证结果

<!-- 写明实际执行的命令和结果，不要只写“已测试”。 -->

- [ ] `ohpm install --all`
- [ ] `hvigorw test --mode module -p product=default -p buildMode=debug --no-daemon`
- [ ] `hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon`
- [ ] 相关 `ohosTest`、设备或模拟器 smoke test（如适用）
- [ ] `git diff --check`

## 审查清单

- [ ] 页面变更已考虑 phone/tablet/横竖屏和返回栈（如适用）
- [ ] 数据格式、权限、后台播放或第三方接口变更已同步文档和测试（如适用）
- [ ] 未提交密钥、Token、Cookie、设备 UDID、签名材料、日志或机器绝对路径
- [ ] 用户可见行为变更已更新相关 README 或迁移文档
- [ ] UI 变更已附截图或录屏，并已脱敏（如适用）

## 其他说明

<!-- 记录已知限制、未执行的验证、兼容性风险或需要 reviewer 重点关注的代码路径。 -->
