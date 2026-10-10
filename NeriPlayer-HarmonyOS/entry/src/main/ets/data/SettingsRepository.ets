// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Logger } from '../app/Logger';
import { common } from '@kit.AbilityKit';
import { AppPreferences } from './AppPreferences';

/**
 * Typed access to app settings. Values live in AppStorage for reactive UI
 * binding and are durably persisted through AppPreferences (preferences API),
 * so they survive process restarts.
 */
export class SettingsRepository {
  static readonly KEY_DISCLAIMER_ACCEPTED: string = 'np.disclaimer_accepted';
  // Version of the disclaimer/legal docs the user last accepted, compared
  // against util/DisclaimerConsentPolicy.CURRENT_DISCLAIMER_VERSION; empty
  // means the acceptance predates versioning and re-prompts once.
  static readonly KEY_DISCLAIMER_ACCEPTED_VERSION: string = 'np.disclaimer_accepted_version';
  static readonly KEY_ONBOARDING_COMPLETED: string = 'np.onboarding_completed';
  static readonly KEY_DARK_MODE: string = 'np.dark_mode'; // auto | light | dark
  static readonly KEY_DYNAMIC_COLOR: string = 'np.dynamic_color';
  static readonly KEY_DEV_MODE: string = 'np.dev_mode';
  static readonly KEY_ALWAYS_RECORD_LOGS: string = 'np.always_record_logs';
  static readonly KEY_YOUTUBE_ENABLED: string = 'np.youtube_enabled';
  static readonly KEY_LYRIC_FONT_SIZE: string = 'np.lyric_font_size';
  static readonly KEY_PLAYBACK_SPEED: string = 'np.playback_speed';
  static readonly KEY_DEFAULT_START_TAB: string = 'np.default_start_tab';
  static readonly KEY_LAST_CRASH_DETECTED: string = 'np.last_crash_detected';
  // Wall clock of the previous launch. CrashEventWatcher reads it to bound the
  // SafeMode arming window (only a fault newer than the previous launch can be
  // what killed the last session) and immediately replaces it with this
  // launch's timestamp. 0 means "no mark yet" and never arms SafeMode.
  static readonly KEY_LAST_STARTUP_MS: string = 'np.last_startup_ms';
  static readonly KEY_SHOW_LYRICS: string = 'np.show_lyrics';
  static readonly KEY_DOWNLOAD_CONCURRENCY: string = 'np.download_concurrency';
  // Managed download directory (Android download_directory_uri/_label): a
  // user-picked document URI persisted with fileShare grants; empty means the
  // sandbox default <filesDir>/Download/NeriPlayer.
  static readonly KEY_DOWNLOAD_DIRECTORY_URI: string = 'np.download_directory_uri';
  static readonly KEY_DOWNLOAD_DIRECTORY_LABEL: string = 'np.download_directory_label';
  // \n-joined list of formerly applied custom directories: cold start
  // re-activates their fileShare grants so committed files stay playable.
  static readonly KEY_DOWNLOAD_DIRECTORY_HISTORY: string = 'np.download_directory_history';
  // Local music library scan root (backlog §8): a persisted DocumentViewPicker
  // directory that the local library re-scans incrementally.
  static readonly KEY_LOCAL_SCAN_DIRECTORY_URI: string = 'np.local_scan_directory_uri';
  static readonly KEY_LOCAL_SCAN_DIRECTORY_LABEL: string = 'np.local_scan_directory_label';
  // Listen Together server. Android keeps two keys with different clearing
  // rules: _SERVER is what the client dials and is stored only for a custom
  // address (the built-in default is represented by absence, so changing the
  // default later reaches existing installs), while _INPUT is what the settings
  // dialog shows and falls back to _SERVER when unset. Both hold the normalized
  // address. Rules live in listentogether/network/ListenTogetherServerSetting.
  static readonly KEY_LISTEN_TOGETHER_SERVER: string = 'np.listen_together_server';
  static readonly KEY_LISTEN_TOGETHER_SERVER_INPUT: string = 'np.listen_together_server_input';
  // Listen Together identity and room settings (upstream
  // data/listentogether/ListenTogetherPreferences.kt DataStore keys). Identity
  // is not a credential: Android keeps it in plaintext DataStore too.
  static readonly KEY_LISTEN_TOGETHER_LAST_USER_ID: string = 'np.listen_together_last_user_id';
  static readonly KEY_LISTEN_TOGETHER_LAST_USER_UUID: string = 'np.listen_together_last_user_uuid';
  static readonly KEY_LISTEN_TOGETHER_LAST_NICKNAME: string = 'np.listen_together_last_nickname';
  static readonly KEY_LISTEN_TOGETHER_ALLOW_MEMBER_CONTROL: string = 'np.listen_together_allow_member_control';
  static readonly KEY_LISTEN_TOGETHER_AUTO_PAUSE_ON_MEMBER_CHANGE: string = 'np.listen_together_auto_pause_on_member_change';
  static readonly KEY_LISTEN_TOGETHER_SHARE_AUDIO_LINKS: string = 'np.listen_together_share_audio_links';
  // NetEase anonymous device identity for the phone-login risk-control flow
  // (network/NeteasePhoneLogin.ets): a stable device fingerprint across
  // launches plus the MUSIC_A anonymous token once registered. Not a user
  // credential — Android clients persist the same data in plaintext.
  static readonly KEY_NETEASE_DEVICE_IDENTITY: string = 'np.netease_device_identity';
  static readonly KEY_NETEASE_ANON_MUSIC_A: string = 'np.netease_anon_music_a';
  // Audio quality. KEY_AUDIO_QUALITY is the legacy single choice (still the
  // fallback when a per-network key has never been written); the Wi-Fi and
  // cellular keys implement the per-network split (empty = inherit legacy).
  static readonly KEY_AUDIO_QUALITY: string = 'np.audio_quality';
  static readonly KEY_AUDIO_QUALITY_WIFI: string = 'np.audio_quality_wifi';
  static readonly KEY_AUDIO_QUALITY_CELLULAR: string = 'np.audio_quality_cellular';
  // Per-platform cellular tiers (backlog §7, Android mobile_data_* keys):
  // when cellular-follow-default is off, each platform streams at its own
  // cellular tier instead of the shared cellular choice. Empty = inherit.
  static readonly KEY_CELLULAR_FOLLOW_DEFAULT: string = 'np.cellular_follow_default_quality';
  static readonly KEY_CELLULAR_NETEASE_QUALITY: string = 'np.cellular_netease_quality';
  static readonly KEY_CELLULAR_YOUTUBE_QUALITY: string = 'np.cellular_youtube_quality';
  static readonly KEY_CELLULAR_BILI_QUALITY: string = 'np.cellular_bili_quality';
  // Per-platform lyric baseline offsets in ms (backlog §3.7/§6.2, Android
  // cloud_music/qq_music_lyric_default_offset_ms). 0 = no shift.
  static readonly KEY_NETEASE_LYRIC_OFFSET_MS: string = 'np.netease_lyric_offset_ms';
  static readonly KEY_BILI_LYRIC_OFFSET_MS: string = 'np.bili_lyric_offset_ms';
  static readonly KEY_YOUTUBE_LYRIC_OFFSET_MS: string = 'np.youtube_lyric_offset_ms';
  // Keep playing alongside other apps' audio. Maps to the AVPlayer interrupt
  // mode plus ignoring cooperative (SHARE-type) pause hints; a system FORCED
  // interruption still wins on HarmonyOS.
  static readonly KEY_MIX_AUDIO: string = 'np.mix_audio';
  // App-level soft volume applied to AVPlayer (0.0..1.0).
  static readonly KEY_PLAYBACK_VOLUME: string = 'np.playback_volume';
  // Volume fade behind play/pause/track-switch (Android playback_fade_in).
  // The master switch covers both directions; a 0ms duration disables one
  // side individually (Android parity).
  static readonly KEY_PLAYBACK_FADE: string = 'np.playback_fade';
  static readonly KEY_PLAYBACK_FADE_IN_MS: string = 'np.playback_fade_in_ms';
  static readonly KEY_PLAYBACK_FADE_OUT_MS: string = 'np.playback_fade_out_ms';
  // Resume playback automatically after cold start once the queue is restored.
  static readonly KEY_AUTOPLAY_ON_LAUNCH: string = 'np.autoplay_on_launch';
  // Android keep_playback_mode_state (default true): restore loop/shuffle
  // across launches; off resets to list-loop each start (backlog §2.2).
  static readonly KEY_KEEP_PLAYBACK_MODE_STATE: string = 'np.keep_playback_mode_state';
  // NowPlaying backdrop style: 'blur' (blurred cover), 'solid', 'gradient'
  // (flowing cover-color gradient).
  static readonly KEY_NOWPLAYING_BG_STYLE: string = 'np.nowplaying_bg_style';
  // 播放页/歌词页控件大小档位（PlaybackControlSize 序数：0 小 / 1 中 / 2 大，
  // 上游 2644267f）。
  static readonly KEY_NOW_PLAYING_CONTROL_SIZE: string = 'np.nowplaying_control_size';
  static readonly KEY_LYRIC_CONTROL_SIZE: string = 'np.lyric_control_size';
  // Keep the screen on while the full-screen player is open.
  static readonly KEY_KEEP_SCREEN_ON: string = 'np.keep_screen_on';
  // Circular rotating vinyl cover on the full-screen player.
  static readonly KEY_CIRCULAR_COVER: string = 'np.circular_cover';
  // Show the transport capsule at the bottom of the lyric page.
  static readonly KEY_LYRIC_PAGE_CONTROLS: string = 'np.lyric_page_controls';
  // Bottom mini player options.
  static readonly KEY_MINI_NEXT_BUTTON: string = 'np.mini_next_button';
  static readonly KEY_MINI_SHOW_LYRIC: string = 'np.mini_show_lyric';
  static readonly KEY_MINI_EXPAND_AUTOPLAY: string = 'np.mini_expand_autoplay';
  // Lyric typography. Centered alignment, active-line font weight (100..900)
  // and line-spacing multiplier (LINE_SPACING * value).
  static readonly KEY_LYRIC_CENTER: string = 'np.lyric_center';
  static readonly KEY_LYRIC_FONT_WEIGHT: string = 'np.lyric_font_weight';
  static readonly KEY_LYRIC_LINE_SPACING: string = 'np.lyric_line_spacing';
  // Fixed start page: 'last' (follow the tab used last time) or '0'..'3'.
  static readonly KEY_START_PAGE: string = 'np.start_page';
  static readonly KEY_PLAYBACK_CACHE: string = 'np.playback_cache';
  // Playback cache LRU capacity (upstream #499 honor-the-cache-size-setting):
  // number of cached songs; 0 means unlimited.
  static readonly KEY_PLAYBACK_CACHE_MAX_ENTRIES: string = 'np.playback_cache_max_entries';
  static readonly KEY_LYRIC_TRANSLATION: string = 'np.lyric_translation';
  static readonly KEY_LYRIC_PHONETIC: string = 'np.lyric_phonetic';
  static readonly KEY_LYRIC_BLUR: string = 'np.lyric_blur';
  static readonly KEY_LYRIC_OFFSET_MS: string = 'np.lyric_offset_ms';
  // F-2（上游 #417/#349）：非网易云歌曲在线取词的优先源
  // （'lrclib_first' 默认 = 现行阶梯；'netease_first' = 有守卫命中时网易
  // 歌词作主源）；LRCLIB 源基准偏移（按歌词来源叠加，独立于歌曲平台）；
  // 歌词持久缓存开关（命中后离线可看， replays 不再重复请求）。
  static readonly KEY_LYRIC_SOURCE_PREFERENCE: string = 'np.lyric_source_preference';
  static readonly KEY_LRCLIB_LYRIC_OFFSET_MS: string = 'np.lrclib_lyric_offset_ms';
  static readonly KEY_LYRIC_CACHE_ENABLED: string = 'np.lyric_cache_enabled';
  // In-app floating lyric bar (D4 fallback for the Android system overlay).
  static readonly KEY_FLOATING_LYRIC: string = 'np.floating_lyric';
  // Lyric line in the AVSession title slot (notification / AVRCP lyric line).
  static readonly KEY_BT_LYRIC: string = 'np.bt_lyric';
  // NowPlaying blurred-cover strength, Android scale 0..500 (0 disables).
  static readonly KEY_NOWPLAYING_BLUR_STRENGTH: string = 'np.nowplaying_blur_strength';
  static readonly KEY_SAVE_TRAFFIC: string = 'np.save_traffic';
  static readonly KEY_COVER_POLICY: string = 'np.cover_policy';
	  static readonly KEY_DOWNLOAD_MATCH_LYRICS: string = 'np.download_match_lyrics';
	  static readonly KEY_LANGUAGE: string = 'np.language';
  static readonly KEY_NETEASE_LOGGED: string = 'np.netease_logged';
  static readonly KEY_NETEASE_AUTO_FALLBACK: string = 'np.netease_auto_fallback';
  static readonly KEY_BILIBILI_LOGGED: string = 'np.bilibili_logged';
  static readonly KEY_YOUTUBE_LOGGED: string = 'np.youtube_logged';
  // GitHub sync config; the token itself lives in the asset store (GitHubConfigRepository).
  static readonly KEY_GITHUB_OWNER: string = 'np.github_owner';
  static readonly KEY_GITHUB_REPO: string = 'np.github_repo';
  static readonly KEY_GITHUB_DATA_SAVER: string = 'np.github_data_saver';
  // Alias of KEY_GITHUB_DATA_SAVER: data-saver is one global switch shared by
  // the GitHub and WebDAV transports (Android parity); the legacy key value
  // is kept so existing user settings survive.
  static readonly KEY_SYNC_DATA_SAVER: string = 'np.github_data_saver';
  // Auto silent sync (backlog §1.5): Android auto-sync defaults off; here it
  // covers the debounced mutation sync + throttled startup sync.
  static readonly KEY_SYNC_AUTO: string = 'np.sync_auto';
  // Source playlist auto sync (网易云歌单/B站收藏夹 → 本地镜像歌单). The master
  // switch only gates the automatic triggers; mirrors keep syncing manually.
  static readonly KEY_SOURCE_SYNC_ENABLED: string = 'np.source_sync_enabled';
  static readonly KEY_SOURCE_SYNC_THROTTLE_MINUTES: string = 'np.source_sync_throttle_minutes';
  // WebDAV credentials live in AssetStore; only endpoint metadata is persisted here.
  static readonly KEY_WEBDAV_SERVER_URL: string = 'np.webdav_server_url';
  static readonly KEY_WEBDAV_BASE_PATH: string = 'np.webdav_base_path';
  // Explicit application HTTP proxy (mainland access to YouTube). Empty host
  // / 0 port means direct connection. HttpClient also publishes this as the
  // NetworkKit application proxy so media components can share the setting.
  static readonly KEY_PROXY_HOST: string = 'np.proxy_host';
  static readonly KEY_PROXY_PORT: string = 'np.proxy_port';

