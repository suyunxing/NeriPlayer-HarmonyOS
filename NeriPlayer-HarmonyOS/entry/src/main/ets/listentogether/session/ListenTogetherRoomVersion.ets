// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherRoomVersion.kt.
 *
 * The highest room version this client has ever accepted, whichever transport
 * delivered it. The live state alone is not enough: it can be replaced by a
 * synthetic state built locally, whose version may sit below one already seen.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';

export function latestListenTogetherAcceptedRoomVersion(
  lastAppliedRoomVersion: number,
  currentState: ListenTogetherRoomState | null
): number {
  return Math.max(lastAppliedRoomVersion, currentState === null ? -1 : currentState.version);
}
