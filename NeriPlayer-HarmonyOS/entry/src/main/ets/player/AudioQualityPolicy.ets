import { SettingsRepository } from '../data/SettingsRepository';

/**
 * Per-network audio quality resolution (playback settings: Wi-Fi and cellular
 * each pick their own tier, falling back to the legacy single choice).
 *
 * resolve() is a pure function over its arguments so the tier logic stays
 * unit-testable; effective()/currentOrDefault() are the impure wrappers that
 * read the reactive settings store.
 */
export class AudioQualityPolicy {
  static readonly DEFAULT_QUALITY: string = 'standard';

  /**
   * Picks the quality tier for the current network: the per-network choice
   * when the user has ever written one, otherwise the legacy single choice.
   * Empty per-network values mean "never set", not "use the default".
   */
  static resolve(isWifi: boolean, wifiQuality: string, cellularQuality: string,
    legacyQuality: string): string {
    const specific = isWifi ? wifiQuality : cellularQuality;
    if (specific.length > 0) {
      return specific;
    }
    return legacyQuality.length > 0 ? legacyQuality : AudioQualityPolicy.DEFAULT_QUALITY;
  }

  /** Reactive read for UI: the effective tier shown by the settings rows. */
  static currentOrDefault(isWifi: boolean): string {
    return AudioQualityPolicy.resolve(
      isWifi,
      SettingsRepository.getString(SettingsRepository.KEY_AUDIO_QUALITY_WIFI, ''),
      SettingsRepository.getString(SettingsRepository.KEY_AUDIO_QUALITY_CELLULAR, ''),
      SettingsRepository.getString(SettingsRepository.KEY_AUDIO_QUALITY,
        AudioQualityPolicy.DEFAULT_QUALITY)
    );
  }

  /**
   * The tier to request while streaming. `wifi` comes from the caller's
   * network probe (util/NetworkStatus.isWifi); offline/unknown defaults to
   * the Wi-Fi tier so playback resolution never blocks on connectivity.
   */
  static effective(wifi: boolean): string {
    return AudioQualityPolicy.currentOrDefault(wifi);
  }
}
