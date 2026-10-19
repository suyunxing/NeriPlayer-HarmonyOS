// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { KeyedMutex } from '../../../main/ets/util/KeyedMutex';
import { ProtoWriter } from '../../../main/ets/sync/ProtobufWire';
import { decodeSyncDataProto } from '../../../main/ets/sync/SyncDataProtoCodec';
import {
  syncDataFromJsonText,
  syncDataToJsonText
} from '../../../main/ets/sync/SyncDataJsonCodec';
import { SyncData, SyncPlaylist, SyncSong } from '../../../main/ets/sync/SyncModels';

function sampleSkipData(): SyncData {
  const song = new SyncSong(1, 'good', 'Artist', 'netease', 0, 0,
    null, null, 0, null, null, null, null, 0, null, null, null, null, null,
    null, null, null, 'netease', '1', null, null, [], 0, null);
  const playlist = new SyncPlaylist(1, 'p', [song], 1, 0);
  return new SyncData('2.0', 'device', 'Name', 0, [playlist], [], [], [], [], [], 0, [], []);
}

export default function syncAuditFixesTest(): void {
  describe('KeyedMutex', () => {
    it('serializesConcurrentRunsPerKey', 0, async () => {
      const mutex = new KeyedMutex();
      const order: string[] = [];
      const slow = mutex.run('k', async (): Promise<void> => {
        order.push('slow-start');
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 20));
        order.push('slow-end');
      });
      const fast = mutex.run('k', async (): Promise<void> => {
        order.push('fast');
      });
      await Promise.all([slow, fast]);
      expect(order.length).assertEqual(3);
      expect(order[0]).assertEqual('slow-start');
      expect(order[1]).assertEqual('slow-end');
      expect(order[2]).assertEqual('fast');
    });

    it('rejectedTaskDoesNotBreakTheChain', 0, async () => {
      const mutex = new KeyedMutex();
      const order: string[] = [];
      const failing = mutex.run('k', async (): Promise<number> => {
        throw new Error('boom');
      });
      const following = mutex.run('k', async (): Promise<void> => {
        order.push('ran');
      });
      let failed = false;
      try {
        await failing;
      } catch (error) {
        failed = true;
      }
      await following;
      expect(failed).assertTrue();
      expect(order.length).assertEqual(1);
    });

    it('differentKeysRunIndependently', 0, async () => {
      const mutex = new KeyedMutex();
      const order: string[] = [];
      const a = mutex.run('a', async (): Promise<void> => {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 20));
        order.push('a');
      });
      const b = mutex.run('b', async (): Promise<void> => {
        order.push('b');
      });
      await Promise.all([a, b]);
      expect(order[0]).assertEqual('b');
      expect(order[1]).assertEqual('a');
    });
  });

  describe('UndecodableMemberSkip', () => {
    it('jsonSkipsUndecodablePlaylistMembers', 0, () => {
      const obj = JSON.parse(syncDataToJsonText(sampleSkipData())) as Record<string, Object>;
      const playlists = obj['playlists'] as Object[];
      const first = playlists[0] as Record<string, Object>;
      const songs = first['songs'] as Object[];
      songs.push(42 as Object);
      songs.push('garbage' as Object);
      const parsed = syncDataFromJsonText(JSON.stringify(obj));
      expect(parsed === null).assertFalse();
      if (parsed !== null) {
        expect(parsed.playlists.length).assertEqual(1);
        expect(parsed.playlists[0].songs.length).assertEqual(1);
        expect(parsed.playlists[0].songs[0].name).assertEqual('good');
      }
    });

    it('protoSkipsUndecodablePlaylistMembers', 0, () => {
      const goodSong = new ProtoWriter();
      goodSong.writeStringField(2, 'good');
      const garbageSong = new ProtoWriter();
      // 0xFF is an invalid protobuf tag: the member fails wire parsing.
      garbageSong.appendBytes(new Uint8Array([0xFF]));
      const playlist = new ProtoWriter();
      playlist.writeNumberField(1, 7);
      playlist.writeMessageField(3, goodSong);
      playlist.writeMessageField(3, garbageSong);
      const data = new ProtoWriter();
      data.writeMessageField(5, playlist);
      const decoded = decodeSyncDataProto(data.toBytes(), 0);
      expect(decoded === null).assertFalse();
      if (decoded !== null) {
        expect(decoded.playlists.length).assertEqual(1);
        expect(decoded.playlists[0].songs.length).assertEqual(1);
        expect(decoded.playlists[0].songs[0].name).assertEqual('good');
      }
    });

    it('legacySongMemberFailsCurrentSchemaInsteadOfEmptyingPlaylist', 0, () => {
      // Legacy SyncSong tag 8 is a varint addedAt; current tag 8 is a string
      // mediaUri. The skip-undecodable rule must not swallow that: a decoded
      // but song-less playlist would suppress the legacy fallback and lose
      // every song in the backup.
      const legacySong = new ProtoWriter();
      legacySong.writeStringField(2, 'legacy-name');
      legacySong.writeNumberField(8, 1755000000000);
      const playlist = new ProtoWriter();
      playlist.writeNumberField(1, 7);
      playlist.writeMessageField(3, legacySong);
      const data = new ProtoWriter();
      data.writeMessageField(5, playlist);
      expect(decodeSyncDataProto(data.toBytes(), 0)).assertNull();
    });
  });
}
