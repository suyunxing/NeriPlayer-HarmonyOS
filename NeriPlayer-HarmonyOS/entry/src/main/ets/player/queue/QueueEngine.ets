// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { RepeatMode } from '../PlaybackConstants';

/**
 * Deterministic shuffle/random source. Mirrors kotlin.random.Random enough
 * for queue purposes: same seed produces the same pick sequence, so engine
 * snapshots stay reproducible in tests.
 */
export class SeededRandom {
  private state: number;

  constructor(seed: number) {
    // LCG constants from Numerical Recipes; avoid the fixed point at 0.
    this.state = (seed >>> 0) === 0 ? 1 : seed >>> 0;
  }

  nextInt(bound: number): number {
    this.state = (Math.imul(this.state, 1664525) + 1013904223) >>> 0;
    return this.state % bound;
  }

  getState(): number {
    return this.state;
  }

  setState(state: number): void {
    this.state = (state >>> 0) === 0 ? 1 : state >>> 0;
  }
}

/** What the engine wants when the current track finishes naturally. */
export enum TrackEndAction {
  /** Repeat one: replay the same track. */
  REPLAY = 0,
  /** Advance with force (wrap/rebuild allowed). */
  ADVANCE = 1,
  /** Queue exhausted under repeat off: stop but keep the queue. */
  STOP = 2
}

/** Remapped shuffle index lists after an insert-as-next queue mutation. */
export class ShuffleIndexState {
  bag: number[];
  history: number[];
  future: number[];

  constructor(bag: number[], history: number[], future: number[]) {
    this.bag = bag;
    this.history = history;
    this.future = future;
  }
}

/**
 * Pure playback queue state machine (no @ohos APIs): shuffle bag / history /
 * future, repeat policy, next/prev advancement and index remapping for queue
 * mutations. Ported from PlayerManager + PlayerManagerPlaybackExtensions.
 *
 * Invariants (matching Android):
 * - indices refer to positions in the song queue;
 * - the currently playing index is never inside the bag;
 * - history is a backtrack stack for previous(), future is a LIFO stack of
 *   indices parked by previous() or queued by play-next insertions.
 */
export class QueueEngine {
  private bag: number[] = [];
  private history: number[] = [];
  private future: number[] = [];
  private queueSize: number = 0;
  private random: SeededRandom;

  currentIndex: number = -1;
  shuffle: boolean = false;
  repeatMode: RepeatMode = RepeatMode.ALL;

  constructor(seed: number = Date.now()) {
    this.random = new SeededRandom(seed);
  }

  getCurrentQueueIndex(): number {
    return this.currentIndex;
  }

  getBag(): number[] {
    return this.bag.slice();
  }

  getHistory(): number[] {
    return this.history.slice();
  }

  getFuture(): number[] {
    return this.future.slice();
  }

  setQueueSize(size: number): void {
    this.queueSize = size;
  }

  getQueueSize(): number {
    return this.queueSize;
  }

  // --------------------------------------------------------------------------
  // Shuffle bag
  // --------------------------------------------------------------------------

  /**
   * Rebuilds the shuffle bag from all queue indices, excluding excludeIndex
   * (the current track) so a fresh cycle never starts by replaying it.
   */
  rebuildShuffleBag(excludeIndex: number = -1): void {
    const bag: number[] = [];
    for (let i = 0; i < this.queueSize; i++) {
      if (i !== excludeIndex) {
        bag.push(i);
      }
    }
    for (let i = bag.length - 1; i > 0; i--) {
      const j = this.random.nextInt(i + 1);
      const tmp = bag[i];
      bag[i] = bag[j];
      bag[j] = tmp;
    }
    this.bag = bag;
  }

  // --------------------------------------------------------------------------
  // Mode changes
  // --------------------------------------------------------------------------

  /**
   * Toggles shuffle: enabling rebuilds the bag around the current track and
   * clearing both stacks; disabling clears all three structures (sequential
   * advancement does not need them).
   */
  setShuffle(enabled: boolean): void {
    this.shuffle = enabled;
    this.history = [];
    this.future = [];
    if (enabled) {
      this.rebuildShuffleBag(this.currentIndex);
    } else {
      this.bag = [];
    }
  }

  setRepeatMode(mode: RepeatMode): void {
    this.repeatMode = mode;
  }

  /** Android order: OFF -> ALL -> ONE -> OFF. */
  cycleRepeatMode(): RepeatMode {
    if (this.repeatMode === RepeatMode.OFF) {
      this.repeatMode = RepeatMode.ALL;
    } else if (this.repeatMode === RepeatMode.ALL) {
      this.repeatMode = RepeatMode.ONE;
    } else {
      this.repeatMode = RepeatMode.OFF;
    }
    return this.repeatMode;
  }

  // --------------------------------------------------------------------------
  // Advancement
  // --------------------------------------------------------------------------

