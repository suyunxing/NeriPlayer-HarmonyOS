/**
 * Tests for listentogether/settings/ListenTogetherConfigSnapshot.ets — the pure
 * half of the ListenTogetherPreferences port (upstream
 * data/listentogether/ListenTogetherPreferences.kt's snapshot()/restore()
 * branching plus data/config/AppConfigBackup.kt's snapshot model).
 *
 * The ''-means-remove convention and the three input-dropping rules are the
 * whole point: they decide what a config restore may silently change.
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherConfigSnapshot,
  buildListenTogetherConfigSnapshot,
  normalizeListenTogetherSnapshotForRestore,
  resolveStoredListenTogetherNickname
} from '../../../main/ets/listentogether/settings/ListenTogetherConfigSnapshot';

// Base URLs are stored normalized, which strips the trailing slash.
const CUSTOM_SERVER: string = 'https://lt.example';
const DEFAULT_SERVER: string = 'https://neriplayer.hancat.work';
const OVERLONG_NICKNAME: string = 'a'.repeat(25);

function fullSnapshot(): ListenTogetherConfigSnapshot {
  const snapshot = new ListenTogetherConfigSnapshot();
  snapshot.workerBaseUrl = CUSTOM_SERVER;
  snapshot.workerBaseUrlInput = CUSTOM_SERVER;
  snapshot.userUuid = 'uuid-1';
  snapshot.nickname = 'Nick';
  snapshot.allowMemberControl = false;
  snapshot.autoPauseOnMemberChange = false;
  snapshot.shareAudioLinks = false;
  return snapshot;
}

export default function listenTogetherConfigSnapshotTest() {
  describe('ListenTogetherConfigSnapshot', () => {
    it('counts only non-blank text entries plus the three settings', 0, () => {
      expect(new ListenTogetherConfigSnapshot().entryCount()).assertEqual(3);

      const snapshot = fullSnapshot();
      snapshot.workerBaseUrlInput = '';
      expect(snapshot.entryCount()).assertEqual(6);
      expect(fullSnapshot().entryCount()).assertEqual(7);
    });

    it('resolves the nickname from saved value, then legacy user id', 0, () => {
      expect(resolveStoredListenTogetherNickname('Nick', '123')).assertEqual('Nick');
      // Unsanitary saved name falls through to the legacy id.
      expect(resolveStoredListenTogetherNickname(OVERLONG_NICKNAME, '123')).assertEqual('123');
      expect(resolveStoredListenTogetherNickname(null, '  123  ')).assertEqual('123');
      expect(resolveStoredListenTogetherNickname(null, null)).assertEqual('');
      expect(resolveStoredListenTogetherNickname(OVERLONG_NICKNAME, OVERLONG_NICKNAME)).assertEqual('');
    });

    it('builds a snapshot with the default server represented by absence', 0, () => {
      const custom = buildListenTogetherConfigSnapshot(
        CUSTOM_SERVER, '', ' uuid-1 ', 'Nick', false, true, false);

      expect(custom.workerBaseUrl).assertEqual(CUSTOM_SERVER);
      // Blank input falls back to the saved server.
      expect(custom.workerBaseUrlInput).assertEqual(CUSTOM_SERVER);
      expect(custom.userUuid).assertEqual('uuid-1');
      expect(custom.nickname).assertEqual('Nick');
      expect(custom.allowMemberControl).assertFalse();
      expect(custom.autoPauseOnMemberChange).assertTrue();
      expect(custom.shareAudioLinks).assertFalse();

      const onDefault = buildListenTogetherConfigSnapshot(
        DEFAULT_SERVER, null, null, null, true, true, true);
      expect(onDefault.workerBaseUrl).assertEqual('');
      expect(onDefault.workerBaseUrlInput).assertEqual('');
      expect(onDefault.userUuid).assertEqual('');
      expect(onDefault.nickname).assertEqual('');
    });

    it('restore drops a default or blank server back to absence', 0, () => {
      const fromDefault = fullSnapshot();
      fromDefault.workerBaseUrl = DEFAULT_SERVER;
      const normalizedDefault = normalizeListenTogetherSnapshotForRestore(fromDefault);
      expect(normalizedDefault.workerBaseUrl).assertEqual('');
      // Upstream keeps the input independently of the server: a non-blank,
      // non-default input survives even when the server itself falls back to
      // the built-in default.
      expect(normalizedDefault.workerBaseUrlInput).assertEqual(CUSTOM_SERVER);

      const fromBlank = fullSnapshot();
      fromBlank.workerBaseUrl = '   ';
      fromBlank.workerBaseUrlInput = '';
      const normalizedBlank = normalizeListenTogetherSnapshotForRestore(fromBlank);
      expect(normalizedBlank.workerBaseUrl).assertEqual('');
      // Blank input falls back to nothing once the server is gone too.
      expect(normalizedBlank.workerBaseUrlInput).assertEqual('');
    });

    it('restore keeps a distinct custom input but drops echoes and defaults', 0, () => {
      const distinct = fullSnapshot();
      distinct.workerBaseUrlInput = 'https://mirror.example';
      const normalizedDistinct = normalizeListenTogetherSnapshotForRestore(distinct);
      expect(normalizedDistinct.workerBaseUrl).assertEqual(CUSTOM_SERVER);
      expect(normalizedDistinct.workerBaseUrlInput).assertEqual('https://mirror.example');

      // Input equal to the restored server is redundant: drop it.
      const echo = fullSnapshot();
      echo.workerBaseUrlInput = CUSTOM_SERVER;
      echo.workerBaseUrl = CUSTOM_SERVER;
      expect(normalizeListenTogetherSnapshotForRestore(echo).workerBaseUrlInput).assertEqual('');

      // Restoring the default must not look like a custom entry.
      const defaultInput = fullSnapshot();
      defaultInput.workerBaseUrl = CUSTOM_SERVER;
      defaultInput.workerBaseUrlInput = DEFAULT_SERVER;
      expect(normalizeListenTogetherSnapshotForRestore(defaultInput).workerBaseUrlInput).assertEqual('');
    });

    it('restore trims identity, sanitizes the nickname, keeps settings', 0, () => {
      const snapshot = fullSnapshot();
      snapshot.userUuid = '  uuid-2  ';
      snapshot.nickname = OVERLONG_NICKNAME;
      snapshot.allowMemberControl = true;
      snapshot.autoPauseOnMemberChange = false;
      snapshot.shareAudioLinks = true;

      const restored = normalizeListenTogetherSnapshotForRestore(snapshot);

      expect(restored.userUuid).assertEqual('uuid-2');
      expect(restored.nickname).assertEqual('');
      expect(restored.allowMemberControl).assertTrue();
      expect(restored.autoPauseOnMemberChange).assertFalse();
      expect(restored.shareAudioLinks).assertTrue();
    });
  });
}
