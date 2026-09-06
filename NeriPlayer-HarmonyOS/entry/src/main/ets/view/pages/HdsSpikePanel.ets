import { hdsMaterial, hdsEffect, HdsVisualComponent, HdsSceneController, HdsSceneType, HdsTabs, HdsNavigation, HdsNavDestination } from '@kit.UIDesignKit';
import { HdsVisualComponentAttribute, HdsTabsAttribute, HdsNavigationAttribute, HdsNavDestinationAttribute } from '@kit.UIDesignKit';
import { Theme } from '../Theme';

/**
 * S0 摸底探针（docs/HDS_IMMERSIVE_SPIKE.md）：分层验证 UIDesignKit 在本机
 * API 24 CLT 工具链上的编译与运行可用性。STAGE 开关逐层放开，编译错误即定位
 * 到具体层；仅挂在调试页，S0 结束后按结论决定去留。
 */

// 逐层开关（编译分层探针，全部验证完成后统一收口）
const STAGE1_MATERIAL_TYPES = true;   // hdsMaterial.getSystemMaterialTypes()
const STAGE2_POINT_LIGHT = true;      // hdsEffect.pointLight -> visualEffect
const STAGE3_PRESS_SHADOW = true;     // hdsEffect.pressShadow -> visualEffect
const STAGE4_VISUAL_COMPONENT = true; // HdsVisualComponent().scene(...)
const STAGE5_HDS_TABS_BASE = true;   // HdsTabs 仅 json 已登记属性
const STAGE6_HDS_TABS_FLOAT = true;  // HdsTabs.barFloatingStyle（json 未登记，预期拦）
const STAGE7_HDS_NAVIGATION = true;  // HdsNavigation + HdsNavDestination

@Component
export struct HdsSpikePanel {
  @State probeResult: string = '尚未探测';
  private sceneController: HdsSceneController = new HdsSceneController();

  aboutToAppear(): void {
    this.sceneController.setSceneParams({
      backgroundMaskColors: ['#FFE8D6', '#FFD3E0', '#D6E6FF'],
      firstEdgeFlowLight: { startPos: 0, endPos: 0.5, color: '#E8452B' },
      secondEdgeFlowLight: { startPos: 0, endPos: -0.5, color: '#7C4DFF' }
    });
  }

  private probeMaterialTypes(): void {
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      const names: string[] = types.map((t: hdsMaterial.MaterialType): string => {
        if (t === hdsMaterial.MaterialType.IMMERSIVE) {
          return 'IMMERSIVE';
        }
        if (t === hdsMaterial.MaterialType.ADAPTIVE) {
          return 'ADAPTIVE';
        }
        return `NONE(${t})`;
      });
      this.probeResult = `getSystemMaterialTypes: [${names.join(', ')}]`;
    } catch (error) {
      this.probeResult = `getSystemMaterialTypes 抛错: ${(error as Error).message}`;
    }
  }

  private pointLightEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: { color: '#E8452B', intensity: 1, height: '80vp', bloom: 0.4 }
      })
      .buildEffect();
  }

  private pressShadowEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
      .buildEffect();
  }

  private frameRate(): hdsEffect.ExpectedFrameRateRange {
    return {
      expected: hdsEffect.FrameRateType.FRAME_RATE_60,
      min: hdsEffect.FrameRateType.FRAME_RATE_30,
      max: hdsEffect.FrameRateType.FRAME_RATE_60
    };
  }

  build() {
    Column({ space: 12 }) {
      if (STAGE1_MATERIAL_TYPES) {
        Button('探测系统材质类型')
          .width('100%')
          .height(40)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick((): void => this.probeMaterialTypes())
        Text(this.probeResult)
          .fontSize(12)
          .fontColor(Theme.primary(Theme.isDark()))
          .width('100%')
      }

      if (STAGE2_POINT_LIGHT) {
        Text('S2 pointLight：期望卡片边缘+内容泛光').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        Column() {
          Text('光晕卡片').fontSize(13).fontColor('#1B1B20')
        }
        .width(120)
        .height(64)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFE8D6')
        .borderRadius(14)
        .visualEffect(this.pointLightEffect())
      }

      if (STAGE3_PRESS_SHADOW) {
        Text('S3 pressShadow：按住期望官方按压阴影').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        Column() {
          Text('按住我').fontSize(13).fontColor('#FFFFFF')
        }
        .width(120)
        .height(64)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E8452B')
        .borderRadius(14)
        .visualEffect(this.pressShadowEffect())
      }

      if (STAGE4_VISUAL_COMPONENT) {
        Text('S4 HdsVisualComponent 双边流光：期望渐变底 + 两条流动光').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        Stack() {
          HdsVisualComponent()
            .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.sceneController,
              (): void => {}, this.frameRate())
            .width('100%')
            .height(72)
        }
        .width('100%')
        .borderRadius(16)
        .clip(true)
      }

      if (STAGE5_HDS_TABS_BASE) {
        Text('S5 HdsTabs 基础属性：期望底部文字 Tab 可切换').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column().width('100%').height('100%').backgroundColor('#FDFDFF')
          }.tabBar('首页')
          TabContent() {
            Column().width('100%').height('100%').backgroundColor('#F0F0F4')
          }.tabBar('探针')
        }
        .barPosition(BarPosition.End)
        .barOverlap(true)
        .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .height(140)
        .width('100%')
        .borderRadius(16)
        .clip(true)
      }

      if (STAGE6_HDS_TABS_FLOAT) {
        Text('S6 barFloatingStyle（json 未登记，编译验证）').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column().width('100%').height('100%')
          }.tabBar('甲')
          TabContent() {
            Column().width('100%').height('100%')
          }.tabBar('乙')
        }
        .barPosition(BarPosition.End)
        .barOverlap(true)
        .barFloatingStyle({
          barSideMargin: 16,
          barBottomMargin: 12,
          lightColor: '#E8452B'
        })
        .height(120)
        .width('100%')
        .borderRadius(16)
        .clip(true)
      }

      if (STAGE7_HDS_NAVIGATION) {
        Text('S7 HdsNavigation + HdsNavDestination：推入子页再返回').fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark())).width('100%')
        HdsSpikeNav()
      }

    }
    .width('100%')
    .padding(12)
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(12)
  }
}

/** S7 独立子组件：隔离 Navigation 探针的编译风险。 */
@Component
struct HdsSpikeNav {
  private navStack: NavPathStack = new NavPathStack();

  @Builder
  hdsDestBuilder(name: string, pageInfos: Object) {
    if (name === 'hds_spike_dest') {
      HdsNavDestination() {
        Column() {
          Text('HdsNavDestination 已到达').fontSize(14)
          Button('返回')
            .height(40)
            .onClick(() => this.navStack.pop())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .hideTitleBar(true)
    }
  }

  build() {
    HdsNavigation(this.navStack) {
      Column() {
        Button('推入子页')
          .height(40)
          .onClick(() => {
            this.navStack.pushPath({ name: 'hds_spike_dest' }, false);
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .navDestination((name: string, pageInfos: Object): void => this.hdsDestBuilder(name, pageInfos))
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .height(140)
    .width('100%')
    .borderRadius(16)
    .clip(true)
  }
}
