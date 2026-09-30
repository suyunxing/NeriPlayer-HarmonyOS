// SPDX-License-Identifier: GPL-3.0

// Pure presentation math. All coordinates are window-relative vp.
// The transition is driven by native attribute animations (see NowPlayingCurves);
// these functions only evaluate ENDPOINT geometry (amount is 0 or 1) and the
// stagger layout, so the model stays unit-testable without any UI kit.
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
  // 行错峰最大时延（5×18ms）+ 余量：收起结算要等最后一行落定后再卸载模态。
  static readonly ROW_SETTLE_MS: number = 150;

  static clamp(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  static segment(progress: number, start: number, end: number): number {
    return NowPlayingMotion.clamp((progress - start) / (end - start));
  }

  // Plain lerp of the amount; timing/elasticity live in the native curves.
  static panel(amount: number, mini: NowPlayingRect, width: number, height: number): NowPlayingRect {
    return {
      x: mini.x * (1 - amount),
      y: mini.y * (1 - amount),
      width: mini.width + (width - mini.width) * amount,
      height: mini.height + (height - mini.height) * amount
    };
  }

  // Row stagger domain: with endpoint amounts every row flips 0 -> 1 (or 1 -> 0)
  // together; the per-row DELAY (see NowPlayingPage.rowDelay) produces the
  // layered cascade, so these windows only need correct endpoint values.
  static rowProgress(amount: number, row: number): number {
    return NowPlayingMotion.segment(amount, 0.68 + row * 0.038, 0.81 + row * 0.038);
  }

  static rowOffset(amount: number, row: number): number {
    return 48 * (1 - NowPlayingMotion.rowProgress(amount, row));
  }

  static rowOpacity(amount: number, row: number): number {
    return NowPlayingMotion.clamp(NowPlayingMotion.rowProgress(amount, row) * 2);
  }

  // Corners match the bar pill (20) when collapsed and vanish (0) when the
  // panel settles full-screen. Only the 0/1 endpoints are ever evaluated:
  // the panel's borderRadius is a native attribute animation between those
  // endpoints, so intermediate rounding (timing included) is owned entirely
  // by the native panel curve — its slow start keeps the radius near 20
  // through the first half of the flight.
  static panelRadius(amount: number): number {
    return 20 * (1 - NowPlayingMotion.clamp(amount));
  }
}
