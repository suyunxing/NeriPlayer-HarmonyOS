import { Router } from '../Router';
import { Theme } from '../Theme';
import { HdsNavigation, HdsNavDestination, HdsTabs } from '@kit.UIDesignKit';
import { HdsNavigationAttribute, HdsNavDestinationAttribute, HdsTabsAttribute } from '@kit.UIDesignKit';
import { BP_LG } from '../../util/Breakpoint';
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
import { LegalDocPage } from './LegalDocPage';
import { AlbumPage } from './AlbumPage';

/** Tab 项内容高度 56 + 顶部 6 的视觉间距，与改造前的 tabItem 固定高度一致。 */
const TAB_BAR_CONTENT_VP: number = 62;
/** 侧边导航栏宽度。固定值，不随窗口膨胀 —— 这正是改用 Tabs 要解决的问题。 */
const SIDE_BAR_WIDTH_VP: number = 96;
/** 侧边栏单项高度：22vp 图标 + 10fp 文字，纵向排列后的舒适高度。 */
const SIDE_BAR_ITEM_VP: number = 64;

@Component
export struct MainShell {
  /**
   * 全屏路由栈。Router 只是它的门面（attach 见 aboutToAppear），所以全项目
   * 38 处 Router.push/pop 调用点在这次改造里一行都没动。
   */
  @Provide('NavPathStack') pageStack: NavPathStack = new NavPathStack();
  @StorageLink('player.currentSong') currentSongJson: string = '';
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('systemDark') systemDark: boolean = false;
  /** 由 util/WindowMetrics.ets 按窗口逻辑宽度发布：'sm' | 'md' | 'lg'。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';
  /**
   * 由 util/WindowMetrics.ets 按 TYPE_NAVIGATION_INDICATOR 避让区发布。默认值
   * 是指南常量，只在 WindowMetrics 还没采到样时短暂生效。用 @StorageProp 而不
   * 是直接调函数，同样是为了让最小化更新看得见这个值（见 resolveDark 注释）。
   */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @State currentTab: number = 0;

  /**
   * 与 Theme.isDark() 同一规则，但读自被跟踪的成员，所以 build() 会响应切换。
   * 底部导航栏的背景层曾经写成 Theme.surface(Theme.isDark())，不引用任何可
   * 观察状态，ArkUI 最小化更新因此跳过它 —— 实测深色模式下底部永久残留一条
   * 白色导航栏，切页也修不回来。Index.ets 的 resolveDark 是同一手法。
   */
  private resolveDark(): boolean {
    if (this.darkMode === 'dark') {
      return true;
    }
    if (this.darkMode === 'light') {
      return false;
    }
    return this.systemDark;
  }

  /** lg 断点（≥840vp）改用侧边导航栏，底部不再有固定栏。 */
  private wide(): boolean {
    return this.breakpoint === BP_LG;
  }

  /**
   * 垫在窗口底边以下的色带。窄屏时与 Tab 栏同色，宽屏时与页面底色同色，两种
   * 情况下系统导航条区域都不会出现色块切割。
   */
  private bandColor(): string {
    const dark = this.resolveDark();
    return this.wide() ? Theme.background(dark) : Theme.surface(dark);
  }

  private paramText(param: Object): string {
    return typeof param === 'string' ? param as string : '';
  }

  aboutToAppear(): void {
    Router.attach(this.pageStack);
    const stored = AppStorage.get<number>('np.default_start_tab');
    if (stored !== undefined && stored !== null) {
      this.currentTab = stored;
    }
  }

  aboutToDisappear(): void {
    Router.detach();
  }