  hasNext(force: boolean): boolean {
    if (this.queueSize === 0) {
      return false;
    }
    if (this.shuffle) {
      return this.future.length > 0 || this.bag.length > 0 || force || this.repeatMode === RepeatMode.ALL;
    }
    return this.currentIndex < this.queueSize - 1 || force || this.repeatMode === RepeatMode.ALL;
  }

  hasPrevious(): boolean {
    if (this.queueSize === 0) {
      return false;
    }
    if (this.shuffle) {
      return this.history.length > 0;
    }
    return this.currentIndex > 0 || this.repeatMode === RepeatMode.ALL;
  }

  /**
   * Whether the current track is the last one this cycle will produce
   * (shuffle: bag and future both drained; sequential: at the last index).
   */
  isLastInPlaylist(): boolean {
    if (this.queueSize === 0) {
      return true;
    }
    if (this.shuffle) {
      return this.future.length === 0 && this.bag.length === 0;
    }
    return this.currentIndex >= this.queueSize - 1;
  }

  /**
   * Advances to the next track and returns its queue index, or -1 when there
   * is no next track (callers decide between no-op and stop; sequential mode
   * at the end with repeat off is a silent no-op, matching Android).
   */
  next(force: boolean): number {
    if (!this.hasNext(force)) {
      return -1;
    }
    if (this.shuffle) {
      if (this.future.length > 0) {
        const target = this.future[this.future.length - 1];
        this.future.splice(this.future.length - 1, 1);
        if (this.currentIndex >= 0) {
          this.history.push(this.currentIndex);
        }
        this.currentIndex = target;
        return target;
      }
      if (this.bag.length === 0) {
        // hasNext ensured force or repeat-all: start a new cycle.
        this.rebuildShuffleBag(this.currentIndex);
      }
      if (this.bag.length === 0) {
        // Single-track queue: replay the current track.
        return this.currentIndex;
      }
      if (this.currentIndex >= 0) {
        this.history.push(this.currentIndex);
      }
      const pick = this.bag.length === 1 ? 0 : this.random.nextInt(this.bag.length);
      this.currentIndex = this.bag.splice(pick, 1)[0];
      return this.currentIndex;
    }
    if (this.currentIndex < this.queueSize - 1) {
      this.currentIndex += 1;
      return this.currentIndex;
    }
    if (force || this.repeatMode === RepeatMode.ALL) {
      this.currentIndex = 0;
      return 0;
    }
    return -1;
  }

  /**
   * Goes back and returns the target queue index, or -1 when there is no
   * previous track. Shuffle mode never touches the bag here: the revisited
   * track was already drawn from it.
   */
  previous(): number {
    if (this.queueSize === 0) {
      return -1;
    }
    if (this.shuffle) {
      if (this.history.length === 0) {
        return -1;
      }
      if (this.currentIndex >= 0) {
        this.future.push(this.currentIndex);
      }
      this.currentIndex = this.history[this.history.length - 1];
      this.history.splice(this.history.length - 1, 1);
      return this.currentIndex;
    }
    if (this.currentIndex > 0) {
      this.currentIndex -= 1;
      return this.currentIndex;
    }
    if (this.repeatMode === RepeatMode.ALL) {
      this.currentIndex = this.queueSize - 1;
      return this.currentIndex;
    }
    return -1;
  }

  /**
   * Manual track selection from the queue: records the outgoing track for
   * previous() backtracking, discards parked future entries, and removes the
   * picked track from the bag (it is playing now).
   */
  playAt(index: number): void {
    if (index < 0 || index >= this.queueSize) {
      return;
    }
    if (this.currentIndex >= 0 && this.currentIndex !== index) {
      this.history.push(this.currentIndex);
    }
    this.future = [];
    const bagIndex = this.bag.indexOf(index);
    if (bagIndex >= 0) {
      this.bag.splice(bagIndex, 1);
    }
    this.currentIndex = index;
  }

  /**
   * Starts a fresh queue at startIndex: resets both stacks and, when shuffle
   * is on, rebuilds the bag around the start track.
   */
  start(startIndex: number, shuffle: boolean, repeatMode: RepeatMode): void {
    this.shuffle = shuffle;
    this.repeatMode = repeatMode;
    this.history = [];
    this.future = [];
    this.bag = [];
    this.currentIndex = startIndex;
    if (shuffle) {
      this.rebuildShuffleBag(startIndex);
    }
  }

  /**
   * Flips the whole queue order in place: every stored index remaps to its
   * mirrored position, so the same songs play in reverse while the stack
   * chronology (history as a time-ordered backtrack log) is preserved.
   */
  reverse(): void {
    const count = this.queueSize;
    if (count < 2) {
      return;
    }
    const flip = (index: number): number => {
      return index >= 0 && index < count ? count - 1 - index : index;
    };
    this.currentIndex = flip(this.currentIndex);
    this.bag = this.bag.map((value: number): number => flip(value));
    this.history = this.history.map((value: number): number => flip(value));
    this.future = this.future.map((value: number): number => flip(value));
  }

