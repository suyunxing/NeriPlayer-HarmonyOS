// SPDX-License-Identifier: GPL-3.0

import { KEY_REFRESH_TICK } from '../util/Breakpoint';
import { ROUTE_MAIN, RoutePushAction, routePushAction } from './RouteStack';
import { ezCustomTransition } from '@hmanimations/ezcustomtransition';

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
  /** 网易云艺人页，param 为 JSON：{ artist: string, artistId: number }。 */
  static readonly ARTIST: string = 'artist';
  /** 隐私政策 / 用户协议阅读页，param 取 LEGAL_PRIVACY / LEGAL_AGREEMENT。 */
  static readonly LEGAL_DOC: string = 'legal_doc';
  /**
   * 一镜到底 M1 spike 验证页（docs/ONETAKE_INTEGRATION_PLAN.md §4）：
   * HdsNavigation × ezcustomtransition 兼容性最小闭环，临时路由，M5 拆除。
   */
  static readonly LONG_TAKE_SPIKE: string = 'longtake_spike';

  private static pathStack: NavPathStack | null = null;
  /** attach 时由 MainShell 一并交入：NOW_PLAYING 的 animateTo 需要 UIContext 入口。 */
  private static uiContext: UIContext | null = null;
  /**
   * 全屏播放页模态的开关键（Router 写、MainShell 的 bindContentCover 读）。
   * MainShell/MiniPlayer 侧装饰器只收字符串字面量，须与此常量保持同名字面量
   * 'ui.nowPlayingShown'（@StorageLink 装饰器参数不接受导入的常量引用）。
   */
  static readonly KEY_NOW_PLAYING_SHOWN: string = 'ui.nowPlayingShown';
  /**
   * 播放页承载形态开关（docs/ONETAKE_INTEGRATION_PLAN.md D4 回退门）：
   * true/未设置 = 播放页以 NavDestination 入栈（一镜到底三方库路径）；
   * false = 旧 bindContentCover 模态路径。调试开关在 DebugPage（非持久，
   * 重启回默认路由形态）；真机验证通过一个里程碑周期后随模态路径一起拆除。
   */
  static readonly KEY_NOW_PLAYING_AS_ROUTE: string = 'ui.nowPlayingAsRoute';
  /**
   * 当前 NavPathStack 深度快照（0 = Tab 骨架，>0 = 处于子页）。每次栈操作后
   * 同步发布，MainShell 用 @StorageProp 消费，驱动迷你条在子页下沉为 dock
   * 形态。push 全部经过 Router.push、返回全部经过 Index.onBackPress →
   * Router.pop，所以这里就是深度唯一的事实来源。
   */
  static readonly KEY_SUB_PAGE_DEPTH: string = 'ui.subPageDepth';

  private static nowPlayingShown(): boolean {
    return AppStorage.get<boolean>(Router.KEY_NOW_PLAYING_SHOWN) === true;
  }

  /** 播放页当前是否走路由形态（flag 未设置时默认 true，见 KEY_NOW_PLAYING_AS_ROUTE）。 */
  static routeMode(): boolean {
    return AppStorage.get<boolean>(Router.KEY_NOW_PLAYING_AS_ROUTE) !== false;
  }

  /** MainShell.aboutToAppear 把 Navigation 的栈交给 Router。 */
  static attach(stack: NavPathStack, uiContext: UIContext): void {
    Router.pathStack = stack;
    Router.uiContext = uiContext;
  }

  /**
   * 栈操作后同步发布深度快照。NavPathStack 的 size() 在 push/pop/replace/clear
   * 之后即时可读（Router.push 自身的防重决策就依赖这一语义），这里沿用。
   */
  private static publishDepth(): void {
    const stack = Router.pathStack;
    AppStorage.setOrCreate(Router.KEY_SUB_PAGE_DEPTH, stack === null ? 0 : stack.size());
  }

  static detach(): void {
    Router.pathStack = null;
    Router.uiContext = null;
  }

  static push(name: string, param: string = ''): void {
    if (name === Router.NOW_PLAYING) {
      Router.pushNowPlaying();
      return;
    }
    Router.pushObject(name, param);
  }

  /**
   * 播放页唯一入口（M3 收口：迷你条与歌曲行七处调用点统一走这里）。两种
   * 形态：路由形态——先置 'ui.nowPlayingShown'（双路径共用的「播放页可见」
   * 语义，迷你条显隐门/pop 门/系统返回都消费它；归零由播放页 NavDestination
   * 的 onDisAppear 统一负责，覆盖侧滑手势路径）再真正入栈；triggerId 非空时
   * 同步截图并生成一镜到底转场参数经 route param 传给目标页（长表单歌曲行
   * 入口暂不传 id，走系统默认转场，M4 真机评估后再铺 id）；模态形态——维持
   * 原开关翻转，由 MainShell 的 bindContentCover 承载。转场选项（弹簧曲线/
   * 手势开关）库未导出选项类型，M3 用库默认值（CardLongTake + 手势开 +
   * 默认曲线），M4 真机评估调优。
   */
  static pushNowPlaying(triggerId?: string, cornerRadius?: number): void {
    AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, true);
    if (!Router.routeMode() || Router.pathStack === null) {
      return;
    }
    const param: Record<string, Object> = {};
    if (triggerId !== undefined && triggerId.length > 0 && Router.uiContext !== null) {
      // 截图与矩形测量同步执行（onClick 内）：迷你条约 40vp 小组件，开销可忽略；
      // 组件未挂载（切 Tab 重建窗口期）时库返回 undefined，回退默认转场。
      const longTakeParam = ezCustomTransition.generateLongTakeParam(
        Router.uiContext, triggerId, cornerRadius ?? 0);
      if (longTakeParam !== undefined) {
        param['longTakeTransitionParam'] = longTakeParam;
      }
    }
    Router.pushObject(Router.NOW_PLAYING, param);
  }

  /**
   * 以任意对象参数入栈。一镜到底转场参数（LongTakeTransitionParam 实例）
   * 经 route param 传给目标页，字符串通道装不下，spike 起开放此入口；
   * push(name, param) 的字符串参数也统一从这里落栈，决策规则（防重、
   * CLEAR、REPLACE_TOP、深度上限驱逐）保持一处。
   */
  static pushObject(name: string, param: Object): void {
    const stack = Router.pathStack;
    if (stack === null) {
      // 启动门阶段（免责声明/引导页）还没有 Navigation，此时不该有路由跳转。
      return;
    }
    // 模态路径专用：模态盖在整个 Navigation 之上，播放页内发起的路由（专辑/
    // 一起听）必须先收掉模态再入栈，否则新页面渲染在模态下面不可见。路由形态
    // 下播放页在栈内、模态不再挂载，跳过收起——子页直接叠上、返回即回播放页，
    // 「返回时回到打开播放页之前的页面」的历史包袱就此消除（D1）。
    if (!Router.routeMode() && Router.nowPlayingShown()) {
      AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
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
      Router.publishDepth();
      return;
    }
    if (action === RoutePushAction.REPLACE_TOP) {
      stack.replacePathByName(name, param);
      Router.publishDepth();
      return;
    }
    if (action === RoutePushAction.EVICT_THEN_PUSH) {
      stack.removeByIndexes([0]);
    }
    stack.pushPathByName(name, param);
    Router.publishDepth();
  }

  /** 播放页路由返回转场的时间窗防重（ms）：返回转场中重复返回不弹下一层。 */
  private static readonly PLAYING_POP_GUARD_MS: number = 450;
  private static lastPlayingPopMs: number = 0;

  static pop(): void {
    const stack = Router.pathStack;
    if (stack === null) {
      return;
    }
    if (Router.routeMode()) {
      // 路由形态：播放页在栈内，返回就是普通弹栈（'ui.nowPlayingShown' 由
      // 播放页 NavDestination 的 onDisAppear 归零）。仅当模态残留（调试中
      // 运行时切换 flag 的窗口期）时走模态关闭分支。
      if (AppStorage.get<boolean>('ui.nowPlayingMounted') === true) {
        AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
        return;
      }
      const names = stack.getAllPathName();
      const top = names.length > 0 ? names[names.length - 1] : '';
      const now = Date.now();
      if (top === Router.NOW_PLAYING && now - Router.lastPlayingPopMs < Router.PLAYING_POP_GUARD_MS) {
        return;
      }
      if (top === Router.NOW_PLAYING) {
        Router.lastPlayingPopMs = now;
      }
      stack.pop();
      Router.publishDepth();
      return;
    }
    // Repeated back presses during exit must not pop the route underneath.
    if (Router.nowPlayingShown() || AppStorage.get<boolean>('ui.nowPlayingMounted') === true) {
      AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
      return;
    }
    stack.pop();
    Router.publishDepth();
  }

  /**
   * 只重发深度快照、不发 Tab 刷新信号。给「不经 Router 的弹栈路径」（一镜
   * 到底手势返回、NavDestination 自身的系统返回）补齐 ui.subPageDepth 用；
   * notifyReturned() 的刷新广播对播放页不适用（会触发首页重载式闪屏，见
   * MainShell 模态 onDisappear 注释）。
   */
  static syncDepth(): void {
    Router.publishDepth();
  }

  /** True while a full-screen route or the now-playing modal is showing, i.e. back has something to close. */
  static canPop(): boolean {
    if (Router.nowPlayingShown() || AppStorage.get<boolean>('ui.nowPlayingMounted') === true) {
      return true;
    }
    const stack = Router.pathStack;
    return stack !== null && stack.size() > 0;
  }

  /** Current Navigation depth (0 = the tab shell), for diagnostics and tests. */
  static depth(): number {
    const stack = Router.pathStack;
    return stack === null ? 0 : stack.size();
  }

  /** Drops every route level and closes the now-playing modal. */
  static reset(): void {
    // 播放页模态不在 Navigation 栈里，reset 需要一并收掉。
    AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
    const stack = Router.pathStack;
    if (stack !== null) {
      stack.clear();
      Router.publishDepth();
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
    // 返回不止 Router.pop() 一条路：侧滑返回手势与子页标题栏返回键由
    // Navigation 直接弹栈，Router 感知不到——而每个 NavDestination 消失时
    // 都会回调到这里（见下注释四条路径），在这里补发深度快照，dock 态迷你条
    // 的 ui.subPageDepth 才不会卡在 >0（真机首版实测：卡住后主页槽位迷你条
    // 内容永久隐藏，只剩 HdsTabs 自绘的空药丸壳）。幂等重发，无副作用。
    Router.publishDepth();
    const previous = AppStorage.get<number>(KEY_REFRESH_TICK);
    const tick = previous === undefined || previous === null ? 0 : previous;
    AppStorage.setOrCreate(KEY_REFRESH_TICK, tick + 1);
  }
}
