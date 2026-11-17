// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';
import { PlaylistSyncSource, sourceKeyOf } from '../../../main/ets/sourcesync/SourceSyncModels';
import { SyncPlaylist } from '../../../main/ets/sync/SyncModels';
import { playlistIdToSync, syncPlaylistFromPlaylist } from '../../../main/ets/sync/SyncSongConvert';
import { restorePlaylistFromSync } from '../../../main/ets/sync/SyncPlaylistRestore';

function boundPlaylist(): Playlist {
  const playlist = new Playlist('local_123', 'Merged');
  playlist.coverUrl = 'cover';
  playlist.description = 'my description';
  playlist.manualSongKeys = ['manual'];
  playlist.manualOwnershipKnown = true;
  playlist.syncSources = [new PlaylistSyncSource(MusicPlatform.BILIBILI, '11', 'Folder A'),
    new PlaylistSyncSource(MusicPlatform.BILIBILI, '22', 'Folder B'),
    new PlaylistSyncSource(MusicPlatform.NETEASE, '33', 'Playlist C')];
  playlist.syncSources[0].ownedSongKeys = ['owned'];
  playlist.syncSources[0].ownershipKnown = true;
  playlist.syncSources[0].skipKeys = ['skipped'];
  playlist.syncSources[0].bindingId = 'generation';
  playlist.syncSources[0].bindingRevision = 3;
  playlist.getSyncSources();
  return playlist;
}

export default function syncPlaylistRestoreTest(): void {
  describe('SyncPlaylistRestore', () => {
    it('keepsThreeLocalSourcesAcrossSharedSnapshot', 0, () => {
      const local = boundPlaylist();
      const row = syncPlaylistFromPlaylist(local, 99);
      const restored = restorePlaylistFromSync(row, local, 'favorites');
      expect(restored.id).assertEqual(local.id);
      expect(restored.getSyncSources().length).assertEqual(3);
      expect(sourceKeyOf(restored.getSyncSources()[1])).assertEqual('bilibili:22');
      expect(restored.syncSource === restored.getSyncSources()[0]).assertTrue();
      expect(restored.syncSources[0].bindingRevision).assertEqual(3);
      expect(restored.syncSources[0].skipKeys[0]).assertEqual('skipped');
      expect(restored.syncSources[0].ownedSongKeys[0]).assertEqual('owned');
      expect(restored.manualSongKeys[0]).assertEqual('manual');
      expect(restored.manualOwnershipKnown).assertTrue();
      expect(restored.description).assertEqual('my description');
      expect(restored.updatedAt).assertEqual(99);
    });
    it('doesNotShareMutableBindingArraysWithPriorSnapshot', 0, () => {
      const local = boundPlaylist();
      const restored = restorePlaylistFromSync(syncPlaylistFromPlaylist(local, 99), local, 'favorites');
      restored.syncSources[0].skipKeys.push('new');
      restored.syncSources[0].ownedSongKeys.push('new');
      restored.manualSongKeys.push('new');
      expect(local.syncSources[0].skipKeys.length).assertEqual(1);
      expect(local.syncSources[0].ownedSongKeys.length).assertEqual(1);
      expect(local.manualSongKeys.length).assertEqual(1);
    });
    it('restoresLegacySingleBindingWithoutLosingIt', 0, () => {
      const local = Playlist.fromJson('{"id":"local_7","name":"Old","syncSource":' +
        '{"platform":2,"remoteId":"123","skipKeys":["skip"]}}');
      const restored = restorePlaylistFromSync(syncPlaylistFromPlaylist(local, 10), local, 'favorites');
      expect(restored.getSyncSources().length).assertEqual(1);
      expect(restored.syncSources[0].remoteId).assertEqual('123');
      expect(restored.syncSources[0].skipKeys[0]).assertEqual('skip');
      const reread = Playlist.fromJson(restored.toJson());
      expect(reread.getSyncSources().length).assertEqual(1);
    });
    it('neverExportsLocalBindingsIntoSharedFormat', 0, () => {
      const row = syncPlaylistFromPlaylist(boundPlaylist(), 9);
      const serialized = JSON.stringify(row);
      expect(serialized.includes('syncSources')).assertFalse();
      expect(serialized.includes('ownedSongKeys')).assertFalse();
      expect(serialized.includes('bindingId')).assertFalse();
      const restoredOnAnotherDevice = restorePlaylistFromSync(row, undefined, 'favorites');
      expect(restoredOnAnotherDevice.getSyncSources().length).assertEqual(0);
    });
    it('preservesLocalFileAndItsCustomDisplayMetadata', 0, () => {
      const local = boundPlaylist();
      const song = new SongItem(5, 'file', 'artist', 'local', 0, 1, '', 'file://fixture', MusicPlatform.LOCAL);
      song.customName = 'custom file';
      song.customCoverUrl = 'custom cover';
      local.songs = [song];
      local.songKeys = [stableKeyOf(song)];
      const row = syncPlaylistFromPlaylist(local, 10);
      expect(row.songs.length).assertEqual(0);
      const restored = restorePlaylistFromSync(row, local, 'favorites');
      expect(restored.songs.length).assertEqual(1);
      expect(restored.songs[0].customName).assertEqual('custom file');
      expect(restored.displayCoverUrl).assertEqual('custom cover');
      expect(restored.songKeys[0]).assertEqual(stableKeyOf(song));
    });
    it('keepsFavoritesAndImportedNumericIdShapes', 0, () => {
      const favorite = new SyncPlaylist(playlistIdToSync('favorites'), 'Favorites');
      expect(restorePlaylistFromSync(favorite, undefined, 'favorites').id).assertEqual('favorites');
      const local = new Playlist('42', 'Imported');
      const restored = restorePlaylistFromSync(syncPlaylistFromPlaylist(local, 8), local, 'favorites');
      expect(restored.id).assertEqual('42');
    });
  });
}
