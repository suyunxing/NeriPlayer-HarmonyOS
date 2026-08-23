import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { RepeatMode, PlaybackStatus } from './PlaybackConstants';

export interface SessionControlListener {
  onPlay(): void;
  onPause(): void;
  onStop(): void;
  onNext(): void;
  onPrevious(): void;
  onSeek(timeMs: number): void;
  onSpeed(speed: number): void;
  onLoopMode(mode: RepeatMode): void;
}

/**
 * AVSession (media session) integration, equivalent of MediaSession in the
 * Android app: rich metadata (cover/duration), full playback-state mapping
 * (prepare/play/pause/completed/error), speed/loop sync and paired
 * unregister/destroy cleanup.
 */
export class AVSessionManager {
  private static session: avSession.AVSession | null = null;
  private static controlListener: SessionControlListener | null = null;
  // Last lyric line pushed via metadata title (Android "bluetooth lyrics"
  // slot); guards against re-sending identical metadata every position tick.
  private static lastLyricLine: string = '';

  static async init(context: common.UIAbilityContext, listener: SessionControlListener): Promise<void> {
    AVSessionManager.controlListener = listener;
    if (AVSessionManager.session !== null) {
      return;
    }
    try {
      const session = await avSession.createAVSession(context, 'NeriPlayer', 'audio');
      AVSessionManager.session = session;
      await session.activate();
      session.on('play', () => {
        AVSessionManager.controlListener?.onPlay();
      });
      session.on('pause', () => {
        AVSessionManager.controlListener?.onPause();
      });
      session.on('stop', () => {
        AVSessionManager.controlListener?.onStop();
      });
      session.on('playNext', () => {
        AVSessionManager.controlListener?.onNext();
      });
      session.on('playPrevious', () => {
        AVSessionManager.controlListener?.onPrevious();
      });
      session.on('seek', (time: number) => {
        AVSessionManager.controlListener?.onSeek(time);
      });
      session.on('setSpeed', (speed: number) => {
        AVSessionManager.controlListener?.onSpeed(speed);
      });
      session.on('setLoopMode', (mode: avSession.LoopMode) => {
        const repeatMode = AVSessionManager.toRepeatMode(mode);
        if (repeatMode !== null) {
          AVSessionManager.controlListener?.onLoopMode(repeatMode);
        }
      });
      Logger.info('AVSessionManager initialized');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.init failed: ${e.message}`);
    }
  }

  /**
   * Unregisters every command listener and destroys the session; call from
   * ability onDestroy. Safe to call multiple times.
   */
  static async release(): Promise<void> {
    const session = AVSessionManager.session;
    AVSessionManager.session = null;
    if (session === null) {
      return;
    }
    try {
      // off() only accepts literal event names, so they are listed here
      // explicitly and must stay in sync with init().
      session.off('play');
      session.off('pause');
      session.off('stop');
      session.off('playNext');
      session.off('playPrevious');
      session.off('seek');
      session.off('setSpeed');
      session.off('setLoopMode');
      await session.destroy();
      Logger.info('AVSessionManager released');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.release failed: ${e.message}`);
    }
  }

  static async updateMetadata(song: SongItem, durationMs: number): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    AVSessionManager.lastLyricLine = '';
    try {
      const metadata: avSession.AVMetadata = {
        // Stable across platforms: a bare numeric id would collide between
        // Netease/Bili/YTM sources.
        assetId: `${song.platform}:${song.id}:${song.mediaUri}`,
        title: song.displayName,
        artist: song.displayArtist,
        album: song.album,
        duration: durationMs,
      };
      const cover = song.effectiveCoverUrl;
      if (cover.length > 0) {
        metadata.mediaImage = cover;
      }
      await session.setAVMetadata(metadata);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.updateMetadata failed: ${e.message}`);
    }
  }

  /**
   * Publishes the current lyric line through the session title (and the
   * "song - artist" credits through artist), which the system player
   * surfaces in the notification/control center and remote AVRCP devices.
   * `null` restores the real song metadata. Deliberately global (no
   * audio-output-device gating, unlike Android's bluetooth-only behavior):
   * the feature is user-toggled (np.bt_lyric), see FEATURE_MATRIX.
   */
  static async updateLyricLine(lineText: string | null, song: SongItem, durationMs: number): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    if (lineText === null) {
      if (AVSessionManager.lastLyricLine.length === 0) {
        return;
      }
      AVSessionManager.lastLyricLine = '';
      await AVSessionManager.updateMetadata(song, durationMs);
      return;
    }
    if (lineText === AVSessionManager.lastLyricLine) {
      return;
    }
    AVSessionManager.lastLyricLine = lineText;
    try {
      const metadata: avSession.AVMetadata = {
        assetId: `${song.platform}:${song.id}:${song.mediaUri}`,
        title: lineText,
        artist: `${song.displayName} - ${song.displayArtist}`,
        album: song.album,
        duration: durationMs,
      };
      const cover = song.effectiveCoverUrl;
      if (cover.length > 0) {
        metadata.mediaImage = cover;
      }
      await session.setAVMetadata(metadata);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.updateLyricLine failed: ${e.message}`);
    }
  }

  static async updatePlaybackState(
    status: PlaybackStatus,
    positionMs: number,
    speed: number,
    durationMs: number,
    repeatMode: RepeatMode
  ): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    try {
      const playbackState: avSession.AVPlaybackState = {
        state: AVSessionManager.toSessionState(status),
        position: {
          elapsedTime: positionMs,
          updateTime: Date.now(),
        },
        speed: speed,
        // The system derives the progress bar from duration + position.
        duration: durationMs,
        loopMode: AVSessionManager.toLoopMode(repeatMode),
      };
      await session.setAVPlaybackState(playbackState);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.updatePlaybackState failed: ${e.message}`);
    }
  }

  private static toSessionState(status: PlaybackStatus): avSession.PlaybackState {
    switch (status) {
      case PlaybackStatus.LOADING:
        return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
      case PlaybackStatus.PLAYING:
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
      case PlaybackStatus.COMPLETED:
        return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
      case PlaybackStatus.ERROR:
        return avSession.PlaybackState.PLAYBACK_STATE_ERROR;
      case PlaybackStatus.PAUSED:
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      default:
        return avSession.PlaybackState.PLAYBACK_STATE_INITIAL;
    }
  }

  private static toLoopMode(mode: RepeatMode): avSession.LoopMode {
    if (mode === RepeatMode.ONE) {
      return avSession.LoopMode.LOOP_MODE_SINGLE;
    }
    if (mode === RepeatMode.OFF) {
      return avSession.LoopMode.LOOP_MODE_SEQUENCE;
    }
    return avSession.LoopMode.LOOP_MODE_LIST;
  }

  private static toRepeatMode(mode: avSession.LoopMode): RepeatMode | null {
    if (mode === avSession.LoopMode.LOOP_MODE_SINGLE) {
      return RepeatMode.ONE;
    }
    if (mode === avSession.LoopMode.LOOP_MODE_SEQUENCE) {
      return RepeatMode.OFF;
    }
    if (mode === avSession.LoopMode.LOOP_MODE_LIST) {
      return RepeatMode.ALL;
    }
    // SHUFFLE / CUSTOM have no RepeatMode equivalent yet.
    return null;
  }
}
