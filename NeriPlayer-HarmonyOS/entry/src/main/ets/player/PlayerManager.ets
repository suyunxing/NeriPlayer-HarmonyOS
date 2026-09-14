// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

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
import { DownloadEngine } from '../download/DownloadEngine';
import { DownloadStorage } from '../download/DownloadStorage';
import { HistoryRepository } from '../data/HistoryRepository';
import { PlaybackStatsRepository } from '../data/PlaybackStatsRepository';
import { PlaybackStateRepository } from '../data/PlaybackStateRepository';
import { AppPreferences } from '../data/AppPreferences';
import { PersistedPlaybackState } from '../model/PersistedPlaybackState';
import { AVSessionManager, SessionControlListener } from './AVSessionManager';
import { AutoSongMatcher, AutoMatchPlaybackEnv } from './AutoSongMatcher';
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
import { VolumeFader, FADE_IN_DURATION_MS, FADE_OUT_DURATION_MS } from './VolumeFader';
import { AvPlaylistBridge } from './AvPlaylistBridge';
import { advanceForceFor, peekNextIndex, shouldPrimeNext } from './AvPlaylistPolicy';
import { decideLoadFailureAction, LoadFailureAction } from './PlaybackFailurePolicy';
import { PlaybackCacheManager } from './PlaybackCacheManager';
import {
  ListenTogetherPlaybackCommand,
  ListenTogetherPlaybackCommandSource,
  createListenTogetherPlaybackCommand
} from '../listentogether/control/ListenTogetherPlaybackCommand';
import { shouldHoldListenTogetherPlaybackForSafetyPause } from '../listentogether/playback/ListenTogetherListenerSafetyPausePolicy';

/**
 * Reconciliation slack for the AVPlayer's reported duration: VBR/late-demux
 * re-estimates can drift a few hundred ms between reads, and re-publishing
 * each drift would churn AppStorage and the media session for no visible change.
 */
const DURATION_RECONCILE_TOLERANCE_MS = 300;

export interface PlayerListener {
  onSnapshotChanged(): void;
}

/**
 * Resolved stream for one load chain: the player URL plus the download
 * catalog provenance. The caller commits `catalogKey` only after its own
 * generation check — assigning it inside the resolver would let a superseded
 * chain overwrite the live chain's key and make a later failure self-heal
 * delete the wrong download.
 */
interface ResolvedStream {
  url: string;
  catalogKey: string;
}

/** Bridges AutoSongMatcher back into the queue without a circular import at
 * call sites (loadSong hands it over fire-and-forget). */
class PlayerManagerAutoMatchEnv implements AutoMatchPlaybackEnv {
  isCurrentSong(candidate: SongItem): boolean {
    const current = PlayerManager.getCurrentSong();
    return current !== null && stableKeyOf(current) === stableKeyOf(candidate);
  }

  applyToPlayerQueue(updated: SongItem): void {
    PlayerManager.applySongMetadataUpdate(updated);
  }
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
  // Descriptor for the current local source, consumed by loadSong via the
  // player's fdSrc property (MediaSourceWithUrl cannot carry a raw fd).
  private static pendingLocalDescriptor: media.AVFileDescriptor | null = null;
  private static listeners: PlayerListener[] = [];
  private static queue: SongItem[] = [];
  private static engine: QueueEngine = new QueueEngine();
  private static speed: number = 1.0;
  private static status: PlaybackStatus = PlaybackStatus.IDLE;
  private static positionMs: number = 0;
  private static durationMs: number = 0;
  private static errorAttempts: number = 0;
  // Consecutive auto-skips after load failures, reset on every successful
  // start and on user-driven queue moves; bounds the skip path in
  // PlaybackFailurePolicy so a fully broken queue stops instead of wrapping.
  private static autoSkipFailures: number = 0;
  // Generation whose load failure is currently being recovered: the AVPlayer
  // error callback and the rejected load chain both report the same failure,
  // and handling it twice double-incremented the retry budget and raced two
  // recovery chains onto one AVPlayer.
  private static failureGeneration: number = -1;
  // Catalog provenance of the currently loaded fd:// source: a failure while
  // reading it means the local copy is broken and must be dropped (self-heal).
  private static catalogSourceKey: string = '';
  // The fd:// URL the key was committed with. The AVPlayer 'error' event
  // carries no source identity, so self-heal only fires when the error
  // surfaced against exactly this URL — a late error from a superseded load
  // must not delete the newer song's catalog row.
  private static catalogSourceUrl: string = '';
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
  // Volume fade behind play/pause/track-switch. Every interpolated step is
  // routed into the live AVPlayer through the applier below.
  private static volumeFader: VolumeFader = new VolumeFader(
    (volume: number) => {
      PlayerManager.applyPlayerVolume(volume);
    },
    () => Date.now()
  );
  // Supersession token for fade-out pauses: play() and loadSong() bump it so
  // a stale fade completion can never pause freshly started playback.
  private static pauseGeneration: number = 0;

