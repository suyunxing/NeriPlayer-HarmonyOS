// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SongItem } from '../model/SongItem';

/**
 * Download pipeline models, mirroring DownloadTaskModels.kt /
 * AudioDownloadManager.kt on Android.
 */
export enum DownloadTransportKind {
  /** Single response, whole file. */
  DIRECT = 0,
  /** Sequential Range-chunked transfer. */
  CHUNKED_RANGE = 1,
  /** HLS playlist + segments. */
  HLS = 2
}

/** Progress-display stage (not persisted). */
export enum DownloadStage {
  TRANSFERRING = 0,
  WAITING_RETRY = 1,
  FINALIZING = 2
}

export enum DownloadStatus {
  QUEUED = 0,
  DOWNLOADING = 1,
  WAITING_NETWORK = 2,
  COMPLETED = 3,
  FAILED = 4,
  CANCELLED = 5
}

export class DownloadProgress {
  attemptId: number = 0;
  stage: DownloadStage = DownloadStage.TRANSFERRING;
  bytesRead: number = 0;
  totalBytes: number = -1;

  /**
   * 0-99 while transferring, 100 in FINALIZING or when all bytes are read,
   * -1 when the total length is unknown (Android percentage semantics).
   */
  percentage(): number {
    if (this.stage === DownloadStage.FINALIZING) {
      return 100;
    }
    if (this.totalBytes <= 0) {
      return -1;
    }
    if (this.bytesRead >= this.totalBytes) {
      return 100;
    }
    return Math.floor((this.bytesRead / this.totalBytes) * 100);
  }
}

export class DownloadTask {
  song: SongItem;
  progress: DownloadProgress | null;
  status: DownloadStatus;
  attemptId: number;

  constructor(song: SongItem, status: DownloadStatus, attemptId: number) {
    this.song = song;
    this.progress = null;
    this.status = status;
    this.attemptId = attemptId;
  }
}

/** Whether the status participates in an in-flight attempt. */
export function isDownloadAttemptActive(status: DownloadStatus): boolean {
  return status === DownloadStatus.QUEUED || status === DownloadStatus.DOWNLOADING;
}

/** Only terminal statuses can be cleared from the task list. */
export function isDownloadTaskClearable(status: DownloadStatus): boolean {
  return status === DownloadStatus.COMPLETED || status === DownloadStatus.FAILED
    || status === DownloadStatus.CANCELLED;
}

/**
 * Guard for stale-attempt mutations: an update only applies when the task
 * still carries the expected attempt id (or the caller passes no guard).
 */
export function shouldApplyTaskMutation(task: DownloadTask, expectedAttemptId: number): boolean {
  return expectedAttemptId < 0 || task.attemptId === expectedAttemptId;
}
