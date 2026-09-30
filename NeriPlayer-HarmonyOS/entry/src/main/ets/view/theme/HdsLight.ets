// SPDX-License-Identifier: GPL-3.0

/**
 * Official immersive-light facade over hdsEffect (@kit.UIDesignKit):
 * - capability probing (getSystemMaterialTypes) cached per process, with the
 *   emulator returning [] — every consumer must keep a self-drawn fallback;
 * - pointLight / pressShadow builders applied through the ArkUI universal
 *   attribute .visualEffect() (hdsEffect.buildEffect → VisualEffect, API 20+);
 * - ArkUI base-level immersive system material (uiMaterial, API 26): the only
 *   way to put a system glass material on an arbitrary component — HDS
 *   SystemMaterialParams only takes effect inside its HdsTabs/HdsNavigation
 *   hosts, so standalone overlays (dock mini bar) go through .systemMaterial().
 *
 * Pure helpers that only assemble param objects stay testable; the effect
 * objects themselves require the kit and are built here.
 */
// VisualEffect 是 common.d.ts 里的全局 ambient 类型（S0 结论的姊妹坑），
// 不从模块导入。SystemUiMaterial 同理（common.d.ts:16964 的 ambient 别名）。
import { hdsEffect, hdsMaterial } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';

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

/**
 * ArkUI 底座沉浸材质（uiMaterial，API 26）的能力探测与实例缓存。HDS 的
 * SystemMaterialParams 只能随 HdsTabs 悬浮栏 / HdsNavigation 标题栏宿主
 * 生效，独立悬浮组件要挂系统玻璃材质只能走通用属性 .systemMaterial()。
 */
class SystemMaterialCapability {
  private static probed: boolean = false;
  private static materialSupported: boolean = false;
  private static barMaterial: SystemUiMaterial | undefined = undefined;

  static supported(): boolean {
    if (!SystemMaterialCapability.probed) {
      SystemMaterialCapability.probed = true;
      try {
        SystemMaterialCapability.materialSupported = uiMaterial.isImmersiveMaterialSupported();
      } catch (error) {
        // Kit absent or call rejected: keep false → callers degrade.
      }
    }
    return SystemMaterialCapability.materialSupported;
  }

  static bar(): SystemUiMaterial | undefined {
    if (!SystemMaterialCapability.supported()) {
      return undefined;
    }
    if (SystemMaterialCapability.barMaterial === undefined) {
      SystemMaterialCapability.barMaterial = new uiMaterial.ImmersiveMaterial();
    }
    return SystemMaterialCapability.barMaterial;
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

  /**
   * ArkUI 通用属性 .systemMaterial()（API 26 uiMaterial 沉浸材质）在本机是否
   * 可用。模拟器/低配形态返回 false 时使用方须保持自绘玻璃兜底。
   */
  static systemMaterialSupported(): boolean {
    return SystemMaterialCapability.supported();
  }

  /**
   * 独立承载悬浮条（dock 态迷你播放条）的系统沉浸材质实例：默认参数
   * （REGULAR 玻璃质感 + 材质自带阴影），进程内缓存复用；设备不支持时
   * 返回 undefined，使用方跳过 .systemMaterial() 走自绘玻璃。
   */
  static barSystemMaterial(): SystemUiMaterial | undefined {
    return SystemMaterialCapability.bar();
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
