import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { Logger } from '../app/Logger';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { SchemaStore } from '../data/schema/SchemaStore';
import { SettingsRepository } from '../data/SettingsRepository';
import { StreamResolver } from '../network/StreamResolver';
import { HttpClient } from '../network/HttpClient';
import { HttpStreamDownloader, StreamDownloadHeaders } from '../network/HttpStreamDownloader';
import {
  DownloadProgress,
  DownloadStage,
  DownloadStatus,
  DownloadTask
} from './DownloadModels';
import { DownloadTaskStore } from './DownloadTaskStore';
import { DownloadRetryPolicy } from './DownloadSupport';
import { DownloadStorage, ResumeFingerprint, HlsResumeState } from './DownloadStorage';

export interface DownloadEngineListener {
  onTasksChanged(): void;
}

/** Parsed HLS playlist with the segment list and its fingerprint. */
export class HlsPlaylist {
  segmentUrls: string[] = [];
  fingerprint: number = 0;
}

export class HlsPlaylistParser {
  /** Extracts non-comment lines as segment URLs; fingerprint = joined hash. */
  static parse(text: string): HlsPlaylist | null {
    if (text.indexOf('#EXTM3U') < 0) {
      return null;
    }
    const playlist = new HlsPlaylist();
    for (const rawLine of text.split('\n')) {
      const line = rawLine.trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      playlist.segmentUrls.push(line);
    }
    if (playlist.segmentUrls.length === 0) {
      return null;
    }
    let hash = 0x811c9dc5;
    const joined = playlist.segmentUrls.join('\n');
    for (let i = 0; i < joined.length; i++) {
      hash ^= joined.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    playlist.fingerprint = hash >>> 0;
    return playlist;
  }
}

/**
 * Download engine: bounded concurrency scheduling, transient retries with
 * backoff, resume via Range/If-Range fingerprints (DIRECT) or HLS segment
 * checkpoints, atomic commit into the managed tree, network-aware waiting
 * and startup queue recovery. Mirrors GlobalDownloadManager +
 * AudioDownloadManager at the scale this port needs.
 */
export class DownloadEngine {
  private static store: DownloadTaskStore = new DownloadTaskStore();
  private static activeCount: number = 0;
  private static listeners: DownloadEngineListener[] = [];
  private static context: common.Context | null = null;
  private static netConnection: connection.NetConnection | null = null;
  private static initialized: boolean = false;

  static init(context: common.Context): void {
    if (DownloadEngine.initialized) {
      return;
    }
    DownloadEngine.initialized = true;
    DownloadEngine.context = context;
    DownloadStorage.init(context);
    DownloadEngine.registerNetworkListener();
    DownloadEngine.recoverPendingForStartup();
  }

  static addListener(listener: DownloadEngineListener): void {
    DownloadEngine.listeners.push(listener);
  }

  static getTasks(): DownloadTask[] {
    return DownloadEngine.store.getTasks();
  }

  static enqueue(songs: SongItem[]): void {
    DownloadEngine.store.prepareBatch(songs, false);
    DownloadEngine.persistQueue();
    DownloadEngine.pump();
    DownloadEngine.notifyChanged();
  }

  static cancel(songKey: string): void {
    const task = DownloadEngine.store.getTask(songKey);
    if (task === null) {
      return;
    }
    DownloadEngine.store.updateStatus(songKey, task.attemptId, DownloadStatus.CANCELLED);
    DownloadEngine.persistQueue();
    DownloadEngine.notifyChanged();
  }

  static resume(songKey: string): void {
    const task = DownloadEngine.store.getTask(songKey);
    if (task === null) {
      return;
    }
    if (task.status === DownloadStatus.WAITING_NETWORK || task.status === DownloadStatus.FAILED
      || task.status === DownloadStatus.CANCELLED) {
      DownloadEngine.store.prepare(task.song, false);
      DownloadEngine.persistQueue();
      DownloadEngine.pump();
      DownloadEngine.notifyChanged();
    }
  }

  static clearFinished(): void {
    DownloadEngine.store.clearCompleted();
    DownloadEngine.persistQueue();
    DownloadEngine.notifyChanged();
  }

  /** Debug/reset path: drops every task regardless of status (files stay). */
  static clearAllTasks(): void {
    DownloadEngine.store.clearAll();
    DownloadEngine.persistQueue();
    DownloadEngine.notifyChanged();
  }

