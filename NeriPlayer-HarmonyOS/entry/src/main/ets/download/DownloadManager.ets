import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AppPreferences } from '../data/AppPreferences';
import { DownloadsRepository } from '../data/DownloadsRepository';
import { SettingsRepository } from '../data/SettingsRepository';
import { DownloadTask, DownloadStatus } from '../model/DownloadTask';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { Logger } from '../app/Logger';
import { StreamResolver } from '../network/StreamResolver';
import { LyricApi } from '../network/LyricApi';
import { LyricPayload } from '../network/NeteaseApi';
import { HttpClient, HttpBinaryResponse } from '../network/HttpClient';
import { DownloadFileStore } from './DownloadFileStore';

/**
 * Download transfer pipeline for the HarmonyOS port.
 *
 * Implements the roadmap item "Range 断点续传 + 实际文件落盘":
 *  - persisted queue with startup recovery for interrupted transfers;
 *  - Range (206) chunked download, 200 fallback for servers that ignore Range;
 *  - pause/resume/retry without losing the partial file;
 *  - optional .lrc sidecar and .song.json metadata after completion.
 */
export class DownloadManager {
  static readonly REVISION_KEY: string = 'downloads.revision';
  private static readonly CHUNK_SIZE: number = 2 * 1024 * 1024;
  private static readonly PROGRESS_INTERVAL_MS: number = 500;
  private static readonly MAX_CHUNK_ATTEMPTS: number = 3;

  private static context: common.UIAbilityContext | null = null;
  private static initialized: boolean = false;
  private static activeIds: Set<string> = new Set<string>();
  private static cancelledIds: Set<string> = new Set<string>();
  private static removedIds: Set<string> = new Set<string>();
  private static lastPersist: Map<string, number> = new Map<string, number>();

  static initialize(context: common.UIAbilityContext): void {
    if (DownloadManager.initialized) {
      return;
    }
    DownloadManager.initialized = true;
    DownloadManager.context = context;
    AppPreferences.init(context);
    AppStorage.setOrCreate(DownloadManager.REVISION_KEY, 0);
    DownloadManager.recoverInterrupted();
  }

  static async enqueueAndStart(song: SongItem): Promise<DownloadTask> {
    const task = await DownloadsRepository.enqueue(song);
    DownloadManager.publishRevision();
    await DownloadManager.kick();
    return task;
  }

  static async pause(id: string): Promise<void> {
    DownloadManager.cancelledIds.add(id);
    await DownloadsRepository.setStatus(id, DownloadStatus.PAUSED, '');
    DownloadManager.publishRevision();
  }

  static async resume(id: string): Promise<void> {
    DownloadManager.cancelledIds.delete(id);
    await DownloadsRepository.setStatus(id, DownloadStatus.QUEUED, '');
    DownloadManager.publishRevision();
    await DownloadManager.kick();
  }

  static async retry(id: string): Promise<void> {
    DownloadManager.cancelledIds.delete(id);
    // Keep the partial file; transfer() revalidates its size. If a stale
    // partial is longer than the current server resource, the 416 branch resets it.
    await DownloadsRepository.setStatus(id, DownloadStatus.QUEUED, '');
    DownloadManager.publishRevision();
    await DownloadManager.kick();
  }

