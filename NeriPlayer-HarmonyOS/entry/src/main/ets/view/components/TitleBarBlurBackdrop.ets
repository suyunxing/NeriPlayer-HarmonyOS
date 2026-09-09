import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';

/**
 * 标题栏渐变模糊背板：无内容的纯材质层，放在 Stack 里垫在常驻标题行与
 * 滚动内容之间，内容从标题栏背后滚过时被系统材质模糊，再被自上而下
 * 渐深的同色 scrim 逐渐「溶」进页面背景——HDS 沉浸式标题栏（渐变模糊）
 * 的自绘等价实现。SDK 里 ScrollEffectType.GRADIENT_BLUR 只能经 HdsNavigation
 * 标题栏承载，而外壳按 S4 结论（模拟器上 navDestination 子树不挂载）回退了
 * 标准 Navigation，这里以标准 ArkUI 属性复刻同款观感，后续切回 HdsNavigation
 * 时整组件可删。
 *
 * scrim 底部取页面背景同色的不透明档：背板下边缘与页面底色逐像素同色，
 * 不出现硬接缝；顶部留半透明档让材质模糊透出。关毛玻璃（np.glass_effect）
 * 时与 MiniPlayer 同策略回落：无模糊 + 顶档升到全不透明，退化为纯色标题栏。
 */
@Component
export struct TitleBarBlurBackdrop {
  /** 背板总高：标题行高 + 底部渐隐延伸区。几何常量，无需响应式。 */
  barHeight: number = 92;
  /** 订阅封面配色：动态取色换歌后背板与页面背景一起重染（同页面 schemeBg）。 */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('np.glass_effect') glassEffect: boolean = true;

  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private baseColor(): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(Theme.isDark()) : Theme.background(Theme.isDark());
  }

  build() {
    Column()
      .width('100%')
      .height(this.barHeight)
      .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [Theme.withAlpha(this.baseColor(), this.glassEffect ? 0x99 : 0xFF), 0],
          [this.baseColor(), 1]
        ]
      })
  }
}
