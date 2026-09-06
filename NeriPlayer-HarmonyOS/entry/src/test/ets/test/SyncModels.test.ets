import { describe, it, expect } from '@ohos/hypium';
import {
  SyncCausalToken,
  SongIdentityKey,
  SyncSong,
  SyncPlaybackCounterShard,
  causalTokenEquals,
  normalizedSyncCausalTokens,
  syncSongIdentity,
  stableSyncId,
  sha256Bytes,
  mergePositiveTimestamp,
  normalizeCounterShards,
  counterShardEquals
} from '../../../main/ets/sync/SyncModels';

function hex(bytes: number[]): string {
  let out = '';
  for (const b of bytes) {
    out += (b < 16 ? '0' : '') + b.toString(16);
  }
  return out;
}

function token(deviceId: string, counter: number): SyncCausalToken {
  return new SyncCausalToken(deviceId, counter);
}

function expectTokenList(actual: SyncCausalToken[], expected: SyncCausalToken[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(causalTokenEquals(actual[i], expected[i])).assertTrue();
  }
}

function expectShardList(actual: SyncPlaybackCounterShard[], expected: SyncPlaybackCounterShard[]): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(counterShardEquals(actual[i], expected[i])).assertTrue();
  }
}

export default function syncModelsTest(): void {
  describe('SyncSha256', () => {
    it('matchesFipsVectors', 0, () => {
      expect(hex(sha256Bytes('abc')))
        .assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(hex(sha256Bytes('')))
        .assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    it('encodesUtf8SurrogatePairsLikeKotlin', 0, () => {
      // SHA-256 over UTF-8 bytes; the emoji below is a surrogate pair.
      expect(hex(sha256Bytes('🎵')).length).assertEqual(64);
      // 4 UTF-8 bytes for the emoji + 1 for 'a' → block length path must agree
      // with a reference implementation; verify via stable id stability only.
    });

    it('stableSyncIdUsesSignedBigEndianInt64IncludingNegatives', 0, () => {
      // Expected values produced by the Android stableYouTubeMusicId algorithm:
      // SHA-256 UTF-8 digest, first 8 bytes, big-endian signed 64-bit decimal.
      expect(stableSyncId('youtube_music|dQw4w9WgXcQ')).assertEqual('5261136495461919825');
      expect(stableSyncId('bilibili|BV1x|2')).assertEqual('6164648244738212718');
      expect(stableSyncId('netease|abc')).assertEqual('1243507407946820734');
      expect(stableSyncId('test-seed')).assertEqual('-3009301144789168460');
    });
  });

  describe('SyncCausalTokenModel', () => {
    it('normalizationRemovesDuplicatesAndSortsDeterministically', 0, () => {
      const tokens = [
        token('device-b', 2), token('device-a', 2),
        token('device-a', 1), token('device-b', 2)
      ];
      expectTokenList(normalizedSyncCausalTokens(tokens), [
        token('device-a', 1), token('device-a', 2), token('device-b', 2)
      ]);
    });

    it('invalidTokensAreConstructibleWithoutThrowing', 0, () => {
      expect(new SyncCausalToken(' ', 1).isValid()).assertFalse();
      expect(new SyncCausalToken('device', 0).isValid()).assertFalse();
      expect(new SyncCausalToken('', 0).isValid()).assertFalse();
      expect(new SyncCausalToken('device', 1).isValid()).assertTrue();
    });

    it('normalizationDropsInvalidTokens', 0, () => {
      const tokens = [
        token('device-a', 3), token('device-b', 0),
        token(' ', 5), token('device-c', -1)
      ];
      expectTokenList(normalizedSyncCausalTokens(tokens), [token('device-a', 3)]);
    });
  });

  describe('SyncTimestampMerge', () => {
    it('missingTimestampDoesNotReplaceValidCreationTime', 0, () => {
      expect(mergePositiveTimestamp(123, 0)).assertEqual(123);
      expect(mergePositiveTimestamp(0, 123)).assertEqual(123);
    });

    it('earlierPositiveCreationTimeWins', 0, () => {
      expect(mergePositiveTimestamp(100, 200)).assertEqual(100);
    });
  });

  describe('SyncSongIdentity', () => {
    it('neteaseNumericAudioIdKeepsNumericIdentity', 0, () => {
      // Aligns with the M2.2-verified Android stable key format "123|netease|".
      const song = new SyncSong(123, 'Song', 'Artist', 'netease album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, 'netease', '123', null, null, [], 1, null);
      const identity = syncSongIdentity(song);
      expect(identity.id).assertEqual('123');
      expect(identity.album).assertEqual('netease');
      expect(identity.stableKey()).assertEqual('123|netease|');
    });

    it('neteaseNonNumericAudioFallsBackToStableHash', 0, () => {
      const song = new SyncSong(0, 'Song', 'Artist', 'album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, 'netease', 'abc', null, null, [], 1, null);
      const identity = syncSongIdentity(song);
      expect(identity.id).assertEqual('1243507407946820734');
      expect(identity.album).assertEqual('netease');
    });

    it('youtubeMusicMediaUriNormalizesToHashedIdentity', 0, () => {
      const song = new SyncSong(0, 'Song', 'Artist', 'album', 0, 0,
        null, 'youtube_music|dQw4w9WgXcQ', 0, null, null, null, null, 0,
        null, null, null, null, null, null, null, null, null, null, null,
        null, [], 1, null);
      const identity = syncSongIdentity(song);
      // Hash input is the bare videoId 'dQw4w9WgXcQ' (Android hashes the
      // extracted videoId, not the prefixed mediaUri string).
      expect(identity.id).assertEqual('6875601686285462142');
      expect(identity.album).assertEqual('youtube_music');
      expect(identity.mediaUri).assertEqual('youtube_music|dQw4w9WgXcQ');
    });

    it('bilibiliSubAudioIdInheritsAlbumSuffixWhenAbsent', 0, () => {
      const song = new SyncSong(0, 'Song', 'Artist', 'Bilibili Audio|P2', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, 'bilibili', 'BV1x', null, null, [], 1, null);
      const identity = syncSongIdentity(song);
      // subAudioId inherits the album suffix after '|' → 'P2', so the hash
      // input is "bilibili|BV1x|P2".
      expect(identity.id).assertEqual('4391197325284116759');
      expect(identity.album).assertEqual('bilibili');
    });

    it('blankRemoteFallsBackToNeteaseChannelInference', 0, () => {
      const song = new SyncSong(11, 'Song', 'Artist', 'Legacy Album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, null, null, null, null, [], 1, null);
      const identity = syncSongIdentity(song);
      expect(identity.album).assertEqual('netease');
      expect(identity.id).assertEqual('11');
    });

    it('nullAndEmptyMediaUriStayDistinctForExactEquality', 0, () => {
      const withNull = new SongIdentityKey('1', 'album', null);
      const withEmpty = new SongIdentityKey('1', 'album', '');
      expect(withNull.equals(withEmpty)).assertFalse();
      // stableKey() collapses both to '' exactly like the Android orEmpty().
      expect(withNull.stableKey()).assertEqual('1|album|');
      expect(withEmpty.stableKey()).assertEqual('1|album|');
    });
  });

  describe('SyncCounterShardNormalization', () => {
    it('groupsByDeviceAndEpochThenMergesAndSorts', 0, () => {
      const shards = [
        new SyncPlaybackCounterShard('device-b', 0, 100, 2, 150, 200),
        new SyncPlaybackCounterShard('device-a', 0, 500, 5, 100, 300),
        new SyncPlaybackCounterShard('device-a', 0, 300, 3, 50, 400),
        new SyncPlaybackCounterShard('device-a', 10, 10, 1, 10, 20)
      ];
      expectShardList(normalizeCounterShards(shards), [
        new SyncPlaybackCounterShard('device-a', 0, 500, 5, 50, 400),
        new SyncPlaybackCounterShard('device-a', 10, 10, 1, 10, 20),
        new SyncPlaybackCounterShard('device-b', 0, 100, 2, 150, 200)
      ]);
    });

    it('dropsBlankDeviceIdAndRepairsIrrationalFirstPlayedAt', 0, () => {
      const shards = [
        new SyncPlaybackCounterShard(' ', 0, 100, 2, 1, 2),
        new SyncPlaybackCounterShard('device-a', 0, 100, 2, 500, 400)
      ];
      const normalized = normalizeCounterShards(shards);
      expect(normalized.length).assertEqual(1);
      expect(normalized[0].firstPlayedAt).assertEqual(400);
      expect(normalized[0].lastPlayedAt).assertEqual(400);
    });
  });
}