  static initialize(context: common.UIAbilityContext): void {
    PlayerManager.context = context;
    PlayerManager.publishDefaults();
    PlayerManager.restoreFromDisk();
    AVSessionManager.init(context, new PlayerControlListener());
    BackgroundTaskRunner.init(context);
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
    // Share probes run outside a load chain and need http(s) only: resolve
    // the network paths directly. A *usable* offline copy short-circuits to
    // [] (its fd:// URLs are not shareable, and resolving would recycle the
    // file descriptor live playback holds); a stale, deleted or corrupt row
    // falls through to the network resolvers so sharing keeps working.
    if (song.platform === MusicPlatform.LOCAL) {
      return [];
    }
    const downloaded = await DownloadStorage.findCatalogEntry(song);
    if (downloaded !== null) {
      const localPath = DownloadStorage.resolveFilePath(downloaded.audioPath);
      if (localPath.length > 0 && DownloadStorage.fileSize(localPath) > 0
        && DownloadStorage.hasPlausibleAudioHeader(localPath)) {
        return [];
      }
    }
    const authoritativeUrls = PlayerManager.listenTogetherDelegate?.resolveAuthoritativeStreamUrls(song) ?? [];
    if (authoritativeUrls.length > 0) {
      return PlayerManager.httpShareableOnly(authoritativeUrls[0]);
    }
    return PlayerManager.httpShareableOnly(await StreamResolver.resolveWithNeteaseAutoFallback(song));
  }

