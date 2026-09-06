/**
 * Production binding from the listen-together player surface to the real
 * `PlayerManager` statics. The only purpose is dependency direction: the
 * applier and its tests depend on the interface, never on the player singleton.
 *
 * Every transport call here is a REMOTE_SYNC command source, so nothing the
 * applier does is echoed back to the room (upstream parity).
 */
import { SongItem } from '../model/SongItem';
import { PlayerManager } from './PlayerManager';
import { PlaybackStatus } from './PlaybackConstants';
import { ListenTogetherPlaybackCommandSource } from '../listentogether/control/ListenTogetherPlaybackCommand';
import { ListenTogetherPlayerSurface } from '../listentogether/playback/ListenTogetherPlayerSurface';

const REMOTE_SYNC: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.REMOTE_SYNC;

export class PlayerManagerListenTogetherSurface implements ListenTogetherPlayerSurface {
  private static instance: PlayerManagerListenTogetherSurface | null = null;

  static getInstance(): PlayerManagerListenTogetherSurface {
    if (PlayerManagerListenTogetherSurface.instance === null) {
      PlayerManagerListenTogetherSurface.instance = new PlayerManagerListenTogetherSurface();
    }
    return PlayerManagerListenTogetherSurface.instance;
  }

  currentQueue(): SongItem[] {
    return PlayerManager.getQueue();
  }

  currentSong(): SongItem | null {
    return PlayerManager.getCurrentSong();
  }

  currentPositionMs(): number {
    return PlayerManager.getPositionMs();
  }

  isPlaying(): boolean {
    return PlayerManager.getStatus() === PlaybackStatus.PLAYING;
  }

  isPlayWhenReady(): boolean {
    return PlayerManager.isPlayWhenReady();
  }

  currentMediaUrl(): string | null {
    return PlayerManager.getCurrentMediaUrl();
  }

  playPlaylistForRemoteSync(queue: SongItem[], index: number): void {
    PlayerManager.playPlaylist(queue, index, REMOTE_SYNC);
  }

  applyListenTogetherPlaybackMode(repeatMode: number | null, shuffleEnabled: boolean | null): void {
    PlayerManager.applyListenTogetherPlaybackMode(repeatMode, shuffleEnabled);
  }

  resetSyncPlaybackRate(): void {
    PlayerManager.resetListenTogetherSyncPlaybackRate();
  }

  setSyncPlaybackRate(rate: number): void {
    PlayerManager.setListenTogetherSyncPlaybackRate(rate);
  }

  seekToForRemoteSync(positionMs: number): void {
    PlayerManager.seekTo(positionMs, REMOTE_SYNC);
  }

  pauseForRemoteSync(): void {
    PlayerManager.pause(REMOTE_SYNC);
  }

  playForRemoteSync(): void {
    PlayerManager.play(REMOTE_SYNC);
  }

  shouldHoldPlaybackForSafetyPause(causeType: string | null): boolean {
    return PlayerManager.shouldHoldListenTogetherPlaybackForSafetyPause(causeType);
  }

  shouldWaitForAuthoritativeStream(song: SongItem): boolean {
    return PlayerManager.shouldWaitForListenTogetherAuthoritativeStream(song);
  }

  elapsedRealtimeMs(): number {
    // ArkTS has no separate monotonic-uptime API in the base runtime; the
    // event-loop clock does not step backwards, which is the property the
    // elapsed math needs.
    return Date.now();
  }

  wallClockMs(): number {
    return Date.now();
  }
}
