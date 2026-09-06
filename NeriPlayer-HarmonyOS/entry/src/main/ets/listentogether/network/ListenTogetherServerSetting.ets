/**
 * Persistence semantics of the two Listen Together server keys, ported from
 * data/listentogether/ListenTogetherPreferences.kt (`workerBaseUrlFlow`,
 * `workerBaseUrlInputFlow`, `setWorkerBaseUrl`, `setWorkerBaseUrlInput`).
 *
 * The pair looks redundant until you read the rules; it is not:
 * - `server` is what the client dials. It is stored ONLY when the address
 *   normalizes to something that is not the built-in default, so "use the
 *   default" is represented by absence rather than by storing the default URL.
 *   That way a future change of the default host reaches existing installs.
 * - `input` is what the settings dialog shows. It falls back to `server` when
 *   unset, so a user who configured a custom host still sees it.
 *
 * Kept pure (no preferences access) so the rules are unit-testable; the thin
 * platform wrapper is `listentogether/settings/ListenTogetherServerPreferences`.
 */
import {
  configuredListenTogetherBaseUrlOrNull,
  isDefaultListenTogetherBaseUrl
} from '../invite/ListenTogetherBaseUrlResolver';

/** The two values to persist. An empty string means "remove the key". */
export class ListenTogetherServerSetting {
  server: string = '';
  input: string = '';
}

/**
 * Upstream `setWorkerBaseUrl` + `setWorkerBaseUrlInput` for a dialog-confirmed
 * address. Returns null when the user typed something non-blank that cannot be
 * normalized, which the dialog reports as `server_input_invalid` instead of
 * silently falling back to the default.
 */
export function listenTogetherServerSettingForSave(rawInput: string): ListenTogetherServerSetting | null {
  const trimmed = rawInput.trim();
  const normalized = configuredListenTogetherBaseUrlOrNull(trimmed);
  if (trimmed.length > 0 && normalized === null) {
    return null;
  }
  const setting = new ListenTogetherServerSetting();
  if (normalized === null || isDefaultListenTogetherBaseUrl(normalized)) {
    // Blank or the default: both keys are cleared, matching prefs.remove().
    return setting;
  }
  setting.server = normalized;
  setting.input = normalized;
  return setting;
}

/**
 * Upstream `workerBaseUrlFlow`: the configured custom server, or '' when the
 * built-in default should be used. Re-normalizing on read matters because the
 * stored value may predate a normalizer change.
 */
export function listenTogetherSavedCustomServer(rawSavedServer: string): string {
  const normalized = configuredListenTogetherBaseUrlOrNull(rawSavedServer);
  if (normalized === null || isDefaultListenTogetherBaseUrl(normalized)) {
    return '';
  }
  return normalized;
}

/** Upstream `workerBaseUrlInputFlow`: saved input, falling back to the server. */
export function listenTogetherSavedServerInput(rawSavedInput: string, rawSavedServer: string): string {
  const savedInput = rawSavedInput.trim();
  return savedInput.length > 0 ? savedInput : listenTogetherSavedCustomServer(rawSavedServer);
}
