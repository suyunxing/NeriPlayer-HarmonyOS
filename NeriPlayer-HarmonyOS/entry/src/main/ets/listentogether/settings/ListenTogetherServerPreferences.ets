/**
 * Thin bridge between the Listen Together server-address rules and the app's
 * settings store. Keeps the rules themselves in the kit-free
 * `network/ListenTogetherServerSetting` so they stay unit-testable; this file
 * only reads and writes the two keys.
 *
 * Upstream's `ListenTogetherPreferences` also runs a one-time migration that
 * copies a custom `WORKER_BASE_URL` into `WORKER_BASE_URL_INPUT` when the latter
 * is blank. That is not needed here: the read-side fallback in
 * `listenTogetherSavedServerInput` covers the same case without writing on read,
 * and it keeps covering it for values written by any future code path.
 */
import { SettingsRepository } from '../../data/SettingsRepository';
import { resolveListenTogetherBaseUrl } from '../invite/ListenTogetherBaseUrlResolver';
import {
  ListenTogetherServerSetting,
  listenTogetherSavedCustomServer,
  listenTogetherSavedServerInput,
  listenTogetherServerSettingForSave
} from '../network/ListenTogetherServerSetting';

/** The configured custom server, or '' when the built-in default is in use. */
export function listenTogetherCustomServer(): string {
  return listenTogetherSavedCustomServer(
    SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, '')
  );
}

/** What the settings dialog should prefill. */
export function listenTogetherServerInput(): string {
  return listenTogetherSavedServerInput(
    SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER_INPUT, ''),
    SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, '')
  );
}

/** The base URL to dial: the custom server if configured, else the default. */
export function resolveListenTogetherServerBaseUrl(): string {
  const custom = listenTogetherCustomServer();
  return resolveListenTogetherBaseUrl(custom.length > 0 ? custom : null);
}

/**
 * Persists a dialog-confirmed address. Returns the stored custom server ('' when
 * the default is now in use), or null when the input could not be normalized —
 * in which case nothing is written, so a typo cannot wipe a working address.
 */
export function saveListenTogetherServer(rawInput: string): string | null {
  const setting: ListenTogetherServerSetting | null = listenTogetherServerSettingForSave(rawInput);
  if (setting === null) {
    return null;
  }
  SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, setting.server);
  SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER_INPUT, setting.input);
  return setting.server;
}
