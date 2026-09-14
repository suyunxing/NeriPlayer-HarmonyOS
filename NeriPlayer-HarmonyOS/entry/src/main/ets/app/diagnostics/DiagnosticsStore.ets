// SPDX-License-Identifier: GPL-3.0

import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { Logger } from '../Logger';
import { AppPreferences } from '../../data/AppPreferences';
import { SchemaStore } from '../../data/schema/SchemaStore';
import { utf8Decode } from '../../sync/SyncDataJsonCodec';
import {
  DiagnosticRecord,
  diagnosticFileName,
  extractDiagnostic,
  formatDiagnosticReport,
  mergeDiagnosticRecord
} from './DiagnosticsModels';

const INDEX_KEY: string = 'diagnostics_records';

/**
 * Persistence side of the M9.2 crash diagnostics loop (Android counterpart:
 * CrashReportStore + the crashes/ directory):
 *
 * - a SchemaStore-versioned index key holds the bounded record ring
 *   (summaries only, keeping the preferences payload small);
 * - each record's full sanitized detail goes to its own file under
 *   files/diagnostics/, named {prefix}_{yyyyMMdd_HHmmss}_p{pid}.txt like
 *   CrashLogFiles.kt;
 * - exports assemble every detail plus the in-memory log ring into one
 *   text report, written either into the sandbox (clipboard source) or
 *   through DocumentViewPicker into user-chosen storage.
 */
export class DiagnosticsStore {
  private static dir: string = '';
  private static initialized: boolean = false;
  /**
   * Serializes index mutations. Both channels append concurrently — the
   * startup pull awaits faultLogger while a live fault event arrives — and
   * each append is a read-modify-write of one preferences key followed by a
   * prune of the detail directory. Interleaved, the later save overwrites the
   * earlier record and the prune then deletes its detail file as an orphan
   * (device-observed 2026-08-24: the pull's JS_CRASH row and its file were
   * both lost to the subscription's APP_CRASH row landing 16 ms later, so the
   * fault survived only in its coarse form). The chain never rejects, so one
   * failed append cannot stall the rest.
   */
  private static mutations: Promise<void> = Promise.resolve();

  static init(context: common.Context): void {
    if (DiagnosticsStore.initialized) {
      return;
    }
    DiagnosticsStore.dir = `${context.filesDir}/diagnostics`;
    try {
      if (!fileIo.accessSync(DiagnosticsStore.dir)) {
        fileIo.mkdirSync(DiagnosticsStore.dir, true);
      }
      DiagnosticsStore.initialized = true;
    } catch (error) {
      Logger.warn(`DiagnosticsStore: cannot create dir: ${(error as Error).message}`);
    }
  }

  static isInitialized(): boolean {
    return DiagnosticsStore.initialized;
  }

  /** Parses the persisted index; corrupt lines are dropped, never thrown. */
  static parseIndex(json: string): DiagnosticRecord[] {
    try {
      const arr: Object[] = JSON.parse(json) as Object[];
      if (!Array.isArray(arr)) {
        return [];
      }
      const out: DiagnosticRecord[] = [];
      for (const item of arr) {
        const record = DiagnosticRecord.fromJson(item as Record<string, Object>);
        if (record !== null) {
          out.push(record);
        }
      }
      return out;
    } catch (error) {
      return [];
    }
  }

  static async listRecords(): Promise<DiagnosticRecord[]> {
    const json = await AppPreferences.getString(INDEX_KEY, '');
    return DiagnosticsStore.parseIndex(json);
  }

  /**
   * Normalizes a raw fault event params object and persists it. Returns the
   * stored record, or null when it is a duplicate of an already-known fault
   * (the startup pull re-reads the system's whole retained fault history on
   * every launch).
   */
  static async appendFromEvent(domain: string, eventName: string, params: Record<string, Object>):
    Promise<DiagnosticRecord | null> {
    const extraction = extractDiagnostic(domain, eventName, params);
    const record = extraction.record;
    const detail = extraction.detail;
    const named = new DiagnosticRecord(record.kind, record.eventName, record.domain, record.timeMs,
      record.pid, record.uid, record.summary, diagnosticFileName(record.kind, record.timeMs, record.pid));
    const stored = await DiagnosticsStore.appendRecord(named, detail);
    return stored ? named : null;
  }

  /** Directly stores an already-built record (device tests, migrations). */
  static appendRecord(record: DiagnosticRecord, detail: string): Promise<boolean> {
    const queued: Promise<boolean> = DiagnosticsStore.mutations
      .then((): Promise<boolean> => DiagnosticsStore.appendLocked(record, detail));
    DiagnosticsStore.mutations = queued.then((): void => {}, (): void => {});
    return queued;
  }

