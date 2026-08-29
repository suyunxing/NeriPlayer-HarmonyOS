# 全屏路由转场（RouteShell，M11.6d 移植）

本文件记录 `feat/nav-route-transitions` 分支：把 ch 分支 M11.6d 的"全屏路由竖向
转场"移植到 dev 的 `Navigation` 架构上。PR 对应 `docs/MERGE_CH_INTO_DEV.md` §10 待办 1。

## 1. 目标与最终形态

- push：新页从**底部滑入** 220ms（NowPlaying 300ms）
- pop ：被返回的页从**顶部滑下归位** 240ms（NowPlaying 250ms）
- pop 出场：退出的页固定 fade（避免与归位页相撞）
- 冷启动直接压入的路由不播入场动画（首帧布防）

实现：新增 `view/components/RouteShell.ets`，`MainShell.pageMap` 改为把每条路由
分发进一个 `RouteShell`。时长取 `MotionSpec` 常量（Android 同源，NeriApp.kt:304-310）。

## 2. 为什么用 RouteShell + NavDestination.customTransition

### 2.1 状态必须按页隔离（硬约束）

`customNavContentTransition`（Navigation 级）与 `NavDestination.customTransition`
（按目标页声明）都要求**每个 destination 有自己的动画状态**（`@State translateY/opacity`）。

dev 原来的 pageMap 是 `MainShell` 的一个 `@Builder`，返回**一个共享的 NavDestination**，
内部 if/else 分发 12 条路由 —— `@Builder` 引用的 `@State` 属于唯一的 `MainShell` 实例，
所有栈条目共享同一份动画状态，无法独立动画。

方案：每条路由实例化一个 `RouteShell`（独立 `@Component`）→ 每个栈条目一个实例、
一份 `@State`。这正是官方示例的形态（共享 pageMap 分发到自带状态的组件）。
**不修改 12 个页面文件**，改动集中在 1 个新文件 + pageMap。

### 2.2 为什么选 customTransition 而不是 customNavContentTransition

| | customNavContentTransition（API 11+） | customTransition（API 15+，本工程 API 24 可用） |
| --- | --- | --- |
| 注册表 | 要按 `navDestinationId` 建回调 Map，onReady 注册/onDisAppear 注销 | 无，按页声明 |
| 生命周期 | 必须手动 `finishTransition()`，否则 timeout 后强杀 | 无 |
| 时长 | 自己包 animateTo | `duration`/`curve` 一等字段 |
| NavBar（Tab 骨架） | NavContentInfo `index === -1`、无 navDestinationId，**官方示例一律 return undefined** → 「详情页→Tab」这条最常用的返回路径**无法**自定义 | **不受限**：per-destination 委托，destination 退出时照常触发 → 详情页 pop 回 Tab 的滑出/fade 能生效 |

后者更简单且覆盖更广，是查证后的选择（API 可用性见 §5）。

## 3. 文件改动

| 文件 | 改动 |
| --- | --- |
| `view/components/RouteShell.ets` | 新增：NavDestination 外壳 + 转场状态 + customTransition |
| `view/pages/MainShell.ets` | pageMap 分发进 RouteShell；`hideTitleBar`/透明背景/`onWillDisappear` 移入 RouteShell（行为不变）；NowPlaying 传 300/250 |

## 4. 转场语义细节

- `PUSH + isEnter`：`translateY = 100`（屏外下缘）→ event 拉回 `0`，EaseOut，`enterMs`。
- `POP + isEnter`（被返回的页）：`translateY = -100`（屏外上缘）→ 归位 `0`，EaseOut，`exitMs`。
- `POP + !isEnter`（退出的页）：opacity `1 → 0`，EaseIn，`exitMs`。fade 而非滑出，
  避免与上方归位页在中间相撞（ch M11.6d"出场固定 fade"）。
- `PUSH + !isEnter`（下层页）：保持不动，`undefined` 交还系统。
- 未武装（挂载后首个宏任务前）时一律 `undefined`：冷启动直接压入的路由不播入场动画。
- `REPLACE`：`undefined`（本应用路由不用 replace，交还系统兜底）。

## 5. 查证依据（deveco-cli 文档，2026-08-29）

- `customNavContentTransition` API 11+、`NavDestination.customTransition` API 15+、
  `NavigationOperation`（PUSH=1/POP=2/REPLACE=3）、`NavDestinationTransition`
  （`duration`/`curve`/`delay`/`event`）—— 均在本工程 API 24 可用范围内。
- 官方 FAQ 明确：`customNavContentTransition` 生效时原默认 page 动画失效；
  对 NavBar（index -1）官方示例一律 `return undefined`。
- 官方 FAQ：不要在 NavDestination 上设 `zIndex`/`transition`/`geometryTransition`/
  `sharedTransition`/`animation`（覆盖系统分层或与之冲突）；`.translate()`/`.opacity()`
  是官方示例的做法，可用。
- 未找到共享单 `@Builder` + Navigation 级委托注册表的官方组合案例；"每页组件自带状态"
  是从官方示例（按页注册/onReady 取 navDestinationId）推断的 —— 即 §2.1 的硬约束来源。

## 6. 验证状态

**本轮实测（2026-08-29，DevEco 6.1.1.300 本机）：**

- `assembleHap`：**`BUILD SUCCESSFUL in 33 s`，0 `ERROR`**
- 单测：**0 `AssertException`、0 `ERROR`** → 全部通过（退出码恒为 0，不作判据，
  见 `docs/MERGE_CH_INTO_DEV.md` §9.4）
- 首轮构建曾报 4 个编译错误并已修复，见 §6.1

**设备未验证（本 PR 主要风险点）**：转场观感、时序、`customTransition` 在 6.1.1
真机上的实际行为（含冷启动布防窗口、Swiper 分页与 translate 叠加、fade 出场后实例销毁）
均未上机确认。合并前请至少在模拟器/真机过一遍：进播放页、返回、进设置详情、返回 Tab、
冷启动恢复播放。

已知边界：Tab 骨架（NavBar）本身无法动画；pop 回 Tab 时只有出场的详情页在动，
Tab 页直接显示（系统行为）。与 Android 侧"整页一起动"有观感差异，记录在案。

### 6.1 首轮构建错误记录（已修复）

1. `Curve` / `NavigationOperation` / `NavDestinationTransition` 不是 `@kit.ArkUI` 的导出
   成员，而是 ArkTS 环境全局类型 —— 从 import 中移除即可（现有代码 `Curve.EaseOut`
   在仅 `import { curves }` 的文件里本就能编译）。
2. `@State opacity` 与 `CustomComponent` 基类的 `opacity()` 属性方法同名遮蔽 ——
   改名为 `fadeOpacity`。

## 7. 回滚

```bash
git revert -m 1 <合并提交>   # 或
git checkout dev -- NeriPlayer-HarmonyOS/entry/src/main/ets/view/components/RouteShell.ets \
                     NeriPlayer-HarmonyOS/entry/src/main/ets/view/pages/MainShell.ets
```
