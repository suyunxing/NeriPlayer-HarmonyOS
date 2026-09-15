// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherMembershipCredential.kt.
 *
 * The credential is what lets a client re-attach to a room it already joined
 * (after a websocket drop or a process restart) without asking the server for a
 * new membership. Divergences forced by this port:
 * - the Kotlin extension `ListenTogetherSessionState.toMembershipCredentialOrNull()`
 *   becomes a free function taking the state first;
 * - the data class becomes a readonly class plus an explicit `…Equals` helper,
 *   since ArkTS classes compare by reference.
 *
 * `token`/`memberSecret`/`joinSecret` are secrets: never log them, and never put
 * them in an error message that could reach the UI.
 */
import { ListenTogetherSessionState } from '../protocol/ListenTogetherSessionModels';

export class ListenTogetherMembershipCredential {
  readonly baseUrl: string;
  readonly roomId: string;
  readonly userUuid: string;
  readonly token: string | null;
  readonly memberSecret: string | null;
  readonly joinSecret: string | null;

  constructor(
    baseUrl: string,
    roomId: string,
    userUuid: string,
    token: string | null,
    memberSecret: string | null,
    joinSecret: string | null
  ) {
    this.baseUrl = baseUrl;
    this.roomId = roomId;
    this.userUuid = userUuid;
    this.token = token;
    this.memberSecret = memberSecret;
    this.joinSecret = joinSecret;
  }
}

function blankToNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function equalsIgnoreCase(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

/** Kotlin data-class equality. */
export function listenTogetherMembershipCredentialEquals(
  left: ListenTogetherMembershipCredential,
  right: ListenTogetherMembershipCredential
): boolean {
  return left.baseUrl === right.baseUrl &&
    left.roomId === right.roomId &&
    left.userUuid === right.userUuid &&
    left.token === right.token &&
    left.memberSecret === right.memberSecret &&
    left.joinSecret === right.joinSecret;
}

/**
 * Null unless the session identifies a room member and carries at least one of
 * the two proofs the server accepts.
 */
export function listenTogetherMembershipCredentialOrNull(
  state: ListenTogetherSessionState
): ListenTogetherMembershipCredential | null {
  const normalizedBaseUrl = blankToNull(state.baseUrl);
  const normalizedRoomId = blankToNull(state.roomId);
  const normalizedUserUuid = blankToNull(state.userUuid);
  const normalizedToken = blankToNull(state.token);
  const normalizedMemberSecret = blankToNull(state.memberSecret);
  if (
    normalizedBaseUrl === null ||
    normalizedRoomId === null ||
    normalizedUserUuid === null ||
    (normalizedToken === null && normalizedMemberSecret === null)
  ) {
    return null;
  }
  return new ListenTogetherMembershipCredential(
    normalizedBaseUrl,
    normalizedRoomId,
    normalizedUserUuid,
    normalizedToken,
    normalizedMemberSecret,
    blankToNull(state.joinSecret)
  );
}

/**
 * Prefers the live session's credential over the retained one, and only reuses a
 * credential minted for the very same room and user.
 */
export function resolveReusableListenTogetherMembershipCredential(
  activeSession: ListenTogetherSessionState,
  retainedCredential: ListenTogetherMembershipCredential | null,
  baseUrl: string,
  roomId: string,
  userUuid: string
): ListenTogetherMembershipCredential | null {
  const expectedBaseUrl = baseUrl.trim();
  const expectedRoomId = roomId.trim();
  const expectedUserUuid = userUuid.trim();
  const candidates: (ListenTogetherMembershipCredential | null)[] = [
    listenTogetherMembershipCredentialOrNull(activeSession),
    retainedCredential
  ];
  for (const candidate of candidates) {
    if (candidate === null) {
      continue;
    }
    if (
      equalsIgnoreCase(candidate.baseUrl, expectedBaseUrl) &&
      equalsIgnoreCase(candidate.roomId, expectedRoomId) &&
      equalsIgnoreCase(candidate.userUuid, expectedUserUuid)
    ) {
      return candidate;
    }
  }
  return null;
}
