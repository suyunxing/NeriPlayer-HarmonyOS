/**
 * Cover-driven full color scheme: score extracted candidates → pick the
 * dominant → snap it to the standard swatch card (CIEDE2000) → clamp in LCh
 * under contrast guardrails → derive light/dark ramps from the snapped hue.
 *
 * Guardrails (numeric, unit-tested):
 * - gray cover (C* < 8) or no usable candidate → neutral fallback scheme
 *   whose accent is the card's nearest neutral;
 * - near-black/near-white candidates (L* < 15 / > 90) are skipped while any
 *   chromatic candidate remains;
 * - accent keeps the swatch hue; L* converges toward 40 (light) / 80 (dark)
 *   in 5-unit steps until it holds ≥3:1 against its surface (WCAG UI);
 * - on-accent text picks white or L*-15 near-black by the 4.5:1 rule;
 * - snap distance ΔE00 > 20 means the color is outside the card's gamut —
 *   keep the original hue instead of shipping a wrong-looking match.
 */
import { ColorScience, Lab, Lch } from './ColorScience';
import { SwatchCard } from './SwatchCard';

/** One extracted cover color with its share of the image. */
export interface CoverCandidate {
  /** '#RRGGBB'. */
  hex: string;
  /** 0..1 share of pixels (effectKit proportion or histogram weight). */
  proportion: number;
}

/** One mode's full derived ramp. All values '#RRGGBB'. */
export class SchemeMode {
  readonly primary: string;
  readonly onPrimary: string;
  readonly primaryContainer: string;
  readonly secondary: string;
  readonly tertiary: string;
  readonly background: string;
  readonly surface: string;
  readonly surfaceVariant: string;
  readonly surfaceHigh: string;
  readonly textPrimary: string;
  readonly textSecondary: string;
  readonly textDisabled: string;
  readonly divider: string;
  readonly tagBg: string;
  readonly tagText: string;

  constructor(
    primary: string,
    onPrimary: string,
    primaryContainer: string,
    secondary: string,
    tertiary: string,
    background: string,
    surface: string,
    surfaceVariant: string,
    surfaceHigh: string,
    textPrimary: string,
    textSecondary: string,
    textDisabled: string,
    divider: string,
    tagBg: string,
    tagText: string
  ) {
    this.primary = primary;
    this.onPrimary = onPrimary;
    this.primaryContainer = primaryContainer;
    this.secondary = secondary;
    this.tertiary = tertiary;
    this.background = background;
    this.surface = surface;
    this.surfaceVariant = surfaceVariant;
    this.surfaceHigh = surfaceHigh;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.textDisabled = textDisabled;
    this.divider = divider;
    this.tagBg = tagBg;
    this.tagText = tagText;
  }
}

const TARGET_CHROMA = 36;
const WEIGHT_PROPORTION = 0.7;
const WEIGHT_CHROMA_ABOVE = 0.3;
const WEIGHT_CHROMA_BELOW = 0.1;
const GRAY_CHROMA = 8;
const DARK_L_MIN = 15;
const LIGHT_L_MAX = 90;
const SNAP_DELTA_MAX = 20;
const ACCENT_CHROMA_MIN = 10;
const ACCENT_CHROMA_MAX = 42;
const ACCENT_UI_CONTRAST = 3.0;
const ACCENT_TEXT_CONTRAST = 4.5;

/** Pure fallback hue candidates are card snaps of these neutrals. */
const FALLBACK_ACCENT_HEX = '#7A7A7A';

export class AccentScheme {
  readonly light: SchemeMode;
  readonly dark: SchemeMode;
  /** Dominant cover color actually used ('#RRGGBB'). */
  readonly dominantHex: string;
  /** Snapped swatch code, or '' when the scheme is the neutral fallback. */
  readonly swatchCode: string;
  /** Snapped swatch hex, or '' on fallback. */
  readonly swatchHex: string;
  /** CIEDE2000 distance from dominant to swatch. */
  readonly snapDeltaE: number;
  /** True when no chromatic candidate existed (gray cover / empty input). */
  readonly isFallback: boolean;

  private constructor(
    light: SchemeMode,
    dark: SchemeMode,
    dominantHex: string,
    swatchCode: string,
    swatchHex: string,
    snapDeltaE: number,
    isFallback: boolean
  ) {
    this.light = light;
    this.dark = dark;
    this.dominantHex = dominantHex;
    this.swatchCode = swatchCode;
    this.swatchHex = swatchHex;
    this.snapDeltaE = snapDeltaE;
    this.isFallback = isFallback;
  }

