import { describe, it, expect } from '@ohos/hypium';
import {
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion
} from '../../../main/ets/sync/SyncModels';
import {
  SyncDeletionState,
  normalizeRecentPlayDeletions
} from '../../../main/ets/sync/SyncDeletionStore';
import { token } from './SongMetadataMergePolicy.test';

function recentDeletion(songId: number, deletedAt: number, deviceId: string): SyncRecentPlayDeletion {
  return new SyncRecentPlayDeletion(songId, 'netease', null, deletedAt, deviceId);
}

export default function syncDeletionStoreTest(): void {
  describe('NormalizeRecentPlayDeletions', () => {
    it('keepsNewestMirrorPerStableKey', 0, () => {
      const normalized = normalizeRecentPlayDeletions([
        recentDeletion(11, 100, 'a'),
        recentDeletion(11, 300, 'b'),
        recentDeletion(12, 200, 'c')
      ]);
      expect(normalized.length).assertEqual(2);
      expect(normalized[0].songId).assertEqual(11);
      expect(normalized[0].deletedAt).assertEqual(300);
      expect(normalized[1].songId).assertEqual(12);
    });

    it('breaksDeletedAtTiesByDeviceId', 0, () => {
      const normalized = normalizeRecentPlayDeletions([
        recentDeletion(11, 200, 'aaa'),
        recentDeletion(11, 200, 'zzz')
      ]);
      expect(normalized.length).assertEqual(1);
      expect(normalized[0].deviceId).assertEqual('zzz');
    });

    it('ordersNewestFirstAndCapsAtFiveHundred', 0, () => {
      const deletions: SyncRecentPlayDeletion[] = [];
      for (let i = 0; i < 502; i++) {
        deletions.push(recentDeletion(i, i, 'device'));
      }
      const normalized = normalizeRecentPlayDeletions(deletions);
      expect(normalized.length).assertEqual(500);
      expect(normalized[0].deletedAt).assertEqual(501);
      expect(normalized[499].deletedAt).assertEqual(2);
    });
  });

  describe('DeletionStateRoundTrip', () => {
    it('roundTripsTombstonesTokensAndBigIds', 0, () => {
      const state = new SyncDeletionState(
        [recentDeletion(11, 300, 'b')],
        [new SyncPlaylistSongDeletion(7, 0, 'netease', null, 200, 'device',
          [token('a', 1)], '9999999999999999999')],
        'device-uuid-1'
      );
      const text = state.toJsonText();
      expect(text.indexOf('9999999999999999999') > 0).assertTrue();
      const restored = SyncDeletionState.fromJsonText(text);
      expect(restored !== null).assertTrue();
      const parsed = restored as SyncDeletionState;
      expect(parsed.deviceId).assertEqual('device-uuid-1');
      expect(parsed.recentPlayDeletions.length).assertEqual(1);
      expect(parsed.recentPlayDeletions[0].deletedAt).assertEqual(300);
      expect(parsed.playlistSongDeletions.length).assertEqual(1);
      expect(parsed.playlistSongDeletions[0].syncSongIdText).assertEqual('9999999999999999999');
      expect(parsed.playlistSongDeletions[0].stableKey()).assertEqual('7|9999999999999999999|netease|');
      expect(parsed.playlistSongDeletions[0].removedMembershipTokens.length).assertEqual(1);
      expect(parsed.playlistSongDeletions[0].removedMembershipTokens[0].deviceId).assertEqual('a');
    });

    it('returnsNullOnCorruptState', 0, () => {
      expect(SyncDeletionState.fromJsonText('not json')).assertNull();
      expect(SyncDeletionState.fromJsonText('')).assertNull();
    });

    it('omitsNullMediaUriButRestoresItAsNull', 0, () => {
      const state = new SyncDeletionState(
        [new SyncRecentPlayDeletion(11, 'netease', 'https://x', 300, 'b')],
        [], 'd'
      );
      const parsed = SyncDeletionState.fromJsonText(state.toJsonText()) as SyncDeletionState;
      expect(parsed.recentPlayDeletions[0].mediaUri).assertEqual('https://x');
      const withoutUri = new SyncDeletionState(
        [new SyncRecentPlayDeletion(11, 'netease', null, 300, 'b')], [], 'd');
      const text = withoutUri.toJsonText();
      expect(text.indexOf('"mediaUri"')).assertEqual(-1);
      const parsedNull = SyncDeletionState.fromJsonText(text) as SyncDeletionState;
      expect(parsedNull.recentPlayDeletions[0].mediaUri).assertNull();
    });
  });
}
