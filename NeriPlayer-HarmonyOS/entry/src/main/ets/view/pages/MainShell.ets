import { Router } from '../Router';
import { Theme } from '../Theme';
import { MotionSpec } from '../theme/MotionSpec';
import { MotionCurves } from '../theme/MotionCurves';
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
  // Armed after the first build so the mini player slides in when playback
  // *starts*, but not on a cold start that restores a song: ArkUI transition
  // effects fire on initial mount too, while Android's AnimatedVisibility
  // only animates on state change (NeriApp.kt:3641-3656).
  @State miniplayerTransitionArmed: boolean = false;
  // Same arming for route transitions: a cold start that lands directly on a
  // route (e.g. the AVSession card launch) must not animate its first mount
  // — Android's AnimatedVisibility/AnimatedContent only animate on change.
  @State routeTransitionArmed: boolean = false;

  // Slide distance for the mini player appear/disappear: half the ~70vp
  // player, matching Android's slideInVertically { it / 2 }.
  private static readonly MINIPLAYER_SLIDE_VP: number = 35;

  aboutToAppear(): void {
    const stored = AppStorage.get<number>(SettingsRepository.KEY_DEFAULT_START_TAB);
    if (stored !== undefined && stored !== null) {
      this.currentTab = stored;
    }
    setTimeout(() => {
      this.miniplayerTransitionArmed = true;
      this.routeTransitionArmed = true;
    }, 0);
  }

  private routeDirection(): string {
    const value = AppStorage.get<string>(Router.KEY_DIRECTION);
    return value === 'push' || value === 'pop' ? value : 'none';
  }

  /**
   * Route pages move as a vertical deck (the NeriApp.kt:462-653 metaphor):
   * a push slides the new page up from the bottom edge, a pop slides the
   * returned-to page down from the top edge. Timings port
   * NeriApp.kt:304-305 (220ms open / 240ms close, FastOutSlowIn); the
   * NowPlaying layer keeps its own 300/250ms plus a 150ms fade
   * (NeriApp.kt:3679-3689). 'y: 100%' resolves against the page's own
   * height, so the slide is full-screen without vp constants.
   *
   * The disappearing side always fades rather than sliding: ArkUI reads a
   * removed branch's transition attribute from its last render (the branch
   * is not re-evaluated before removal), so a direction-aware disappear
   * would act on a stale direction. A fade reads correctly under either
   * stacking order of the entering/exiting nodes.
   */
  private routeTransition(isNowPlaying: boolean): TransitionEffect {
    if (!this.routeTransitionArmed) {
      return TransitionEffect.IDENTITY;
    }
    const popping = this.routeDirection() === 'pop';
    const curve = MotionCurves.fastOutSlowIn();
    const enterFrom: string = popping ? '-100%' : '100%';
    const slideMs = isNowPlaying
      ? (popping ? MotionSpec.NOWPLAYING_EXIT_SLIDE_MS : MotionSpec.NOWPLAYING_ENTER_SLIDE_MS)
      : (popping ? MotionSpec.DETAIL_CLOSE_MS : MotionSpec.DETAIL_OPEN_MS);
    const exitFadeMs = isNowPlaying ? MotionSpec.NOWPLAYING_EXIT_SLIDE_MS : MotionSpec.DETAIL_CLOSE_MS;
    let appear: TransitionEffect = TransitionEffect.translate({ y: enterFrom })
      .animation({ duration: slideMs, curve: curve });
    if (isNowPlaying) {
      appear = appear.combine(TransitionEffect.opacity(0)
        .animation({ duration: MotionSpec.NOWPLAYING_FADE_MS, curve: curve }));
    }
    const disappear: TransitionEffect = TransitionEffect.opacity(0)
      .animation({ duration: exitFadeMs, curve: curve });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  private miniplayerTransition(): TransitionEffect {
    if (!this.miniplayerTransitionArmed) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: MainShell.MINIPLAYER_SLIDE_VP })
        .animation({ duration: MotionSpec.MINIPLAYER_ENTER_SLIDE_MS, curve: MotionCurves.fastOutSlowIn() })
        .combine(TransitionEffect.opacity(0)
          .animation({ duration: MotionSpec.MINIPLAYER_ENTER_FADE_MS, curve: MotionCurves.fastOutSlowIn() })),
      TransitionEffect.translate({ y: MainShell.MINIPLAYER_SLIDE_VP })
        .animation({ duration: MotionSpec.MINIPLAYER_EXIT_SLIDE_MS, curve: MotionCurves.fastOutSlowIn() })
        .combine(TransitionEffect.opacity(0)
          .animation({ duration: MotionSpec.MINIPLAYER_EXIT_FADE_MS, curve: MotionCurves.fastOutSlowIn() }))
    );
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
    // Themed backdrop for the route transitions: while a page slides in
    // from an edge, the uncovered strip shows this background instead of an
    // unthemed flash. Wrapper Columns carry the transitions because custom
    // components cannot chain .transition directly.
    Stack() {
      if (this.routeName === Router.NOW_PLAYING) {
        Column() {
          NowPlayingPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(true))
      } else if (this.routeName === Router.PLAYLIST_DETAIL) {
        Column() {
          PlaylistDetailPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.NETEASE_PLAYLIST) {
        Column() {
          NeteasePlaylistPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.BILI_FAV) {
        Column() {
          BiliFavPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.RECENT) {
        Column() {
          RecentPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.STATS) {
        Column() {
          StatsPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.SETTINGS_DETAIL) {
        Column() {
          SettingsDetailPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.DEBUG) {
        Column() {
          DebugPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.DOWNLOADS) {
        Column() {
          DownloadsPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else if (this.routeName === Router.LISTEN_TOGETHER) {
        Column() {
          ListenTogetherPage()
        }
        .width('100%')
        .height('100%')
        .transition(this.routeTransition(false))
      } else {
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            if (this.currentSongJson.length > 0) {
              // Wrapper Column: custom components cannot carry .transition
              // directly.
              Column() {
                MiniPlayer()
              }
              .transition(this.miniplayerTransition())
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
        .transition(this.routeTransition(false))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(this.isDark))
  }

  private selectTab(index: number): void {
    this.currentTab = index;
    // Goes through SettingsRepository so the choice reaches AppPreferences:
    // the previous AppStorage.setOrCreate wrote the settings key without
    // persisting it, so the default start tab reset on every process restart.
    SettingsRepository.setNumber(SettingsRepository.KEY_DEFAULT_START_TAB, index);
  }
}
