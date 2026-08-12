import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { QueueState } from '../model/QueueState';
import { MusicPlatform } from '../model/MusicPlatform';
import { stableKeyOf } from '../model/SongIdentity';
import { StreamResolver } from '../network/StreamResolver';
import { HistoryRepository } from '../data/HistoryRepository';
import { PlaybackStatsRepository } from '../data/PlaybackStatsRepository';
import { AVSessionManager, SessionControlListener } from './AVSessionManager';
import { BackgroundTaskRunner } from './BackgroundTaskRunner';
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

  onNext(): void {
    PlayerManager.next(false);
  }

  onPrevious(): void {
    PlayerManager.previous();
  }

  onSeek(timeMs: number): void {
    PlayerManager.seekTo(timeMs);
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
  private static order: number[] = [];
  private static orderIndex: number = -1;
  private static shuffle: boolean = false;
  private static repeatMode: RepeatMode = RepeatMode.ALL;
  private static speed: number = 1.0;
  private static status: PlaybackStatus = PlaybackStatus.IDLE;
  private static positionMs: number = 0;
  private static durationMs: number = 0;
  private static errorAttempts: number = 0;
  private static listenedMs: number = 0;
  private static lastTimeMs: number = 0;
  private static lastPublishMs: number = 0;

  static initialize(context: common.UIAbilityContext): void {
    PlayerManager.context = context;
    PlayerManager.publishDefaults();
    PlayerManager.restoreQueue();
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
    if (PlayerManager.orderIndex < 0 || PlayerManager.orderIndex >= PlayerManager.order.length) {
      return null;
    }
    const queueIndex = PlayerManager.order[PlayerManager.orderIndex];
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
    PlayerManager.buildOrder(startIndex);
    PlayerManager.publishQueue();
    await PlayerManager.loadSong(0);
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
        await PlayerManager.loadSong(0);
      }
      return;
    }
    if (PlayerManager.status === PlaybackStatus.COMPLETED) {
      await PlayerManager.seekTo(0);
      await PlayerManager.resumeIfPrepared();
    }
  }

  static async pause(): Promise<void> {
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
    const nextIndex = PlayerManager.nextOrderIndex();
    if (nextIndex < 0) {
      if (!auto) {
        await PlayerManager.pause();
      }
      PlayerManager.publishStatus(PlaybackStatus.COMPLETED);
      return;
    }
    await PlayerManager.loadSong(nextIndex);
  }

  static async previous(): Promise<void> {
    if (PlayerManager.order.length === 0) {
      return;
    }
    const prevIndex = PlayerManager.orderIndex - 1;
    const target = prevIndex < 0 ? PlayerManager.order.length - 1 : prevIndex;
    await PlayerManager.loadSong(target);
  }

  /**
   * Jumps to a specific queue position (used by the queue sheet).
   */
  static async playAt(orderIndex: number): Promise<void> {
    if (orderIndex < 0 || orderIndex >= PlayerManager.order.length) {
      return;
    }
    await PlayerManager.loadSong(orderIndex);
  }

  static getOrderIndex(): number {
    return PlayerManager.orderIndex;
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
    PlayerManager.shuffle = enabled;
    const currentQueueIndex = PlayerManager.order.length > 0
      ? PlayerManager.order[Math.min(PlayerManager.orderIndex, PlayerManager.order.length - 1)]
      : 0;
    PlayerManager.buildOrder(currentQueueIndex);
    PlayerManager.publishQueue();
  }

  static setRepeatMode(mode: RepeatMode): void {
    PlayerManager.repeatMode = mode;
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, mode);
    PlayerManager.notify();
  }

  static setSpeed(speed: number): void {
    PlayerManager.speed = speed;
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, speed);
    if (PlayerManager.player !== null) {
      try {
        PlayerManager.player.setSpeed(PlayerManager.toPlaybackSpeed(speed));
      } catch (error) {
        const e = error as Error;
        Logger.warn(`PlayerManager.setSpeed failed: ${e.message}`);
      }
    }
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
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, PlayerManager.repeatMode);
    AppStorage.setOrCreate(PlaybackConstants.KEY_SHUFFLE, PlayerManager.shuffle);
    AppStorage.setOrCreate(PlaybackConstants.KEY_SPEED, PlayerManager.speed);
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_JSON, '');
  }

  private static restoreQueue(): void {
    const json = AppStorage.get<string>(PlaybackConstants.KEY_QUEUE_JSON) ?? '';
    if (json.length === 0) {
      return;
    }
    try {
      const state = QueueState.fromJson(json);
      if (state.songs.length === 0) {
        return;
      }
      PlayerManager.queue = state.songs;
      PlayerManager.shuffle = state.shuffle;
      PlayerManager.repeatMode = state.repeatOne ? RepeatMode.ONE : PlayerManager.repeatMode;
      PlayerManager.buildOrder(Math.min(state.queueIndex, state.songs.length - 1));
      PlayerManager.orderIndex = 0;
      PlayerManager.publishQueue();
      PlayerManager.publishStatus(PlaybackStatus.PAUSED);
      const song = PlayerManager.getCurrentSong();
      if (song !== null) {
        PlayerManager.publishCurrentSong(song);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`PlayerManager.restoreQueue failed: ${e.message}`);
    }
  }

  private static buildOrder(startQueueIndex: number): void {
    const count = PlayerManager.queue.length;
    const order: number[] = [];
    if (PlayerManager.shuffle) {
      const remaining: number[] = [];
      for (let i = 0; i < count; i++) {
        if (i !== startQueueIndex) {
          remaining.push(i);
        }
      }
      // Fisher-Yates on the remaining indices.
      for (let i = remaining.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        const tmp = remaining[i];
        remaining[i] = remaining[j];
        remaining[j] = tmp;
      }
      order.push(startQueueIndex, ...remaining);
    } else {
      for (let i = 0; i < count; i++) {
        order.push(i);
      }
    }
    PlayerManager.order = order;
    PlayerManager.orderIndex = 0;
  }

  private static nextOrderIndex(): number {
    if (PlayerManager.order.length === 0) {
      return -1;
    }
    const next = PlayerManager.orderIndex + 1;
    if (next < PlayerManager.order.length) {
      return next;
    }
    return PlayerManager.repeatMode === RepeatMode.ALL ? 0 : -1;
  }

  private static async loadSong(orderIndex: number): Promise<void> {
    if (orderIndex < 0 || orderIndex >= PlayerManager.order.length) {
      return;
    }
    PlayerManager.orderIndex = orderIndex;
    PlayerManager.errorAttempts = 0;
    const song = PlayerManager.getCurrentSong();
    if (song === null) {
      return;
    }
    PlayerManager.flushPlaybackStatsAsync();
    PlayerManager.positionMs = 0;
    PlayerManager.durationMs = song.durationMs;
    PlayerManager.lastTimeMs = 0;
    PlayerManager.publishCurrentSong(song);
    PlayerManager.publishPosition();
    PlayerManager.publishDuration();
    PlayerManager.publishQueue();
    PlayerManager.publishStatus(PlaybackStatus.LOADING);
    HistoryRepository.addSong(song);
    AVSessionManager.updateMetadata(song);

    try {
      const player = await PlayerManager.ensurePlayer();
      const uri = await PlayerManager.resolveStreamUrl(song);
      if (uri.length === 0) {
        throw new Error(`No playable stream for ${song.displayName}`);
      }
      await player.reset();
      await player.setMediaSource(media.createMediaSourceWithUrl(uri));
      await PlayerManager.waitForState(['initialized']);
      await player.prepare();
      await PlayerManager.waitForState(['prepared']);
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
      await player.play();
      Logger.info(`PlayerManager playback started: ${song.displayName}`);
    } catch (error) {
      const e = error as Error;
      Logger.error(`PlayerManager.loadSong failed for ${song.displayName}: ${e.message}`);
      await PlayerManager.handleLoadFailure();
    }
  }

  private static async resolveStreamUrl(song: SongItem): Promise<string> {
    if (song.platform === MusicPlatform.LOCAL) {
      const uri = song.localFilePath.length > 0 ? song.localFilePath : song.mediaUri;
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
    return StreamResolver.resolve(song);
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
      await PlayerManager.loadSong(PlayerManager.orderIndex);
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
    const player = PlayerManager.player;
    if (PlayerManager.repeatMode === RepeatMode.ONE) {
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
    }
    await PlayerManager.next(true);
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
  }

  private static onPlayerError(error: BusinessError): void {
    Logger.error(`AVPlayer error: code=${error.code} message=${error.message}`);
    PlayerManager.publishStatus(PlaybackStatus.ERROR);
    PlayerManager.rejectStateWaiters(error.message);
    PlayerManager.handleLoadFailure();
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
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_INDEX, PlayerManager.orderIndex);
    PlayerManager.notify();
  }

  private static publishStatus(status: PlaybackStatus): void {
    PlayerManager.status = status;
    AppStorage.setOrCreate(PlaybackConstants.KEY_STATUS, status);
    AVSessionManager.updatePlaybackState(status, PlayerManager.positionMs);
    PlayerManager.notify();
  }

  private static publishPosition(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_POSITION_MS, PlayerManager.positionMs);
  }

  private static publishDuration(): void {
    AppStorage.setOrCreate(PlaybackConstants.KEY_DURATION_MS, PlayerManager.durationMs);
  }

  private static publishQueue(): void {
    const state = new QueueState(
      PlayerManager.queue,
      PlayerManager.order.length > 0 ? PlayerManager.order[Math.max(0, PlayerManager.orderIndex)] : 0,
      PlayerManager.repeatMode === RepeatMode.ONE,
      PlayerManager.shuffle
    );
    AppStorage.setOrCreate(PlaybackConstants.KEY_QUEUE_JSON, state.toJson());
    AppStorage.setOrCreate(PlaybackConstants.KEY_SHUFFLE, PlayerManager.shuffle);
    AppStorage.setOrCreate(PlaybackConstants.KEY_REPEAT_MODE, PlayerManager.repeatMode);
    PlayerManager.notify();
  }

  private static notify(): void {
    for (const listener of PlayerManager.listeners) {
      listener.onSnapshotChanged();
    }
  }
}
