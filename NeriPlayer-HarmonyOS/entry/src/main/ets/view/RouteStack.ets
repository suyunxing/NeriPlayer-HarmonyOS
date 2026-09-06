/**
 * Pure push-decision rules behind Router — no AppStorage, no ArkUI, so the
 * navigation rules stay unit-testable while the stack itself lives in ArkUI's
 * NavPathStack (Navigation/NavDestination).
 *
 * 历史：这里原先自己维护一个 RouteEntry[] 并序列化进 AppStorage
 * (`route.stack`)，栈顶再镜像到 `route.name`/`route.param`。改用
 * Navigation 之后栈由框架持有，序列化与镜像一起删除 —— 在 Stack 模式下
 * 下层 destination 仍然存活，共享一个 `route.param` 会污染它们。
 * 保留下来的只有三条与容器无关的决策规则。
 */
export const ROUTE_MAIN: string = 'main';

/**
 * Depth cap. A route pushed in a loop (a page that re-enters itself on a data
 * change) would otherwise grow the stack without bound; the oldest entry is
 * dropped instead, so back always stays finite.
 */
export const ROUTE_MAX_DEPTH: number = 16;

export enum RoutePushAction {
  /** 空路由名：非法调用，什么都不做。 */
  IGNORE = 0,
  /** 推入 MAIN 等价于回到 Tab 骨架 —— 清空整栈。 */
  CLEAR = 1,
  /**
   * 栈顶已是同名路由：替换而不是叠一层，这样连点两次不需要按两次返回。
   * 参数可能不同（同一个歌单详情页换一个 id），所以是 replace 而非忽略。
   */
  REPLACE_TOP = 2,
  /** 常规入栈。 */
  PUSH = 3,
  /** 已达深度上限：先丢最旧一层再入栈，返回链始终有限。 */
  EVICT_THEN_PUSH = 4
}

/**
 * 决定一次 Router.push 该怎么落到 NavPathStack 上。
 *
 * @param topName 当前栈顶路由名，空栈传 ''
 * @param depth 当前栈深（0 = 正显示 Tab 骨架）
 * @param name 要推入的路由名
 */
export function routePushAction(topName: string, depth: number, name: string): RoutePushAction {
  if (name.length === 0) {
    return RoutePushAction.IGNORE;
  }
  if (name === ROUTE_MAIN) {
    return RoutePushAction.CLEAR;
  }
  if (depth > 0 && topName === name) {
    return RoutePushAction.REPLACE_TOP;
  }
  return depth >= ROUTE_MAX_DEPTH ? RoutePushAction.EVICT_THEN_PUSH : RoutePushAction.PUSH;
}
