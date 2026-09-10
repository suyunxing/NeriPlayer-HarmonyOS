import { Router } from '../Router';
import { Theme } from '../Theme';
import { HdsTabs, HdsBarLayoutMode, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HdsTabsAttribute } from '@kit.UIDesignKit';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, BlurStrategy } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { HdsLight } from '../theme/HdsLight';
import { AccentScheme } from '../theme/AccentScheme';
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
/** HdsNavigationTitleMode.MINI 标题栏标准高度：四个 Tab 页内容顶部让位同高。 */
const TITLEBAR_SPACE_VP: number = 56;
/** 各 Tab 在壳层标题栏的标题。 */
const TAB_TITLES: string[] = ['NeriPlayer', '探索', '资料库', '设置'];

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
  // 封面 scheme 驱动悬浮 Tab 栏的 lightColor（光晕色）与系统材质档位。
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State currentTab: number = 0;
  /**
   * 全屏播放页模态开关：Router 在 animateTo 闭包里翻转（AppStorage 同名
   * key），下方 bindContentCover 消费。字面量须与 Router.KEY_NOW_PLAYING_SHOWN
   * 一致（装饰器参数只收字面量）。
   */
  @StorageLink('ui.nowPlayingShown') nowPlayingShown: boolean = false;
  /**
   * 官方 FAQ 对 HdsNavigation + HdsTabs 组合的要求：每个 Tab 的滚动容器持独立
   * Scroller，标题栏只绑定当前可见 Tab 的那一个；实例经构造参数下发给各 Tab 页。
   */
  private tabScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];

  /** 官方 HdsTabsMiniBar 槽位：无歌时留空，有歌渲染紧凑 MiniPlayer。 */
  @Builder
  miniBarBuilder() {
    if (this.currentSongJson.length > 0) {
      MiniPlayer({ compact: true })
    }
  }

  /** 悬浮 Tab 栏的系统沉浸材质：设备不支持时保持 undefined（自绘玻璃兜底）。 */
  private systemMaterialEffect(): SystemMaterialParams | undefined {
    if (!HdsLight.immersiveSupported() && !HdsLight.adaptiveSupported()) {
      return undefined;
    }
    const params: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    return params;
  }


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
    Router.attach(this.pageStack, this.getUIContext());
    // np.start_page ('last' | '0'..'3') is the explicit 启动页 choice; the
    // legacy np.default_start_tab keeps tracking the last visited tab and is
    // what 'last' resolves to.
    const startPage = AppStorage.get<string>('np.start_page') ?? 'last';
    const parsed = Number(startPage);
    if (startPage !== 'last' && !Number.isNaN(parsed) && parsed >= 0 && parsed <= 3) {
      this.currentTab = parsed;
      return;
    }
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
      HomePage({ scroller: this.tabScrollers[0] })
    }
    .tabBar(this.wide()
      ? this.sideTabBar(0, '首页', $r('app.media.ic_tab_home_24'))
      : this.bottomTabBar(0, '首页', $r('app.media.ic_tab_home_24')))

    TabContent() {
      ExplorePage({ scroller: this.tabScrollers[1] })
    }
    .tabBar(this.wide()
      ? this.sideTabBar(1, '探索', $r('app.media.ic_tab_search_24'))
      : this.bottomTabBar(1, '探索', $r('app.media.ic_tab_search_24')))

    TabContent() {
      LibraryPage({ scroller: this.tabScrollers[2] })
    }
    .tabBar(this.wide()
      ? this.sideTabBar(2, '资料库', $r('app.media.ic_tab_library_24'))
      : this.bottomTabBar(2, '资料库', $r('app.media.ic_tab_library_24')))

    TabContent() {
      SettingsPage({ scroller: this.tabScrollers[3] })
    }
    .tabBar(this.wide()
      ? this.sideTabBar(3, '设置', $r('app.media.ic_tab_settings_24'))
      : this.bottomTabBar(3, '设置', $r('app.media.ic_tab_settings_24')))
  }

  /**
   * 全屏路由。10 个 if/else 分支从 build() 搬到这里，由 Navigation 按栈顶
   * 路由名调用；转场交给系统标准动效，不再自己拼 TransitionEffect。
   * 播放页不在此列：一镜到底改由 build() 根上的 bindContentCover 全屏模态
   * 承载（NOW_PLAYING 不再入栈，见 Router 注释）。
   */
  @Builder
  pageMap(name: string, param: Object) {
    // S4 实测：HdsNavDestination 在模拟器上只渲染标题栏 chrome、不挂载内容
    // 子树（与 S0 spike S7 探针一致），路由页回退标准 NavDestination；
    // HdsNavigation 外壳与 HdsTabs 悬浮栏保留。
    NavDestination() {
      if (name === Router.PLAYLIST_DETAIL) {
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
    //（播放页模态的同类信号在 bindContentCover 的 onDisappear 发出。）
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }

  /**
   * 一镜到底播放页的模态内容。动画分工：modalTransition NONE 关掉系统推拉，
   * 封面几何飞行由 Router 的 animateTo + geometryTransition('np.cover') 提供，
   * 页面正文淡入淡出由 NowPlayingPage 根节点的 OPACITY 转场提供。
   */
  @Builder
  nowPlayingBuilder() {
    NowPlayingPage()
  }

  build() {
    // S4 曾因「模拟器上 navDestination 内容子树不挂载」回退标准 Navigation；
    // 真机复测无此问题（2026-09-10 用户确认），外壳按官方标准启用 HdsNavigation：
    // MINI 标题栏统一承载四个 Tab 的标题（各 Tab 页内大标题随之移除，避免双标题），
    // GRADIENT_BLUR 渐变模糊随内容滚过标题栏生效，滚动绑定按官方 FAQ 只挂当前 Tab。
    HdsNavigation(this.pageStack) {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
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
            // S3b-2: 悬浮胶囊 Tab 栏 + 官方 MiniBar 槽位。barOverlap 后
            // 内容延伸到栏下，四个 Tab 页的滚动尾部加了 FLOAT_TAB_CLEARANCE
            // 避让；系统材质在不支持的设备上回落自绘玻璃。
            HdsTabs({ barPosition: BarPosition.End, index: this.currentTab }) {
              this.tabPages()
            }
            .vertical(false)
            .barMode(BarMode.Fixed)
            .barOverlap(true)
            .barFloatingStyle({
              barSideMargin: 16,
              barBottomMargin: this.bottomLift + 8,
              lightColor: this.coverScheme.light.primary,
              gradientMask: { maskColor: Theme.withAlpha(Theme.background(this.resolveDark()), 0x99), maskHeight: 92 },
              miniBar: {
                miniBarBuilder: (): void => {
                  this.miniBarBuilder()
                },
                enableMiniBarBackground: true,
                barLayoutMode: HdsBarLayoutMode.VERTICAL
              },
              systemMaterialEffect: this.systemMaterialEffect()
            })
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

        // In-app floating lyric overlay (D4 fallback), floats above content;
        // 顶部让位 MINI 标题栏（56vp），不再压进标题栏材质区。
        FloatingLyricBar()
          .margin({ top: TITLEBAR_SPACE_VP + 4 })

        // MiniPlayer 回归官方 HdsTabsMiniBar 槽位（用户决策）：槽位高度
        // 系统固定，以缩小播放按钮视觉圆（30vp，触控热区仍 40vp）适配。
      }
      .width('100%')
      .height('100%')
    }
    // 标题栏只绑当前可见 Tab 的 Scroller（官方 FAQ：多 Tab 共用外壳时动态换绑，
    // 避免多滚动容器手势冲突导致模糊失效或抖动）。
    .bindToScrollable([this.tabScrollers[this.currentTab]])
    .titleMode(HdsNavigationTitleMode.MINI)
    // 壳层是 Tab 骨架的根，自身无可返回的上级路由：隐藏系统默认返回按钮。
    .hideBackButton(true)
    .titleBar({
      content: {
        title: { mainTitle: TAB_TITLES[this.currentTab] }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(8)
        },
        blurStrategy: BlurStrategy.ADAPTIVE,
        // 静止态背板与页面底色同色（无接缝），滚动后过渡为透出系统渐变
        // 模糊材质的透明背板；标题色跟随应用主题，不取系统默认。
        originalStyle: {
          backgroundStyle: { backgroundColor: Theme.background(this.resolveDark()) },
          contentStyle: {
            titleStyle: { mainTitleColor: Theme.textPrimary(this.resolveDark()) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: Theme.textPrimary(this.resolveDark()) }
          }
        },
        systemMaterialEffect: this.systemMaterialEffect()
      }
    })
    // 显式 Stack：Auto 会在 ≥600vp 时切分栏，把 navBar 压进 240vp 侧栏，
    // 而这里的 navBar 内容是整个 Tab 骨架（完整页面），结构不匹配。大屏适配
    // 由 Tabs.vertical(true) 与各页的 GridRow 承担。
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    // 一镜到底播放页：全屏模态挂在壳层根上（盖住 Tab 骨架与悬浮栏）。
    // modalTransition NONE + 透明背板：模态自身不做系统推拉动画，动画全部
    // 交给 Router 的 animateTo（封面 geometryTransition 飞行）与页面根节点的
    // OPACITY 转场。返回键/侧滑先到 onWillDismiss：转交 Router.pop() 走带
    // 动画收起，再 dismiss() 兜底（官方要求注册后必须调用才会真正关闭）。
    // onDisappear 收敛开关并通知常驻 Tab 页刷新，覆盖收起与 push 专辑前
    // 收起等全部关闭路径（替代原 NOW_PLAYING destination 的 onWillDisappear）。
    .bindContentCover(this.nowPlayingShown, this.nowPlayingBuilder(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      // 模态内容限制在安全区内（对齐原 NavDestination 的默认避让），页面
      // 背景层自带的 expandSafeArea 仍可延伸进系统栏。
      enableSafeArea: true,
      onDisappear: () => {
        this.nowPlayingShown = false;
        Router.notifyReturned();
      },
      onWillDismiss: (action: DismissContentCoverAction) => {
        Router.pop();
        action.dismiss();
      }
    })
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
