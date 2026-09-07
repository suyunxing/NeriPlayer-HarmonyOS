import { QueueEngine } from './queue/QueueEngine';
import { RepeatMode } from './PlaybackConstants';

/**
 * Pure policy for the API 26 native-playlist bridge (AvPlaylistBridge).
 *
 * The native playlist (addPlaybackMediaSource / advanceToNextMediaSource,
 * @since 26) is used as a *transport accelerator* only: the QueueEngine keeps
 * deciding what plays next (sleep timer, listen-together room and repeat-one
 * replay all arbitrate before any advance), and the bridge swaps the media
 * inside the kernel without loadSong's reset/prepare cycle. The functions
 * here answer the two questions the glue layer must not improvise on:
 * - what index would the engine advance to (without mutating it), and
 * - whether an entry is eligible for gapless priming at all.
 */

/**
 * Whether the natural-advance path asks the engine for a forced next.
 * Mirrors the `auto` computation inside PlayerManager.next(): under
 * repeat-all the queue wraps/rebuilds, otherwise it only moves while tracks
 * remain. Kept beside peekNextIndex so a drift between the two would break
 * a unit test, not a gapless skip.
 */
export function advanceForceFor(repeatMode: RepeatMode): boolean {
  return repeatMode === RepeatMode.ALL;
}

/**
 * Predicts the queue index engine.next(force) will land on, without touching
 * the live engine: QueueEngine.toJson()/fromJson() round-trips the whole
 * state machine *including the seeded random state*, so even the next shuffle
 * pick is reproduced exactly on the clone. -1 when the engine would not
 * advance.
 */
export function peekNextIndex(engine: QueueEngine, force: boolean): number {
  const clone = QueueEngine.fromJson(engine.toJson(), engine.getQueueSize());
  if (clone === null) {
    return -1;
  }
  return clone.next(force);
}

/** Inputs of the priming decision; every gate is explicit so tests can pin them. */
export interface PrimeNextInput {
  queueLength: number;
  repeatMode: RepeatMode;
  /** Predicted next index (peekNextIndex), -1 when the engine would stop. */
  nextIndex: number;
  /** A listen-together session drives "next" through the room, never locally. */
  listenTogetherActive: boolean;
  /**
   * The next entry resolves without network (downloaded catalog file or
   * local-media path). Network streams are never primed: pre-resolving would
   * hit the platform APIs once per song (risk control) and signed URLs would
   * likely expire before the advance fires.
   */
  nextOfflineAvailable: boolean;
}

export function shouldPrimeNext(input: PrimeNextInput): boolean {
  if (input.repeatMode === RepeatMode.ONE) {
    // Track end replays the same source; there is nothing to hand over.
    return false;
  }
  if (input.queueLength < 2) {
    return false;
  }
  if (input.listenTogetherActive) {
    return false;
  }
  if (input.nextIndex < 0) {
    // Repeat off at the tail: the engine will stop, not advance.
    return false;
  }
  return input.nextOfflineAvailable;
}
