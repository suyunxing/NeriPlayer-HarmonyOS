// Pure presentation math. All coordinates are window-relative vp.
export interface NowPlayingRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class NowPlayingMotion {
  // 展开 300ms、收起 400ms（用户指定节奏）。
  static readonly EXPAND_MS: number = 300;
  static readonly COLLAPSE_MS: number = 400;
  // 变速积分 da/dt = (v0 + k·a)/T（收起时对 1−a 同式）：初速 v0 慢、随进程
  // 加速到 v0+k，即「先慢后快」；闭环解保证任意时刻打断/反向都不跳变。
  private static readonly RATE_K: number = 1.9;
  private static readonly RATE_V0: number = 0.35;

  static clamp(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  static segment(progress: number, start: number, end: number): number {
    return NowPlayingMotion.clamp((progress - start) / (end - start));
  }

  /**
   * 单帧推进面板插值量。expand 方向以 a 为自变量、collapse 以 1−a 为自变量
   * 做 ease-in，两个方向都是起步慢、临近终点快；闭环解（指数步进）在任意
   * 帧长下单调、且反向切换时数值连续（速度分布换向，位置不跳）。
   */
  static advance(amount: number, deltaMs: number, expanding: boolean, durationMs: number): number {
    const e = Math.exp(NowPlayingMotion.RATE_K * Math.max(0, deltaMs) / durationMs);
    const grow = (x: number): number =>
      x * e + (NowPlayingMotion.RATE_V0 / NowPlayingMotion.RATE_K) * (e - 1);
    if (expanding) {
      return NowPlayingMotion.clamp(grow(amount));
    }
    return NowPlayingMotion.clamp(1 - grow(1 - amount));
  }

  // Terminal-overshoot spring: values pass the target then settle back, the
  // elastic feel of the reference. Exact 0 at 0 and 1 so reversals stay glued.
  static backOut(value: number): number {
    const t = NowPlayingMotion.clamp(value);
    const c1 = 1.70158;
    const c3 = c1 + 1;
    const u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
  }

  // Panel geometry is a plain lerp of the amount; the slow-then-fast character
  // lives entirely in the amount timeline (advance()).
  static panel(amount: number, mini: NowPlayingRect, width: number, height: number): NowPlayingRect {
    return {
      x: mini.x * (1 - amount),
      y: mini.y * (1 - amount),
      width: mini.width + (width - mini.width) * amount,
      height: mini.height + (height - mini.height) * amount
    };
  }

  // Rows start only once the panel is nearly full height. Reversing the same
  // position curve keeps opacity at one for the first half of the downward move.
  static rowProgress(amount: number, row: number): number {
    return NowPlayingMotion.segment(amount, 0.68 + row * 0.038, 0.81 + row * 0.038);
  }

  static rowOffset(amount: number, row: number): number {
    return 48 * (1 - NowPlayingMotion.backOut(NowPlayingMotion.rowProgress(amount, row)));
  }

  static rowOpacity(amount: number, row: number): number {
    return NowPlayingMotion.clamp(NowPlayingMotion.rowProgress(amount, row) * 2);
  }

  static miniReturnOpacity(panelTop: number, windowHeight: number, miniTop: number): number {
    const threshold = Math.min(windowHeight * 0.8, miniTop);
    return NowPlayingMotion.clamp((panelTop - threshold) / Math.max(1, (miniTop - threshold) * 0.5));
  }

  // Corners match the bar pill (20) at both endpoints for a seamless handoff,
  // swell to 34 through the first quarter of the flight, then vanish to 0 as
  // the panel settles full-screen. Symmetric on the way back down.
  static panelRadius(amount: number): number {
    const swell = 20 + 14 * NowPlayingMotion.segment(amount, 0, 0.25);
    return swell * (1 - NowPlayingMotion.segment(amount, 0.3, 0.7));
  }
}
