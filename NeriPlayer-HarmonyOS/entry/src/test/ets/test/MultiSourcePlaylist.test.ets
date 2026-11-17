// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect, MockKit } from '@ohos/hypium';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { LocalPlaylistRepository } from '../../../main/ets/data/LocalPlaylistRepository';
import { AutoSyncScheduler } from '../../../main/ets/sync/AutoSyncScheduler';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';
import { PlaylistSyncSource, SOURCE_SYNC_MODE_APPEND, sourceKeyOf, sourceBindingTokenOf }
  from '../../../main/ets/sourcesync/SourceSyncModels';
import { ensurePlaylistOwnership, findPlaylistSource, currentSourceForApply, attachPlaylistSource,
  detachPlaylistSource, applySourceSnapshot, markPlaylistSongDeleted, markPlaylistSongManual,
  clearPlaylistSongSkips, mergePlaylistContent } from '../../../main/ets/sourcesync/SourceSyncOwnership';

function song(id: number, name: string = 'track'): SongItem {
  return new SongItem(id, name, 'artist', 'album', id * 10, 100, '', '', MusicPlatform.NETEASE);
}

function source(id: string, platform: MusicPlatform = MusicPlatform.BILIBILI): PlaylistSyncSource {
  return new PlaylistSyncSource(platform, id, id);
}

function bind(playlist: Playlist, value: PlaylistSyncSource): PlaylistSyncSource {
  attachPlaylistSource(playlist, value, 'binding-' + sourceKeyOf(value));
  return findPlaylistSource(playlist, sourceKeyOf(value)) as PlaylistSyncSource;
}

function sync(playlist: Playlist, value: PlaylistSyncSource, songs: SongItem[]): void {
  const result = applySourceSnapshot(playlist, value, songs);
  playlist.songKeys = result.keys;
  playlist.songs = result.songs;
}

function remove(playlist: Playlist, key: string): void {
  markPlaylistSongDeleted(playlist, key);
  const index = playlist.songKeys.indexOf(key);
  if (index >= 0) {
    playlist.songKeys.splice(index, 1);
    playlist.songs.splice(index, 1);
  }
}

class LegacyPlaylistFixture {
  id: string = 'legacy';
  name: string = 'legacy';
  songKeys: string[] = [];
  songs: SongItem[] = [];
  syncSource: PlaylistSyncSource | null = null;
}

async function withMemoryRepository(task: () => Promise<void>): Promise<void> {
  const values = new Map<string, string>();
  const mocks = new MockKit();
  let uuidCounter = 0;
  mocks.mockProperty(LocalPlaylistRepository, 'generateSourceBindingId', (): string => {
    uuidCounter += 1;
    return '00000000-0000-4000-8000-' + String(uuidCounter).padStart(12, '0');
  });
  mocks.mockProperty(AppPreferences, 'getString', async (key: string, fallback: string): Promise<string> =>
    values.get(key) ?? fallback);
  mocks.mockProperty(AppPreferences, 'putString', async (key: string, value: string): Promise<void> => {
    values.set(key, value);
  });
  mocks.mockProperty(AutoSyncScheduler, 'scheduleMutationSync', (): void => {});
  try {
    await task();
  } finally {
    mocks.clearAll();
  }
}

async function storedPlaylist(id: string): Promise<Playlist> {
  const playlists = await LocalPlaylistRepository.loadAll();
  const playlist = playlists.find((item: Playlist): boolean => item.id === id);
  if (playlist === undefined) {
    throw new Error('Missing fixture playlist: ' + id);
  }
  return playlist;
}

