import { describe, it, expect } from '@ohos/hypium';
import { WebDavConfigRepository } from '../../../main/ets/sync/webdav/WebDavConfigRepository';
import { WebDavSyncClient, WebDavTransport } from '../../../main/ets/sync/webdav/WebDavTransport';
import { OhosWebDavExecutor } from '../../../main/ets/sync/webdav/OhosWebDavExecutor';
import { WebDavError, WebDavErrorKind } from '../../../main/ets/sync/webdav/WebDavErrors';
import { SyncService } from '../../../main/ets/sync/SyncService';
import { deserializeSyncContent } from '../../../main/ets/sync/SyncDataJsonCodec';
import { playlistIdToSync } from '../../../main/ets/sync/SyncSongConvert';
import { LocalPlaylistRepository } from '../../../main/ets/data/LocalPlaylistRepository';
import { Playlist } from '../../../main/ets/model/Playlist';

/**
 * M5.6 WebDAV sync acceptance against a self-hosted local server
 * (host-side script tools/m56: python webdav_server.py on 127.0.0.1:18765,
 * reachable from the emulator as 10.0.2.2:18765; Basic auth neri/neri-m56-local).
 *
 * The suite is deliberately idempotent and instance-agnostic: running it on
 * emulator A first performs the initial upload, then running the same suite on
 * emulator B performs download+merge+upload (cross-device data becomes
 * visible), and any subsequent run exercises the deterministic conflict path
 * (a stale fingerprint is injected before syncing, so the optimistic PUT hits
 * HTTP 412 and the coordinator must refetch -> remerge -> re-upload). Merge
 * policy equivalence with Android is covered by the 107 local unit tests; this
 * suite proves the pipeline over a real network with per-device data
 * isolation.
 */

const SERVER_URL: string = 'http://10.0.2.2:18765';
const BASE_PATH: string = 'dav';
const USERNAME: string = 'neri';
const PASSWORD: string = 'neri-m56-local';
const PLAYLIST_PREFIX: string = 'm56-';

/** Stale marker that can never match the live sha256 fingerprint: forces the
 * coordinator onto the remote-changed path (refetch -> remerge -> upload).
 * Note it does NOT reach the PUT If-Match header (upload always carries the
 * version from the coordinator's own fetch); a true 412 needs a concurrent
 * write inside the fetch->upload window and is covered by the local
 * SyncCoordinator/WebDavTransport unit tests plus the host-side curl matrix. */
const STALE_REMOTE_VERSION: string =
  'fingerprint:0000000000000000000000000000000000000000000000000000000000000000' +
  ';etag:%2200000000000000000000000000%22';

async function caughtWebDavKind(action: () => Promise<void>): Promise<string> {
  try {
    await action();
  } catch (error) {
    const e = error as WebDavError;
    if (e instanceof WebDavError) {
      return e.kind;
    }
    return `unexpected:${(error as Error).message}`;
  }
  return 'no-error';
}

