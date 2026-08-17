/**
 * Full-screen route stack for detail overlays. Kept in AppStorage so
 * MainShell can react to changes.
 */
export class Router {
  static readonly KEY_NAME: string = 'route.name';
  static readonly KEY_PARAM: string = 'route.param';

  static readonly MAIN: string = 'main';
  static readonly NOW_PLAYING: string = 'now_playing';
  static readonly PLAYLIST_DETAIL: string = 'playlist_detail';
  static readonly NETEASE_PLAYLIST: string = 'netease_playlist';
  static readonly RECENT: string = 'recent';
  static readonly DOWNLOADS: string = 'downloads';
  static readonly STATS: string = 'stats';
  static readonly DEBUG: string = 'debug';
  static readonly SETTINGS_DETAIL: string = 'settings_detail';

  static push(name: string, param: string = ''): void {
    AppStorage.setOrCreate(Router.KEY_NAME, name);
    AppStorage.setOrCreate(Router.KEY_PARAM, param);
  }

  static pop(): void {
    AppStorage.setOrCreate(Router.KEY_NAME, Router.MAIN);
    AppStorage.setOrCreate(Router.KEY_PARAM, '');
  }
}
