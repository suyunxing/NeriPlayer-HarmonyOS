# M10.2 系统级桌面歌词可行性 Spike（D4 复核）

> 调研日期：2026-08-25。执行者：ZCode agent。结论消费者：`HARMONYOS_NATIVE_FEATURES.md` §3、§12 M10.2，`FEATURE_MATRIX.md`「动态取色/高级视觉」行的 **D4 降级**结论。
>
> 方法：本机 API 24 SDK d.ts 逐条核对（`sdk/default/openharmony/ets/api/@ohos.multimedia.avsession.d.ts`）+ **模拟器设备端探针**（ohosTest，正向链路 + 负向反证）+ 系统服务 hilog 取证 + 窗口树 dump + 截图。**未做**：真机验证（本机无真机），如实记录，见 §5。

## 1. 结论

**系统级桌面歌词在 API 24 上对普通应用可用，且系统侧确认接管了我们推送的歌词——`FEATURE_MATRIX.md` 的 D4 降级前提「鸿蒙无系统级悬浮歌词能力，只能应用内自绘」已被推翻。**

但**本次未能取得「歌词窗真的绘制出来」的视觉证据**：模拟器上窗口对象被创建、`show` 被调用、系统解析出 2 行歌词，然而窗口从未进入合成树，截图为空。有证据表明这是**模拟器图形栈的限制**而非 API 失败（§4），但这一步只到「系统服务真实接管」一级，**未到「像素上屏」一级**。

因此：**D4 结论应改写为「能力存在且已验证到服务层，渲染层待真机确认」，而不是直接改写为「可用」。** 是否将应用内自绘 `np.floating_lyric` 切换/并入系统桌面歌词，须待真机复跑本文档 §3 的探针后再定。

## 2. API 面证据（d.ts 核对，API 24）

全部位于 `@ohos.multimedia.avsession.d.ts`，**全部 `@since 23`（≤ 基线 24）、无 `@permission`、无 `@systemapi`、`@stagemodelonly`**（本工程正是 Stage 模型）→ 普通应用可直接调用，`module.json5` 无需新增权限。

| 能力 | API | 位置 |
| --- | --- | --- |
| 设备能力查询 | `avSession.isDesktopLyricSupported(): Promise<boolean>` | :122，**顶层命名空间函数，无需 session 实例** |
| 启用/停用 | `AVSession.enableDesktopLyric(enable: boolean): Promise<void>` | :684 |
| 显示/隐藏 | `AVSession.setDesktopLyricVisible(visible: boolean): Promise<void>` | :696 |
| 查询可见性 | `AVSession.isDesktopLyricVisible(): Promise<boolean>` | :709 |
| 可见性回调 | `AVSession.onDesktopLyricVisibilityChanged(cb)` / `off…` | :718 |
| 锁定态 | `AVSession.setDesktopLyricState(state)` / `getDesktopLyricState()`；`DesktopLyricState { isLocked: boolean }` | :130、:774 |
| 控制端一侧 | `AVSessionController.isDesktopLyricEnabled` / `onDesktopLyricEnabled` 等同名族 | :6081–6195 |

错误码分工（本次全部实际观测到或据其设计断言）：

| 码 | 含义 |
| --- | --- |
| 6600101 | Session service exception |
| 6600102 | The session does not exist |
| **6600110** | **本应用未启用桌面歌词**（`setDesktopLyricVisible` 专有） |
| 6600111 | 设备不支持桌面歌词 |

歌词内容本身不走桌面歌词 API，而是复用 M10.1 已落地的 `AVMetadata.lyric`（完整 LRC，`@since 10`）——见 §3 系统侧日志实证。

## 3. 设备探针

`entry/src/ohosTest/ets/test/DesktopLyricProbe.test.ets`，3 个用例，Pura 90 API 24 模拟器，`Tests run: 3, Failure: 0, Error: 0, Pass: 3`。

### 3.1 正向链路：10 步全部成功

```
DesktopLyricProbe isDesktopLyricSupported=true
DesktopLyricProbe steps setAVMetadata=ok activate=ok setAVPlaybackState=ok
  onDesktopLyricVisibilityChanged=ok enableDesktopLyric=ok setDesktopLyricVisible=ok
  isDesktopLyricVisible=ok getDesktopLyricState=ok
  setDesktopLyricVisible(false)=ok isDesktopLyricVisible(afterOff)=ok
DesktopLyricProbe visibilityCallbacks=2 last=false
```

- `isDesktopLyricSupported()` 在**模拟器上返回 `true`**（与「模拟器多半不支持」的预期相反）。
- 可见性**双向往返成立**：`true` → 回调 `true`、查询 `true`；`false` → 回调 `false`、查询 `false`，共 2 次回调。
- `getDesktopLyricState().isLocked = false`。

### 3.2 负向反证：证明这不是 stub

关键在于，若整套 API 无条件返回成功，则 §3.1 的「全 ok」毫无意义。用例 `desktopLyricVisibleWithoutEnableIsRefused` 故意跳过 `enableDesktopLyric` 直接调 `setDesktopLyricVisible`：

