// Pure presentation math. All coordinates are window-relative vp.
export interface NowPlayingRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class NowPlayingMotion {
  static readonly DURATION_MS: number = 800;

  static clamp(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  static segment(progress: number, start: number, end: number): number {
    return NowPlayingMotion.clamp((progress - start) / (end - start));
  }

  static smooth(value: number): number {
    const t = NowPlayingMotion.clamp(value);
    return t * t * (3 - 2 * t);
  }

  // Finite spring settles exactly at both endpoints, including interrupted runs.
  static spring(value: number): number {
    const t = NowPlayingMotion.clamp(value);
    return 1 - Math.pow(1 - t, 3) * Math.cos(t * Math.PI * 2);
  }

  static panel(progress: number, mini: NowPlayingRect, width: number, height: number): NowPlayingRect {
    const t = NowPlayingMotion.smooth(NowPlayingMotion.segment(progress, 0, 0.68));
    return {
      x: mini.x * (1 - t),
      y: mini.y * (1 - t),
      width: mini.width + (width - mini.width) * t,
      height: mini.height + (height - mini.height) * t
    };
  }

  // Rows start only once the panel is almost full height. Reversing the same
  // position curve keeps opacity at one for the first half of the downward move.
  static rowProgress(progress: number, row: number): number {
    return NowPlayingMotion.segment(progress, 0.57 + row * 0.035, 0.82 + row * 0.035);
  }

  static rowOffset(progress: number, row: number): number {
    return 48 * (1 - NowPlayingMotion.spring(NowPlayingMotion.rowProgress(progress, row)));
  }

  static rowOpacity(progress: number, row: number): number {
    const distance = NowPlayingMotion.spring(NowPlayingMotion.rowProgress(progress, row));
    return NowPlayingMotion.clamp(distance * 2);
  }

  static miniReturnOpacity(panelTop: number, windowHeight: number, miniTop: number): number {
    const threshold = Math.min(windowHeight * 0.8, miniTop);
    return NowPlayingMotion.clamp((panelTop - threshold) / Math.max(1, (miniTop - threshold) * 0.5));
  }

  // Corners match the bar pill (20) at both endpoints for a seamless handoff,
  // swell to 34 through the first quarter of the flight, then vanish to 0 as
  // the panel settles full-screen. Symmetric on the way back down.
  static panelRadius(progress: number): number {
    const swell = 20 + 14 * NowPlayingMotion.segment(progress, 0, 0.25);
    return swell * (1 - NowPlayingMotion.segment(progress, 0.3, 0.7));
  }
}
