/**
 * Port of listentogether/validation/ListenTogetherValidationError.kt.
 *
 * Android carries a @StringRes id plus format args and resolves the text through
 * a Context. Validation here must stay callable from the local hypium tests (no
 * resource manager, no platform imports), so the error keeps a stable code for
 * programmatic checks and a pre-formatted message for the UI. The texts are the
 * verbatim `listen_together_error_*` strings from the Android default resources.
 */

export enum ListenTogetherValidationCode {
  ROOM_ID_LENGTH = 'room_id_length',
  ROOM_ID_CHARS = 'room_id_chars',
  NICKNAME_LENGTH = 'nickname_length',
  NICKNAME_CHARS = 'nickname_chars',
  JOIN_SECRET_REQUIRED = 'join_secret_required',
  JOIN_SECRET_LENGTH = 'join_secret_length',
  USER_UUID_REQUIRED = 'user_uuid_required',
  USER_UUID_INVALID = 'user_uuid_invalid',
  CURRENT_TRACK_MISSING = 'current_track_missing',
  CURRENT_TRACK_NOT_SHAREABLE = 'current_track_not_shareable',
  CURRENT_TRACK_UNAVAILABLE = 'current_track_unavailable'
}

export class ListenTogetherValidationError {
  readonly code: ListenTogetherValidationCode;
  readonly message: string;

  constructor(code: ListenTogetherValidationCode, message: string) {
    this.code = code;
    this.message = message;
  }
}

/** Thrown by the `require*` helpers, mirroring Kotlin `error(...)`. */
export class ListenTogetherValidationFailure extends Error {
  readonly code: ListenTogetherValidationCode;

  constructor(error: ListenTogetherValidationError) {
    super(error.message);
    this.name = 'ListenTogetherValidationFailure';
    this.code = error.code;
  }
}

function argAt(args: number[], index: number): number {
  return index < args.length ? args[index] : 0;
}

function formatListenTogetherValidationMessage(
  code: ListenTogetherValidationCode,
  args: number[]
): string {
  switch (code) {
    case ListenTogetherValidationCode.ROOM_ID_LENGTH:
      return `房间 ID 需要为 ${argAt(args, 0)} 位`;
    case ListenTogetherValidationCode.ROOM_ID_CHARS:
      return '房间 ID 仅支持大写字母和数字';
    case ListenTogetherValidationCode.NICKNAME_LENGTH:
      return `当前昵称长度需要为 ${argAt(args, 0)}-${argAt(args, 1)} 位`;
    case ListenTogetherValidationCode.NICKNAME_CHARS:
      return '当前昵称仅支持汉字、英文字母和数字';
    case ListenTogetherValidationCode.JOIN_SECRET_REQUIRED:
      return '邀请密钥不能为空';
    case ListenTogetherValidationCode.JOIN_SECRET_LENGTH:
      return `邀请密钥不能超过 ${argAt(args, 0)} 个字符`;
    case ListenTogetherValidationCode.USER_UUID_REQUIRED:
      return '用户 UUID 不能为空';
    case ListenTogetherValidationCode.USER_UUID_INVALID:
      return '用户 UUID 格式无效';
    case ListenTogetherValidationCode.CURRENT_TRACK_MISSING:
      return '当前没有正在播放的歌曲，无法创建一起听';
    case ListenTogetherValidationCode.CURRENT_TRACK_NOT_SHAREABLE:
      return '本地或无法分享的歌曲不能创建一起听，请切换到在线歌曲';
    case ListenTogetherValidationCode.CURRENT_TRACK_UNAVAILABLE:
      return '当前歌曲不在播放队列中，无法创建一起听';
    default:
      return '一起听参数校验失败';
  }
}

export function listenTogetherValidationError(
  code: ListenTogetherValidationCode,
  args: number[] = []
): ListenTogetherValidationError {
  return new ListenTogetherValidationError(code, formatListenTogetherValidationMessage(code, args));
}

/** `error(it.formatForApp())` equivalent used by every `require*` helper. */
export function throwListenTogetherValidation(error: ListenTogetherValidationError): void {
  throw new ListenTogetherValidationFailure(error);
}
