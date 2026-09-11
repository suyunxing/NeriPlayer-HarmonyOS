# 播放页转场修复记录（2026-09-10）

## 第六轮：原生属性动画与剩余偏移（2026-09-11，5eaa922 之后）

- 卡顿：JS `setInterval(16ms)` 逐帧驱动 width/height/position 的方案整体废弃——定时抖动 + 每帧 JS→state→diff→UI 往返是卡顿来源。改为 `panelAmount` 目标值（0/1）+ 原生 `.animation()`：面板几何（translate+width/height/radius）、行位移/透明度、MiniBar 副本全部走 render/动画管线逐帧插值；JS 只保留「挂载延迟一帧」与「结算计时器」（时长+行错峰+余量后恢复命中/卸载模态）。行错峰由每行 `.animation.delay`（展开 i×18ms、收起 (5−i)×18ms）承担。
- 曲线：新增 `view/NowPlayingCurves.ets`（`curves.customCurve`，y 值无界可过冲）——PANEL_CURVE = fraction^2.2（先慢后快，两方向同形），ROW_CURVE = easeOutBack（冲过落点回弹）。`NowPlayingMotion` 退化为纯端点几何 + 错峰预算，`advance/backOut/miniReturnOpacity` 删除。
- 内页位移从 `position`（布局属性）改为 `translate`（渲染属性），去掉每帧子树重排。
- 剩余偏移：按真机截图像素实测（面板起点 (20.1, 629.5) vs 药丸 (26.6, 610.6, 宽 323.6) @360vp），标定常数修正为 PILL_OFFSET_X 27 / PILL_OFFSET_Y −93 / PILL_SHRINK_W 31。

## 第五轮：弹性手感（2026-09-11，7352e3f 之后）

位置标定验证通过后，动画观感生硬。修正：

- 时间轴改为「先慢后快」变速：`NowPlayingMotion.advance()` 对面板插值量做方向感知的闭环积分（da/dt = (0.35 + 1.9a)/T，收起对 1−a 同式），展开与收起都起步慢、临近终点加速；闭环解保证任意帧长下单调、反向切换位置连续（速度分布换向不跳变）。
- 弹性：新增 `backOut`（easeOutBack，端点精确 0/1、中途过冲 ~10% 后回弹）；行入场位移与 MiniBar 上移跟随都改用它，行飞过落点后回弹落定。
- 面板 `panel()` 退化为纯线性插值（变速完全由 amount 时间轴承担）；行错峰窗口按 amount 域重排（0.68 + i·0.038，跨度 0.13）。
- 单测重写：变速前后半程覆盖量、完成不越界、反向连续、行过冲、backOut 端点、面板线性中点。

## 第四轮：起止位置标定与节奏（同日，cec05a4 之后）

真机录屏逐帧像素实测：面板首帧矩形为 (x=0, y≈700vp, w≈347)，而迷你条药丸实际位于 (x≈23, y≈626, w≈314)——HdsTabs 迷你条槽位内 builder 的 `onAreaChange`/`globalPosition` 返回的是**槽位布局矩形**（全宽、贴悬浮栏底部），可见药丸是 HdsTabs 内部位移/裁剪后的呈现，这类变换不触发 `onAreaChange`。修正：

- `MainShell.toPillRect`：槽位矩形 + 标定偏移（+23, −74, 宽 −29）换算成药丸视觉矩形；常量按当前 Hds 版本标定，Hds 调整悬浮栏内部布局时需重标。
- 默认兜底矩形同步改为药丸典型位置。
- 节奏：展开 300ms、收起 400ms（`NowPlayingMotion.EXPAND_MS/COLLAPSE_MS`）。
- 动画启动延迟 32ms → 16ms（总时长缩短后减少空档）。

## 第三轮：真机反馈修正（同日，908d9f2 之后）

- 起止位置不符：模态内容区原点可能与窗口原点有安全区偏移，而面板/迷你条副本用的是窗口坐标——模态根节点 `onAreaChange` 实测自身原点后做 `position` 自校正；MiniBar 矩形测量加固（NaN/零尺寸丢弃）；动画启动延后约两帧，保证首帧画在迷你条原位（模态挂建耗时大于一个 tick 时首帧会从进度 > 0 起跳，看起来像从错误位置开始）。
- 速度：总时长 1000ms → 800ms（1.25 倍）。
- 圆角：新增 `panelRadius`——端点 20 与迷你条药丸一致，飞行前 1/4 段鼓胀到 34，0.3–0.7 段收到 0；补充单测。
- 关闭闪屏：移除模态 `onDisappear` 里的 `Router.notifyReturned()`——普通收起不改变 Tab 页数据，触发刷新会让首页列表重载闪屏；路由级返回刷新仍由各 NavDestination 自身钩子覆盖。

## 第二轮：分阶段动画重写（同日）

按用户四点要求替换上一轮共享元素方案（`geometryTransition` 全部移除）：

- 单一进度驱动：`view/NowPlayingMotion.ets` 纯函数模型（0..1 进度 → 面板矩形、各行位移/透明度、MiniBar 回归时机）；MainShell 以可取消的 16ms 步进持有 `motionProgress`，反向从当前进度回退，支持中途打断折返。
- 面板：`bindContentCover` 挂载期与显示期分离（`ui.nowPlayingMounted`）；面板为固定窗口尺寸内容 + 移动裁剪框（mini 实测矩形 → 全窗），内容不随面板缩放重排。
- MiniBar：展开时上移 22vp 弹性跟随后淡出；收起时面板上边框降到窗口 80% 高度后，展示副本沿上边框（保持条内原顶间距 0vp）弹入淡入；真实迷你条在模态挂载期间整体隐藏。
- 播放页各行（标题行、封面区、歌名区、波形+时间、传输行、底部控件行、歌词胶囊行）按行号 0..5 以 0.035 错峰，进场前半段淡入，退场反向（先下移、后半段淡出）。
- 首页底部：移除 `HdsTabs` 纯色底带；`Index → HdsNavigation → Stack → Column → HdsTabs → TabContent → HomePage Scroll` 链路逐层 `expandSafeArea BOTTOM`，滚动内容真实延伸进手势条区；仅叠加一层由上到下渐透明的底色渐变（不拦截触摸）；播放页模态自身无渐变。
- 路由：`Router.push/pop` 不再包 `animateTo`；退出期间重复返回不弹底层栈（`canPop` 同步认挂载态）。

新增纯函数单测 `entry/src/test/ets/test/NowPlayingMotion.test.ets`（阈值 0.8、错峰 0.035、透明度前半段、面板插值端点）。

## 验证边界

环境：Linux command-line-tools（API 26），`hdc list targets` 为空。

- 已执行：debug 构建、改动文件 codelinter、`hvigorw test` 编译级检查（Linux 执行段挂死为已知平台限制，结果以本次交付说明为准）。
- 未验证（需真机）：分阶段动画观感与参考视频的一致性、打断折返、歌词模式返回、首页内容穿透手势条的实际显示与渐变可读性。
- 未修改数据格式、权限、第三方接口与签名配置。

## 第一轮摘要（已被本轮替换）

迷你条背景/控件兄弟化 + 统一 480ms Friction + 底色统一，构建通过；共享元素时序问题当时已缓解，但控件飞行路径与参考差异大，随后按用户反馈整层替换。