  private static httpShareableOnly(url: string): string[] {
    const trimmed = url.trim();
    const lowered = trimmed.toLowerCase();
    return lowered.startsWith('http://') || lowered.startsWith('https://') ? [trimmed] : [];
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
    PlayerManager.autoSkipFailures = 0;
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
    if (player !== null &&
      (PlayerManager.status === PlaybackStatus.PAUSED || PlayerManager.volumeFader.isFadingOut())) {
      // Resume, or reverse a fade-out pause that has not landed yet. The
      // generation bumps also abort a track-switch fade, so play() keeps the
      // current song instead of letting its load chain reset it.
      PlayerManager.pauseGeneration++;
      PlayerManager.loadGeneration++;
      AvPlaylistBridge.abandon();
      PlayerManager.volumeFader.cancel();
      const fadeInMs = PlayerManager.getFadeInMs();
      // With a fade armed: paused audio is silent anyway, so snapping to 0 is
      // inaudible and playback starts from true silence. Without one, land
      // directly on the set volume.
      PlayerManager.volumeFader.snapTo(fadeInMs > 0 ? 0 : PlayerManager.getTargetVolume());
      try {
        await player.play();
        if (fadeInMs > 0) {
          PlayerManager.volumeFader.fadeTo(PlayerManager.getTargetVolume(), fadeInMs);
        }
        // Publish immediately so the UI toggles without waiting for the
        // async AVPlayer stateChange event (which may lag on some streams).
        PlayerManager.publishStatus(PlaybackStatus.PLAYING);
        return;
      } catch (error) {
        const e = error as Error;
        Logger.warn(`PlayerManager.play failed: ${e.message}`);
        // A failed resume must not leave the player muted at the fade start.
        PlayerManager.volumeFader.snapTo(PlayerManager.getTargetVolume());
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
    const fadeOutMs = PlayerManager.getFadeOutMs();
    if (PlayerManager.isAudiblyPlaying() && fadeOutMs > 0) {
      // Fade to silence first; the real pause lands when the fade completes.
      // Status stays PLAYING until then so the surfaces keep describing the
      // audio that is still audible (the stateChange event confirms later).
      const generation = ++PlayerManager.pauseGeneration;
      PlayerManager.volumeFader.fadeTo(0, fadeOutMs, (completed: boolean) => {
        if (!completed || generation !== PlayerManager.pauseGeneration ||
          PlayerManager.player !== player) {
          return;
        }
        player.pause().catch((error: Object) => {
          Logger.warn(`fade-out pause failed: ${(error as Error).message}`);
        });
      });
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
      PlayerManager.stopContinuousTask();
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      return;
    }
    PlayerManager.playWhenReady = true;
    if (!auto) {
      PlayerManager.autoSkipFailures = 0;
    }
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
    PlayerManager.autoSkipFailures = 0;
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
    PlayerManager.autoSkipFailures = 0;
    const command = createListenTogetherPlaybackCommand('PLAY_FROM_QUEUE', source, Date.now());
    command.currentIndex = queueIndex;
    PlayerManager.emitPlaybackCommand(command);
    await PlayerManager.loadSong();
  }

  static getCurrentQueueIndex(): number {
    return PlayerManager.engine.getCurrentQueueIndex();
  }

  /**
   * Reverses the whole queue order while the current track keeps playing
   * (queue sheet "倒序播放"): every engine index is remapped to its mirrored
   * position, so next()/previous() continue from the same song in the
   * flipped order. No-op for queues with fewer than two songs.
   */
  static reverseQueue(): void {
    if (PlayerManager.queue.length < 2) {
      return;
    }
    PlayerManager.queue.reverse();
    PlayerManager.engine.reverse();
    PlayerManager.publishQueue();
  }

  /**
   * Empties the queue and stops playback (queue sheet "清空列表"). The load
   * generation is bumped first so an in-flight loadSong cannot repopulate
   * player state after the clear.
   */
  static async clearQueue(): Promise<void> {
    PlayerManager.playWhenReady = false;
    PlayerManager.loadGeneration++;
    PlayerManager.pauseGeneration++;
    PlayerManager.volumeFader.cancel();
    AvPlaylistBridge.abandon();
    const player = PlayerManager.player;
    if (player !== null) {
      try {
        await player.stop();
        await player.reset();
      } catch (error) {
        const e = error as Error;
        Logger.warn(`clearQueue stop failed: ${e.message}`);
      }
    }
    PlayerManager.positionMs = 0;
    PlayerManager.durationMs = 0;
    PlayerManager.engine.reset();
    PlayerManager.stopContinuousTask();
    PlayerManager.publishDefaults();
    PlayerManager.publishStatus(PlaybackStatus.IDLE);
    PlayerManager.persistNow();
  }

  static async seekTo(
    timeMs: number,
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): Promise<void> {
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    // The bar and lyrics scale seek targets by the catalog-declared duration,
    // which can exceed the resolved stream's real length (NetEase -> Bilibili
    // fallback). A target past the real end drops the AVPlayer on its final
    // frame and instantly fires 'completed', so a drag reads as a skip —
    // clamp to the player-known duration before anything consumes the value.
    const targetMs = PlayerManager.clampSeekTarget(Math.max(0, timeMs));
    Logger.debug(`seekTo: requested=${Math.round(timeMs)} target=${targetMs}`);
    const command = createListenTogetherPlaybackCommand('SEEK', source, Date.now());
    command.positionMs = targetMs;
    PlayerManager.emitPlaybackCommand(command);
    try {
      // seek() returns void on this API level (no promise overload to await).
      player.seek(targetMs, media.SeekMode.SEEK_PREV_SYNC);
      // A seek moves the extrapolation baseline while `status` is unchanged,
      // so nothing else would push it to the session and the control center
      // would keep counting from the pre-seek datum until the next play/pause.
      PlayerManager.positionMs = targetMs;
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

  /**
   * Caps a seek target at the AVPlayer's real stream length: `durationMs` may
   * still hold the catalog-declared value (reconcileStreamDuration trues it up
   * asynchronously), and seeking past the real end completes the track.
   */
  private static clampSeekTarget(targetMs: number): number {
    const player = PlayerManager.player;
    if (player === null) {
      return targetMs;
    }
    try {
      const realDurationMs = player.duration;
      if (realDurationMs > 0 && targetMs > realDurationMs) {
        return realDurationMs;
      }
    } catch (error) {
      const e = error as Error;
      Logger.debug(`read AVPlayer duration for seek clamp failed: ${e.message}`);
    }
    return targetMs;
  }

  /**
   * Trues the published duration up with the AVPlayer's real stream length.
   * loadSong seeds the UI with the catalog-declared `durationMs`; some sources
   * (notably the NetEase -> Bilibili fallback) resolve to a stream whose real
   * length differs and is only reported after prepare, leaving the play page's
   * bar scaled by a wrong total — a drag past the real end then instantly
   * completes the track and reads as an unintended skip. Callers must already
   * know the player belongs to the current song (the load chain after prepare,
   * a 'playing' transition, or a timeUpdate while PLAYING): a stale timeUpdate
   * from the previous track during a load transition must not re-seed the next
   * song's duration.
   */
  private static reconcileStreamDuration(): void {
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      const realDurationMs = player.duration;
      if (realDurationMs > 0 &&
        Math.abs(realDurationMs - PlayerManager.durationMs) > DURATION_RECONCILE_TOLERANCE_MS) {
        PlayerManager.durationMs = realDurationMs;
        PlayerManager.publishDuration();
      }
    } catch (error) {
      const e = error as Error;
      Logger.debug(`reconcile AVPlayer duration failed: ${e.message}`);
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

  /**
   * One-button play-mode cycle for the now-playing page:
   * 顺序播放 -> 列表循环 -> 单曲循环 -> 随机播放 -> 顺序播放. Each step fully
   * defines both axes (repeat + shuffle), so a state left behind by AVSession
   * or Listen-Together sync simply falls into the nearest step on next tap.
   */
  static cyclePlayMode(
    source: ListenTogetherPlaybackCommandSource = ListenTogetherPlaybackCommandSource.LOCAL
  ): void {
    const engine = PlayerManager.engine;
    if (engine.shuffle) {
      PlayerManager.applyPlayMode(false, RepeatMode.OFF, source);
    } else if (engine.repeatMode === RepeatMode.OFF) {
      PlayerManager.applyPlayMode(false, RepeatMode.ALL, source);
    } else if (engine.repeatMode === RepeatMode.ALL) {
      PlayerManager.applyPlayMode(false, RepeatMode.ONE, source);
    } else {
      PlayerManager.applyPlayMode(true, RepeatMode.ALL, source);
    }
  }

  private static applyPlayMode(
    shuffle: boolean,
    mode: RepeatMode,
    source: ListenTogetherPlaybackCommandSource
  ): void {
    PlayerManager.engine.setRepeatMode(mode);
    PlayerManager.engine.setShuffle(shuffle);
    // publishQueue re-publishes both mode keys, persists the session and
    // notifies listeners, so the cycle emits exactly one PLAYBACK_MODE command.
    PlayerManager.publishQueue();
    const command = createListenTogetherPlaybackCommand('PLAYBACK_MODE', source, Date.now());
    command.repeatMode = mode;
    command.shuffleEnabled = shuffle;
    PlayerManager.emitPlaybackCommand(command);
  }

  static setSpeed(speed: number): void {
    PlayerManager.speed = speed;
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, speed);
    PlayerManager.schedulePersist(0);
    PlayerManager.applyEffectiveSpeed();
  }

  /**
   * App-level soft volume (np.playback_volume, 0..1): persisted through the
   * settings store and applied live when a player exists; every freshly
   * prepared source re-applies it in loadSong. The system volume curve is
   * untouched.
   */
  static setVolume(volume: number): void {
    const clamped = Math.min(1, Math.max(0, volume));
    SettingsRepository.setNumber(SettingsRepository.KEY_PLAYBACK_VOLUME, clamped);
    // An explicit volume change cancels any fade in flight and lands on the
    // requested value through the fader, so its internal state stays in sync
    // with what the player actually renders.
    PlayerManager.volumeFader.snapTo(clamped);
  }

  /** Routes one interpolated fade step into the live AVPlayer (any state). */
  private static applyPlayerVolume(volume: number): void {
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      player.setVolume(volume);
    } catch (error) {
      const e = error as Error;
      Logger.debug(`apply fade volume failed: ${e.message}`);
    }
  }

  /** The persisted app-level soft volume (np.playback_volume), clamped. */
  private static getTargetVolume(): number {
    return Math.min(1, Math.max(0, SettingsRepository.getNumber(SettingsRepository.KEY_PLAYBACK_VOLUME, 1.0)));
  }

  /** Volume fade master switch (np.playback_fade, Android playback_fade_in). */
  private static isFadeEnabled(): boolean {
    return SettingsRepository.getBoolean(SettingsRepository.KEY_PLAYBACK_FADE, true);
  }

  /**
   * Effective fade-in length. A 0ms duration (or master off) disables the
   * fade entirely, mirroring Android's shouldFade* duration gate.
   */
  private static getFadeInMs(): number {
    if (!PlayerManager.isFadeEnabled()) {
      return 0;
    }
    return Math.max(0, Math.round(
      SettingsRepository.getNumber(SettingsRepository.KEY_PLAYBACK_FADE_IN_MS, FADE_IN_DURATION_MS)
    ));
  }

  private static getFadeOutMs(): number {
    if (!PlayerManager.isFadeEnabled()) {
      return 0;
    }
    return Math.max(0, Math.round(
      SettingsRepository.getNumber(SettingsRepository.KEY_PLAYBACK_FADE_OUT_MS, FADE_OUT_DURATION_MS)
    ));
  }

  /**
   * True only when audio is actually sounding: the published PLAYING status
   * alone is stale between the 'completed' event and the next track's start
   * (auto-advance fallback), where a fade-out would only delay the switch.
   */
  private static isAudiblyPlaying(): boolean {
    if (PlayerManager.status !== PlaybackStatus.PLAYING) {
      return false;
    }
    const player = PlayerManager.player;
    if (player === null) {
      return false;
    }
    try {
      return player.state === 'playing';
    } catch (error) {
      const e = error as Error;
      Logger.debug(`read AVPlayer state for fade gate failed: ${e.message}`);
      return false;
    }
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
    // np.autoplay_on_launch: continue the restored session without waiting
    // for the first play press. Read from the preferences store (not the
    // reactive AppStorage mirror) — the settings merge may still be in
    // flight while restore runs.
    const autoplay = await AppPreferences.getBoolean(
      SettingsRepository.KEY_AUTOPLAY_ON_LAUNCH, false);
    if (autoplay) {
      Logger.info('PlayerManager autoplay-on-launch armed, resuming restored session');
      PlayerManager.play().catch((error: Error) => {
        Logger.warn(`autoplay on launch failed: ${error.message}`);
      });
    }
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
      // Seed the catalog-declared length before the first play(): without it
      // durationMs stayed 0 until loadSong, and sliders rendered a full bar
      // against the restored position (0:N / 0:00).
      if (song.durationMs > 0) {
        PlayerManager.durationMs = song.durationMs;
        PlayerManager.publishDuration();
      }
      PlayerManager.publishCurrentSong(song);
    }
    Logger.info(`PlayerManager restored queue: ${state.songs.length} songs at index ${state.queueIndex}`);
  }

  private static async loadSong(startPositionMs: number = 0, isRetry: boolean = false): Promise<void> {
    const generation = ++PlayerManager.loadGeneration;
    // Any explicit load invalidates a primed native-playlist entry: the
    // bridge's source was predicted for the previous queue position.
    AvPlaylistBridge.abandon();
    // Any failure self-heal from here on belongs to this load only; the
    // resolved provenance is committed below after the generation check, so a
    // superseded chain can never leave a stale key behind.
    PlayerManager.catalogSourceKey = '';
    PlayerManager.catalogSourceUrl = '';
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
    // Manual/natural switch while audible: fade the current track out before
    // the load chain's reset() cuts it. A superseding play()/load bumps the
    // generations, which both aborts this fade and discards this chain.
    const switchFadeOutMs = PlayerManager.getFadeOutMs();
    if (switchFadeOutMs > 0 && PlayerManager.isAudiblyPlaying()) {
      PlayerManager.pauseGeneration++;
      await new Promise<void>((resolve) => {
        PlayerManager.volumeFader.fadeTo(0, switchFadeOutMs, () => resolve());
      });
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
    }
    PlayerManager.beginTrackTransition(song, startPositionMs);

    try {
      const player = await PlayerManager.ensurePlayer();
      if (generation !== PlayerManager.loadGeneration) {
        return;
      }
      // Opt-in playback cache (np.playback_cache): a completed offline copy
      // replays from disk without touching the platform APIs. Skipped while
      // a listen-together session is active (the room's link is authoritative).
      let cachedSource: media.MediaSource | null = null;
      if (song.platform !== MusicPlatform.LOCAL) {
        const listenTogetherActive =
          PlayerManager.listenTogetherDelegate?.isListenTogetherActive() ?? false;
        cachedSource = await PlaybackCacheManager.takeSourceFor(song, listenTogetherActive);
        if (generation !== PlayerManager.loadGeneration) {
          return;
        }
      }
      let source: media.MediaSource | null = null;
      let playedUrl: string = '';
      let playedHeaders: Record<string, string> = {};
      if (cachedSource !== null) {
        await player.reset();
        source = cachedSource;
      } else {
        const resolved = await PlayerManager.resolveStreamUrl(song);
        if (generation !== PlayerManager.loadGeneration) {
          // Superseded mid-resolution: the fd/pending descriptor opened for
          // this chain stays until the next openLocalFd recycles it, but no
          // catalog provenance is committed (the failure self-heal of the
          // *current* chain must not see this chain's key).
          return;
        }
        if (resolved.url.length === 0) {
          throw new Error(`No playable stream for ${song.displayName}`);
        }
        PlayerManager.catalogSourceKey = resolved.catalogKey;
        // Pair the key with the exact fd:// URL it came from: the self-heal
        // only acts when the player's current media still is this source.
        PlayerManager.catalogSourceUrl = resolved.catalogKey.length > 0 ? resolved.url : '';
        PlayerManager.setCurrentMediaUrl(resolved.url);
        playedUrl = resolved.url;
        await player.reset();
        if (generation !== PlayerManager.loadGeneration) {
          return;
        }
        if (resolved.url.startsWith('fd://') && PlayerManager.pendingLocalDescriptor !== null) {
          // Local sources bypass MediaSource entirely: the descriptor goes
          // through the player's fdSrc property (see openLocalFd).
          player.fdSrc = PlayerManager.pendingLocalDescriptor;
          PlayerManager.pendingLocalDescriptor = null;
        } else {
          // Bilibili CDN hosts require a web Referer + desktop UA (plus the login
          // cookie when present) or the player's own fetch is rejected with 403.
          const biliCookie = BiliCookieRepository.isLoggedIn()
            ? buildBiliCookieHeader(BiliCookieRepository.getCookies())
            : '';
          const headers = streamHeadersFor(resolved.url, biliCookie);
          playedHeaders = headers;
          source = Object.keys(headers).length > 0
            ? media.createMediaSourceWithUrl(resolved.url, headers)
            : media.createMediaSourceWithUrl(resolved.url);
        }
      }
      if (source !== null) {
        await player.setMediaSource(source);
      }
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
      // Focus mode follows np.mix_audio ("允许与其他应用同时播放"): SHARE keeps
      // a single focus owner inside this app and lets cooperative pause hints
      // from other apps be ignored (AudioInterruptPolicy); INDEPENDENT makes
      // each stream request focus on its own. Must be set between prepare and
      // the first play of each source.
      player.audioInterruptMode = SettingsRepository.getBoolean(SettingsRepository.KEY_MIX_AUDIO, true)
        ? audio.InterruptMode.SHARE_MODE
        : audio.InterruptMode.INDEPENDENT_MODE;
      // Re-apply the app-level soft volume to every freshly prepared source:
      // an auto-played start begins silent and fades in; anything else (e.g.
      // a pause that landed mid-switch) restores the set volume directly.
      const fadeInMs = PlayerManager.getFadeInMs();
      PlayerManager.volumeFader.snapTo(PlayerManager.playWhenReady && fadeInMs > 0
        ? 0
        : PlayerManager.getTargetVolume());
      // First correction point for the catalog-declared duration; playing and
      // timeUpdate reconcile later if the demuxer only reports the length then.
      PlayerManager.reconcileStreamDuration();
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
      if (!PlayerManager.playWhenReady) {
        // A pause that landed mid-switch armed this load before dying; leave
        // the new track prepared and paused instead of playing over the pause.
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        return;
      }
      await player.play();
      if (fadeInMs > 0) {
        PlayerManager.volumeFader.fadeTo(PlayerManager.getTargetVolume(), fadeInMs);
      }
      Logger.info(`PlayerManager playback started: ${song.displayName}`);
      if (generation === PlayerManager.loadGeneration) {
        // Both accelerators are strictly fire-and-forget: playback already
        // succeeded, so neither may delay or fail this chain.
        if (playedUrl.length > 0) {
          PlaybackCacheManager.scheduleCache(song, playedUrl, playedHeaders);
        }
        PlayerManager.primeNativeNextAsync(generation);
      }
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

  /**
   * Track-change side effects shared by loadSong and the native-playlist
   * advance (tryNativeAdvance): stats flush, position/duration reset and the
   * AVSession/UI/history/auto-match publishes. loadSong continues from here
   * into stream resolution; the native advance continues into the kernel
   * handover that already swapped the media.
   */
  private static beginTrackTransition(song: SongItem, startPositionMs: number): void {
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
    // Fire-and-forget metadata auto-match (lyrics/artist/cover) for songs
    // missing it. Must never delay or break playback, so it is not awaited;
    // stale results are rejected inside via the current-song check.
    AutoSongMatcher.maybeAutoMatch(song, new PlayerManagerAutoMatchEnv());
  }

  private static async resolveStreamUrl(song: SongItem): Promise<ResolvedStream> {
    const resolved: ResolvedStream = { url: '', catalogKey: '' };
    if (song.platform !== MusicPlatform.LOCAL) {
      // A completed download short-circuits network resolution so catalog
      // tracks stay playable offline (Android offline-first semantics).
      const downloaded = await DownloadStorage.findCatalogEntry(song);
      if (downloaded !== null) {
        const localUrl = PlayerManager.openLocalFd(downloaded.audioPath);
        if (localUrl.length > 0) {
          resolved.url = localUrl;
          resolved.catalogKey = stableKeyOf(song);
          return resolved;
        }
      }
      // A listener may consume the controller's already-resolved stream after
      // the offline catalog has had a chance to satisfy the request.
      const authoritativeUrls = PlayerManager.listenTogetherDelegate?.resolveAuthoritativeStreamUrls(song) ?? [];
      if (authoritativeUrls.length > 0) {
        resolved.url = authoritativeUrls[0];
        return resolved;
      }
      // NetEase songs fall back to a matched Bilibili source when the direct
      // stream is unavailable and the setting is on.
      resolved.url = await StreamResolver.resolveWithNeteaseAutoFallback(song);
      return resolved;
    }
    const uri = song.localFilePath.length > 0 ? song.localFilePath : song.mediaUri;
    resolved.url = PlayerManager.openLocalFd(uri);
    return resolved;
  }

  /** Opens a sandbox audio file for AVPlayer; '' when unreadable. */
  private static openLocalFd(uri: string): string {
    if (uri.length === 0) {
      return '';
    }
    // Catalog rows from a user-picked download directory hold file:// URIs;
    // CoreFileKit needs the converted sandbox path for open/stat.
    const path = DownloadStorage.resolveFilePath(uri);
    if (path.length === 0) {
      return '';
    }
    try {
      PlayerManager.closeLocalFile();
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      PlayerManager.localFile = file;
      // The descriptor is applied through the player's fdSrc property, not
      // through MediaSourceWithUrl: feeding the fd URL into a network-shaped
      // MediaSource makes the container sniffer fail with 5400106 even for
      // clean transfers. size pins the exact payload length for the sniffer.
      const size = fileIo.statSync(path).size;
      PlayerManager.pendingLocalDescriptor = { fd: file.fd, offset: 0, length: size };
      return `fd://${file.fd}?offset=0&size=${size}`;
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
    if (PlayerManager.failureGeneration === PlayerManager.loadGeneration) {
      return;
    }
    PlayerManager.failureGeneration = PlayerManager.loadGeneration;
    // A source opened from the download catalog but rejected by the player
    // means the local copy is broken (e.g. zero-holed staging writes). Drop
    // the stale catalog row, the file and the finished task record: the
    // library count stays truthful and the engine's completed-task
    // short-circuit no longer pins the bad file against a re-download.
    // The AVPlayer error event carries no source identity, so act only when
    // the current media still is the exact fd:// URL the key was committed
    // with — a late error from a superseded load must not delete the newer
    // song's catalog row.
    if (PlayerManager.catalogSourceKey.length > 0
      && PlayerManager.catalogSourceUrl.length > 0
      && PlayerManager.catalogSourceUrl === PlayerManager.currentMediaUrl) {
      const staleKey = PlayerManager.catalogSourceKey;
      PlayerManager.catalogSourceKey = '';
      PlayerManager.catalogSourceUrl = '';
      try {
        await DownloadEngine.deleteDownload(staleKey);
        Logger.warn('PlayerManager: dropped corrupt download from catalog');
      } catch (error) {
        const e = error as Error;
        Logger.warn(`catalog self-heal failed: ${e.message}`);
      }
    }
    PlayerManager.errorAttempts += 1;
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    const action = decideLoadFailureAction({
      errorAttempts: PlayerManager.errorAttempts,
      autoSkipFailures: PlayerManager.autoSkipFailures,
      queueLength: PlayerManager.queue.length,
      nextTarget: peekNextIndex(PlayerManager.engine, PlayerManager.engine.repeatMode === RepeatMode.ALL),
      currentIndex: PlayerManager.engine.getCurrentQueueIndex()
    });
    if (action === LoadFailureAction.RETRY_SAME) {
      // URL re-sign first (backlog §2.1): direct links carry TTLs, and both
      // the per-song cache and the YTM resolver cache would happily serve
      // the same expired URL to the retry.
      StreamResolver.invalidateResolvedUrl(song);
      Logger.warn(`Retrying playback with a fresh stream for ${song.displayName} `
        + `(attempt ${PlayerManager.errorAttempts})`);
      await PlayerManager.loadSong(0, true);
      return;
    }
    if (action === LoadFailureAction.SKIP_NEXT) {
      PlayerManager.autoSkipFailures += 1;
      Logger.warn(`Giving up on ${song.displayName}, skipping to next`);
      await PlayerManager.next(true);
      return;
    }
    Logger.warn(`Giving up on ${song.displayName}; playback stopped`);
    PlayerManager.playWhenReady = false;
    PlayerManager.stopContinuousTask();
    PlayerManager.publishStatus(PlaybackStatus.ERROR);
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
      AvPlaylistBridge.attach(player);
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
        PlayerManager.autoSkipFailures = 0;
        PlayerManager.reconcileStreamDuration();
        if (PlayerManager.context !== null) {
          BackgroundTaskRunner.start(PlayerManager.context);
        }
        break;
      case 'paused':
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.schedulePersist(0);
        PlayerManager.stopContinuousTask();
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
      AvPlaylistBridge.abandon();
      PlayerManager.sleepTimer.cancel();
      PlayerManager.publishSleepState();
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      PlayerManager.playWhenReady = false;
      PlayerManager.stopContinuousTask();
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
      AvPlaylistBridge.abandon();
      const player = PlayerManager.player;
      if (player !== null) {
        try {
          // seek() returns void on this API level; the pending seek applies
          // before the play() below starts (same contract as in loadSong).
          player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
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
      // API 26 native-playlist handover first (gapless); every arbitration
      // above has already agreed to advance, so the kernel swap only decides
      // the *how*. Any mismatch or failure falls back to the loadSong path.
      if (await PlayerManager.tryNativeAdvance()) {
        return;
      }
      await PlayerManager.next(true);
      return;
    }
    AvPlaylistBridge.abandon();
    PlayerManager.stopContinuousTask();
    PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
  }

  /**
   * Gapless advance over the API 26 native playlist (AvPlaylistBridge). The
   * bridge holds the next (offline) source pre-added to the player's list;
   * advancing swaps media inside the kernel without the reset/prepare cycle
   * of loadSong. The native list never decides *whether* to advance — only
   * the *how* is delegated — so the sleep timer, the listen-together room
   * and repeat-one semantics all keep running in handleCompletion above.
   * Returns false (engine untouched) whenever the safe path must be taken.
   */
  private static async tryNativeAdvance(): Promise<boolean> {
    if (!AvPlaylistBridge.isPrimed()) {
      return false;
    }
    const delegate = PlayerManager.listenTogetherDelegate;
    if (delegate !== null && delegate.isListenTogetherActive()) {
      // The room arbitrates "next"; a locally primed handover would race it.
      AvPlaylistBridge.abandon();
      return false;
    }
    const primedIndex = AvPlaylistBridge.peekPrimedIndex();
    const force = advanceForceFor(PlayerManager.engine.repeatMode);
    if (peekNextIndex(PlayerManager.engine, force) !== primedIndex) {
      // The queue moved under us (mode toggle, mutation): the primed source
      // no longer matches the engine's decision.
      AvPlaylistBridge.abandon();
      return false;
    }
    const mediaUrl = AvPlaylistBridge.primedMediaUrl();
    if (!(await AvPlaylistBridge.advance())) {
      // Bridge latched itself off; the engine has not moved.
      return false;
    }
    const target = PlayerManager.engine.next(force);
    if (target !== primedIndex) {
      // Cannot happen (predicted above on a full clone); if it ever does,
      // engine and playback would diverge — recover through a full reload.
      Logger.warn(`PlayerManager native advance landed on ${target}, expected ${primedIndex}`);
      await PlayerManager.loadSong();
      return true;
    }
    const song = PlayerManager.getCurrentSong();
    if (song !== null) {
      PlayerManager.beginTrackTransition(song, 0);
      PlayerManager.setCurrentMediaUrl(mediaUrl);
    }
    // The kernel swapped to the primed offline source; the failure self-heal
    // must now point at THIS song's catalog row, not the previous track's
    // (a loadSong would have reset the key, but the native advance skips it).
    PlayerManager.catalogSourceKey = song !== null && song.platform !== MusicPlatform.LOCAL
      ? stableKeyOf(song)
      : '';
    PlayerManager.catalogSourceUrl = PlayerManager.catalogSourceKey.length > 0 ? mediaUrl : '';
    // The kernel already swapped the media; nudge the transport in case it
    // parked, and re-apply the speed the new source did not inherit.
    const player = PlayerManager.player;
    if (player !== null) {
      try {
        player.setSpeed(
          PlayerManager.toPlaybackSpeed(PlayerManager.speed * PlayerManager.listenTogetherSyncPlaybackRate)
        );
      } catch (error) {
        const e = error as Error;
        Logger.debug(`native advance setSpeed failed: ${e.message}`);
      }
      try {
        await player.play();
      } catch (error) {
        const e = error as Error;
        Logger.warn(`native advance play failed: ${e.message}`);
      }
    }
    PlayerManager.persistNow();
    Logger.info(`PlayerManager native playlist advance to queue index ${primedIndex}`);
    return true;
  }

  private static primeNativeNextAsync(generation: number): void {
    void PlayerManager.primeNativeNext(generation).catch((error: Object) => {
      Logger.debug(`primeNativeNext failed: ${(error as Error).message}`);
    });
  }

  /**
   * Primes the native playlist with the next queue entry (AvPlaylistPolicy
   * gates: no session, no repeat-one, offline-resolvable next). Network
   * streams are never primed — see AvPlaylistPolicy.shouldPrimeNext.
   */
  private static async primeNativeNext(generation: number): Promise<void> {
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    const delegate = PlayerManager.listenTogetherDelegate;
    const listenTogetherActive = delegate !== null && delegate.isListenTogetherActive();
    const force = advanceForceFor(PlayerManager.engine.repeatMode);
    const nextIndex = peekNextIndex(PlayerManager.engine, force);
    if (nextIndex < 0 || nextIndex >= PlayerManager.queue.length) {
      return;
    }
    const nextSong = PlayerManager.queue[nextIndex];
    const localPath = await PlayerManager.offlinePathFor(nextSong);
    if (generation !== PlayerManager.loadGeneration) {
      return;
    }
    if (!shouldPrimeNext({
      queueLength: PlayerManager.queue.length,
      repeatMode: PlayerManager.engine.repeatMode,
      nextIndex: nextIndex,
      listenTogetherActive: listenTogetherActive,
      nextOfflineAvailable: localPath.length > 0
    })) {
      return;
    }
    await AvPlaylistBridge.prime(nextIndex, localPath);
  }

  /** Sandbox/download path for an offline-playable song, '' when online-only. */
  private static async offlinePathFor(song: SongItem): Promise<string> {
    if (song.platform === MusicPlatform.LOCAL) {
      return song.localFilePath.length > 0 ? song.localFilePath : song.mediaUri;
    }
    const downloaded = await DownloadStorage.findCatalogEntry(song);
    return downloaded !== null ? downloaded.audioPath : '';
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
      // PLAYING-only: a stale timeUpdate from the previous track can still
      // arrive during a load transition, and its duration must not re-seed
      // the incoming song's bar scale.
      if (PlayerManager.status === PlaybackStatus.PLAYING) {
        PlayerManager.reconcileStreamDuration();
      }
    }
    if (now - PlayerManager.lastProgressPersistMs > 15000) {
      PlayerManager.lastProgressPersistMs = now;
      PlayerManager.schedulePersist(250);
    }
  }

  private static onPlayerError(error: BusinessError): void {
    Logger.error(`AVPlayer error: code=${error.code} message=${error.message}`);
    PlayerManager.publishStatus(PlaybackStatus.ERROR);
    PlayerManager.stopContinuousTask();
    PlayerManager.rejectStateWaiters(error.message);
    PlayerManager.handleLoadFailure();
  }

  /**
   * Releases the AUDIO_PLAYBACK continuous task. Terminal paths (queue end,
   * sleep-timer stop, player error) funnel through here so the app never
   * holds a task without audible playback — the background guide suspends
   * apps that keep a task while the business has ended.
   */
  private static stopContinuousTask(): void {
    if (PlayerManager.context !== null) {
      BackgroundTaskRunner.stop(PlayerManager.context);
    }
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
      PlayerManager.resumeOnFocusRegain,
      SettingsRepository.getBoolean(SettingsRepository.KEY_MIX_AUDIO, true)
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
        // The system owns this pause (and any ducking ramp); stop our fade
        // ticks instead of racing its volume handling.
        PlayerManager.volumeFader.cancel();
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        break;
      case InterruptAction.PAUSE_PERMANENT:
        PlayerManager.resumeOnFocusRegain = false;
        PlayerManager.playWhenReady = false;
        PlayerManager.volumeFader.cancel();
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.persistNow();
        break;
      case InterruptAction.RESUME:
        PlayerManager.resumeOnFocusRegain = false;
        PlayerManager.playWhenReady = true;
        PlayerManager.volumeFader.cancel();
        // A fade cut short by the interrupt must not resume into a muted or
        // half-faded player. Direct restore, no fade: the system may be
        // un-ducking at the same time and owns its own ramp.
        PlayerManager.volumeFader.snapTo(PlayerManager.getTargetVolume());
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
