/**
 * Port of listentogether/invite/ListenTogetherInviteBuilder.kt.
 *
 * Android's `Uri.Builder.appendQueryParameter` leaves exactly
 * `A-Za-z0-9-_.!~*'()` unescaped, which is the same set as
 * `encodeURIComponent`, so the produced links are byte-identical.
 *
 * Parameter order differs from Kotlin (`joinSecret` moved ahead of the two
 * optional arguments) because ArkTS requires optional parameters last.
 */
import {
  requireValidListenTogetherJoinSecret,
  requireValidListenTogetherNickname,
  requireValidListenTogetherRoomId
} from '../validation/ListenTogetherFieldValidation';
import { normalizeListenTogetherBaseUrl } from '../network/ListenTogetherBaseUrl';
import { isDefaultListenTogetherBaseUrl } from './ListenTogetherBaseUrlResolver';

export const LISTEN_TOGETHER_INVITE_SCHEME: string = 'neriplayer';
export const LISTEN_TOGETHER_INVITE_HOST: string = 'listen-together';
export const LISTEN_TOGETHER_INVITE_JOIN_PATH: string = 'join';

/** `"Neri" + first 6 hex chars of a v4 uuid`, upper-cased. */
export function listenTogetherNicknameFromUuid(rawUuid: string): string {
  const hex = rawUuid.split('-').join('');
  return `Neri${hex.substring(0, 6).toUpperCase()}`;
}

export function buildListenTogetherInviteUri(
  roomId: string,
  joinSecret: string,
  inviterNickname: string | null = null,
  baseUrl: string | null = null
): string {
  const normalizedRoomId = requireValidListenTogetherRoomId(roomId);
  const normalizedJoinSecret = requireValidListenTogetherJoinSecret(joinSecret);
  let normalizedBaseUrl: string | null = null;
  if (baseUrl !== null && baseUrl.trim().length > 0) {
    // Throws for a malformed URL, exactly like Kotlin `normalizeBaseUrl()`.
    const candidate = normalizeListenTogetherBaseUrl(baseUrl);
    normalizedBaseUrl = isDefaultListenTogetherBaseUrl(candidate) ? null : candidate;
  }
  let query = `roomId=${encodeURIComponent(normalizedRoomId)}`;
  if (inviterNickname !== null && inviterNickname.trim().length > 0) {
    const validated = requireValidListenTogetherNickname(inviterNickname);
    query += `&inviter=${encodeURIComponent(validated)}`;
  }
  if (normalizedBaseUrl !== null) {
    query += `&baseUrl=${encodeURIComponent(normalizedBaseUrl)}`;
  }
  query += `&secret=${encodeURIComponent(normalizedJoinSecret)}`;
  const prefix = `${LISTEN_TOGETHER_INVITE_SCHEME}://${LISTEN_TOGETHER_INVITE_HOST}`;
  return `${prefix}/${LISTEN_TOGETHER_INVITE_JOIN_PATH}?${query}`;
}
