// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { AppPreferences } from '../data/AppPreferences';
import { SchemaStore } from '../data/schema/SchemaStore';
import { SettingsRepository } from '../data/SettingsRepository';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { DownloadNaming } from './DownloadSupport';
import { DownloadDirectory } from './DownloadDirectory';

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
  // Field initializers are required: ArkTS JSON.stringify of a class
  // instance without them serializes type defaults, not constructor values.
  stableKey: string = '';
  audioPath: string = '';
  songJson: string = '';
  committedAt: number = 0;

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
 * Managed download storage tree (D3 decision: app sandbox; a user-picked
 * document URI directory can override the final tree since the directory
 * selection setting):
 * - working/staging: <filesDir>/download_staging/*.download + sidecars;
 * - final tree: <filesDir>/Download/NeriPlayer/<name>.<ext>, or the picked
 *   file URI directory when np.download_directory_uri is configured;
 * - catalog: preferences key `downloaded_catalog` via SchemaStore.
 */
export class DownloadStorage {
  private static context: common.Context | null = null;

  static init(context: common.Context): void {
    DownloadStorage.context = context;
    DownloadStorage.ensureDir(DownloadStorage.stagingDir());
    const dir = DownloadStorage.downloadDir();
    // User-picked document directories exist by construction (picker); mkdir
    // is not documented for URIs, so only the sandbox default is ensured.
    if (!DownloadDirectory.isCustomUri(dir)) {
      DownloadStorage.ensureDir(dir);
    }
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
    const custom = SettingsRepository.getString(SettingsRepository.KEY_DOWNLOAD_DIRECTORY_URI, '');
    return DownloadDirectory.resolveActiveDir(custom, base);
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

  /**
   * Cheap payload sanity check over the first bytes: every real audio
   * container starts with a known magic value or frame sync (see
   * isPlausibleAudioHead), never with HTML/JSON error payloads from expiring
   * CDNs or arbitrary binary. Guards the completed-task short-circuit and the
   * commit path against pinning or committing unplayable bytes.
   */
  static hasPlausibleAudioHeader(path: string): boolean {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        // 192 bytes so the MPEG-TS two-packet sync check (0x47 at 0 and 188)
        // can see both packets.
        const head = new ArrayBuffer(192);
        const read = fileIo.readSync(file.fd, head);
        return isPlausibleAudioHead(new Uint8Array(head, 0, read));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      return false;
    }
  }

