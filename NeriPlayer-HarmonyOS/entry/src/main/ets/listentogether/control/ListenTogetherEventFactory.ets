/**
 * Port of listentogether/control/ListenTogetherEventFactory.kt: every outbound
 * room event is built here and nowhere else, so the wire shape has exactly one
 * author.
 *
 * Three divergences, all of them seams rather than behaviour changes:
 *
 * 1. **The local player state arrives as an injected snapshot.** Upstream reads
 *    six `PlayerManager` flows plus
 *    `PlayerManager.currentListenTogetherShareableStreamUrls()` directly out of a
 *    Kotlin `object`, which makes the factory impossible to exercise off-device.
 *    Here one [ListenTogetherLocalPlaybackSnapshot] is pulled from a provider at
 *    the top of each build, which also fixes a latent upstream inconsistency: a
 *    single event could read `currentQueueFlow` and `isPlayingFlow` at two
 *    different instants. Upstream's `localPlaybackStateNameProvider` and
 *    `localTransportActiveProvider` fold into the same snapshot, so the
 *    constructor is 6 parameters instead of 7 despite carrying strictly more.
 * 2. **The clock is injected.** Upstream stamps `System.currentTimeMillis()`
 *    inline at seven sites. A `clockMs` provider makes `clientTimeMs`
 *    reproducible in the host unit suite, and M7.3b passes `Date.now`.
 * 3. **The six `NPLogger` calls in `buildLinkReadyEvent` become an optional
 *    diagnostic listener.** Every other file under `listentogether/` is kit-free
 *    on purpose (see `invite/ListenTogetherIdentity.ets`), and importing
 *    `app/Logger` would pull `@kit.PerformanceAnalysisKit` into the tree. The
 *    listener seam is the one this codebase already uses for the same problem —
 *    `ListenTogetherBlockedStreamUrlListener` in the queue snapshot. The messages
 *    are upstream's, minus nothing; none of them contains a stream url, and none
 *    ever may, because resolved urls carry auth tokens.
 */
import { SongItem } from '../../model/SongItem';
import {
  ListenTogetherEvent,
  createListenTogetherEvent
} from '../protocol/ListenTogetherEventModels';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherSocketEnvelope } from '../protocol/ListenTogetherSocketEnvelope';
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';
import {
  ListenTogetherShareableQueueSnapshot,
  listenTogetherShareableQueueSnapshot,
  mergeListenTogetherCurrentTrack
} from '../playback/ListenTogetherShareableQueueSnapshot';
import {
  listenTogetherTrackWithStreamUrls,
  songItemToListenTogetherTrackOrNull
} from '../mapping/ListenTogetherTrackMapping';
import {
  hasShareableListenTogetherTrackAt,
  isShareableForListenTogether
} from '../playback/ListenTogetherShareabilityPolicy';
import { indexOfListenTogetherTrack } from '../playback/ListenTogetherPlaybackTrack';
import {
  resolveListenTogetherLinkReadyState,
  resolveListenTogetherPlaybackCommandShouldPlay
} from '../compat/ListenTogetherEventCompatibility';
import { resolveListenTogetherPlaybackCommandSnapshot } from './ListenTogetherPlaybackCommandSnapshot';
import { ListenTogetherPlaybackCommand } from './ListenTogetherPlaybackCommand';

const REQUEST_TYPE_PREFIX: string = 'REQUEST_';

/**
 * Everything the factory needs to know about the local player, read at one
 * instant. Upstream's seven separate global reads collapse into this.
 */
