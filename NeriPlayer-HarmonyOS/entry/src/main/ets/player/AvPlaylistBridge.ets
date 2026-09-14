// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { Logger } from '../app/Logger';
import { DownloadStorage } from '../download/DownloadStorage';

/** Upper bound for one native-playlist call; the APIs are @since 26 and a
 * hung stub (the setLoudnessGain lesson) must never pin the player. */
const BRIDGE_CALL_TIMEOUT_MS = 8000;

/**
 * The API 26 native-playlist seam of the player (addPlaybackMediaSource /
 * advanceToNextMediaSource / onPlaybackContentChanged, all @since 26).
 *
 * Role: transport accelerator for the *next* natural track end. The
 * QueueEngine still decides whether an advance happens (sleep timer,
 * listen-together room, repeat-one replay all arbitrate first in
 * PlayerManager.handleCompletion); when it does, the bridge hands over a
 * source that was pre-added to the player's list, and the kernel swaps media
 * without loadSong's reset/setMediaSource/prepare cycle.
 *
 * Only offline sources are primed (see AvPlaylistPolicy): the primed entry
 * holds the fd the source was built from, and it is released exactly once —
 * on consume (the advance moved to it), on abandon (conditions changed) or
 * on failure.
 *
 * Every platform call is timeout-guarded; the first hard failure latches the
 * bridge off for the process and playback silently keeps the loadSong path.
 */
export class AvPlaylistBridge {
  private static player: media.AVPlayer | null = null;
  private static primed: PrimedSlot | null = null;
  private static failed: boolean = false;

  static attach(player: media.AVPlayer): void {
    if (AvPlaylistBridge.failed || AvPlaylistBridge.player === player) {
      return;
    }
    AvPlaylistBridge.player = player;
    try {
      player.onPlaybackContentChanged((id: string) => {
        AvPlaylistBridge.onContentChanged(id);
      });
      // The app owns end-of-track arbitration, so the native list must never
      // loop on its own; an unsolicited advance would bypass the sleep timer
      // and the listen-together room.
      player.playlistLoopMode = media.PlaylistLoopMode.PLAYLIST_LOOP_MODE_NONE;
      Logger.info('AvPlaylistBridge attached');
    } catch (error) {
      const e = error as Error;
      AvPlaylistBridge.latchOff(`attach failed: ${e.message}`);
    }
  }

  static isPrimed(): boolean {
    return AvPlaylistBridge.primed !== null;
  }

  static peekPrimedIndex(): number {
    return AvPlaylistBridge.primed !== null ? AvPlaylistBridge.primed.queueIndex : -1;
  }

  /** fd:// URL of the primed source, for currentMediaUrl bookkeeping. */
  static primedMediaUrl(): string {
    return AvPlaylistBridge.primed !== null ? AvPlaylistBridge.primed.mediaUrl : '';
  }

  /**
   * Pre-adds the next (offline) source to the player's playlist. `localPath`
   * must be a readable sandbox/download file; the bridge opens and owns the
   * fd until the entry is consumed or abandoned. The source is built with
   * createMediaSourceWithFd — feeding an fd:// URL into
   * createMediaSourceWithUrl makes the container sniffer fail with 5400106
   * (the same lesson as PlayerManager.openLocalFd), and a gapless advance
   * into that dead source would bypass every loadSong retry path.
   */
  static async prime(queueIndex: number, localPath: string): Promise<boolean> {
    const player = AvPlaylistBridge.player;
    if (AvPlaylistBridge.failed || player === null || localPath.length === 0) {
      return false;
    }
    AvPlaylistBridge.abandon();
    // Catalog paths from a user-picked download directory hold file:// URIs;
    // CoreFileKit needs the converted sandbox path for open/stat.
    const path = DownloadStorage.resolveFilePath(localPath);
    if (path.length === 0) {
      AvPlaylistBridge.latchOff('prime failed: unreadable path');
      return false;
    }
    let fd: fileIo.File | null = null;
    try {
      fd = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const mediaUrl = `fd://${fd.fd}`;
      const size = fileIo.statSync(path).size;
      const source = media.createMediaSourceWithFd({ fd: fd.fd, offset: 0, length: size });
      if (source === undefined) {
        throw new Error('createMediaSourceWithFd returned undefined');
      }
      const assignedId = await AvPlaylistBridge.call(
        player.addPlaybackMediaSource(source, `npq:${queueIndex}`)
      );
      AvPlaylistBridge.primed = {
        playlistId: assignedId,
        queueIndex: queueIndex,
        mediaUrl: mediaUrl,
        fd: fd
      };
      Logger.info(`AvPlaylistBridge primed queue index ${queueIndex} (${assignedId})`);
      return true;
    } catch (error) {
      const e = error as Error;
      AvPlaylistBridge.closeFd(fd);
      AvPlaylistBridge.latchOff(`prime failed: ${e.message}`);
      return false;
    }
  }

