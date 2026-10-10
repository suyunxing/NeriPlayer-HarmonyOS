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
  /** 技术性失败原因（英文短语/HTTP 状态），UI 展示经 downloadFailureText 映射。 */
  failureReason: string = '';

  constructor(song: SongItem, status: DownloadStatus, attemptId: number) {
    this.song = song;
    this.progress = null;
    this.status = status;
    this.attemptId = attemptId;
  }
}

/**
 * 用户可读的失败原因文案：覆盖引擎全部 failTask reason（含 commit 失败），
 * 未知文本原样返回（多为网络层 message，保留可诊断上下文）。
 */
export function downloadFailureText(reason: string): string {
  const trimmed = reason.trim();
  if (trimmed.length === 0) {
    return '未知原因';
  }
  if (trimmed === 'no playable source') {
    return '未找到可下载的音源';
  }
  if (trimmed === 'downloaded payload is not audio') {
    return '下载内容不是有效音频';
  }
  if (trimmed === 'downloaded payload has filler corruption') {
    return '音源数据异常，已弃用损坏副本';
  }
  if (trimmed === 'save to download directory failed') {
    return '保存到下载目录失败，请检查目录是否可写';
  }
  if (trimmed === 'retry attempts exhausted') {
    return '多次重试后仍失败';
  }
  if (trimmed === 'unsupported HLS playlist') {
    return '不支持的音乐源格式';
  }
  if (trimmed.startsWith('HLS segment')) {
    return '分段下载失败';
  }
  if (trimmed.startsWith('HLS failed:')) {
    return `下载中断：${trimmed.substring('HLS failed:'.length).trim()}`;
  }
  if (trimmed.startsWith('HTTP')) {
    return `服务端返回 ${trimmed}`;
  }
  return trimmed;
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