  /**
   * Empties the queue: clears both stacks, the bag and the current index,
   * leaving the engine inert until the next start()/setQueueSize().
   */
  reset(): void {
    this.queueSize = 0;
    this.bag = [];
    this.history = [];
    this.future = [];
    this.currentIndex = -1;
  }

  // --------------------------------------------------------------------------
  // Queue edits (insert-next / add-to-end / move / remove)
  // --------------------------------------------------------------------------

  /**
   * Applies an externally computed queue edit (the song array lives in
   * PlayerManager, which knows song identity): resizes, re-points the
   * current index, and keeps the shuffle index lists aligned with the new
   * queue structure.
   *
   * existingIndex/insertIndex/newSongIndex mirror Android
   * remapShuffleStateForInsertNext: existingIndex is the removed duplicate's
   * pre-edit index (-1 when the song is new), insertIndex the post-removal
   * insertion slot (-1 for pure appends/removals), newSongIndex the inserted
   * song's final index (-1 for moves/removals, i.e. no future-parking).
   * rebuildShuffle mirrors Android addToQueueEndImpl, which rebuilds the bag
   * from scratch instead of shifting indices for end-appends.
   */
  applyQueueEdit(
    existingIndex: number,
    insertIndex: number,
    newSongIndex: number,
    newQueueSize: number,
    newCurrentIndex: number,
    rebuildShuffle: boolean
  ): void {
    this.queueSize = newQueueSize;
    this.currentIndex = newCurrentIndex;
    if (!this.shuffle) {
      return;
    }
    if (rebuildShuffle) {
      // 整袋重建意味着本周期作废：history/future 里的旧下标未随本次结构
      // 编辑平移，留着会错播，与 setShuffle 的清栈语义保持一致。
      this.history = [];
      this.future = [];
      this.rebuildShuffleBag(this.currentIndex);
      return;
    }
    const remapped = QueueEngine.remapForInsertNext(this.bag, this.history, this.future,
      existingIndex, insertIndex, newSongIndex);
    this.bag = remapped.bag;
    this.history = remapped.history;
    this.future = remapped.future;
  }

  /**
   * Resolves the current index after the item at removedIndex was spliced
   * out of a queue of oldSize entries. Mirrors Android
   * resolveQueueCurrentIndexAfterRemoval: removing an earlier item shifts
   * the current index down; removing the current item points it at the song
   * that shifted into its slot (clamped to the new last index, -1 once the
   * queue empties).
   */
  static currentIndexAfterRemoval(oldSize: number, currentIndex: number, removedIndex: number): number {
    if (oldSize <= 0 || currentIndex < 0 || currentIndex >= oldSize) {
      return -1;
    }
    if (removedIndex < 0 || removedIndex >= oldSize) {
      return currentIndex;
    }
    const newSize = oldSize - 1;
    if (newSize <= 0) {
      return -1;
    }
    if (currentIndex === removedIndex) {
      return Math.min(removedIndex, newSize - 1);
    }
    if (removedIndex < currentIndex) {
      return currentIndex - 1;
    }
    return currentIndex;
  }

  // --------------------------------------------------------------------------
  // Track-end policy
  // --------------------------------------------------------------------------

  /**
   * Decides what to do when the current track finishes naturally. Repeat one
   * replays; repeat all advances with force (wrapping/rebuilding the bag);
   * repeat off advances while tracks remain and stops afterwards.
   */
  onTrackEnded(): TrackEndAction {
    if (this.repeatMode === RepeatMode.ONE) {
      return TrackEndAction.REPLAY;
    }
    if (this.repeatMode === RepeatMode.ALL) {
      return TrackEndAction.ADVANCE;
    }
    return this.hasNext(false) ? TrackEndAction.ADVANCE : TrackEndAction.STOP;
  }

  // --------------------------------------------------------------------------
  // Queue mutation remapping (pure helpers)
  // --------------------------------------------------------------------------

