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
  static readonly KEY_SHOW_LYRICS: string = 'np.show_lyrics';
  static readonly KEY_DOWNLOAD_CONCURRENCY: string = 'np.download_concurrency';
  static readonly KEY_LISTEN_TOGETHER_SERVER: string = 'np.listen_together_server';
  static readonly KEY_AUDIO_QUALITY: string = 'np.audio_quality';
  static readonly KEY_LYRIC_TRANSLATION: string = 'np.lyric_translation';
  static readonly KEY_LYRIC_PHONETIC: string = 'np.lyric_phonetic';
  static readonly KEY_LYRIC_BLUR: string = 'np.lyric_blur';
  static readonly KEY_LYRIC_OFFSET_MS: string = 'np.lyric_offset_ms';
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
  // WebDAV credentials live in AssetStore; only endpoint metadata is persisted here.
  static readonly KEY_WEBDAV_SERVER_URL: string = 'np.webdav_server_url';
  static readonly KEY_WEBDAV_BASE_PATH: string = 'np.webdav_base_path';

  private static defaults: [string, boolean | string | number][] = [
    [SettingsRepository.KEY_DISCLAIMER_ACCEPTED, false],
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
    [SettingsRepository.KEY_SHOW_LYRICS, true],
    [SettingsRepository.KEY_DOWNLOAD_CONCURRENCY, 6],
    [SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, ''],
    [SettingsRepository.KEY_AUDIO_QUALITY, 'standard'],
    [SettingsRepository.KEY_LYRIC_TRANSLATION, true],
    [SettingsRepository.KEY_LYRIC_PHONETIC, false],
    [SettingsRepository.KEY_LYRIC_BLUR, true],
    [SettingsRepository.KEY_LYRIC_OFFSET_MS, 0],
    [SettingsRepository.KEY_SAVE_TRAFFIC, false],
    [SettingsRepository.KEY_COVER_POLICY, 'always'],
    [SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, true],
    [SettingsRepository.KEY_LANGUAGE, 'zh'],
    [SettingsRepository.KEY_NETEASE_AUTO_FALLBACK, true],
    [SettingsRepository.KEY_GITHUB_OWNER, ''],
    [SettingsRepository.KEY_GITHUB_REPO, ''],
    // Android defaults data saver to true (writes GZIP+proto); this port
    // uploads JSON until the compact writer lands (M5.2b record), reads all formats.
    [SettingsRepository.KEY_GITHUB_DATA_SAVER, false],
    [SettingsRepository.KEY_WEBDAV_SERVER_URL, ''],
    [SettingsRepository.KEY_WEBDAV_BASE_PATH, '']
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
