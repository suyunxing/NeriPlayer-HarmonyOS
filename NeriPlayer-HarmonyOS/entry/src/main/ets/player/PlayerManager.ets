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
import { QueueEngine, TrackEndAction } from './queue/QueueEngine';
import { AudioInterruptPolicy, InterruptAction } from './AudioInterruptPolicy';
import { SleepTimer, SleepTimerMode } from './SleepTimer';
import { PlaybackConstants, PlaybackStatus, RepeatMode } from './PlaybackConstants';

export interface PlayerListener {
  onSnapshotChanged(): void;
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
  private static listenedMs: number = 0;
  private static lastTimeMs: number = 0;
  private static lastPublishMs: number = 0;
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

  static getStatus(): PlaybackStatus {
    return PlayerManager.status;
  }

  static async playPlaylist(songs: SongItem[], startIndex: number): Promise<void> {
    if (songs.length === 0) {
      return;
    }
    PlayerManager.queue = songs.slice();
    PlayerManager.engine.setQueueSize(songs.length);
    PlayerManager.engine.start(startIndex, PlayerManager.engine.shuffle, PlayerManager.engine.repeatMode);
    PlayerManager.publishQueue();
    await PlayerManager.loadSong();
  }

  static async play(): Promise<void> {
    const player = PlayerManager.player;
    if (player !== null && PlayerManager.status === PlaybackStatus.PAUSED) {
      try {
        await player.play();
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
      await PlayerManager.seekTo(0);
      await PlayerManager.resumeIfPrepared();
    }
  }

  static async pause(): Promise<void> {
    // User-facing pause cancels any pending auto-resume intent.
    PlayerManager.resumeOnFocusRegain = false;
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      await player.pause();
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

  static async next(auto: boolean = false): Promise<void> {
    // Force (wrap/rebuild) is only legitimate under repeat-all or explicit
    // skip-after-failure, mirroring Android nextImpl(force).
    const force = auto && PlayerManager.engine.repeatMode === RepeatMode.ALL;
    const target = PlayerManager.engine.next(force);
    if (target < 0) {
      if (!auto) {
        await PlayerManager.pause();
      }
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      return;
    }
    await PlayerManager.loadSong();
  }

  static async previous(): Promise<void> {
    const target = PlayerManager.engine.previous();
    if (target < 0) {
      return;
    }
    await PlayerManager.loadSong();
  }

  /**
   * Jumps to a specific queue position (used by the queue sheet).
   */
  static async playAt(queueIndex: number): Promise<void> {
    PlayerManager.engine.playAt(queueIndex);
    await PlayerManager.loadSong();
  }

  static getCurrentQueueIndex(): number {
    return PlayerManager.engine.getCurrentQueueIndex();
  }

  static async seekTo(timeMs: number): Promise<void> {
    const player = PlayerManager.player;
    if (player === null) {
      return;
    }
    try {
      await player.seek(Math.max(0, timeMs), media.SeekMode.SEEK_PREV_SYNC);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlayerManager.seekTo failed: ${e.message}`);
    }
  }

  static setShuffle(enabled: boolean): void {
    PlayerManager.engine.setShuffle(enabled);
    PlayerManager.publishQueue();
  }

  static setRepeatMode(mode: RepeatMode): void {
    PlayerManager.engine.setRepeatMode(mode);
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, mode);
    PlayerManager.schedulePersist(0);
    PlayerManager.notify();
  }

  /** Android order: OFF -> ALL -> ONE. */
  static cycleRepeatMode(): RepeatMode {
    const mode = PlayerManager.engine.cycleRepeatMode();
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, mode);
    PlayerManager.schedulePersist(0);
    PlayerManager.notify();
    return mode;
  }

  static setSpeed(speed: number): void {
    PlayerManager.speed = speed;
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, speed);
    PlayerManager.schedulePersist(0);
    if (PlayerManager.player !== null) {
      try {
        PlayerManager.player.setSpeed(PlayerManager.toPlaybackSpeed(speed));
      } catch (error) {
        const e = error as Error;
        Logger.warn(`PlayerManager.setSpeed failed: ${e.message}`);
      }
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

  private static async loadSong(startPositionMs: number = 0): Promise<void> {
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    PlayerManager.errorAttempts = 0;
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.positionMs = startPositionMs;
    PlayerManager.restoredPositionMs = 0;
    PlayerManager.durationMs = song.durationMs;
    PlayerManager.lastTimeMs = 0;
    PlayerManager.publishCurrentSong(song);
    PlayerManager.publishPosition();
    PlayerManager.publishDuration();
    PlayerManager.publishQueue();
    PlayerManager.publishStatus(PlaybackStatus.LOADING);
    HistoryRepository.addSong(song);
    AVSessionManager.updateMetadata(song, PlayerManager.durationMs);

    try {
      const player = await PlayerManager.ensurePlayer();
      const uri = await PlayerManager.resolveStreamUrl(song);
      if (uri.length === 0) {
        throw new Error(`No playable stream for ${song.displayName}`);
      }
      await player.reset();
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
      await player.prepare();
      await PlayerManager.waitForState(['prepared']);
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
        player.setSpeed(PlayerManager.toPlaybackSpeed(PlayerManager.speed));
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
      await PlayerManager.loadSong();
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
   */
  private static toPlaybackSpeed(speed: number): media.PlaybackSpeed {
    if (speed <= 0.75) {
      return speed <= 0.6 ? media.PlaybackSpeed.SPEED_FORWARD_0_50_X : media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (speed < 1.2) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
    if (speed < 1.4) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    if (speed < 1.9) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    }
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
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
      PlayerManager.persistNow();
      return;
    }
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
    PlayerManager.applyInterruptAction(action);
  }

  private static applyInterruptAction(action: InterruptAction): void {
    const player = PlayerManager.player;
    switch (action) {
      case InterruptAction.PAUSE_TRANSIENT:
        PlayerManager.resumeOnFocusRegain = true;
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        break;
      case InterruptAction.PAUSE_PERMANENT:
        PlayerManager.resumeOnFocusRegain = false;
        PlayerManager.publishStatus(PlaybackStatus.PAUSED);
        PlayerManager.flushPlaybackStatsAsync();
        PlayerManager.persistNow();
        break;
      case InterruptAction.RESUME:
        PlayerManager.resumeOnFocusRegain = false;
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
    PlayerManager.notify();
  }

  private static publishStatus(status: PlaybackStatus): void {
    PlayerManager.status = status;
    AppStorage.setOrCreate(PlaybackConstants.KEY_STATUS, status);
    AVSessionManager.updatePlaybackState(
      status,
      PlayerManager.positionMs,
      PlayerManager.speed,
      PlayerManager.durationMs,
      PlayerManager.engine.repeatMode
    );
    PlayerManager.notify();
  }

  private static publishPosition(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_POSITION_MS, PlayerManager.positionMs);
  }

  private static publishDuration(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_DURATION_MS, PlayerManager.durationMs);
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