  static async clearAll(): Promise<void> {
    try {
      const tasks = await DownloadsRepository.loadAll();
      for (const task of tasks) {
        DownloadManager.removedIds.add(task.id);
        DownloadManager.cancelledIds.add(task.id);
      }
      await DownloadsRepository.clearAll();
      DownloadManager.publishRevision();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadManager.clearAll failed: ${e.message}`);
      throw e;
    }
  }

  static async remove(id: string): Promise<void> {
    DownloadManager.removedIds.add(id);
    DownloadManager.cancelledIds.add(id);
    await DownloadsRepository.remove(id);
    DownloadManager.publishRevision();
  }

  private static async recoverInterrupted(): Promise<void> {
    try {
      const tasks = await DownloadsRepository.loadAll();
      let changed = false;
      for (const task of tasks) {
        if (task.status === DownloadStatus.DOWNLOADING) {
          task.status = DownloadStatus.QUEUED;
          changed = true;
        }
      }
      if (changed) {
        await DownloadsRepository.saveAll(tasks);
      }
      DownloadManager.publishRevision();
      await DownloadManager.kick();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadManager.recoverInterrupted failed: ${e.message}`);
    }
  }

  private static async kick(): Promise<void> {
    if (DownloadManager.context === null) {
      return;
    }
    try {
      const tasks = await DownloadsRepository.loadAll();
      let concurrency = SettingsRepository.getNumber(SettingsRepository.KEY_DOWNLOAD_CONCURRENCY, 2);
      if (concurrency < 1) {
        concurrency = 1;
      }
      if (concurrency > 8) {
        concurrency = 8;
      }
      let active = DownloadManager.activeIds.size;
      for (const task of tasks) {
        if (active >= concurrency) {
          break;
        }
        if (task.status !== DownloadStatus.QUEUED || DownloadManager.activeIds.has(task.id) ||
          DownloadManager.cancelledIds.has(task.id) || DownloadManager.removedIds.has(task.id)) {
          continue;
        }
        DownloadManager.activeIds.add(task.id);
        active += 1;
        DownloadManager.run(task.id);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadManager.kick failed: ${e.message}`);
    }
  }

  private static async run(id: string): Promise<void> {
    try {
      await DownloadManager.download(id);
    } catch (error) {
      const e = error as Error;
      Logger.error(`DownloadManager task ${id} failed: ${e.message}`);
      if (!DownloadManager.removedIds.has(id)) {
        await DownloadsRepository.setStatus(id, DownloadStatus.FAILED, e.message);
        DownloadManager.publishRevision();
      }
    } finally {
      DownloadManager.activeIds.delete(id);
      DownloadManager.kick();
    }
  }

  private static async download(id: string): Promise<void> {
    if (DownloadManager.context === null || DownloadManager.removedIds.has(id)) {
      return;
    }
    const task = await DownloadsRepository.getById(id);
    if (task === null || task.status !== DownloadStatus.QUEUED) {
      return;
    }
    const dir = DownloadFileStore.ensureDirSync(DownloadManager.context);
    if (task.filePath.length === 0) {
      task.filePath = DownloadFileStore.buildFinalPath(dir, task);
      task.downloadedBytes = DownloadFileStore.partialSize(task);
      await DownloadsRepository.updateTask(task);
    }
    if (DownloadManager.cancelledIds.has(id)) {
      await DownloadsRepository.setStatus(id, DownloadStatus.PAUSED, '');
      DownloadManager.publishRevision();
      return;
    }
    await DownloadsRepository.setStatus(id, DownloadStatus.DOWNLOADING, '');
    DownloadManager.publishRevision();

    if (task.song.platform === MusicPlatform.LOCAL) {
      await DownloadManager.downloadLocal(task);
      return;
    }
    const url = await StreamResolver.resolve(task.song);
    if (url.length === 0) {
      throw new Error(`No playable stream for ${task.song.displayName}`);
    }
    await DownloadManager.transfer(task, url);
    await DownloadManager.finalize(task);
  }

  private static async downloadLocal(task: DownloadTask): Promise<void> {
    const source = task.song.localFilePath.length > 0 ? task.song.localFilePath : task.song.mediaUri;
    if (source.length === 0 || task.filePath.length === 0) {
      throw new Error('Local source path is empty');
    }
    let size = 0;
    try {
      size = fileIo.statSync(source).size;
    } catch (error) {
      const e = error as Error;
      throw new Error(`Local source stat failed: ${e.message}`);
    }
    DownloadFileStore.resetPartial(task);
    try {
      fileIo.unlinkSync(task.filePath);
    } catch (error) {
      // Previous final file may not exist.
    }
    try {
      fileIo.copyFileSync(source, task.filePath);
    } catch (error) {
      const e = error as Error;
      throw new Error(`Local copy failed: ${e.message}`);
    }
    task.totalBytes = size;
    task.downloadedBytes = size;
    task.status = DownloadStatus.COMPLETED;
    task.error = '';
    await DownloadsRepository.updateTask(task);
    DownloadManager.publishRevision();
    Logger.info(`DownloadManager local copy completed: ${task.fileName}`);
  }

  private static async transfer(task: DownloadTask, url: string): Promise<void> {
    let offset = DownloadFileStore.partialSize(task);
    let total = task.totalBytes;
    if (total > 0 && offset >= total) {
      return;
    }
    let attempts = 0;
    while (true) {
      if (DownloadManager.removedIds.has(task.id)) {
        return;
      }
      if (DownloadManager.cancelledIds.has(task.id)) {
        await DownloadsRepository.setStatus(task.id, DownloadStatus.PAUSED, '');
        DownloadManager.publishRevision();
        return;
      }

      const headers = DownloadManager.platformHeaders(task.song);
      headers['Range'] = `bytes=${offset}-${offset + DownloadManager.CHUNK_SIZE - 1}`;
      let response: HttpBinaryResponse = new HttpBinaryResponse();
      try {
        response = await HttpClient.getBytes(url, headers, 60000, true);
        attempts = 0;
      } catch (error) {
        const e = error as Error;
        attempts += 1;
        if (attempts >= DownloadManager.MAX_CHUNK_ATTEMPTS) {
          throw new Error(`Chunk request failed after ${attempts} attempts: ${e.message}`);
        }
        Logger.warn(`DownloadManager chunk retry ${attempts} for ${task.id}: ${e.message}`);
        await DownloadManager.sleep(700 * attempts);
        continue;
      }

      if (response.statusCode === 206) {
        const rangeStart = response.contentRangeStart();
        const rangeTotal = response.contentRangeTotal();
        if (rangeStart >= 0) {
          offset = rangeStart;
        }
        if (rangeTotal > 0) {
          total = rangeTotal;
        }
        const chunk = response.body;
        if (chunk.byteLength === 0) {
          if (total > 0 && offset < total) {
            throw new Error(`Server returned an empty 206 chunk at ${offset}/${total}`);
          }
          return;
        }
        DownloadFileStore.writeChunk(task, offset, chunk);
        offset += chunk.byteLength;
        task.downloadedBytes = offset;
        task.totalBytes = total > 0 ? total : task.totalBytes;
        await DownloadManager.persistProgress(task);
        if (total > 0 && offset >= total) {
          return;
        }
        continue;
      }

      if (response.statusCode === 200) {
        // Server ignored the Range header. Accept the full representation and
        // restart the local file from zero.
        offset = 0;
        DownloadFileStore.resetPartial(task);
        DownloadFileStore.writeChunk(task, 0, response.body);
        offset = response.body.byteLength;
        total = response.contentLength() > 0 ? response.contentLength() : response.body.byteLength;
        task.downloadedBytes = offset;
        task.totalBytes = total;
        await DownloadManager.persistProgress(task);
        return;
      }

      if (response.statusCode === 416) {
        if (offset <= 0) {
          throw new Error('Server rejected the initial Range request (416)');
        }
        // Stale partial file is longer than the current resource; restart it.
        DownloadFileStore.resetPartial(task);
        offset = 0;
        total = 0;
        task.downloadedBytes = 0;
        task.totalBytes = 0;
        await DownloadManager.persistProgress(task);
        continue;
      }

      throw new Error(`HTTP ${response.statusCode} while downloading ${task.fileName}`);
    }
  }

  private static async finalize(task: DownloadTask): Promise<void> {
    if (DownloadManager.removedIds.has(task.id)) {
      return;
    }
    if (DownloadManager.cancelledIds.has(task.id)) {
      await DownloadsRepository.setStatus(task.id, DownloadStatus.PAUSED, '');
      DownloadManager.publishRevision();
      return;
    }
    const partialPath = DownloadFileStore.partialPath(task);
    let size = 0;
    try {
      size = fileIo.statSync(partialPath).size;
    } catch (error) {
      throw new Error(`Partial file disappeared before finalization: ${partialPath}`);
    }
    if (task.totalBytes > 0 && size < task.totalBytes) {
      throw new Error(`Download incomplete: ${size}/${task.totalBytes} bytes`);
    }
    DownloadFileStore.commitPartial(task);
    task.downloadedBytes = task.totalBytes > 0 ? task.totalBytes : size;
    task.totalBytes = task.totalBytes > 0 ? task.totalBytes : size;
    task.status = DownloadStatus.COMPLETED;
    task.error = '';
    await DownloadsRepository.updateTask(task);
    await DownloadManager.writeSidecars(task);
    DownloadManager.publishRevision();
    Logger.info(`DownloadManager completed: ${task.fileName}`);
  }

  private static async writeSidecars(task: DownloadTask): Promise<void> {
    try {
      const matchLyrics = SettingsRepository.getBoolean(SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, true);
      if (matchLyrics) {
        let payload: LyricPayload | null = null;
        if (task.song.platform === MusicPlatform.NETEASE) {
          const neteaseId = Number(task.song.audioId);
          if (!Number.isNaN(neteaseId) && neteaseId > 0) {
            payload = await LyricApi.fetchFromNetease(neteaseId);
          }
        } else {
          payload = await LyricApi.fetchFromLrcLib(task.song.displayName, task.song.displayArtist, task.song.durationMs);
        }
        if (payload !== null && payload.lyric.length > 0) {
          let lrc = payload.lyric;
          if (payload.translated.length > 0) {
            lrc = `${lrc}\n\n[translations]\n${payload.translated}`;
          }
          DownloadFileStore.writeText(`${task.filePath}.lrc`, lrc);
        }
      }
      DownloadFileStore.writeText(`${task.filePath}.song.json`, task.song.toJson());
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadManager sidecars failed for ${task.id}: ${e.message}`);
    }
  }

  private static async persistProgress(task: DownloadTask): Promise<void> {
    const now = Date.now();
    const previous = DownloadManager.lastPersist.get(task.id) ?? 0;
    if (now - previous < DownloadManager.PROGRESS_INTERVAL_MS) {
      return;
    }
    DownloadManager.lastPersist.set(task.id, now);
    await DownloadsRepository.updateProgress(task.id, task.downloadedBytes, task.totalBytes);
    DownloadManager.publishRevision();
  }

  private static platformHeaders(song: SongItem): Record<string, string> {
    const headers: Record<string, string> = {};
    if (song.platform === MusicPlatform.BILIBILI) {
      headers['Referer'] = 'https://www.bilibili.com';
    } else if (song.platform === MusicPlatform.YOUTUBE_MUSIC) {
      headers['Referer'] = 'https://music.youtube.com';
    } else {
      headers['Referer'] = 'https://music.163.com';
    }
    return headers;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private static publishRevision(): void {
    const current = AppStorage.get<number>(DownloadManager.REVISION_KEY) ?? 0;
    AppStorage.setOrCreate(DownloadManager.REVISION_KEY, current + 1);
  }
}