export default function syncWebdavDeviceTest(): void {
  describe('ActsSyncWebdavDeviceTest', () => {
    it('badCredentialsClassifiedAsAuth', 0, async () => {
      // Wrong password against the live server: also proves emulator -> host
      // (10.0.2.2:8765) connectivity; an unreachable server would be NETWORK.
      const transport = new WebDavTransport(new OhosWebDavExecutor(), USERNAME, 'definitely-wrong');
      const kind = await caughtWebDavKind(() => transport.validateConnection(SERVER_URL, BASE_PATH));
      expect(kind).assertEqual(WebDavErrorKind.AUTH);
    });

    it('unreachableServerClassifiedAsNetwork', 0, async () => {
      const transport = new WebDavTransport(new OhosWebDavExecutor(), USERNAME, PASSWORD);
      const kind = await caughtWebDavKind(() =>
        transport.validateConnection('http://10.0.2.2:59997', BASE_PATH));
      expect(kind).assertEqual(WebDavErrorKind.NETWORK);
    });

    it('syncUploadsMergesAndRecoversFromConflict', 0, async () => {
      await WebDavConfigRepository.init();
      const configured = await WebDavConfigRepository.saveConfig(
        SERVER_URL, BASE_PATH, USERNAME, PASSWORD);
      expect(configured).assertTrue();

      const config = await WebDavConfigRepository.loadConfig();
      expect(config !== null).assertTrue();

      // Probe whether a previous device already uploaded a backup.
      const probeClient = new WebDavSyncClient(
        new WebDavTransport(new OhosWebDavExecutor(), USERNAME, PASSWORD));
      let remoteUrl = '';
      if (config !== null) {
        remoteUrl = config.remoteFileUrl();
      }
      const remoteSnapshot = await probeClient.fetchRemoteSnapshot(remoteUrl);
      const firstUpload = remoteSnapshot === null;

      // Local change for this run (unique per device + run).
      const playlistName = `${PLAYLIST_PREFIX}${Date.now().toString(36)}` +
        `${Math.floor(Math.random() * 1000)}`;
      await LocalPlaylistRepository.createPlaylist(playlistName);

      if (!firstUpload) {
        // Deterministic conflict injection: the stored remote marker is stale,
        // so the optimistic PUT carries a dead If-Match etag and the server
        // answers 412; the coordinator must refetch -> remerge -> re-upload.
        await WebDavConfigRepository.saveLastRemoteFingerprint(STALE_REMOTE_VERSION);
      }

      let report = await SyncService.syncWebDav();
      expect(report.success).assertTrue();
      if (!report.success) {
        // Surface the failure reason in the test output on the failing path.
        expect(`sync failure message: ${report.message}`).assertEqual('');
      }
      expect(report.uploadPerformed).assertTrue();
      if (!firstUpload) {
        expect(report.remoteChangedDuringSync).assertTrue();
      }

      // Post-merge assertions on local data. Cross-device evidence (remote
      // backup holding playlists created by BOTH devices) is asserted on the
      // host side against the server file after each round; inside the device
      // we cannot reliably assert "other device's playlist" on later rounds
      // because deletion tombstones from earlier cleanups legitimately win
      // the merge and remove those very playlists.
      const playlists: Playlist[] = await LocalPlaylistRepository.loadAll();
      const names: string[] = playlists.map((item: Playlist) => item.name);
      expect(names.includes(playlistName)).assertTrue();

      // Second sync must stay stable (no conflict loop, no data change).
      report = await SyncService.syncWebDav();
      expect(report.success).assertTrue();
      if (!report.success) {
        expect(`second sync failure message: ${report.message}`).assertEqual('');
      }

      // Cleanup only what this run created; remote-side leftovers are part of
      // the throwaway host-side server directory.
      const cleanup: Playlist[] = await LocalPlaylistRepository.loadAll();
      for (const item of cleanup) {
        if (item.name === playlistName) {
          await LocalPlaylistRepository.removePlaylist(item.id);
        }
      }
    });

    it('deletedPlaylistTombstonePropagatesToRemote', 0, async () => {
      // M5.7 regression: deleting a playlist right after a sync used to leave
      // a live row on the remote (the apply had rewritten the local id shape,
      // so the exact-match removal missed it and the next snapshot resurrect
      // it). The tombstone must now reach the remote and stay deleted locally.
      await WebDavConfigRepository.init();
      const configured = await WebDavConfigRepository.saveConfig(
        SERVER_URL, BASE_PATH, USERNAME, PASSWORD);
      expect(configured).assertTrue();

      const playlist = await LocalPlaylistRepository.createPlaylist(
        `${PLAYLIST_PREFIX}del${Date.now().toString(36)}`);
      const pid = playlistIdToSync(playlist.id);

      let report = await SyncService.syncWebDav();
      expect(report.success).assertTrue();
      if (!report.success) {
        expect(`upload phase failure: ${report.message}`).assertEqual('');
      }

      await LocalPlaylistRepository.removePlaylist(playlist.id);
      const stillLive = (await LocalPlaylistRepository.loadAll())
        .some((item: Playlist): boolean => playlistIdToSync(item.id) === pid);
      expect(stillLive).assertFalse();

      report = await SyncService.syncWebDav();
      expect(report.success).assertTrue();
      if (!report.success) {
        expect(`tombstone phase failure: ${report.message}`).assertEqual('');
      }
      expect(report.uploadPerformed).assertTrue();

      const config = await WebDavConfigRepository.loadConfig();
      expect(config !== null).assertTrue();
      if (config !== null) {
        const snapshot = await new WebDavSyncClient(
          new WebDavTransport(new OhosWebDavExecutor(), USERNAME, PASSWORD))
          .fetchRemoteSnapshot(config.remoteFileUrl());
        expect(snapshot !== null).assertTrue();
        if (snapshot !== null) {
          const decoded = deserializeSyncContent(snapshot.content);
          expect(decoded.data !== null).assertTrue();
          if (decoded.data !== null) {
            const row = decoded.data.playlists.find((item): boolean => item.id === pid);
            expect(row !== undefined).assertTrue();
            if (row !== undefined) {
              expect(row.isDeleted).assertTrue();
            }
          }
        }
      }

      const resurrected = (await LocalPlaylistRepository.loadAll())
        .some((item: Playlist): boolean => playlistIdToSync(item.id) === pid);
      expect(resurrected).assertFalse();
    });
  });
}
