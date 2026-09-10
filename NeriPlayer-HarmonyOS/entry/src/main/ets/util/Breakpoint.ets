/**
 * 纯的窗口度量派生规则：逻辑宽度 -> 断点，导航指示器避让区 -> 底部抬升量。
 * 不引 ArkUI、不读 AppStorage，所以可以直接单测（与 RouteStack.ets 同一惯例）。
 * 读写 AppStorage 的那一半在 util/WindowMetrics.ets。
 */

/**
 * 断点阈值与 ArkUI GridRow 的默认值同源（['320vp','600vp','840vp'] +
 * BreakpointsReference.WindowSize），这样 GridRow 自己分列的结果与本文件算出的
 * ui.breakpoint 永远一致 —— 否则会出现「Tab 已切成侧边栏但卡片网格还是两列」。
 * xs（<320vp）不单列一档：本项目最窄形态是折叠外屏 346vp，归进 sm 即可。
 */
export const BP_MD_VP: number = 600;
export const BP_LG_VP: number = 840;

export const BP_SM: string = 'sm';
export const BP_MD: string = 'md';
export const BP_LG: string = 'lg';

/**
 * WindowMetrics 发布到 AppStorage 的键名。
 *
 * 注意：@StorageProp / @StorageLink 的参数必须是字符串字面量（装饰器在编译期
 * 解析），所以页面里要原样写这些字符串，不能引用下面的常量。常量只服务于
 * WindowMetrics 的写入侧与单测。
 */
export const KEY_WIDTH_VP: string = 'ui.widthVp';
export const KEY_BREAKPOINT: string = 'ui.breakpoint';
export const KEY_BOTTOM_LIFT_VP: string = 'ui.bottomLiftVp';
export const KEY_TOP_INSET_VP: string = 'ui.topInsetVp';
export const KEY_REFRESH_TICK: string = 'ui.refreshTick';

/** 指南硬性值：应用内底部固定控件相对系统导航条上抬 28vp。 */
export const GUIDELINE_BOTTOM_LIFT_VP: number = 28;

/**
 * 栏宽档位，配 view/components/Ui.ets 的 ContentBand 使用。
 *
 * 大屏上「继续铺满」不等于「用好了宽度」：tablet 1440vp 时法务正文一行能排七八十
 * 个字，眼睛要横扫整块屏。两档的分法与断点阈值刻意错开 —— 断点决定用几列，
 * 栏宽决定单列多宽。
 *   正文类 600vp：法务 / 免责声明 / 引导，纯阅读，一行 30 字左右
 *   列表类 840vp：设置行、资料库、探索页，图标 + 双行文字的横向结构
 * 卡片网格不套 ContentBand —— 那类内容用 GridRow 分列消化宽度。
 */
export const BAND_TEXT_VP: number = 600;
export const BAND_LIST_VP: number = 840;

/**
 * 全宽按钮（width('90%') 之类）在大屏上的宽度上限。再宽下去点击目标就散开了，
 * 也不再像一个按钮 —— 首启同意/不同意、引导页「下一步」都按这个值收口。
 */
export const BAND_BUTTON_VP: number = 360;

/** 窗口逻辑宽度落在哪一档。拿不到宽度时按最窄处理，绝不误判成大屏。 */
export function breakpointFor(widthVp: number): string {
  if (!Number.isFinite(widthVp) || widthVp <= 0) {
    return BP_SM;
  }
  if (widthVp >= BP_LG_VP) {
    return BP_LG;
  }
  if (widthVp >= BP_MD_VP) {
    return BP_MD;
  }
  return BP_SM;
}

/** 大屏形态判据：顶层导航切侧边栏、正文分栏都以此为界。 */
export function isWide(breakpoint: string): boolean {
  return breakpoint === BP_LG;
}

/**
 * 顶部状态栏避让高度（vp）。TYPE_SYSTEM.topRect.height 即状态栏像素高
 * （官方 FAQ「如何获取状态栏和导航栏高度」），按屏幕密度换算成 vp 后供
 * 全屏模态（enableSafeArea:false 的播放页）给头部控件让位。取不到有效的
 * 像素值或密度时归零 —— 宁可头部贴顶也不凭空垫一截死区。
 */
export function topInsetFor(statusBarHeightPx: number, density: number): number {
  if (!Number.isFinite(statusBarHeightPx) || statusBarHeightPx <= 0
    || !Number.isFinite(density) || density <= 0) {
    return 0;
  }
  return Math.round(statusBarHeightPx / density);
}

/**
 * 底部抬升量。窗口是非全屏布局（EntryAbility.applyEdgeToEdge 有意
 * setWindowLayoutFullScreen(false)），窗口底边就落在导航指示器上沿，所以 28vp
 * 是「指示器之上的外边距」而不是指示器高度 —— 没有指示器还留 28vp 就是纯死区。
 *
 * 同一条规则同时对上两处实测：tablet 的 SCBGestureNavBar 高 56px / 2.0 = 28vp
 * 与常量吻合；2in1 自由窗口 TYPE_NAVIGATION_INDICATOR 避让区为 0，抬升量应当
 * 归零。原来的硬编码常量属于「碰巧在 tablet 上对」。
 */
export function bottomLiftFor(indicatorHeightPx: number): number {
  if (!Number.isFinite(indicatorHeightPx) || indicatorHeightPx <= 0) {
    return 0;
  }
  return GUIDELINE_BOTTOM_LIFT_VP;
}
