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
   * Fallback profile reserved for M6.2: downgrade trick copied from the
   * probe/tvhtml5_downgraded template. Its responses only carry
   * signatureCipher URLs, so it is useless until a cipher solver exists.
   */
  static readonly TVHTML5_DOWNGRADED: YtmClientProfile = new YtmClientProfile(
    'tvhtml5_downgraded',
    'TVHTML5',
    '7',
    '5.20260114',
    'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
    'https://www.youtube.com',
    'MOBILE',
    '',
    '',
    '',
    ''
  );
}
