// SPDX-License-Identifier: GPL-3.0

import { LongTakeSession, LongTakeTransitionParam, LongTakeTransitionDelegate } from '@hmanimations/ezcustomtransition';
import { Router } from '../Router';
import { Theme } from '../Theme';

/**
 * 一镜到底 M1 spike 目标页（docs/ONETAKE_INTEGRATION_PLAN.md §4）。
 *
 * 目的：在动播放页架构（M2）之前，用最小闭环在真机验证 HdsNavigation 外壳
 * × ezcustomtransition 的兼容性（计划风险 R1）：转场是否生效、有无布局错乱、
 * 返回手势是否正常。临时路由，M5 拆除，不承载业务数据。
 *
 * 按技能「目标页 5 处修改」样板实现：onReady 解析路由参数并 init session（1/2）、
 * LongTakeTransitionDelegate 包裹内容（3）、NavDestination 背景交 session 管理（4）、
 * 原 NavDestination 背景迁到子组件并 expandSafeArea 延伸进状态栏（5）、
 * onSizeChange 通知 session（6）。
 */
@Component
export struct LongTakeSpikePage {
  @State longTakeSession: LongTakeSession = new LongTakeSession();
  @State longTakeTransitionParam: LongTakeTransitionParam | undefined = undefined;
  // 转场/返回进行中的防重入门：session 的 pop 回调与页内按钮可能先后触发。
  private popHandled: boolean = false;

  private doPop(): void {
    if (this.popHandled) {
      return;
    }
    this.popHandled = true;
    Router.pop();
  }

  @Builder
  contentBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 16 }) {
        Text('一镜到底 Spike')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
        Text('M1：验证 HdsNavigation × ezcustomtransition 转场与返回手势')
          .fontSize(14)
          .fontColor(Theme.textSecondary(Theme.isDark()))
        Button('返回')
          .onClick(() => this.doPop())
      }
    }
    .width('100%')
    .height('100%')
    // 技能 Step5：NavDestination 原背景色迁到子组件，并延伸进状态栏。
    .backgroundColor(Theme.background(Theme.isDark()))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  build() {
    NavDestination() {
      // 技能 Step3：带转场参数时由库的 Delegate 接管布局与动画。
      if (this.longTakeTransitionParam !== undefined) {
        LongTakeTransitionDelegate({
          longTakeSession: this.longTakeSession,
          contentBuilder: (): void => {
            this.contentBuilder()
          }
        })
      } else {
        this.contentBuilder()
      }
    }
    // 技能 Step4：一镜到底会话期间 NavDestination 背景由 session 动态管理；
    // 无参数（截图失败兜底）时保持透明，由子组件背景呈现。
    .backgroundColor(this.longTakeTransitionParam !== undefined
      ? this.longTakeSession.navDestinationBgColor
      : Color.Transparent)
    .hideTitleBar(true)
    // 技能 Step6：窗口尺寸变化（旋转/自由窗口）时同步动画计算基准。
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.longTakeSession.setNewSize(newValue);
    })
    .onReady((navDestContext: NavDestinationContext) => {
      const param = navDestContext.pathInfo?.param as Record<string, Object> | undefined;
      if (param === undefined || param === null) {
        return;
      }
      const longTakeParam = param['longTakeTransitionParam'] as LongTakeTransitionParam | undefined;
      if (longTakeParam === undefined || longTakeParam === null) {
        return;
      }
      this.longTakeTransitionParam = longTakeParam;
      this.longTakeSession.init(navDestContext, longTakeParam, {
        pop: (): void => {
          this.doPop();
        }
      });
    })
    .onDisAppear(() => {
      // 手势返回不经 Router.pop：这里补发深度快照，防止 ui.subPageDepth 卡住。
      Router.syncDepth();
    })
  }
}
