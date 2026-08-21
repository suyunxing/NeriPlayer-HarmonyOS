/**
 * Port of listentogether/protocol/ListenTogetherSessionModels.kt: the
 * client-local session snapshot exposed to the UI.
 *
 * The Kotlin enum carries @SerialName values; they become the ArkTS enum values
 * so the wire form is preserved without a separate mapping table.
 */

export enum ListenTogetherConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected'
}

export class ListenTogetherSessionState {
  baseUrl: string | null = null;
  roomId: string | null = null;
  userUuid: string | null = null;
  nickname: string | null = null;
  role: string | null = null;
  token: string | null = null;
  memberSecret: string | null = null;
  joinSecret: string | null = null;
  wsUrl: string | null = null;
  connectionState: ListenTogetherConnectionState = ListenTogetherConnectionState.DISCONNECTED;
  lastError: string | null = null;
  expectedPositionMs: number | null = null;
  roomNotice: string | null = null;
}

/** Kotlin `copy()` equivalent: callers mutate the clone before publishing it. */
export function cloneListenTogetherSessionState(
  state: ListenTogetherSessionState
): ListenTogetherSessionState {
  const copy = new ListenTogetherSessionState();
  copy.baseUrl = state.baseUrl;
  copy.roomId = state.roomId;
  copy.userUuid = state.userUuid;
  copy.nickname = state.nickname;
  copy.role = state.role;
  copy.token = state.token;
  copy.memberSecret = state.memberSecret;
  copy.joinSecret = state.joinSecret;
  copy.wsUrl = state.wsUrl;
  copy.connectionState = state.connectionState;
  copy.lastError = state.lastError;
  copy.expectedPositionMs = state.expectedPositionMs;
  copy.roomNotice = state.roomNotice;
  return copy;
}

/** Role strings compared verbatim by the session and control policies. */
export const LISTEN_TOGETHER_ROLE_CONTROLLER: string = 'controller';
export const LISTEN_TOGETHER_ROLE_LISTENER: string = 'listener';