  // ----------------------------------------------------------------------
  // Scheduling
  // ----------------------------------------------------------------------

  private static concurrencyLimit(): number {
    const raw = Number(AppStorage.get<number>(SettingsRepository.KEY_DOWNLOAD_CONCURRENCY) ?? 6);
    if (Number.isNaN(raw)) {
      return 6;
    }
    return Math.min(8, Math.max(1, Math.floor(raw)));
  }

  private static pump(): void {
    while (DownloadEngine.activeCount < DownloadEngine.concurrencyLimit()) {
      const next = DownloadEngine.store.getTasks()
        .find((task: DownloadTask) => task.status === DownloadStatus.QUEUED);
      if (next === undefined) {
        return;
      }
      DownloadEngine.activeCount += 1;
      DownloadEngine.runTask(next).finally(() => {
        DownloadEngine.activeCount -= 1;
        DownloadEngine.pump();
      });
    }
  }

  private static notifyChanged(): void {
    for (const listener of DownloadEngine.listeners) {
      listener.onTasksChanged();
    }
  }

  // ----------------------------------------------------------------------
  // Single task execution
  // ----------------------------------------------------------------------

  private static async runTask(task: DownloadTask): Promise<void> {
    const songKey = stableKeyOf(task.song);
    DownloadEngine.store.registerActive(songKey, task.attemptId);
    DownloadEngine.notifyChanged();

    // Already in the catalog with a readable file: skip re-transferring.
    const cached = await DownloadStorage.findCatalogEntry(task.song);
    if (cached !== null && DownloadStorage.fileSize(cached.audioPath) > 0) {
      DownloadEngine.store.updateStatus(songKey, task.attemptId, DownloadStatus.COMPLETED);
      DownloadEngine.persistQueue();
      DownloadEngine.notifyChanged();
      return;
    }

    let url = '';
    try {
      url = await StreamResolver.resolve(task.song);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`download resolve failed: ${e.message}`);
    }
    if (url.length === 0) {
      await DownloadEngine.failTask(songKey, task.attemptId, task.song, 'no playable source');
      return;
    }
    if (DownloadEngine.isCancelled(songKey, task.attemptId)) {
      return;
    }

    const isHls = url.indexOf('.m3u8') >= 0;
    if (isHls) {
      await DownloadEngine.runHlsTask(songKey, task, url);
      return;
    }
    await DownloadEngine.runDirectTask(songKey, task, url);
  }