  private static defaults: [string, boolean | string | number][] = [
    [SettingsRepository.KEY_DISCLAIMER_ACCEPTED, false],
    [SettingsRepository.KEY_DISCLAIMER_ACCEPTED_VERSION, ''],
    [SettingsRepository.KEY_ONBOARDING_COMPLETED, false],
    [SettingsRepository.KEY_DARK_MODE, 'auto'],
    [SettingsRepository.KEY_DYNAMIC_COLOR, true],
    [SettingsRepository.KEY_DEV_MODE, false],
    [SettingsRepository.KEY_ALWAYS_RECORD_LOGS, false],
    [SettingsRepository.KEY_YOUTUBE_ENABLED, true],
    [SettingsRepository.KEY_LYRIC_FONT_SIZE, 16],
    [SettingsRepository.KEY_PLAYBACK_SPEED, 1.0],
    [SettingsRepository.KEY_DEFAULT_START_TAB, 0],
    [SettingsRepository.KEY_LAST_CRASH_DETECTED, false],
    [SettingsRepository.KEY_LAST_STARTUP_MS, 0],
    [SettingsRepository.KEY_SHOW_LYRICS, true],
    [SettingsRepository.KEY_DOWNLOAD_CONCURRENCY, 6],
    [SettingsRepository.KEY_DOWNLOAD_DIRECTORY_URI, ''],
    [SettingsRepository.KEY_DOWNLOAD_DIRECTORY_LABEL, ''],
    [SettingsRepository.KEY_DOWNLOAD_DIRECTORY_HISTORY, ''],
    [SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_URI, ''],
    [SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_LABEL, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_SERVER_INPUT, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_ID, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_UUID, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_LAST_NICKNAME, ''],
    [SettingsRepository.KEY_LISTEN_TOGETHER_ALLOW_MEMBER_CONTROL, true],
    [SettingsRepository.KEY_LISTEN_TOGETHER_AUTO_PAUSE_ON_MEMBER_CHANGE, true],
    [SettingsRepository.KEY_LISTEN_TOGETHER_SHARE_AUDIO_LINKS, true],
    [SettingsRepository.KEY_AUDIO_QUALITY, 'standard'],
    [SettingsRepository.KEY_AUDIO_QUALITY_WIFI, ''],
    [SettingsRepository.KEY_AUDIO_QUALITY_CELLULAR, ''],
    [SettingsRepository.KEY_CELLULAR_FOLLOW_DEFAULT, true],
    [SettingsRepository.KEY_CELLULAR_NETEASE_QUALITY, ''],
    [SettingsRepository.KEY_CELLULAR_YOUTUBE_QUALITY, ''],
    [SettingsRepository.KEY_CELLULAR_BILI_QUALITY, ''],
    [SettingsRepository.KEY_NETEASE_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_BILI_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_YOUTUBE_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_MIX_AUDIO, true],
    [SettingsRepository.KEY_PLAYBACK_VOLUME, 1.0],
    [SettingsRepository.KEY_PLAYBACK_FADE, true],
    [SettingsRepository.KEY_PLAYBACK_FADE_IN_MS, 500],
    [SettingsRepository.KEY_PLAYBACK_FADE_OUT_MS, 500],
    [SettingsRepository.KEY_AUTOPLAY_ON_LAUNCH, false],
    [SettingsRepository.KEY_KEEP_PLAYBACK_MODE_STATE, true],
    [SettingsRepository.KEY_NOWPLAYING_BG_STYLE, 'blur'],
    [SettingsRepository.KEY_NOW_PLAYING_CONTROL_SIZE, 1],
    [SettingsRepository.KEY_LYRIC_CONTROL_SIZE, 1],
    [SettingsRepository.KEY_KEEP_SCREEN_ON, false],
    [SettingsRepository.KEY_CIRCULAR_COVER, false],
    [SettingsRepository.KEY_LYRIC_PAGE_CONTROLS, true],
    [SettingsRepository.KEY_MINI_NEXT_BUTTON, true],
    [SettingsRepository.KEY_MINI_SHOW_LYRIC, true],
    [SettingsRepository.KEY_MINI_EXPAND_AUTOPLAY, false],
    [SettingsRepository.KEY_LYRIC_CENTER, true],
    [SettingsRepository.KEY_LYRIC_FONT_WEIGHT, 500],
    [SettingsRepository.KEY_LYRIC_LINE_SPACING, 1.0],
    [SettingsRepository.KEY_START_PAGE, 'last'],
    // Opt-in: AVDownloaderManager playback cache is Wi-Fi only but still
    // re-downloads a copy of what was just streamed.
    [SettingsRepository.KEY_PLAYBACK_CACHE, false],
    [SettingsRepository.KEY_PLAYBACK_CACHE_MAX_ENTRIES, 24],
    [SettingsRepository.KEY_LYRIC_TRANSLATION, true],
    [SettingsRepository.KEY_LYRIC_PHONETIC, false],
    [SettingsRepository.KEY_LYRIC_BLUR, true],
    [SettingsRepository.KEY_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_LYRIC_SOURCE_PREFERENCE, 'lrclib_first'],
    [SettingsRepository.KEY_LRCLIB_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_LYRIC_CACHE_ENABLED, true],
    [SettingsRepository.KEY_FLOATING_LYRIC, false],
    [SettingsRepository.KEY_BT_LYRIC, false],
    [SettingsRepository.KEY_NOWPLAYING_BLUR_STRENGTH, 300],
    [SettingsRepository.KEY_SAVE_TRAFFIC, false],
    [SettingsRepository.KEY_COVER_POLICY, 'always'],
    [SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, true],
    [SettingsRepository.KEY_LANGUAGE, 'zh'],
    // Login flags must be in defaults so the saved value is reloaded from
    // preferences on cold start (doInit re-derives it from the restored
    // credential bundle; both must agree for @StorageLink consumers).
    [SettingsRepository.KEY_NETEASE_LOGGED, false],
    [SettingsRepository.KEY_BILIBILI_LOGGED, false],
    [SettingsRepository.KEY_NETEASE_AUTO_FALLBACK, true],
    [SettingsRepository.KEY_GITHUB_OWNER, ''],
    [SettingsRepository.KEY_GITHUB_REPO, ''],
    // Android defaults data saver to true (writes GZIP+proto); this port
    // uploads JSON until the compact writer lands (M5.2b record), reads all formats.
    [SettingsRepository.KEY_GITHUB_DATA_SAVER, false],
    [SettingsRepository.KEY_SYNC_AUTO, false],
    [SettingsRepository.KEY_SOURCE_SYNC_ENABLED, true],
    [SettingsRepository.KEY_SOURCE_SYNC_THROTTLE_MINUTES, 30],
    [SettingsRepository.KEY_WEBDAV_SERVER_URL, ''],
    [SettingsRepository.KEY_WEBDAV_BASE_PATH, ''],
    [SettingsRepository.KEY_PROXY_HOST, ''],
    [SettingsRepository.KEY_PROXY_PORT, 0]
  ];

