// SPDX-License-Identifier: GPL-3.0

import { Router } from '../Router';
import { DownloadEngine, DownloadEngineListener } from '../../download/DownloadEngine';
import { SongItem } from '../../model/SongItem';
import { NowPlayingMotion, NowPlayingRect } from '../NowPlayingMotion';
import { PANEL_CURVE } from '../NowPlayingCurves';
import { Theme } from '../Theme';
import { common } from '@kit.AbilityKit';
import { SystemBars } from '../../util/SystemBars';
import { HdsTabs, HdsBarLayoutMode, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HdsTabsAttribute } from '@kit.UIDesignKit';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, BlurStrategy } from '@kit.UIDesignKit';
import { ezCustomTransition } from '@hmanimations/ezcustomtransition';
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
import { NowPlayingRoutePage } from './NowPlayingRoutePage';
import { PlaylistDetailPage } from './PlaylistDetailPage';
import { NeteasePlaylistPage } from './NeteasePlaylistPage';
import { BiliFavPage } from './BiliFavPage';
import { DebugPage } from './DebugPage';
import { LongTakeSpikePage } from './LongTakeSpikePage';
import { DownloadsPage } from './DownloadsPage';
import { ListenTogetherPage } from './ListenTogetherPage';
import { RecentPage } from './RecentPage';
import { StatsPage } from './StatsPage';
import { SettingsDetailPage } from './SettingsDetailPage';
import { LegalDocPage } from './LegalDocPage';
import { AlbumPage } from './AlbumPage';
import { ArtistPage } from './ArtistPage';

/** Tab 项内容高度 56 + 顶部 6 的视觉间距，与改造前的 tabItem 固定高度一致。 */
const TAB_BAR_CONTENT_VP: number = 62;
/** 悬浮 Tab 栏左右边距：barFloatingStyle.barSideMargin 与 dock 态迷你条共用同一值。 */
const FLOAT_BAR_SIDE_MARGIN_VP: number = 16;
/** 悬浮 Tab 栏底部边距的呼吸增量：barBottomMargin = bottomLift + 此值。 */
const FLOAT_BAR_BOTTOM_GAP_VP: number = 8;
/** dock 态迷你条高度 = 非紧凑 MiniPlayer 胶囊高度（进度条 2 + 内容行 60）。 */
const DOCK_MINI_HEIGHT_VP: number = 62;
/**
 * 槽位药丸顶边相对 dock 条顶边的上移量。真机视频三轮标定（2026-09-21）：
 * 104.5vp 差 10px 不到位 → 108.5vp 过 2px（+4vp 实测位移 9.9px，与
 * 2.483px/vp 线性一致）→ 取 107.5vp。药丸与 dock 都由壳层定位、共享同一
 * 坐标映射，此相对量自动跟随 bottomLift/窗口尺寸变化；若 Hds 内部布局
 * 变更，按同法（冻结帧落点与槽位内容之差 × 2.483px/vp 修正）重测。
 */
const PILL_RISE_FROM_DOCK_VP: number = 107.5;
/** 槽位药丸高度：HdsTabs 玻璃壳实测 94px ≈ 38vp，取设计值 40。 */
const PILL_HEIGHT_VP: number = 40;
/** 子页 dock 态迷你条的几何迁移时长：与 NavDestination 系统转场同一量级。 */
const DOCK_MORPH_MS: number = 350;

/**
 * 下载完成提示的壳层订阅：引擎回调无 UI 上下文，由常驻的 MainShell 统一弹
 * toast（DownloadsPage 只刷列表不弹提示，避免两处重复）。
 */
class ShellDownloadListener implements DownloadEngineListener {
  private shell: WeakRef<MainShell> | null = null;

  attach(shell: MainShell): void {
    this.shell = new WeakRef<MainShell>(shell);
  }

  onTasksChanged(): void {
    // 任务列表刷新由各页面自行订阅。
  }

