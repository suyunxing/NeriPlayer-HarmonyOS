// SPDX-License-Identifier: GPL-3.0

import { KEY_REFRESH_TICK } from '../util/Breakpoint';
import { ROUTE_MAIN, RoutePushAction, routePushAction } from './RouteStack';

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
  /** B 站内嵌官方登录页（WebView），无参数。 */
  static readonly BILI_WEB_LOGIN: string = 'bili_web_login';
  /** 网易云内嵌官方登录页（WebView），无参数。 */
  static readonly NETEASE_WEB_LOGIN: string = 'netease_web_login';

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
   * 当前 NavPathStack 深度快照（0 = Tab 骨架，>0 = 处于子页）。每次栈操作后
   * 同步发布，MainShell 用 @StorageProp 消费，驱动迷你条在子页下沉为 dock
   * 形态。push 全部经过 Router.push、返回全部经过 Index.onBackPress →
   * Router.pop，所以这里就是深度唯一的事实来源。
   */
  static readonly KEY_SUB_PAGE_DEPTH: string = 'ui.subPageDepth';

  private static nowPlayingShown(): boolean {
    return AppStorage.get<boolean>(Router.KEY_NOW_PLAYING_SHOWN) === true;
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
      // The shell owns visual progress and keeps the modal mounted through exit.
      AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, true);
      return;
    }
    const stack = Router.pathStack;
    if (stack === null) {
      // 启动门阶段（免责声明/引导页）还没有 Navigation，此时不该有路由跳转。
      return;
    }
    // 模态盖在整个 Navigation 之上，播放页内发起的路由（专辑/一起听）必须先
    // 收掉模态再入栈，否则新页面渲染在模态下面不可见。不包 animateTo：立即
    // 收起，不与被推入页面自身的 DEFAULT 转场叠加；副作用是返回时回到打开
    // 播放页之前的页面而不是播放页（模态已收，与设计预期一致）。
    if (Router.nowPlayingShown()) {
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
    const evict = (): void => {
      if (action === RoutePushAction.EVICT_THEN_PUSH) {
        stack.removeByIndexes([0]);
      }
    };
    evict();
    stack.pushPathByName(name, param);
    Router.publishDepth();
  }

  static pop(): void {
    // Repeated back presses during exit must not pop the route underneath.
    if (Router.nowPlayingShown() || AppStorage.get<boolean>('ui.nowPlayingMounted') === true) {
      AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
      return;
    }
    const stack = Router.pathStack;
    if (stack === null) {
      return;
    }
    stack.pop();
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