  /** Full pipeline. Always returns a usable scheme (never null). */
  static from(candidates: CoverCandidate[]): AccentScheme {
    const dominant = AccentScheme.pickDominant(candidates);
    if (dominant === null) {
      return AccentScheme.neutralFallback();
    }
    // pickDominant can still return the largest-share gray when the whole
    // cover is gray — that is the fallback path, not a chromatic scheme.
    const dominantLchCheck = ColorScience.hexToLch(dominant.hex);
    if (dominantLchCheck === null || dominantLchCheck.c < GRAY_CHROMA) {
      return AccentScheme.neutralFallback();
    }
    const nearest = SwatchCard.nearest(dominant.hex);
    let hueDeg: number;
    let swatchCode = '';
    let swatchHex = '';
    let snapDelta = 0;
    if (nearest !== null) {
      const swatchLch = SwatchCard.lchByCode(nearest.swatch.code);
      if (nearest.deltaE <= SNAP_DELTA_MAX && swatchLch !== null && swatchLch.c >= 1) {
        hueDeg = swatchLch.h;
        swatchCode = nearest.swatch.code;
        swatchHex = nearest.swatch.hex;
      } else {
        // Out of card gamut (or hue-unstable swatch): keep the cover's own
        // hue, still record the match.
        hueDeg = dominantLchCheck.h;
        swatchCode = nearest.swatch.code;
        swatchHex = nearest.swatch.hex;
      }
      snapDelta = nearest.deltaE;
    } else {
      hueDeg = dominantLchCheck.h;
    }
    const chroma = dominantLchCheck.c;
    return new AccentScheme(
      AccentScheme.buildMode(hueDeg, chroma, false),
      AccentScheme.buildMode(hueDeg, chroma, true),
      dominant.hex,
      swatchCode,
      swatchHex,
      snapDelta,
      false
    );
  }

  /** Neutral scheme (no chromatic candidate): card-snapped gray accent. */
  static neutralFallback(): AccentScheme {
    const nearest = SwatchCard.nearest(FALLBACK_ACCENT_HEX);
    const lch = nearest !== null ? SwatchCard.lchByCode(nearest.swatch.code) : null;
    const hueDeg = lch !== null ? lch.h : 0;
    const chroma = lch !== null ? Math.max(2, lch.c) : 2;
    return new AccentScheme(
      AccentScheme.buildMode(hueDeg, chroma, false),
      AccentScheme.buildMode(hueDeg, chroma, true),
      FALLBACK_ACCENT_HEX,
      '',
      '',
      nearest !== null ? nearest.deltaE : 0,
      true
    );
  }

  /**
   * Material-Score-inspired pick: proportion dominates, chroma closeness to
   * the target breaks ties. Near-black/white and gray candidates are skipped
   * while any chromatic alternative exists.
   */
  static pickDominant(candidates: CoverCandidate[]): CoverCandidate | null {
    let best: CoverCandidate | null = null;
    let bestScore = -1;
    let bestWithoutDarkWhite: CoverCandidate | null = null;
    let bestScoreDarkWhite = -1;
    for (const candidate of candidates) {
      const lch = ColorScience.hexToLch(candidate.hex);
      if (lch === null) {
        continue;
      }
      const chromaAbove = Math.max(0, lch.c - TARGET_CHROMA) / TARGET_CHROMA;
      const chromaBelow = Math.max(0, TARGET_CHROMA - lch.c) / TARGET_CHROMA;
      const score = WEIGHT_PROPORTION * Math.max(0, candidate.proportion)
        + WEIGHT_CHROMA_ABOVE * chromaAbove
        + WEIGHT_CHROMA_BELOW * chromaBelow;
      const isExtreme = lch.l < DARK_L_MIN || lch.l > LIGHT_L_MAX;
      const isGray = lch.c < GRAY_CHROMA;
      if (!isExtreme && !isGray && score > bestScore) {
        bestScore = score;
        best = candidate;
      }
      if (isGray && score > bestScoreDarkWhite) {
        bestScoreDarkWhite = score;
        bestWithoutDarkWhite = candidate;
      }
    }
    if (best !== null) {
      return best;
    }
    // All-gray covers: keep the largest-share gray so the UI still tints.
    return bestWithoutDarkWhite;
  }