  /** Tab 项视觉，底部栏与侧边栏共用；尺寸由外层两个 builder 各自给。 */
  @Builder
  tabBarContent(index: number, label: string, icon: Resource) {
    Column({ space: 2 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentTab === index ? Theme.primary(this.resolveDark()) : Theme.textSecondary(this.resolveDark()))
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? Theme.primary(this.resolveDark()) : Theme.textSecondary(this.resolveDark()))
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  bottomTabBar(index: number, label: string, icon: Resource) {
    Column() {
      this.tabBarContent(index, label, icon)
    }
    .width('100%')
    .height('100%')
    // 指南要求底部固定控件相对系统导航条上抬；抬升量来自真实避让区，没有
    // 导航指示器的形态（2in1 自由窗口）为 0，不再留 28vp 死区。
    .padding({ top: 6, bottom: this.bottomLift })
  }

  @Builder
  sideTabBar(index: number, label: string, icon: Resource) {
    Column() {
      this.tabBarContent(index, label, icon)
    }
    .width('100%')
    .height(SIDE_BAR_ITEM_VP)
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  tabPages() {
    TabContent() {
      HomePage()
    }
    .tabBar(this.wide()
      ? this.sideTabBar(0, '首页', $r('app.media.ic_tab_home_24'))
      : this.bottomTabBar(0, '首页', $r('app.media.ic_tab_home_24')))

    TabContent() {
      ExplorePage()
    }
    .tabBar(this.wide()
      ? this.sideTabBar(1, '探索', $r('app.media.ic_tab_search_24'))
      : this.bottomTabBar(1, '探索', $r('app.media.ic_tab_search_24')))

    TabContent() {
      LibraryPage()
    }
    .tabBar(this.wide()
      ? this.sideTabBar(2, '资料库', $r('app.media.ic_tab_library_24'))
      : this.bottomTabBar(2, '资料库', $r('app.media.ic_tab_library_24')))

    TabContent() {
      SettingsPage()
    }
    .tabBar(this.wide()
      ? this.sideTabBar(3, '设置', $r('app.media.ic_tab_settings_24'))
      : this.bottomTabBar(3, '设置', $r('app.media.ic_tab_settings_24')))
  }

  /**
   * 全屏路由。11 个 if/else 分支从 build() 搬到这里，由 Navigation 按栈顶
   * 路由名调用；转场交给系统标准动效，不再自己拼 TransitionEffect。
   */
  @Builder
  pageMap(name: string, param: Object) {
    HdsNavDestination() {
      if (name === Router.NOW_PLAYING) {
        NowPlayingPage()
      } else if (name === Router.PLAYLIST_DETAIL) {
        PlaylistDetailPage({ playlistId: this.paramText(param) })
      } else if (name === Router.NETEASE_PLAYLIST) {
        NeteasePlaylistPage({ playlistParam: this.paramText(param) })
      } else if (name === Router.BILI_FAV) {
        BiliFavPage({ favParam: this.paramText(param) })
      } else if (name === Router.RECENT) {
        RecentPage()
      } else if (name === Router.STATS) {
        StatsPage()
      } else if (name === Router.SETTINGS_DETAIL) {
        SettingsDetailPage({ section: this.paramText(param) })
      } else if (name === Router.DEBUG) {
        DebugPage()
      } else if (name === Router.DOWNLOADS) {
        DownloadsPage()
      } else if (name === Router.ALBUM) {
        AlbumPage({ albumParam: this.paramText(param) })
      } else if (name === Router.LISTEN_TOGETHER) {
        ListenTogetherPage()
      } else if (name === Router.LEGAL_DOC) {
        // 设置页入口按全屏路由打开，返回键与页内返回按钮都走 Router.pop()。
        LegalDocPage({ doc: this.paramText(param), onClose: () => Router.pop() })
      } else {
        // 未知路由名：给一个空白页而不是崩掉，返回键仍能退出。
        Column().width('100%').height('100%')
      }
    }
    .hideTitleBar(true)
    // NavDestination 默认背景是不透明白：深色模式下内容区以下的系统
    // 导航条区会露出一截白边。显式置透明，条带回落到 Index 的沉浸背景
    // 层（应用底色），与改造前全屏路由的行为一致；页面正文各自的
    // 背景是动态取色，无法用单一 NavDestination 背景逐路由对齐。
    .backgroundColor(Color.Transparent)
    // destination 被销毁时通知常驻的 Tab 页刷新。一处覆盖四条返回路径：
    // Router.pop()、系统返回键、侧滑返回手势、Router.reset() 的 clear()。
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }

  build() {
    HdsNavigation(this.pageStack) {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          if (this.currentSongJson.length > 0) {
            MiniPlayer()
          }

          if (this.wide()) {
            HdsTabs({ barPosition: BarPosition.Start, index: this.currentTab }) {
              this.tabPages()
            }
            .vertical(true)
            .barWidth(SIDE_BAR_WIDTH_VP)
            // 侧边栏必须 Scrollable：Fixed 会把 4 项均分整个窗口高度，
            // 又变回「22vp 图标在 240vp 格子里空转」。
            .barMode(BarMode.Scrollable)
            .barBackgroundColor(Theme.surface(this.resolveDark()))
            // Tabs 容器自身会延伸到窗口物理底边（内部安全区处理），给它
            // 上背景色后，系统导航条那条带跟随 Tab 栏同色，不出现色差
            // 接缝。页面根节点都不透明，surface 只在条带处可见。
            .backgroundColor(this.bandColor())
            .animationDuration(250)
            .scrollable(false)
            .layoutWeight(1)
            .width('100%')
            .onChange((index: number) => {
              this.selectTab(index);
            })
          } else {
            // S3b: HdsTabs 先按原布局语义替换（保留系统材质的接入点
            // barFloatingStyle，等悬浮态避让就绪后再开启，见 S3b-2）。
            HdsTabs({ barPosition: BarPosition.End, index: this.currentTab }) {
              this.tabPages()
            }
            .vertical(false)
            .barHeight(TAB_BAR_CONTENT_VP + this.bottomLift)
            .barMode(BarMode.Fixed)
            .barBackgroundColor(Theme.surface(this.resolveDark()))
            .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            // 同上：容器延伸进系统导航条区域，背景色让条带与 Tab 栏连续。
            .backgroundColor(this.bandColor())
            .animationDuration(250)
            // 不允许左右滑动切页：保持改造前的行为，也避免与首页每日推荐的
            // 横向 Scroll、播放页 WaveformSlider 争手势。
            .scrollable(false)
            .layoutWeight(1)
            .width('100%')
            .onChange((index: number) => {
              this.selectTab(index);
            })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.background(this.resolveDark()))

        // In-app floating lyric overlay (D4 fallback), floats above content.
        FloatingLyricBar()
          .margin({ top: 46 })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    // 显式 Stack：Auto 会在 ≥600vp 时切分栏，把 navBar 压进 240vp 侧栏，
    // 而这里的 navBar 内容是整个 Tab 骨架（完整页面），结构不匹配。大屏适配
    // 由 Tabs.vertical(true) 与各页的 GridRow 承担。
    .mode(NavigationMode.Stack)
    .navDestination((name: string, pageInfos: Object): void => this.pageMap(name, pageInfos))
    .width('100%')
    .height('100%')
  }

  private selectTab(index: number): void {
    if (this.currentTab === index) {
      return;
    }
    this.currentTab = index;
    // 先落 default_start_tab，再发刷新信号：Tab 页用它判断自己是否可见。
    AppStorage.setOrCreate('np.default_start_tab', index);
    Router.notifyReturned();
  }
}
