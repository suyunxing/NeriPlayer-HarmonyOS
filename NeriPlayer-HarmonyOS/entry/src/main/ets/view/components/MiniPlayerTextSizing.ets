// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit b6911607 "feat: implement auto-sizing and font-scale-aware text for
// MiniPlayer (#357)".

/** 文本自适应字号的上下限（fp）。 */
export class MiniPlayerTextAutoSizeRange {
  readonly minFontSize: number;
  readonly maxFontSize: number;

  constructor(minFontSize: number, maxFontSize: number) {
    this.minFontSize = minFontSize;
    this.maxFontSize = maxFontSize;
  }
}

/**
 * 迷你条元信息文字的字号范围解析（上游 resolveMiniPlayerTextAutoSizeRange
 * 直译）。系统字体放大（fontScale>1）时 fp 字号的视觉行高会同步放大，迷你条
 * 行高固定（标题 24vp、副行 20vp），所以字号的视觉尺寸必须封顶：
 *
 *   视觉行高 = 字号(fp) × fontScale × lineHeightEm ≤ maxLineHeight
 *   → maxFontSize = min(baseFontSize, maxLineHeight / lineHeightEm / fontScale)
 *
 * 下限保证缩放后仍有最小可读视觉字号（minVisual / fontScale），且永不越过
 * 上限。行高比 lineHeightEm 缺省 1.5（上游 MINI_PLAYER_METADATA_LINE_HEIGHT_EM）。
 */
export class MiniPlayerTextSizing {
  /** 标题行视觉行高上限（vp）。 */
  static readonly TITLE_LINE_HEIGHT: number = 24;
  /** 副行（歌手/歌词）视觉行高上限（vp）。 */
  static readonly SUB_LINE_HEIGHT: number = 20;
  /** 标题最小可读视觉字号（fp×fontScale 后的下限基准）。 */
  static readonly TITLE_MIN_VISUAL_FONT_SIZE: number = 10;
  /** 副行最小可读视觉字号。 */
  static readonly SUB_MIN_VISUAL_FONT_SIZE: number = 9;
  /** 元信息行高比（行高 = 字号 × 1.5）。 */
  static readonly METADATA_LINE_HEIGHT_EM: number = 1.5;

  static resolveTextAutoSizeRange(baseFontSize: number, maxLineHeight: number,
    fontScale: number, minVisualFontSize: number, lineHeightEm: number): MiniPlayerTextAutoSizeRange {
    const safeFontScale = Math.max(0.01, fontScale);
    const safeLineHeightEm = Math.max(0.01, lineHeightEm);
    const maxFontSize = Math.max(0.1,
      Math.min(baseFontSize, maxLineHeight / safeLineHeightEm / safeFontScale));
    const minFontSize = Math.max(0.1, Math.min(maxFontSize, minVisualFontSize / safeFontScale));
    return new MiniPlayerTextAutoSizeRange(minFontSize, maxFontSize);
  }

  /**
   * 标题字号：行高封顶后的最大值（不随宽度再缩——超宽由跑马灯滚动承接，
   * 对应上游 EllipsizingMiniPlayerText 的取值方式）。
   */
  static titleFontSize(baseFontSize: number, fontScale: number): number {
    return MiniPlayerTextSizing.resolveTextAutoSizeRange(baseFontSize,
      MiniPlayerTextSizing.TITLE_LINE_HEIGHT, fontScale,
      MiniPlayerTextSizing.TITLE_MIN_VISUAL_FONT_SIZE,
      MiniPlayerTextSizing.METADATA_LINE_HEIGHT_EM).maxFontSize;
  }

  /** 副行字号范围：上限封顶行高，下限保最小视觉字号（宽度不足时向下自适应）。 */
  static subLineRange(baseFontSize: number, fontScale: number): MiniPlayerTextAutoSizeRange {
    return MiniPlayerTextSizing.resolveTextAutoSizeRange(baseFontSize,
      MiniPlayerTextSizing.SUB_LINE_HEIGHT, fontScale,
      MiniPlayerTextSizing.SUB_MIN_VISUAL_FONT_SIZE,
      MiniPlayerTextSizing.METADATA_LINE_HEIGHT_EM);
  }
}