  private static async runDirectTask(songKey: string, task: DownloadTask, url: string): Promise<void> {
    const ext = DownloadEngine.guessExtension(url);
    const workingPath = DownloadStorage.workingFilePath(task.song, ext);

    let resumeStart = 0;
    let validator = '';
    const existing = DownloadStorage.readFingerprint(workingPath);
    if (existing !== null && existing.sourceUrl === url && DownloadStorage.fileSize(workingPath) > 0) {
      resumeStart = DownloadStorage.fileSize(workingPath);
      validator = existing.validator();
    } else {
      DownloadStorage.deleteWorkingSet(workingPath);
    }

    for (let attempt = 1; attempt <= DownloadRetryPolicy.MAX_ATTEMPTS; attempt++) {
      if (DownloadEngine.isCancelled(songKey, task.attemptId)) {
        return;
      }
      let failure = '';
      let restartRequired = false;
      try {
        const code = await HttpStreamDownloader.download(url, resumeStart, validator, {
          onHeaders: (headers: StreamDownloadHeaders) => {
            if (resumeStart > 0 && headers.contentRangeStart >= 0 && headers.contentRangeStart !== resumeStart) {
              // Server ignored the offset; restart from zero.
              restartRequired = true;
              return;
            }
            const fingerprint = new ResumeFingerprint();
            fingerprint.sourceUrl = url;
            fingerprint.etag = headers.etag;
            fingerprint.lastModified = headers.lastModified;
            fingerprint.expectedContentLength = resumeStart > 0
              ? resumeStart + headers.contentLength
              : headers.contentLength;
            DownloadStorage.writeFingerprint(workingPath, fingerprint);
            const progress = new DownloadProgress();
            progress.attemptId = task.attemptId;
            progress.stage = DownloadStage.TRANSFERRING;
            progress.bytesRead = resumeStart;
            progress.totalBytes = fingerprint.expectedContentLength;
            DownloadEngine.store.updateProgress(songKey, task.attemptId, progress);
            DownloadEngine.notifyChanged();
          },
          onData: (chunk: ArrayBuffer, received: number) => {
            if (DownloadEngine.isCancelled(songKey, task.attemptId) || restartRequired) {
              return false;
            }
            DownloadStorage.appendChunk(workingPath, chunk);
            const progress = new DownloadProgress();
            progress.attemptId = task.attemptId;
            progress.stage = DownloadStage.TRANSFERRING;
            progress.bytesRead = resumeStart + received;
            const current = DownloadEngine.store.getTask(songKey);
            progress.totalBytes = current !== null && current.progress !== null
              ? current.progress.totalBytes
              : -1;
            DownloadEngine.store.updateProgress(songKey, task.attemptId, progress);
            return true;
          }
        });
        if (restartRequired) {
          DownloadStorage.deleteWorkingSet(workingPath);
          resumeStart = 0;
          validator = '';
          failure = 'restart: range mismatch';
        } else if (code === 416 && resumeStart > 0) {
          // Already complete on the server side.
          await DownloadEngine.completeTask(songKey, task.attemptId, task.song, workingPath, ext);
          return;
        } else if (code === 0 || code === 206 || (code >= 200 && code < 300)) {
          // code 0: the stream completed via dataEnd before the response
          // code settled — validate by received size (Android
          // isTransferSizeComplete semantics) instead of trusting the code.
          if (DownloadEngine.transferSizeComplete(songKey, workingPath)) {
            await DownloadEngine.completeTask(songKey, task.attemptId, task.song, workingPath, ext);
            return;
          }
          failure = 'incomplete transfer';
        } else if (!DownloadRetryPolicy.isRetryableHttpError(code)) {
          await DownloadEngine.failTask(songKey, task.attemptId, task.song, `HTTP ${code}`);
          return;
        } else {
          failure = `HTTP ${code}`;
        }
      } catch (error) {
        const e = error as Error;
        failure = e.message;
        if (failure === 'aborted') {
          return;
        }
      }
      // Retryable failure: back off, or park on network loss.
      if (!DownloadRetryPolicy.isRetryableMessage(failure)
        && !failure.startsWith('HTTP') && !failure.startsWith('restart')
        && !failure.startsWith('incomplete')) {
        await DownloadEngine.failTask(songKey, task.attemptId, task.song, failure);
        return;
      }
      if (await DownloadEngine.hasNetwork()) {
        await DownloadEngine.sleep(DownloadRetryPolicy.retryDelayMs(attempt));
      } else {
        DownloadEngine.store.applyWaitingNetwork(songKey, task.attemptId);
        DownloadEngine.notifyChanged();
        return; // network-restored path re-enqueues
      }
    }
    await DownloadEngine.failTask(songKey, task.attemptId, task.song, 'retry attempts exhausted');
  }

  private static async runHlsTask(songKey: string, task: DownloadTask, url: string): Promise<void> {
    const workingPath = DownloadStorage.workingFilePath(task.song, 'ts');
    try {
      const text = await HttpClient.getText(url);
      const playlist = HlsPlaylistParser.parse(text);
      if (playlist === null) {
        await DownloadEngine.failTask(songKey, task.attemptId, task.song, 'unsupported HLS playlist');
        return;
      }
      let checkpoint = DownloadStorage.readHlsCheckpoint(workingPath);
      if (checkpoint === null
        || checkpoint.playlistFingerprint !== playlist.fingerprint
        || checkpoint.nextSegmentIndex > playlist.segmentUrls.length
        || DownloadStorage.fileSize(workingPath) !== checkpoint.downloadedBytes) {
        DownloadStorage.deleteWorkingSet(workingPath);
        checkpoint = null;
      }
      let nextIndex = checkpoint !== null ? checkpoint.nextSegmentIndex : 0;
      for (; nextIndex < playlist.segmentUrls.length; nextIndex++) {
        if (DownloadEngine.isCancelled(songKey, task.attemptId)) {
          return;
        }
        let segmentFailure = true;
        for (let attempt = 1; attempt <= DownloadRetryPolicy.MAX_ATTEMPTS && segmentFailure; attempt++) {
          try {
            const code = await HttpStreamDownloader.download(playlist.segmentUrls[nextIndex], -1, '', {
              onHeaders: (headers: StreamDownloadHeaders) => {
                const progress = new DownloadProgress();
                progress.attemptId = task.attemptId;
                progress.stage = DownloadStage.TRANSFERRING;
                progress.bytesRead = DownloadStorage.fileSize(workingPath);
                progress.totalBytes = -1;
                DownloadEngine.store.updateProgress(songKey, task.attemptId, progress);
              },
              onData: (chunk: ArrayBuffer) => {
                DownloadStorage.appendChunk(workingPath, chunk);
                return true;
              }
            });
            if (code >= 200 && code < 300) {
              segmentFailure = false;
            }
          } catch (error) {
            const e = error as Error;
            if (e.message === 'aborted') {
              return;
            }
          }
          if (segmentFailure) {
            await DownloadEngine.sleep(DownloadRetryPolicy.retryDelayMs(attempt));
          }
        }
        if (segmentFailure) {
          await DownloadEngine.failTask(songKey, task.attemptId, task.song, `HLS segment ${nextIndex} failed`);
          return;
        }
        const state = new HlsResumeState();
        state.playlistFingerprint = playlist.fingerprint;
        state.nextSegmentIndex = nextIndex + 1;
        state.downloadedBytes = DownloadStorage.fileSize(workingPath);
        DownloadStorage.writeHlsCheckpoint(workingPath, state);
        DownloadEngine.notifyChanged();
      }
      await DownloadEngine.completeTask(songKey, task.attemptId, task.song, workingPath, 'ts');
    } catch (error) {
      const e = error as Error;
      await DownloadEngine.failTask(songKey, task.attemptId, task.song, `HLS failed: ${e.message}`);
    }
  }