  /**
   * Drops the primed entry (new load, mode change, queue mutation). The
   * remove call keeps the native list in step with app state; its failure
   * means the list's shape is unknown, so it latches the bridge off rather
   * than risk advancing to a stale source later.
   */
  static abandon(): void {
    const primed = AvPlaylistBridge.primed;
    if (primed === null) {
      return;
    }
    AvPlaylistBridge.primed = null;
    AvPlaylistBridge.closeFd(primed.fd);
    if (AvPlaylistBridge.failed || AvPlaylistBridge.player === null) {
      return;
    }
    try {
      AvPlaylistBridge.call(AvPlaylistBridge.player.removePlaybackMediaSource(primed.playlistId))
        .catch(() => {
          // Already nulled above; a failed remove only costs the latch.
        });
    } catch (error) {
      const e = error as Error;
      AvPlaylistBridge.latchOff(`abandon remove failed: ${e.message}`);
    }
  }

  /**
   * Performs the gapless handover. True when the kernel accepted it (the
   * caller then applies the app-side track-change pipeline); false when the
   * bridge is off/empty or the call failed — the caller falls back to the
   * loadSong path with the engine untouched.
   */
  static async advance(): Promise<boolean> {
    const player = AvPlaylistBridge.player;
    if (AvPlaylistBridge.failed || AvPlaylistBridge.primed === null || player === null) {
      return false;
    }
    try {
      await AvPlaylistBridge.call(player.advanceToNextMediaSource());
      AvPlaylistBridge.consume();
      return true;
    } catch (error) {
      const e = error as Error;
      AvPlaylistBridge.latchOff(`advance failed: ${e.message}`);
      return false;
    }
  }

  private static consume(): void {
    const primed = AvPlaylistBridge.primed;
    if (primed === null) {
      return;
    }
    AvPlaylistBridge.primed = null;
    AvPlaylistBridge.closeFd(primed.fd);
  }

  /**
   * Confirmation channel for the advance, and a tripwire for anything the
   * app did not ask for (with looping pinned to NONE the list should never
   * move on its own).
   */
  private static onContentChanged(id: string): void {
    const primed = AvPlaylistBridge.primed;
    if (primed === null) {
      Logger.warn(`AvPlaylistBridge: unexpected content change to ${id}`);
      return;
    }
    if (id === primed.playlistId) {
      AvPlaylistBridge.consume();
      return;
    }
    Logger.warn(`AvPlaylistBridge: content changed to unknown id ${id} (primed ${primed.playlistId})`);
  }

  private static closeFd(fd: fileIo.File | null): void {
    if (fd === null) {
      return;
    }
    try {
      fileIo.closeSync(fd);
    } catch (error) {
      const e = error as Error;
      Logger.debug(`AvPlaylistBridge close fd failed: ${e.message}`);
    }
  }

  /** One shared timeout wrapper; a rejection carries the call name. */
  private static call<T>(promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      const timer = setTimeout(() => {
        reject(new Error('avplaylist call timed out'));
      }, BRIDGE_CALL_TIMEOUT_MS);
      promise.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }, (reason: Error) => {
        clearTimeout(timer);
        reject(reason);
      });
    });
  }

  private static latchOff(reason: string): void {
    if (AvPlaylistBridge.failed) {
      return;
    }
    AvPlaylistBridge.failed = true;
    AvPlaylistBridge.consume();
    Logger.warn(`AvPlaylistBridge disabled for this process: ${reason}`);
  }
}

interface PrimedSlot {
  playlistId: string;
  queueIndex: number;
  mediaUrl: string;
  fd: fileIo.File | null;
}
