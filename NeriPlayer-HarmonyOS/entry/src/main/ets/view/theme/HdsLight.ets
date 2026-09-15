// SPDX-License-Identifier: GPL-3.0

/**
 * Official immersive-light facade over hdsEffect (@kit.UIDesignKit):
 * - capability probing (getSystemMaterialTypes) cached per process, with the
 *   emulator returning [] — every consumer must keep a self-drawn fallback;
 * - pointLight / pressShadow builders applied through the ArkUI universal
 *   attribute .visualEffect() (hdsEffect.buildEffect → VisualEffect, API 20+).
 *
 * Pure helpers that only assemble param objects stay testable; the effect
 * objects themselves require the kit and are built here.
 */
// VisualEffect 是 common.d.ts 里的全局 ambient 类型（S0 结论的姊妹坑），
// 不从模块导入。
import { hdsEffect, hdsMaterial } from '@kit.UIDesignKit';

class MaterialCapability {
  private static probed: boolean = false;
  private static immersive: boolean = false;
  private static adaptive: boolean = false;

  static immersiveSupported(): boolean {
    MaterialCapability.probe();
    return MaterialCapability.immersive;
  }

  static adaptiveSupported(): boolean {
    MaterialCapability.probe();
    return MaterialCapability.adaptive;
  }

  private static probe(): void {
    if (MaterialCapability.probed) {
      return;
    }
    MaterialCapability.probed = true;
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      for (const t of types) {
        if (t === hdsMaterial.MaterialType.IMMERSIVE) {
          MaterialCapability.immersive = true;
        } else if (t === hdsMaterial.MaterialType.ADAPTIVE) {
          MaterialCapability.adaptive = true;
        }
      }
    } catch (error) {
      // Kit absent or call rejected: keep both false → callers degrade.
    }
  }
}

export class HdsLight {
  /** True when the device reports the immersive material type. */
  static immersiveSupported(): boolean {
    return MaterialCapability.immersiveSupported();
  }

  /** True when the device reports any adaptive material support. */
  static adaptiveSupported(): boolean {
    return MaterialCapability.adaptiveSupported();
  }

  /** Soft glow around the illuminated component (cover art, play FAB, hero card). */
  static pointLight(accentHex: string, intensity: number, bloom: number): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: { color: accentHex, intensity: intensity, height: '80vp', bloom: bloom }
      })
      .buildEffect();
  }

  /** Official press feedback (mixed gradient shadow). */
  static pressShadow(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .buildEffect();
  }

  /**
   * Animated dual-edge flow light running on an ordinary component via
   * shaderEffect (HdsVisualComponent is the dedicated renderer, but the same
   * EffectType applies through visualEffect). Params: colors from the cover
   * scheme; 30fps is plenty for an ambient sweep.
   */
  static flowLight(firstColor: string, secondColor: string): VisualEffect {
    const controller: hdsEffect.ShaderEffectController | undefined = undefined;
    return new hdsEffect.HdsEffectBuilder()
      .shaderEffect({
        effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
        animation: {
          duration: 2400,
          iterations: -1,
          autoPlay: true,
          expectedFrameRateRange: {
            expected: hdsEffect.FrameRateType.FRAME_RATE_30,
            min: hdsEffect.FrameRateType.FRAME_RATE_15,
            max: hdsEffect.FrameRateType.FRAME_RATE_30
          }
        },
        params: {
          firstEdgeFlowLight: { startPos: 0, endPos: 0.5, color: firstColor },
          secondEdgeFlowLight: { startPos: 0, endPos: -0.5, color: secondColor }
        },
        controller: controller
      })
      .buildEffect();
  }
}