  // ----------------------------------------------------------------------
  // Terminal transitions
  // ----------------------------------------------------------------------

  private static async completeTask(
    songKey: string, attemptId: number, song: SongItem, workingPath: string, ext: string
  ): Promise<void> {
    // Finalize first, flip to COMPLETED last: observers (UI, offline
    // playback) treat COMPLETED as "catalog row already visible" — the same
    // ordering as Android finalizeCompletedDownload.
    const finalizing = new DownloadProgress();
    finalizing.attemptId = attemptId;
    finalizing.stage = DownloadStage.FINALIZING;
    finalizing.bytesRead = DownloadStorage.fileSize(workingPath);
    finalizing.totalBytes = finalizing.bytesRead;
    DownloadEngine.store.updateProgress(songKey, attemptId, finalizing);
    DownloadEngine.notifyChanged();

    const finalPath = DownloadStorage.commit(song, workingPath, ext);
    if (finalPath.length === 0) {
      DownloadEngine.store.updateStatus(songKey, attemptId, DownloadStatus.FAILED);
      DownloadEngine.notifyChanged();
      return;
    }
    await DownloadStorage.addCatalogEntry(song, finalPath);
    if (!DownloadEngine.store.updateStatus(songKey, attemptId, DownloadStatus.COMPLETED)) {
      // The attempt was superseded while finalizing: roll the catalog back
      // (Android rollbackStaleCompletedDownload semantics; the orphan file
      // stays on disk until the user clears storage).
      await DownloadStorage.removeCatalogEntry(song);
      return;
    }
    DownloadEngine.persistQueue();
    DownloadEngine.notifyChanged();
    Logger.info(`DownloadEngine: completed ${song.displayName} -> ${finalPath}`);
  }

  private static async failTask(songKey: string, attemptId: number, song: SongItem, reason: string): Promise<void> {
    DownloadEngine.store.updateStatus(songKey, attemptId, DownloadStatus.FAILED);
    DownloadEngine.persistQueue();
    DownloadEngine.notifyChanged();
    Logger.warn(`DownloadEngine: failed ${song.displayName}: ${reason}`);
  }

  private static isCancelled(songKey: string, attemptId: number): boolean {
    return !DownloadEngine.store.isAttemptActive(songKey, attemptId);
  }

  /**
   * Size validation for a finished transfer: positive local size, and when
   * the source advertised a total, the file must reach it (Android
   * isTransferSizeComplete).
   */
  private static transferSizeComplete(songKey: string, workingPath: string): boolean {
    const size = DownloadStorage.fileSize(workingPath);
    if (size <= 0) {
      return false;
    }
    const task = DownloadEngine.store.getTask(songKey);
    const expected = task !== null && task.progress !== null ? task.progress.totalBytes : -1;
    return expected <= 0 || size >= expected;
  }

