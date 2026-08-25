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
  // Resolved dark flag, republished by Theme.refreshIsDark() whenever
  // np.dark_mode or the system colorMode changes. Subscribing to it here —
  // rather than calling Theme.isDark() inside the expressions below — is what
  // makes the shell actually repaint: an AppStorage read hidden inside a
  // method call is invisible to ArkUI's minimal-update tracking (M7.4).
  @StorageProp('theme.isDark') isDark: boolean = false;

  aboutToAppear(): void {
    const stored = AppStorage.get<number>(SettingsRepository.KEY_DEFAULT_START_TAB);
    if (stored !== undefined && stored !== null) {
      this.currentTab = stored;
    }
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
          .backgroundColor(Theme.surface(this.isDark))
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.background(this.isDark))

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
