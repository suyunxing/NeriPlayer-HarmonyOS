/**
 * Port of ListenTogetherSessionManager.kt's listener-membership recovery gates
 * (`maybeRecoverMissingListenerMembership`, `maybeRecoverFromFatalMembershipError`,
 * `triggerListenerMembershipRecovery`).
 *
 * Only the decisions live here. The recovery *act* — cancelling reconnect,
 * stopping the heartbeat, disconnecting with code 1000 `listener_recovering`,
 * rejoining over HTTP — is runtime wiring and belongs to the session manager
 * (M7.3b-3), as does the idempotence guard on the in-flight recovery job. What is
 * worth testing offline is exactly what upstream buries in early returns: *when*
 * a listener has silently fallen out of a room it still believes it is in.
 *
 * The failure this guards against is quiet rather than loud. A listener whose
 * membership the worker has dropped keeps receiving broadcasts and keeps playing
 * in sync; nothing is visibly wrong until it tries to send a control request and
 * is told it is not a member. Recovery is therefore driven from two independent
 * signals — a state snapshot that does not list us, and an error string that says
 * so outright.
 */
import { ListenTogetherRoomState, ListenTogetherRoomStatuses } from '../protocol/ListenTogetherRoomModels';

/**
 * Upstream matches these two substrings, lowercased and trimmed, against
 * whatever the worker returned. Substring rather than equality because the text
 * arrives wrapped in an HTTP or socket error envelope.
 */
const FATAL_MEMBERSHIP_ERROR_FRAGMENTS: string[] = ['member not in room', 'member missing'];

function blankToNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * A member matches us when its uuid matches, or — for a member the worker
 * recorded before uuids existed — when its legacy `userId` does. Upstream's
 * `it.userUuid.ifBlank { it.userId.orEmpty() }` compares only one of the two, the
 * uuid taking precedence, so a member carrying *both* a blank uuid and a matching
 * userId still counts as us.
 */
function memberIdentifiesUser(memberUserUuid: string, memberUserId: string | null, userUuid: string): boolean {
  const uuid = blankToNull(memberUserUuid);
  if (uuid !== null) {
    return uuid === userUuid;
  }
  const legacy = blankToNull(memberUserId);
  return legacy !== null && legacy === userUuid;
}

/**
 * True when this room snapshot proves the local listener is no longer a member,
 * so a rejoin is warranted. Upstream `maybeRecoverMissingListenerMembership()`,
 * with its four early returns preserved in order:
 *
 * 1. No local uuid — we never joined, so there is nothing to recover.
 * 2. We are the controller — the controller's own membership is not tracked this
 *    way, and rejoining as one would hand the room to nobody mid-flight.
 * 3. The room is CLOSED — the members list is *expected* to be empty, and
 *    rejoining a closed room would loop.
 * 4. We are in the list — the ordinary case.
 */
export function shouldRecoverMissingListenTogetherMembership(
  state: ListenTogetherRoomState,
  sessionUserUuid: string | null,
  isCurrentUserController: boolean
): boolean {
  const userUuid = blankToNull(sessionUserUuid);
  if (userUuid === null) {
    return false;
  }
  if (isCurrentUserController) {
    return false;
  }
  if (state.roomStatus === ListenTogetherRoomStatuses.CLOSED) {
    return false;
  }
  for (const member of state.members) {
    if (memberIdentifiesUser(member.userUuid, member.userId, userUuid)) {
      return false;
    }
  }
  return true;
}

/**
 * True when an error text is the worker saying our membership is gone. Upstream
 * `maybeRecoverFromFatalMembershipError()`.
 *
 * Note this is *not* one of the terminal reconnect errors: a terminal error
 * closes the room locally, while this one is recoverable by rejoining, which is
 * why the two predicates stay separate even though both read error strings.
 */
export function isFatalListenTogetherMembershipError(errorMessage: string | null): boolean {
  const normalized = errorMessage === null ? '' : errorMessage.trim().toLowerCase();
  if (normalized.length === 0) {
    return false;
  }
  for (const fragment of FATAL_MEMBERSHIP_ERROR_FRAGMENTS) {
    if (normalized.includes(fragment)) {
      return true;
    }
  }
  return false;
}

/**
 * The session-completeness half of upstream `triggerListenerMembershipRecovery()`:
 * all four fields are needed to rejoin, and a controller never rejoins as a
 * listener. Returning false here is upstream's "skipped, missing session" branch.
 *
 * The job-already-active branch is deliberately absent — it is live runtime state,
 * not a decision, and upstream returns *true* for it (the recovery is considered
 * under way), which a pure predicate cannot express without lying.
 */
export function canTriggerListenTogetherMembershipRecovery(
  baseUrl: string | null,
  roomId: string | null,
  userUuid: string | null,
  nickname: string | null,
  isCurrentUserController: boolean
): boolean {
  if (isCurrentUserController) {
    return false;
  }
  return (
    blankToNull(baseUrl) !== null &&
    blankToNull(roomId) !== null &&
    blankToNull(userUuid) !== null &&
    blankToNull(nickname) !== null
  );
}
