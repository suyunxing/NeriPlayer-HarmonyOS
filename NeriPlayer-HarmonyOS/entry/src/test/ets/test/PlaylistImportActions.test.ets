// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect, MockKit } from '@ohos/hypium';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { LocalPlaylistRepository } from '../../../main/ets/data/LocalPlaylistRepository';
import { AutoSyncScheduler } from '../../../main/ets/sync/AutoSyncScheduler';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { PlaylistSyncSource, SOURCE_SYNC_MODE_APPEND, sourceKeyOf } from '../../../main/ets/sourcesync/SourceSyncModels';
import { importPlaylistSelection } from '../../../main/ets/view/components/PlaylistImportActions';

function track(id: number): SongItem {
  return new SongItem(id, 'track', 'artist', 'album', id, 100, '', '', MusicPlatform.NETEASE);
}
function binding(id: string, platform: MusicPlatform = MusicPlatform.BILIBILI): PlaylistSyncSource {
  const source = new PlaylistSyncSource(platform, id, 'source-' + id);
  source.mode = SOURCE_SYNC_MODE_APPEND;
  return source;
}
async function withStore(task: () => Promise<void>): Promise<void> {
  const values = new Map<string, string>();
  const mocks = new MockKit();
  mocks.mockProperty(AppPreferences, 'getString', async (key: string, fallback: string): Promise<string> =>
    values.get(key) ?? fallback);
  mocks.mockProperty(AppPreferences, 'putString', async (key: string, value: string): Promise<void> => {
    values.set(key, value);
  });
  mocks.mockProperty(AutoSyncScheduler, 'scheduleMutationSync', (): void => {});
  try {
    await AppPreferences.putString('playlists', JSON.stringify([new Playlist('target', 'combined')]));
    await task();
  } finally {
    mocks.clearAll();
  }
}
async function target(): Promise<Playlist> {
  const all = await LocalPlaylistRepository.loadAll();
  const playlist = all.find((item: Playlist): boolean => item.id === 'target');
  if (playlist === undefined) {
    throw new Error('Missing target');
  }
  return playlist;
}
export default function playlistImportActionsTest(): void {
  describe('PlaylistImportActions', () => {
    it('oneShotIntoExistingPlaylistCreatesManualMembershipWithoutBinding', 0, async () => {
      await withStore(async (): Promise<void> => {
        const result = await importPlaylistSelection('target', '', false, binding('1'), [track(1), track(1)]);
        expect(result.addedCount).assertEqual(1);
        expect(result.playlistName).assertEqual('combined');
        const stored = await target();
        expect(stored.getSyncSources().length).assertEqual(0);
        expect(stored.manualSongKeys.length).assertEqual(1);
      });
    });
    it('twoBiliFoldersAndNeteaseImportIntoOneTargetRemainSourceOwned', 0, async () => {
      await withStore(async (): Promise<void> => {
        await importPlaylistSelection('target', '', true, binding('1'), [track(1), track(2)]);
        await importPlaylistSelection('target', '', true, binding('2'), [track(2), track(3)]);
        const result = await importPlaylistSelection('target', '', true, binding('3', MusicPlatform.NETEASE), [track(4)]);
        const stored = await target();
        expect(result.addedCount).assertEqual(1);
        expect(stored.songKeys.length).assertEqual(4);
        expect(stored.getSyncSources().length).assertEqual(3);
        expect(stored.manualSongKeys.length).assertEqual(0);
      });
    });
    it('repeatedContinuousImportKeepsOneBindingAndAddsOnlyNewSongs', 0, async () => {
      await withStore(async (): Promise<void> => {
        const source = binding('1');
        await importPlaylistSelection('target', '', true, source, [track(1)]);
        const before = (await target()).getSyncSources()[0].bindingId;
        const result = await importPlaylistSelection('target', '', true, source, [track(1), track(2)]);
        const stored = await target();
        expect(result.addedCount).assertEqual(1);
        expect(stored.getSyncSources().length).assertEqual(1);
        expect(stored.getSyncSources()[0].bindingId).assertEqual(before);
      });
    });
    it('continuousImportCreatesNamedPlaylistAndSeedsOwnership', 0, async () => {
      await withStore(async (): Promise<void> => {
        const source = binding('1');
        const result = await importPlaylistSelection('', 'custom combined', true, source, [track(1)]);
        expect(result.playlistName).assertEqual('custom combined');
        expect(result.addedCount).assertEqual(1);
        const all = await LocalPlaylistRepository.loadAll();
        const created = all.find((item: Playlist): boolean => item.name === 'custom combined');
        expect(created !== undefined).assertTrue();
        if (created !== undefined) {
          expect(created.getSyncSources().length).assertEqual(1);
          expect(created.manualSongKeys.length).assertEqual(0);
          expect(sourceKeyOf(created.getSyncSources()[0])).assertEqual(sourceKeyOf(source));
        }
      });
    });
    it('oneShotCreatesPlainNamedPlaylist', 0, async () => {
      await withStore(async (): Promise<void> => {
        const result = await importPlaylistSelection('', 'one-shot', false, binding('1'), [track(1)]);
        expect(result.playlistName).assertEqual('one-shot');
        expect(result.addedCount).assertEqual(1);
        const all = await LocalPlaylistRepository.loadAll();
        const created = all.find((item: Playlist): boolean => item.name === 'one-shot');
        expect(created !== undefined).assertTrue();
        if (created !== undefined) {
          expect(created.getSyncSources().length).assertEqual(0);
        }
      });
    });
    it('missingAndReservedTargetsRejectWithoutChangingStoredPlaylists', 0, async () => {
      await withStore(async (): Promise<void> => {
        const before = await AppPreferences.getString('playlists', '');
        const ids: string[] = ['missing', LocalPlaylistRepository.FAVORITES_ID, LocalPlaylistRepository.LOCAL_MUSIC_ID];
        for (const id of ids) {
          let failed = false;
          try {
            await importPlaylistSelection(id, '', true, binding('1'), [track(1)]);
          } catch (error) {
            failed = (error as Error).message.length > 0;
          }
          expect(failed).assertTrue();
          expect(await AppPreferences.getString('playlists', '')).assertEqual(before);
        }
      });
    });
  });
}