  /**
   * Streaming scan for filler corruption (see fillerRunCoverage): reads the
   * file in 1 MiB blocks with a 1 KiB overlap so runs up to 1024 bytes are
   * seen intact by at least one block. True when non-pad filler runs cover
   * more than 0.5% of the file — clean transfers measure ~0%, the poisoned
   * NetEase weapi AAC payloads measure ~1.2%.
   *
   * Fails closed: an unreadable file or an incomplete scan reports corrupted
   * (true) rather than silently passing the integrity gate.
   */
  static async hasExcessiveFillerRuns(path: string): Promise<boolean> {
    const CHUNK = 1024 * 1024;
    const OVERLAP = 1024;
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        // Stat through the opened fd: a path-level statSync failure would
        // otherwise surface as size 0 ("nothing to scan") and pass the gate.
        const size = fileIo.statSync(file.fd).size;
        let covered = 0;
        let scanned = 0;
        let offset = 0;
        let incomplete = false;
        const buffer = new ArrayBuffer(CHUNK + OVERLAP);
        while (offset < size) {
          const readLen = Math.min(CHUNK + OVERLAP, size - offset);
          const read = fileIo.readSync(file.fd, buffer, { offset: offset, length: readLen });
          if (read <= 0) {
            incomplete = true;
            break;
          }
          covered += Math.round(fillerRunCoverage(new Uint8Array(buffer, 0, read)) * read);
          scanned += Math.min(read, CHUNK);
          offset += CHUNK;
        }
        if (incomplete || (size > 0 && scanned < size)) {
          return true;
        }
        return scanned > 0 && covered / scanned > 0.005;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`hasExcessiveFillerRuns scan failed (fail closed): ${e.message}`);
      return true;
    }
  }

  /** Number of files (audio + sidecars) parked in the staging directory. */
  static stagingFileCount(): number {
    try {
      return fileIo.listFileSync(DownloadStorage.stagingDir()).length;
    } catch (error) {
      return 0;
    }
  }

  /**
   * Appends a chunk to the working file, creating it when absent. The file
   * must be opened with OpenMode.APPEND and written without an offset:
   * WriteOptions.offset is an absolute file position, so passing the chunk
   * size there pinned every chunk to the same offset and committed
   * zero-holed containers AVPlayer rejects with 5400106.
   */
  static appendChunk(workingPath: string, chunk: ArrayBuffer): number {
    try {
      const exists = fileIo.accessSync(workingPath);
      const file = exists
        ? fileIo.openSync(workingPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND)
        : fileIo.openSync(workingPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        return fileIo.writeSync(file.fd, chunk);
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
   * Commits the working file into the final tree: rename inside the sandbox
   * (atomic), or an fd-to-fd copy into a user-picked document URI directory
   * (rename is not documented for URIs). Returns the final path or ''.
   */
  static commit(song: SongItem, workingPath: string, ext: string): string {
    try {
      const baseName = DownloadNaming.renderWithFallback(DownloadNaming.DEFAULT_TEMPLATE, song);
      const fileName = `${baseName}.${ext.length > 0 ? ext : 'bin'}`;
      const dir = DownloadStorage.downloadDir();
      const finalPath = DownloadDirectory.fileInDir(dir, fileName);
      if (DownloadDirectory.isCustomUri(dir)) {
        DownloadStorage.copyIntoDirectory(workingPath, finalPath);
      } else {
        fileIo.renameSync(workingPath, finalPath);
      }
      DownloadStorage.deleteWorkingSet(workingPath);
      return finalPath;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`commit failed: ${e.message}`);
      return '';
    }
  }

  /**
   * Copies the staged file onto the target URI. The openSync address follows
   * the official DOWNLOAD-mode save example (FileUri(...).path); the staging
   * copy is removed by the caller afterwards, so a mid-copy crash only leaves
   * an orphan to overwrite on retry.
   */
  private static copyIntoDirectory(workingPath: string, targetUri: string): void {
    const converted = new fileUri.FileUri(targetUri).path;
    const target = converted.length > 0 ? converted : targetUri;
    const source = fileIo.openSync(workingPath, fileIo.OpenMode.READ_ONLY);
    try {
      const dest = fileIo.openSync(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const chunk = new ArrayBuffer(512 * 1024);
        while (true) {
          const read = fileIo.readSync(source.fd, chunk);
          if (read <= 0) {
            break;
          }
          const written = fileIo.writeSync(dest.fd, chunk, { length: read });
          if (written !== read) {
            throw new Error(`short write ${written}/${read}`);
          }
        }
      } finally {
        fileIo.closeSync(dest);
      }
    } finally {
      fileIo.closeSync(source);
    }
  }

  static async addCatalogEntry(song: SongItem, audioPath: string): Promise<void> {
    const entries = await DownloadStorage.getCatalog();
    const key = stableKeyOf(song);
    const next = entries.filter((entry: DownloadedSongEntry) => entry.stableKey !== key);
    next.push(new DownloadedSongEntry(key, audioPath, song.toJson(), Date.now()));
    // Serialize the instances directly: mapping through toJson() first would
    // double-encode rows as a JSON string array, which getCatalog's object
    // parser then degrades into all-empty entries.
    const json = JSON.stringify(next);
    await SchemaStore.save('downloaded_catalog', json, (value: string) => value);
  }

  /** Wholesale catalog rewrite (stable-key migration); keeps the store key encapsulated. */
  static async replaceCatalog(entries: DownloadedSongEntry[]): Promise<void> {
    const json = JSON.stringify(entries);
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
        const entry = DownloadedSongEntry.fromRecord(raw as Record<string, Object>);
        // Drop entries written before the serializer fix (all-empty rows).
        if (entry.stableKey.length > 0) {
          entries.push(entry);
        }
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
    await DownloadStorage.removeCatalogEntryByKey(stableKeyOf(song));
  }

  static async removeCatalogEntryByKey(stableKey: string): Promise<void> {
    const entries = await DownloadStorage.getCatalog();
    const next = entries.filter((entry: DownloadedSongEntry) => entry.stableKey !== stableKey);
    const json = JSON.stringify(next);
    await SchemaStore.save('downloaded_catalog', json, (value: string) => value);
  }

  /**
   * Resolves a catalog address into an openable sandbox path: rows committed
   * against a user-picked download directory hold file:// URIs, which
   * CoreFileKit open/stat calls do not accept directly. Returns '' when the
   * URI cannot be converted; plain sandbox paths pass through unchanged.
   */
  static resolveFilePath(path: string): string {
    if (!path.startsWith('file://')) {
      return path;
    }
    try {
      const converted = new fileUri.FileUri(path).path;
      return converted.length > 0 ? converted : '';
    } catch (error) {
      const e = error as Error;
      Logger.warn(`resolveFilePath failed: ${e.message}`);
      return '';
    }
  }

  /**
   * Deletes a committed download file, tolerating missing paths and
   * user-picked file:// URI directories. Never throws.
   */
  static deleteFileQuiet(audioPath: string): void {
    DownloadStorage.deleteSidecarQuiet(audioPath);
    if (audioPath.length === 0) {
      return;
    }
    const target = DownloadStorage.resolveFilePath(audioPath);
    if (target.length === 0) {
      return;
    }
    try {
      if (fileIo.accessSync(target)) {
        fileIo.unlinkSync(target);
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`deleteFileQuiet failed: ${e.message}`);
    }
  }

  /** Writes a `<audio>.lrc` companion (DownloadLyricSidecar); never throws. */
  static writeSidecarText(path: string, text: string): void {
    if (text.trim().length === 0) {
      return;
    }
    DownloadStorage.writeTextFile(path, text);
  }

  /** Removes the `<audio>.lrc` companion when its audio file is deleted. */
  static deleteSidecarQuiet(audioPath: string): void {
    if (audioPath.length === 0) {
      return;
    }
    const dot = audioPath.lastIndexOf('.');
    const slash = audioPath.lastIndexOf('/');
    const withoutExt = dot > slash ? audioPath.substring(0, dot) : audioPath;
    const sidecar = DownloadStorage.resolveFilePath(`${withoutExt}.lrc`);
    if (sidecar.length === 0) {
      return;
    }
    try {
      if (fileIo.accessSync(sidecar)) {
        fileIo.unlinkSync(sidecar);
      }
    } catch (error) {
      const e = error as Error;
      Logger.debug(`deleteSidecarQuiet ignored: ${e.message}`);
    }
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
      return decoder.decodeToString(new Uint8Array(buffer), { stream: false });
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

/**
 * Pure byte decision behind hasPlausibleAudioHeader (unit-testable): a head
 * counts as audio only when it carries a known container magic or frame sync.
 * The broken staging writer produced NUL-holed files, expiring CDNs answer
 * with HTML/JSON (leading '<'/'{'/'[', optionally after whitespace), and any
 * other binary (e.g. 'abcd') must not pass — none carry these signatures.
 */
const AUDIO_HEAD_MAGICS: number[][] = [
  [0x49, 0x44, 0x33],             // ID3 (tagged mp3)
  [0x66, 0x4C, 0x61, 0x43],       // fLaC
  [0x4F, 0x67, 0x67, 0x53],       // OggS (ogg/opus/vorbis)
  [0x52, 0x49, 0x46, 0x46],       // RIFF (wav)
  [0x30, 0x26, 0xB2, 0x75],       // ASF (wma)
  [0x23, 0x21, 0x41, 0x4D, 0x52], // #!AMR
  [0x1A, 0x45, 0xDF, 0xA3]        // EBML (webm/mkv audio)
];

function matchesMagicAt(head: Uint8Array, offset: number, magic: number[]): boolean {
  if (head.length < offset + magic.length) {
    return false;
  }
  for (let i = 0; i < magic.length; i++) {
    if (head[offset + i] !== magic[i]) {
      return false;
    }
  }
  return true;
}

export function isPlausibleAudioHead(head: Uint8Array): boolean {
  if (head.length < 4) {
    return false;
  }
  for (const magic of AUDIO_HEAD_MAGICS) {
    if (matchesMagicAt(head, 0, magic)) {
      return true;
    }
  }
  // MPEG audio / ADTS AAC frame sync: the first 11 bits are all set.
  if (head[0] === 0xFF && (head[1] & 0xE0) === 0xE0) {
    return true;
  }
  // ISO-BMFF (m4a/mp4/3gp): 4-byte box size (may lead with NULs) + 'ftyp'.
  if (matchesMagicAt(head, 4, [0x66, 0x74, 0x79, 0x70])) {
    return true;
  }
  // MPEG-TS: 0x47 sync byte at every 188-byte packet boundary; a single
  // leading 0x47 is not enough (GIF also starts with it).
  if (head[0] === 0x47 && head.length > 188 && head[188] === 0x47) {
    return true;
  }
  return false;
}

/**
 * Offset of the first run of `minRun` identical bytes in the buffer, or -1.
 * Pure and unit-testable; used to flag the periodic filler runs that poison
 * otherwise valid-looking downloads (5400106 CONTAINER_ERR on play).
 */
export function findLongIdenticalRun(bytes: Uint8Array, minRun: number): number {
  const n = bytes.length;
  if (minRun <= 1 && n > 0) {
    return 0;
  }
  let runStart = 0;
  for (let i = 1; i < n; i++) {
    if (bytes[i] !== bytes[runStart]) {
      if (i - runStart >= minRun) {
        return runStart;
      }
      runStart = i;
    }
  }
  return n - runStart >= minRun ? runStart : -1;
}

/** Benign long runs: ID3/encoder padding and VBR filler patterns. */
const BENIGN_PAD_BYTES: Set<number> = new Set<number>([0x00, 0xFF, 0xAA, 0x55]);

/**
 * Share of the buffer (0..1) covered by runs of >=64 identical bytes whose
 * value is not a benign pad. Pure and unit-testable: the NetEase weapi AAC
 * CDN injects periodic filler (~1.2% of bytes, values in a small non-pad
 * cycle) that streams fine but breaks committed local playback, while clean
 * mp3/m4a transfers stay at ~0% under this metric.
 */
export function fillerRunCoverage(bytes: Uint8Array): number {
  const n = bytes.length;
  if (n === 0) {
    return 0;
  }
  let covered = 0;
  let runStart = 0;
  for (let i = 1; i <= n; i++) {
    if (i === n || bytes[i] !== bytes[runStart]) {
      const runLen = i - runStart;
      if (runLen >= 64 && !BENIGN_PAD_BYTES.has(bytes[runStart])) {
        covered += runLen;
      }
      runStart = i;
    }
  }
  return covered / n;
}

// Re-export for callers that use the preferences-backed store directly.
export { AppPreferences };
