import { describe, it, expect } from '@ohos/hypium';
import {
  ROUTE_MAIN,
  ROUTE_MAX_DEPTH,
  RoutePushAction,
  routePushAction
} from '../../../main/ets/view/RouteStack';

/**
 * 路由改用 ArkUI 的 Navigation / NavPathStack 之后，栈本身由框架持有，
 * RouteStack.ets 只剩「一次 push 该落成哪种动作」这条纯规则，用例随之改为断言
 * 动作枚举，而不再自己维护 RouteEntry[]。
 *
 * 原 6 条用例中删掉 2 条：`serialize/parse round trips…`（AppStorage 里的
 * `route.stack` 序列化随镜像一起删除）与 `pushRoute never mutates its input`
 * （不再有输入数组可谈不可变性）。删的是「被测行为已经不存在」的用例，不是为了
 * 让测试变绿。
 */
export default function routeStackTest(): void {
  describe('RouteStack', (): void => {
    it('stacks each level of the settings chain as a regular push', 0, (): void => {
      // 设备走查用的正是这条链：设置 → 设置详情 → 调试页。每一层都必须是常规
      // 入栈，返回才会落在设置详情而不是直接回根。
      expect(routePushAction('', 0, 'settings_detail')).assertEqual(RoutePushAction.PUSH);
      expect(routePushAction('settings_detail', 1, 'debug')).assertEqual(RoutePushAction.PUSH);
      expect(routePushAction('debug', 2, 'now_playing')).assertEqual(RoutePushAction.PUSH);
    });

    it('re-pushing the visible route replaces the top instead of stacking', 0, (): void => {
      // MiniPlayer 双击、或换一个 id 再进同一个歌单详情，离开时都只应按一次返回。
      expect(routePushAction('playlist_detail', 1, 'playlist_detail'))
        .assertEqual(RoutePushAction.REPLACE_TOP);
      // 深度 0 时栈顶为空串，同名判据不能误命中：此时只有常规入栈。
      expect(routePushAction('', 0, 'playlist_detail')).assertEqual(RoutePushAction.PUSH);
    });

    it('pushing MAIN clears the stack and an empty name is ignored', 0, (): void => {
      expect(routePushAction('debug', 2, ROUTE_MAIN)).assertEqual(RoutePushAction.CLEAR);
      // 已经在 Tab 骨架上再推 MAIN 也走清栈，清空栈是幂等的。
      expect(routePushAction('', 0, ROUTE_MAIN)).assertEqual(RoutePushAction.CLEAR);
      // 空路由名没有对应的 NavDestination，推进去就是一层空白覆盖层。
      expect(routePushAction('stats', 1, '')).assertEqual(RoutePushAction.IGNORE);
      expect(routePushAction('', 0, '')).assertEqual(RoutePushAction.IGNORE);
    });

    it('depth is capped by dropping the oldest level', 0, (): void => {
      // 自己重入自己的页面（数据变化触发再次 push）不能把栈撑到无限深，
      // 到上限就丢最旧一层，返回链始终有限。
      expect(routePushAction('route_a', ROUTE_MAX_DEPTH - 1, 'route_b'))
        .assertEqual(RoutePushAction.PUSH);
      expect(routePushAction('route_a', ROUTE_MAX_DEPTH, 'route_b'))
        .assertEqual(RoutePushAction.EVICT_THEN_PUSH);
      expect(routePushAction('route_a', ROUTE_MAX_DEPTH + 5, 'route_b'))
        .assertEqual(RoutePushAction.EVICT_THEN_PUSH);
      // 满栈时同名再推仍然是替换：替换不增深，没必要驱逐。
      expect(routePushAction('route_a', ROUTE_MAX_DEPTH, 'route_a'))
        .assertEqual(RoutePushAction.REPLACE_TOP);
    });
  });
}
