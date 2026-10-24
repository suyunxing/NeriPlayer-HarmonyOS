// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherAuthoritativeStreamAvailability.kt
 * (upstream #359, squashed 3cfd7037): confirmation ledger for
 * "the controller has no shareable link for this track".
 *
 * A single LINK_UNAVAILABLE is not trusted (it may race a late resolution);
 * two signals with distinct ids confirm it, and any authoritative stream (or a
 * target change) clears the record. Divergence: the Kotlin `synchronized`
 * blocks collapse — this port runs on the single-threaded event loop.
 */
class UnavailableRecord {
  readonly roomId: string;
  readonly stableKey: string;
  signalCount: number;
  lastSignalId: string | null;

  constructor(roomId: string, stableKey: string, signalCount: number, lastSignalId: string | null) {
    this.roomId = roomId;
    this.stableKey = stableKey;
    this.signalCount = signalCount;
    this.lastSignalId = lastSignalId;
  }

  isConfirmed(): boolean {
    return this.signalCount >= 2;
  }
}

function normalizedOrNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export class ListenTogetherAuthoritativeStreamAvailability {
  private unavailableRecord: UnavailableRecord | null = null;

  /**
   * Records one unavailability signal; true when this signal *confirmed* the
   * target unavailable (the second distinct signal).
   */
  markUnavailable(roomId: string | null, stableKey: string | null, signalId: string | null = null): boolean {
    const normalizedRoomId = normalizedOrNull(roomId);
    const normalizedStableKey = normalizedOrNull(stableKey);
    if (normalizedRoomId === null || normalizedStableKey === null) {
      this.unavailableRecord = null;
      return false;
    }
    const normalizedSignalId = normalizedOrNull(signalId);
    const previous = this.unavailableRecord;
    let confirmed: boolean;
    if (previous === null || previous.roomId !== normalizedRoomId || previous.stableKey !== normalizedStableKey) {
      this.unavailableRecord = new UnavailableRecord(normalizedRoomId, normalizedStableKey, 1, normalizedSignalId);
      confirmed = false;
    } else if (normalizedSignalId !== null && normalizedSignalId !== previous.lastSignalId) {
      previous.signalCount++;
      previous.lastSignalId = normalizedSignalId;
      confirmed = previous.isConfirmed();
    } else {
      confirmed = previous.isConfirmed();
    }
    return confirmed;
  }

  /** Any authoritative stream — or a target switch — clears the record. */
  reconcile(roomId: string | null, stableKey: string | null, hasAuthoritativeStream: boolean): void {
    const unavailable = this.unavailableRecord;
    if (unavailable === null) {
      return;
    }
    const normalizedRoomId = normalizedOrNull(roomId);
    const normalizedStableKey = normalizedOrNull(stableKey);
    const sameTarget = normalizedRoomId === unavailable.roomId && normalizedStableKey === unavailable.stableKey;
    if (hasAuthoritativeStream || !sameTarget) {
      this.unavailableRecord = null;
    }
  }

  isUnavailable(roomId: string | null, stableKey: string | null): boolean {
    return this.matchesRecord(roomId, stableKey, true);
  }

  isAwaitingConfirmation(roomId: string | null, stableKey: string | null): boolean {
    return this.matchesRecord(roomId, stableKey, false);
  }

  clear(): void {
    this.unavailableRecord = null;
  }

  private matchesRecord(roomId: string | null, stableKey: string | null, confirmed: boolean): boolean {
    const normalizedRoomId = normalizedOrNull(roomId);
    const normalizedStableKey = normalizedOrNull(stableKey);
    const record = this.unavailableRecord;
    return record !== null &&
      record.roomId === normalizedRoomId &&
      record.stableKey === normalizedStableKey &&
      record.isConfirmed() === confirmed;
  }
}
