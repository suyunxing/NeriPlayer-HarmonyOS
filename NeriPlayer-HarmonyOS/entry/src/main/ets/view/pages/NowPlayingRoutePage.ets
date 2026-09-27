// SPDX-License-Identifier: GPL-3.0

import {
  LongTakeSession,
  LongTakeTransitionParam,
  LongTakeTransitionDelegate
} from '@hmanimations/ezcustomtransition';
import { common } from '@kit.AbilityKit';
import { SystemBars } from '../../util/SystemBars';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { NowPlayingPage } from './NowPlayingPage';

/**
 * 播放页的路由承载壳（docs/ONETAKE_INTEGRATION_PLAN.md M2/M3）。
 *
 * 播放页从 bindContentCover 全屏模态迁为 NavDestination 入栈（D1）：消除
 * 「播放页内发起子路由必须先收模态」的历史包袱，返回手势与生命周期走标准
 * Navigation 行为，并为 ezcustomtransition 一镜到底转场提供目标页前提。
 * NowPlayingPage 本体零改动——模态回退路径（'ui.nowPlayingAsRoute' = false）
 * 仍直接使用它；本壳固定以完全展开态（transitionProgress=1）呈现，页面级
 * 分阶段进场动画由库的转场接替（M3 接线），页内布局动画不受影响。
 *
 * 库目标页样板（技能 Step 1-6）：onReady 解析参数 → session.init →
 * LongTakeTransitionDelegate 包裹 → NavDestination 背景交 session →
 * onSizeChange 同步尺寸；原 NavDestination 背景迁至子组件 + expandSafeArea
 * 由 NowPlayingPage 自己的全屏背景层承担（封面取色/流光/模糊，根 Stack 自带
 * 实色底，符合项目「子页根 Stack 必须自带实色底」约定）。
 */
@Component
export struct NowPlayingRoutePage {
  @State longTakeSession: LongTakeSession = new LongTakeSession();
  @State longTakeTransitionParam: LongTakeTransitionParam | undefined = undefined;

  @Builder
  contentBuilder() {
    NowPlayingPage({ transitionProgress: 1, closing: false })
      .width('100%')
      .height('100%')
  }

  build() {
    NavDestination() {
      // 带转场参数（M3 接线后）由库的 Delegate 接管布局与转场动画。
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
    // 一镜到底会话期间 NavDestination 背景由 session 动态管理；无参数
    // （M2 中间态/截图失败兜底）时保持透明，由 NowPlayingPage 的全屏背景呈现。
    .backgroundColor(this.longTakeTransitionParam !== undefined
      ? this.longTakeSession.navDestinationBgColor
      : Color.Transparent)
    .hideTitleBar(true)
    // 窗口尺寸变化（旋转/自由窗口）时同步库的动画计算基准。
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
          Router.pop();
        }
      });
    })
    .onDisAppear(() => {
      // 'ui.nowPlayingShown' 归零 + 深度快照补发：统一覆盖 Router.pop、系统
      // 返回键与侧滑手势三条弹栈路径（手势返回不经 Router）。不发刷新广播
      // （notifyReturned）——普通收起播放页不改 Tab 页数据，广播会引发首页
      // 重载式闪屏（同 MainShell 模态 onDisappear 的既有结论）。
      AppStorage.setOrCreate(Router.KEY_NOW_PLAYING_SHOWN, false);
      Router.syncDepth();
      // 播放页按封面亮度改写过系统栏图标色，这里交回主页主题配色（同模态
      // onDisappear 的既有行为；恢复时机对飞行半程图标的影响待真机复核）。
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        SystemBars.apply(context as common.UIAbilityContext, Theme.isDark());
      }
    })
  }
}
