import { Router } from '../Router';
import { NowPlayingMotion, NowPlayingRect } from '../NowPlayingMotion';
import { PANEL_CURVE } from '../NowPlayingCurves';
import { Theme } from '../Theme';
import { common } from '@kit.AbilityKit';
import { SystemBars } from '../../util/SystemBars';
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
  @StorageLink('ui.nowPlayingShown') @Watch('onNowPlayingRequested') nowPlayingShown: boolean = false;
  @StorageLink('ui.nowPlayingMounted') modalMounted: boolean = false;
  @StorageProp('ui.windowWidthVp') windowWidth: number = 360;
  @StorageProp('ui.windowHeightVp') windowHeight: number = 800;
  @State panelAmount: number = 0;
  // 动画方向（false=展开）：决定各属性动画的时长/时延取向。
  @State closing: boolean = false;
  // 转场进行中：模态内容不响应命中，结算后恢复。
  @State transitioning: boolean = false;
  // 默认兜底值 = 360vp 宽窗口下的药丸典型位置（窗口度量发布后按实测覆盖）。
  @State miniRect: NowPlayingRect = { x: 23, y: 611, width: 314, height: 40 };
  @State originRect: NowPlayingRect = { x: 23, y: 611, width: 314, height: 40 };
  // 模态内容区的窗口坐标原点：面板/迷你条副本用窗口坐标（globalPosition 实测
  // 的 mini 矩形）计算，但 position() 相对模态内容区原点——若模态因安全区有
  // 偏移，直接套用会整体错位（展开起点/收起终点与迷你条不符）。在模态根节点
  // 实测原点后做自校正，模态铺满窗口时该值为 (0,0)，两种布局下都成立。
  @State modalOriginX: number = 0;
  @State modalOriginY: number = 0;
  private startDelayTimer: number = -1;
  private settleTimer: number = -1;
  private modalReady: boolean = false;
  private pendingDismiss: DismissContentCoverAction | undefined = undefined;

  private clearSettle(): void {
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
  }

  /**
   * 转场结算：几何全部由原生属性动画驱动（无 JS 逐帧步进，见 NowPlayingCurves），
   * JS 侧只需在「时长 + 行错峰 + 余量」之后收尾——展开恢复命中，收起卸载模态
   * 并执行挂起的系统 dismiss。中途反向（重开）会重置该计时器。
   */
  private armSettle(durationMs: number): void {
    this.clearSettle();
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1;
      this.transitioning = false;
      if (!this.nowPlayingShown) {
        this.modalReady = false;
        this.modalMounted = false;
        const dismiss = this.pendingDismiss;
        this.pendingDismiss = undefined;
        dismiss?.dismiss();
      }
    }, durationMs + NowPlayingMotion.ROW_SETTLE_MS + 80);
  }

  private onNowPlayingRequested(): void {
    if (this.nowPlayingShown && !this.modalMounted) {
      this.originRect = this.miniRect;
      this.panelAmount = 0;
      this.closing = false;
      this.transitioning = true;
      this.modalMounted = true;
      // 首帧推进交给 onAppear 的延迟触发（挂建耗时 > 1 tick 时立即翻开会
      // 跳过起始帧）；这里只负责挂载。
      return;
    }
    if (this.nowPlayingShown) {
      this.pendingDismiss = undefined;
    }
    this.closing = !this.nowPlayingShown;
    this.transitioning = true;
    this.panelAmount = this.nowPlayingShown ? 1 : 0;
    this.armSettle(this.nowPlayingShown ? NowPlayingMotion.EXPAND_MS : NowPlayingMotion.COLLAPSE_MS);
  }

  private static validRect(area: Area): NowPlayingRect | undefined {
    const x = Number(area.globalPosition.x);
    const y = Number(area.globalPosition.y);
    const width = Number(area.width);
    const height = Number(area.height);
    // Number(undefined) 为 NaN：初次布局回调或异常度量直接丢弃，保留上一
    // 次有效矩形，避免 NaN 传播到 position() 后组件落到 0,0。
    if (Number.isFinite(x) && Number.isFinite(y) && width > 0 && height > 0) {
      return { x: x, y: y, width: width, height: height };
    }
    return undefined;
  }

  /**
   * HdsTabs 迷你条槽位的坐标标定。槽位内 builder 的 onAreaChange 返回的是
   * 槽位布局矩形（全宽、贴在悬浮栏底部），而可见的迷你条药丸被 HdsTabs 内部
   * 位移/裁剪到悬浮栏上部——这类变换不触发 onAreaChange，所以测量值永远偏左
   * 下。Y 向偏移按真机实测标定；X/宽不依赖槽位（槽位宽度在两次会话间不稳定），
   * 直接用药丸的对称设计值：左右边距各 23vp（barSideMargin 16 + 槽位内边距 7），
   * 宽 = 窗口宽 − 46。若 Hds 调整悬浮栏内部布局需重标 Y 偏移。
   */
  private static readonly PILL_MARGIN_X: number = 23;
  private static readonly PILL_OFFSET_Y: number = -93;

  private static toPillRect(slot: NowPlayingRect, windowWidth: number): NowPlayingRect {
    return {
      x: MainShell.PILL_MARGIN_X,
      y: slot.y + MainShell.PILL_OFFSET_Y,
      width: Math.max(40, windowWidth - 2 * MainShell.PILL_MARGIN_X),
      height: slot.height
    };
  }

  private panelRect(): NowPlayingRect {
    return NowPlayingMotion.panel(this.panelAmount, this.originRect, this.windowWidth, this.windowHeight);
  }

  /**
   * 官方 FAQ 对 HdsNavigation + HdsTabs 组合的要求：每个 Tab 的滚动容器持独立
   * Scroller，标题栏只绑定当前可见 Tab 的那一个；实例经构造参数下发给各 Tab 页。
   */
  private tabScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];

  /** 官方 HdsTabsMiniBar 槽位：无歌时留空，有歌渲染紧凑 MiniPlayer。 */
  @Builder
  miniBarBuilder() {
    if (this.currentSongJson.length > 0) {
      MiniPlayer({ compact: true, onMeasured: (area: Area): void => {
        const rect = MainShell.validRect(area);
        if (rect !== undefined) {
          this.miniRect = MainShell.toPillRect(rect, this.windowWidth);
        }
      } })
        // 模态展开期间隐藏（面板占据药丸位置）；收起后半段直接淡入真实
        // 迷你条——它就是"正确位置"本身，模态卸载时零差异、不再闪烁。
        .opacity(this.miniBarHidden() ? 0 : 1)
        .animation(this.miniBarHidden()
          ? { duration: 0 }
          : { duration: 220, delay: Math.round(NowPlayingMotion.COLLAPSE_MS * 0.55), curve: Curve.EaseOut })
        .accessibilityLevel(this.miniBarHidden() ? 'no-hide-descendants' : 'auto')
        .hitTestBehavior(this.miniBarHidden() ? HitTestMode.None : HitTestMode.Default)
    }
  }

  /**
   * 真实迷你条在转场期间的隐藏条件：模态挂载且处于展开方向（面板占位）。
   * 收起方向（closing）时提前可见并淡入；未挂载时常态可见。
   */
  private miniBarHidden(): boolean {
    return this.modalMounted && !this.closing;
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
    if (this.startDelayTimer >= 0) {
      clearTimeout(this.startDelayTimer);
      this.startDelayTimer = -1;
    }
    this.clearSettle();
    this.modalReady = false;
    this.pendingDismiss = undefined;
    this.modalMounted = false;
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
    // 首页滚动内容要钻到状态栏后被标题栏渐变模糊覆盖：TabContent 默认
    // clip(true) 会把向上滚出视口的内容裁掉（官方 FAQ faqs-arkui-1095），
    // 关裁剪放行子层向上延伸。
    .clip(false)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .tabBar(this.wide()
      ? this.sideTabBar(0, '首页', $r('app.media.ic_tab_home_24'))
      : this.bottomTabBar(0, '首页', $r('app.media.ic_tab_home_24')))

    TabContent() {
      ExplorePage({ scroller: this.tabScrollers[1] })
    }
    // 与首页 TabContent 同理：放行页内滚动内容向上穿透到状态栏后被渐变模糊覆盖。
    .clip(false)
    .tabBar(this.wide()
      ? this.sideTabBar(1, '探索', $r('app.media.ic_tab_search_24'))
      : this.bottomTabBar(1, '探索', $r('app.media.ic_tab_search_24')))

    TabContent() {
      LibraryPage({ scroller: this.tabScrollers[2] })
    }
    // 同探索页：放行内容向上穿透。
    .clip(false)
    .tabBar(this.wide()
      ? this.sideTabBar(2, '资料库', $r('app.media.ic_tab_library_24'))
      : this.bottomTabBar(2, '资料库', $r('app.media.ic_tab_library_24')))

    TabContent() {
      SettingsPage({ scroller: this.tabScrollers[3] })
    }
    // 同探索页：放行内容向上穿透。
    .clip(false)
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
   * 一镜到底播放页的模态内容。动画分工：modalTransition NONE 关掉系统推拉；
   * 面板几何（mini 矩形 → 全窗）由 MainShell 的 panelAmount 目标值驱动
   * （原生属性动画 + NowPlayingCurves 的先慢后快曲线），内容行
   * 的分层弹入由 NowPlayingMotion 纯函数按同一进度计算（见 NowPlayingPage）。
   */
  @Builder
  nowPlayingBuilder() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        NowPlayingPage({ transitionProgress: this.panelAmount, closing: this.closing })
          .width(this.windowWidth)
          .height(this.windowHeight)
          // 内层反向位移必须与外框共用同一动画规格：收起瞬间它要从
          // (0,0) 同步滑到 (-mini.x, -mini.y)，否则内容瞬移（外框还近乎
          // 全屏时页面内容先跳到左上角，再随外框收缩"从上方落下"）。
          .translate({ x: -this.panelRect().x, y: -this.panelRect().y })
          .animation({
            duration: this.closing ? NowPlayingMotion.COLLAPSE_MS : NowPlayingMotion.EXPAND_MS,
            curve: PANEL_CURVE
          })
          .hitTestBehavior(!this.transitioning && this.panelAmount === 1
            ? HitTestMode.Default : HitTestMode.None)
      }
      .width(this.panelRect().width)
      .height(this.panelRect().height)
      .borderRadius(NowPlayingMotion.panelRadius(this.panelAmount))
      .clip(true)
      .translate({ x: this.panelRect().x - this.modalOriginX, y: this.panelRect().y - this.modalOriginY })
      // 面板几何整体走原生属性动画（先慢后快），render 管线逐帧驱动。
      .animation({
        duration: this.closing ? NowPlayingMotion.COLLAPSE_MS : NowPlayingMotion.EXPAND_MS,
        curve: PANEL_CURVE
      })
      // 透明度渐变挂在几何动画之后（各自捕获自己的属性段）：展开初期
      // ~90ms 快速实体化，收缩末段 ~140ms 随落地淡出，避免生硬的出入现。
      .opacity(this.panelAmount)
      .animation(this.closing
        ? {
          duration: Math.round(NowPlayingMotion.COLLAPSE_MS * 0.35),
          delay: Math.round(NowPlayingMotion.COLLAPSE_MS * 0.65),
          curve: Curve.EaseIn
        }
        : {
          duration: Math.round(NowPlayingMotion.EXPAND_MS * 0.3),
          curve: Curve.EaseOut
        })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      const rect = MainShell.validRect(area);
      if (rect !== undefined) {
        this.modalOriginX = rect.x;
        this.modalOriginY = rect.y;
      }
    })
  }

  build() {
    // 外层 Stack 只为一镜到底服务：播放页模态展开/收起时把整个壳层（含
    // HdsNavigation 标题栏）压暗，模态本身透明，主页从卡片边缘透出。
    Stack() {
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
            // 同 TabContent：放行首页内容向上穿透到状态栏后被渐变模糊覆盖。
            .clip(false)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
            // 同 TabContent：放行首页内容向上穿透到状态栏后被渐变模糊覆盖。
            .clip(false)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        // In-app floating lyric overlay (D4 fallback), floats above content;
        // 顶部让位 MINI 标题栏（56vp），不再压进标题栏材质区。
        FloatingLyricBar()
          .margin({ top: TITLEBAR_SPACE_VP + 4 })

        // 手势条渐变遮罩：内容真实延伸进底部安全区后不再垫纯色，仅叠一层
        // 由上到下渐透明的页面底色渐变，保证导航指示条区域的可读性；不拦
        // 截触摸，播放页模态展开时整层被模态盖住（模态自身无渐变）。
        Column()
          .width('100%')
          .height(this.bottomLift + 8)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [
              [Theme.withAlpha(Theme.background(this.resolveDark()), 0xD9), 0],
              [0x00000000, 1]
            ]
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          .hitTestBehavior(HitTestMode.None)
          .position({ x: 0, y: this.windowHeight - this.bottomLift - 8 })

        // MiniPlayer 回归官方 HdsTabsMiniBar 槽位（用户决策）：槽位高度
        // 系统固定，以缩小播放按钮视觉圆（30vp，触控热区仍 40vp）适配。
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
    // 顶部沉浸：标题栏背板（静止底色 + 滚动渐变模糊）向上延伸进状态栏与
    // 挖孔区，顶到屏幕物理顶端。expandSafeArea 只扩绘制区不触发二次布局，
    // 标题内容仍停在状态栏下方（官方「沉浸光感」模板做法），静止态背板与
    // 页面底色同色，状态栏区域无接缝。
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 一镜到底播放页：全屏模态挂在壳层根上（盖住 Tab 骨架与悬浮栏）。
    // modalTransition NONE + 透明背板：模态自身不做系统推拉，动画由
    // panelAmount 目标值驱动（面板几何 + 内容分层 + MiniBar 衔接），
    // 原生属性动画提供先慢后快与回弹手感，JS 只做结算计时。
    // 返回键/侧滑先到 onWillDismiss：记录 dismiss 动作并请求收起，进度
    // 归零后再 dismiss() 兜底（官方要求注册后必须调用才会真正关闭）。
    // onDisappear 收敛开关并通知常驻 Tab 页刷新，覆盖收起与 push 专辑前
    // 收起等全部关闭路径（替代原 NOW_PLAYING destination 的 onWillDisappear）。
    // enableSafeArea 保持默认 false（官方语义：内容不受安全区限制、不避让
    // 状态栏与导航条）——状态栏/导航条区域从头到尾属于播放页自己的背景层，
    // 几何转场的飞行矩形才能与最终铺满窗口的矩形一致，沉浸不被系统栏条带
    // 打断；页面正文由 NowPlayingPage 用发布的 ui.topInsetVp/ui.bottomLiftVp
    // 自行避让。
    .bindContentCover(this.modalMounted, this.nowPlayingBuilder(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      enableSafeArea: false,
      onAppear: () => {
        this.modalReady = true;
        // 延迟约一帧再翻转目标值：挂建 NowPlayingPage 耗时 > 1 tick 时立即
        // 翻开会跳过起始帧（首帧直接从进度 > 0 画出，起点错位观感）。
        if (this.startDelayTimer >= 0) {
          clearTimeout(this.startDelayTimer);
        }
        this.startDelayTimer = setTimeout(() => {
          this.startDelayTimer = -1;
          this.transitioning = true;
          this.panelAmount = 1;
          this.armSettle(NowPlayingMotion.EXPAND_MS);
        }, 16);
      },
      onDisappear: () => {
        // A new open request may arrive while the previous modal is unmounting.
        if (this.modalMounted || this.nowPlayingShown) {
          return;
        }
        // 注意：这里不能发 Router.notifyReturned()——普通收起播放页不改变
        // 任何 Tab 页数据，触发刷新会让首页列表重载、出现「重新加载式闪屏」。
        // 路由级返回的刷新仍由各 NavDestination 自身的 onDisappear 覆盖。
        // 播放页按封面取色改写过系统栏图标颜色，收起动画结束后交回主页
        // 主题配色；立即恢复会让飞行半程的图标压在错误的背景上。
        const context = this.getUIContext().getHostContext();
        if (context !== undefined) {
          SystemBars.apply(context as common.UIAbilityContext, this.resolveDark());
        }
      },
      onWillDismiss: (action: DismissContentCoverAction) => {
        this.pendingDismiss = action;
        Router.pop();
      }
    })

    // 一镜到底背板：模态展开/收起期间主页整体压暗（参考实现为背景色 wash，
    // 悬浮 Tab 栏与迷你条一并压暗）。透明度绑定 nowPlayingShown，在 Router
    // 的弹簧 animateTo 上下文里随共享元素几何飞行同步插值；不拦截命中测试，
    // 模态收起后对主页交互零影响。
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.withAlpha(Theme.background(this.resolveDark()), 0x99))
      .opacity(this.nowPlayingShown ? 1 : 0)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .hitTestBehavior(HitTestMode.None)
    }
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
