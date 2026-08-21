/**
 * Platform seam for the two random identifiers listen together needs, ported
 * from listentogether/invite/ListenTogetherInviteBuilder.kt
 * (`buildListenTogetherUserUuid` / `buildDefaultListenTogetherNickname`).
 *
 * Kept apart from the pure invite logic: this is the only listentogether file
 * that imports a platform kit, so every parser/validator stays loadable in the
 * local hypium tests.
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
