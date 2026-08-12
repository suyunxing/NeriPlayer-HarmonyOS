import { AppPreferences } from './AppPreferences';
import { DownloadTask, DownloadStatus } from '../model/DownloadTask';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { Logger } from '../app/Logger';

/**
 * Persisted download task catalog (queue, progress, completion state).
 * Actual byte-level transfer pipeline is a roadmap item; the UI and catalog
 * are fully wired.
 */
export class DownloadsRepository {
  private static readonly KEY: string = 'downloads';
  private static readonly LIMIT: number = 500;

  static async loadAll(): Promise<DownloadTask[]> {
    const json = await AppPreferences.getString(DownloadsRepository.KEY, '[]');
    const tasks: DownloadTask[] = [];
    try {
      const rawList = JSON.parse(json) as Object[];
      for (const raw of rawList) {
        tasks.push(DownloadTask.fromJson(JSON.stringify(raw)));
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadsRepository.loadAll failed: ${e.message}`);
    }
    return tasks;
  }

  static async saveAll(tasks: DownloadTask[]): Promise<void> {
    const limited = tasks.slice(0, DownloadsRepository.LIMIT);
    const json = JSON.stringify(limited.map((task: DownloadTask) => DownloadTask.fromJson(task.toJson())));
    await AppPreferences.putString(DownloadsRepository.KEY, json);
  }

  static async enqueue(song: SongItem): Promise<DownloadTask> {
    const tasks = await DownloadsRepository.loadAll();
    const key = stableKeyOf(song);
    const existing = tasks.find((task: DownloadTask) => stableKeyOf(task.song) === key &&
      task.status !== DownloadStatus.COMPLETED);
    if (existing !== undefined) {
      return existing;
    }
    const safeName = song.displayName.replace(/[\\/:*?"<>|]/g, '_');
    const task = new DownloadTask(
      `dl_${Date.now()}_${key.length > 12 ? key.substring(0, 12) : key}`,
      song,
      `${safeName}.mp3`
    );
    tasks.unshift(task);
    await DownloadsRepository.saveAll(tasks);
    return task;
  }

  static async updateProgress(id: string, downloadedBytes: number, totalBytes: number): Promise<void> {
    const tasks = await DownloadsRepository.loadAll();
    const task = tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined) {
      return;
    }
    task.downloadedBytes = downloadedBytes;
    task.totalBytes = totalBytes;
    task.updatedAt = Date.now();
    await DownloadsRepository.saveAll(tasks);
  }

  static async setStatus(id: string, status: DownloadStatus, error: string = ''): Promise<void> {
    const tasks = await DownloadsRepository.loadAll();
    const task = tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined) {
      return;
    }
    task.status = status;
    task.error = error;
    task.updatedAt = Date.now();
    await DownloadsRepository.saveAll(tasks);
  }

  static async remove(id: string): Promise<void> {
    const tasks = await DownloadsRepository.loadAll();
    const filtered = tasks.filter((task: DownloadTask) => task.id !== id);
    await DownloadsRepository.saveAll(filtered);
  }

  static async clearCompleted(): Promise<void> {
    const tasks = await DownloadsRepository.loadAll();
    const filtered = tasks.filter((task: DownloadTask) => task.status !== DownloadStatus.COMPLETED);
    await DownloadsRepository.saveAll(filtered);
  }

  static async clearAll(): Promise<void> {
    await AppPreferences.putString(DownloadsRepository.KEY, '[]');
  }
}
