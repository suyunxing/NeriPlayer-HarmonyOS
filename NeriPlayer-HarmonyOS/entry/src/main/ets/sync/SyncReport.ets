/** User-facing outcome of one coordinated sync run. */

export enum SyncConflictResolution {
  LOCAL_WINS = 'local_wins',
  REMOTE_WINS = 'remote_wins',
  MANUAL_REQUIRED = 'manual_required'
}

export class SyncConflictSummary {
  playlistId: number;
  playlistName: string;
  description: string;
  resolution: SyncConflictResolution;

  constructor(
    playlistId: number = 0,
    playlistName: string = '',
    description: string = '',
    resolution: SyncConflictResolution = SyncConflictResolution.MANUAL_REQUIRED
  ) {
    this.playlistId = playlistId;
    this.playlistName = playlistName;
    this.description = description;
    this.resolution = resolution;
  }
}

export class SyncReport {
  success: boolean = true;
  message: string = '';
  playlistsAdded: number = 0;
  playlistsUpdated: number = 0;
  playlistsDeleted: number = 0;
  songsAdded: number = 0;
  songsRemoved: number = 0;
  conflicts: SyncConflictSummary[] = [];
  uploadPerformed: boolean = false;
  remoteChangedDuringSync: boolean = false;
  localChangedDuringSync: boolean = false;
  pendingPlaylistCount: number = 0;
  remoteVersion: string = '';

  summary(): string {
    if (!this.success) {
      return this.message;
    }
    const changes = this.playlistsAdded + this.playlistsUpdated + this.playlistsDeleted +
      this.songsAdded + this.songsRemoved;
    if (changes === 0 && this.conflicts.length === 0) {
      return this.message.length > 0 ? this.message : '同步完成，无数据变化';
    }
    let text = `同步完成：歌单 +${this.playlistsAdded} / 更新 ${this.playlistsUpdated} / 删除 ${this.playlistsDeleted}`;
    text += `，歌曲 +${this.songsAdded} / -${this.songsRemoved}`;
    if (this.conflicts.length > 0) {
      text += `，冲突 ${this.conflicts.length}`;
    }
    if (this.localChangedDuringSync) {
      text += '；同步期间本地又有修改，已保留待下次同步';
    }
    return text;
  }
}