  /** One mode's ramp from hue + base chroma with contrast convergence. */
  private static buildMode(hueDeg: number, baseChroma: number, dark: boolean): SchemeMode {
    const accent = AccentScheme.deriveAccent(hueDeg, baseChroma, dark);
    const surfaceHex = dark
      ? AccentScheme.lchHex(6, 2.5, hueDeg)
      : AccentScheme.lchHex(98.5, 1.5, hueDeg);
    const onAccent = ColorScience.contrastRatio(accent, '#FFFFFF') >= ACCENT_TEXT_CONTRAST
      ? '#FFFFFF'
      : AccentScheme.lchHex(15, Math.min(6, baseChroma * 0.3), hueDeg);
    const chromaSoft = Math.max(4, Math.min(ACCENT_CHROMA_MAX * 0.5, baseChroma * 0.45));
    const neutralC = dark ? 2.5 : 2;
    const textC = dark ? 1.2 : 1.8;
    return new SchemeMode(
      accent,
      onAccent,
      dark
        ? AccentScheme.lchHex(30, chromaSoft, hueDeg)
        : AccentScheme.lchHex(90, chromaSoft, hueDeg),
      dark
        ? AccentScheme.lchHex(75, Math.max(3, baseChroma * 0.35), hueDeg)
        : AccentScheme.lchHex(42, Math.max(3, baseChroma * 0.35), hueDeg),
      dark
        ? AccentScheme.lchHex(78, Math.max(3, baseChroma * 0.32), AccentScheme.shiftHue(hueDeg, 48))
        : AccentScheme.lchHex(45, Math.max(3, baseChroma * 0.32), AccentScheme.shiftHue(hueDeg, 48)),
      dark
        ? AccentScheme.lchHex(6, neutralC, hueDeg)
        : AccentScheme.lchHex(95.5, neutralC, hueDeg),
      dark
        ? AccentScheme.lchHex(11, neutralC + 0.5, hueDeg)
        : AccentScheme.lchHex(98.5, 1.2, hueDeg),
      dark
        ? AccentScheme.lchHex(18, neutralC + 1, hueDeg)
        : AccentScheme.lchHex(92.5, neutralC + 1, hueDeg),
      dark
        ? AccentScheme.lchHex(22, neutralC + 1, hueDeg)
        : AccentScheme.lchHex(99, 1, hueDeg),
      dark
        ? AccentScheme.lchHex(92, textC, hueDeg)
        : AccentScheme.lchHex(14, textC, hueDeg),
      dark
        ? AccentScheme.lchHex(70, textC + 0.3, hueDeg)
        : AccentScheme.lchHex(46, textC + 0.2, hueDeg),
      dark
        ? AccentScheme.lchHex(48, 1, hueDeg)
        : AccentScheme.lchHex(72, 1, hueDeg),
      dark
        ? AccentScheme.lchHex(24, 1, hueDeg)
        : AccentScheme.lchHex(90, 1.2, hueDeg),
      dark
        ? AccentScheme.lchHex(28, 6, hueDeg)
        : AccentScheme.lchHex(92, 5, hueDeg),
      dark
        ? AccentScheme.lchHex(85, 4, hueDeg)
        : AccentScheme.lchHex(38, 5, hueDeg)
    );
  }

  /**
   * Accent = swatch hue, clamped chroma, L* converged to the mode's anchor
   * (40 light / 80 dark) until ≥3:1 against the mode's surface.
   */
  private static deriveAccent(hueDeg: number, baseChroma: number, dark: boolean): string {
    const chroma = Math.max(ACCENT_CHROMA_MIN, Math.min(ACCENT_CHROMA_MAX, baseChroma));
    const anchor = dark ? 80 : 40;
    const minL = dark ? 70 : 28;
    const maxL = dark ? 90 : 52;
    let l = Math.max(minL, Math.min(maxL, anchor));
    const surfaceHex = dark
      ? AccentScheme.lchHex(6, 2.5, hueDeg)
      : AccentScheme.lchHex(95.5, 2, hueDeg);
    for (let attempt = 0; attempt < 7; attempt++) {
      const hex = AccentScheme.lchHex(l, chroma, hueDeg);
      if (ColorScience.contrastRatio(hex, surfaceHex) >= ACCENT_UI_CONTRAST) {
        return hex;
      }
      // Move away from the surface's mid-lightness: down in light mode,
      // up in dark mode.
      l += dark ? 5 : -5;
      if (l < minL || l > maxL) {
        return AccentScheme.lchHex(Math.max(minL, Math.min(maxL, l)), chroma, hueDeg);
      }
    }
    return AccentScheme.lchHex(l, chroma, hueDeg);
  }

  private static shiftHue(h: number, delta: number): number {
    return ((h + delta) % 360 + 360) % 360;
  }

  private static lchHex(l: number, c: number, h: number): string {
    return ColorScience.lchToHexInGamut(l, c, h);
  }
}
