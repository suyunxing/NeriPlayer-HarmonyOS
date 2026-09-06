import { describe, it, expect } from '@ohos/hypium';
import {
  SyncData,
  SyncPlaylist,
  SyncSong,
  SyncRecentPlay,
  SyncPlaylistSongDeletion
} from '../../../main/ets/sync/SyncModels';
import { hasDataChanged } from '../../../main/ets/sync/DataChangeDetector';
import {
  parseJsonText,
  syncDataToJsonText,
  syncDataFromJsonText,
  serializeSyncDataJson,
  deserializeSyncContent,
  ensureRemoteContentSize,
  getSyncFileName,
  getReadFallbackFileNames,
  isBinarySyncFileName,
  utf8EncodeText,
  SyncWireFormat,
  JSON_FILE_NAME,
  RAW_BINARY_FILE_NAME,
  LEGACY_BINARY_FILE_NAME
} from '../../../main/ets/sync/SyncDataJsonCodec';
import { token } from './SongMetadataMergePolicy.test';

function bigIdSong(): SyncSong {
  // 64-bit id beyond Number precision (YTM/Bilibili hashed id shape):
  // id keeps a JS approximation, syncIdText keeps the exact decimal text.
  const song = new SyncSong(0, 'Song', 'Artist', 'netease', 0, 0,
    null, null, 0, null, null, null, null, 0, null, null, null, null, null,
    null, null, null, 'netease', '123', null, null, [token('device', 1)], 1, null);
  song.id = 5261136495461919825;
  song.syncIdText = '5261136495461919825';
  return song;
}

function sampleSyncData(): SyncData {
  const song = bigIdSong();
  const playlist = new SyncPlaylist(7, 'playlist', [song], 7, 500);
  const deletion = new SyncPlaylistSongDeletion(8, 999, 'netease', null, 200,
    'device', [token('other', 3)], '9999999999999999999');
  return new SyncData('2.0', 'device-a', 'Pixel', 1000, [playlist], [],
    [new SyncRecentPlay(5261136495461919825, song, 900, 'device-a', 75000)], [], [],
    [], 0, [], [deletion]);
}

