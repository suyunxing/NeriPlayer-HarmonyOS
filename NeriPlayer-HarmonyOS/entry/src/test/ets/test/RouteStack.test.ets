import { describe, it, expect } from '@ohos/hypium';
import {
  ROUTE_MAIN,
  ROUTE_MAX_DEPTH,
  RouteEntry,
  directionForRouteChange,
  parseRouteStack,
  popRoute,
  pushRoute,
  routeTop,
  serializeRouteStack
} from '../../../main/ets/view/RouteStack';

export default function routeStackTest(): void {
  describe('RouteStack', (): void => {
    it('pushRoute stacks levels and popRoute unwinds them one at a time', 0, (): void => {
      // The exact chain the device walk-through exercised: 设置 → 设置详情 →
      // 调试页. Back must land on 设置详情, not jump straight to the root.
      let stack: RouteEntry[] = [];
      stack = pushRoute(stack, 'settings_detail', 'playback');
      stack = pushRoute(stack, 'debug', '');
      expect(stack.length).assertEqual(2);
      expect((routeTop(stack) as RouteEntry).name).assertEqual('debug');

      stack = popRoute(stack);
      expect(stack.length).assertEqual(1);
      const top = routeTop(stack) as RouteEntry;
      expect(top.name).assertEqual('settings_detail');
      expect(top.param).assertEqual('playback');

      stack = popRoute(stack);
      expect(stack.length).assertEqual(0);
      expect(routeTop(stack)).assertNull();
    });

    it('pushRoute never mutates its input', 0, (): void => {
      const base = pushRoute([], 'now_playing', '');
      const grown = pushRoute(base, 'listen_together', '');
      expect(base.length).assertEqual(1);
      expect(grown.length).assertEqual(2);
      expect(popRoute(grown).length).assertEqual(1);
      expect(grown.length).assertEqual(2);
    });

    it('re-pushing the visible route replaces the top instead of stacking', 0, (): void => {
      // A double tap on the MiniPlayer, or a playlist row re-entered with a
      // different id, must still take one back press to leave.
      let stack = pushRoute([], 'playlist_detail', 'local_1');
      stack = pushRoute(stack, 'playlist_detail', 'local_2');
      expect(stack.length).assertEqual(1);
      expect((routeTop(stack) as RouteEntry).param).assertEqual('local_2');
    });

    it('directionForRouteChange classifies push/pop/none for the route transition', 0, (): void => {
      // Depth deltas drive the deck motion: deeper = the new page slides up
      // from the bottom edge, shallower (including a drop to the root) = the
      // returned-to page slides down from the top edge.
      const root: RouteEntry[] = [];
      const one = pushRoute(root, 'debug', '');
      const two = pushRoute(one, 'now_playing', '');
      expect(directionForRouteChange(root, root)).assertEqual('none');
      expect(directionForRouteChange(root, one)).assertEqual('push');
      expect(directionForRouteChange(one, two)).assertEqual('push');
      expect(directionForRouteChange(two, one)).assertEqual('pop');
      expect(directionForRouteChange(one, root)).assertEqual('pop');
      // Same-route re-push replaces the top in place: nothing remounts, so
      // no transition must fire.
      expect(directionForRouteChange(one, pushRoute(one, 'debug', 'x'))).assertEqual('none');
      // At the depth cap the stack stays the same length but still swaps the
      // top for a different route — deeper content, so it reads as a push.
      let deep: RouteEntry[] = [];
      for (let i = 0; i < ROUTE_MAX_DEPTH; i++) {
        deep = pushRoute(deep, `route_${i}`, '');
      }
      expect(directionForRouteChange(deep, pushRoute(deep, 'next_route', ''))).assertEqual('push');
    });

    it('pushing MAIN clears the stack and popping at the root is a no-op', 0, (): void => {
      let stack = pushRoute([], 'stats', '');
      stack = pushRoute(stack, 'downloads', '');
      expect(pushRoute(stack, ROUTE_MAIN, '').length).assertEqual(0);
      expect(popRoute([]).length).assertEqual(0);
      // An empty name cannot create a route that nothing renders.
      expect(pushRoute(stack, '', 'x').length).assertEqual(2);
    });

    it('depth is capped by dropping the oldest level', 0, (): void => {
      let stack: RouteEntry[] = [];
      for (let i = 0; i < ROUTE_MAX_DEPTH + 5; i++) {
        stack = pushRoute(stack, `route_${i}`, `${i}`);
      }
      expect(stack.length).assertEqual(ROUTE_MAX_DEPTH);
      expect(stack[0].name).assertEqual('route_5');
      expect((routeTop(stack) as RouteEntry).name).assertEqual(`route_${ROUTE_MAX_DEPTH + 4}`);
    });

    it('serialize/parse round trips and rejects unusable rows', 0, (): void => {
      let stack = pushRoute([], 'netease_playlist', '12345');
      stack = pushRoute(stack, 'now_playing', '');
      const restored = parseRouteStack(serializeRouteStack(stack));
      expect(restored.length).assertEqual(2);
      expect(restored[0].name).assertEqual('netease_playlist');
      expect(restored[0].param).assertEqual('12345');
      expect(restored[1].name).assertEqual('now_playing');

      // First launch (nothing persisted yet) and corrupt payloads both degrade
      // to the root rather than throwing during build().
      expect(parseRouteStack('').length).assertEqual(0);
      expect(parseRouteStack('not json').length).assertEqual(0);
      expect(parseRouteStack('{"n":"debug"}').length).assertEqual(0);
      // Rows with no usable name, and a persisted MAIN row from an older
      // build, are dropped instead of rendering an empty overlay.
      expect(parseRouteStack('[{"p":"x"},{"n":""},{"n":"main"},{"n":"debug"}]').length).assertEqual(1);
      // A non-string param degrades to empty, it does not drop the level.
      const coerced = parseRouteStack('[{"n":"bili_fav","p":42}]');
      expect(coerced.length).assertEqual(1);
      expect(coerced[0].param).assertEqual('');
    });
  });
}
