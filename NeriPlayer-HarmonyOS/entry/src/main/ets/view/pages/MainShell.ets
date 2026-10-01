// SPDX-License-Identifier: GPL-3.0

import { Router } from '../Router';
import { DownloadEngine, DownloadEngineListener } from '../../download/DownloadEngine';
import { SongItem } from '../../model/SongItem';
import { NowPlayingMotion, NowPlayingRect } from '../NowPlayingMotion';
import { PANEL_CURVE } from '../NowPlayingCurves';
import { Theme } from '../Theme';
import { common } from '@kit.AbilityKit';
import { SystemBars } from '../../util/SystemBars';
import { HdsTabs, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
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
import { BiliWebLoginPage } from './BiliWebLoginPage';
import { LegalDocPage } from './LegalDocPage';
import { AlbumPage } from './AlbumPage';
import { ArtistPage } from './ArtistPage';

/** Tab 项内容高度 56 + 顶部 6 的视觉间距，与改造前的 tabItem 固定高度一致。 */
const TAB_BAR_CONTENT_VP: number = 62;
/** 悬浮栏组左右边距：页签胶囊与迷你条胶囊共用。 */
const FLOAT_BAR_SIDE_MARGIN_VP: number = 16;
/** 悬浮栏组底部边距的呼吸增量：底边 = windowHeight - (bottomLift + 此值)。 */
const FLOAT_BAR_BOTTOM_GAP_VP: number = 8;
/** 迷你条胶囊高度 = 非紧凑 MiniPlayer 胶囊高度（进度条 2 + 内容行 60）。 */
const DOCK_MINI_HEIGHT_VP: number = 62;
/** 页签胶囊高度（堆叠态）：对齐 HDS 悬浮栏 56vp 视觉。 */
const TABS_PILL_H_VP: number = 56;
/** 折叠态页签小胶囊宽度：仅容当前项（图标 + 文字）。 */
const FOLDED_TABS_W_VP: number = 72;
/** 堆叠态页签胶囊与迷你条胶囊的行距。 */
const ROW_GAP_VP: number = 8;
/** 滚动折叠阈值：当前 Tab 滚过此值且在向下滚，栏组折叠为单行。 */
const FOLD_ON_OFFSET_VP: number = 96;
/** 滚动展开阈值：滚回此值以内栏组恢复堆叠（与折叠阈值拉开防抖滞回）。 */
const UNFOLD_ON_OFFSET_VP: number = 48;
/** 栏组两态形变时长（dock 迁移另有 DOCK_MORPH_MS）。 */
const BAR_MORPH_MS: number = 300;
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
  // 封面 scheme 订阅（曾驱动悬浮 Tab 栏 lightColor，自绘栏组后保留供光感扩展）。
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State currentTab: number = 0;
  /**
   * 悬浮栏组形态：false=堆叠（迷你条在上、页签全宽在下），true=折叠（页签
   * 收缩为当前项小胶囊、与迷你条并排一行）。由内容滚动位置驱动（见
   * handleTabBarScroll），两态都是全不透明真实控件，切换走原生属性动画。
   */
  @State barFolded: boolean = false;
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
  // 一镜到底展开起点。主页（含 dock 态子页）由 pillRect()/dockRect() 实时
  // 推导（见 pillRect 注释），lg 宽屏用 wideFallbackOrigin；不再保存 @State
  // 标定值——槽位锚点会随导航周期漂移，静态标定值会随窗口度量变化失真。
  @State originRect: NowPlayingRect = { x: 23, y: 611, width: 314, height: 40 };
  // dock 态迷你条覆盖层的挂载与几何状态：mounted 只控制存在性，docked 驱动
  // 迷你条现位（主页栏组，折叠态感知）↔ dock 矩形（页签胶囊足迹）之间的属性动画。
  @State dockBarMounted: boolean = false;
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
    if (this.nowPlayingShown && !this.modalMounted) {
      // lg 宽屏（侧栏模式）没有底部迷你条，pillRect() 的手机药丸
      // 矩形无意义：改用底部整宽条带作为展开起点（底部弹出面板观感）。手机
      // 端子页上迷你条停在 dock 矩形（页签胶囊足迹），展开起点随之切换，
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

  /**
   * 悬浮栏组底边（窗口坐标）：页签胶囊与 dock 态迷你条共用的锚线。
   */
  private barBottomEdgeY(): number {
    return this.windowHeight - (this.bottomLift + FLOAT_BAR_BOTTOM_GAP_VP);
  }

  /** 无歌时栏组不可折叠（折叠的意义是给迷你条让出同行空间）。 */
  private barFoldable(): boolean {
    return this.currentSongJson.length > 0;
  }

  /**
   * 页签胶囊矩形：堆叠态 = 全宽 56vp（贴底边）；折叠态 = 当前项小胶囊
   * 72×62，与迷你条并排一行。几何全部由本文件常量推导——自绘栏组后不再
   * 有 HdsTabs 内部布局黑盒，dock 返程落点与一镜到底展开起点随之成为精确值。
   */
  private tabsPillRect(): NowPlayingRect {
    if (this.barFolded && this.barFoldable()) {
      return {
        x: FLOAT_BAR_SIDE_MARGIN_VP,
        y: this.barBottomEdgeY() - DOCK_MINI_HEIGHT_VP,
        width: FOLDED_TABS_W_VP,
        height: DOCK_MINI_HEIGHT_VP
      };
    }
    return {
      x: FLOAT_BAR_SIDE_MARGIN_VP,
      y: this.barBottomEdgeY() - TABS_PILL_H_VP,
      width: this.windowWidth - 2 * FLOAT_BAR_SIDE_MARGIN_VP,
      height: TABS_PILL_H_VP
    };
  }

  /**
   * 迷你条胶囊矩形：堆叠态 = 全宽、悬在页签胶囊上方 ROW_GAP_VP；折叠态 =
   * 页签小胶囊右侧余下的同行空间。即一镜到底展开起点与 dock 返程落点。
   */
  private miniPillRect(): NowPlayingRect {
    if (this.barFolded && this.barFoldable()) {
      return {
        x: FLOAT_BAR_SIDE_MARGIN_VP + FOLDED_TABS_W_VP + ROW_GAP_VP,
        y: this.barBottomEdgeY() - DOCK_MINI_HEIGHT_VP,
        width: this.windowWidth - 2 * FLOAT_BAR_SIDE_MARGIN_VP - FOLDED_TABS_W_VP - ROW_GAP_VP,
        height: DOCK_MINI_HEIGHT_VP
      };
    }
    return {
      x: FLOAT_BAR_SIDE_MARGIN_VP,
      y: this.barBottomEdgeY() - TABS_PILL_H_VP - ROW_GAP_VP - DOCK_MINI_HEIGHT_VP,
      width: this.windowWidth - 2 * FLOAT_BAR_SIDE_MARGIN_VP,
      height: DOCK_MINI_HEIGHT_VP
    };
  }

  /** 迷你条现位（折叠态感知）= dock 返程落点 & 一镜到底展开起点。 */
  private pillRect(): NowPlayingRect {
    return this.miniPillRect();
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
   * dock 态覆盖层的隐藏条件：只跟随播放页模态的开合（面板占位时让位）。
   * 主页栏组的迷你条不在本条件内——它挂在 HdsNavigation 内容 Stack 里，
   * 模态展开期间被面板与压暗层自然覆盖，无需自行显隐。
   */
  private dockOverlayHidden(): boolean {
    return this.modalMounted && !this.closing;
  }

  /**
   * dock 态迷你条覆盖层（参考网易云：进入二级页后迷你条落到页签胶囊足迹）。
   * 挂在壳层根 Stack 里 HdsNavigation 之上，所以全屏 NavDestination 子页盖得
   * 住主页栏组（floatingBottomBars），盖不住它。
   *
   * 几何动画：容器在「迷你条现位（pillRect()，折叠态感知，与主页栏组迷你条
   * 同位同形）」和「dock 矩形（页签胶囊足迹）」之间做原生属性动画。两者同为
   * 62vp 非紧凑 MiniPlayer 胶囊——自绘栏组后迷你条恒为 62 高，40↔62 交叉
   * 淡入淡出已无存在必要（2026-10-01 重构删除）。透明度/命中只跟随模态开合
   * （dockOverlayHidden）：播放页模态展开期间隐藏，收起后半段同步淡入。
   */
  @Builder
  dockMiniBarOverlay() {
    if (this.dockBarMounted && this.currentSongJson.length > 0) {
      Stack() {
        MiniPlayer({ compact: false, embedded: true })
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
   * dock 态几何：与悬浮栏组同一边距体系（左右 16、底部 bottomLift+8），
   * 尺寸取非紧凑 MiniPlayer 胶囊（62vp 高）——即折叠态迷你条的同一规格。
   * 窗口坐标与 pillRect() 同一坐标系，可直接作为一镜到底的展开起点。
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
   * 下潜 = 挂载在迷你条现位 → 延迟一帧翻转到 dock 几何（属性动画起飞）；返回
   * = 翻回迷你条现位 → 动画落定后卸载——那一刻主页栏组的迷你条已在同位同形
   * 处挂载（subPageDepth 归零即时渲染，被本覆盖层盖住到卸载瞬间），零差异
   * 接管。返回动画中途再次入栈会清掉卸载计时器并直接反向重定目标。
   */
  private syncDockBar(): void {
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
    // 落点用 pillRect()（迷你条现位，折叠态感知）。自绘栏组后该矩形与主页
    // 迷你条由同一批常量推导，subPageDepth 归零瞬间主页迷你条即在同位同形
    // 处挂载（被本覆盖层盖住），卸载交接零差异——HdsTabs 槽位时代「锚点
    // 漂移需真机标定」的问题类别整体消失。
    this.dockBarDocked = false;
    // 卸载延时只需比飞行动画（DOCK_MORPH_MS）留足余量：交接期内本覆盖层
    // 是唯一可见控件，卸载那一刻主页迷你条在同位同形处瞬时接管，取 +120
    // 防个别设备动画尾帧被截。
    this.dockMountTimer = setTimeout(() => {
      this.dockMountTimer = -1;
      if (!this.shouldDockBar()) {
        this.dockBarMounted = false;
      }
    }, DOCK_MORPH_MS + 120);
  }

  /**
   * 滚动自适应栏组（参考网易云录屏的两态折叠）：各 Tab 页根滚动容器经
   * onScrollFrameBegin 把纵向增量与位置交到这里。向下滚（yDelta>0）且滚过
   * FOLD_ON_OFFSET_VP → 折叠；位置回到 UNFOLD_ON_OFFSET_VP 以内 → 堆叠。
   * 不再使用 HdsTabsController.applyHide/ShowAnimation——真机实测（2026-10-01）
   * 其 SCROLL_ANIMATION 为原地半透明淡出且随滚动方向反复触发时在实心/半透
   * 明间闪切，与参考视频的「折叠成单行」相去甚远，弃用；两态形变改为自绘
   * 控件的属性动画（floatingBottomBars）。触底兜底（页面报 -1）天然无副作用：
   * -1 不满足折叠条件，位置在底部也不满足展开条件，栏组保持折叠态。
   */
  private handleTabBarScroll(yDelta: number): void {
    if (this.wide()) {
      return;
    }
    if (!this.barFolded) {
      const yOffset = this.tabScrollers[this.currentTab].currentOffset().yOffset;
      if (yDelta > 0 && yOffset > FOLD_ON_OFFSET_VP && this.barFoldable()) {
        this.barFolded = true;
      }
    } else if (!this.barFoldable()
      || this.tabScrollers[this.currentTab].currentOffset().yOffset < UNFOLD_ON_OFFSET_VP) {
      this.barFolded = false;
    }
  }

  /** 标题栏的系统沉浸材质参数：设备不支持时保持 undefined（自绘玻璃兜底）。 */
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

  /** barFolded 的渲染值：无歌时强制按堆叠态画（折叠只为给迷你条让位）。 */
  private barFoldedVisual(): boolean {
    return this.barFolded && this.barFoldable();
  }

  /** 页签胶囊的系统玻璃：设备支持沉浸材质时交系统接管，否则自绘玻璃兜底。 */
  private barGlass(): boolean {
    return HdsLight.systemMaterialSupported();
  }

  /**
   * 主页自绘悬浮栏组（2026-10-01 真机反馈重构，取代 HdsTabs 自带栏 +
   * miniBar 槽位 + applyHide/ShowAnimation 滚动隐藏）：参考网易云录屏的两态
   * 形变。堆叠态（静止/回顶）：迷你条胶囊在上、全宽页签胶囊在下；折叠态
   * （滚入正文）：页签收缩为当前项小胶囊，与迷你条并排一行。两态均为全
   * 不透明真实控件，形变由 barFolded 驱动属性动画（BAR_MORPH_MS，Friction），
   * 全程没有透明度动画——真机实测 SDK SCROLL_ANIMATION 是原地半透明淡出、
   * 且随滚动方向反复触发时实心/半透明闪切，与参考视频相去甚远，弃用。
   *
   * 命中：根 Stack HitTestMode.None 只豁免容器自身，两枚胶囊各自可点，
   * 胶囊间隙与胶囊外的列表照常滚动。
   */
  @Builder
  floatingBottomBars() {
    if (!this.wide()) {
      Stack() {
        // 页签胶囊：容器几何两态切换（BAR_MORPH_MS）；内容两份（全宽四项 ↔
        // 当前项小胶囊）按目标形态交叉淡入淡出，规避布局重排跳变（dock
        // 覆盖层同款分工）。玻璃背板在设备支持时交系统沉浸材质接管。
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.barGlass() ? Color.Transparent : Theme.surfaceGlass(this.resolveDark()))
            .backgroundBlurStyle(this.barGlass() ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK)
            .systemMaterial(this.barGlass() ? HdsLight.barSystemMaterial() : undefined)
            .hitTestBehavior(HitTestMode.None)
          Row() {
            this.tabPillItem(0, '首页', $r('app.media.ic_tab_home_24'))
            this.tabPillItem(1, '探索', $r('app.media.ic_tab_search_24'))
            this.tabPillItem(2, '资料库', $r('app.media.ic_tab_library_24'))
            this.tabPillItem(3, '设置', $r('app.media.ic_tab_settings_24'))
          }
          .width('100%')
          .height('100%')
          .opacity(this.barFoldedVisual() ? 0 : 1)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .accessibilityLevel(this.barFoldedVisual() ? 'no-hide-descendants' : 'auto')
          .hitTestBehavior(this.barFoldedVisual() ? HitTestMode.None : HitTestMode.Default)
          Row() {
            if (this.currentTab === 0) {
              this.tabPillItem(0, '首页', $r('app.media.ic_tab_home_24'))
            } else if (this.currentTab === 1) {
              this.tabPillItem(1, '探索', $r('app.media.ic_tab_search_24'))
            } else if (this.currentTab === 2) {
              this.tabPillItem(2, '资料库', $r('app.media.ic_tab_library_24'))
            } else {
              this.tabPillItem(3, '设置', $r('app.media.ic_tab_settings_24'))
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .opacity(this.barFoldedVisual() ? 1 : 0)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .accessibilityLevel(this.barFoldedVisual() ? 'auto' : 'no-hide-descendants')
          .hitTestBehavior(this.barFoldedVisual() ? HitTestMode.Default : HitTestMode.None)
        }
        .width(this.barFoldedVisual() ? FOLDED_TABS_W_VP : this.windowWidth - 2 * FLOAT_BAR_SIDE_MARGIN_VP)
        .height(this.barFoldedVisual() ? DOCK_MINI_HEIGHT_VP : TABS_PILL_H_VP)
        .borderRadius(this.barFoldedVisual() ? DOCK_MINI_HEIGHT_VP / 2 : TABS_PILL_H_VP / 2)
        .clip(true)
        .position({
          x: this.tabsPillRect().x,
          y: this.tabsPillRect().y
        })
        .animation({ duration: BAR_MORPH_MS, curve: Curve.Friction })

        // 迷你条胶囊：非紧凑 MiniPlayer 自带玻璃（与 dock 态同一形态），
        // 几何随折叠/堆叠切换。子页期间不渲染（dock 覆盖层在 Navigation 之上
        // 接替，见 dockMiniBarOverlay）。
        if (this.currentSongJson.length > 0 && this.subPageDepth === 0) {
          Stack() {
            MiniPlayer({ compact: false, embedded: true })
          }
          .width(this.miniPillRect().width)
          .height(this.miniPillRect().height)
          .position({
            x: this.miniPillRect().x,
            y: this.miniPillRect().y
          })
          .animation({ duration: BAR_MORPH_MS, curve: Curve.Friction })
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  /** 页签胶囊单项：折叠态点当前项 = 展开整栏（参考网易云交互）。 */
  @Builder
  tabPillItem(index: number, label: string, icon: Resource) {
    Column() {
      this.tabBarContent(index, label, icon)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.barFolded = false;
      this.selectTab(index);
    })
  }

  @Builder
  tabPages() {
    TabContent() {
      HomePage({ scroller: this.tabScrollers[0], onBarScroll: (yDelta: number) => this.handleTabBarScroll(yDelta) })
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
      ExplorePage({ scroller: this.tabScrollers[1], onBarScroll: (yDelta: number) => this.handleTabBarScroll(yDelta) })
    }
    // 与首页 TabContent 同理：放行页内滚动内容向上穿透到状态栏后被渐变模糊覆盖。
    .clip(false)
    .tabBar(this.wide()
      ? this.sideTabBar(1, '探索', $r('app.media.ic_tab_search_24'))
      : this.bottomTabBar(1, '探索', $r('app.media.ic_tab_search_24')))

    TabContent() {
      LibraryPage({ scroller: this.tabScrollers[2], onBarScroll: (yDelta: number) => this.handleTabBarScroll(yDelta) })
    }
    // 同探索页：放行内容向上穿透。
    .clip(false)
    .tabBar(this.wide()
      ? this.sideTabBar(2, '资料库', $r('app.media.ic_tab_library_24'))
      : this.bottomTabBar(2, '资料库', $r('app.media.ic_tab_library_24')))

    TabContent() {
      SettingsPage({ scroller: this.tabScrollers[3], onBarScroll: (yDelta: number) => this.handleTabBarScroll(yDelta) })
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
    } else if (name === Router.BILI_WEB_LOGIN) {
      BiliWebLoginPage()
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
            // S5-2: 内容骨架只保留 HdsTabs 的切页能力，自带栏整体隐藏
            // （barHeight 0；官方语义仅 <0 才回落默认值）。底部两枚悬浮胶囊
            // 由 floatingBottomBars 自绘，形态与几何全部本文件可控——HdsTabs
            // 槽位（药丸锚点漂移需真机标定）与 applyHide/ShowAnimation（原地
            // 淡出 + 闪切）两条路线均于 2026-10-01 真机反馈后弃用。
            HdsTabs({ barPosition: BarPosition.End, index: this.currentTab }) {
              this.tabPages()
            }
            .vertical(false)
            .barHeight(0)
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

        // 自绘悬浮栏组：页签胶囊 + 迷你条胶囊（两态折叠，见 floatingBottomBars）。
        this.floatingBottomBars()
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
    // 新 Tab 的滚动位置决定栏组形态：滚入正文的 Tab 直接以折叠态呈现，
    // 回到顶部的 Tab 恢复堆叠（与滚动判定同一阈值，见 handleTabBarScroll）。
    this.barFolded = this.currentSongJson.length > 0
      && this.tabScrollers[index].currentOffset().yOffset > FOLD_ON_OFFSET_VP;
    // 先落 default_start_tab，再发刷新信号：Tab 页用它判断自己是否可见。
    AppStorage.setOrCreate('np.default_start_tab', index);
    Router.notifyReturned();
  }
}
