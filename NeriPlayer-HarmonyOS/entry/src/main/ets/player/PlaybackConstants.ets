/**
 * AppStorage keys shared between PlayerManager and the ArkUI components.
 */
export class PlaybackConstants {
  static readonly KEY_CURRENT_SONG: string = 'player.currentSong';
  static readonly KEY_STATUS: string = 'player.status';
  static readonly KEY_POSITION_MS: string = 'player.positionMs';
  static readonly KEY_DURATION_MS: string = 'player.durationMs';
  static readonly KEY_QUEUE_INDEX: string = 'player.queueIndex';
  static readonly KEY_REPEAT_MODE: string = 'player.repeatMode';
  static readonly KEY_SHUFFLE: string = 'player.shuffle';
  static readonly KEY_SPEED: string = 'player.speed';
  static readonly KEY_QUEUE_JSON: string = 'player.queueJson';
}

export enum PlaybackStatus {
  IDLE = 0,
  LOADING = 1,
  PLAYING = 2,
  PAUSED = 3,
  COMPLETED = 4,
  ERROR = 5
}

export enum RepeatMode {
  OFF = 0,
  ONE = 1,
  ALL = 2
}
