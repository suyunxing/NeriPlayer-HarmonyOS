/**
 * Official immersive-light backdrop for the NowPlaying page:
 * Layer 1 (bottom): HdsVisualComponent dual-edge flow-light scene whose
 *   backgroundMaskColors come from the cover scheme (gradient backdrop +
 *   two animated edge lights in accent/tertiary hue).
 * Layer 2: the blurred cover image kept as a faint material grain on top of
 *   the shader scene (the page's own crossfade layers stay in NowPlayingPage).
 *
 * Component rules honored here:
 * - the scheme is read through @StorageProp (tracked), then mirrored into
 *   plain fields for the controller — never read AppStorage inside build();
 * - HdsVisualComponentAttribute must be imported explicitly (S0 spike: the
 *   transform emits bare global references with no ambient bridge);
 * - expandSafeArea only on pure display layers.
 */
import { HdsVisualComponent, HdsSceneController, HdsSceneType } from '@kit.UIDesignKit';
import { HdsVisualComponentAttribute } from '@kit.UIDesignKit';
import { AccentScheme } from '../theme/AccentScheme';
import { ColorScience, Lch } from '../theme/ColorScience';

@Component
export struct ImmersiveLightScene {
  @StorageProp('player.coverScheme') @Watch('onSchemeChanged') scheme: AccentScheme = AccentScheme.neutralFallback();
  @Prop dark: boolean = false;
  /** Blur-strength scale from np.nowplaying_blur_strength (0..500). */
  @Prop blurStrength: number = 250;
  @Prop coverUrl: string = '';

  private sceneController: HdsSceneController = new HdsSceneController();

  aboutToAppear(): void {
    this.applySceneParams();
  }

  private onSchemeChanged(): void {
    this.applySceneParams();
  }

  /** Derive scene colors from the current scheme and push them to the shader. */
  private applySceneParams(): void {
    const mode = this.dark ? this.scheme.dark : this.scheme.light;
    const accentLch: Lch | null = ColorScience.hexToLch(mode.primary);
    const hueDeg = accentLch !== null ? accentLch.h : 90;
    const topL = this.dark ? 16 : 90;
    const bottomL = this.dark ? 7 : 96;
    const topC = this.dark ? 8 : 6;
    this.sceneController.setSceneParams({
      backgroundMaskColors: [
        ColorScience.lchToHexInGamut(topL, topC, hueDeg),
        ColorScience.lchToHexInGamut(bottomL, 4, hueDeg)
      ],
      firstEdgeFlowLight: { startPos: 0, endPos: 0.45, color: mode.primary },
      secondEdgeFlowLight: { startPos: 0, endPos: -0.45, color: mode.tertiary }
    });
  }

  build() {
    Stack() {
      // 官方光感场景层：渐变背景遮罩 + 双边流光，GPU 硬件加速。
      HdsVisualComponent()
        .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.sceneController)
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 极淡的模糊封面叠在光感场景上（第二层材质颗粒）。
      if (this.coverUrl.length > 0) {
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(Math.max(0, this.blurStrength * 80 / 500))
          .scale({ x: 1.4, y: 1.4 })
          .opacity(0.25)
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }
}
