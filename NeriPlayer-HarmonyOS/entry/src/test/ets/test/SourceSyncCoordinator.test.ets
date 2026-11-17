// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { PlaylistSyncSource, sourceKeyOf, sourceBindingTokenOf } from '../../../main/ets/sourcesync/SourceSyncModels';
import { SyncSourceAdapter } from '../../../main/ets/sourcesync/SyncSourceAdapter';
import { attachPlaylistSource, detachPlaylistSource, currentSourceForApply, applySourceSnapshot }
  from '../../../main/ets/sourcesync/SourceSyncOwnership';
import { SourceSyncDependencies, runSourceSync } from '../../../main/ets/sourcesync/SourceSyncRunner';

function track(id: number): SongItem {
  return new SongItem(id, 'track', 'artist', 'album', id, 100, '', '', MusicPlatform.NETEASE);
}

class FakeSourceAdapter implements SyncSourceAdapter {
  fingerprint: string = 'changed';
  songs: SongItem[] = [track(1)];
  fail: boolean = false;
  fetchCount: number = 0;
  beforeFetch: (() => void) | null = null;
  async peekFingerprint(): Promise<string> {
    if (this.fail) {
      throw new Error('fixture fetch failed');
    }
    return this.fingerprint;
  }
  async fetchSongs(): Promise<SongItem[]> {
    this.fetchCount += 1;
    if (this.beforeFetch !== null) {
      this.beforeFetch();
    }
    return this.songs;
  }
}

class FakeSourceDependencies implements SourceSyncDependencies {
  playlist: Playlist;
  adapters: Map<string, FakeSourceAdapter> = new Map<string, FakeSourceAdapter>();
  appliedKeys: string[] = [];
  appliedTokens: string[] = [];
  failed: string[] = [];
  loggedIn: boolean = true;
  constructor(playlist: Playlist) { this.playlist = playlist; }
  adapterFor(source: PlaylistSyncSource): SyncSourceAdapter | null {
    return this.adapters.get(sourceKeyOf(source)) ?? null;
  }
  isLoggedIn(platform: MusicPlatform): boolean { return this.loggedIn; }
  now(): number { return 100000; }
  async apply(id: string, songs: SongItem[], fingerprint: string, key: string, token: string): Promise<boolean> {
    this.appliedKeys.push(key);
    this.appliedTokens.push(token);
    const source = currentSourceForApply(this.playlist, key, token);
    if (source === null) {
      return false;
    }
    const result = applySourceSnapshot(this.playlist, source, songs);
    this.playlist.songKeys = result.keys;
    this.playlist.songs = result.songs;
    source.lastFingerprint = fingerprint;
    source.lastCheckedAt = this.now();
    return result.changed;
  }
  onFailure(source: PlaylistSyncSource, error: Error): void { this.failed.push(sourceKeyOf(source)); }
  add(id: string, platform: MusicPlatform = MusicPlatform.BILIBILI): FakeSourceAdapter {
    const source = new PlaylistSyncSource(platform, id, id);
    attachPlaylistSource(this.playlist, source, 'binding-' + id);
    const adapter = new FakeSourceAdapter();
    adapter.songs = [track(Number(id))];
    this.adapters.set(sourceKeyOf(source), adapter);
    return adapter;
  }
}