  private static initialized: boolean = false;
  private static initPromise: Promise<void> | null = null;

  static initialize(context?: common.Context): Promise<void> {
    if (SettingsRepository.initPromise !== null) {
      return SettingsRepository.initPromise;
    }
    if (context !== undefined) {
      AppPreferences.init(context);
    }
    SettingsRepository.initPromise = SettingsRepository.doInitialize();
    return SettingsRepository.initPromise;
  }

  private static async doInitialize(): Promise<void> {
    if (SettingsRepository.initialized) {
      return;
    }
    // Seed AppStorage with defaults first so UI renders before async load.
    for (const entry of SettingsRepository.defaults) {
      if (AppStorage.get(entry[0]) === undefined) {
        AppStorage.setOrCreate(entry[0], entry[1]);
      }
    }
    try {
      const saved = await AppPreferences.getAll();
      for (const entry of SettingsRepository.defaults) {
        const key = entry[0];
        const value = saved[key];
        if (value !== undefined && value !== null) {
          AppStorage.setOrCreate(key, value);
        }
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`SettingsRepository.load failed: ${e.message}`);
    }
    SettingsRepository.initialized = true;
  }

  static getBoolean(key: string, def: boolean): boolean {
    const value = AppStorage.get<boolean>(key);
    return value === undefined || value === null ? def : value;
  }

  static setBoolean(key: string, value: boolean): void {
    AppStorage.setOrCreate(key, value);
    AppPreferences.putBoolean(key, value).catch((error: Error) => {
      Logger.warn(`SettingsRepository.persist(${key}) failed: ${error.message}`);
    });
  }

  static getString(key: string, def: string): string {
    const value = AppStorage.get<string>(key);
    return value === undefined || value === null ? def : value;
  }

  static setString(key: string, value: string): void {
    AppStorage.setOrCreate(key, value);
    AppPreferences.putString(key, value).catch((error: Error) => {
      Logger.warn(`SettingsRepository.persist(${key}) failed: ${error.message}`);
    });
  }

  static getNumber(key: string, def: number): number {
    const value = AppStorage.get<number>(key);
    return value === undefined || value === null ? def : value;
  }

  static setNumber(key: string, value: number): void {
    AppStorage.setOrCreate(key, value);
    AppPreferences.putNumber(key, value).catch((error: Error) => {
      Logger.warn(`SettingsRepository.persist(${key}) failed: ${error.message}`);
    });
  }
}
