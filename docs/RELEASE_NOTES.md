# NeriPlayer HarmonyOS 更新说明（M11 视图层质量）

> 日期：2026-08-26 · 分支：`ch` · 交付：M11.1 视图层缺陷清零 + M11.2 歌词视图对齐
> 详细审查报告见 [docs/UI_REVIEW_M11.md](UI_REVIEW_M11.md)；任务看板见 [docs/PORTING_EXECUTION_PLAN.md](PORTING_EXECUTION_PLAN.md) §6；功能状态见 [docs/FEATURE_MATRIX.md](FEATURE_MATRIX.md)。

## 本次交付

### 1. 视图层缺陷清零（M11.1）

- **冷启动深色模式修复**：`EntryAbility` 以 `context.config.colorMode` 播种 `systemDark`；`Index` 移除会把真值打回浅色的重复覆写，并补发 `refreshIsDark()`。
- **主题切换即时重绘**：新增单一派生键 `theme.isDark` + `Theme.refreshIsDark()`，24 个视图文件 / 440 处调用改为 `@StorageProp` 直读 `this.isDark`，消除 ArkUI 最小更新追踪对方法调用的盲区（M7.4 渲染器陷阱）；系统栏颜色跟随**解析后**的主题——用户锁定浅色时系统切深色，不再出现状态栏与应用表面不一致。
- **死设置处置**：`np.show_lyrics` 接入真实持久化；`SongRow`「加入歌单」「分享」标注「（暂不可用）」并给出可用替代；`np.default_start_tab` 改走 `SettingsRepository` 持久化。
- **角标缩放稳定性**：两处百分比 `.position()` 角标（收藏角标、下载完成对勾）改为 `Stack` 对齐 + 固定 margin，与 M9.3 已修写法同构。
- **交互补全**：删除歌单新增二次确认对话框；探索页「搜索歌曲」接 `focusControl.requestFocus()`，「搜索歌单」如实说明未移植，错误态补「重新搜索」。

### 2. 歌词视图对齐（M11.2）

- **歌词自动滚动**：`Scroll` + 每行 `onAreaChange` 实测行高缓存（布局回调内不写 `@State`，避免重入）+ 视口 30% 带位（首/末行 30%/70% 内边距）+ 420ms 缓动；手动触摸 2.5s 内不抢滚动，点击行 seek 立即解除抑制。
- **消除 O(n×m)**：新增纯逻辑 `lyrics/LyricIndexResolver.ets`（hint 续扫，常态每次位置 tick 一次比较），替换原先每行 4 次全表扫描；暂停时也能给出正确活跃行。
- **`np.lyric_blur` 接线**：按 Android 语义模糊**非活跃行**（审查初稿方向写反，已就地更正），死设置闭合。
- **附带修复**：`NowPlayingPage.currentLyricIndex()` 补齐此前缺失的 `np.lyric_offset_ms`——配歌词偏移时，歌词分享面板预选行与屏幕一致。
- **测试**：新增 `LyricIndexResolver.test.ets`（11 例），已注册进 `entry/src/test/List.test.ets`。

## 验证状态（2026-08-26）

| 门槛 | 结果 |
| --- | --- |
| `assembleHap entry@default`（debug，hvigorw 6.24.4 / SDK 6.1.1.125 API 24） | BUILD SUCCESSFUL |
| 本地单测（以 coverage.log 权威读数） | **827/827，0 failure / 0 error**（816 基线 + 新增 11，只增未减） |
| `assembleHap entry@ohosTest`（debug） | BUILD SUCCESSFUL |
| ArkTS 编译 | 0 error / 125 warn（与基线逐字一致，440 处改动零新增告警） |
| `git diff --check` | 干净 |

> ⚠️ `hvigorw test` 打印 `BUILD SUCCESSFUL` 且退出码 0 也可能有用例失败（本轮实证）。真实结果只认 `entry/.test/default/intermediates/test/coverage_data/coverage.log` 的 `OHOS_REPORT_RESULT: stream=Tests run:` 行。

## 未执行 / 剩余风险（如实登记）

- **CodeLinter 未跑**：DevEco Studio 6.1.1.300 已无命令行入口（只剩 IDE 插件），历史两个互相矛盾的基线均无法从命令行复现。
- **设备验证未执行**：模拟器存活（API 24 / OpenHarmony-6.1.1.125，应用已安装），但本会话无 `NERIPLAYER_SIGNING_PASSWORD`（sign-local.ps1 强制 ≥32 位私有 keystore 口令）；换 SDK 默认 keystore 会导致 `install -r` 签名不一致、只能先 uninstall（会丢失 `preferences/neri_player_data` 等应用数据），故未动设备上的应用。
- **因此以下 UI 行为均未验证**：深色切换整屏是否立即且无撕裂重绘、歌词滚动流畅度与 30% 落点、逐行 `.blur()` 性能开销、`focusControl` 是否真弹键盘、三档字号下新角标稳定性。设备复跑清单见 `docs/UI_REVIEW_M11.md` §9。
- **功能状态未提升**：`FEATURE_MATRIX` 相关三行仍记「部分」——没有设备证据不提升状态。

## 相关文档

- [docs/UI_REVIEW_M11.md](UI_REVIEW_M11.md) —— 静态审查、§3 更正框、§7 完成声明、§8 未验证项、§9 设备复跑清单
- [docs/PORTING_EXECUTION_PLAN.md](PORTING_EXECUTION_PLAN.md) §6 —— 任务看板
- [docs/FEATURE_MATRIX.md](FEATURE_MATRIX.md) —— 功能状态
- [docs/RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) §6 —— 已知能力限制
- [docs/hm.md](hm.md) —— 工具链与构建验证记录
