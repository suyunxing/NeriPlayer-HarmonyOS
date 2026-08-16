import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { AppPreferences } from '../data/AppPreferences';
import { SchemaStore } from '../data/schema/SchemaStore';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { DownloadNaming } from './DownloadSupport';

/**
 * Resume fingerprint for DIRECT/CHUNKED_RANGE transfers (Android
 * WorkingResumeFingerprint): validator (etag preferred) plus the expected
 * total length so a changed source forces a clean restart.
 */
export class ResumeFingerprint {
  sourceUrl: string = '';
  etag: string = '';
  lastModified: string = '';
  expectedContentLength: number = -1;

  validator(): string {
    return this.etag.length > 0 ? this.etag : this.lastModified;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(json: string): ResumeFingerprint | null {
    try {
      const raw = JSON.parse(json) as Record<string, Object>;
      const fp = new ResumeFingerprint();
      fp.sourceUrl = String(raw['sourceUrl'] ?? '');
      fp.etag = String(raw['etag'] ?? '');
      fp.lastModified = String(raw['lastModified'] ?? '');
      fp.expectedContentLength = Number(raw['expectedContentLength'] ?? -1);
      return fp;
    } catch (error) {
      return null;
    }
  }
}

/** HLS resume checkpoint (Android HlsResumeState). */
export class HlsResumeState {
  playlistFingerprint: number = 0;
  nextSegmentIndex: number = 0;
  downloadedBytes: number = 0;

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(json: string): HlsResumeState | null {
    try {
      const raw = JSON.parse(json) as Record<string, Object>;
      const state = new HlsResumeState();
      state.playlistFingerprint = Number(raw['playlistFingerprint'] ?? 0);
      state.nextSegmentIndex = Number(raw['nextSegmentIndex'] ?? 0);
      state.downloadedBytes = Number(raw['downloadedBytes'] ?? 0);
      return state;
    } catch (error) {
      return null;
    }
  }
}

/** Catalog entry for a committed download. */
export class DownloadedSongEntry {
  stableKey: string;
  audioPath: string;
  songJson: string;
  committedAt: number;

  constructor(stableKey: string, audioPath: string, songJson: string, committedAt: number) {
    this.stableKey = stableKey;
    this.audioPath = audioPath;
    this.songJson = songJson;
    this.committedAt = committedAt;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromRecord(record: Record<string, Object>): DownloadedSongEntry {
    return new DownloadedSongEntry(
      String(record['stableKey'] ?? ''),
      String(record['audioPath'] ?? ''),
      String(record['songJson'] ?? ''),
      Number(record['committedAt'] ?? 0)
    );
  }
}

/**
 * Managed download storage tree (D3 decision: app sandbox):
 * - working/staging: <filesDir>/download_staging/*.download + sidecars;
 * - final tree: <filesDir>/Download/NeriPlayer/<name>.<ext>;
 * - catalog: preferences key `downloaded_catalog` via SchemaStore.
 */
export class DownloadStorage {
  private static context: common.Context | null = null;

  static init(context: common.Context): void {
    DownloadStorage.context = context;
    DownloadStorage.ensureDir(DownloadStorage.stagingDir());
    DownloadStorage.ensureDir(DownloadStorage.downloadDir());
  }

  static stagingDir(): string {
    const base = DownloadStorage.context !== null
      ? DownloadStorage.context.filesDir
      : '/data/storage/el2/base/files';
    return `${base}/download_staging`;
  }

  static downloadDir(): string {
    const base = DownloadStorage.context !== null
      ? DownloadStorage.context.filesDir
      : '/data/storage/el2/base/files';
    return `${base}/Download/NeriPlayer`;
  }

  private static ensureDir(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`DownloadStorage.ensureDir(${path}) failed: ${e.message}`);
    }
  }

  // ------------------------------------------------------------------
  // Working files (staging)
  // ------------------------------------------------------------------

  static workingFilePath(song: SongItem, ext: string): string {
    const baseName = DownloadNaming.renderWithFallback(DownloadNaming.DEFAULT_TEMPLATE, song);
    const name = DownloadNaming.workingFileName(song, baseName, ext);
    return `${DownloadStorage.stagingDir()}/${name}`;
  }

  static fingerprintPath(workingPath: string): string {
    return `${workingPath}.resume.json`;
  }

  static hlsCheckpointPath(workingPath: string): string {
    return `${workingPath}.hls.json`;
  }

  static readFingerprint(workingPath: string): ResumeFingerprint | null {
    return DownloadStorage.readJsonFile(DownloadStorage.fingerprintPath(workingPath), ResumeFingerprint.fromJson);
  }

  static writeFingerprint(workingPath: string, fingerprint: ResumeFingerprint): void {
    DownloadStorage.writeTextFile(DownloadStorage.fingerprintPath(workingPath), fingerprint.toJson());
  }

  static readHlsCheckpoint(workingPath: string): HlsResumeState | null {
    return DownloadStorage.readJsonFile(DownloadStorage.hlsCheckpointPath(workingPath), HlsResumeState.fromJson);
  }