export default function sourceSyncCoordinatorTest(): void {
  describe('SourceSyncCoordinator', () => {
    it('runsEachEnabledSourceAndIsolatesFailureBetweenTwoBiliAndNetease', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      deps.add('1').fail = true;
      deps.add('2');
      deps.add('3', MusicPlatform.NETEASE);
      const result = await runSourceSync([playlist], deps);
      expect(result.failedSourceKeys.length).assertEqual(1);
      expect(result.syncedCount).assertEqual(2);
      expect(result.changed).assertTrue();
      expect(playlist.songs.length).assertEqual(2);
      expect(deps.appliedKeys[0]).assertEqual('bilibili:2');
      expect(deps.appliedKeys[1]).assertEqual('netease:3');
    });

    it('targetedSourceDoesNotFetchOrModifyOtherBindings', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      const a = deps.add('1');
      const b = deps.add('2');
      await runSourceSync([playlist], deps, 'p', 'bilibili:2');
      expect(a.fetchCount).assertEqual(0);
      expect(b.fetchCount).assertEqual(1);
      expect(deps.appliedKeys.length).assertEqual(1);
      expect(playlist.songs[0].id).assertEqual(2);
    });

    it('targetsOnlyRequestedPlaylistAndSkipsDisabledSources', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      const a = deps.add('1');
      const b = deps.add('2');
      playlist.getSyncSources()[0].enabled = false;
      const other = Playlist.fromJson(playlist.toJson());
      other.id = 'other';
      await runSourceSync([other, playlist], deps, 'p');
      expect(a.fetchCount).assertEqual(0);
      expect(b.fetchCount).assertEqual(1);
    });

    it('sameFingerprintSkipsAutoButManualForceFetchesSameCountChanges', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      const adapter = deps.add('1');
      const source = playlist.getSyncSources()[0];
      source.lastFingerprint = adapter.fingerprint;
      source.lastCheckedAt = deps.now();
      await runSourceSync([playlist], deps);
      expect(adapter.fetchCount).assertEqual(0);
      await runSourceSync([playlist], deps, 'p', 'bilibili:1', true);
      expect(adapter.fetchCount).assertEqual(1);
      source.ownershipKnown = false;
      await runSourceSync([playlist], deps);
      expect(adapter.fetchCount).assertEqual(2);
    });

    it('lateFetchAfterUnbindOrRebindCannotRestoreRemovedBinding', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      const adapter = deps.add('1');
      const source = playlist.getSyncSources()[0];
      const token = sourceBindingTokenOf(source);
      adapter.beforeFetch = (): void => {
        detachPlaylistSource(playlist, 'bilibili:1');
        attachPlaylistSource(playlist, new PlaylistSyncSource(MusicPlatform.BILIBILI, '1', 'new'), 'new-generation');
      };
      const result = await runSourceSync([Playlist.fromJson(playlist.toJson())], deps);
      expect(deps.appliedTokens[0]).assertEqual(token);
      expect(result.changed).assertFalse();
      expect(playlist.songKeys.length).assertEqual(0);
      expect(playlist.getSyncSources()[0].bindingId).assertEqual('new-generation');
    });

    it('emptyAndSignedOutSourcesPreserveOldSongsAndReportFailure', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      const adapter = deps.add('1');
      await runSourceSync([playlist], deps);
      adapter.fingerprint = 'next';
      adapter.songs = [];
      let result = await runSourceSync([playlist], deps);
      expect(result.failedSourceKeys.length).assertEqual(1);
      expect(playlist.songKeys.length).assertEqual(1);
      deps.loggedIn = false;
      result = await runSourceSync([playlist], deps);
      expect(result.failedSourceKeys.length).assertEqual(1);
      expect(playlist.songKeys.length).assertEqual(1);
    });

    it('targetFailureIsThrownOnlyAfterOtherEnabledSourcesFinish', 0, async () => {
      const playlist = new Playlist('p');
      const deps = new FakeSourceDependencies(playlist);
      deps.add('1').fail = true;
      const b = deps.add('2');
      let failed = false;
      try {
        await runSourceSync([playlist], deps, 'p');
      } catch (error) { failed = true; }
      expect(failed).assertTrue();
      expect(b.fetchCount).assertEqual(1);
      expect(playlist.songKeys.length).assertEqual(1);
      let missing = false;
      try {
        await runSourceSync([playlist], deps, 'p', 'bilibili:missing');
      } catch (error) { missing = true; }
      expect(missing).assertTrue();
    });
  });
}
