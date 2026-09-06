/**
 * Pure layout math for the centered auto-scrolling lyric view. Everything is
 * static and side-effect free so it stays unit-testable without ArkUI.
 *
 * Coordinate domain is the ArkUI "scroll position" s >= 0: a content point y
 * renders at viewport y - s, so line i is vertically centered exactly when
 * tops[i] + heights[i] / 2 - s = viewportHeight / 2.
 */
export interface LyricLineLayout {
  /** Distance from content top to the top of line i; length == line count. */
  tops: number[];
  heights: number[];
  contentHeight: number;
}

export class LyricScrollMath {
  /**
   * Accumulates row heights into absolute tops. The spacing after the last
   * line belongs to the bottom padding gap, not to a following line, so an
   * empty list yields padTop + padBottom of pure padding.
   */
  static buildLayout(heights: number[], spacing: number, padTop: number, padBottom: number): LyricLineLayout {
    const tops: number[] = [];
    let y = padTop;
    for (let i = 0; i < heights.length; i++) {
      tops.push(y);
      y += heights[i] + spacing;
    }
    const contentHeight = heights.length > 0 ? y - spacing + padBottom : padTop + padBottom;
    return { tops, heights, contentHeight };
  }

  /** Scroll position that centers line `index`, clamped into the valid range. */
  static targetScroll(index: number, layout: LyricLineLayout, viewportHeight: number): number {
    if (index < 0 || index >= layout.tops.length) {
      return 0;
    }
    const maxScroll = Math.max(0, layout.contentHeight - viewportHeight);
    const center = layout.tops[index] + layout.heights[index] / 2;
    return Math.max(0, Math.min(maxScroll, center - viewportHeight / 2));
  }

  /** Line whose center is closest to the viewport center; -1 when empty. */
  static centeredIndex(scroll: number, layout: LyricLineLayout, viewportHeight: number): number {
    if (layout.tops.length === 0) {
      return -1;
    }
    const viewportCenter = scroll + viewportHeight / 2;
    let best = 0;
    let bestDistance = Number.MAX_VALUE;
    for (let i = 0; i < layout.tops.length; i++) {
      const distance = Math.abs(layout.tops[i] + layout.heights[i] / 2 - viewportCenter);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }
}