  static writeHlsCheckpoint(workingPath: string, state: HlsResumeState): void {
    DownloadStorage.writeTextFile(DownloadStorage.hlsCheckpointPath(workingPath), state.toJson());
  }

  static fileSize(path: string): number {
    try {
      const stat = fileIo.statSync(path);
      return stat.size;
    } catch (error) {
      return 0;
    }
  }

  /** Appends a chunk to the working file, creating it when absent. */
  static appendChunk(workingPath: string, chunk: ArrayBuffer): number {
    try {
      const exists = fileIo.accessSync(workingPath);
      const file = exists
        ? fileIo.openSync(workingPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND)
        : fileIo.openSync(workingPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        fileIo.writeSync(file.fd, chunk, { offset: chunk.byteLength });
        return chunk.byteLength;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`appendChunk failed: ${e.message}`);
      return 0;
    }
  }

  static deleteWorkingSet(workingPath: string): void {
    const paths = [
      workingPath,
      DownloadStorage.fingerprintPath(workingPath),
      DownloadStorage.hlsCheckpointPath(workingPath)
    ];
    for (const path of paths) {
      try {
        if (fileIo.accessSync(path)) {
          fileIo.unlinkSync(path);
        }
      } catch (error) {
        const e = error as Error;
        Logger.debug(`deleteWorkingSet ignored: ${e.message}`);
      }
    }
  }

  // ------------------------------------------------------------------
  // Commit (staging -> final tree -> catalog)
  // ------------------------------------------------------------------

  /**
   * Atomically commits the working file: fsync + rename into the final
   * tree, then records the catalog entry. Returns the final path or ''.
   */
  static commit(song: SongItem, workingPath: string, ext: string): string {
    try {
      const baseName = DownloadNaming.renderWithFallback(DownloadNaming.DEFAULT_TEMPLATE, song);
      const finalPath = `${DownloadStorage.downloadDir()}/${baseName}.${ext.length > 0 ? ext : 'bin'}`;
      fileIo.renameSync(workingPath, finalPath);
      DownloadStorage.deleteWorkingSet(workingPath);
      return finalPath;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`commit failed: ${e.message}`);
      return '';
    }
  }

  static async addCatalogEntry(song: SongItem, audioPath: string): Promise<void> {
    const entries = await DownloadStorage.getCatalog();
    const key = stableKeyOf(song);
    const next = entries.filter((entry: DownloadedSongEntry) => entry.stableKey !== key);
    next.push(new DownloadedSongEntry(key, audioPath, song.toJson(), Date.now()));
    const json = JSON.stringify(next.map((entry: DownloadedSongEntry) => entry.toJson()));
    await SchemaStore.save('downloaded_catalog', json, (value: string) => value);
  }

  static async getCatalog(): Promise<DownloadedSongEntry[]> {
    return SchemaStore.load<DownloadedSongEntry[]>('downloaded_catalog', [], (json: string): DownloadedSongEntry[] | null => {
      const rawList = JSON.parse(json) as Object[];
      if (!Array.isArray(rawList)) {
        return null;
      }
      const entries: DownloadedSongEntry[] = [];
      for (const raw of rawList) {
        entries.push(DownloadedSongEntry.fromRecord(raw as Record<string, Object>));
      }
      return entries;
    });
  }

  static async findCatalogEntry(song: SongItem): Promise<DownloadedSongEntry | null> {
    const key = stableKeyOf(song);
    const entries = await DownloadStorage.getCatalog();
    for (const entry of entries) {
      if (entry.stableKey === key) {
        return entry;
      }
    }
    return null;
  }

  static async removeCatalogEntry(song: SongItem): Promise<void> {
    const key = stableKeyOf(song);
    const entries = await DownloadStorage.getCatalog();
    const next = entries.filter((entry: DownloadedSongEntry) => entry.stableKey !== key);
    const json = JSON.stringify(next.map((entry: DownloadedSongEntry) => entry.toJson()));
    await SchemaStore.save('downloaded_catalog', json, (value: string) => value);
  }

  // ------------------------------------------------------------------
  // File helpers
  // ------------------------------------------------------------------

  private static readTextFile(path: string): string {
    try {
      if (!fileIo.accessSync(path)) {
        return '';
      }
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(path);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        const decoder = util.TextDecoder.create('utf-8');
        return decoder.decodeWithStream(new Uint8Array(buffer), { stream: false });
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      return '';
    }
  }

  private static readJsonFile<T>(path: string, parse: (json: string) => T | null): T | null {
    const text = DownloadStorage.readTextFile(path);
    if (text.length === 0) {
      return null;
    }
    try {
      return parse(text);
    } catch (error) {
      return null;
    }
  }

  private static writeTextFile(path: string, text: string): void {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`writeTextFile(${path}) failed: ${e.message}`);
    }
  }
}

// Re-export for callers that use the preferences-backed store directly.
export { AppPreferences };