export default function multiSourcePlaylistTest(): void {
  describe('MultiSourcePlaylist', () => {
    it('twoBilibiliFoldersAndNeteaseOwnSongsIndependently', 0, () => {
      const playlist = new Playlist('p');
      const first = bind(playlist, source('1'));
      const second = bind(playlist, source('2'));
      const netease = bind(playlist, source('3', MusicPlatform.NETEASE));
      sync(playlist, first, [song(1), song(2)]);
      sync(playlist, second, [song(2), song(3)]);
      sync(playlist, netease, [song(4)]);
      expect(playlist.songKeys.length).assertEqual(4);
      expect(playlist.getSyncSources().length).assertEqual(3);
      sync(playlist, first, [song(5)]);
      expect(playlist.songKeys.indexOf(stableKeyOf(song(1))) < 0).assertTrue();
      expect(playlist.songKeys.indexOf(stableKeyOf(song(2))) >= 0).assertTrue();
      expect(playlist.songKeys.indexOf(stableKeyOf(song(4))) >= 0).assertTrue();
      sync(playlist, second, [song(6)]);
      expect(playlist.songKeys.indexOf(stableKeyOf(song(2))) < 0).assertTrue();
      expect(playlist.songKeys.length).assertEqual(3);
    });

    it('sharedSongDisappearsOnlyAfterFinalOwnerDropsIt', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(1), song(1)]);
      expect(playlist.songKeys.length).assertEqual(1);
      sync(playlist, a, []);
      expect(playlist.songKeys.length).assertEqual(1);
      sync(playlist, b, []);
      expect(playlist.songKeys.length).assertEqual(0);
    });

    it('manualSongsAndExistingMetadataSurviveSourceChanges', 0, () => {
      const playlist = new Playlist('p');
      playlist.songKeys = [stableKeyOf(song(9))];
      playlist.songs = [song(9, 'local metadata')];
      const a = bind(playlist, source('1'));
      sync(playlist, a, [song(1), song(9, 'remote metadata')]);
      sync(playlist, a, []);
      expect(playlist.songKeys.length).assertEqual(1);
      expect(playlist.songs[0].name).assertEqual('local metadata');
      expect(playlist.manualSongKeys[0]).assertEqual(stableKeyOf(song(9)));
    });

    it('manualDeleteSkipsEveryOwningSourceAndDoesNotResurrect', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      const unrelated = bind(playlist, source('3', MusicPlatform.NETEASE));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(1)]);
      remove(playlist, stableKeyOf(song(1)));
      expect(a.skipKeys.length).assertEqual(1);
      expect(b.skipKeys.length).assertEqual(1);
      expect(unrelated.skipKeys.length).assertEqual(0);
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(1)]);
      expect(playlist.songKeys.length).assertEqual(0);
    });

    it('undoClearsAllSkipsAndRetainsSourceOwnership', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(1)]);
      remove(playlist, stableKeyOf(song(1)));
      clearPlaylistSongSkips(playlist, stableKeyOf(song(1)));
      sync(playlist, a, [song(1)]);
      expect(a.skipKeys.length + b.skipKeys.length).assertEqual(0);
      expect(playlist.manualSongKeys.length).assertEqual(0);
      sync(playlist, a, []);
      sync(playlist, b, []);
      expect(playlist.songKeys.length).assertEqual(0);
    });

    it('manualReaddClearsAllSkipsAndCreatesManualOwnership', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(1)]);
      remove(playlist, stableKeyOf(song(1)));
      markPlaylistSongManual(playlist, stableKeyOf(song(1)));
      playlist.songs.push(song(1));
      playlist.songKeys.push(stableKeyOf(song(1)));
      sync(playlist, a, []);
      sync(playlist, b, []);
      expect(playlist.songKeys.length).assertEqual(1);
      expect(a.skipKeys.length + b.skipKeys.length).assertEqual(0);
    });

    it('legacySingleSourceRoundtripAndFirstSyncStillRemoveOldMembers', 0, () => {
      const fixture = new LegacyPlaylistFixture();
      fixture.syncSource = source('1');
      fixture.songs = [song(1), song(2)];
      fixture.songKeys = fixture.songs.map((item: SongItem): string => stableKeyOf(item));
      const playlist = Playlist.fromJson(JSON.stringify(fixture));
      expect(playlist.getSyncSources().length).assertEqual(1);
      const restored = Playlist.fromJson(playlist.toJson());
      expect(restored.syncSource === null).assertFalse();
      expect(restored.getSyncSources()[0].ownershipKnown).assertFalse();
      sync(restored, restored.getSyncSources()[0], [song(2)]);
      expect(restored.songKeys.length).assertEqual(1);
      expect(restored.manualSongKeys.length).assertEqual(0);
      expect(restored.songKeys[0]).assertEqual(stableKeyOf(song(2)));
    });

    it('plainLegacyListRoundtripRemainsManualAndUnbound', 0, () => {
      const playlist = Playlist.fromJson('{"id":"plain","name":"old","songKeys":[],"songs":[]}');
      ensurePlaylistOwnership(playlist);
      const restored = Playlist.fromJson(playlist.toJson());
      expect(restored.getSyncSources().length).assertEqual(0);
      expect(restored.syncSource === null).assertTrue();
      expect(restored.manualOwnershipKnown).assertTrue();
    });

    it('duplicateBindIsIdempotentAndKeepsSkipsAndOwnership', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      a.skipKeys.push('skip');
      a.lastFingerprint = 'fp';
      const token = sourceBindingTokenOf(a);
      expect(attachPlaylistSource(playlist, source('1'), 'ignored-generation')).assertTrue();
      expect(playlist.getSyncSources().length).assertEqual(2);
      expect(a.skipKeys[0]).assertEqual('skip');
      expect(a.ownedSongKeys.length).assertEqual(1);
      expect(a.lastFingerprint).assertEqual('fp');
      expect(sourceBindingTokenOf(a)).assertEqual(token);
    });

    it('unbindOneSourcePreservesSongsAndOtherBindings', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(2)]);
      expect(detachPlaylistSource(playlist, sourceKeyOf(a))).assertTrue();
      expect(playlist.getSyncSources().length).assertEqual(1);
      sync(playlist, b, []);
      expect(playlist.songKeys.length).assertEqual(1);
      expect(playlist.manualSongKeys[0]).assertEqual(stableKeyOf(song(1)));
      detachPlaylistSource(playlist);
      expect(Playlist.fromJson(playlist.toJson()).getSyncSources().length).assertEqual(0);
    });

    it('lateResponsesFailAfterUnbindRebindOrDisable', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const token = sourceBindingTokenOf(a);
      detachPlaylistSource(playlist, sourceKeyOf(a));
      expect(currentSourceForApply(playlist, sourceKeyOf(a), token) === null).assertTrue();
      attachPlaylistSource(playlist, source('1'), 'replacement');
      expect(currentSourceForApply(playlist, sourceKeyOf(a), token) === null).assertTrue();
      const current = playlist.getSyncSources()[0];
      current.enabled = false;
      expect(currentSourceForApply(playlist, sourceKeyOf(a)) === null).assertTrue();
      current.enabled = true;
      current.bindingRevision += 1;
      expect(currentSourceForApply(playlist, sourceKeyOf(a), sourceBindingTokenOf(current)) !== null).assertTrue();
    });

    it('mergeUnionsSongsAndSourcesWithoutChangingOriginal', 0, () => {
      const target = new Playlist('target');
      const targetSource = bind(target, source('1'));
      sync(target, targetSource, [song(1)]);
      const original = new Playlist('original');
      const a = bind(original, source('1'));
      const b = bind(original, source('2'));
      const n = bind(original, source('3', MusicPlatform.NETEASE));
      sync(original, a, [song(2)]);
      sync(original, b, [song(3)]);
      sync(original, n, [song(4)]);
      const before = original.toJson();
      expect(mergePlaylistContent(target, original, 'merged')).assertEqual(3);
      expect(target.getSyncSources().length).assertEqual(3);
      expect(original.toJson()).assertEqual(before);
      expect(mergePlaylistContent(target, original, 'repeat')).assertEqual(0);
      sync(target, targetSource, []);
      expect(target.songKeys.length).assertEqual(2);
      expect(original.songKeys.length).assertEqual(3);
    });

    it('appendSourceRetainsPastMembershipWhileMirrorStillRemovesItsOwn', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      a.mode = SOURCE_SYNC_MODE_APPEND;
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1)]);
      sync(playlist, b, [song(2)]);
      sync(playlist, a, [song(3)]);
      sync(playlist, b, []);
      expect(playlist.songKeys.length).assertEqual(2);
      expect(a.ownedSongKeys.length).assertEqual(2);
    });

    it('sourceReorderLeavesOtherSourceAndManualRelativeOrderIntact', 0, () => {
      const playlist = new Playlist('p');
      const a = bind(playlist, source('1'));
      const b = bind(playlist, source('2'));
      sync(playlist, a, [song(1), song(2)]);
      sync(playlist, b, [song(3)]);
      markPlaylistSongManual(playlist, stableKeyOf(song(4)));
      playlist.songKeys.push(stableKeyOf(song(4)));
      playlist.songs.push(song(4));
      sync(playlist, a, [song(2), song(1)]);
      expect(playlist.songKeys[0]).assertEqual(stableKeyOf(song(2)));
      expect(playlist.songKeys[1]).assertEqual(stableKeyOf(song(1)));
      expect(playlist.songKeys[2]).assertEqual(stableKeyOf(song(3)));
      expect(playlist.songKeys[3]).assertEqual(stableKeyOf(song(4)));
    });

    it('mergedVisibleTargetSongWinsOverIncomingSameSourceSkip', 0, () => {
      const target = new Playlist('target');
      const targetSource = bind(target, source('1'));
      sync(target, targetSource, [song(1)]);
      const original = new Playlist('original');
      const originalSource = bind(original, source('1'));
      sync(original, originalSource, [song(1)]);
      remove(original, stableKeyOf(song(1)));
      expect(mergePlaylistContent(target, original, 'merged')).assertEqual(0);
      expect(targetSource.skipKeys.length).assertEqual(0);
      sync(target, targetSource, [song(1)]);
      expect(target.songKeys.length).assertEqual(1);
      expect(original.songKeys.length).assertEqual(0);
      expect(originalSource.skipKeys.length).assertEqual(1);
    });

    it('repositoryConcurrentBindsAndSnapshotsRoundtripThreeSourceOwnership', 0, async () => {
      await withMemoryRepository(async (): Promise<void> => {
        const playlist = new Playlist('target');
        await AppPreferences.putString('playlists', JSON.stringify([playlist]));
        const a = source('1');
        const b = source('2');
        const n = source('3', MusicPlatform.NETEASE);
        await Promise.all([
          LocalPlaylistRepository.bindMirrorSource(playlist.id, a),
          LocalPlaylistRepository.bindMirrorSource(playlist.id, b),
          LocalPlaylistRepository.bindMirrorSource(playlist.id, n)
        ]);
        await LocalPlaylistRepository.bindMirrorSource(playlist.id, a);
        await Promise.all([
          LocalPlaylistRepository.applyMirrorSync(playlist.id, [song(1), song(2)], 'a', sourceKeyOf(a)),
          LocalPlaylistRepository.applyMirrorSync(playlist.id, [song(2), song(3)], 'b', sourceKeyOf(b)),
          LocalPlaylistRepository.applyMirrorSync(playlist.id, [song(4)], 'n', sourceKeyOf(n))
        ]);
        let stored = await storedPlaylist(playlist.id);
        expect(stored.getSyncSources().length).assertEqual(3);
        expect(stored.songKeys.length).assertEqual(4);
        expect(stored.manualSongKeys.length).assertEqual(0);
        await LocalPlaylistRepository.applyMirrorSync(playlist.id, [song(5)], 'a2', sourceKeyOf(a));
        stored = await storedPlaylist(playlist.id);
        expect(stored.songKeys.indexOf(stableKeyOf(song(2))) >= 0).assertTrue();
        expect(stored.songKeys.indexOf(stableKeyOf(song(1))) < 0).assertTrue();
        await LocalPlaylistRepository.applyMirrorSync(playlist.id, [], 'b2', sourceKeyOf(b));
        stored = await storedPlaylist(playlist.id);
        expect(stored.songKeys.length).assertEqual(2);
        expect(stored.songKeys.indexOf(stableKeyOf(song(4))) >= 0).assertTrue();
      });
    });

    it('repositoryManualDeleteUndoAndDuplicateManualAddPreserveIntent', 0, async () => {
      await withMemoryRepository(async (): Promise<void> => {
        const created = await LocalPlaylistRepository.createOrGetMirrorPlaylist(source('1'), [song(1)]);
        const b = source('2');
        await LocalPlaylistRepository.bindMirrorSource(created.id, b);
        await LocalPlaylistRepository.applyMirrorSync(created.id, [song(1)], 'b', sourceKeyOf(b));
        const snapshot = await LocalPlaylistRepository.removeSongForUndo(created.id, stableKeyOf(song(1)));
        expect(snapshot === null).assertFalse();
        let stored = await storedPlaylist(created.id);
        expect(stored.getSyncSources()[0].skipKeys.length).assertEqual(1);
        expect(stored.getSyncSources()[1].skipKeys.length).assertEqual(1);
        await LocalPlaylistRepository.applyMirrorSync(created.id, [song(1)], 'still-present');
        expect((await storedPlaylist(created.id)).songKeys.length).assertEqual(0);
        if (snapshot !== null) {
          expect(await LocalPlaylistRepository.restoreRemovedSong(snapshot)).assertTrue();
        }
        stored = await storedPlaylist(created.id);
        expect(stored.manualSongKeys.length).assertEqual(0);
        expect(stored.getSyncSources()[0].skipKeys.length + stored.getSyncSources()[1].skipKeys.length).assertEqual(0);
        expect(await LocalPlaylistRepository.addSong(created.id, song(1))).assertFalse();
        await LocalPlaylistRepository.applyMirrorSync(created.id, [], 'empty-a');
        await LocalPlaylistRepository.applyMirrorSync(created.id, [], 'empty-b', sourceKeyOf(b));
        stored = await storedPlaylist(created.id);
        expect(stored.songKeys.length).assertEqual(1);
        expect(stored.manualSongKeys.length).assertEqual(1);
      });
    });

    it('repositoryMergeAndUnbindKeepOriginalAndRejectLateFetch', 0, async () => {
      await withMemoryRepository(async (): Promise<void> => {
        const target = await LocalPlaylistRepository.createOrGetMirrorPlaylist(source('1'), [song(1)]);
        const original = await LocalPlaylistRepository.createOrGetMirrorPlaylist(source('2'), [song(2)]);
        const before = (await storedPlaylist(original.id)).toJson();
        expect(await LocalPlaylistRepository.mergePlaylists(target.id, [target.id, original.id, original.id, 'missing'])).assertEqual(1);
        expect((await storedPlaylist(original.id)).toJson()).assertEqual(before);
        let stored = await storedPlaylist(target.id);
        expect(stored.getSyncSources().length).assertEqual(2);
        const key = sourceKeyOf(stored.getSyncSources()[1]);
        const token = sourceBindingTokenOf(stored.getSyncSources()[1]);
        expect(await LocalPlaylistRepository.unbindMirrorSource(target.id, key)).assertTrue();
        expect(await LocalPlaylistRepository.applyMirrorSync(target.id, [song(3)], 'late', key, token)).assertFalse();
        await LocalPlaylistRepository.bindMirrorSource(target.id, source('2'));
        expect(await LocalPlaylistRepository.applyMirrorSync(target.id, [song(3)], 'rebind-late', key, token)).assertFalse();
        await LocalPlaylistRepository.setMirrorEnabled(target.id, false, key);
        expect(await LocalPlaylistRepository.applyMirrorSync(target.id, [song(3)], 'disabled', key)).assertFalse();
        await LocalPlaylistRepository.unbindMirrorSource(target.id);
        stored = await storedPlaylist(target.id);
        expect(stored.getSyncSources().length).assertEqual(0);
        expect(stored.songKeys.length).assertEqual(2);
        expect(stored.manualSongKeys.length).assertEqual(2);
      });
    });

    it('repositoryLegacySnapshotUpgradeAndBackupRetainSingleMirrorSemantics', 0, async () => {
      await withMemoryRepository(async (): Promise<void> => {
        const fixture = new LegacyPlaylistFixture();
        fixture.syncSource = source('1');
        fixture.songs = [song(1), song(2)];
        fixture.songKeys = fixture.songs.map((item: SongItem): string => stableKeyOf(item));
        const legacyJson = JSON.stringify([fixture]);
        await AppPreferences.putString('playlists', legacyJson);
        expect(await LocalPlaylistRepository.applyMirrorSync('legacy', [song(2)], 'new')).assertTrue();
        const stored = await storedPlaylist('legacy');
        expect(stored.songKeys.length).assertEqual(1);
        expect(stored.manualSongKeys.length).assertEqual(0);
        expect(stored.getSyncSources()[0].ownershipKnown).assertTrue();
        expect(await AppPreferences.getString('playlists.bak', '')).assertEqual(legacyJson);
        await AppPreferences.putString('playlists', '{broken');
        expect((await storedPlaylist('legacy')).songKeys.length).assertEqual(2);
      });
    });
    it('repositoryCrossDeviceRestoreUsesNewestBindingStateInsideMutex', 0, async () => {
      await withMemoryRepository(async (): Promise<void> => {
        const a = source('1');
        const b = source('2');
        const created = await LocalPlaylistRepository.createOrGetMirrorPlaylist(a, [song(1)]);
        const stale = Playlist.fromJson((await storedPlaylist(created.id)).toJson());
        await LocalPlaylistRepository.unbindMirrorSource(created.id, sourceKeyOf(a));
        await LocalPlaylistRepository.bindMirrorSource(created.id, b);
        await LocalPlaylistRepository.applyMirrorSync(created.id, [song(2)], 'b', sourceKeyOf(b));
        await LocalPlaylistRepository.setMirrorEnabled(created.id, false, sourceKeyOf(b));
        await LocalPlaylistRepository.replaceAllFromSync([stale]);
        const stored = await storedPlaylist(created.id);
        expect(stored.getSyncSources().length).assertEqual(1);
        expect(sourceKeyOf(stored.getSyncSources()[0])).assertEqual(sourceKeyOf(b));
        expect(stored.getSyncSources()[0].enabled).assertFalse();
        expect(stored.getSyncSources()[0].skipKeys[0]).assertEqual(stableKeyOf(song(2)));
        expect(stored.manualSongKeys[0]).assertEqual(stableKeyOf(song(1)));
        expect(await LocalPlaylistRepository.applyMirrorSync(created.id, [song(3)], 'late-a', sourceKeyOf(a))).assertFalse();
      });
    });
  });
}
