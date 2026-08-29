import { Router } from '../Router';
import { MotionSpec } from '../theme/MotionSpec';

/**
 * 全屏路由的统一 NavDestination 外壳：每一条路由（NavPathStack 的每个栈条目）
 * 实例化一个 RouteShell，由它产出 NavDestination 并承载该路由自己的转场状态。
 *
 * 为什么需要这一层而不是在 MainShell.pageMap 的共享 @Builder 里直接写
 * NavDestination：自定义转场要求每个 destination 有**自己的**动画状态
 * （@State translateY/opacity）。共享 @Builder 是 MainShell 的方法，其引用的
 * @State 属于唯一的 MainShell 实例 —— 11 条路由会共享同一份动画状态、一起动。
 * RouteShell 是独立 @Component，每个栈条目一个实例，状态天然隔离。
 *
 * 转场语义移植 ch 分支 M11.6d（docs/UI_ANIMATION_PLAN.md 的 Android 对照，
 * NeriApp.kt:304-310）：
 *   - push：新页从底部滑入 220ms（NowPlaying 300ms）
 *   - pop ：被返回的页从顶部滑下归位 240ms（NowPlaying 250ms）
 *   - pop 出场：退出的页固定 fade（规避移除分支属性过期）
 * 时长取 MotionSpec 常量，与 Android 侧同源。
 *
 * 用 NavDestination.customTransition（API 15+）而非 Navigation 级的
 * customNavContentTransition：前者按目标页声明、无注册表、无 finishTransition，
 * 官方示例即用本组件的形态（共享 pageMap 分发到自带 @State 的组件）。
 * 且 per-destination 委托能覆盖「详情页 → Tab 骨架」这条最常用的返回路径
 * （NavBar 没有 navDestinationId，Navigation 级委托对它会直接回退系统动画）。
 */
@Component
export struct RouteShell {
  /** 页面本体。页面的返回键处理、onWillDisappear 刷新信号等都与此无关，由下方 NavDestination 统一挂接。 */
  @BuilderParam content: () => void;
  /** push 进入时长（ms）。 */
  enterMs: number = MotionSpec.DETAIL_OPEN_MS;
  /** pop 退出/归位时长（ms）。 */
  exitMs: number = MotionSpec.DETAIL_CLOSE_MS;

  @State translateY: number = 0;
  // 出场 fade 的不透明度。不能叫 opacity：CustomComponent 基类已有一个
  // opacity() 属性方法，同名 @State 会把基类成员遮蔽掉（编译报错）。
  @State fadeOpacity: number = 1;
  // 首帧布防：冷启动直接压入的路由（如恢复播放状态时 push NowPlaying）不播入场
  // 动画。挂载后首个宏任务才武装，之后的所有 push/pop 才走自定义转场
  // （移植 ch M11.6d 的 contentTransitionArmed 思路）。
  private armed: boolean = false;

  aboutToAppear(): void {
    setTimeout(() => {
      this.armed = true;
    }, 0);
  }

  build() {
    NavDestination() {
      this.content()
    }
    .hideTitleBar(true)
    // NavDestination 默认背景是不透明白：深色模式下内容区以下的系统
    // 导航条区会露出一截白边。显式置透明，条带回落到 Index 的沉浸背景
    // 层（应用底色）；页面正文各自的背景是动态取色，无法用单一背景逐路由对齐。
    .backgroundColor(Color.Transparent)
    // destination 被销毁时通知常驻的 Tab 页刷新。一处覆盖四条返回路径：
    // Router.pop()、系统返回键、侧滑返回手势、Router.reset() 的 clear()。
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
    .customTransition((operation: NavigationOperation, isEnter: boolean):
    Array<NavDestinationTransition> | undefined => {
      if (!this.armed) {
        return undefined;
      }
      if (operation === NavigationOperation.PUSH && isEnter) {
        // 新页从底部滑入：先落到 +100%（屏幕外下缘），动画拉回原位。
        this.translateY = 100;
        return [{
          duration: this.enterMs,
          curve: Curve.EaseOut,
          event: () => {
            this.translateY = 0;
          }
        }];
      }
      if (operation === NavigationOperation.POP && isEnter) {
        // 被返回的页从顶部滑下归位（pop 的镜像方向）。
        this.translateY = -100;
        return [{
          duration: this.exitMs,
          curve: Curve.EaseOut,
          event: () => {
            this.translateY = 0;
          }
        }];
      }
      if (operation === NavigationOperation.POP && !isEnter) {
        // 退出的页固定 fade 出场，避免与下层归位页在中间相撞。
        this.fadeOpacity = 1;
        return [{
          duration: this.exitMs,
          curve: Curve.EaseIn,
          event: () => {
            this.fadeOpacity = 0;
          }
        }];
      }
      // push 时的下层页保持不动；REPLACE 等其余情况交还系统默认。
      return undefined;
    })
    .translate({ y: `${this.translateY}%` })
    .opacity(this.fadeOpacity)
  }
}
