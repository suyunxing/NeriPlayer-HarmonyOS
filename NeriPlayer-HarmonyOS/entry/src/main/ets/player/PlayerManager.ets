import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { QueueState } from '../model/QueueState';
import { MusicPlatform } from '../model/MusicPlatform';
import { stableKeyOf } from '../model/SongIdentity';
import { StreamResolver } from '../network/StreamResolver';
import { streamHeadersFor } from '../network/StreamHeaders';
import { BiliCookieRepository } from '../data/auth/BiliCookieRepository';
import { buildBiliCookieHeader } from '../data/auth/BiliAuth';
import { DownloadStorage } from '../download/DownloadStorage';
import { HistoryRepository } from '../data/HistoryRepository';
import { PlaybackStatsRepository } from '../data/PlaybackStatsRepository';
import { PlaybackStateRepository } from '../data/PlaybackStateRepository';
import { PersistedPlaybackState } from '../model/PersistedPlaybackState';
import { AVSessionManager, SessionControlListener } from './AVSessionManager';
import { BackgroundTaskRunner } from './BackgroundTaskRunner';
import { CoverArtColorCache } from '../view/theme/CoverArtColorCache';
import { LyricLineTracker } from '../lyrics/LyricLineTracker';
import { LyricLine } from '../model/LyricLine';
import { LocalPlaylistRepository } from '../data/LocalPlaylistRepository';
import { SettingsRepository } from '../data/SettingsRepository';
import { QueueEngine, TrackEndAction } from './queue/QueueEngine';
import { AudioInterruptPolicy, InterruptAction } from './AudioInterruptPolicy';
import { SleepTimer, SleepTimerMode } from './SleepTimer';
import { PlaybackConstants, PlaybackStatus, RepeatMode } from './PlaybackConstants';
import { effectivePlaybackRate, toPlaybackSpeedStep } from './PlaybackSpeedMap';
import {
  ListenTogetherPlaybackCommand,
  ListenTogetherPlaybackCommandSource,
  createListenTogetherPlaybackCommand
} from '../listentogether/control/ListenTogetherPlaybackCommand';
import { shouldHoldListenTogetherPlaybackForSafetyPause } from '../listentogether/playback/ListenTogetherListenerSafetyPausePolicy';

export interface PlayerListener {
  onSnapshotChanged(): void;
}

/**
 * Observes transport commands issued by the local user. Remote-sync commands
 * are filtered out before delivery (upstream `emitPlaybackCommand`), so a
 * session manager never echoes the room's own decisions back into the room.
 */
export interface PlayerCommandListener {
  onPlaybackCommand(command: ListenTogetherPlaybackCommand): void;
}

/**
 * The questions the player asks back about the listen-together session, answered
 * by the session manager once one exists (and by nobody before that). Keeping the
 * seam here avoids player -> session imports: upstream reaches the session
 * singleton directly, which this port cannot do without a dependency cycle.
 */
export interface ListenTogetherPlaybackDelegate {
  isListenTogetherActive(): boolean;
  isCurrentUserController(): boolean;
  /** Upstream `shouldUseListenTogetherListenerSafetyPause()` against live state. */
  shouldUseListenerSafetyPause(): boolean;
  /** Upstream `SessionManager.resumeListenerAfterSafetyPause()`. */
  requestListenerSafetyResume(): void;
  /** Upstream `shouldWaitForListenTogetherAuthoritativeStream(song)`. */
  shouldWaitForAuthoritativeStream(song: SongItem): boolean;
  resolveAuthoritativeStreamUrls(song: SongItem): string[];
}

class PlayerControlListener implements SessionControlListener {
  onPlay(): void {
    PlayerManager.play();
  }

  onPause(): void {
    PlayerManager.pause();
  }

  onStop(): void {
    PlayerManager.pause();
  }

  onNext(): void {
    PlayerManager.next(false);
  }

  onPrevious(): void {
    PlayerManager.previous();
  }

  onSeek(timeMs: number): void {
    PlayerManager.seekTo(timeMs);
  }

  onSpeed(speed: number): void {
    if (speed > 0) {
      PlayerManager.setSpeed(speed);
    }
  }

  onLoopMode(mode: RepeatMode): void {
    PlayerManager.setRepeatMode(mode);
  }

  onToggleFavorite(assetId: string): void {
    PlayerManager.toggleFavoriteByAssetId(assetId);
  }
}

/**
 * Playback core: queue, shuffle/repeat, stream resolution, failure recovery and
 * stats collection. Mirrors PlayerManager + AudioPlayerService in the Android app.
 */
export class PlayerManager {
  private static context: common.UIAbilityContext | null = null;
  private static player: media.AVPlayer | null = null;
  // Keeps the opened local audio file descriptor alive while AVPlayer reads it.
  private static localFile: fileIo.File | null = null;
  private static listeners: PlayerListener[] = [];
  private static queue: SongItem[] = [];
  private static engine: QueueEngine = new QueueEngine();
  private static speed: number = 1.0;
  private static status: PlaybackStatus = PlaybackStatus.IDLE;
  private static positionMs: number = 0;
  private static durationMs: number = 0;
  private static errorAttempts: number = 0;
  /**
   * Supersession token for in-flight loads: listener state application can
   * trigger several loadSong calls in quick succession (join snapshot, then
   * LINK_READY, then a heartbeat re-seek), and two chains interleaving on the
   * one AVPlayer produced 5400102 "not idle, unsupport setMediaSource" churn
   * on device. A superseded chain stops at its next await and must not retry.
   */
  private static loadGeneration: number = 0;
  private static listenedMs: number = 0;
  private static lastTimeMs: number = 0;
  private static lastPublishMs: number = 0;
  // ---- Listen-together support surface (upstream PlayerManager fields) ----
  private static commandListeners: PlayerCommandListener[] = [];
  private static listenTogetherDelegate: ListenTogetherPlaybackDelegate | null = null;
  // Listener safety pause: set when an output-device loss pauses a pinned
  // listener; playback stays down until the room's authoritative resume.
  private static safetyPausePendingResume: boolean = false;
  private static safetyResumeInFlight: boolean = false;
  // A play has been issued but may not have been observed to start yet
  // (upstream `playWhenReadyFlow`). LOADING covers the same idea for stall
  // detection, but the applier needs the intent flag separately.
  private static playWhenReady: boolean = false;
  // Soft drift correction, upstream `listenTogetherSyncPlaybackRate`. API 24
  // quantizes AVPlayer speeds to fixed steps, so sub-step rates land on 1.00x;
  // the value is still tracked so the surface (and any future finer engine
  // path) behaves like upstream.
  private static listenTogetherSyncPlaybackRate: number = 1.0;
  // The stream URL the current song was last resolved to (upstream
  // `currentMediaUrlFlow`), used to detect stale controller-shared links.
  private static currentMediaUrl: string | null = null;
  // Position restored from disk, consumed by the first play() after restore.
  private static restoredPositionMs: number = 0;
  private static persistTimer: number = -1;
  private static lastProgressPersistMs: number = 0;
  // Auto-resume intent: set when the system force-paused us transiently and
  // we were playing; cleared by permanent loss, device unplug or user pause.
  private static resumeOnFocusRegain: boolean = false;
  private static sleepTimer: SleepTimer = new SleepTimer(
    () => Date.now(),
    undefined,
    () => {
      PlayerManager.pause();
    },
    () => {
      PlayerManager.publishSleepState();
    }
  );

