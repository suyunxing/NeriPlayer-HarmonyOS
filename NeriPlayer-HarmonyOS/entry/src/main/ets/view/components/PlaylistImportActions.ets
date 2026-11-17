// SPDX-License-Identifier: GPL-3.0

import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlaylistSyncSource, mirrorPlaylistId, sourceKeyOf, sourceBindingTokenOf } from '../../sourcesync/SourceSyncModels';

export class PlaylistImportOutcome {
  playlistName: string = '';
  addedCount: number = 0;
}

/** UI action adapter only: storage and source membership are owned by repositories. */
export async function importPlaylistSelection(targetId: string, name: string, bind: boolean,
  source: PlaylistSyncSource, songs: SongItem[]): Promise<PlaylistImportOutcome> {
  const playlists = await LocalPlaylistRepository.loadAll();
  const expectedId = targetId.length > 0 ? targetId : (bind ? mirrorPlaylistId(source.platform, source.remoteId) : '');
  const previous = playlists.find((playlist: Playlist): boolean => playlist.id === expectedId);
  if (targetId.length > 0 && (previous === undefined ||
    targetId === LocalPlaylistRepository.FAVORITES_ID || targetId === LocalPlaylistRepository.LOCAL_MUSIC_ID)) {
    throw new Error('所选歌单已不存在，请重新选择目标');
  }
  const oldCount = previous?.songKeys.length ?? 0;
  let resolvedId = targetId;
  let expectedBindingToken = '';
  if (resolvedId.length === 0) {
    const created = bind ? await LocalPlaylistRepository.createOrGetMirrorPlaylist(source, songs) :
      await LocalPlaylistRepository.createPlaylistWithSongs(name, songs, MusicPlatform.LOCAL);
    resolvedId = created.id;
    if (bind && previous === undefined && created.name !== name) {
      await LocalPlaylistRepository.renamePlaylist(created.id, name);
    }
  }
  if (bind) {
    if (targetId.length > 0 && !await LocalPlaylistRepository.bindMirrorSource(resolvedId, source)) {
      throw new Error('目标歌单已变更，来源绑定未完成');
    }
    // Read the just-bound generation before applying; late responses never revive an unbound source.
    const boundPlaylists = await LocalPlaylistRepository.loadAll();
    const target = boundPlaylists.find((playlist: Playlist): boolean => playlist.id === resolvedId);
    const sourceKey = sourceKeyOf(source);
    const binding = target?.getSyncSources().find((item: PlaylistSyncSource): boolean => sourceKeyOf(item) === sourceKey);
    if (binding === undefined) {
      throw new Error('来源已解除，请重新绑定');
    }
    expectedBindingToken = sourceBindingTokenOf(binding);
    if (!binding.enabled) {
      throw new Error('该来源已暂停，请先启用，或关闭持续绑定按一次性方式导入');
    }
    await LocalPlaylistRepository.applyMirrorSync(resolvedId, songs, '', sourceKey, expectedBindingToken);
  } else if (targetId.length > 0) {
    await LocalPlaylistRepository.importSongs(resolvedId, songs);
  }
  const latestPlaylists = await LocalPlaylistRepository.loadAll();
  const latest = latestPlaylists.find((playlist: Playlist): boolean => playlist.id === resolvedId);
  if (latest === undefined) {
    throw new Error('目标歌单已变更，请刷新后重试');
  }
  if (bind && !latest.getSyncSources().some((binding: PlaylistSyncSource): boolean =>
    sourceKeyOf(binding) === sourceKeyOf(source) && sourceBindingTokenOf(binding) === expectedBindingToken)) {
    throw new Error('导入期间来源已变更，请刷新后重新选择');
  }
  const outcome = new PlaylistImportOutcome();
  outcome.playlistName = latest.name;
  outcome.addedCount = Math.max(0, latest.songKeys.length - oldCount);
  return outcome;
}