```
DesktopLyricProbe negative setDesktopLyricVisible/noEnable=err(6600110:
  SetDesktopLyricVisible failed : native desktop lyrics feature of this application is not enabled)
```

**被 6600110 拒绝，且错误文本来自 native 侧**（`native desktop lyrics feature…`）→ 系统在真实追踪每应用的启用状态，这不是空实现。

### 3.3 系统服务侧取证（决定性）

`com.huawei.hmos.mediacontroller`（v6.1.0.512）在探针调用后被真实拉起并接管：

```
MDL_DesktopLyricAbility, onCreate
MDL_DesktopLyricAbility, onRemoteMessageRequest controlPkgName: moe.ouom.neriplayer
MDL_ViewModel, isAppSupportDesktopLyric: true
MDL_StorageTransform, before metadataChange: {"assetId":"probe:desktop-lyric",
  "title":"NeriPlayer 探针","artist":"M10.2","duration":60000,
  "lyric":"[00:00.000] desktop lyric probe line one\n[00:03.000] probe line two\n",
  "singleLyricText":"desktop lyric probe line one"}
MDL_Util, analyzeLyric start
MDL_Util, analyzeLyric end, length = 2
MDL_Service, openWindow size: {"width":1218,"height":518}, position: {"x":51,"y":161}
MDL_Service, openWindow start show
MDL_DesktopLyricPage, DesktopLyricPage page show
```

四点值得单独记下：

1. 系统**读到了我们经 M10.1 正规字段推送的完整 LRC**，并**自己解析出 2 行**（`analyzeLyric end, length = 2`）——歌词内容通路完全打通，应用侧无需再做逐行下发。
2. 系统同时读到 `duration: 60000` 与我们设的播放态 `{"state":2,...}`，`MDL_MediaCardVm` 正常联动。
3. 窗口几何是系统决定的：`1218×518 @ (51,161)`（屏 1320×2856，densityPixels 3.5）。
4. 关闭时对称收尾：`closeRealWindow` → `deleteDlWindow`。

## 4. 为什么屏幕上仍然看不到（模拟器限制的证据）

在窗口存活期（`page show` 至 `closeRealWindow` 之间约 5.5 秒）内截图 3 次、dump 窗口树 2 次：

- 截图全部为纯桌面，无任何歌词窗。
- `hidumper -s WindowManagerService -a '-a'` 的**完整**窗口树共 30 个窗口，**全部属于 SceneBoard（pid 1454）**，没有任何属于 mediacontroller 进程的窗口条目 → 窗口从未进入合成树。
- 同期图形栈报错：`RSClientToRenderConnection: TakeSurfaceCapture failed, node is nullptr` —— 有窗口逻辑实例但**没有渲染节点**。
- 另有 `HdsMaterialUtils, isSupportHdsMaterial: false`（模拟器缺 HDS 材质能力，桌面歌词窗依赖的模糊/材质效果不可用）。

综合判断：**服务层与内容层都正常，缺的是模拟器的窗口合成/渲染能力**。这与 M9.3 布局回归时模拟器一贯可用的应用内窗口不同——桌面歌词窗是 mediacontroller 起的系统级悬浮窗，走的是另一条渲染路径。

必须承认这是**推断而非证明**：不能完全排除「该窗口在模拟器上被有意抑制」或「还差某个未文档化的前置条件」。定论需真机。

## 5. 未验证项（如实登记）

- **真机**：全部结论来自 Pura 90 模拟器。渲染层能否上屏、系统歌词窗的实际观感与交互（拖动/锁定/点按回应用）均未在真机确认。
- **锁定态写入**：只读了 `getDesktopLyricState()`，未调 `setDesktopLyricState()` 改锁定并观察行为。
- **用户从系统侧关闭**：`onDesktopLyricVisibilityChanged` 的 2 次回调都由我们自己的调用触发；「用户在系统 UI 上手动关闭 → 应用收到回调」这一路径未走到（模拟器上无窗口可点）。
- **与应用内 `np.floating_lyric` 的关系**：两者是否会同屏重复、该由谁让位，未设计也未验证。
- **长文本/滚动/逐字**：只推了 2 行普通 LRC。AMLL 逐字（`LyricWord`）在系统歌词窗内如何降级未知。
- **AVSessionController 侧**（:6081–6195）整族 API 未触碰。

## 6. 后续（真机复跑清单）

真机到位后按序执行，本文档 §3 的探针可直接复用（`aa test -s class ActsDesktopLyricProbeTest`）：

1. 复跑 3 用例，确认 `isDesktopLyricSupported()` 真机返回值。
2. 在观测窗口（探针内 `OBSERVE_MS = 6000`）内截图 + dump 窗口树，判定歌词窗是否上屏。
3. 若上屏：手动关闭系统歌词窗，验证 `onDesktopLyricVisibilityChanged` 回调；再试 `setDesktopLyricState({isLocked: true})`。
4. 据结果改写 `FEATURE_MATRIX.md`「动态取色/高级视觉」行的 D4 结论，并决定 `np.floating_lyric` 的去留。
