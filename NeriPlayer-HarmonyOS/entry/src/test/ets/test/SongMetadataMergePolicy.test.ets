import { describe, it, expect } from '@ohos/hypium';
import {
  SyncSong,
  SyncCausalToken,
  syncSongEquals,
  CURRENT_SYNC_METADATA_VERSION,
  LEGACY_SYNC_METADATA_VERSION
} from '../../../main/ets/sync/SyncModels';
import {
  canonicalPayloadKey,
  selectDeterministicPayload,
  resolveSelectedPayload,
  resolveAddedAt
} from '../../../main/ets/sync/SongMetadataMergePolicy';

export function song(
  id: number,
  name: string,
  album: string = 'Album',
  artist: string = 'Artist',
  channelId: string | null = null,
  audioId: string | null = null,
  mediaUri: string | null = null,
  addedAt: number = 0,
  membershipTokens: SyncCausalToken[] = [],
  syncMetadataVersion: number = CURRENT_SYNC_METADATA_VERSION
): SyncSong {
  return new SyncSong(id, name, artist, album, 0, 0, null, mediaUri, addedAt,
    null, null, null, null, 0, null, null, null, null, null, null, null, null,
    channelId, audioId, null, null, membershipTokens, syncMetadataVersion, null);
}

export function token(deviceId: string, counter: number): SyncCausalToken {
  return new SyncCausalToken(deviceId, counter);
}

export default function songMetadataMergePolicyTest(): void {
  describe('CanonicalPayloadKey', () => {
    it('lengthPrefixDominatesLexicographicComparison', 0, () => {
      // "9:Old Album" > "10:New Album" because '9' > '1' — the length prefix
      // prevents shorter-value ambiguity, mirroring the Android joinToString.
      const oldAlbum = song(1, 'Song', 'Old Album');
      const newAlbum = song(1, 'Song', 'New Album');
      expect(canonicalPayloadKey(oldAlbum) > canonicalPayloadKey(newAlbum)).assertTrue();
    });

    it('coversAllTwentySevenFieldsInOrder', 0, () => {
      const base = song(1, 'A', 'B', 'C', 'ch', 'au', 'mu', 7);
      const shifted = song(2, 'A', 'B', 'C', 'ch', 'au', 'mu', 7);
      expect(canonicalPayloadKey(base) < canonicalPayloadKey(shifted)).assertTrue();
    });
  });

  describe('SelectDeterministicPayload', () => {
    it('prefersHigherMetadataVersion', 0, () => {
      const legacyVersion = new SyncSong(1, 'Rich legacy', 'Artist', 'Album', 0, 0,
        null, null, 0, null, null, null, null, 0, null, null, null, null, null,
        null, null, null, null, null, null, null, [], LEGACY_SYNC_METADATA_VERSION, null);
      const current = song(1, 'Bare', 'Album');
      expect(selectDeterministicPayload([legacyVersion, current]).name).assertEqual('Bare');
    });

    it('breaksVersionTiesByCanonicalKeyRegardlessOfOrder', 0, () => {
      const z = song(1, 'Z metadata');
      const a = song(1, 'A metadata');
      expect(selectDeterministicPayload([a, z]).name).assertEqual('Z metadata');
      expect(selectDeterministicPayload([z, a]).name).assertEqual('Z metadata');
    });
  });

  describe('ResolveSelectedPayload', () => {
    it('currentSelectionIsAuthoritativeAndKeepsClearedFields', 0, () => {
      const selected = song(1, 'Song');
      selected.matchedLyric = null;
      selected.customName = null;
      const richCandidate = song(1, 'Song');
      richCandidate.matchedLyric = '[00:01.00]old lyric';
      richCandidate.customName = 'Old custom title';
      const resolved = resolveSelectedPayload(selected, [selected, richCandidate]);
      expect(resolved.matchedLyric).assertNull();
      expect(resolved.customName).assertNull();
    });

    it('legacySelectionIsReplacedByCurrentCandidatePayload', 0, () => {
      const legacySelected = song(1, 'Custom title', 'Album', 'Artist', null, null, null, 900,
        [], LEGACY_SYNC_METADATA_VERSION);
      const current = song(1, 'Original');
      current.matchedLyric = '[00:01.00]lyric';
      current.customName = 'Custom title';
      const resolved = resolveSelectedPayload(legacySelected, [legacySelected, current]);
      expect(resolved.name).assertEqual('Original');
      expect(resolved.matchedLyric).assertEqual('[00:01.00]lyric');
      expect(syncSongEquals(resolved, current)).assertTrue();
    });

    it('allLegacySelectionFillsBlanksFromCandidates', 0, () => {
      const selected = song(1, 'Song', 'Album', 'Artist', null, null, null, 0,
        [], LEGACY_SYNC_METADATA_VERSION);
      const candidate = song(1, 'Song', 'Album', 'Artist', null, null, 'https://media', 500,
        [], LEGACY_SYNC_METADATA_VERSION);
      candidate.coverUrl = 'https://cover';
      const resolved = resolveSelectedPayload(selected, [selected, candidate]);
      expect(resolved.mediaUri).assertEqual('https://media');
      expect(resolved.coverUrl).assertEqual('https://cover');
    });
  });

  describe('ResolveAddedAt', () => {
    it('keepsPositiveSelection', 0, () => {
      expect(resolveAddedAt(500, [song(1, 'a', '', '', null, null, null, 999)])).assertEqual(500);
    });

    it('inheritsMaxCandidateWhenSelectionMissing', 0, () => {
      expect(resolveAddedAt(0, [
        song(1, 'a', '', '', null, null, null, 100),
        song(1, 'b', '', '', null, null, null, 700),
        song(1, 'c', '', '', null, null, null, 300)
      ])).assertEqual(700);
      expect(resolveAddedAt(0, [])).assertEqual(0);
    });
  });
}