  onDownloadCompleted(song: SongItem, fromCache: boolean): void {
    const target = this.shell !== null ? this.shell.deref() : undefined;
    if (target === undefined) {
      return;
    }
    const message = fromCache ? `已在下载库中：${song.displayName}` : `下载完成：${song.displayName}`;
    target.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
  }
}
/** 侧边导航栏宽度。固定值，不随窗口膨胀 —— 这正是改用 Tabs 要解决的问题。 */
const SIDE_BAR_WIDTH_VP: number = 96;
/** 侧边栏单项高度：22vp 图标 + 10fp 文字，纵向排列后的舒适高度。 */
const SIDE_BAR_ITEM_VP: number = 64;
/** HdsNavigationTitleMode.MINI 标题栏标准高度：四个 Tab 页内容顶部让位同高。 */
const TITLEBAR_SPACE_VP: number = 56;
/** 各 Tab 在壳层标题栏的标题。 */
const TAB_TITLES: string[] = ['NeriPlayer', '探索', '资料库', '设置'];

/**
 * HdsTabs miniBar 槽位内容包装。槽位的 CustomBuilder 闭包不随 MainShell
 * 状态变化重渲染（仅 HdsTabs 内部重建——如切 Tab——时重新执行），写在
 * 闭包里的任何显隐表达式都收不到新值（真机三轮实测：push/pop/模态展开
 * 全程迷你条停留在上一次渲染的可见态）。所以显隐由本组件经 AppStorage
 * 订阅——组件级订阅与挂载上下文无关。瞬时切换、不挂动画的理由见
 * MainShell.miniBarBuilder。
 */
@Component
struct SlotMiniBar {
  /** MainShell.publishSlotMiniHidden 发布的最终显隐门（= MainShell.slotMiniHidden()）。 */
  @StorageLink('ui.slotMiniHidden') hidden: boolean = false;
  @StorageLink('player.currentSong') currentSongJson: string = '';

  build() {
    if (this.currentSongJson.length > 0) {
      MiniPlayer({ compact: true })
        .opacity(this.hidden ? 0 : 1)
        .accessibilityLevel(this.hidden ? 'no-hide-descendants' : 'auto')
        .hitTestBehavior(this.hidden ? HitTestMode.None : HitTestMode.Default)
    }
  }
}

