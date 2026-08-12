import { SettingsRepository } from '../data/SettingsRepository';

/**
 * Material3-inspired palette for the HarmonyOS port. Dynamic color (seed color
 * from wallpaper/cover art) remains a roadmap item; light/dark modes are fully
 * wired to SettingsRepository + system color mode.
 */
export class Theme {
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

  static background(dark: boolean): string {
    return dark ? '#0E0E12' : '#F7F7FA';
  }

  static surface(dark: boolean): string {
    return dark ? '#1A1B21' : '#FFFFFF';
  }

  static surfaceVariant(dark: boolean): string {
    return dark ? '#23242C' : '#F0F0F4';
  }

  static surfaceHigh(dark: boolean): string {
    return dark ? '#2A2B35' : '#FFFFFF';
  }

  static primary(dark: boolean): string {
    return dark ? '#C9AFFF' : '#7C4DFF';
  }

  static onPrimary(dark: boolean): string {
    return dark ? '#1B0033' : '#FFFFFF';
  }

  static primaryContainer(dark: boolean): string {
    return dark ? '#4A2A8A' : '#EADDFF';
  }

  static secondary(dark: boolean): string {
    return dark ? '#B7A8E8' : '#6650A4';
  }

  static tertiary(dark: boolean): string {
    return dark ? '#F2B8C6' : '#9C414F';
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
