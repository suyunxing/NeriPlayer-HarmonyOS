import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { PlaybackStatus } from './PlaybackConstants';

export interface SessionControlListener {
  onPlay(): void;
  onPause(): void;
  onNext(): void;
  onPrevious(): void;
  onSeek(timeMs: number): void;
}

/**
 * AVSession (media session) integration, equivalent of MediaSession in Android.
 * API 24: createAVSession uses the 'audio' session type string; transport
 * commands are play / pause / playNext / playPrevious / seek; playback state
 * uses the PLAYBACK_STATE_* enum values and a PlaybackPosition object.
 */
export class AVSessionManager {
  private static session: avSession.AVSession | null = null;
  private static controlListener: SessionControlListener | null = null;

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
      session.on('playNext', () => {
        AVSessionManager.controlListener?.onNext();
      });
      session.on('playPrevious', () => {
        AVSessionManager.controlListener?.onPrevious();
      });
      session.on('seek', (time: number) => {
        AVSessionManager.controlListener?.onSeek(time);
      });
      Logger.info('AVSessionManager initialized');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.init failed: ${e.message}`);
    }
  }

  static async updateMetadata(song: SongItem): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    try {
      const metadata: avSession.AVMetadata = {
        assetId: `${song.id}`,
        title: song.displayName,
        artist: song.displayArtist,
        album: song.album,
      };
      await session.setAVMetadata(metadata);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.updateMetadata failed: ${e.message}`);
    }
  }

  static async updatePlaybackState(status: PlaybackStatus, positionMs: number): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    try {
      const state = status === PlaybackStatus.PLAYING
        ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
        : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      const position: avSession.PlaybackPosition = {
        elapsedTime: positionMs,
        updateTime: Date.now(),
      };
      const playbackState: avSession.AVPlaybackState = {
        state: state,
        position: position,
        speed: 1.0,
      };
      await session.setAVPlaybackState(playbackState);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.updatePlaybackState failed: ${e.message}`);
    }
  }
}