  static initialize(context: common.UIAbilityContext): void {
    PlayerManager.context = context;
    PlayerManager.publishDefaults();
    PlayerManager.restoreFromDisk();
    AVSessionManager.init(context, new PlayerControlListener());
    // Lyrics are fetched by the UI layer; subscribe to the shared tracker so
    // the whole-song LRC reaches AVMetadata.lyric (scrolling lyrics in the
    // media control center) without duplicating the fetch here.
    LyricLineTracker.getInstance().setLinesListener((lines: LyricLine[]) => {
      PlayerManager.publishLyrics(lines);
    });
  }

  static addListener(listener: PlayerListener): void {
    PlayerManager.listeners.push(listener);
  }

  static removeListener(listener: PlayerListener): void {
    const index = PlayerManager.listeners.indexOf(listener);
    if (index >= 0) {
      PlayerManager.listeners.splice(index, 1);
    }
  }

  // --------------------------------------------------------------------------
  // Listen-together support surface
  // --------------------------------------------------------------------------

  static addCommandListener(listener: PlayerCommandListener): void {
    PlayerManager.commandListeners.push(listener);
  }

  static removeCommandListener(listener: PlayerCommandListener): void {
    const index = PlayerManager.commandListeners.indexOf(listener);
    if (index >= 0) {
      PlayerManager.commandListeners.splice(index, 1);
    }
  }

  static setListenTogetherDelegate(delegate: ListenTogetherPlaybackDelegate | null): void {
    PlayerManager.listenTogetherDelegate = delegate;
  }

  /** Upstream `emitPlaybackCommand`: only user-initiated commands are published. */
  private static emitPlaybackCommand(command: ListenTogetherPlaybackCommand): void {
    if (command.source !== ListenTogetherPlaybackCommandSource.LOCAL) {
      return;
    }
    for (const listener of PlayerManager.commandListeners) {
      listener.onPlaybackCommand(command);
    }
  }

  private static localCommand(type: string): ListenTogetherPlaybackCommand {
    return createListenTogetherPlaybackCommand(
      type,
      ListenTogetherPlaybackCommandSource.LOCAL,
      Date.now()
    );
  }

  /**
   * Upstream `playImpl`'s first gate: while a safety resume is pending, a local
   * play is consumed as the request to resume instead of starting playback.
   */
  private static consumeLocalPlayForSafetyResume(source: ListenTogetherPlaybackCommandSource): boolean {
    if (source !== ListenTogetherPlaybackCommandSource.LOCAL ||
      PlayerManager.listenTogetherDelegate === null) {
      return false;
    }
    if (!PlayerManager.requestListenTogetherSafetyPauseResume()) {
      return false;
    }
    Logger.info('PlayerManager local play consumed by listen-together safety resume');
    return true;
  }

  static markListenTogetherSafetyPausePendingResume(): void {
    PlayerManager.safetyPausePendingResume = true;
    PlayerManager.safetyResumeInFlight = false;
  }

  static shouldHoldListenTogetherPlaybackForSafetyPause(causeType: string | null): boolean {
    return shouldHoldListenTogetherPlaybackForSafetyPause(
      PlayerManager.safetyPausePendingResume,
      causeType
    );
  }

  static clearListenTogetherSafetyPause(): void {
    PlayerManager.safetyPausePendingResume = false;
    PlayerManager.safetyResumeInFlight = false;
  }

  /** Keeps the pending flag so the next local play can retry the resume. */
  static retryListenTogetherSafetyPauseResume(): void {
    PlayerManager.safetyResumeInFlight = false;
  }

  static completeListenTogetherSafetyPauseResume(): void {
    PlayerManager.safetyPausePendingResume = false;
    PlayerManager.safetyResumeInFlight = false;
  }

  /**
   * Upstream `requestListenTogetherSafetyPauseResume`: true when the caller must
   * not start playback because the resume handshake took over.
   */
  static requestListenTogetherSafetyPauseResume(): boolean {
    if (!PlayerManager.safetyPausePendingResume) {
      return false;
    }
    const delegate = PlayerManager.listenTogetherDelegate;
    const active = delegate !== null && delegate.isListenTogetherActive();
    const controller = delegate !== null && delegate.isCurrentUserController();
    if (!active || controller) {
      PlayerManager.clearListenTogetherSafetyPause();
      return false;
    }
    if (PlayerManager.safetyResumeInFlight) {
      return true;
    }
    PlayerManager.safetyResumeInFlight = true;
    if (delegate !== null) {
      delegate.requestListenerSafetyResume();
    }
    return true;
  }

  /** Upstream `setListenTogetherSyncPlaybackRate`, clamped to [0.95, 1.05]. */
  static setListenTogetherSyncPlaybackRate(rate: number): void {
    const resolved = Math.min(1.05, Math.max(0.95, rate));
    if (Math.abs(PlayerManager.listenTogetherSyncPlaybackRate - resolved) < 0.001) {
      return;
    }
    PlayerManager.listenTogetherSyncPlaybackRate = resolved;
    PlayerManager.applyEffectiveSpeed();
  }

  static resetListenTogetherSyncPlaybackRate(): void {
    PlayerManager.setListenTogetherSyncPlaybackRate(1.0);
  }

  static getListenTogetherSyncPlaybackRate(): number {
    return PlayerManager.listenTogetherSyncPlaybackRate;
  }