@Component
export struct MainShell {
  /**
   * 全屏路由栈。Router 只是它的门面（attach 见 aboutToAppear），所以全项目
   * 38 处 Router.push/pop 调用点在这次改造里一行都没动。
   */
  @Provide('NavPathStack') pageStack: NavPathStack = new NavPathStack();
  // 有歌才渲染 dock 态覆盖层；变化时同步其挂载状态（子页里开始播放也要下潜）。
  @StorageLink('player.currentSong') @Watch('syncDockBar') currentSongJson: string = '';
  /**
   * NavPathStack 深度快照（Router 在每次栈操作后发布，见 Router.publishDepth）。
   * >0 即处于子页：迷你条离开 HdsTabs 槽位，以 dock 形态悬浮在子页之上。
   */
  @StorageProp('ui.subPageDepth') @Watch('syncDockBar') subPageDepth: number = 0;
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('systemDark') systemDark: boolean = false;
  /** 由 util/WindowMetrics.ets 按窗口逻辑宽度发布：'sm' | 'md' | 'lg'。 */
  @StorageProp('ui.breakpoint') @Watch('syncDockBar') breakpoint: string = 'sm';
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
  @StorageLink('ui.nowPlayingMounted') @Watch('publishSlotMiniHidden') modalMounted: boolean = false;
  @StorageProp('ui.windowWidthVp') windowWidth: number = 360;
  @StorageProp('ui.windowHeightVp') windowHeight: number = 800;
  @State panelAmount: number = 0;
  // 动画方向（false=展开）：决定各属性动画的时长/时延取向。
  @State @Watch('publishSlotMiniHidden') closing: boolean = false;
  // 转场进行中：模态内容不响应命中，结算后恢复。
  @State transitioning: boolean = false;
  // 一镜到底转场的交互闸门（技能 Step4）：Navigation 自定义转场回调在动画
  // 开始/结束时切换，转场期间整棵 Navigation 子树禁交互，防止动画中误触
  // 导致布局错乱。dock 覆盖层在 Navigation 子树之外不受影响——转场期间
  // 它本就因播放页展开而隐藏。
  @State transitionGate: boolean = true;
  // 一镜到底展开起点。主页（含 dock 态子页）由 pillRect()/dockRect() 实时
  // 推导（见 pillRect 注释），lg 宽屏用 wideFallbackOrigin；不再保存 @State
  // 标定值——槽位锚点会随导航周期漂移，静态标定值会随窗口度量变化失真。
  @State originRect: NowPlayingRect = { x: 23, y: 611, width: 314, height: 40 };
  // dock 态迷你条覆盖层的挂载与几何状态：mounted 只控制存在性，docked 驱动
  // 药丸矩形（槽位迷你条原位）↔ dock 矩形（悬浮 Tab 栏足迹）之间的属性动画。
  @State @Watch('publishSlotMiniHidden') dockBarMounted: boolean = false;
  @State dockBarDocked: boolean = false;
  // 模态内容区的窗口坐标原点：面板/迷你条副本用窗口坐标（globalPosition 实测
  // 的 mini 矩形）计算，但 position() 相对模态内容区原点——若模态因安全区有
  // 偏移，直接套用会整体错位（展开起点/收起终点与迷你条不符）。在模态根节点
  // 实测原点后做自校正，模态铺满窗口时该值为 (0,0)，两种布局下都成立。
  @State modalOriginX: number = 0;
  @State modalOriginY: number = 0;
  private startDelayTimer: number = -1;
  private settleTimer: number = -1;
  private dockMountTimer: number = -1;
  private modalReady: boolean = false;
  private pendingDismiss: DismissContentCoverAction | undefined = undefined;
  private downloadListener: ShellDownloadListener = new ShellDownloadListener();

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
    // 路由形态（D4 flag 开，默认）：'ui.nowPlayingShown' 只作「播放页可见」
    // 信号（迷你条显隐门/pop 门共用），模态机器全部跳过；立即重发布显隐门，
    // 覆盖层对播放页路由的让位（dockOverlayHidden 并入了 nowPlayingShown）。
    if (Router.routeMode()) {
      this.publishSlotMiniHidden();
      return;
    }
    if (this.nowPlayingShown && !this.modalMounted) {
      // lg 宽屏（侧栏模式）没有 HdsTabsMiniBar 槽位，pillRect() 的手机药丸
      // 矩形无意义：改用底部整宽条带作为展开起点（底部弹出面板观感）。手机
      // 端子页上迷你条停在 dock 矩形（悬浮 Tab 栏足迹），展开起点随之切换，
      // 面板才从可见的条上起飞。
      this.originRect = this.wide()
        ? MainShell.wideFallbackOrigin(this.windowWidth, this.windowHeight)
        : (this.subPageDepth > 0 ? this.dockRect() : this.pillRect());
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
    } else if (this.startDelayTimer >= 0) {
      // 挂起中的展开推进作废：收起已启动，不能让 onAppear 的延迟计时器再把
      // 面板翻回展开方向（onAppear 计时器内另有二次守卫兜底）。
      clearTimeout(this.startDelayTimer);
      this.startDelayTimer = -1;
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

  private static readonly PILL_MARGIN_X: number = 23;

  /**
   * 槽位药丸矩形 = dock 返程落点 & 一镜到底展开起点。
   * 不从槽位 onAreaChange/getRectangleById 推导：HdsTabs 把可见药丸从槽位
   * 布局锚点（全宽、贴悬浮栏底部）渲染变换上移约 117vp，这两个 API 拿到的
   * 都是变换前的锚点——拿锚点当落点，真机两轮实测分别为「返程向下砸出屏幕」
   * （2026-09-20）与「落点低 59px 交接跳变」（2026-09-21，锚点还会随导航
   * 周期漂移）。改为从 dock 几何相对推导：药丸与 dock 同由壳层定位、共享
   * 同一坐标映射，相对量免换算、自动跟随 bottomLift/窗口尺寸变化。
   * X/宽用药丸对称设计值（barSideMargin 16 + 槽位内边距 7，实测壳宽 316vp
   * 与设计 314vp 吻合）；若 Hds 调整悬浮栏内部布局，按 PILL_RISE_FROM_DOCK_VP
   * 注释的方法重测。
   */
  private pillRect(): NowPlayingRect {
    return {
      x: MainShell.PILL_MARGIN_X,
      y: this.dockRect().y - PILL_RISE_FROM_DOCK_VP,
      width: Math.max(40, this.windowWidth - 2 * MainShell.PILL_MARGIN_X),
      height: PILL_HEIGHT_VP
    };
  }

  /** lg 宽屏兜底锚点：底部 96vp 整宽条带（侧栏形态无迷你条，见 open 分支）。 */
  private static wideFallbackOrigin(width: number, height: number): NowPlayingRect {
    const stripHeight = Math.min(96, Math.max(0, height));
    return { x: 0, y: height - stripHeight, width: width, height: stripHeight };
  }

  private panelRect(): NowPlayingRect {
    return NowPlayingMotion.panel(this.panelAmount, this.originRect, this.windowWidth, this.windowHeight);
  }

  /**
   * 官方 FAQ 对 HdsNavigation + HdsTabs 组合的要求：每个 Tab 的滚动容器持独立
   * Scroller，标题栏只绑定当前可见 Tab 的那一个；实例经构造参数下发给各 Tab 页。
   */
  private tabScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];

