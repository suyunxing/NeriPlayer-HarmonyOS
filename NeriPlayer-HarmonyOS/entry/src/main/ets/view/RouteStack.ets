/**
 * Pure route-stack algebra behind Router — no AppStorage, no ArkUI, so the
 * back-navigation rules are unit-testable.
 *
 * The stack used to be a single slot (one route name + one param), which made
 * pop() always jump to the root: 设置 → 调试页 or 播放页 → 一起听 lost the
 * intermediate page on the way back, and the system back key had nothing to
 * pop against at all (device-observed 2026-08-24, M9.3 返回栈 regression).
 */
export const ROUTE_MAIN: string = 'main';

/**
 * Depth cap. A route pushed in a loop (a page that re-enters itself on a data
 * change) would otherwise grow the persisted stack without bound; the oldest
 * entry is dropped instead, so back always stays finite.
 */
export const ROUTE_MAX_DEPTH: number = 16;

export class RouteEntry {
  readonly name: string;
  readonly param: string;

  constructor(name: string, param: string) {
    this.name = name;
    this.param = param;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['n'] = this.name;
    json['p'] = this.param;
    return json;
  }

  static fromJson(obj: Record<string, Object>): RouteEntry | null {
    const name = obj['n'];
    if (typeof name !== 'string' || name.length === 0 || name === ROUTE_MAIN) {
      return null;
    }
    const param = obj['p'];
    return new RouteEntry(name, typeof param === 'string' ? param : '');
  }
}

/** Reads the persisted stack; anything unparsable degrades to the root. */
export function parseRouteStack(json: string): RouteEntry[] {
  if (json.length === 0) {
    return [];
  }
  try {
    const arr: Object[] = JSON.parse(json) as Object[];
    if (!Array.isArray(arr)) {
      return [];
    }
    const out: RouteEntry[] = [];
    for (const item of arr) {
      const entry = RouteEntry.fromJson(item as Record<string, Object>);
      if (entry !== null) {
        out.push(entry);
      }
    }
    return out;
  } catch (error) {
    return [];
  }
}

export function serializeRouteStack(entries: RouteEntry[]): string {
  return JSON.stringify(entries.map((entry: RouteEntry): Record<string, Object> => entry.toJson()));
}

/** Top of the stack, or null at the root (the tab shell is showing). */
export function routeTop(entries: RouteEntry[]): RouteEntry | null {
  return entries.length > 0 ? entries[entries.length - 1] : null;
}

/**
 * Pushes one level and returns the new stack (the input is never mutated).
 * Re-pushing the route already on top replaces it instead of stacking a
 * duplicate, so a double tap does not need two back presses to undo.
 */
export function pushRoute(entries: RouteEntry[], name: string, param: string): RouteEntry[] {
  if (name.length === 0) {
    return entries.slice();
  }
  if (name === ROUTE_MAIN) {
    return [];
  }
  const next = entries.slice();
  const top = routeTop(next);
  if (top !== null && top.name === name) {
    next[next.length - 1] = new RouteEntry(name, param);
    return next;
  }
  next.push(new RouteEntry(name, param));
  return next.length > ROUTE_MAX_DEPTH ? next.slice(next.length - ROUTE_MAX_DEPTH) : next;
}

/** Pops one level; already at the root is a no-op, never an error. */
export function popRoute(entries: RouteEntry[]): RouteEntry[] {
  return entries.length === 0 ? [] : entries.slice(0, entries.length - 1);
}
