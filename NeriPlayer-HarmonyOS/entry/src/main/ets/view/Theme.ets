import { SettingsRepository } from '../data/SettingsRepository';
import { DynamicTheme, TonePalette } from './theme/DynamicTheme';

/**
 * Material3-inspired palette for the HarmonyOS port. Since M8.1 the static
 * palette doubles as the fallback layer of dynamic color: when
 * np.dynamic_color is on and a cover seed has been published to AppStorage
 * ('player.coverSeedHex', written by CoverArtColorCache from the vibrant ->
 * muted -> dominant cover color), the seed-derived TonePalette overrides the
 * accent/surface slots below; everything else stays on the tuned defaults.
 *
 * Note on reactivity: these static methods read AppStorage at call time, so
 * components repaint on their next rebuild — the components that must react
 * instantly to a seed change subscribe to 'player.coverSeedHex' themselves
 * (NowPlayingPage backdrop, MiniPlayer, MainShell).
 */
export class Theme {
  private static cachedPaletteKey: string = '';
  private static cachedPalette: TonePalette | null = null;

  static isDark(): boolean {
    const mode = SettingsRepository.getString(SettingsRepository.KEY_DARK_MODE, 'auto');
    if (mode === 'dark') {
      return true;
    }
    if (mode === 'light') {
      return false;
    }
    const systemDark = AppStorage.get<boolean>('systemDark');
    return systemDark === true;
  }

  /** Active cover seed ('#RRGGBB') or null when dynamic color is off/unseeded. */
  static activeSeed(): string | null {
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, true)) {
      return null;
    }
    const raw = AppStorage.get<string>('player.coverSeedHex');
    if (raw === undefined || raw === null) {
      return null;
    }
    return DynamicTheme.normalizeSeedHex(raw);
  }

  /**
   * Seed-explicit variant for component expressions: ArkUI's minimal-update
   * tracking cannot see through method calls that read AppStorage (see the
   * M7.4 renderer pitfall), so components that must react to seed changes
   * subscribe to 'player.coverSeedHex' themselves and read their @State copy
   * directly in the expression (empty string = static palette).
   */
  static primaryFor(seed: string, dark: boolean): string {
    const normalized = seed.length > 0 ? DynamicTheme.normalizeSeedHex(seed) : null;
    return normalized !== null ? DynamicTheme.tonePalette(normalized, dark).primary : Theme.primary(dark);
  }

  private static palette(dark: boolean): TonePalette | null {
    const seed = Theme.activeSeed();
    if (seed === null) {
      return null;
    }
    const key = `${seed}_${dark ? 'd' : 'l'}`;
    if (Theme.cachedPaletteKey !== key || Theme.cachedPalette === null) {
      Theme.cachedPalette = DynamicTheme.tonePalette(seed, dark);
      Theme.cachedPaletteKey = key;
    }
    return Theme.cachedPalette;
  }

  static background(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.background : (dark ? '#0E0E12' : '#F7F7FA');
  }

  static surface(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.surface : (dark ? '#1A1B21' : '#FFFFFF');
  }

  static surfaceVariant(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.surfaceVariant : (dark ? '#23242C' : '#F0F0F4');
  }

  static surfaceHigh(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.surfaceHigh : (dark ? '#2A2B35' : '#FFFFFF');
  }

  /** '#RRGGBB' -> '#AARRGGBB' (alpha 0x00..0xFF); opaque input stays opaque. */
  static withAlpha(hex: string, alpha: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(alpha)));
    const alphaText = clamped.toString(16).toUpperCase().padStart(2, '0');
    return `#${alphaText}${hex.slice(1)}`;
  }

  /** Translucent surface tint used over backgroundBlurStyle glass layers. */
  static surfaceGlass(dark: boolean): string {
    return Theme.withAlpha(Theme.surface(dark), dark ? 0x80 : 0x99);
  }

  static primary(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.primary : (dark ? '#C9AFFF' : '#7C4DFF');
  }

  static onPrimary(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.onPrimary : (dark ? '#1B0033' : '#FFFFFF');
  }

  static primaryContainer(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.primaryContainer : (dark ? '#4A2A8A' : '#EADDFF');
  }

  static secondary(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.secondary : (dark ? '#B7A8E8' : '#6650A4');
  }

  static tertiary(dark: boolean): string {
    const palette = Theme.palette(dark);
    return palette !== null ? palette.tertiary : (dark ? '#F2B8C6' : '#9C414F');
  }

  static textPrimary(dark: boolean): string {
    return dark ? '#ECECF0' : '#1B1B20';
  }

  static textSecondary(dark: boolean): string {
    return dark ? '#A6A6B0' : '#66666F';
  }

  static textDisabled(dark: boolean): string {
    return dark ? '#6B6B74' : '#B0B0B8';
  }

  static divider(dark: boolean): string {
    return dark ? '#2C2C35' : '#E8E8ED';
  }

  static danger(dark: boolean): string {
    return dark ? '#FF8A8A' : '#C62828';
  }

  static success(dark: boolean): string {
    return dark ? '#7BD88F' : '#2E7D32';
  }

  static warning(dark: boolean): string {
    return dark ? '#FFC46B' : '#B26A00';
  }

  static onSurfaceOverlay(dark: boolean): string {
    return dark ? '#B3000000' : '#0A000000';
  }

  static scrim(dark: boolean): string {
    return dark ? '#CC000000' : '#66000000';
  }

  static cardRadius(): number {
    return 16;
  }

  static shadow(dark: boolean): ShadowOptions {
    return { radius: 12, color: dark ? '#40000000' : '#18000000', offsetY: 3 };
  }
}
