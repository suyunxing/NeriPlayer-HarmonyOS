import { SongItem } from './SongItem';

export enum DownloadStatus {
  QUEUED = 0,
  DOWNLOADING = 1,
  PAUSED = 2,
  COMPLETED = 3,
  FAILED = 4
}

/**
 * Download task model, mirroring Android DownloadTaskModels. Songs are stored
 * as full SongItem JSON so the catalog can resume playback/lyrics offline.
 */
export class DownloadTask {
  id: string;
  song: SongItem;
  fileName: string;
  totalBytes: number;
  downloadedBytes: number;
  status: DownloadStatus;
  error: string;
  createdAt: number;
  updatedAt: number;

  constructor(
    id: string = '',
    song: SongItem = new SongItem(),
    fileName: string = '',
    totalBytes: number = 0,
    downloadedBytes: number = 0,
    status: DownloadStatus = DownloadStatus.QUEUED,
    error: string = '',
    createdAt: number = Date.now(),
    updatedAt: number = Date.now()
  ) {
    this.id = id;
    this.song = song;
    this.fileName = fileName;
    this.totalBytes = totalBytes;
    this.downloadedBytes = downloadedBytes;
    this.status = status;
    this.error = error;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  get progressPercent(): number {
    if (this.totalBytes <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor((this.downloadedBytes / this.totalBytes) * 100));
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(json: string): DownloadTask {
    const raw = JSON.parse(json) as Record<string, Object>;
    const task = new DownloadTask();
    task.id = String(raw['id'] ?? '');
    task.song = SongItem.fromJson(JSON.stringify(raw['song'] ?? {}));
    task.fileName = String(raw['fileName'] ?? '');
    task.totalBytes = Number(raw['totalBytes'] ?? 0);
    task.downloadedBytes = Number(raw['downloadedBytes'] ?? 0);
    task.status = Number(raw['status'] ?? DownloadStatus.QUEUED) as DownloadStatus;
    task.error = String(raw['error'] ?? '');
    task.createdAt = Number(raw['createdAt'] ?? 0);
    task.updatedAt = Number(raw['updatedAt'] ?? 0);
    return task;
  }
}
