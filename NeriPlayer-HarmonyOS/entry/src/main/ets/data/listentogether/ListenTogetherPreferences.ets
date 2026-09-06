/**
 * Port of data/listentogether/ListenTogetherPreferences.kt: the identity
 * (user id / uuid / nickname) and the three room settings, plus the config
 * snapshot/restore pair used by config backup.
 *
 * Divergences from upstream, both deliberate:
 * - Storage goes through SettingsRepository (AppStorage + preferences file)
 *   instead of a private DataStore, matching every other setting in this port.
 *   Upstream's key names survive as the `np.listen_together_*` suffixes.
 * - The worker-address half (WORKER_BASE_URL / _INPUT and its set-time
 *   migration) already lives in listentogether/settings/
 *   ListenTogetherServerPreferences.ets from M7.2; snapshot()/restore()
 *   delegate to it instead of duplicating the rules.
 *
 * The decision logic (sanitization chains, restore branching, entry counting)
 * lives in listentogether/settings/ListenTogetherConfigSnapshot.ets so it stays
 * unit-testable without the storage layer.
 */
import { SettingsRepository } from '../SettingsRepository';
import { Logger } from '../../app/Logger';
import {
  ListenTogetherConfigSnapshot,
  buildListenTogetherConfigSnapshot,
  normalizeListenTogetherSnapshotForRestore,
  resolveStoredListenTogetherNickname
} from '../../listentogether/settings/ListenTogetherConfigSnapshot';
import { buildDefaultListenTogetherNickname, buildListenTogetherUserUuid } from '../../listentogether/invite/ListenTogetherIdentity';
import { sanitizeListenTogetherNicknameOrNull } from '../../listentogether/validation/ListenTogetherFieldValidation';

export class ListenTogetherPreferences {
  // ---- identity ----------------------------------------------------------

  /** Upstream `userUuidFlow`. */
  static userUuid(): string {
    return SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_UUID, '').trim();
  }

  static setUserUuid(value: string): void {
    const normalized = value.trim();
    if (normalized.length === 0) {
      SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_UUID, '');
      return;
    }
    SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_UUID, normalized);
  }

  /** Upstream `getOrCreateUserUuid()`: blank generates and persists. */
  static getOrCreateUserUuid(): string {
    const existing = ListenTogetherPreferences.userUuid();
    if (existing.length > 0) {
      return existing;
    }
    const generated = buildListenTogetherUserUuid();
    ListenTogetherPreferences.setUserUuid(generated);
    return generated;
  }

  /** Upstream `resetUserUuid()`: always generates a fresh identity. */
  static resetUserUuid(): string {
    const generated = buildListenTogetherUserUuid();
    ListenTogetherPreferences.setUserUuid(generated);
    return generated;
  }

  /** Upstream `nicknameFlow`: saved nickname, else sanitized legacy user id. */
  static nickname(): string {
    const legacyId = SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_ID, '');
    return resolveStoredListenTogetherNickname(
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_NICKNAME, ''),
      legacyId.length > 0 ? legacyId : null
    );
  }

  static setNickname(value: string): void {
    const normalized = value.trim();
    SettingsRepository.setString(
      SettingsRepository.KEY_LISTEN_TOGETHER_LAST_NICKNAME,
      normalized
    );
  }

  /**
   * Upstream `getOrCreateNickname()`: sanitized saved nickname, then sanitized
   * legacy user id, then a generated default; the winner is persisted.
   */
  static getOrCreateNickname(): string {
    const saved = sanitizeListenTogetherNicknameOrNull(
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_NICKNAME, '')
    );
    let resolved = saved === null ? '' : saved;
    if (resolved.length === 0) {
      const legacyId = SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_ID, '');
      const fromLegacy = sanitizeListenTogetherNicknameOrNull(legacyId.length > 0 ? legacyId : null);
      resolved = fromLegacy === null ? '' : fromLegacy;
    }
    if (resolved.length === 0) {
      resolved = buildDefaultListenTogetherNickname();
    }
    ListenTogetherPreferences.setNickname(resolved);
    return resolved;
  }

  /** Upstream `LAST_USER_ID`: the legacy numeric account id, when known. */
  static lastUserId(): string {
    return SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_ID, '').trim();
  }

  static setLastUserId(value: string): void {
    SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_ID, value.trim());
  }

  // ---- room settings -----------------------------------------------------

  static allowMemberControl(): boolean {
    return SettingsRepository.getBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_ALLOW_MEMBER_CONTROL, true);
  }

  static setAllowMemberControl(value: boolean): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_ALLOW_MEMBER_CONTROL, value);
  }

  static autoPauseOnMemberChange(): boolean {
    return SettingsRepository.getBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_AUTO_PAUSE_ON_MEMBER_CHANGE, true);
  }

  static setAutoPauseOnMemberChange(value: boolean): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_AUTO_PAUSE_ON_MEMBER_CHANGE, value);
  }

  static shareAudioLinks(): boolean {
    return SettingsRepository.getBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_SHARE_AUDIO_LINKS, true);
  }

  static setShareAudioLinks(value: boolean): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_SHARE_AUDIO_LINKS, value);
  }

  // ---- snapshot / restore ------------------------------------------------

  /** Upstream `snapshot()` over all seven fields. */
  static snapshot(): ListenTogetherConfigSnapshot {
    return buildListenTogetherConfigSnapshot(
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, ''),
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER_INPUT, ''),
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_USER_UUID, ''),
      SettingsRepository.getString(SettingsRepository.KEY_LISTEN_TOGETHER_LAST_NICKNAME, ''),
      ListenTogetherPreferences.allowMemberControl(),
      ListenTogetherPreferences.autoPauseOnMemberChange(),
      ListenTogetherPreferences.shareAudioLinks()
    );
  }

  /** Upstream `restore()`: normalized values land, blanks remove keys. */
  static restore(snapshot: ListenTogetherConfigSnapshot): void {
    const restored = normalizeListenTogetherSnapshotForRestore(snapshot);
    try {
      // The server half mirrors upstream's two-key write; the normalization
      // above has already decided which keys end up removed ('').
      SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER, restored.workerBaseUrl);
      SettingsRepository.setString(SettingsRepository.KEY_LISTEN_TOGETHER_SERVER_INPUT, restored.workerBaseUrlInput);
      ListenTogetherPreferences.setUserUuid(restored.userUuid);
      ListenTogetherPreferences.setNickname(restored.nickname);
      ListenTogetherPreferences.setAllowMemberControl(restored.allowMemberControl);
      ListenTogetherPreferences.setAutoPauseOnMemberChange(restored.autoPauseOnMemberChange);
      ListenTogetherPreferences.setShareAudioLinks(restored.shareAudioLinks);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`ListenTogetherPreferences.restore failed: ${e.message}`);
    }
  }
}