  /** Applies speed * sync rate to the engine; API 24 quantizes to fixed steps. */
  private static applyEffectiveSpeed(): void {
    if (PlayerManager.player === null) {
      return;
    }
    try {
      PlayerManager.player.setSpeed(
        PlayerManager.toPlaybackSpeed(PlayerManager.speed * PlayerManager.listenTogetherSyncPlaybackRate)
      );
      // Like a seek, this moves the extrapolation baseline's slope without
      // changing `status`, so the session needs the new rate pushed to it.
      PlayerManager.publishSessionPlaybackState();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`applyEffectiveSpeed failed: ${e.message}`);
    }
  }

  /**
   * Upstream `applyListenTogetherPlaybackModeImpl`: applies only the parts the
   * room actually specifies, persists like the user-facing setters, and never
   * publishes a PLAYBACK_MODE command (the room already knows).
   */
  static applyListenTogetherPlaybackMode(repeatMode: number | null, shuffleEnabled: boolean | null): void {
    let normalizedRepeatMode: RepeatMode | null = null;
    if (repeatMode !== null) {
      normalizedRepeatMode =
        repeatMode === RepeatMode.OFF || repeatMode === RepeatMode.ONE || repeatMode === RepeatMode.ALL
          ? repeatMode as RepeatMode
          : RepeatMode.OFF;
    }
    if (normalizedRepeatMode !== null && normalizedRepeatMode !== PlayerManager.engine.repeatMode) {
      PlayerManager.engine.setRepeatMode(normalizedRepeatMode);
      AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, normalizedRepeatMode);
      PlayerManager.schedulePersist(0);
      PlayerManager.notify();
    }
    if (shuffleEnabled !== null && shuffleEnabled !== PlayerManager.engine.shuffle) {
      PlayerManager.engine.setShuffle(shuffleEnabled);
      PlayerManager.publishQueue();
    }
  }

  static shouldWaitForListenTogetherAuthoritativeStream(song: SongItem): boolean {
    const delegate = PlayerManager.listenTogetherDelegate;
    return delegate !== null && delegate.shouldWaitForAuthoritativeStream(song);
  }

  /** Upstream `isTransportActive()` mapped onto this port's state model. */
  static isTransportActive(): boolean {
    return PlayerManager.getCurrentSong() !== null &&
      (PlayerManager.playWhenReady ||
        PlayerManager.status === PlaybackStatus.PLAYING ||
        PlayerManager.status === PlaybackStatus.LOADING);
  }

  static isPlayWhenReady(): boolean {
    return PlayerManager.playWhenReady;
  }

  static getCurrentMediaUrl(): string | null {
    return PlayerManager.currentMediaUrl;
  }

  static getShareableListenTogetherStreamUrls(): string[] {
    const url = (PlayerManager.currentMediaUrl ?? '').trim();
    if (url.length === 0) {
      return [];
    }
    const lowered = url.toLowerCase();
    return lowered.startsWith('http://') || lowered.startsWith('https://') ? [url] : [];
  }

  static async resolveShareableListenTogetherStreamUrls(song: SongItem): Promise<string[]> {
    const current = PlayerManager.getCurrentSong();
    if (current !== null && stableKeyOf(current) === stableKeyOf(song)) {
      const currentUrls = PlayerManager.getShareableListenTogetherStreamUrls();
      if (currentUrls.length > 0) {
        return currentUrls;
      }
    }
    const resolved = await PlayerManager.resolveStreamUrl(song);
    const lowered = resolved.trim().toLowerCase();
    return lowered.startsWith('http://') || lowered.startsWith('https://') ? [resolved.trim()] : [];
  }

  private static setCurrentMediaUrl(url: string | null): void {
    PlayerManager.currentMediaUrl = url;
  }

  static getCurrentSong(): SongItem | null {
    const queueIndex = PlayerManager.engine.getCurrentQueueIndex();
    if (queueIndex < 0 || queueIndex >= PlayerManager.queue.length) {
      return null;
    }
    return PlayerManager.queue[queueIndex];
  }

  static getQueue(): SongItem[] {
    return PlayerManager.queue;
  }

  /**
   * Applies user-edited metadata (custom name/artist/cover) to the queue
   * entries with the same stable key and republishes the current song, so
   * every surface reflects the edit immediately. Playback state is untouched.
   */
  static applySongMetadataUpdate(song: SongItem): void {
    const key = stableKeyOf(song);
    for (let index = 0; index < PlayerManager.queue.length; index++) {
      if (stableKeyOf(PlayerManager.queue[index]) === key) {
        PlayerManager.queue[index] = song;
      }
    }
    PlayerManager.publishQueue();
    const current = PlayerManager.getCurrentSong();
    if (current !== null && stableKeyOf(current) === key) {
      PlayerManager.publishCurrentSong(song);
      PlayerManager.refreshSessionMetadata(song);
    }
  }

  private static refreshSessionMetadata(song: SongItem): void {
    AVSessionManager.updateMetadata(song, PlayerManager.durationMs).catch((error: Error) => {
      Logger.warn(`refreshSessionMetadata failed: ${error.message}`);
    });
  }

  static getStatus(): PlaybackStatus {
    return PlayerManager.status;
  }

  static getRepeatMode(): RepeatMode {
    return PlayerManager.engine.repeatMode;
  }

  static isShuffleEnabled(): boolean {
    return PlayerManager.engine.shuffle;
  }

  static async playPlaylist(
    songs: SongItem[],
    startIndex: number,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    if (songs.length === 0) {
      return;
    }
    PlayerManager.queue = songs.slice();
    PlayerManager.engine.setQueueSize(songs.length);
    PlayerManager.engine.start(startIndex, PlayerManager.engine.shuffle, PlayerManager.engine.repeatMode);
    PlayerManager.publishQueue();
    PlayerManager.playWhenReady = true;
    const command = createListenTogetherPlaybackCommand('PLAY_PLAYLIST', source, Date.now());
    command.queue = songs.slice();
    command.currentIndex = startIndex;
    command.shouldPlay = true;
    PlayerManager.emitPlaybackCommand(command);
    await PlayerManager.loadSong();
  }

  static async play(
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    if (PlayerManager.consumeLocalPlayForSafetyResume(source)) {
      return;
    }
    PlayerManager.playWhenReady = true;
    const command = createListenTogetherPlaybackCommand('PLAY', source, Date.now());
    command.positionMs = Math.max(0, PlayerManager.positionMs);
    PlayerManager.emitPlaybackCommand(command);
    const player = PlayerManager.player;
    if (player !== null && PlayerManager.status === PlaybackStatus.PAUSED) {
      try {
        await player.play();
        // Publish immediately so the UI toggles without waiting for the
        // async AVPlayer stateChange event (which may lag on some streams).
        PlayerManager.publishStatus(PlaybackStatus.PLAYING);
        return;
      } catch (error) {
        const e = error as Error;
        Logger.warn(`PlayerManager.play failed: ${e.message}`);
      }
    }
    if (PlayerManager.getCurrentSong() === null) {
      if (PlayerManager.queue.length > 0) {
        PlayerManager.engine.playAt(0);
        await PlayerManager.loadSong();
      }
      return;
    }
    if (PlayerManager.player === null) {
      // Queue restored from disk but not loaded into AVPlayer yet: resume
      // from the persisted position.
      const resumeMs = PlayerManager.restoredPositionMs;
      await PlayerManager.loadSong(resumeMs);
      return;
    }
    if (PlayerManager.status === PlaybackStatus.COMPLETED) {
      await PlayerManager.seekTo(0, source);
      await PlayerManager.resumeIfPrepared();
    }
  }

  static async pause(
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    // User-facing pause cancels any pending auto-resume intent.
    PlayerManager.resumeOnFocusRegain = false;
    PlayerManager.playWhenReady = false;
    const command = createListenTogetherPlaybackCommand('PAUSE', source, Date.now());
    command.positionMs = Math.max(0, PlayerManager.positionMs);
    PlayerManager.emitPlaybackCommand(command);
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      await player.pause();
      // Publish immediately (see play()); the AVPlayer stateChange event
      // re-confirms the same value later.
      PlayerManager.publishStatus(PlaybackStatus.PAUSED);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlayerManager.pause failed: ${e.message}`);
    }
  }

  static async togglePlayPause(): Promise<void> {
    if (PlayerManager.status === PlaybackStatus.PLAYING) {
      await PlayerManager.pause();
    } else {
      await PlayerManager.play();
    }
  }

  static async next(
    auto: boolean = false,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    // Force (wrap/rebuild) is only legitimate under repeat-all or explicit
    // skip-after-failure, mirroring Android nextImpl(force).
    const force = auto && PlayerManager.engine.repeatMode === RepeatMode.ALL;
    const target = PlayerManager.engine.next(force);
    if (target < 0) {
      if (!auto) {
        await PlayerManager.pause(source);
      }
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      return;
    }
    PlayerManager.playWhenReady = true;
    const command = createListenTogetherPlaybackCommand('NEXT', source, Date.now());
    command.positionMs = Math.max(0, PlayerManager.positionMs);
    PlayerManager.emitPlaybackCommand(command);
    await PlayerManager.loadSong();
  }

  static async previous(
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    const target = PlayerManager.engine.previous();
    if (target < 0) {
      return;
    }
    PlayerManager.playWhenReady = true;
    const command = createListenTogetherPlaybackCommand('PREVIOUS', source, Date.now());
    command.positionMs = Math.max(0, PlayerManager.positionMs);
    PlayerManager.emitPlaybackCommand(command);
    await PlayerManager.loadSong();
  }

  /**
   * Jumps to a specific queue position (used by the queue sheet).
   */
  static async playAt(
    queueIndex: number,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    PlayerManager.engine.playAt(queueIndex);
    PlayerManager.playWhenReady = true;
    const command = createListenTogetherPlaybackCommand('PLAY_FROM_QUEUE', source, Date.now());
    command.currentIndex = queueIndex;
    PlayerManager.emitPlaybackCommand(command);
    await PlayerManager.loadSong();
  }

  static getCurrentQueueIndex(): number {
    return PlayerManager.engine.getCurrentQueueIndex();
  }

  static async seekTo(
    timeMs: number,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    const command = createListenTogetherPlaybackCommand('SEEK', source, Date.now());
    command.positionMs = Math.max(0, timeMs);
    PlayerManager.emitPlaybackCommand(command);
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      await player.seek(Math.max(0, timeMs), media.SeekMode.SEEK_PREV_SYNC);
      // A seek moves the extrapolation baseline while `status` is unchanged,
      // so nothing else would push it to the session and the control center
      // would keep counting from the pre-seek datum until the next play/pause.
      PlayerManager.positionMs = Math.max(0, timeMs);
      // Rebase the listened-time accumulator too: onTimeUpdate credits
      // `timeMs - lastTimeMs` to listenedMs, so a forward seek would otherwise
      // bank the skipped span as if it had been played.
      PlayerManager.lastTimeMs = PlayerManager.positionMs;
      PlayerManager.publishSessionPlaybackState();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlayerManager.seekTo failed: ${e.message}`);
    }
  }

  static setShuffle(
    enabled: boolean,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): void {
    PlayerManager.engine.setShuffle(enabled);
    PlayerManager.publishQueue();
    const command = createListenTogetherPlaybackCommand('PLAYBACK_MODE', source, Date.now());
    command.repeatMode = PlayerManager.engine.repeatMode;
    command.shuffleEnabled = enabled;
    PlayerManager.emitPlaybackCommand(command);
  }

  static setRepeatMode(mode: RepeatMode): void {
    PlayerManager.engine.setRepeatMode(mode);
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, mode);
    PlayerManager.schedulePersist(0);
    PlayerManager.notify();
    const command = PlayerManager.localCommand('PLAYBACK_MODE');
    command.repeatMode = mode;
    command.shuffleEnabled = PlayerManager.engine.shuffle;
    PlayerManager.emitPlaybackCommand(command);
  }

  /** Android order: OFF -> ALL -> ONE. */
  static cycleRepeatMode(
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): RepeatMode {
    const mode = PlayerManager.engine.cycleRepeatMode();
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, mode);
    PlayerManager.schedulePersist(0);
    PlayerManager.notify();
    const command = createListenTogetherPlaybackCommand('PLAYBACK_MODE', source, Date.now());
    command.repeatMode = mode;
    command.shuffleEnabled = PlayerManager.engine.shuffle;
    PlayerManager.emitPlaybackCommand(command);
    return mode;
  }

  static setSpeed(speed: number): void {
    PlayerManager.speed = speed;
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, speed);
    PlayerManager.schedulePersist(0);
    PlayerManager.applyEffectiveSpeed();
  }

  // --------------------------------------------------------------------------
  // Sleep timer
  // --------------------------------------------------------------------------

  static setSleepCountdown(minutes: number, finishCurrentOnExpiry: boolean = false): void {
    PlayerManager.sleepTimer.startCountdown(minutes, finishCurrentOnExpiry);
  }

  static setSleepFinishCurrent(): void {
    PlayerManager.sleepTimer.startFinishCurrent();
  }

  static setSleepFinishPlaylist(): void {
    PlayerManager.sleepTimer.startFinishPlaylist();
  }

  static cancelSleepTimer(): void {
    PlayerManager.sleepTimer.cancel();
    PlayerManager.publishSleepState();
  }

  static isSleepTimerActive(): boolean {
    return PlayerManager.sleepTimer.getState().isActive;
  }

  private static publishSleepState(): void {
    const state = PlayerManager.sleepTimer.getState();
    AppStorage.setOrCreate(PlaybackConstants.KEY_SLEEP_ACTIVE, state.isActive);
    const remainingMin = state.isActive && state.mode === SleepTimerMode.COUNTDOWN
      ? Math.max(1, Math.ceil(state.remainingMs / 60000))
      : 0;
    AppStorage.setOrCreate(PlaybackConstants.KEY_SLEEP_REMAINING_MIN, remainingMin);
  }

  static getPositionMs(): number {
    return PlayerManager.positionMs;
  }

  static getDurationMs(): number {
    return PlayerManager.durationMs;
  }

  static flushPlaybackStatsAsync(): void {
    const song = PlayerManager.getCurrentSong();
    if (song === null || PlayerManager.listenedMs <= 0) {
      return;
    }
    const key = stableKeyOf(song);
    const listenMs = PlayerManager.listenedMs;
    PlayerManager.listenedMs = 0;
    PlaybackStatsRepository.recordPlay(key, listenMs);
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  private static publishDefaults(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_CURRENT_SONG, '');
    AppStorage.setOrCreate(PlaybackConstants.KEY_STATUS, PlaybackStatus.IDLE);
    AppStorage.setOrCreate(PlaybackConstants.KEY_POSITION_MS, 0);
    AppStorage.setOrCreate(PlaybackConstants.KEY_DURATION_MS, 0);
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_INDEX, -1);
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, PlayerManager.engine.repeatMode);
    AppStorage.setOrCreate(PlaybackConstants.KEY_SHUFFLE, PlayerManager.engine.shuffle);
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, PlayerManager.speed);
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_JSON, '');
    AppStorage.setOrCreate(PlaybackConstants.KEY_FAVORITE, false);
  }

  /**
   * Restores the persisted session from preferences. Mirrors the Android
   * applyRestoredStateSnapshot: only fills in-memory state (queue, modes,
   * position) and stays paused; actual playback resumes when the user
   * presses play, continuing from the restored position.
   */
  private static async restoreFromDisk(): Promise<void> {
    const state = await PlaybackStateRepository.load();
    if (state === null) {
      return;
    }
    PlayerManager.applyRestoredState(state);
  }

  static applyRestoredState(state: PersistedPlaybackState): void {
    if (state.songs.length === 0) {
      return;
    }
    PlayerManager.queue = state.songs;
    PlayerManager.speed = state.speed;
    PlayerManager.positionMs = state.positionMs;
    PlayerManager.restoredPositionMs = state.positionMs;
    const startQueueIndex = Math.min(state.queueIndex, state.songs.length - 1);
    // Mirrors Android applyRestoredStateSnapshot: shuffle restarts from a
    // fresh bag around the restored track; history/future are not persisted.
    PlayerManager.engine.setQueueSize(state.songs.length);
    PlayerManager.engine.start(startQueueIndex, state.shuffle, state.repeatMode);
    PlayerManager.publishQueue();
    PlayerManager.publishPosition();
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, PlayerManager.speed);
    PlayerManager.publishStatus(PlaybackStatus.PAUSED);
    const song = PlayerManager.getCurrentSong();
    if (song !== null) {
      PlayerManager.publishCurrentSong(song);
    }
    Logger.info(`PlayerManager restored queue: ${state.songs.length} songs at index ${state.queueIndex}`);
  }

  private static async loadSong(startPositionMs: number = 0, isRetry: boolean = false): Promise<void> {
    const generation = ++PlayerManager.loadGeneration;
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    // A retry must not reset the attempt budget: with the reset here the
    // counter never passed 1 and handleLoadFailure retried without a cap,
    // flooding the stream API fast enough to trip platform risk control.
    if (!isRetry) {
      PlayerManager.errorAttempts = 0;
    }
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.positionMs = startPositionMs;
    PlayerManager.restoredPositionMs = 0;
    PlayerManager.durationMs = song.durationMs;
    PlayerManager.lastTimeMs = 0;
    PlayerManager.setCurrentMediaUrl(null);
    // Before any publish* call: it resets the session's lyric caches and its
    // duration, so a publishDuration triggered by the new length cannot push
    // the previous song's lyrics alongside the new title.
    AVSessionManager.updateMetadata(song, PlayerManager.durationMs);
    PlayerManager.publishCurrentSong(song);
    PlayerManager.publishPosition();
    PlayerManager.publishDuration();
    PlayerManager.publishQueue();
    PlayerManager.publishStatus(PlaybackStatus.LOADING);
    HistoryRepository.addSong(song);

    try {
      const player = await PlayerManager.ensurePlayer();
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
      const uri = await PlayerManager.resolveStreamUrl(song);
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
      if (uri.length === 0) {
        throw new Error(`No playable stream for ${song.displayName}`);
      }
      PlayerManager.setCurrentMediaUrl(uri);
      await player.reset();
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
      // Bilibili CDN hosts require a web Referer + desktop UA (plus the login
      // cookie when present) or the player's own fetch is rejected with 403.
      const biliCookie = BiliCookieRepository.isLoggedIn()
        ? buildBiliCookieHeader(BiliCookieRepository.getCookies())
        : '';
      const headers = streamHeadersFor(uri, biliCookie);
      const source = Object.keys(headers).length > 0
        ? media.createMediaSourceWithUrl(uri, headers)
        : media.createMediaSourceWithUrl(uri);
      await player.setMediaSource(source);
      await PlayerManager.waitForState(['initialized']);
      // Pin the stream to the music usage. This is the only window the SDK
      // accepts it in: the initialized state, before the first prepare().
      //
      // It is not a bug fix — AVPlayer already defaults to
      // STREAM_USAGE_MUSIC for a source with no video track, which is every
      // source we feed it today (Bilibili resolves to the DASH audio-only
      // baseUrl, the rest are plain audio URLs). It flips to
      // STREAM_USAGE_MOVIE only when the container carries video, which
      // prepare() decides by probing and we cannot see beforehand. Declaring
      // it keeps the system's audio policy — volume curve, focus arbitration,
      // low-power offload — on the music path no matter what a future source
      // resolves to, and satisfies the usage precondition of setLoudnessGain().
      try {
        const rendererInfo: audio.AudioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          // Reserved by the SDK; 0 is the documented default.
          rendererFlags: 0,
        };
        player.audioRendererInfo = rendererInfo;
      } catch (error) {
        const e = error as BusinessError;
        Logger.warn(`setAudioRendererInfo failed: ${e.code} ${e.message}`);
      }
      await player.prepare();
      await PlayerManager.waitForState(['prepared']);
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
      // Shared focus mode keeps a single focus owner inside this app; must be
      // set between prepare and the first play of each source.
      player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
      try {
        const duration = player.duration;
        if (duration > 0) {
          PlayerManager.durationMs = duration;
          PlayerManager.publishDuration();
        }
      } catch (error) {
        const e = error as Error;
        Logger.debug(`getAVPlayerDuration failed: ${e.message}`);
      }
      try {
        player.setSpeed(
          PlayerManager.toPlaybackSpeed(PlayerManager.speed * PlayerManager.listenTogetherSyncPlaybackRate)
        );
      } catch (error) {
        const e = error as Error;
        Logger.debug(`setPlaybackSpeed failed: ${e.message}`);
      }
      if (startPositionMs > 0) {
        try {
          // AVPlayer.seek has no promise overload on API 24; AVPlayer applies
          // the pending seek before playback starts.
          player.seek(startPositionMs, media.SeekMode.SEEK_PREV_SYNC);
        } catch (error) {
          const e = error as Error;
          Logger.warn(`seek to restored position failed: ${e.message}`);
        }
      }
      await player.play();
      Logger.info(`PlayerManager playback started: ${song.displayName}`);
    } catch (error) {
      const e = error as Error;
      if (generation !== PlayerManager.loadGeneration) {
        // A newer load superseded this chain; its own outcome wins.
        Logger.debug(`loadSong superseded for ${song.displayName}: ${e.message}`);
        return;
      }
      Logger.error(`PlayerManager.loadSong failed for ${song.displayName}: ${e.message}`);
      await PlayerManager.handleLoadFailure();
    }
  }

  private static async resolveStreamUrl(song: SongItem): Promise<string> {
    if (song.platform !== MusicPlatform.LOCAL) {
      // A completed download short-circuits network resolution so catalog
      // tracks stay playable offline (Android offline-first semantics).
      const downloaded = await DownloadStorage.findCatalogEntry(song);
      if (downloaded !== null) {
        const localUrl = PlayerManager.openLocalFd(downloaded.audioPath);
        if (localUrl.length > 0) {
          return localUrl;
        }
      }
      // A listener may consume the controller's already-resolved stream after
      // the offline catalog has had a chance to satisfy the request.
      const authoritativeUrls = PlayerManager.listenTogetherDelegate?.resolveAuthoritativeStreamUrls(song) ?? [];
      if (authoritativeUrls.length > 0) {
        return authoritativeUrls[0];
      }
      // NetEase songs fall back to a matched Bilibili source when the direct
      // stream is unavailable and the setting is on.
      return StreamResolver.resolveWithNeteaseAutoFallback(song);
    }
    const uri = song.localFilePath.length > 0 ? song.localFilePath : song.mediaUri;
    return PlayerManager.openLocalFd(uri);
  }

  /** Opens a sandbox audio file for AVPlayer; '' when unreadable. */
  private static openLocalFd(uri: string): string {
    if (uri.length === 0) {
      return '';
    }
    try {
      PlayerManager.closeLocalFile();
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      PlayerManager.localFile = file;
      return `fd://${file.fd}`;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`open local audio fd failed: ${e.message}`);
      return '';
    }
  }

  private static closeLocalFile(): void {
    if (PlayerManager.localFile !== null) {
      try {
        fileIo.closeSync(PlayerManager.localFile);
      } catch (error) {
        const e = error as Error;
        Logger.debug(`close local file failed: ${e.message}`);
      }
      PlayerManager.localFile = null;
    }
  }

  private static async handleLoadFailure(): Promise<void> {
    PlayerManager.errorAttempts += 1;
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    if (PlayerManager.errorAttempts < 2) {
      Logger.warn(`Retrying playback for ${song.displayName} (attempt ${PlayerManager.errorAttempts})`);
      await PlayerManager.loadSong(0, true);
      return;
    }
    Logger.warn(`Giving up on ${song.displayName}, skipping to next`);
    await PlayerManager.next(true);
  }

  private static async ensurePlayer(): Promise<media.AVPlayer> {
    try {
      if (PlayerManager.player !== null) {
        return PlayerManager.player;
      }
      const player = await media.createAVPlayer();
      PlayerManager.player = player;
      player.on('stateChange', (state: string) => PlayerManager.onPlayerStateChange(state));
      player.on('durationUpdate', (durationMs: number) => {
        if (durationMs > 0) {
          PlayerManager.durationMs = durationMs;
          PlayerManager.publishDuration();
        }
      });
      player.on('timeUpdate', (timeMs: number) => PlayerManager.onTimeUpdate(timeMs));
      player.on('error', (error: BusinessError) => PlayerManager.onPlayerError(error));
      player.on('audioInterrupt', (event: audio.InterruptEvent) => PlayerManager.onAudioInterrupt(event));
      player.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo) => {
        PlayerManager.onOutputDeviceChange(info);
      });
      return player;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlayerManager.ensurePlayer failed: ${e.message}`);
      throw e;
    }
  }

  /**
   * Maps a numeric playback speed to the media.PlaybackSpeed enum (API 24).
   * The quantization itself lives in PlaybackSpeedMap so it can be unit-tested
   * together with its inverse; this only re-types the step.
   */
  private static toPlaybackSpeed(speed: number): media.PlaybackSpeed {
    return toPlaybackSpeedStep(speed) as media.PlaybackSpeed;
  }

  private static onPlayerStateChange(state: string): void {
    Logger.debug(`AVPlayer state: ${state}`);
    PlayerManager.notifyStateWaiters(state);
    switch (state) {
      case 'playing':
        PlayerManager.publishStatus(PlaybackStatus.PLAYING);
        if (PlayerManager.context !== null) {
          BackgroundTaskRunner.start(PlayerManager.context);
        }
        break;
      case 'paused':
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.schedulePersist(0);
        if (PlayerManager.context !== null) {
          BackgroundTaskRunner.stop(PlayerManager.context);
        }
        break;
      case 'completed':
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.handleCompletion();
        break;
      case 'error':
        // The 'error' event carries the detail; state change to 'error' is a fallback.
        break;
      default:
        break;
    }
  }

  private static async handleCompletion(): Promise<void> {
    // Sleep timer arbitration runs before repeat/advance decisions so that
    // repeat-one/all can never prevent a scheduled stop (Android parity).
    if (PlayerManager.sleepTimer.shouldStopOnTrackEnd(PlayerManager.engine.isLastInPlaylist())) {
      PlayerManager.sleepTimer.cancel();
      PlayerManager.publishSleepState();
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      PlayerManager.playWhenReady = false;
      PlayerManager.persistNow();
      return;
    }
    // Natural track end is a local playback fact the session must forward
    // (upstream emits TRACK_FINISHED from handleTrackEnded). Emitted for every
    // non-sleep-stopped completion, including repeat-one replays: the room
    // decides what "next" means, the local repeat decision stays independent.
    const finishedCommand = PlayerManager.localCommand('TRACK_FINISHED');
    finishedCommand.queue = PlayerManager.queue.slice();
    finishedCommand.currentIndex = PlayerManager.engine.getCurrentQueueIndex();
    finishedCommand.positionMs = Math.max(0, PlayerManager.durationMs);
    PlayerManager.emitPlaybackCommand(finishedCommand);
    const action = PlayerManager.engine.onTrackEnded();
    if (action === TrackEndAction.REPLAY) {
      const player = PlayerManager.player;
      if (player !== null) {
        try {
          await player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
          await player.play();
          return;
        } catch (error) {
          const e = error as Error;
          Logger.warn(`repeat-one restart failed: ${e.message}`);
        }
      }
      await PlayerManager.next(true);
      return;
    }
    if (action === TrackEndAction.ADVANCE) {
      await PlayerManager.next(true);
      return;
    }
    PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
  }

  private static onTimeUpdate(timeMs: number): void {
    if (PlayerManager.status === PlaybackStatus.PLAYING) {
      const delta = Math.max(0, timeMs - PlayerManager.lastTimeMs);
      PlayerManager.listenedMs += delta;
    }
    PlayerManager.lastTimeMs = timeMs;
    PlayerManager.positionMs = timeMs;
    const now = Date.now();
    if (now - PlayerManager.lastPublishMs > 500) {
      PlayerManager.lastPublishMs = now;
      PlayerManager.publishPosition();
    }
    if (now - PlayerManager.lastProgressPersistMs > 15000) {
      PlayerManager.lastProgressPersistMs = now;
      PlayerManager.schedulePersist(250);
    }
  }

  private static onPlayerError(error: BusinessError): void {
    Logger.error(`AVPlayer error: code=${error.code} message=${error.message}`);
    PlayerManager.publishStatus(PlaybackStatus.ERROR);
    PlayerManager.rejectStateWaiters(error.message);
    PlayerManager.handleLoadFailure();
  }

  /**
   * Audio focus arbitration: transient loss pauses with a resume intent,
   * permanent loss or device unplug pauses without one, and a resume hint
   * continues playback only when that intent exists. Ducking is handled by
   * the system itself.
   */
  private static onAudioInterrupt(event: audio.InterruptEvent): void {
    const wasPlaying = PlayerManager.status === PlaybackStatus.PLAYING;
    const action = AudioInterruptPolicy.decide(
      event.hintType,
      event.forceType,
      wasPlaying,
      PlayerManager.resumeOnFocusRegain
    );
    PlayerManager.applyInterruptAction(action);
  }

  private static onOutputDeviceChange(info: audio.AudioStreamDeviceChangeInfo): void {
    const action = AudioInterruptPolicy.decideForDeviceChange(info.changeReason);
    // Upstream `pauseForAudioRouteLoss`: a pinned listener losing its output
    // device arms the safety pause instead of the ordinary auto-resume intent,
    // because resuming locally would desync the room.
    if (action === InterruptAction.PAUSE_PERMANENT &&
      PlayerManager.listenTogetherDelegate !== null &&
      PlayerManager.listenTogetherDelegate.shouldUseListenerSafetyPause()) {
      PlayerManager.markListenTogetherSafetyPausePendingResume();
    }
    PlayerManager.applyInterruptAction(action);
  }

  private static applyInterruptAction(action: InterruptAction): void {
    const player = PlayerManager.player;
    switch (action) {
      case InterruptAction.PAUSE_TRANSIENT:
        PlayerManager.resumeOnFocusRegain = true;
        PlayerManager.playWhenReady = false;
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        break;
      case InterruptAction.PAUSE_PERMANENT:
        PlayerManager.resumeOnFocusRegain = false;
        PlayerManager.playWhenReady = false;
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.persistNow();
        break;
      case InterruptAction.RESUME:
        PlayerManager.resumeOnFocusRegain = false;
        PlayerManager.playWhenReady = true;
        if (player !== null && PlayerManager.status === PlaybackStatus.PAUSED) {
          player.play().catch((error: Object) => {
            const e = error as Error;
            Logger.warn(`resume after focus regain failed: ${e.message}`);
          });
        }
        break;
      default:
        break;
    }
  }

  private static waitingStates: string[] = [];
  private static waitingResolve: (() => void) | null = null;
  private static waitingReject: ((reason: Error) => void) | null = null;
  private static waitingTimer: number = -1;

  private static waitForState(targets: string[], timeoutMs: number = 20000): Promise<void> {
    const player = PlayerManager.player;
    if (player !== null) {
      try {
        const current = player.state;
        if (current !== undefined && targets.indexOf(current) >= 0) {
          return Promise.resolve();
        }
      } catch (error) {
        const e = error as Error;
        Logger.debug(`read current AVPlayer state failed: ${e.message}`);
      }
    }
    return new Promise<void>((resolve, reject) => {
      PlayerManager.waitingStates = targets;
      PlayerManager.waitingResolve = resolve;
      PlayerManager.waitingReject = reject;
      PlayerManager.waitingTimer = setTimeout(() => {
        PlayerManager.waitingStates = [];
        PlayerManager.waitingResolve = null;
        PlayerManager.waitingReject = null;
        reject(new Error(`state wait timeout (${targets.join(',')})`));
      }, timeoutMs);
    });
  }

  private static notifyStateWaiters(state: string): void {
    if (PlayerManager.waitingResolve === null) {
      return;
    }
    if (PlayerManager.waitingStates.indexOf(state) >= 0) {
      const resolve = PlayerManager.waitingResolve;
      PlayerManager.clearStateWait();
      resolve();
    }
  }

  private static rejectStateWaiters(message: string): void {
    if (PlayerManager.waitingReject === null) {
      return;
    }
    const reject = PlayerManager.waitingReject;
    PlayerManager.clearStateWait();
    reject(new Error(message));
  }

  private static clearStateWait(): void {
    if (PlayerManager.waitingTimer >= 0) {
      clearTimeout(PlayerManager.waitingTimer);
      PlayerManager.waitingTimer = -1;
    }
    PlayerManager.waitingStates = [];
    PlayerManager.waitingResolve = null;
    PlayerManager.waitingReject = null;
  }

  private static async resumeIfPrepared(): Promise<void> {
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      await player.play();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`resumeIfPrepared failed: ${e.message}`);
    }
  }

  private static publishCurrentSong(song: SongItem): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_CURRENT_SONG, song.toJson());
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_INDEX, PlayerManager.engine.getCurrentQueueIndex());
    CoverArtColorCache.onSongChanged(song.effectiveCoverUrl);
    PlayerManager.publishFavorite(song);
    PlayerManager.notify();
  }

  private static publishStatus(status: PlaybackStatus): void {
    PlayerManager.status = status;
    AppStorage.setOrCreate(PlaybackConstants.KEY_STATUS, status);
    PlayerManager.publishSessionPlaybackState();
    if (status !== PlaybackStatus.PLAYING && status !== PlaybackStatus.LOADING) {
      PlayerManager.restoreLyricMetadata();
    }
    PlayerManager.notify();
  }

  /**
   * Re-sends AVPlaybackState without touching the in-app feed.
   *
   * The system does not poll us: it extrapolates the control center's (and the
   * desktop lyric window's) progress from `position.elapsedTime` +
   * `updateTime` + `speed`. So a fresh datum is needed exactly when that
   * baseline moves, and never on a timer — which is why the 500ms
   * `publishPosition` throttle deliberately stays out of the session and only
   * feeds AppStorage.
   *
   * Seeking and changing the speed both move the baseline while `status` stays
   * the same, so neither is covered by publishStatus() alone.
   */
  private static publishSessionPlaybackState(): void {
    AVSessionManager.updatePlaybackState(
      PlayerManager.status,
      PlayerManager.positionMs,
      PlayerManager.effectivePlaybackSpeed(),
      PlayerManager.durationMs,
      PlayerManager.engine.repeatMode
    );
  }

  /**
   * The rate the player actually runs at, i.e. what the system must use to
   * extrapolate. Reporting the requested `speed` instead would drift whenever
   * the quantization in toPlaybackSpeed() rounds it to a different step.
   */
  private static effectivePlaybackSpeed(): number {
    return effectivePlaybackRate(PlayerManager.speed * PlayerManager.listenTogetherSyncPlaybackRate);
  }

  private static publishPosition(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_POSITION_MS, PlayerManager.positionMs);
    PlayerManager.publishLyricLine();
  }

  /**
   * Bridges lyric line changes into the AppStorage feed (floating bar) and,
   * when np.bt_lyric is on, into AVMetadata.singleLyricText (notification /
   * AVRCP lyric line, Android metadata-slot semantics).
   */
  private static publishLyricLine(): void {
    const line = LyricLineTracker.getInstance().onPosition(
      PlayerManager.positionMs,
      SettingsRepository.getNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, 0)
    );
    if (line === null) {
      return;
    }
    AppStorage.setOrCreate('player.currentLyricLine', line);
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_BT_LYRIC, false)) {
      return;
    }
    const index = PlayerManager.engine.getCurrentQueueIndex();
    if (index < 0 || index >= PlayerManager.queue.length) {
      return;
    }
    AVSessionManager.updateLyricLine(line, PlayerManager.queue[index]);
  }

  /** Clears the single-line lyric slot after a bt-lyric takeover on pause/stop. */
  private static restoreLyricMetadata(): void {
    if (!SettingsRepository.getBoolean(SettingsRepository.KEY_BT_LYRIC, false)) {
      return;
    }
    const index = PlayerManager.engine.getCurrentQueueIndex();
    if (index < 0 || index >= PlayerManager.queue.length) {
      return;
    }
    AVSessionManager.updateLyricLine(null, PlayerManager.queue[index]);
  }

  /**
   * Pushes the whole-song LRC to AVMetadata.lyric (the control center's
   * scrolling-lyrics source). Unlike the single-line slot this is not gated
   * on np.bt_lyric: it is the officially documented metadata field, not a
   * takeover of another field, so there is nothing to opt out of.
   */
  private static publishLyrics(lines: LyricLine[]): void {
    const index = PlayerManager.engine.getCurrentQueueIndex();
    if (index < 0 || index >= PlayerManager.queue.length) {
      return;
    }
    AVSessionManager.updateLyrics(lines, PlayerManager.queue[index]);
  }

  /**
   * Handles the control center's favorite button. `assetId` is matched
   * against the current song rather than searched across the queue: the
   * control center only ever shows the currently playing asset, and a stale
   * id (arriving after a track change) must not toggle the wrong song.
   */
  static async toggleFavoriteByAssetId(assetId: string): Promise<void> {
    const song = PlayerManager.currentSong();
    if (song === null) {
      return;
    }
    if (AVSessionManager.assetIdOf(song) !== assetId) {
      Logger.warn('AVSession toggleFavorite for a stale assetId, ignored');
      return;
    }
    await PlayerManager.toggleFavoriteForCurrentSong();
  }

  /**
   * Single entry point for flipping the current song's favorite state, shared
   * by the in-app button and the media control center so both observe the
   * same published flag.
   */
  static async toggleFavoriteForCurrentSong(): Promise<void> {
    const song = PlayerManager.currentSong();
    if (song === null) {
      return;
    }
    try {
      const favorite = await LocalPlaylistRepository.isFavorite(song);
      if (favorite) {
        await LocalPlaylistRepository.removeFavorite(song);
      } else {
        await LocalPlaylistRepository.addFavorite(song);
      }
      await PlayerManager.publishFavorite(song);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`toggleFavorite failed: ${e.message}`);
    }
  }

  /**
   * Re-reads the favorite flag, publishes it to the UI feed and re-sends the
   * playback state so the control center's favorite icon matches.
   */
  private static async publishFavorite(song: SongItem): Promise<void> {
    const favorite = await LocalPlaylistRepository.isFavorite(song);
    AppStorage.setOrCreate(PlaybackConstants.KEY_FAVORITE, favorite);
    AVSessionManager.setFavorite(favorite);
    PlayerManager.publishStatus(PlayerManager.status);
  }

  private static currentSong(): SongItem | null {
    const index = PlayerManager.engine.getCurrentQueueIndex();
    if (index < 0 || index >= PlayerManager.queue.length) {
      return null;
    }
    return PlayerManager.queue[index];
  }

  private static publishDuration(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_DURATION_MS, PlayerManager.durationMs);
    // The control center's progress bar reads AVMetadata.duration, so the real
    // length resolved by the player has to reach the session too, not just the
    // in-app feed (previously it only ever saw the catalog's declared length).
    const index = PlayerManager.engine.getCurrentQueueIndex();
    if (index < 0 || index >= PlayerManager.queue.length) {
      return;
    }
    AVSessionManager.updateDuration(PlayerManager.queue[index], PlayerManager.durationMs);
  }

  private static publishQueue(): void {
    const queueIndex = PlayerManager.engine.getCurrentQueueIndex();
    const state = new QueueState(
      PlayerManager.queue,
      queueIndex,
      PlayerManager.engine.repeatMode === RepeatMode.ONE,
      PlayerManager.engine.shuffle
    );
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_JSON, state.toJson());
    AppStorage.setOrCreate(PlaybackConstants.KEY_SHUFFLE, PlayerManager.engine.shuffle);
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, PlayerManager.engine.repeatMode);
    PlayerManager.schedulePersist(250);
    PlayerManager.notify();
  }

  /**
   * Schedules a persisted-state write. Debounce mirrors the Android
   * STATE_PERSIST_DEBOUNCE_MS (250ms); pass 0 to flush immediately.
   */
  private static schedulePersist(debounceMs: number): void {
    if (PlayerManager.persistTimer >= 0) {
      clearTimeout(PlayerManager.persistTimer);
    }
    PlayerManager.persistTimer = setTimeout(() => {
      PlayerManager.persistTimer = -1;
      PlayerManager.persistNow();
    }, debounceMs);
  }

  /**
   * Writes the current session snapshot to preferences. Called by the
   * debounced timer, on pause, and from ability lifecycle callbacks where the
   * process may end soon.
   */
  static persistNow(): void {
    if (PlayerManager.persistTimer >= 0) {
      clearTimeout(PlayerManager.persistTimer);
      PlayerManager.persistTimer = -1;
    }
    const state = new PersistedPlaybackState(
      PlayerManager.queue,
      PlayerManager.engine.getCurrentQueueIndex(),
      PlayerManager.positionMs,
      PlayerManager.engine.repeatMode,
      PlayerManager.engine.shuffle,
      PlayerManager.speed
    );
    PlaybackStateRepository.save(state);
  }

  private static notify(): void {
    for (const listener of PlayerManager.listeners) {
      listener.onSnapshotChanged();
    }
  }
}
