import { AppPreferences } from './AppPreferences';
import { DownloadTask, DownloadStatus } from '../model/DownloadTask';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { DownloadFileStore } from '../download/DownloadFileStore';
import { Logger } from '../app/Logger';

/**
 * Persisted download task catalog (queue, progress, completion state).
 * Mutations are serialized because several transfer workers may finish chunks
 * around the same time.
 */
export class DownloadsRepository {
  private static readonly KEY: string = 'downloads';
  private static readonly LIMIT: number = 500;
  private static serial: Promise<void> = Promise.resolve();

  private static serialize(operation: () => Promise<void>): Promise<void> {
    const result = DownloadsRepository.serial.then(() => operation());
    DownloadsRepository.serial = result.then(() => {}, () => {});
    return result;
  }

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

  static async getById(id: string): Promise<DownloadTask | null> {
    const tasks = await DownloadsRepository.loadAll();
    const task = tasks.find((item: DownloadTask) => item.id === id);
    return task ?? null;
  }

  static async enqueue(song: SongItem): Promise<DownloadTask> {
    let created = new DownloadTask();
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const key = stableKeyOf(song);
      const existing = tasks.find((task: DownloadTask) => stableKeyOf(task.song) === key &&
        task.status !== DownloadStatus.COMPLETED);
      if (existing !== undefined) {
        created = existing;
        return;
      }
      const safeName = song.displayName.replace(/[\\/:*?"<>|]/g, '_');
      const task = new DownloadTask(
        `dl_${Date.now()}_${key.length > 12 ? key.substring(0, 12) : key}`,
        song,
        `${safeName}.mp3`
      );
      tasks.unshift(task);
      await DownloadsRepository.saveAll(tasks);
      created = task;
    });
    return created;
  }

  static async updateProgress(id: string, downloadedBytes: number, totalBytes: number): Promise<void> {
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const task = tasks.find((item: DownloadTask) => item.id === id);
      if (task === undefined) {
        return;
      }
      task.downloadedBytes = downloadedBytes;
      task.totalBytes = totalBytes;
      task.updatedAt = Date.now();
      await DownloadsRepository.saveAll(tasks);
    });
  }

  static async setStatus(id: string, status: DownloadStatus, error: string = ''): Promise<void> {
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const task = tasks.find((item: DownloadTask) => item.id === id);
      if (task === undefined) {
        return;
      }
      task.status = status;
      task.error = error;
      task.updatedAt = Date.now();
      await DownloadsRepository.saveAll(tasks);
    });
  }

  /**
   * Replaces the persisted record for a task. Used by the transfer worker when
   * it creates the final/partial file paths or stores validator headers.
   */
  static async updateTask(task: DownloadTask): Promise<void> {
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const index = tasks.findIndex((item: DownloadTask) => item.id === task.id);
      if (index < 0) {
        return;
      }
      task.updatedAt = Date.now();
      tasks[index] = task;
      await DownloadsRepository.saveAll(tasks);
    });
  }

  static async remove(id: string): Promise<void> {
    let removed: DownloadTask | null = null;
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const task = tasks.find((item: DownloadTask) => item.id === id);
      if (task !== undefined) {
        removed = task;
      }
      const filtered = tasks.filter((task: DownloadTask) => task.id !== id);
      await DownloadsRepository.saveAll(filtered);
    });
    if (removed !== null) {
      DownloadFileStore.deleteTaskFiles(removed);
    }
  }

  static async clearCompleted(): Promise<void> {
    await DownloadsRepository.serialize(async (): Promise<void> => {
      const tasks = await DownloadsRepository.loadAll();
      const filtered = tasks.filter((task: DownloadTask) => task.status !== DownloadStatus.COMPLETED);
      await DownloadsRepository.saveAll(filtered);
    });
  }

  static async clearAll(): Promise<void> {
    let tasks: DownloadTask[] = [];
    await DownloadsRepository.serialize(async (): Promise<void> => {
      tasks = await DownloadsRepository.loadAll();
      await AppPreferences.putString(DownloadsRepository.KEY, '[]');
    });
    for (const task of tasks) {
      DownloadFileStore.deleteTaskFiles(task);
    }
  }
}