  /**
   * Remaps the shuffle index lists when an existing queue item (existingIndex,
   * or -1 when the song is new) is moved/inserted at insertIndex, becoming
   * the track at newSongIndex that should play next.
   *
   * Mirrors Android remapShuffleStateForInsertNext: first apply the removal
   * shift, then the insertion shift, then pull the next-up song out of
   * bag/history and append it to future.
   */
  static remapForInsertNext(
    bag: number[],
    history: number[],
    future: number[],
    existingIndex: number,
    insertIndex: number,
    newSongIndex: number
  ): ShuffleIndexState {
    const newBag = QueueEngine.shiftForMove(QueueEngine.shiftForMove(bag, existingIndex, -1), -1, insertIndex);
    const newHistory = QueueEngine.shiftForMove(QueueEngine.shiftForMove(history, existingIndex, -1), -1, insertIndex);
    let newFuture = QueueEngine.shiftForMove(QueueEngine.shiftForMove(future, existingIndex, -1), -1, insertIndex);
    if (newSongIndex >= 0) {
      QueueEngine.removeAll(newBag, newSongIndex);
      QueueEngine.removeAll(newHistory, newSongIndex);
      if (newFuture.indexOf(newSongIndex) < 0) {
        newFuture.push(newSongIndex);
      }
    }
    return new ShuffleIndexState(newBag, newHistory, newFuture);
  }

  /**
   * Applies index shifts for a removal (toIndex < 0) or an insertion
   * (fromIndex < 0); the other parameter is ignored. A negative ignored
   * parameter keeps this a single helper for both steps.
   */
  private static shiftForMove(list: number[], removedIndex: number, insertIndex: number): number[] {
    if (removedIndex >= 0) {
      const out: number[] = [];
      for (const value of list) {
        if (value === removedIndex) {
          continue;
        }
        out.push(value > removedIndex ? value - 1 : value);
      }
      return out;
    }
    if (insertIndex >= 0) {
      const out: number[] = [];
      for (const value of list) {
        out.push(value >= insertIndex ? value + 1 : value);
      }
      return out;
    }
    return list.slice();
  }

  private static removeAll(list: number[], value: number): void {
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i] === value) {
        list.splice(i, 1);
      }
    }
  }

  /**
   * Resolves the current index after a queue item moved from fromIndex to
   * toIndex. Mirrors Android resolveQueueCurrentIndexAfterMove.
   */
  static currentIndexAfterMove(queueSize: number, currentIndex: number, fromIndex: number, toIndex: number): number {
    if (queueSize <= 0) {
      return -1;
    }
    if (currentIndex < 0 || currentIndex >= queueSize) {
      return currentIndex;
    }
    if (fromIndex < 0 || fromIndex >= queueSize || toIndex < 0 || toIndex >= queueSize || fromIndex === toIndex) {
      return currentIndex;
    }
    if (currentIndex === fromIndex) {
      return toIndex;
    }
    if (fromIndex < currentIndex && currentIndex <= toIndex) {
      return currentIndex - 1;
    }
    if (toIndex <= currentIndex && currentIndex < fromIndex) {
      return currentIndex + 1;
    }
    return currentIndex;
  }

  // --------------------------------------------------------------------------
  // Snapshot
  // --------------------------------------------------------------------------

  /**
   * Full serializable snapshot, including the seeded random state, so an
   * engine can be restored mid-cycle (test/debug/session tooling).
   */
  toJson(): string {
    return JSON.stringify({
      shuffle: this.shuffle,
      repeatMode: this.repeatMode,
      currentIndex: this.currentIndex,
      bag: this.bag,
      history: this.history,
      future: this.future,
      randomState: this.random.getState()
    });
  }

  static fromJson(json: string, queueSize: number): QueueEngine | null {
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const engine = new QueueEngine(1);
    engine.queueSize = queueSize;
    engine.shuffle = Boolean(raw['shuffle'] ?? false);
    const modeRaw = Number(raw['repeatMode'] ?? RepeatMode.ALL);
    engine.repeatMode = modeRaw === RepeatMode.OFF || modeRaw === RepeatMode.ONE || modeRaw === RepeatMode.ALL
      ? modeRaw
      : RepeatMode.ALL;
    engine.currentIndex = Number(raw['currentIndex'] ?? -1);
    engine.bag = QueueEngine.readNumberList(raw['bag']);
    engine.history = QueueEngine.readNumberList(raw['history']);
    engine.future = QueueEngine.readNumberList(raw['future']);
    engine.random.setState(Number(raw['randomState'] ?? 1));
    return engine;
  }

  private static readNumberList(value: Object | undefined): number[] {
    const out: number[] = [];
    if (value !== undefined && Array.isArray(value)) {
      const entries = value as Object[];
      for (const entry of entries) {
        out.push(Number(entry));
      }
    }
    return out;
  }
}

/**
 * First track for a "play playlist" action, mirroring Android
 * resolvePlaylistPlaybackStartIndex: sequential play starts at 0, shuffle
 * starts at the caller-supplied random pick clamped into range (the engine
 * then keeps that track out of the shuffle bag). Returns -1 when empty.
 */
export function resolvePlaylistPlaybackStartIndex(
  songCount: number,
  shuffleEnabled: boolean,
  randomIndex: number
): number {
  if (songCount <= 0) {
    return -1;
  }
  if (!shuffleEnabled) {
    return 0;
  }
  return Math.min(Math.max(randomIndex, 0), songCount - 1);
}
