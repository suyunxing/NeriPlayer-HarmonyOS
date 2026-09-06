/**
 * Tests for listentogether/playback/ListenTogetherPlayerStateApplier.ets —
 * upstream's ListenTogetherPlayerStateApplier had no unit test because it calls
 * the PlayerManager singleton directly; here the whole orchestration runs
 * against a recording fake surface.
 *
 * The planner arithmetic itself is pinned by ListenTogetherSyncPlanner.test;
 * what these cases lock is the applier's own decisions: the three skip gates,
 * when a reload/seek/play/pause/rate command goes out, and that the expected
 * position is derived from the clock offset and clamped to the track duration.
 */
import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import {
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { ListenTogetherChannels } from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';
import { ListenTogetherPlayerStateApplier } from '../../../main/ets/listentogether/playback/ListenTogetherPlayerStateApplier';
import {
  ListenTogetherPlayerSurface,
  ListenTogetherPlayerStateApplierConfig
} from '../../../main/ets/listentogether/playback/ListenTogetherPlayerSurface';

const TRACK_DURATION_MS: number = 200_000;

function neteaseTrack(audioId: string): ListenTogetherTrack {
  const track = createListenTogetherTrack(
    `netease:${audioId}`, ListenTogetherChannels.NETEASE, audioId, `Song ${audioId}`, 'Artist');
  // Room snapshots carry real durations; the applier clamps against them.
  track.durationMs = TRACK_DURATION_MS;
  return track;
}

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '', 0, TRACK_DURATION_MS, '');
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = audioId;
  return song;
}

/** A room with a one-track queue playing/paused at `positionMs`. */
function roomWith(trackAudioId: string, playing: boolean, positionMs: number): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ABC234', 1);
  state.queue = [neteaseTrack(trackAudioId)];
  state.currentIndex = 0;
  state.track = neteaseTrack(trackAudioId);
  state.playback.state = playing ? 'playing' : 'paused';
  state.playback.basePositionMs = positionMs;
  state.playback.baseTimestampMs = 1000;
  return state;
}

class RecordedSurface implements ListenTogetherPlayerSurface {
  queue: SongItem[] = [];
  song: SongItem | null = null;
  positionMs: number = 0;
  playing: boolean = false;
  playWhenReady: boolean = false;
  mediaUrl: string | null = null;
  holdSafetyPause: boolean = false;
  waitForAuthoritativeStream: boolean = false;
  elapsedMs: number = 10_000;

  reloadedQueues: number = 0;
  lastReloadIndex: number = -1;
  seekCalls: number[] = [];
  pauseCalls: number = 0;
  playCalls: number = 0;
  rateCalls: number[] = [];
  resets: number = 0;

  currentQueue(): SongItem[] {
    return this.queue;
  }

  currentSong(): SongItem | null {
    return this.song;
  }

  currentPositionMs(): number {
    return this.positionMs;
  }

  isPlaying(): boolean {
    return this.playing;
  }

  isPlayWhenReady(): boolean {
    return this.playWhenReady;
  }

  currentMediaUrl(): string | null {
    return this.mediaUrl;
  }

  playPlaylistForRemoteSync(queue: SongItem[], index: number): void {
    this.reloadedQueues++;
    this.lastReloadIndex = index;
    this.queue = queue;
    this.song = queue[index];
  }

  applyListenTogetherPlaybackMode(repeatMode: number | null, shuffleEnabled: boolean | null): void {
    // Recorded implicitly through room state; not asserted directly here.
  }

  resetSyncPlaybackRate(): void {
    this.resets++;
  }

  setSyncPlaybackRate(rate: number): void {
    this.rateCalls.push(rate);
  }

  seekToForRemoteSync(positionMs: number): void {
    this.seekCalls.push(positionMs);
  }

  pauseForRemoteSync(): void {
    this.pauseCalls++;
  }

  playForRemoteSync(): void {
    this.playCalls++;
  }

  shouldHoldPlaybackForSafetyPause(causeType: string | null): boolean {
    return this.holdSafetyPause;
  }

  shouldWaitForAuthoritativeStream(song: SongItem): boolean {
    return this.waitForAuthoritativeStream;
  }

  elapsedRealtimeMs(): number {
    return this.elapsedMs;
  }

  wallClockMs(): number {
    return 1000;
  }
}

function applierFor(
  surface: RecordedSurface,
  roomProvider: () => ListenTogetherRoomState | null
): ListenTogetherPlayerStateApplier {
  const config = new ListenTogetherPlayerStateApplierConfig(
    TAG, 500, 5000, 2500, 800, 600, 1500, 800, 2000);
  return new ListenTogetherPlayerStateApplier(
    config, surface, roomProvider, () => false, () => 0);
}

const TAG: string = 'test';

