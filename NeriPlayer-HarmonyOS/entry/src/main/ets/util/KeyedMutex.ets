// SPDX-License-Identifier: GPL-3.0

/**
 * Per-key async mutual exclusion (promise-chain). Serializes
 * load-modify-save sequences over the same persisted store so a second
 * writer cannot interleave between the load and the save of the first —
 * upstream 607af71d5 fixed the same lost-update window with a pendingWrite
 * snapshot + rebase; a plain FIFO chain is the structural equivalent for
 * the SchemaStore/preferences repositories here.
 *
 * NOT reentrant: a task running under key K must never call run(K, ...)
 * again. The inner task queues behind the outer one's promise while the
 * outer one awaits the inner, so both hang forever and every later task on
 * K hangs behind them. Code inside a locked task must call the owning
 * repository's `*Locked` variants instead. (Regression that motivated this
 * note: addFavoriteLocked called the public addSong, which re-entered this
 * lock on every favorites toggle.)
 */
export class KeyedMutex {
  private readonly tails: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  run<T>(key: string, task: () => Promise<T>): Promise<T> {
    const prior = this.tails.get(key);
    const result = (prior === undefined ? Promise.resolve() : prior)
      .then((): Promise<T> => task());
    // The chain itself must never reject or later waiters would be skipped;
    // task failures still surface through `result` alone.
    this.tails.set(key, result.then((): void => {}, (): void => {}));
    return result;
  }
}