  private static guessExtension(url: string): string {
    const query = url.indexOf('?');
    const path = query >= 0 ? url.substring(0, query) : url;
    const dot = path.lastIndexOf('.');
    if (dot >= 0 && path.length - dot <= 5) {
      return path.substring(dot + 1).toLowerCase();
    }
    return 'mp3';
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }

  // ----------------------------------------------------------------------
  // Network awareness + startup recovery (M3.5)
  // ----------------------------------------------------------------------

  private static async hasNetwork(): Promise<boolean> {
    try {
      return await connection.hasDefaultNet();
    } catch (error) {
      return true;
    }
  }

  private static registerNetworkListener(): void {
    try {
      const conn = connection.createNetConnection();
      conn.on('netAvailable', () => {
        Logger.info('DownloadEngine: network restored, resuming waiting tasks');
        DownloadEngine.resumeWaitingTasks();
      });
      conn.on('netUnavailable', () => {
        Logger.info('DownloadEngine: network lost, pausing active tasks');
        for (const task of DownloadEngine.store.getTasks()) {
          if (task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.QUEUED) {
            DownloadEngine.store.applyWaitingNetwork(stableKeyOf(task.song), task.attemptId);
          }
        }
        DownloadEngine.notifyChanged();
      });
      DownloadEngine.netConnection = conn;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadEngine network listener failed: ${e.message}`);
    }
  }

  private static resumeWaitingTasks(): void {
    let changed = false;
    for (const task of DownloadEngine.store.getTasks()) {
      if (task.status === DownloadStatus.WAITING_NETWORK) {
        DownloadEngine.store.prepare(task.song, false);
        changed = true;
      }
    }
    if (changed) {
      DownloadEngine.persistQueue();
      DownloadEngine.pump();
      DownloadEngine.notifyChanged();
    }
  }

  /** Startup recovery: reload the persisted queue and requeue it. */
  private static recoverPendingForStartup(): void {
    DownloadEngine.loadQueue().then((songs: SongItem[]) => {
      if (songs.length === 0) {
        return;
      }
      DownloadEngine.store.prepareBatch(songs, true);
      DownloadEngine.notifyChanged();
      DownloadEngine.pump();
    }).catch((error: Error) => {
      Logger.warn(`DownloadEngine recovery failed: ${error.message}`);
    });
  }

  // ----------------------------------------------------------------------
  // Queue persistence (pending_download_queue_v1 semantics)
  // ----------------------------------------------------------------------

  private static readonly QUEUE_KEY: string = 'pending_download_queue';

  private static async persistQueue(): Promise<void> {
    const active = DownloadEngine.store.getTasks().filter((task: DownloadTask) => {
      return task.status === DownloadStatus.QUEUED || task.status === DownloadStatus.DOWNLOADING
        || task.status === DownloadStatus.WAITING_NETWORK;
    });
    const entries: PendingQueueEntry[] = active.map((task: DownloadTask, index: number) => {
      const entry = new PendingQueueEntry();
      entry.stableKey = stableKeyOf(task.song);
      entry.order = index;
      entry.queuedAtMs = Date.now();
      entry.songJson = task.song.toJson();
      return entry;
    });
    const envelope = new PendingQueueEnvelope();
    envelope.entries = entries;
    const json = JSON.stringify(envelope);
    await SchemaStore.save(DownloadEngine.QUEUE_KEY, json, (value: string) => value);
  }

  private static async loadQueue(): Promise<SongItem[]> {
    return SchemaStore.load<SongItem[]>(DownloadEngine.QUEUE_KEY, [], (json: string): SongItem[] | null => {
      const raw = JSON.parse(json) as Record<string, Object>;
      const rawEntries = raw['entries'];
      if (rawEntries === undefined || !Array.isArray(rawEntries)) {
        return null;
      }
      const songs: SongItem[] = [];
      for (const entry of rawEntries as Object[]) {
        const record = entry as Record<string, Object>;
        const songJson = record['songJson'];
        if (songJson !== undefined) {
          songs.push(SongItem.fromJson(String(songJson)));
        }
      }
      return songs;
    });
  }
}

/** Persisted queue records (pending_download_queue_v1 semantics). */
class PendingQueueEntry {
  stableKey: string = '';
  order: number = 0;
  queuedAtMs: number = 0;
  songJson: string = '';
}

class PendingQueueEnvelope {
  version: number = 1;
  updatedAtMs: number = 0;
  entries: PendingQueueEntry[] = [];
}