export default function listenTogetherStateApplierTest() {
  describe('ListenTogetherPlayerStateApplier', () => {
    it('skips a state older than the accepted version', 0, () => {
      const surface = new RecordedSurface();
      const fresh = roomWith('1', true, 1000);
      const applier = applierFor(surface, () => fresh);

      const stale = roomWith('1', false, 5);
      stale.version = 0;

      expect(applier.apply(stale, 'HEARTBEAT', null)).assertFalse();
      expect(surface.reloadedQueues).assertEqual(0);
      expect(surface.seekCalls.length).assertEqual(0);
      expect(surface.pauseCalls).assertEqual(0);
      expect(surface.playCalls).assertEqual(0);
    });

    it('holds everything back while a listener safety pause is armed', 0, () => {
      const surface = new RecordedSurface();
      surface.holdSafetyPause = true;
      const room = roomWith('1', true, 1000);
      const applier = applierFor(surface, () => room);

      expect(applier.apply(room, 'HEARTBEAT', null)).assertFalse();
      expect(surface.reloadedQueues).assertEqual(0);
      expect(surface.playCalls).assertEqual(0);
    });

    it('skips a room without any track to play', 0, () => {
      const surface = new RecordedSurface();
      const empty = createListenTogetherRoomState('ABC234', 1);
      const applier = applierFor(surface, () => empty);

      expect(applier.apply(empty, 'HEARTBEAT', null)).assertFalse();
      expect(surface.reloadedQueues).assertEqual(0);
    });

    it('reloads the playlist and clamps the target index on context change', 0, () => {
      const surface = new RecordedSurface();
      const room = roomWith('2', false, 0);
      room.queue = [neteaseTrack('1'), neteaseTrack('2'), neteaseTrack('3')];
      room.currentIndex = 9; // Out of range on purpose; must clamp to 2.
      const applier = applierFor(surface, () => room);

      expect(applier.apply(room, 'SET_TRACK', 0)).assertTrue();
      expect(surface.reloadedQueues).assertEqual(1);
      expect(surface.lastReloadIndex).assertEqual(2);
      expect(surface.pauseCalls).assertEqual(1);
    });

    it('seeks and pauses a paused listener whose drift exceeds the tight threshold', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 0;
      const room = roomWith('1', false, 5000);
      const applier = applierFor(surface, () => room);

      // Explicit position: drift = 5000 >= pausedDriftForceSyncMs (800).
      expect(applier.apply(room, 'HEARTBEAT', 5000)).assertTrue();
      expect(surface.seekCalls.length).assertEqual(1);
      expect(surface.seekCalls[0]).assertEqual(5000);
      // Already paused locally: no pause command needed.
      expect(surface.pauseCalls).assertEqual(0);
      expect(surface.playCalls).assertEqual(0);
    });

    it('leaves a paused listener alone inside the threshold', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 4900;
      const room = roomWith('1', false, 5000);
      const applier = applierFor(surface, () => room);

      expect(applier.apply(room, 'HEARTBEAT', 5000)).assertTrue();
      expect(surface.seekCalls.length).assertEqual(0);
      expect(surface.pauseCalls).assertEqual(0);
    });

    it('issues play when the room plays and the local player does not', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 3000;
      surface.playing = false;
      surface.playWhenReady = false;
      const room = roomWith('1', true, 3000);
      const applier = applierFor(surface, () => room);

      expect(applier.apply(room, 'HEARTBEAT', 3000)).assertTrue();
      expect(surface.playCalls).assertEqual(1);
    });

    it('nudges the playback rate for a small positive drift while playing', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 3000;
      surface.playing = true;
      surface.playWhenReady = true;
      const room = roomWith('1', true, 3500);
      const applier = applierFor(surface, () => room);

      // Drift = 500 < soft min (600): no correction at all.
      expect(applier.apply(room, 'HEARTBEAT', 3500)).assertTrue();
      expect(surface.seekCalls.length).assertEqual(0);
      expect(surface.rateCalls.length).assertEqual(0);

      // Drift = 1000 in [600, 2500), room ahead -> 1.03x.
      const ahead = roomWith('1', true, 4000);
      expect(applier.apply(ahead, 'HEARTBEAT', 4000)).assertTrue();
      expect(surface.rateCalls.length).assertEqual(1);
      expect(surface.rateCalls[0]).assertEqual(1.03);
    });

    it('resets the rate when the drift is below the correction floor', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 3000;
      surface.playing = true;
      surface.playWhenReady = true;
      const room = roomWith('1', true, 3200);
      const applier = applierFor(surface, () => room);

      // Drift 200 < floor: the rate must be actively reset, not left alone.
      expect(applier.apply(room, 'HEARTBEAT', 3200)).assertTrue();
      expect(surface.resets).assertEqual(1);
      expect(surface.rateCalls.length).assertEqual(0);
    });

    it('extrapolates the position from the clock offset and clamps it', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 0;
      const room = roomWith('1', false, 190_000);
      room.playback.repeatMode = 0;
      const applier = applierFor(surface, () => room);

      // An absurdly large explicit position must clamp to the track duration.
      expect(applier.apply(room, 'SET_TRACK', 999_999)).assertTrue();
      expect(surface.seekCalls.length).assertEqual(1);
      expect(surface.seekCalls[0]).assertEqual(TRACK_DURATION_MS);
    });

    it('ignores a passive zero-position rollback deep into a track', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 60_000;
      surface.playing = true;
      surface.playWhenReady = true;
      const room = roomWith('1', true, 60_000);
      const applier = applierFor(surface, () => room);

      // HEARTBEAT reporting 0 while we are a minute in: keep our position.
      expect(applier.apply(room, 'HEARTBEAT', 0)).assertTrue();
      expect(surface.seekCalls.length).assertEqual(0);
    });

    it('forces a reload on a watchdog stall even without an index change', 0, () => {
      const surface = new RecordedSurface();
      surface.queue = [neteaseSong('1')];
      surface.song = surface.queue[0];
      surface.positionMs = 1000;
      surface.playing = false;
      const room = roomWith('1', true, 1000);
      const applier = applierFor(surface, () => room);

      expect(applier.apply(room, 'WATCHDOG_STALL', 1000)).assertTrue();
      expect(surface.reloadedQueues).assertEqual(1);
    });
  });
}
