// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics } from '@kit.ArkUI';
import { ScrollEffectType, BlurStrategy, HdsNavigationTitleBarOptions, HdsNavigationMenuItemOptions, HdsNavigationTitle, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { Theme } from '../Theme';
import { HdsLight } from '../theme/HdsLight';

/**
 * 二、三级路由页与首页外壳同款的沉浸光感渐变模糊标题栏（MainShell 8958d16
 * 起的标准做法下沉到子页）：各路由页根节点换 HdsNavDestination，由其承载
 * GRADIENT_BLUR titleBar，滚动内容穿到状态栏背后被渐变模糊材质覆盖。样式
 * 配置集中在这里，子页只报标题文本（与可选菜单项），避免 12 个页面各抄
 * 一份 30 行的样式块。
 */

/** 标题栏菜单项的最小构造（icon 传 $r 资源，HDS 内部渲染，含 sys.symbol）。 */
export interface SubPageMenuEntry {
  label: string;
  icon: ResourceStr;
  action: () => void;
}

/** 与外壳一致的标题栏系统沉浸材质：设备不支持时保持 undefined（HDS 自降级）。 */
function systemMaterialEffect(): SystemMaterialParams | undefined {
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
 * 子页标题栏统一配置：GRADIENT_BLUR（0→8vp 渐进过渡）+ BlurStrategy.ADAPTIVE +
 * 系统沉浸材质；静止态背板取页面底色、滚动态透出渐变模糊材质的透明背板。
 * enableComponentSafeArea 让内容区自动避让标题栏（官方 HdsNavDestination 开发
 * 实例写法），滚动容器配合 .clip(false) 让内容滚入标题栏下方被渐变模糊覆盖。
 * 参数与 MainShell 外壳 titleBar 逐项对齐，深浅色与主题色走同一 Theme 决策。
 */
export function subPageTitleBar(title: ResourceStr, menu?: SubPageMenuEntry[], subTitle?: ResourceStr): HdsNavigationTitleBarOptions {
  const titleEntry: HdsNavigationTitle = {
    mainTitle: title
  };
  if (subTitle !== undefined) {
    titleEntry.subTitle = subTitle;
  }
  const options: HdsNavigationTitleBarOptions = {
    enableComponentSafeArea: true,
    content: {
      title: titleEntry
    },
    style: {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(8)
      },
      blurStrategy: BlurStrategy.ADAPTIVE,
      // 静止态背板与页面底色同色（无接缝），滚动后过渡为透出系统渐变模糊
      // 材质的透明背板；标题色跟随应用主题，不取系统默认。
      originalStyle: {
        backgroundStyle: { backgroundColor: Theme.background(Theme.isDark()) },
        contentStyle: {
          titleStyle: { mainTitleColor: Theme.textPrimary(Theme.isDark()) }
        }
      },
      scrollEffectStyle: {
        backgroundStyle: { backgroundColor: Color.Transparent },
        contentStyle: {
          titleStyle: { mainTitleColor: Theme.textPrimary(Theme.isDark()) }
        }
      },
      systemMaterialEffect: systemMaterialEffect()
    }
  };
  if (menu !== undefined && menu.length > 0) {
    const items: HdsNavigationMenuItemOptions[] = menu.map((entry: SubPageMenuEntry): HdsNavigationMenuItemOptions => {
      return {
        content: {
          label: entry.label,
          icon: entry.icon,
          action: entry.action
        }
      };
    });
    options.content = {
      title: titleEntry,
      menu: { value: items }
    };
  }
  return options;
}

/**
 * 子页底部的渐变模糊效果（对齐首页 MainShell 的手势条渐变遮罩做法）：页面
 * 根容器经 HdsNavDestination.ignoreLayoutSafeArea 延伸进底部安全区后，叠一层
 * 由上到下渐透明的页面底色渐变，保证系统导航指示条区域的可读性。不拦截
 * 触摸；作为页面根 Stack/Column 的最后一个子节点叠在滚动内容之上。
 */
@Component
export struct SubPageBottomFade {
  /** 真实导航指示器避让区高度（util/WindowMetrics.ets 发布；无指示器形态为 0）。 */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();

  /** 渐变条高度 = 避让区 + 8vp 呼吸（与 MainShell 手势条遮罩同高）。 */
  private fadeHeight(): number {
    return this.bottomLift + 8;
  }

  build() {
    Column()
      .width('100%')
      .height(this.fadeHeight())
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [Theme.withAlpha(Theme.background(Theme.isDark()), 0xD9), 0],
          [0x00000000, 1]
        ]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: '100%' })
      .markAnchor({ y: this.fadeHeight() })
  }
}
