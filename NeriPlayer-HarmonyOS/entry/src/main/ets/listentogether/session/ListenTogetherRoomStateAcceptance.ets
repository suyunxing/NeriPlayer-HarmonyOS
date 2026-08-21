/**
 * Port of listentogether/session/ListenTogetherRoomStateAcceptance.kt: the
 * result of the version gate, plus which transport a state arrived on.
 *
 * The Kotlin enum pairs each constant with a `logName`; here the enum value *is*
 * the log name, so the log text cannot drift from the constant. These strings
 * only ever reach the log, never the wire.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';

/**
 * A room state that passed the version gate. `expectedPositionMs` is the
 * server-computed position that came with it, absent when the transport did not
 * carry one — the player then extrapolates from the playback base instead.
 */
export class ListenTogetherAcceptedRoomState {
  readonly state: ListenTogetherRoomState;
  readonly expectedPositionMs: number | null;

  constructor(state: ListenTogetherRoomState, expectedPositionMs: number | null = null) {
    this.state = state;
    this.expectedPositionMs = expectedPositionMs;
  }
}

export enum ListenTogetherRoomStateSource {
  HTTP_REFRESH = 'http_refresh',
  HTTP_CONTROL_FALLBACK = 'http_control_fallback',
  HTTP_SESSION_UPDATE = 'http_session_update',
  WEB_SOCKET_STATE = 'websocket_state',
  WEB_SOCKET_CONTROL_RESULT = 'websocket_control_result',
  WEB_SOCKET_ROOM_STATUS = 'websocket_room_status',
  WEB_SOCKET_ROOM_CLOSED = 'websocket_room_closed',
  LOCAL_SYNTHETIC = 'local_synthetic'
}
