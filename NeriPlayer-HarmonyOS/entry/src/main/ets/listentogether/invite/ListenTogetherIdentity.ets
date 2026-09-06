/**
 * Platform seam for the random identifiers listen together needs, ported from
 * listentogether/invite/ListenTogetherInviteBuilder.kt
 * (`buildListenTogetherUserUuid` / `buildDefaultListenTogetherNickname`) and
 * listentogether/control/ListenTogetherEventFactory.kt
 * (`nextListenTogetherEventId`).
 *
 * Kept apart from the pure invite logic: this is the only listentogether file
 * that imports a platform kit, so every parser/validator stays loadable in the
 * local hypium tests. The event factory therefore takes an id factory as a
 * provider instead of calling this directly.
 */
import { util } from '@kit.ArkTS';
import { listenTogetherNicknameFromUuid } from './ListenTogetherInviteBuilder';

/** RFC 4122 v4 uuid, matching Android `UUID.randomUUID().toString()`. */
export function buildListenTogetherUserUuid(): string {
  return util.generateRandomUUID(false);
}

export function buildDefaultListenTogetherNickname(): string {
  return listenTogetherNicknameFromUuid(util.generateRandomUUID(false));
}

/**
 * Upstream `nextListenTogetherEventId()`. The timestamp prefix is not decoration:
 * it makes a captured event log sortable by eye, while the uuid is what actually
 * makes the id unique across two clients in the same millisecond.
 */
export function nextListenTogetherEventId(nowMs: number = Date.now()): string {
  return `evt-${nowMs}-${util.generateRandomUUID(false)}`;
}