  /**
   * 官方 HdsTabsMiniBar 槽位：无歌时留空，有歌渲染紧凑 MiniPlayer。
   * 槽位的 CustomBuilder 闭包不随本组件状态重渲染（仅 HdsTabs 内部重建
   * 时重新执行），显隐不能写在这里的任何表达式上——由槽内 SlotMiniBar
   * 经 AppStorage 订阅 'ui.slotMiniHidden'，本组件经 publishSlotMiniHidden
   * 发布。显隐一律瞬时切换、不挂动画：每个切换点都有"同位同形"的接替
   * 者盖住或接住它——模态面板全程盖住药丸位、dock 覆盖层落位即迷你条
   * 本身——任何淡入淡出都会在遮盖缝隙里露出第二个控件（真机三轮实测）。
   */
  @Builder
  miniBarBuilder() {
    SlotMiniBar()
  }

  /**
   * 槽位真实迷你条的最终隐藏条件：miniBarHidden() 之外再并入「返回交接
   * 期」（dock 仍挂载但已回到主页）。交接期作为状态硬门控，任何时刻 dock
   * 是唯一可见控件；dock 卸载（syncDockBar 尾段定时器）本态自动解除——
   * 那一刻 dock 落位矩形与迷你条同位同形，瞬时接管零差异。结果经
   * publishSlotMiniHidden 发布，供槽内 SlotMiniBar 订阅（槽位闭包不响应
   * MainShell 状态，见 miniBarBuilder 注释）。
   */
  private slotMiniHidden(): boolean {
    return this.miniBarHidden() || (this.dockBarMounted && this.subPageDepth === 0);
  }

  /**
   * 把 slotMiniHidden() 的结果发布到 AppStorage：HdsTabs miniBar 槽位里的
   * CustomBuilder 闭包不随 MainShell 状态重渲染，槽内组件只能靠订阅此键
   * 实时显隐。触发源：modalMounted/closing/dockBarMounted 各自的 @Watch，
   * 以及 syncDockBar（subPageDepth 变化路径；其余入参最终也汇入
   * dockBarMounted，重复发布无害）。
   */
  private publishSlotMiniHidden(): void {
    AppStorage.setOrCreate('ui.slotMiniHidden', this.slotMiniHidden());
  }

  /**
   * 基础隐藏条件：模态挂载且处于展开方向（面板占位），或正处于子页（迷你
   * 条已由 dock 态覆盖层接替，见 dockMiniBarOverlay）。收起方向（closing）
   * 时提前可见——面板全程盖住药丸位，模态卸载瞬间零差异。返回交接期由
   * slotMiniHidden() 在此之上追加。
   */
  private miniBarHidden(): boolean {
    return (this.modalMounted && !this.closing) || this.subPageDepth > 0;
  }

  /**
   * dock 态覆盖层的隐藏条件：只跟随播放页模态的开合（面板占位时让位）。
   * 不能复用 miniBarHidden()——后者含 subPageDepth > 0（隐藏槽位真实迷你条
   * 用），并入会让覆盖层恰好在子页上时永远透明（真机首版实测：子页整层
   * 不可见，只剩返回主页后槽位空药丸壳）。
   */
  private dockOverlayHidden(): boolean {
    // 路由形态：播放页 NavDestination 盖不住这层覆盖层（它悬浮在 Navigation
    // 之上），播放页可见期间（路由或模态）一律让位；模态收起方向
    // （nowPlayingShown 已归零、modalMounted 未卸）不受影响，维持原节奏。
    return (this.modalMounted && !this.closing) || this.nowPlayingShown;
  }

