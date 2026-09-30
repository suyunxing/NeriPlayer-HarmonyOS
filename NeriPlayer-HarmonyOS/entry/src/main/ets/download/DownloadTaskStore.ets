// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import {
  DownloadProgress,
  DownloadStatus,
  DownloadTask,
  isDownloadAttemptActive,
  shouldApplyTaskMutation
} from './DownloadModels';

/**
 * In-memory download task registry, mirroring Android DownloadTaskStore:
 * keyed by stable song key, guarded by per-attempt ids so late callbacks of
 * a superseded attempt can never mutate the replacement task.
 *
 * Pure logic (no @ohos APIs) — persistence of the queue itself is owned by
 * the caller (DownloadQueueStore) and re-issues fresh attempt ids on load.
 */
export class DownloadTaskStore {
  private tasks: Map<string, DownloadTask> = new Map<string, DownloadTask>();
  private attemptCounter: number = 0;

  getTasks(): DownloadTask[] {
    return Array.from(this.tasks.values());
  }

  getTask(songKey: string): DownloadTask | null {
    return this.tasks.get(songKey) ?? null;
  }

  isAttemptActive(songKey: string, attemptId: number): boolean {
    const task = this.tasks.get(songKey);
    return task !== undefined && task.attemptId === attemptId
      && isDownloadAttemptActive(task.status);
  }

  /**
   * Prepares a task for download. An active task is kept as-is (returns it
   * with no new attempt); re-enterable terminal/WAITING_NETWORK tasks get a
   * fresh attempt id and are requeued. replaceExistingActiveTasks allows the
   * startup-recovery path to supersede active tasks.
   */
  prepare(song: SongItem, replaceExistingActiveTasks: boolean = false): DownloadTask {
    const songKey = stableKeyOf(song);
    const existing = this.tasks.get(songKey);
    if (existing !== undefined) {
      const active = isDownloadAttemptActive(existing.status);
      if (active && !replaceExistingActiveTasks) {
        return existing;
      }
      const task = new DownloadTask(existing.song, DownloadStatus.QUEUED, this.nextAttemptId());
      this.tasks.set(songKey, task);
      return task;
    }
    const task = new DownloadTask(song, DownloadStatus.QUEUED, this.nextAttemptId());
    this.tasks.set(songKey, task);
    return task;
  }

  /**
   * Batch prepare: de-duplicates by song key; first occurrence wins.
   * Returns the tasks that are actually queued by this call.
   */
  prepareBatch(songs: SongItem[], replaceExistingActiveTasks: boolean = false): DownloadTask[] {
    const seen: Set<string> = new Set<string>();
    const queued: DownloadTask[] = [];
    for (const song of songs) {
      const songKey = stableKeyOf(song);
      if (seen.has(songKey)) {
        continue;
      }
      seen.add(songKey);
      const existing = this.tasks.get(songKey);
      if (existing !== undefined && isDownloadAttemptActive(existing.status)
        && !replaceExistingActiveTasks) {
        continue;
      }
      const task = new DownloadTask(song, DownloadStatus.QUEUED, this.nextAttemptId());
      this.tasks.set(songKey, task);
      queued.push(task);
    }
    return queued;
  }

  /** Marks a queued attempt as transferring; guarded by attempt id. */
  registerActive(songKey: string, attemptId: number): boolean {
    const task = this.tasks.get(songKey);
    if (task === undefined || !shouldApplyTaskMutation(task, attemptId)) {
      return false;
    }
    task.status = DownloadStatus.DOWNLOADING;
    return true;
  }

  updateStatus(songKey: string, expectedAttemptId: number, status: DownloadStatus): boolean {
    const task = this.tasks.get(songKey);
    if (task === undefined || !shouldApplyTaskMutation(task, expectedAttemptId)) {
      return false;
    }
    task.status = status;
    if (status === DownloadStatus.WAITING_NETWORK || status === DownloadStatus.CANCELLED) {
      task.progress = null;
    }
    return true;
  }

  updateProgress(songKey: string, expectedAttemptId: number, progress: DownloadProgress): boolean {
    const task = this.tasks.get(songKey);
    if (task === undefined || !shouldApplyTaskMutation(task, expectedAttemptId)) {
      return false;
    }
    task.progress = progress;
    return true;
  }

  /** Network-policy pause: keeps the working files, clears progress. */
  applyWaitingNetwork(songKey: string, attemptId: number): boolean {
    const task = this.tasks.get(songKey);
    if (task === undefined || task.attemptId !== attemptId) {
      return false;
    }
    task.status = DownloadStatus.WAITING_NETWORK;
    task.progress = null;
    return true;
  }

  /** Queue-level cancel of every non-terminal task. */
  cancelAll(): void {
    for (const task of this.tasks.values()) {
      if (isDownloadAttemptActive(task.status) || task.status === DownloadStatus.WAITING_NETWORK) {
        task.status = DownloadStatus.CANCELLED;
        task.progress = null;
      }
    }
  }

  removeTask(songKey: string, expectedAttemptId: number): boolean {
    const task = this.tasks.get(songKey);
    if (task === undefined || !shouldApplyTaskMutation(task, expectedAttemptId)) {
      return false;
    }
    this.tasks.delete(songKey);
    return true;
  }

  /** Removes terminal tasks only; active/waiting tasks stay. */
  clearCompleted(): void {
    for (const task of this.tasks.values()) {
      if (task.status === DownloadStatus.COMPLETED || task.status === DownloadStatus.FAILED
        || task.status === DownloadStatus.CANCELLED) {
        this.tasks.delete(stableKeyOf(task.song));
      }
    }
  }

  clearAll(): void {
    this.tasks.clear();
  }

  nextAttemptId(): number {
    this.attemptCounter += 1;
    return this.attemptCounter;
  }
}