export default function syncDataJsonCodecTest(): void {
  describe('JsonParser', () => {
    it('parsesPrimitivesAndEscapes', 0, () => {
      const root = parseJsonText('{"s":"a\\u0041b\\n","t":true,"f":false,"n":null,"pi":1.5,"neg":-7,"exp":1e3,"arr":[1,"two"]}');
      expect(root instanceof Map).assertTrue();
      const obj = root as Map<string, Object>;
      expect(obj.get('s')).assertEqual('aAb\n');
      expect(obj.get('t')).assertEqual(true);
      expect(obj.get('f')).assertEqual(false);
      expect(obj.get('n')).assertNull();
      expect(obj.get('pi')).assertEqual(1.5);
      expect(obj.get('neg')).assertEqual(-7);
      expect(obj.get('exp')).assertEqual(1000);
      const arr = obj.get('arr') as Object[];
      expect(arr.length).assertEqual(2);
      expect(arr[1]).assertEqual('two');
    });

    it('keepsOutOfRangeIntegersAsText', 0, () => {
      const root = parseJsonText('{"big":-3009301144789168460,"safe":9007199254740991}') as Map<string, Object>;
      expect(typeof root.get('big')).assertEqual('string');
      expect(root.get('big')).assertEqual('-3009301144789168460');
      expect(typeof root.get('safe')).assertEqual('number');
    });

    it('rejectsMalformedDocuments', 0, () => {
      expect(parseJsonText('')).assertNull();
      expect(parseJsonText('{')).assertNull();
      expect(parseJsonText('{"a":}')).assertNull();
      expect(parseJsonText('{"a":1} trailing')).assertNull();
      expect(parseJsonText('[1,2')).assertNull();
    });
  });

  describe('SyncDataJsonRoundTrip', () => {
    it('roundTripsThroughTextWithChangeDetectorEquality', 0, () => {
      const original = sampleSyncData();
      const text = syncDataToJsonText(original);
      const parsed = syncDataFromJsonText(text);
      expect(parsed !== null).assertTrue();
      // No change between original and re-parsed snapshot on every collection.
      expect(hasDataChanged(original, parsed as SyncData)).assertFalse();
      // And the big id survived byte-for-byte through the text form.
      const song = (parsed as SyncData).playlists[0].songs[0];
      expect(song.syncIdText).assertEqual('5261136495461919825');
      expect(songIdTextOf(song)).assertEqual('5261136495461919825');
    });

    it('roundTripsTombstoneBigSongId', 0, () => {
      const original = sampleSyncData();
      const parsed = syncDataFromJsonText(syncDataToJsonText(original)) as SyncData;
      const deletion = parsed.playlistSongDeletions[0];
      expect(deletion.syncSongIdText).assertEqual('9999999999999999999');
      expect(deletion.stableKey()).assertEqual('8|9999999999999999999|netease|');
    });

    it('writesDefaultsAndOmitsNulls', 0, () => {
      const data = new SyncData('2.0', 'd', 'n', 5, [new SyncPlaylist(1, 'p', [new SyncSong()], 1, 2)]);
      const text = syncDataToJsonText(data);
      // encodeDefaults=true: default zero/empty values are still written.
      expect(text.indexOf('"addedAt":0') > 0).assertTrue();
      expect(text.indexOf('"syncMembershipTokens":[]') > 0).assertTrue();
      expect(text.indexOf('"isDeleted":false') > 0).assertTrue();
      // explicitNulls=false: null coverUrl/mediaUri are omitted.
      expect(text.indexOf('"coverUrl"')).assertEqual(-1);
      expect(text.indexOf('"mediaUri"')).assertEqual(-1);
    });

    it('ignoresUnknownKeysAndFillsMissingWithDefaults', 0, () => {
      const parsed = syncDataFromJsonText('{"version":"9.9","futureField":[1,2],"playlists":[{"id":3,"name":"x","brandNew":true}]}');
      expect(parsed !== null).assertTrue();
      const data = parsed as SyncData;
      expect(data.version).assertEqual('9.9');
      expect(data.playlists.length).assertEqual(1);
      expect(data.playlists[0].id).assertEqual(3);
      expect(data.playlists[0].songOrderVersion).assertEqual(0);
      expect(data.recentPlays.length).assertEqual(0);
    });

    it('normalizesTokensOnRead', 0, () => {
      const parsed = syncDataFromJsonText(
        '{"playlists":[{"id":1,"songs":[{"id":5,"syncMembershipTokens":[{"deviceId":"b","counter":1},{"deviceId":"b","counter":1},{"deviceId":"a","counter":0}]}]}]}'
      ) as SyncData;
      const tokens = parsed.playlists[0].songs[0].syncMembershipTokens;
      expect(tokens.length).assertEqual(1);
      expect(tokens[0].deviceId).assertEqual('b');
    });

    it('returnsNullOnCorruptJson', 0, () => {
      expect(syncDataFromJsonText('not json at all')).assertNull();
      expect(syncDataFromJsonText('{"playlists": 12}')).assertNull();
    });
  });

  describe('SyncWireFormat', () => {
    it('sniffsGzipMagicBeforeJson', 0, () => {
      const gzip = new Uint8Array([0x1F, 0x8B, 0x08, 0x00]);
      const result = deserializeSyncContent(gzip);
      expect(result.format).assertEqual(SyncWireFormat.GZIP_PROTO);
      expect(result.data).assertNull();
      expect(result.errorMessage.length > 0).assertTrue();
    });

    it('decodesJsonWithBomAndLeadingWhitespace', 0, () => {
      const content = utf8EncodeText('﻿ 	{\"version\":\"2.0\"}');
      const result = deserializeSyncContent(content);
      expect(result.format).assertEqual(SyncWireFormat.JSON);
      expect(result.data !== null).assertTrue();
    });

    it('classifiesUnknownBytesAsLegacyBase64', 0, () => {
      const result = deserializeSyncContent(new Uint8Array([0x41, 0x42, 0x43]));
      expect(result.format).assertEqual(SyncWireFormat.LEGACY_BASE64);
      expect(result.data).assertNull();
    });

    it('serializesJsonWithinUploadBound', 0, () => {
      const bytes = serializeSyncDataJson(new SyncData());
      expect(bytes.length < 8 * 1024 * 1024).assertTrue();
      const oversizedJson = new Uint8Array(8 * 1024 * 1024 + 1);
      oversizedJson[0] = 0x7B; // '{' → json branch with the 8 MiB bound
      expect(ensureRemoteContentSize(oversizedJson)).assertFalse();
      expect(ensureRemoteContentSize(new Uint8Array([0x7B]))).assertTrue();
    });

    it('choosesFileNamesLikeAndroid', 0, () => {
      expect(getSyncFileName(false)).assertEqual(JSON_FILE_NAME);
      expect(getSyncFileName(true)).assertEqual(RAW_BINARY_FILE_NAME);
      expect(getReadFallbackFileNames(false)[0]).assertEqual(RAW_BINARY_FILE_NAME);
      expect(getReadFallbackFileNames(false)[1]).assertEqual(LEGACY_BINARY_FILE_NAME);
      expect(getReadFallbackFileNames(true)[1]).assertEqual(JSON_FILE_NAME);
      expect(isBinarySyncFileName('backup-raw.bin')).assertTrue();
      expect(isBinarySyncFileName('backup.json')).assertFalse();
    });
  });
}

function songIdTextOf(song: SyncSong): string {
  return song.syncIdText.length > 0 ? song.syncIdText : `${song.id}`;
}
