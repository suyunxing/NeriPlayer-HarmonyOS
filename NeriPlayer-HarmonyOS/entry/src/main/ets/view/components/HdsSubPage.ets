// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics } from '@kit.ArkUI';
import { ScrollEffectType, BlurStrategy, HdsNavigationTitleBarOptions, HdsNavigationMenuItemOptions, HdsNavigationTitle, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { Theme } from '../Theme';
import { HdsLight } from '../theme/HdsLight';

/**
 * 二、三级路由页与首页外壳同款的沉浸光感渐变模糊标题栏（MainShell 8958d16
 * 起的标准做法下沉到子页）：各路由页根节点换 HdsNavDestination，由其承载
 * GRADIENT_BLUR titleBar，滚动内容穿到状态栏背后被渐变模糊材质覆盖。
 *
 * 布局模型对齐首页（19502ec 首版照官方 demo 用 enableComponentSafeArea 让
 * 内容避开标题栏，真机实测标题栏底下没有页面内容、光感材质渲染出自己的
 * 暖色底板，顶部出现一条淡黄断层——2026-09-16 用户反馈）：内容根铺满全窗
 * （HdsNavDestination ignoreLayoutSafeArea TOP|BOTTOM），滚动容器顶部让位
 * SUB_TITLEBAR_SPACE_VP 并 clip(false) 放行内容滚入标题栏下方，与外壳四个
 * Tab 页完全同构。
 */

/** HdsNavDestinationTitleMode.MINI 标题栏高度：子页滚动内容顶部让位同高（同 MainShell）。 */
export const SUB_TITLEBAR_SPACE_VP: number = 56;

/** 底部渐变带高度（对齐首页 HdsTabs gradientMask 的 92vp）+ 24vp 收尾呼吸。 */
export const SUB_BOTTOM_CLEARANCE_VP: number = 116;

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
 * 参数与 MainShell 外壳 titleBar 逐项对齐（不用 enableComponentSafeArea——
 * 外壳首页也没用，内容避让由各页滚动容器 padding top 完成），深浅色与主题色
 * 走同一 Theme 决策。
 */
export function subPageTitleBar(title: ResourceStr, menu?: SubPageMenuEntry[], subTitle?: ResourceStr): HdsNavigationTitleBarOptions {
  const titleEntry: HdsNavigationTitle = {
    mainTitle: title
  };
  if (subTitle !== undefined) {
    titleEntry.subTitle = subTitle;
  }
  const options: HdsNavigationTitleBarOptions = {
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
 * 子页底部的渐变模糊效果，复刻首页的复合遮罩（MainShell HdsTabs
 * gradientMask 92vp·0x99 + 手势条渐变 0xD9）：页面根容器经
 * HdsNavDestination.ignoreLayoutSafeArea 延伸进底部安全区后，叠一层由上到下
 * 「渐入 0x99 → 一路加深到屏幕最底边 0xD9」的页面底色渐变，导航指示条区域
 * 同样被覆盖（不避让）。不拦截触摸；作为页面根 Stack/Column 的最后一个
 * 子节点叠在滚动内容之上。
 */
@Component
export struct SubPageBottomFade {
  /** 真实导航指示器避让区高度（util/WindowMetrics.ets 发布；无指示器形态为 0）。 */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();

  /** 渐变条总高 = 92vp 主遮罩带 + 手势条避让区 + 8vp 呼吸（与首页同规模）。 */
  private fadeHeight(): number {
    return 92 + this.bottomLift + 8;
  }

  private fadeStops(): Array<[ResourceColor, number]> {
    const bg = Theme.background(Theme.isDark());
    const height = this.fadeHeight();
    const maskEnd = 92 / height;
    // 全部色标用页面底色的透明变体（终止色若用透明黑，插值穿过半透明黑，
    // 浅色主题下底部呈「黑雾」——首页同写法但该区域被悬浮 Tab 栏与其
    // gradientMask 盖住不可见，子页无遮挡会直接露出）。末段一路加深到
    // 0xD9 直达屏幕最底边：导航指示条区域同样被渐变覆盖，不避让
    //（2026-09-16 用户反馈：底端回退透明会让渐变看起来从导航条上沿才开始）。
    return [
      [Theme.withAlpha(bg, 0x00), 0],
      [Theme.withAlpha(bg, 0x99), maskEnd],
      [Theme.withAlpha(bg, 0xD9), 1]
    ];
  }

  build() {
    Column()
      .width('100%')
      .height(this.fadeHeight())
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: this.fadeStops()
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: '100%' })
      .markAnchor({ y: this.fadeHeight() })
  }
}
