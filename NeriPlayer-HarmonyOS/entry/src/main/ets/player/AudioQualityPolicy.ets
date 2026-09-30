// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SettingsRepository } from '../data/SettingsRepository';
import { MusicPlatform } from '../model/MusicPlatform';

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

  /**
   * Per-platform cellular tier (backlog §7, Android mobile_data_* keys): on
   * cellular with follow-default off, the platform-specific choice wins over
   * the shared cellular tier. Pure over its arguments for unit-testability.
   */
  static resolvePlatform(isWifi: boolean, followDefault: boolean,
    platformCellularQuality: string, sharedQuality: string): string {
    if (!isWifi && !followDefault && platformCellularQuality.length > 0) {
      return platformCellularQuality;
    }
    return sharedQuality;
  }

  /** Reactive read for a specific platform's streaming tier. */
  static effectiveForPlatform(wifi: boolean, platform: MusicPlatform): string {
    const shared = AudioQualityPolicy.effective(wifi);
    if (wifi) {
      return shared;
    }
    const follow = SettingsRepository.getBoolean(SettingsRepository.KEY_CELLULAR_FOLLOW_DEFAULT, true);
    const platformKey = platform === MusicPlatform.NETEASE
      ? SettingsRepository.KEY_CELLULAR_NETEASE_QUALITY
      : platform === MusicPlatform.BILIBILI
        ? SettingsRepository.KEY_CELLULAR_BILI_QUALITY
        : SettingsRepository.KEY_CELLULAR_YOUTUBE_QUALITY;
    const specific = SettingsRepository.getString(platformKey, '');
    return AudioQualityPolicy.resolvePlatform(wifi, follow, specific, shared);
  }
}
