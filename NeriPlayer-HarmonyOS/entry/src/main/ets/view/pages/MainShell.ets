import { Router } from '../Router';
import { Theme } from '../Theme';
import { SettingsRepository } from '../../data/SettingsRepository';
import { MiniPlayer } from '../components/MiniPlayer';
import { FloatingLyricBar } from '../components/FloatingLyricBar';
import { HomePage } from './HomePage';
import { ExplorePage } from './ExplorePage';
import { LibraryPage } from './LibraryPage';
import { SettingsPage } from './SettingsPage';
import { NowPlayingPage } from './NowPlayingPage';
import { PlaylistDetailPage } from './PlaylistDetailPage';
import { NeteasePlaylistPage } from './NeteasePlaylistPage';
import { BiliFavPage } from './BiliFavPage';
import { DebugPage } from './DebugPage';
import { DownloadsPage } from './DownloadsPage';
import { ListenTogetherPage } from './ListenTogetherPage';
import { RecentPage } from './RecentPage';
import { StatsPage } from './StatsPage';
import { SettingsDetailPage } from './SettingsDetailPage';

@Component
export struct MainShell {
  @StorageLink('route.name') routeName: string = Router.MAIN;
  @StorageLink('route.param') routeParam: string = '';
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @State currentTab: number = 0;
  // Theme reactivity: Theme.isDark() reads AppStorage, and ArkUI's
  // minimal-update tracking cannot see through method calls (M7.4 pitfall), so
  // the shell subscribes to both inputs and mirrors the resolved value into
  // @State. Without this, switching dark mode only repainted the settings page
  // (the one page holding an @StorageProp on np.dark_mode).
  @StorageProp('np.dark_mode') @Watch('onThemeChanged') darkModePref: string = 'auto';
  @StorageProp('systemDark') @Watch('onThemeChanged') systemDark: boolean = false;
  @State isDark: boolean = false;

  aboutToAppear(): void {
    this.isDark = Theme.isDark();
    const stored = AppStorage.get<number>(SettingsRepository.KEY_DEFAULT_START_TAB);
    if (stored !== undefined && stored !== null) {
      this.currentTab = stored;
    }
  }

  private onThemeChanged(): void {
    this.isDark = Theme.isDark();
  }

  @Builder
  tabItem(index: number, label: string, icon: Resource) {
    Column({ space: 2 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentTab === index ? Theme.primary(this.isDark) : Theme.textSecondary(this.isDark))
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? Theme.primary(this.isDark) : Theme.textSecondary(this.isDark))
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectTab(index);
    })
  }

  build() {
    if (this.routeName === Router.NOW_PLAYING) {
      NowPlayingPage()
    } else if (this.routeName === Router.PLAYLIST_DETAIL) {
      PlaylistDetailPage()
    } else if (this.routeName === Router.NETEASE_PLAYLIST) {
      NeteasePlaylistPage()
    } else if (this.routeName === Router.BILI_FAV) {
      BiliFavPage()
    } else if (this.routeName === Router.RECENT) {
      RecentPage()
    } else if (this.routeName === Router.STATS) {
      StatsPage()
    } else if (this.routeName === Router.SETTINGS_DETAIL) {
      SettingsDetailPage()
    } else if (this.routeName === Router.DEBUG) {
      DebugPage()
    } else if (this.routeName === Router.DOWNLOADS) {
      DownloadsPage()
    } else if (this.routeName === Router.LISTEN_TOGETHER) {
      ListenTogetherPage()
    } else {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          if (this.currentSongJson.length > 0) {
            MiniPlayer()
          }
          Stack() {
            if (this.currentTab === 0) {
              HomePage()
            } else if (this.currentTab === 1) {
              ExplorePage()
            } else if (this.currentTab === 2) {
              LibraryPage()
            } else {
              SettingsPage()
            }
          }
          .layoutWeight(1)
          .width('100%')

          Row() {
            this.tabItem(0, '首页', $r('app.media.ic_tab_home_24'))
            this.tabItem(1, '探索', $r('app.media.ic_tab_search_24'))
            this.tabItem(2, '资料库', $r('app.media.ic_tab_library_24'))
            this.tabItem(3, '设置', $r('app.media.ic_tab_settings_24'))
          }
          .width('100%')
          .height(88)
          .padding({ top: 6, bottom: 32 })
          .backgroundColor(Theme.surface(Theme.isDark()))
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.background(Theme.isDark()))

        // In-app floating lyric overlay (D4 fallback), floats above content.
        FloatingLyricBar()
          .margin({ top: 46 })
      }
      .width('100%')
      .height('100%')
    }
  }

  private selectTab(index: number): void {
    this.currentTab = index;
    // Goes through SettingsRepository so the choice reaches AppPreferences:
    // the previous AppStorage.setOrCreate wrote the settings key without
    // persisting it, so the default start tab reset on every process restart.
    SettingsRepository.setNumber(SettingsRepository.KEY_DEFAULT_START_TAB, index);
  }
}
