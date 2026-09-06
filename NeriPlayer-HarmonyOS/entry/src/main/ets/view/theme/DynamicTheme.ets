/**
 * Seed-color driven theme overlay, the HarmonyOS counterpart of Android's
 * material-kolor rememberDynamicColorScheme(seedColor, isDark) plus
 * CoverArtColorCache.adjustedAccentColorArgb. Android feeds a single seed
 * (vibrant->muted->dominant from the cover) into material-kolor which emits a
 * whole Material3 color scheme; material-kolor's HCT pipeline is not being
 * re-implemented here — this file derives a deterministic tonal palette in
 * HSL space with the same intent (primary from the seed hue, softened
 * secondary/tertiary, lightly tinted neutrals, safe text colors kept from the
 * static palette). Behavior is pinned by unit tests instead of numerical
 * parity with material-kolor.
 */
import { PaletteSwatch } from './Palette';

export class TonePalette {
  readonly primary: string;
  readonly onPrimary: string;
  readonly primaryContainer: string;
  readonly secondary: string;
  readonly tertiary: string;
  readonly background: string;
  readonly surface: string;
  readonly surfaceVariant: string;
  readonly surfaceHigh: string;

  constructor(
    primary: string,
    onPrimary: string,
    primaryContainer: string,
    secondary: string,
    tertiary: string,
    background: string,
    surface: string,
    surfaceVariant: string,
    surfaceHigh: string
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
  }
}

const DARK_NEUTRAL_BLEND = '#121212';
const LIGHT_NEUTRAL_BLEND = '#FFFFFF';

export class DynamicTheme {
  /** '#RRGGBB' (case-insensitive) or null when malformed. */
  static normalizeSeedHex(input: string): string | null {
    const text = input.trim();
    const body = text.startsWith('#') ? text.slice(1) : text;
    if (!/^[0-9a-fA-F]{6}$/.test(body)) {
      return null;
    }
    return `#${body.toUpperCase()}`;
  }

  static hexToRgb(hex: string): number[] {
    const normalized = DynamicTheme.normalizeSeedHex(hex);
    if (normalized === null) {
      return [128, 128, 128];
    }
    return [
      parseInt(normalized.slice(1, 3), 16),
      parseInt(normalized.slice(3, 5), 16),
      parseInt(normalized.slice(5, 7), 16)
    ];
  }

  static rgbToHex(r: number, g: number, b: number): string {
    const to2 = (v: number): string => {
      const clamped = Math.max(0, Math.min(255, Math.round(v)));
      const text = clamped.toString(16).toUpperCase();
      return text.length < 2 ? `0${text}` : text;
    };
    return `#${to2(r)}${to2(g)}${to2(b)}`;
  }

  private static hslHex(h: number, s: number, l: number): string {
    const rgb = PaletteSwatch.hslToRgb(h, s, l);
    return DynamicTheme.rgbToHex(rgb[0], rgb[1], rgb[2]);
  }

  /**
   * CoverArtColorCache.adjustedAccentColorArgb, 1:1: compress saturation and
   * lock luminance per theme, then blend toward the neutral backdrop so the
   * accent never fights foreground text. Used for the NowPlaying backdrop.
   */
  static adjustedAccentColor(seedHex: string, dark: boolean): string {
    const rgb = DynamicTheme.hexToRgb(seedHex);
    const hsl = PaletteSwatch.rgbToHsl(rgb[0], rgb[1], rgb[2]);
    const h = hsl[0];
    const s = hsl[1];
    let l: number;
    let blendRatio: number;
    let neutral: number[];
    if (dark) {
      // Android clamps dark accent luminance into [0.18, 0.26]; the midpoint
      // 0.22 is used rather than preserving the cover's own luminance.
      l = 0.22;
      blendRatio = 0.22;
      neutral = DynamicTheme.hexToRgb(DARK_NEUTRAL_BLEND);
    } else {
      l = 0.9;
      blendRatio = 0.28;
      neutral = DynamicTheme.hexToRgb(LIGHT_NEUTRAL_BLEND);
    }
    const compressed = Math.min(s * (dark ? 0.38 : 0.32), dark ? 0.3 : 0.24);
    const accentRgb = PaletteSwatch.hslToRgb(h, compressed, l);
    const blended = [
      accentRgb[0] * (1 - blendRatio) + neutral[0] * blendRatio,
      accentRgb[1] * (1 - blendRatio) + neutral[1] * blendRatio,
      accentRgb[2] * (1 - blendRatio) + neutral[2] * blendRatio
    ];
    return DynamicTheme.rgbToHex(blended[0], blended[1], blended[2]);
  }

  /**
   * Deterministic HSL tonal palette from a seed. Light/dark variants keep the
   * seed hue; only saturation/luminance (and slight hue shifts for
   * secondary/tertiary) change, mirroring TonalSpot intent.
   */
  static tonePalette(seedHex: string, dark: boolean): TonePalette {
    const rgb = DynamicTheme.hexToRgb(seedHex);
    const hsl = PaletteSwatch.rgbToHsl(rgb[0], rgb[1], rgb[2]);
    const h = hsl[0];
    const s = hsl[1];
    // Cap chroma for theme use: very saturated seeds (pure red covers) would
    // otherwise produce accent colors that fail contrast on tinted surfaces.
    const themeSat = Math.max(0.12, Math.min(0.62, s * 0.7));
    if (dark) {
      const primary = DynamicTheme.hslHex(h, themeSat, 0.76);
      const onPrimary = DynamicTheme.hslHex(h, Math.min(0.6, themeSat), 0.12);
      const primaryContainer = DynamicTheme.hslHex(h, themeSat * 0.75, 0.3);
      const secondary = DynamicTheme.hslHex(h, themeSat * 0.38, 0.7);
      const tertiary = DynamicTheme.hslHex(h + 48, themeSat * 0.45, 0.74);
      const background = DynamicTheme.hslHex(h, 0.08, 0.06);
      const surface = DynamicTheme.hslHex(h, 0.08, 0.11);
      const surfaceVariant = DynamicTheme.hslHex(h, 0.09, 0.16);
      const surfaceHigh = DynamicTheme.hslHex(h, 0.1, 0.2);
      return new TonePalette(
        primary, onPrimary, primaryContainer, secondary, tertiary,
        background, surface, surfaceVariant, surfaceHigh
      );
    }
    const primary = DynamicTheme.hslHex(h, themeSat, 0.42);
    const onPrimary = '#FFFFFF';
    const primaryContainer = DynamicTheme.hslHex(h, themeSat * 0.5, 0.9);
    const secondary = DynamicTheme.hslHex(h, themeSat * 0.4, 0.42);
    const tertiary = DynamicTheme.hslHex(h + 48, themeSat * 0.45, 0.44);
    const background = DynamicTheme.hslHex(h, 0.1, 0.965);
    const surface = '#FFFFFF';
    const surfaceVariant = DynamicTheme.hslHex(h, 0.1, 0.94);
    const surfaceHigh = '#FFFFFF';
    return new TonePalette(
      primary, onPrimary, primaryContainer, secondary, tertiary,
      background, surface, surfaceVariant, surfaceHigh
    );
  }
}
