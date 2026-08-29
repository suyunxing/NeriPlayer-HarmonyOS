/**
 * Maps an AccentScheme onto the official 51-slot CustomColors theme
 * (ThemeControl/WithTheme) so built-in components (Toggle, Slider, Menu,
 * TextInput, LoadingProgress, …) follow the cover-derived palette too.
 * Semantic colors (warning/alert/confirm) keep the system defaults — they
 * must not shift with the cover hue.
 *
 * This is the only bridge between the pure scheme engine and
 * @kit.ArkUI theme types; AccentScheme itself stays platform-free for tests.
 */
import { CustomColors, CustomTheme } from '@kit.ArkUI';
import { AccentScheme, SchemeMode } from './AccentScheme';

export class SchemeCustomTheme {
  /**
   * Both light and dark ramps are always populated (CustomTheme.darkColors,
   * API 20+); WithTheme's colorMode picks which one applies.
   */
  static build(scheme: AccentScheme | null): CustomTheme {
    const lightColors: CustomColors = SchemeCustomTheme.fromMode(
      scheme !== null ? scheme.light : null
    );
    const darkColors: CustomColors = SchemeCustomTheme.fromMode(
      scheme !== null ? scheme.dark : null
    );
    const theme: CustomTheme = {
      colors: lightColors,
      darkColors: darkColors
    };
    return theme;
  }

  private static fromMode(mode: SchemeMode | null): CustomColors {
    const colors: CustomColors = {};
    if (mode === null) {
      // Empty CustomColors = system defaults; the static Theme fallbacks
      // already cover our own components before the first scheme arrives.
      return colors;
    }
    colors.brand = mode.primary;
    colors.fontPrimary = mode.textPrimary;
    colors.fontSecondary = mode.textSecondary;
    colors.fontTertiary = mode.textDisabled;
    colors.fontFourth = mode.textDisabled;
    colors.fontEmphasize = mode.primary;
    colors.fontOnPrimary = mode.onPrimary;
    colors.iconPrimary = mode.textPrimary;
    colors.iconSecondary = mode.textSecondary;
    colors.iconEmphasize = mode.primary;
    colors.iconOnPrimary = mode.onPrimary;
    colors.backgroundPrimary = mode.background;
    colors.backgroundSecondary = mode.surface;
    colors.backgroundTertiary = mode.surfaceVariant;
    colors.backgroundFourth = mode.surfaceHigh;
    colors.backgroundEmphasize = mode.primary;
    colors.compForegroundPrimary = mode.textPrimary;
    colors.compBackgroundPrimary = mode.surfaceVariant;
    colors.compBackgroundSecondary = mode.tagBg;
    colors.compBackgroundTertiary = mode.tagBg;
    colors.compBackgroundEmphasize = mode.primary;
    colors.compEmphasizeSecondary = mode.primaryContainer;
    colors.compEmphasizeTertiary = mode.tagBg;
    colors.compDivider = mode.divider;
    colors.interactiveHover = mode.tagBg;
    colors.interactivePressed = mode.primaryContainer;
    colors.interactiveActive = mode.primary;
    colors.interactiveSelect = mode.primary;
    return colors;
  }
}