  /**
   * dock 态迷你条覆盖层（参考网易云：进入二级页后迷你条扩大到 Tab 栏
   * 尺寸并落到 Tab 栏位置）。挂在壳层根 Stack 里 HdsNavigation 之上，所以
   * 全屏 NavDestination 子页盖得住 Tab 骨架与槽位迷你条，盖不住它。
   *
   * 几何动画：容器在「药丸矩形（pillRect()，与槽位迷你条同位同形）」和「dock
   * 矩形（悬浮 Tab 栏足迹）」之间做原生属性动画；两种紧凑/展开内容按目标
   * 形态交叉淡入淡出，规避 40↔62vp 内容重排的跳变。透明度/命中只跟随模态
   * 开合（dockOverlayHidden）：播放页模态展开期间隐藏（面板占位），收起
   * 后半段同步淡入。
   */
  @Builder
  dockMiniBarOverlay() {
    if (this.dockBarMounted && this.currentSongJson.length > 0) {
      Stack({ alignContent: Alignment.Top }) {
        MiniPlayer({ compact: true, embedded: true })
          .opacity(this.dockBarDocked ? 0 : 1)
          .animation({ duration: 180, curve: Curve.EaseOut })
          // 交叉淡入淡出的两份内容对读屏同样互斥，避免控件重复。
          .accessibilityLevel(this.dockBarDocked ? 'no-hide-descendants' : 'auto')
          .hitTestBehavior(this.dockBarDocked ? HitTestMode.None : HitTestMode.Default)
        MiniPlayer({ compact: false, embedded: true })
          .opacity(this.dockBarDocked ? 1 : 0)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .accessibilityLevel(this.dockBarDocked ? 'auto' : 'no-hide-descendants')
          .hitTestBehavior(this.dockBarDocked ? HitTestMode.Default : HitTestMode.None)
      }
      .width(this.dockBarDocked ? this.dockRect().width : this.pillRect().width)
      .height(this.dockBarDocked ? this.dockRect().height : this.pillRect().height)
      .position({
        x: this.dockBarDocked ? this.dockRect().x : this.pillRect().x,
        y: this.dockBarDocked ? this.dockRect().y : this.pillRect().y
      })
      // 几何段：dock 挂载/返回的起飞与落定（Friction 减速曲线，落栏手感）。
      .animation({ duration: DOCK_MORPH_MS, curve: Curve.Friction })
      // 透明度段：只跟随模态开合（dockOverlayHidden），各自捕获自己的属性段。
      .opacity(this.dockOverlayHidden() ? 0 : 1)
      .animation(this.dockOverlayHidden()
        ? { duration: 0 }
        : { duration: 220, delay: Math.round(NowPlayingMotion.COLLAPSE_MS * 0.55), curve: Curve.EaseOut })
      .accessibilityLevel(this.dockOverlayHidden() ? 'no-hide-descendants' : 'auto')
      .hitTestBehavior(this.dockOverlayHidden() ? HitTestMode.None : HitTestMode.Default)
    }
  }

  /** dock 态覆盖层的存在条件：处于子页、有歌、且非 lg 侧栏形态（侧栏无迷你条）。 */
  private shouldDockBar(): boolean {
    return this.subPageDepth > 0 && this.currentSongJson.length > 0 && !this.wide();
  }

  /**
   * dock 态几何：与悬浮 Tab 栏同一边距体系（barSideMargin 16、barBottomMargin
   * bottomLift+8），尺寸取非紧凑 MiniPlayer 胶囊（62vp 高）。窗口坐标与
   * pillRect() 同一坐标系，可直接作为一镜到底的展开起点。
   */
  private dockRect(): NowPlayingRect {
    return {
      x: FLOAT_BAR_SIDE_MARGIN_VP,
      y: this.windowHeight - (this.bottomLift + FLOAT_BAR_BOTTOM_GAP_VP) - DOCK_MINI_HEIGHT_VP,
      width: this.windowWidth - 2 * FLOAT_BAR_SIDE_MARGIN_VP,
      height: DOCK_MINI_HEIGHT_VP
    };
  }

