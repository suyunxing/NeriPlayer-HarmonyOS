/**
 * Port of the pure half of data/config/AppConfigBackup.kt's
 * `ListenTogetherConfigSnapshot` plus the decision branches buried in
 * data/listentogether/ListenTogetherPreferences.kt's `snapshot()`/`restore()`.
 *
 * Kit-free on purpose: the storage bridge (data/listentogether/
 * ListenTogetherPreferences.ets) applies these decisions through
 * SettingsRepository, and the normalization rules are exactly the part worth
 * unit-testing — a removed key and an empty value share the '' representation,
 * which is why every rule below ends in "blank means remove".
 */
import { configuredListenTogetherBaseUrlOrNull, isDefaultListenTogetherBaseUrl } from '../invite/ListenTogetherBaseUrlResolver';
import { sanitizeListenTogetherNicknameOrNull } from '../validation/ListenTogetherFieldValidation';

export class ListenTogetherConfigSnapshot {
  workerBaseUrl: string = '';
  workerBaseUrlInput: string = '';
  userUuid: string = '';
  nickname: string = '';
  allowMemberControl: boolean = true;
  autoPauseOnMemberChange: boolean = true;
  shareAudioLinks: boolean = true;

  /** Upstream `entryCount()`: how many non-default entries a backup carries. */
  entryCount(): number {
    let count = 0;
    if (this.workerBaseUrl.length > 0) {
      count++;
    }
    if (this.workerBaseUrlInput.length > 0) {
      count++;
    }
    if (this.userUuid.length > 0) {
      count++;
    }
    if (this.nickname.length > 0) {
      count++;
    }
    // The three room settings always count, matching upstream.
    count += 3;
    return count;
  }
}

/**
 * Upstream `nicknameFlow`'s chain: the saved nickname if it survives
 * sanitization, else the sanitized legacy userId, else nothing.
 */
export function resolveStoredListenTogetherNickname(
  savedNickname: string | null,
  savedUserId: string | null
): string {
  const fromNickname = sanitizeListenTogetherNicknameOrNull(savedNickname);
  if (fromNickname !== null) {
    return fromNickname;
  }
  const fromLegacyId = sanitizeListenTogetherNicknameOrNull(savedUserId);
  return fromLegacyId === null ? '' : fromLegacyId;
}

/**
 * Upstream `snapshot()`: reads raw stored values and derives the effective
 * configuration. The custom server only counts when it is not the built-in
 * default (absence represents the default), and the input falls back to the
 * saved server when unset.
 */
export function buildListenTogetherConfigSnapshot(
  storedServerUrl: string | null,
  storedServerInput: string | null,
  storedUserUuid: string | null,
  storedNickname: string | null,
  allowMemberControl: boolean,
  autoPauseOnMemberChange: boolean,
  shareAudioLinks: boolean
): ListenTogetherConfigSnapshot {
  const snapshot = new ListenTogetherConfigSnapshot();
  const configured = configuredListenTogetherBaseUrlOrNull(storedServerUrl);
  snapshot.workerBaseUrl =
    configured !== null && !isDefaultListenTogetherBaseUrl(configured) ? configured : '';
  const trimmedInput = storedServerInput === null ? '' : storedServerInput.trim();
  snapshot.workerBaseUrlInput = trimmedInput.length > 0 ? trimmedInput : snapshot.workerBaseUrl;
  snapshot.userUuid = storedUserUuid === null ? '' : storedUserUuid.trim();
  snapshot.nickname = resolveStoredListenTogetherNickname(storedNickname, null);
  snapshot.allowMemberControl = allowMemberControl;
  snapshot.autoPauseOnMemberChange = autoPauseOnMemberChange;
  snapshot.shareAudioLinks = shareAudioLinks;
  return snapshot;
}

/**
 * Upstream `restore()`'s branching, computed instead of written: the returned
 * snapshot holds exactly what should land in storage, where '' means "remove
 * the key". Rules, in upstream order:
 * - server: keep only a non-default configured address;
 * - input: dropped when blank, equal to the restored server, or itself a
 *   default address (restoring the default must not look like a custom entry);
 * - uuid: trimmed, blank dropped;
 * - nickname: sanitized, blank dropped;
 * - the three room settings pass through untouched.
 */
export function normalizeListenTogetherSnapshotForRestore(
  snapshot: ListenTogetherConfigSnapshot
): ListenTogetherConfigSnapshot {
  const restored = new ListenTogetherConfigSnapshot();
  const configured = configuredListenTogetherBaseUrlOrNull(snapshot.workerBaseUrl);
  restored.workerBaseUrl =
    configured !== null && !isDefaultListenTogetherBaseUrl(configured) ? configured : '';

  const trimmedInput = snapshot.workerBaseUrlInput.trim();
  const inputConfigured = configuredListenTogetherBaseUrlOrNull(trimmedInput);
  const inputIsDefault = inputConfigured !== null && isDefaultListenTogetherBaseUrl(inputConfigured);
  if (trimmedInput.length === 0 || trimmedInput === restored.workerBaseUrl || inputIsDefault) {
    restored.workerBaseUrlInput = '';
  } else {
    restored.workerBaseUrlInput = trimmedInput;
  }

  restored.userUuid = snapshot.userUuid.trim();
  const nickname = sanitizeListenTogetherNicknameOrNull(snapshot.nickname);
  restored.nickname = nickname === null ? '' : nickname;
  restored.allowMemberControl = snapshot.allowMemberControl;
  restored.autoPauseOnMemberChange = snapshot.autoPauseOnMemberChange;
  restored.shareAudioLinks = snapshot.shareAudioLinks;
  return restored;
}
