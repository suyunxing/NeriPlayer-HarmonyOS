// SPDX-License-Identifier: GPL-3.0

/**
 * Per-key async mutual exclusion (promise-chain). Serializes
 * load-modify-save sequences over the same persisted store so a second
 * writer cannot interleave between the load and the save of the first —
 * upstream 607af71d5 fixed the same lost-update window with a pendingWrite
 * snapshot + rebase; a plain FIFO chain is the structural equivalent for
 * the SchemaStore/preferences repositories here.
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
