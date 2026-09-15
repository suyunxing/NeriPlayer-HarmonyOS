// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Central registry of innertube player client profiles (D2 decision:
 * keep client versions in one place so drift is a single-line change).
 *
 * IOS is the primary path: the M6.0 spike (docs/YTMUSIC_M60_SPIKE.md,
 * 2026-08-19) verified that the anonymous IOS player API returns direct
 * downloadable googlevideo URLs without cipher or PoToken. The Android
 * client chain (WEB_REMIX -> TVHTML5 -> TVHTML5 downgraded) always yields
 * ciphered URLs, which is why Android needs the EJS solver; HarmonyOS skips
 * that by leading with IOS.
 */

/** Fallback IOS version for drift retry (downgrade trick, see withVersion). */
export const YTM_IOS_DOWNGRADED_VERSION: string = '19.29.1';

export class YtmClientProfile {
  readonly key: string;
  readonly clientName: string;
  readonly clientId: string;
  readonly clientVersion: string;
  readonly userAgent: string;
  readonly origin: string;
  readonly platform: string;
  readonly deviceMake: string;
  readonly deviceModel: string;
  readonly osName: string;
  readonly osVersion: string;

  constructor(
    key: string,
    clientName: string,
    clientId: string,
    clientVersion: string,
    userAgent: string,
    origin: string,
    platform: string,
    deviceMake: string,
    deviceModel: string,
    osName: string,
    osVersion: string
  ) {
    this.key = key;
    this.clientName = clientName;
    this.clientId = clientId;
    this.clientVersion = clientVersion;
    this.userAgent = userAgent;
    this.origin = origin;
    this.platform = platform;
    this.deviceMake = deviceMake;
    this.deviceModel = deviceModel;
    this.osName = osName;
    this.osVersion = osVersion;
  }

  /**
   * Clone with a different clientVersion (and the matching version inside
   * the user agent, e.g. "com.google.ios.youtube/<v>(...)") so a rejected
   * version can be retried once on an older one without touching the
   * canonical profile.
   */
  withVersion(version: string): YtmClientProfile {
    const versionNeedle = `/${this.clientVersion}`;
    const uaIndex = this.userAgent.indexOf(versionNeedle);
    const userAgent =
      uaIndex >= 0
        ? this.userAgent.substring(0, uaIndex) +
          `/${version}` +
          this.userAgent.substring(uaIndex + versionNeedle.length)
        : this.userAgent;
    return new YtmClientProfile(
      this.key,
      this.clientName,
      this.clientId,
      version,
      userAgent,
      this.origin,
      this.platform,
      this.deviceMake,
      this.deviceModel,
      this.osName,
      this.osVersion
    );
  }
}

export class YtmClientCatalog {
  /** Primary playback client, spike-verified anonymous direct URLs. */
  static readonly IOS: YtmClientProfile = new YtmClientProfile(
    'ios',
    'IOS',
    '5',
    '21.03.2',
    'com.google.ios.youtube/21.03.2(iPhone16,2; U; CPU iOS 18_7_2 like Mac OS X; US)',
    'https://www.youtube.com',
    'MOBILE',
    'Apple',
    'iPhone16,2',
    'iOS',
    '18.7.2.22H124'
  );

  /**
   * Fallback profile: the probe's tvhtml5_downgraded template (version
   * downgraded to 5.20260114 + simplified Cobalt UA, platform=TV per the
   * spike matrix). Its responses only carry signatureCipher URLs, so a hit
   * here surfaces the needs_decrypt error (M6.2) until a solver exists (M6.3).
   */
  static readonly TVHTML5_DOWNGRADED: YtmClientProfile = new YtmClientProfile(
    'tvhtml5_downgraded',
    'TVHTML5',
    '7',
    '5.20260114',
    'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
    'https://www.youtube.com',
    'TV',
    '',
    '',
    '',
    ''
  );

  /** Resolution order for the M6.2 fallback chain. */
  static playerChain(): YtmClientProfile[] {
    return [YtmClientCatalog.IOS, YtmClientCatalog.TVHTML5_DOWNGRADED];
  }
}
