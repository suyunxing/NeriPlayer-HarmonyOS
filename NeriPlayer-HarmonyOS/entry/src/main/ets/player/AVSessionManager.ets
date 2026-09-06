import { avSession } from '@kit.AVSessionKit';
import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { LyricLine } from '../model/LyricLine';
import { LrcParser } from '../lyrics/LrcParser';
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
  /**
   * Favorite toggled from the media control center. `assetId` is the id this
   * manager published in AVMetadata, so the listener can map it back to a
   * queue entry (see AVSessionManager.assetIdOf).
   */
  onToggleFavorite(assetId: string): void;
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
  // Last lyric line pushed via AVMetadata.singleLyricText; guards against
  // re-sending identical metadata every position tick.
  private static lastLyricLine: string = '';
  // Whole-song LRC published through AVMetadata.lyric (the scrolling-lyrics
  // source for the media control center). Kept so that the per-line updates
  // can re-send it without re-serializing.
  private static currentLyric: string = '';
  // Track length last published through AVMetadata.duration. setAVMetadata
  // replaces the whole record, so every partial update (lyric, single line)
  // has to re-send this value rather than take it from its caller.
  private static durationMs: number = 0;
  private static favorite: boolean = false;

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
      // Registering the command is what makes the control center render an
      // interactive favorite button (unregistered commands are greyed out).
      session.on('toggleFavorite', (assetId: string) => {
        AVSessionManager.controlListener?.onToggleFavorite(assetId);
      });
      await AVSessionManager.bindLaunchAbility(context, session);
      Logger.info('AVSessionManager initialized');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.init failed: ${e.message}`);
    }
  }

  /**
   * Makes the media control card launch this app when tapped (the official
   * playback-control checklist requires the card to open a specific page).
   * UPDATE_PRESENT_FLAG so a re-created agent replaces the extras of the
   * existing one instead of piling up.
   */
  private static async bindLaunchAbility(
    context: common.UIAbilityContext,
    session: avSession.AVSession
  ): Promise<void> {
    try {
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: { 'np.launch_from': 'avsession' },
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await session.setLaunchAbility(agent);
    } catch (error) {
      const e = error as Error;
      // Non-fatal: the session still works, the card just is not tappable.
      Logger.warn(`AVSessionManager.bindLaunchAbility failed: ${e.message}`);
    }
  }

  /**
   * Unregisters every command listener and destroys the session; call from
   * ability onDestroy. Safe to call multiple times.
   */
  static async release(): Promise<void> {
    const session = AVSessionManager.session;
    AVSessionManager.session = null;
    AVSessionManager.lastLyricLine = '';
    AVSessionManager.currentLyric = '';
    AVSessionManager.durationMs = 0;
    AVSessionManager.favorite = false;
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
      session.off('toggleFavorite');
      await session.destroy();
      Logger.info('AVSessionManager released');
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.release failed: ${e.message}`);
    }
  }

  /** Stable across platforms: a bare numeric id would collide between sources. */
  static assetIdOf(song: SongItem): string {
    return `${song.platform}:${song.id}:${song.mediaUri}`;
  }

  /**
   * Publishes the whole-song lyric (standard LRC) that the system renders as
   * scrolling lyrics in the media control center. Call on lyric load; pass an
   * empty array to clear. Re-sends the metadata so the change takes effect,
   * preserving whatever single line is currently displayed.
   */
  static async updateLyrics(lines: LyricLine[], song: SongItem): Promise<void> {
    const lyric = lines.length > 0 ? LrcParser.serialize(lines) : '';
    if (lyric === AVSessionManager.currentLyric) {
      return;
    }
    AVSessionManager.currentLyric = lyric;
    await AVSessionManager.pushMetadata(song, AVSessionManager.lastLyricLine);
  }

  /**
   * Call on track change: resets the lyric caches (the previous song's lyrics
   * must not linger on the new one) and republishes the metadata. The duration
   * is reset unconditionally, even to 0: the new song's real length is unknown
   * until the player reports it through updateDuration.
   */
  static async updateMetadata(song: SongItem, durationMs: number): Promise<void> {
    AVSessionManager.lastLyricLine = '';
    AVSessionManager.currentLyric = '';
    AVSessionManager.durationMs = durationMs;
    await AVSessionManager.pushMetadata(song, '');
  }

  /**
   * Publishes the track length. Kept as its own entry point because every
   * setAVMetadata call replaces the whole record: when the lyric or the single
   * line is republished it must reuse the cached duration, otherwise a caller
   * that happens to hold 0 (a queue restored but not yet prepared) would reset
   * the control center's progress bar to 0:00.
   */
  static async updateDuration(song: SongItem, durationMs: number): Promise<void> {
    if (durationMs === AVSessionManager.durationMs) {
      return;
    }
    AVSessionManager.durationMs = durationMs;
    await AVSessionManager.pushMetadata(song, AVSessionManager.lastLyricLine);
  }

  /**
   * Publishes the current lyric line through AVMetadata.singleLyricText (the
   * documented "single lyric text, not including time prefix" field, @since
   * 17), which the system surfaces in the notification/control center and on
   * remote AVRCP devices. `null` clears the line. Deliberately global (no
   * audio-output-device gating, unlike Android's bluetooth-only behavior):
   * the feature is user-toggled (np.bt_lyric), see FEATURE_MATRIX.
   *
   * Unlike the earlier implementation this no longer squats on `title` /
   * `artist`, so the song name stays correct while lyrics scroll.
   */
  static async updateLyricLine(lineText: string | null, song: SongItem): Promise<void> {
    const line = lineText === null ? '' : lineText;
    if (line === AVSessionManager.lastLyricLine) {
      return;
    }
    AVSessionManager.lastLyricLine = line;
    await AVSessionManager.pushMetadata(song, line);
  }

  private static async pushMetadata(song: SongItem, lyricLine: string): Promise<void> {
    const session = AVSessionManager.session;
    if (session === null) {
      return;
    }
    try {
      await session.setAVMetadata(AVSessionManager.buildMetadata(song, lyricLine));
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AVSessionManager.pushMetadata failed: ${e.message}`);
    }
  }

  private static buildMetadata(song: SongItem, lyricLine: string): avSession.AVMetadata {
    const metadata: avSession.AVMetadata = {
      assetId: AVSessionManager.assetIdOf(song),
      title: song.displayName,
      artist: song.displayArtist,
      album: song.album,
      duration: AVSessionManager.durationMs,
    };
    const cover = song.effectiveCoverUrl;
    if (cover.length > 0) {
      metadata.mediaImage = cover;
    }
    if (AVSessionManager.currentLyric.length > 0) {
      metadata.lyric = AVSessionManager.currentLyric;
    }
    if (lyricLine.length > 0) {
      metadata.singleLyricText = lyricLine;
    }
    return metadata;
  }

  /**
   * Caches the favorite state reported alongside every playback state, so the
   * control center's favorite button renders filled/empty correctly.
   */
  static setFavorite(favorite: boolean): void {
    AVSessionManager.favorite = favorite;
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
        isFavorite: AVSessionManager.favorite,
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