  /**
   * dock 态覆盖层状态机（由 subPageDepth / currentSong / breakpoint 变化驱动）：
   * 下潜 = 挂载在药丸原位 → 延迟一帧翻转到 dock 几何（属性动画起飞）；返回 =
   * 翻回药丸几何 → 动画落定后卸载，与槽位内真实迷你条（同位同形）无缝交还。
   * 返回动画中途再次入栈会清掉卸载计时器并直接反向重定目标。
   */
  private syncDockBar(): void {
    this.publishSlotMiniHidden();
    if (this.shouldDockBar()) {
      if (this.dockMountTimer >= 0) {
        clearTimeout(this.dockMountTimer);
        this.dockMountTimer = -1;
      }
      if (this.dockBarMounted) {
        this.dockBarDocked = true;
        return;
      }
      this.dockBarMounted = true;
      this.dockBarDocked = false;
      // 延迟约一帧再翻转目标几何：同帧挂载+翻转会吞掉起始药丸帧（同
      // bindContentCover onAppear 的首帧推进手法）。
      this.dockMountTimer = setTimeout(() => {
        this.dockMountTimer = -1;
        if (this.shouldDockBar()) {
          this.dockBarDocked = true;
        }
      }, 16);
      return;
    }
    if (!this.dockBarMounted) {
      return;
    }
    if (this.dockMountTimer >= 0) {
      clearTimeout(this.dockMountTimer);
      this.dockMountTimer = -1;
    }
    if (!this.dockBarDocked) {
      // 尚未起跳就已失效（如子页里歌曲被清空）：直接卸载，不做往返动画。
      this.dockBarMounted = false;
      return;
    }
    // 落点用 pillRect()（从 dock 几何相对推导，见其注释）。不要改回
    // getRectangleById/onAreaChange"实测药丸"：HdsTabs 对药丸的上移是渲染
    // 变换，这两个 API 返回的都是变换前的槽位布局锚点（贴悬浮栏底部、全宽）
    // ——真机两轮实测：当落点 = 返程向下砸出屏幕（2026-09-20）；写回标定值
    // = 锚点漂移后落点低 59px、卸载交接向上跳一下（2026-09-21）。
    this.dockBarDocked = false;
    // 卸载延时只需比飞行动画（DOCK_MORPH_MS）留足余量：交接期内槽位迷
    // 你条被 slotMiniHidden() 硬性隐藏，本覆盖层是唯一可见控件；卸载那
    // 一刻迷你条在同位同形处瞬时接管（见 miniBarBuilder），取 +120 防
    // 个别设备动画尾帧被截。
    this.dockMountTimer = setTimeout(() => {
      this.dockMountTimer = -1;
      if (!this.shouldDockBar()) {
        this.dockBarMounted = false;
      }
    }, DOCK_MORPH_MS + 120);
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
    // 槽位迷你条显隐门初值：保证 SlotMiniBar 首帧挂载前键已就位。
    this.publishSlotMiniHidden();
    // 注册要放在启动页分支的 return 之前，任何默认页配置下都得收到完成回调。
    this.downloadListener.attach(this);
    DownloadEngine.addListener(this.downloadListener);
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
    if (this.dockMountTimer >= 0) {
      clearTimeout(this.dockMountTimer);
      this.dockMountTimer = -1;
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
   * 全屏路由。由 Navigation 按栈顶路由名调用；转场交给系统标准动效，不再自己拼
   * TransitionEffect。播放页不在此列：一镜到底改由 build() 根上的 bindContentCover
   * 全屏模态承载（NOW_PLAYING 不再入栈，见 Router 注释）。
   * 各路由页自身以 HdsNavDestination 为根（配置见 view/components/HdsSubPage.ets），
   * 承载与外壳同款的 GRADIENT_BLUR 渐变模糊标题栏与底部渐变遮罩；返回刷新广播
   * （notifyReturned）随之移到各页 HdsNavDestination 的 onWillDisappear。
   * S4 模拟器曾实测 HdsNavDestination 只渲染标题栏 chrome、不挂载内容子树（与
   * S0 spike S7 探针一致）；外壳 HdsNavigation 的同类问题真机不复现（2026-09-10
   * 用户确认），子页按官方开发实例写法启用 HdsNavDestination，模拟器行为待复核。
   */
  @Builder
  pageMap(name: string, param: Object) {
    if (name === Router.NOW_PLAYING) {
      // 播放页路由承载壳（docs/ONETAKE_INTEGRATION_PLAN.md M2）：NOW_PLAYING
      // 重新入栈；模态回退路径（'ui.nowPlayingAsRoute' = false）不经此分支，
      // 仍走下方 bindContentCover。
      NowPlayingRoutePage()
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
    } else if (name === Router.ARTIST) {
      ArtistPage({ artistParam: this.paramText(param) })
    } else if (name === Router.LISTEN_TOGETHER) {
      ListenTogetherPage()
    } else if (name === Router.LONG_TAKE_SPIKE) {
      // M1 spike（docs/ONETAKE_INTEGRATION_PLAN.md §4）：一镜到底兼容性验证页，
      // 临时路由，M5 拆除。
      LongTakeSpikePage()
    } else if (name === Router.LEGAL_DOC) {
      // 设置页入口按全屏路由打开，返回走 HdsNavDestination 标题栏返回键。
      LegalDocPage({ doc: this.paramText(param), asRoute: true, onClose: () => Router.pop() })
    } else {
      // 未知路由名：给一个空白页而不是崩掉，返回键仍能退出。navDestination
      // builder 的根必须是 NavDestination 系组件；标准 NavDestination 官方
      // 允许与 HdsNavDestination 混用。
      NavDestination() {
        Column().width('100%').height('100%')
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      .onWillDisappear(() => {
        Router.notifyReturned();
      })
    }
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
              barSideMargin: FLOAT_BAR_SIDE_MARGIN_VP,
              barBottomMargin: this.bottomLift + FLOAT_BAR_BOTTOM_GAP_VP,
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
    // 一镜到底转场桥（技能 Step4）：库内部按「目标页/退出页是否注册了一镜
    // 到底 session」自动分流——未注册的普通页面返回 undefined 走系统默认
    // 转场，无需在此按路由名过滤（计划 D3 由库内部实现兜底）。
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
      return ezCustomTransition.customNavContentTransition(from, to, operation, {
        onTransitionStart: (): void => {
          this.transitionGate = false;
        },
        onTransitionEnd: (): void => {
          this.transitionGate = true;
        }
      });
    })
    // 转场期间禁用整棵 Navigation 子树的交互；enabled 经 HdsNavigationAttribute
    // 继承自 CommonMethod 可用。
    .enabled(this.transitionGate)
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
          // 挂起期间可能已被收起（挂载后立刻返回：pop 先翻转 nowPlayingShown
          // 并进入收起分支）。此时再推进展开目标会让面板反向飞回、闪现一次
          // 再卸载；放弃推进，收尾交给已在跑的收起动画与结算。
          if (!this.nowPlayingShown || this.closing) {
            return;
          }
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

    // 子页 dock 态迷你条：子页是全屏 NavDestination，会盖住 HdsTabs 与槽位
    // 内的迷你条；这层悬浮在 Navigation 之上接替它（见 dockMiniBarOverlay）。
    // 放在压暗层之下，播放页模态开合时与主页其余部分一同被压暗。
    this.dockMiniBarOverlay()

    // 一镜到底背板：模态展开/收起期间主页整体压暗（参考实现为背景色 wash，
    // 悬浮 Tab 栏与迷你条一并压暗）。透明度绑定 panelAmount（端点 0/1）并
    // 挂与面板几何同一规格的属性动画——Router 已不包 animateTo，绑
    // nowPlayingShown 会在开合瞬间硬跳（压暗闪变）；随几何同步插值后压暗
    // 与飞行同节奏。不拦截命中测试，模态收起后对主页交互零影响。
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.withAlpha(Theme.background(this.resolveDark()), 0x99))
      .opacity(this.panelAmount)
      .animation({
        duration: this.closing ? NowPlayingMotion.COLLAPSE_MS : NowPlayingMotion.EXPAND_MS,
        curve: PANEL_CURVE
      })
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