export class ListenTogetherLocalPlaybackSnapshot {
  /** Upstream `PlayerManager.currentQueueFlow.value`. */
  queue: SongItem[] = [];
  /** Upstream `PlayerManager.currentSongFlow.value`. */
  currentSong: SongItem | null = null;
  /** Upstream `PlayerManager.playbackPositionFlow.value`. */
  positionMs: number = 0;
  /** Upstream `PlayerManager.isPlayingFlow.value`. */
  isPlaying: boolean = false;
  /** Upstream `PlayerManager.repeatModeFlow.value`. */
  repeatMode: number = 0;
  /** Upstream `PlayerManager.shuffleModeFlow.value`. */
  shuffleEnabled: boolean = false;
  /**
   * Upstream `localTransportActiveProvider()`: the transport has been told to
   * play, which is not the same as audio actually flowing yet.
   */
  transportActive: boolean = false;
  /** Upstream `localPlaybackStateNameProvider()`. */
  playbackStateName: string = 'paused';
  /**
   * Upstream `PlayerManager.currentListenTogetherShareableStreamUrls()`: the
   * controller's own resolved urls for the current track, which only ever leave
   * this device when the room settings allow direct links.
   */
  shareableStreamUrls: string[] = [];
}

export type ListenTogetherRoomStateProvider = () => ListenTogetherRoomState | null;
export type ListenTogetherBooleanProvider = () => boolean;
export type ListenTogetherStringProvider = () => string;
export type ListenTogetherNumberProvider = () => number;
export type ListenTogetherLocalPlaybackSnapshotProvider = () => ListenTogetherLocalPlaybackSnapshot;
/** Receives the reason an event could not be built. Never carries a stream url. */
export type ListenTogetherEventDiagnosticListener = (message: string) => void;

export class ListenTogetherEventFactory {
  private readonly roomStateProvider: ListenTogetherRoomStateProvider;
  private readonly isControllerProvider: ListenTogetherBooleanProvider;
  private readonly playbackSnapshotProvider: ListenTogetherLocalPlaybackSnapshotProvider;
  private readonly eventIdFactory: ListenTogetherStringProvider;
  private readonly clientInstanceIdProvider: ListenTogetherStringProvider;
  private readonly clientSequenceFactory: ListenTogetherNumberProvider;
  private readonly clockMs: ListenTogetherNumberProvider;
  private readonly onDiagnostic: ListenTogetherEventDiagnosticListener | null;

  constructor(
    roomStateProvider: ListenTogetherRoomStateProvider,
    isControllerProvider: ListenTogetherBooleanProvider,
    playbackSnapshotProvider: ListenTogetherLocalPlaybackSnapshotProvider,
    eventIdFactory: ListenTogetherStringProvider,
    clientInstanceIdProvider: ListenTogetherStringProvider,
    clientSequenceFactory: ListenTogetherNumberProvider,
    clockMs: ListenTogetherNumberProvider,
    onDiagnostic: ListenTogetherEventDiagnosticListener | null = null
  ) {
    this.roomStateProvider = roomStateProvider;
    this.isControllerProvider = isControllerProvider;
    this.playbackSnapshotProvider = playbackSnapshotProvider;
    this.eventIdFactory = eventIdFactory;
    this.clientInstanceIdProvider = clientInstanceIdProvider;
    this.clientSequenceFactory = clientSequenceFactory;
    this.clockMs = clockMs;
    this.onDiagnostic = onDiagnostic;
  }

  buildSetTrackEvent(
    queue: SongItem[],
    currentIndex: number,
    positionMs: number,
    shouldPlay: boolean
  ): ListenTogetherEvent {
    const snapshot = this.shareableSnapshot(queue, currentIndex, this.isControllerProvider());
    const event = this.newEnvelope('SET_TRACK');
    event.positionMs = Math.max(positionMs, 0);
    event.currentIndex = snapshot.currentIndex;
    event.track = trackAt(snapshot.tracks, snapshot.currentIndex);
    event.queue = snapshot.tracks;
    event.shouldPlay = shouldPlay;
    return event;
  }

  buildPlayEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('PLAY', positionMs);
  }

  buildPauseEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('PAUSE', positionMs);
  }

  buildSeekEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('SEEK', positionMs);
  }

  buildRequestPlayEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('REQUEST_PLAY', positionMs);
  }

  buildRequestPauseEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('REQUEST_PAUSE', positionMs);
  }

  buildRequestSeekEvent(positionMs: number): ListenTogetherEvent {
    return this.playbackSnapshotEvent('REQUEST_SEEK', positionMs);
  }

  /**
   * The mode change carries the *current* position rather than a caller-supplied
   * one: nothing about repeat or shuffle moves the playhead, so re-sending where
   * it already is keeps peers from seeking.
   */
  buildPlaybackModeEvent(repeatMode: number, shuffleEnabled: boolean): ListenTogetherEvent {
    const playback = this.playbackSnapshotProvider();
    const type = this.isControllerProvider() ? 'PLAYBACK_MODE' : 'REQUEST_PLAYBACK_MODE';
    const event = this.playbackSnapshotEvent(type, Math.max(playback.positionMs, 0), playback);
    event.repeatMode = repeatMode;
    event.shuffleEnabled = shuffleEnabled;
    return event;
  }

  /**
   * `includeQueue = false` is how a listener keeps a 22-second heartbeat cheap:
   * the room already has the queue, and an absent queue means "do not touch it".
   */
  buildHeartbeatEvent(
    state: string,
    positionMs: number,
    includeQueue: boolean = true
  ): ListenTogetherEvent {
    const playback = this.playbackSnapshotProvider();
    const snapshot = this.currentTrackSnapshot(playback, this.isControllerProvider());
    const event = this.newEnvelope('HEARTBEAT');
    event.currentIndex = snapshot.currentIndex;
    event.track = trackAt(snapshot.tracks, snapshot.currentIndex);
    event.queue = includeQueue ? snapshot.tracks : null;
    event.state = state;
    event.positionMs = Math.max(positionMs, 0);
    return event;
  }

  /**
   * `forceRefresh` is sent only when true. A `false` on the wire would read as a
   * deliberate "do not refresh" to a server that supports the flag, which is not
   * what an ordinary link request means.
   */
  buildRequestLinkEvent(
    stableKey: string,
    currentIndex: number | null = null,
    track: ListenTogetherTrack | null = null,
    forceRefresh: boolean = false
  ): ListenTogetherEvent {
    const event = this.newEnvelope('REQUEST_LINK');
    event.currentIndex = currentIndex;
    event.track = track;
    event.requestTrackStableKey = stableKey;
    event.forceRefresh = forceRefresh ? true : null;
    return event;
  }

  /**
   * The controller answering a listener's REQUEST_LINK. Six guards, each of which
   * means "the track this link was asked for is no longer the one playing here",
   * so publishing anything would hand the room a url for the wrong song.
   */
  buildLinkReadyEvent(
    stableKey: string,
    positionMs: number,
    streamUrlOverride: string | null = null,
    streamUrlsOverride: string[] = []
  ): ListenTogetherEvent | null {
    const playback = this.playbackSnapshotProvider();
    const currentSong = playback.currentSong;
    if (currentSong === null) {
      this.report(`buildLinkReadyEvent(): currentSong missing, stableKey=${stableKey}`);
      return null;
    }
    const currentTrack = songItemToListenTogetherTrackOrNull(currentSong);
    if (currentTrack === null) {
      this.report(`buildLinkReadyEvent(): current song is not shareable, stableKey=${stableKey}`);
      return null;
    }
    if (currentTrack.stableKey !== stableKey) {
      this.report(`buildLinkReadyEvent(): current stableKey mismatch, expected=${stableKey}, actual=${currentTrack.stableKey}`);
      return null;
    }
    // The controller always publishes with its resolved urls folded in, whatever
    // the room settings say about direct links: the settings gate is applied per
    // url inside the snapshot, not here.
    const snapshot = this.currentTrackSnapshot(playback, true);
    const shareableTrack = trackAt(snapshot.tracks, snapshot.currentIndex);
    if (shareableTrack === null) {
      this.report(`buildLinkReadyEvent(): shareableTrack missing, stableKey=${stableKey}, resolvedCurrentIndex=${snapshot.currentIndex}, queueSize=${snapshot.tracks.length}`);
      return null;
    }
    if (shareableTrack.stableKey !== stableKey) {
      this.report(`buildLinkReadyEvent(): stableKey mismatch, expected=${stableKey}, actual=${shareableTrack.stableKey}, resolvedCurrentIndex=${snapshot.currentIndex}`);
      return null;
    }
    // Candidate order is the trust order: what the caller just resolved, then
    // what the player holds, then whatever survived the snapshot.
    const candidates: string[] = [];
    for (const url of streamUrlsOverride) {
      candidates.push(url);
    }
    if (streamUrlOverride !== null) {
      candidates.push(streamUrlOverride);
    }
    for (const url of playback.shareableStreamUrls) {
      candidates.push(url);
    }
    for (const url of shareableTrack.streamUrls) {
      candidates.push(url);
    }
    if (shareableTrack.streamUrl !== null) {
      candidates.push(shareableTrack.streamUrl);
    }
    const trustedTrack = listenTogetherTrackWithStreamUrls(shareableTrack, candidates);
    if (trustedTrack.streamUrls.length === 0) {
      this.report(`buildLinkReadyEvent(): direct stream urls missing, stableKey=${stableKey}, track=${shareableTrack.name}`);
      return null;
    }
    const roomState = this.roomStateProvider();
    const event = this.newEnvelope('LINK_READY');
    event.currentIndex = snapshot.currentIndex;
    event.track = trustedTrack;
    event.queue = mergeListenTogetherCurrentTrack(snapshot.tracks, snapshot.currentIndex, trustedTrack);
    event.state = resolveListenTogetherLinkReadyState(
      roomState === null ? null : roomState.playback.state,
      playback.transportActive,
      playback.isPlaying
    );
    event.positionMs = Math.max(positionMs, 0);
    event.requestTrackStableKey = stableKey;
    return event;
  }

  buildRequestSetTrackEvent(
    queue: SongItem[],
    currentIndex: number,
    positionMs: number,
    shouldPlay: boolean
  ): ListenTogetherEvent {
    const event = this.buildSetTrackEvent(queue, currentIndex, positionMs, shouldPlay);
    event.type = 'REQUEST_SET_TRACK';
    return event;
  }

  /**
   * A track ending is reported by whoever noticed, but only the controller may
   * say what plays next — a listener sends the bare fact and lets the room
   * decide, which is why every payload field but `finishedTrackStableKey` is
   * withheld for listeners.
   */
  buildTrackFinishedEvent(
    command: ListenTogetherPlaybackCommand,
    queue: SongItem[],
    currentSong: SongItem | null,
    positionMs: number
  ): ListenTogetherEvent | null {
    if (queue.length === 0 || currentSong === null) {
      return null;
    }
    const finishedTrack = songItemToListenTogetherTrackOrNull(currentSong);
    if (finishedTrack === null) {
      return null;
    }
    let proposedNextIndex: number;
    if (command.currentIndex !== null) {
      proposedNextIndex = Math.min(Math.max(command.currentIndex, 0), queue.length - 1);
    } else {
      const found = indexOfListenTogetherTrack(queue, currentSong);
      proposedNextIndex = found >= 0 ? found : 0;
    }
    if (!hasShareableListenTogetherTrackAt(queue, proposedNextIndex)) {
      return null;
    }
    const isController = this.isControllerProvider();
    // Never a resolved url: the next track has not been prepared here, so any
    // url in the queue would be stale.
    const snapshot = this.shareableSnapshot(queue, proposedNextIndex, false);
    const shouldAdvance = command.shouldPlay === true;
    const event = this.newEnvelope('TRACK_FINISHED');
    event.positionMs = Math.max(positionMs, 0);
    event.currentIndex = isController ? snapshot.currentIndex : null;
    event.nextIndex = isController ? snapshot.currentIndex : null;
    event.track = isController && shouldAdvance
      ? trackAt(snapshot.tracks, snapshot.currentIndex)
      : null;
    event.queue = isController ? snapshot.tracks : null;
    event.shouldPlay = isController ? shouldAdvance : null;
    event.finishedTrackStableKey = finishedTrack.stableKey;
    return event;
  }

  /**
   * The controller turning a listener's forwarded REQUEST_* into the committed
   * event. The payload is the request's, verbatim: the controller is granting
   * exactly what was asked for, not re-deriving it from its own player, which
   * would race the request.
   */
  buildControllerCommitEventFromForwardedRequest(
    message: ListenTogetherSocketEnvelope
  ): ListenTogetherEvent | null {
    const cause = message.causedBy;
    const requestType = cause === null ? null : cause.type;
    if (requestType === null) {
      return null;
    }
    // A type that was not a request has nothing to commit; committing it would
    // re-broadcast an already-authoritative event.
    if (!requestType.startsWith(REQUEST_TYPE_PREFIX)) {
      return null;
    }
    const commitType = requestType.substring(REQUEST_TYPE_PREFIX.length);
    const rawPositionMs = message.positionMs ?? message.expectedPositionMs ?? 0;
    const event = this.newEnvelope(commitType);
    event.positionMs = Math.max(rawPositionMs, 0);
    event.currentIndex = message.currentIndex;
    event.track = message.track;
    event.queue = message.queue;
    event.shouldPlay = message.shouldPlay;
    event.state = message.stateName;
    event.repeatMode = message.repeatMode;
    event.shuffleEnabled = message.shuffleEnabled;
    event.requestTrackStableKey = message.requestTrackStableKey;
    return event;
  }

  /**
   * The single entry point the player integration uses: a local transport action
   * in, the room event it warrants out, or null when this action is not worth
   * publishing (an unshareable track, or a command type the room has no wire
   * form for).
   */
  buildEventForPlaybackCommand(
    command: ListenTogetherPlaybackCommand
  ): ListenTogetherEvent | null {
    const playback = this.playbackSnapshotProvider();
    const commandSnapshot = resolveListenTogetherPlaybackCommandSnapshot<SongItem>(
      command.queue,
      command.positionMs,
      playback.queue,
      playback.positionMs
    );
    const queue = commandSnapshot.queue;
    const currentSong = playback.currentSong;
    let currentIndex: number;
    if (command.currentIndex !== null) {
      currentIndex = command.currentIndex;
    } else {
      const found = indexOfListenTogetherTrack(queue, currentSong);
      currentIndex = found >= 0 ? found : 0;
    }
    const positionMs = commandSnapshot.positionMs;
    const shouldPlay = resolveListenTogetherPlaybackCommandShouldPlay(
      command.type,
      command.shouldPlay,
      playback.transportActive,
      playback.isPlaying
    );
    const isController = this.isControllerProvider();
    const type = command.type;

    if (type === 'PLAY_PLAYLIST' || type === 'PLAY_FROM_QUEUE' || type === 'NEXT' || type === 'PREVIOUS') {
      if (!hasShareableListenTogetherTrackAt(queue, currentIndex)) {
        return null;
      }
      return isController
        ? this.buildSetTrackEvent(queue, currentIndex, positionMs, shouldPlay)
        : this.buildRequestSetTrackEvent(queue, currentIndex, positionMs, shouldPlay);
    }
    if (type === 'PLAY') {
      if (!isShareableForListenTogether(currentSong)) {
        return null;
      }
      return isController ? this.buildPlayEvent(positionMs) : this.buildRequestPlayEvent(positionMs);
    }
    if (type === 'PAUSE') {
      if (!isShareableForListenTogether(currentSong)) {
        return null;
      }
      return isController ? this.buildPauseEvent(positionMs) : this.buildRequestPauseEvent(positionMs);
    }
    if (type === 'PLAYBACK_MODE') {
      return this.buildPlaybackModeEvent(
        command.repeatMode ?? playback.repeatMode,
        command.shuffleEnabled ?? playback.shuffleEnabled
      );
    }
    if (type === 'TRACK_FINISHED') {
      return this.buildTrackFinishedEvent(command, queue, currentSong, positionMs);
    }
    if (type === 'SEEK') {
      if (!isShareableForListenTogether(currentSong)) {
        return null;
      }
      if (!hasShareableListenTogetherTrackAt(queue, currentIndex)) {
        return null;
      }
      // A seek re-states which track it applies to, because a seek that lands on
      // a peer after a track switch must be discardable.
      const snapshot = this.shareableSnapshot(queue, currentIndex, isController);
      const event = isController
        ? this.buildSeekEvent(positionMs)
        : this.buildRequestSeekEvent(positionMs);
      event.currentIndex = snapshot.currentIndex;
      event.track = trackAt(snapshot.tracks, snapshot.currentIndex);
      return event;
    }
    return null;
  }

  /**
   * `positionMs` is passed rather than read so PLAYBACK_MODE can reuse the same
   * snapshot it took for the position; `playback` is passed for the same reason.
   */
  private playbackSnapshotEvent(
    type: string,
    positionMs: number,
    playbackSnapshot: ListenTogetherLocalPlaybackSnapshot | null = null
  ): ListenTogetherEvent {
    const playback = playbackSnapshot ?? this.playbackSnapshotProvider();
    const snapshot = this.currentTrackSnapshot(playback, this.isControllerProvider());
    const bareType = type.startsWith(REQUEST_TYPE_PREFIX)
      ? type.substring(REQUEST_TYPE_PREFIX.length)
      : type;
    // PLAY and PAUSE state what they are asking for; everything else reports what
    // the local player is actually doing.
    let resolvedState: string;
    if (bareType === 'PLAY') {
      resolvedState = 'playing';
    } else if (bareType === 'PAUSE') {
      resolvedState = 'paused';
    } else {
      resolvedState = playback.playbackStateName;
    }
    const event = this.newEnvelope(type);
    event.positionMs = Math.max(positionMs, 0);
    event.currentIndex = snapshot.currentIndex;
    event.track = trackAt(snapshot.tracks, snapshot.currentIndex);
    event.queue = snapshot.tracks;
    event.shouldPlay = resolvedState === 'playing';
    event.state = resolvedState;
    event.repeatMode = playback.repeatMode;
    event.shuffleEnabled = playback.shuffleEnabled;
    return event;
  }

  /** The snapshot centred on whatever the local player currently has loaded. */
  private currentTrackSnapshot(
    playback: ListenTogetherLocalPlaybackSnapshot,
    includeResolvedStreamUrl: boolean
  ): ListenTogetherShareableQueueSnapshot {
    const rawIndex = indexOfListenTogetherTrack(playback.queue, playback.currentSong);
    return this.shareableSnapshot(
      playback.queue,
      rawIndex >= 0 ? rawIndex : 0,
      includeResolvedStreamUrl,
      playback
    );
  }

  private shareableSnapshot(
    queue: SongItem[],
    currentIndex: number,
    includeResolvedStreamUrl: boolean,
    playbackSnapshot: ListenTogetherLocalPlaybackSnapshot | null = null
  ): ListenTogetherShareableQueueSnapshot {
    const playback = playbackSnapshot ?? this.playbackSnapshotProvider();
    const roomState = this.roomStateProvider();
    return listenTogetherShareableQueueSnapshot(
      queue,
      currentIndex,
      playback.shareableStreamUrls,
      roomState === null ? null : roomState.settings,
      includeResolvedStreamUrl
    );
  }

  /** The four envelope fields every outbound event carries. */
  private newEnvelope(type: string): ListenTogetherEvent {
    const event = createListenTogetherEvent(type);
    event.eventId = this.eventIdFactory();
    event.clientTimeMs = this.clockMs();
    event.clientInstanceId = this.clientInstanceIdProvider();
    event.clientSequence = this.clientSequenceFactory();
    return event;
  }

  private report(message: string): void {
    const listener = this.onDiagnostic;
    if (listener !== null) {
      listener(message);
    }
  }
}

function trackAt(tracks: ListenTogetherTrack[], index: number): ListenTogetherTrack | null {
  return index >= 0 && index < tracks.length ? tracks[index] : null;
}
