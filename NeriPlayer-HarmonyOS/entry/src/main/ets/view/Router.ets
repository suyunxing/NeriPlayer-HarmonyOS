import { curves } from '@kit.ArkUI';
import { KEY_REFRESH_TICK } from '../util/Breakpoint';
import { ROUTE_MAIN, RoutePushAction, routePushAction } from './RouteStack';

/**
 * 一镜到底（NOW_PLAYING）的转场弹簧：push/pop 共用同一条曲线，封面沿
 * geometryTransition('np.cover') 往返的节奏才对称。该路由的系统转场是
 * NavigationSystemTransitionType.NONE，动画完全靠把栈操作包进 animateTo
 * 闭包驱动（MiniPlayer S6 引入，现收敛到 Router 统一提供）。闭包内的路由
 * 操作必须带 animated=false（官方共享元素范式，见 Navigation 转场指南与
 * faqs-arkui-991）：系统转场管线一旦参与（NONE = 零时长），会在第 0 帧同步
 * 结束并卸载退场页，把 animateTo 的共享元素动画掐死。
 */
const NOW_PLAYING_SPRING: AnimateParam = { curve: curves.interpolatingSpring(0, 1, 328, 36) };

/**
 * Full-screen route stack for detail overlays.
 *
 * 公开 API（push/pop/canPop/depth/reset + 路由名常量）与自研版本完全一致，
 * 所以全项目 38 处调用点一行都不用改；变的只是内部实现 —— 栈从 AppStorage
 * 里的 JSON 镜像换成了 ArkUI 的 NavPathStack，由 MainShell 的 Navigation
 * 持有并在 aboutToAppear 里 attach() 进来。
 *
 * Back navigation: Index.onBackPress consumes the system back key while
 * canPop() is true. Without that, back on any detail page backgrounded the
 * whole ability (device-observed 2026-08-24).
 */
export class Router {
  static readonly MAIN: string = ROUTE_MAIN;
  static readonly NOW_PLAYING: string = 'now_playing';
  static readonly PLAYLIST_DETAIL: string = 'playlist_detail';
  static readonly NETEASE_PLAYLIST: string = 'netease_playlist';
  static readonly BILI_FAV: string = 'bili_fav';
  static readonly RECENT: string = 'recent';
  static readonly DOWNLOADS: string = 'downloads';
  static readonly STATS: string = 'stats';
  static readonly DEBUG: string = 'debug';
  static readonly SETTINGS_DETAIL: string = 'settings_detail';
  static readonly LISTEN_TOGETHER: string = 'listen_together';
  /** 专辑页，param 为 JSON：{ album: string, albumId: number }。 */
  static readonly ALBUM: string = 'album';
  /** 隐私政策 / 用户协议阅读页，param 取 LEGAL_PRIVACY / LEGAL_AGREEMENT。 */
  static readonly LEGAL_DOC: string = 'legal_doc';

  private static pathStack: NavPathStack | null = null;
  /** attach 时由 MainShell 一并交入：NOW_PLAYING 的 animateTo 需要 UIContext 入口。 */
  private static uiContext: UIContext | null = null;

  /** MainShell.aboutToAppear 把 Navigation 的栈交给 Router。 */
  static attach(stack: NavPathStack, uiContext: UIContext): void {
    Router.pathStack = stack;
    Router.uiContext = uiContext;
  }

  static detach(): void {
    Router.pathStack = null;
    Router.uiContext = null;
  }

  static push(name: string, param: string = ''): void {
    const stack = Router.pathStack;
    if (stack === null) {
      // 启动门阶段（免责声明/引导页）还没有 Navigation，此时不该有路由跳转。
      return;
    }
    const depth = stack.size();
    const names = stack.getAllPathName();
    const top = depth > 0 ? names[depth - 1] : '';
    const action = routePushAction(top, depth, name);
    if (action === RoutePushAction.IGNORE) {
      return;
    }
    if (action === RoutePushAction.CLEAR) {
      stack.clear();
      return;
    }
    if (action === RoutePushAction.REPLACE_TOP) {
      stack.replacePathByName(name, param);
      return;
    }
    const evict = (): void => {
      if (action === RoutePushAction.EVICT_THEN_PUSH) {
        stack.removeByIndexes([0]);
      }
    };
    if (name === Router.NOW_PLAYING && Router.uiContext !== null) {
      // 一镜到底 push 半程：该路由系统转场为 NONE，动画由这个 animateTo 闭包
      // 提供，geometryTransition 才能把封面从迷你条飞到播放页。所有入口统一
      // 在这里包 —— 此前只有 MiniPlayer 自己包了，其余入口 push 是硬切。
      // pushPathByName 带 animated=false，关掉系统 push 管线，转场完全交给
      // animateTo（pop 方向不这么做会硬切，见 pop() 内注释）。
      Router.uiContext.animateTo(NOW_PLAYING_SPRING, () => {
        evict();
        stack.pushPathByName(name, param, false);
      });
      return;
    }
    evict();
    stack.pushPathByName(name, param);
  }

  static pop(): void {
    const stack = Router.pathStack;
    if (stack === null) {
      return;
    }
    const names = stack.getAllPathName();
    const top = names.length > 0 ? names[names.length - 1] : '';
    if (top === Router.NOW_PLAYING && Router.uiContext !== null) {
      // 一镜到底 pop 半程。仅包 animateTo 还不够（b404c3f 实测真机仍硬切）：
      // pop 默认 animated=true，系统 pop 管线（NONE = 零时长）同步结束后立即
      // 卸载退场的 NavDestination，组件级 .transition() 保得住自身、保不住父
      // 容器，geometryTransition('np.cover') 的 out 端在第 0 帧就被销毁。官方
      // 共享元素范式要求路由操作本身 animated=false（Navigation 转场指南 /
      // faqs-arkui-991），退场页存活到 animateTo 闭包动画结束，封面才沿共享
      // 元素飞回迷你条；侧滑手势由 MainShell 的 onBackPressed 拦截后也汇入这里。
      Router.uiContext.animateTo(NOW_PLAYING_SPRING, () => {
        stack.pop(false);
      });
      return;
    }
    stack.pop();
  }

  /** True while a full-screen route is showing, i.e. back has something to pop. */
  static canPop(): boolean {
    const stack = Router.pathStack;
    return stack !== null && stack.size() > 0;
  }

  /** Current depth (0 = the tab shell); for diagnostics and tests. */
  static depth(): number {
    const stack = Router.pathStack;
    return stack === null ? 0 : stack.size();
  }

  /** Drops every level and returns to the tab shell. */
  static reset(): void {
    const stack = Router.pathStack;
    if (stack !== null) {
      stack.clear();
    }
  }

  /**
   * 「回到了 Tab 页」的刷新信号。
   *
   * 改用 Navigation 之前，push 一个路由会整体替换 Tab 骨架，返回时四个 Tab 页
   * 的 aboutToAppear 重跑，数据顺带刷新。现在 Tab 页由 Tabs 常驻、被
   * destination 覆盖时也不销毁，这个隐式刷新就没有了 —— 歌单改名、下载完成
   * 后返回会看到旧数据。所以每个 NavDestination 消失时（覆盖 Router.pop()、
   * 系统返回键、侧滑返回手势、clear() 四条路径）和切换 Tab 时都发一次信号，
   * 由当前可见的 Tab 页自己决定重载。
   */
  static notifyReturned(): void {
    const previous = AppStorage.get<number>(KEY_REFRESH_TICK);
    const tick = previous === undefined || previous === null ? 0 : previous;
    AppStorage.setOrCreate(KEY_REFRESH_TICK, tick + 1);
  }
}