  private static async appendLocked(record: DiagnosticRecord, detail: string): Promise<boolean> {
    let named = record;
    if (named.fileName.length === 0) {
      named = new DiagnosticRecord(record.kind, record.eventName, record.domain, record.timeMs,
        record.pid, record.uid, record.summary, diagnosticFileName(record.kind, record.timeMs, record.pid));
    }
    const existing = await DiagnosticsStore.listRecords();
    const merged = mergeDiagnosticRecord(existing, named);
    if (merged === null) {
      return false;
    }
    await SchemaStore.save(INDEX_KEY, merged, (records: DiagnosticRecord[]): string => {
      return JSON.stringify(records.map((item: DiagnosticRecord): Record<string, Object> => item.toJson()));
    });
    DiagnosticsStore.writeDetailFile(named.fileName, detail);
    DiagnosticsStore.pruneDetailFiles(merged);
    return true;
  }

  static async readDetail(id: string): Promise<string> {
    const records = await DiagnosticsStore.listRecords();
    for (const record of records) {
      if (record.id === id && record.fileName.length > 0) {
        return DiagnosticsStore.readFileText(record.fileName);
      }
    }
    return '';
  }

  /** Wipes the index and every detail file; joins the append queue. */
  static clearAll(): Promise<void> {
    const queued: Promise<void> = DiagnosticsStore.mutations
      .then((): Promise<void> => DiagnosticsStore.clearLocked());
    DiagnosticsStore.mutations = queued.then((): void => {}, (): void => {});
    return queued;
  }

  private static async clearLocked(): Promise<void> {
    await AppPreferences.putString(INDEX_KEY, '[]');
    if (!DiagnosticsStore.initialized) {
      return;
    }
    try {
      const names = fileIo.listFileSync(DiagnosticsStore.dir);
      for (const name of names) {
        const fileName = typeof name === 'string' ? name : String(name);
        if (fileName.endsWith('.txt')) {
          fileIo.unlinkSync(`${DiagnosticsStore.dir}/${fileName}`);
        }
      }
    } catch (error) {
      Logger.warn(`DiagnosticsStore: clear files failed: ${(error as Error).message}`);
    }
  }

  /**
   * Assembles the full export report: header, every record with its detail
   * file content, and the recent in-memory log ring.
   */
  static async buildExportReport(recentLogLines: string[], nowMs: number): Promise<string> {
    const records = await DiagnosticsStore.listRecords();
    const details = new Map<string, string>();
    for (const record of records) {
      if (record.fileName.length > 0) {
        details.set(record.id, DiagnosticsStore.readFileText(record.fileName));
      }
    }
    return formatDiagnosticReport(records, details, recentLogLines, nowMs);
  }

  /**
   * Saves the report through DocumentViewPicker. Returns a user-facing
   * result message (toast-ready); cancellation resolves as "已取消".
   */
  static async exportViaPicker(reportText: string): Promise<string> {
    const docPicker = new picker.DocumentViewPicker();
    const uris = await docPicker.save({ newFileNames: ['neriplayer-diagnostics.txt'] });
    if (uris.length === 0) {
      return '已取消导出';
    }
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, reportText);
    } finally {
      fileIo.closeSync(file);
    }
    return `诊断报告已导出（${reportText.length} 字符）`;
  }

  /**
   * Deletes detail files no longer referenced by the index. The ring is
   * bounded but the files were not: evicted records and records upgraded to a
   * sharper kind (APP_CRASH -> JS_CRASH) both leave their file behind, so the
   * directory would grow without limit across a crash loop.
   */
  private static pruneDetailFiles(records: DiagnosticRecord[]): void {
    if (!DiagnosticsStore.initialized) {
      return;
    }
    const keep = new Set<string>();
    for (const record of records) {
      if (record.fileName.length > 0) {
        keep.add(record.fileName);
      }
    }
    try {
      const names = fileIo.listFileSync(DiagnosticsStore.dir);
      for (const name of names) {
        const fileName = typeof name === 'string' ? name : String(name);
        if (fileName.endsWith('.txt') && !keep.has(fileName)) {
          fileIo.unlinkSync(`${DiagnosticsStore.dir}/${fileName}`);
        }
      }
    } catch (error) {
      Logger.warn(`DiagnosticsStore: prune details failed: ${(error as Error).message}`);
    }
  }

  private static writeDetailFile(fileName: string, detail: string): void {
    if (!DiagnosticsStore.initialized || fileName.length === 0) {
      return;
    }
    try {
      const path = `${DiagnosticsStore.dir}/${fileName}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, detail);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      Logger.warn(`DiagnosticsStore: write detail failed: ${(error as Error).message}`);
    }
  }

  private static readFileText(fileName: string): string {
    if (!DiagnosticsStore.initialized || fileName.length === 0) {
      return '';
    }
    try {
      const path = `${DiagnosticsStore.dir}/${fileName}`;
      const stat = fileIo.statSync(path);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        return utf8Decode(new Uint8Array(buffer));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      return '';
    }
  }
}
