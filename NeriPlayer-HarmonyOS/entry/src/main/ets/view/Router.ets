import {
  ROUTE_MAIN,
  RouteEntry,
  directionForRouteChange,
  parseRouteStack,
  popRoute,
  pushRoute,
  routeTop,
  serializeRouteStack
} from './RouteStack';

/**
 * Full-screen route stack for detail overlays.
 *
 * The stack itself lives in AppStorage (`route.stack`) so it survives
 * component rebuilds, and its top is mirrored into `route.name`/`route.param`
 * — every page keeps reading those two keys through @StorageLink exactly as
 * before. The stack algebra is in RouteStack.ets (pure, unit-tested).
 *
 * Back navigation: Index.onBackPress consumes the system back key while
 * canPop() is true. Without that, back on any detail page backgrounded the
 * whole ability (device-observed 2026-08-24).
 */
export class Router {
  static readonly KEY_NAME: string = 'route.name';
  static readonly KEY_PARAM: string = 'route.param';
  static readonly KEY_STACK: string = 'route.stack';
  /** Direction of the last change ('push'|'pop'|'none'), read by MainShell's route transition. */
  static readonly KEY_DIRECTION: string = 'route.lastDirection';

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

  static push(name: string, param: string = ''): void {
    Router.publish(pushRoute(Router.stack(), name, param));
  }

  static pop(): void {
    Router.publish(popRoute(Router.stack()));
  }

  /** True while a full-screen route is showing, i.e. back has something to pop. */
  static canPop(): boolean {
    return Router.stack().length > 0;
  }

  /** Current depth (0 = the tab shell); for diagnostics and tests. */
  static depth(): number {
    return Router.stack().length;
  }

  /** Drops every level and returns to the tab shell. */
  static reset(): void {
    Router.publish([]);
  }

  private static stack(): RouteEntry[] {
    const stored = AppStorage.get<string>(Router.KEY_STACK);
    return parseRouteStack(stored === undefined || stored === null ? '' : stored);
  }

  private static publish(entries: RouteEntry[]): void {
    const previous = Router.stack();
    const top = routeTop(entries);
    // Order matters twice: the direction — like the param — must be in place
    // before the name flips, because the transition effect attached during
    // the name-triggered rebuild reads it to pick push vs pop motion.
    AppStorage.setOrCreate(Router.KEY_DIRECTION, directionForRouteChange(previous, entries));
    AppStorage.setOrCreate(Router.KEY_STACK, serializeRouteStack(entries));
    AppStorage.setOrCreate(Router.KEY_PARAM, top === null ? '' : top.param);
    AppStorage.setOrCreate(Router.KEY_NAME, top === null ? Router.MAIN : top.name);
  }
}
