// SPDX-License-Identifier: GPL-3.0

/**
 * M9.2 crash diagnostics — pure models mirroring the Android crash chain
 * (ExceptionHandler + CrashReportStore + AnrWatchdog semantics):
 *
 * - fault rows from both channels — the startup history pull (faultLogger,
 *   the only way to observe the crash that killed the previous process) and
 *   the live HiAppEvent subscription — are normalized into DiagnosticRecord
 *   entries;
 * - records are deduplicated by identity (kind + time + pid) and kept in a
 *   bounded ring, mirroring the pending_startup_crash.flag + crashes/
 *   directory pair on Android;
 * - SafeMode is armed only for faults inside the arming window
 *   (faultArmsSafeModeSince), because the pull channel re-reads the whole OS
 *   fault history on every launch, including faults from days ago;
 * - text destined for files, exports or the clipboard is sanitized first:
 *   query strings are stripped from URLs (googlevideo/netease URLs carry
 *   auth tokens) and long opaque blobs are folded away.
 *
 * Zero platform imports so the whole module is unit-testable in hypium.
 */

export class DiagKind {
  static readonly JS_CRASH: string = 'JS_CRASH';
  static readonly CPP_CRASH: string = 'CPP_CRASH';
  /**
   * The OS/APP_CRASH aggregate event without a crashtype param — fatal, but
   * the JS/native distinction is unknown. The subscription channel delivers
   * this shape for a crash that just killed the previous process
   * (device-observed 2026-08-24); the history pull later resolves the same
   * fault to JS_CRASH or CPP_CRASH and replaces the record.
   */
  static readonly APP_CRASH: string = 'APP_CRASH';
  static readonly APP_FREEZE: string = 'APP_FREEZE';
  static readonly ADDRESS_SANITIZER: string = 'ADDRESS_SANITIZER';
  static readonly MAIN_THREAD_JANK: string = 'MAIN_THREAD_JANK';
  static readonly OTHER: string = 'OTHER';
}

/** Kinds that mark "the app died or was frozen" and arm the SafeMode flag. */
export function kindArmsSafeMode(kind: string): boolean {
  return kind === DiagKind.JS_CRASH || kind === DiagKind.CPP_CRASH
    || kind === DiagKind.APP_CRASH || kind === DiagKind.APP_FREEZE;
}

/**
 * SafeMode arming window. Android writes pending_startup_crash.flag at crash
 * time and consumes it on the next launch, so the flag means exactly "the
 * session that just ended died". HarmonyOS has no write-at-crash hook: the
 * flag has to be armed while walking a fault *history* the system keeps for
 * days, so without a window an old crash would force SafeMode on every launch
 * (device-observed 2026-08-24: four historical JS crashes and one C++ crash
 * put a freshly installed build straight into SafeMode). The window is
 * reconstructed from a persisted startup high-water mark — only a fault at or
 * after the previous launch can belong to the session that died.
 *
 * armFromMs === 0 means no mark exists yet (first launch of a build carrying
 * diagnostics, e.g. an update over an older install): pre-existing history is
 * then informational only and must never force SafeMode.
 */
export function faultArmsSafeModeSince(kind: string, faultTimeMs: number, armFromMs: number): boolean {
  if (!kindArmsSafeMode(kind)) {
    return false;
  }
  if (armFromMs <= 0 || faultTimeMs <= 0) {
    return false;
  }
  return faultTimeMs >= armFromMs;
}

/**
 * Maps a HiAppEvent fault event name (and optional crash type param) to a
 * normalized diagnostic kind. Known shapes come from the system event
 * overview (APP_CRASH aggregate, APP_FREEZE, ADDRESS_SANITIZER,
 * MAIN_THREAD_JANK); unknown names degrade to OTHER instead of throwing.
 */
export function diagnosticKindFor(name: string, crashType: string): string {
  const normalized = (name + '|' + crashType).toUpperCase();
  if (normalized.includes('JSERROR') || normalized.includes('JS_ERROR') || normalized.includes('JS_CRASH')
    || normalized.includes('JSCRASH') || normalized.includes('TYPE_ERROR') || normalized.includes('RANGE_ERROR')) {
    return DiagKind.JS_CRASH;
  }
  if (normalized.includes('CPPCRASH') || normalized.includes('CPP_CRASH') || normalized.includes('SIGSEGV')
    || normalized.includes('SIGABRT')) {
    return DiagKind.CPP_CRASH;
  }
  if (normalized.includes('FREEZE') || normalized.includes('THREAD_BLOCK')) {
    return DiagKind.APP_FREEZE;
  }
  if (normalized.includes('ADDRESS_SANITIZER')) {
    return DiagKind.ADDRESS_SANITIZER;
  }
  if (normalized.includes('MAIN_THREAD_JANK')) {
    return DiagKind.MAIN_THREAD_JANK;
  }
  // Least specific, checked last: the aggregate crash event with no crashtype
  // to narrow it down. Must not fall through to OTHER — OTHER never arms
  // SafeMode, and this event means the app died.
  if (normalized.includes('APP_CRASH')) {
    return DiagKind.APP_CRASH;
  }
  return DiagKind.OTHER;
}

export class DiagnosticRecord {
  readonly id: string;
  readonly kind: string;
  readonly eventName: string;
  readonly domain: string;
  readonly timeMs: number;
  readonly pid: number;
  readonly uid: number;
  readonly summary: string;
  readonly fileName: string;

  constructor(kind: string, eventName: string, domain: string, timeMs: number, pid: number, uid: number,
    summary: string, fileName: string) {
    this.id = `${kind}@${timeMs}@${pid}`;
    this.kind = kind;
    this.eventName = eventName;
    this.domain = domain;
    this.timeMs = timeMs;
    this.pid = pid;
    this.uid = uid;
    this.summary = summary;
    this.fileName = fileName;
  }

  static recordId(kind: string, timeMs: number, pid: number): string {
    return `${kind}@${timeMs}@${pid}`;
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['id'] = this.id;
    out['kind'] = this.kind;
    out['eventName'] = this.eventName;
    out['domain'] = this.domain;
    out['timeMs'] = this.timeMs;
    out['pid'] = this.pid;
    out['uid'] = this.uid;
    out['summary'] = this.summary;
    out['fileName'] = this.fileName;
    return out;
  }

  static fromJson(raw: Record<string, Object>): DiagnosticRecord | null {
    const kind = String(raw['kind'] ?? '');
    const timeMs = Number(raw['timeMs'] ?? 0);
    const pid = Number(raw['pid'] ?? 0);
    if (kind.length === 0 || !Number.isFinite(timeMs) || timeMs <= 0) {
      return null;
    }
    return new DiagnosticRecord(
      kind,
      String(raw['eventName'] ?? ''),
      String(raw['domain'] ?? ''),
      timeMs,
      Number.isFinite(pid) ? pid : 0,
      Number(raw['uid'] ?? 0),
      String(raw['summary'] ?? ''),
      String(raw['fileName'] ?? '')
    );
  }
}

const SUMMARY_CAP: number = 120;
export const DETAIL_CAP: number = 32 * 1024;
export const EXPORT_CAP: number = 64 * 1024;
const DIAGNOSTIC_RING_CAP: number = 20;

/**
 * Removes secrets from diagnostic text: URL query strings (streaming URLs
 * and player API responses embed tokens) and opaque blobs ≥ 40 chars
 * (cookie values, PoToken-ish payloads). Stack frames, class names and
 * file/line references survive untouched.
 */
export function sanitizeDiagnosticText(text: string): string {
  let out = text.replace(/https?:\/\/[^\s"'<>)]+/g, (url: string): string => {
    const queryAt = url.indexOf('?');
    return queryAt > 0 ? url.substring(0, queryAt) + '?<redacted>' : url;
  });
  out = out.replace(/[A-Za-z0-9+/=_-]{40,}/g, (blob: string): string => `<blob:${blob.length}>`);
  return out;
}

export function trimToCap(text: string, cap: number): string {
  if (text.length <= cap) {
    return text;
  }
  return text.substring(0, cap) + `\n…(截断，原长度 ${text.length})`;
}

/**
 * Single reused Date instance for epoch→ISO formatting: the report builder
 * formats one timestamp per record inside a loop, and allocating a Date per
 * iteration trips @performance/reuse-date-instances-check. ArkTS is
 * single-threaded and no await sits between setTime and toISOString, so the
 * scratch instance cannot be observed mid-update.
 */
const isoScratch: Date = new Date(0);

export function isoTime(timeMs: number): string {
  isoScratch.setTime(timeMs);
  return isoScratch.toISOString();
}

/** One-line record summary shared by the SafeMode and DebugPage listings. */
export function formatRecordLine(record: DiagnosticRecord): string {
  return `[${record.kind}] ${isoTime(record.timeMs)} pid=${record.pid} ${record.summary}`;
}

function readString(record: Record<string, Object>, key: string): string {
  const value = record[key];
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

function readNumber(record: Record<string, Object>, key: string): number {
  const value = record[key];
  if (value === undefined || value === null) {
    return 0;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function readStringArray(record: Record<string, Object>, key: string): string[] {
  const value = record[key];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return [];
  }
  const items: Object[] = value as Object[];
  const out: string[] = [];
  for (const item of items) {
    if (item !== undefined && item !== null) {
      out.push(String(item));
    }
  }
  return out;
}

/** Result of normalizing one fault event. */
export interface DiagnosticExtraction {
  record: DiagnosticRecord;
  detail: string;
}

/**
 * Normalizes a faultLogger.FaultLogInfo row (startup history query — the
 * HiAppEvent subscription does not replay past faults, so the previous
 * crash is pulled via querySelfFaultLog on the next launch, mirroring
 * Android AnrWatchdog.capturePreviousAnrIfNeeded). timestamp is in
 * seconds, reason/module identify the fault, fullLog carries the stack.
 */
export function faultLogToDiagnostic(kind: string, timeSec: number, pid: number, uid: number,
  reason: string, module: string, fullLog: string): DiagnosticExtraction {
  // d.ts documents "second level" but API 24 devices deliver milliseconds
  // (device-observed 2026-08-24); normalize both shapes defensively.
  const timeMs = timeSec >= 1e12 ? timeSec : (timeSec > 0 ? timeSec * 1000 : 0);
  const summary = trimToCap(`${reason} @ ${module}`.replace(/\s+/g, ' ').trim(), SUMMARY_CAP);
  const record = new DiagnosticRecord(kind, kind, 'FAULTLOG', timeMs, pid, uid, summary, '');
  const detail = `kind: ${kind}\nreason: ${sanitizeDiagnosticText(reason)}\nmodule: ${module}\n`
    + `time: ${isoTime(timeMs)}\npid/uid: ${pid}/${uid}\n--- full log ---\n`
    + trimToCap(sanitizeDiagnosticText(fullLog), DETAIL_CAP);
  const extraction: DiagnosticExtraction = { record: record, detail: detail };
  return extraction;
}

/**
 * Normalizes one HiAppEvent fault params object into a record plus the full
 * sanitized detail text. `time` arrives in milliseconds in current system
 * events but older shapes used seconds — both are accepted.
 */
export function extractDiagnostic(domain: string, eventName: string, params: Record<string, Object>):
  DiagnosticExtraction {
  const crashType = readString(params, 'crashtype');
  const kind = diagnosticKindFor(eventName, crashType);
  const rawTime = readNumber(params, 'time');
  const timeMs = rawTime >= 1e12 ? rawTime : rawTime * 1000;
  const pid = readNumber(params, 'pid');
  const uid = readNumber(params, 'uid');
  const reason = readString(params, 'reason');
  const stack = sanitizeDiagnosticText(readString(params, 'crashstack'));
  const externalLogs = readStringArray(params, 'external_log').map((name: string): string => sanitizeDiagnosticText(name));

  const summaryParts: string[] = [];
  if (reason.length > 0) {
    summaryParts.push(trimToCap(reason.replace(/\s+/g, ' ').trim(), SUMMARY_CAP));
  }
  if (stack.length > 0) {
    const firstFrame = stack.split('\n').find((line: string): boolean => line.trim().length > 0);
    if (firstFrame !== undefined) {
      summaryParts.push(trimToCap(firstFrame.trim(), SUMMARY_CAP));
    }
  }
  if (summaryParts.length === 0) {
    summaryParts.push(`${eventName}(无摘要)`);
  }
  const record = new DiagnosticRecord(kind, eventName, domain, timeMs, pid, uid,
    summaryParts.join(' | '), '');
  const detailLines: string[] = [
    `kind: ${kind}`,
    `event: ${eventName} (domain ${domain})`,
    `time: ${isoTime(timeMs)}`,
    `pid/uid: ${pid}/${uid}`
  ];
  if (reason.length > 0) {
    detailLines.push(`reason: ${sanitizeDiagnosticText(reason)}`);
  }
  if (externalLogs.length > 0) {
    detailLines.push(`system log files: ${externalLogs.join(', ')}`);
  }
  if (stack.length > 0) {
    detailLines.push('--- stack ---');
    detailLines.push(trimToCap(stack, DETAIL_CAP));
  }
  const extraction: DiagnosticExtraction = {
    record: record,
    detail: detailLines.join('\n')
  };
  return extraction;
}

/**
 * How precisely a kind names the fault. The two channels see the same crash
 * at different resolutions — the subscription reports the OS/APP_CRASH
 * aggregate, the history pull reports JS_CRASH or CPP_CRASH — so the ring
 * keeps the sharper one instead of listing the fault twice.
 */
function kindSpecificity(kind: string): number {
  if (kind === DiagKind.OTHER) {
    return 0;
  }
  if (kind === DiagKind.APP_CRASH) {
    return 1;
  }
  return 2;
}

/**
 * Merges an incoming record into the ring: identity duplicates (the startup
 * pull re-reads the same OS fault history on every launch) are skipped, a
 * coarser view of an already-known fault is either dropped or upgraded in
 * place, and the oldest entries are dropped beyond the cap. Returns null when
 * nothing changed.
 */
export function mergeDiagnosticRecord(existing: DiagnosticRecord[], incoming: DiagnosticRecord):
  DiagnosticRecord[] | null {
  for (let i = 0; i < existing.length; i++) {
    const item = existing[i];
    if (item.id === incoming.id) {
      return null;
    }
    // Same process, same millisecond: one fault reported by both channels.
    // Two genuinely distinct faults cannot share that pair.
    if (incoming.timeMs > 0 && item.timeMs === incoming.timeMs && item.pid === incoming.pid) {
      if (kindSpecificity(incoming.kind) <= kindSpecificity(item.kind)) {
        return null;
      }
      const upgraded = existing.slice();
      upgraded[i] = incoming;
      return upgraded;
    }
  }
  const merged = existing.slice();
  merged.push(incoming);
  if (merged.length > DIAGNOSTIC_RING_CAP) {
    return merged.slice(merged.length - DIAGNOSTIC_RING_CAP);
  }
  return merged;
}

/** Formats the exportable report (SafeMode export / DebugPage export). */
export function formatDiagnosticReport(records: DiagnosticRecord[], detailsById: Map<string, string>,
  recentLogLines: string[], nowMs: number): string {
  const lines: string[] = [
    'NeriPlayer 诊断报告 (HarmonyOS)',
    `生成时间: ${isoTime(nowMs)}`,
    `记录数: ${records.length}`
  ];
  for (const record of records) {
    lines.push('');
    lines.push(`== [${record.kind}] ${isoTime(record.timeMs)} ${record.eventName} pid=${record.pid} ==`);
    lines.push(`摘要: ${record.summary}`);
    const detail = detailsById.get(record.id);
    if (detail !== undefined && detail.length > 0) {
      lines.push(detail);
    }
  }
  if (recentLogLines.length > 0) {
    lines.push('');
    lines.push(`== 最近应用日志（${recentLogLines.length} 行，进程内存环，崩溃前窗口） ==`);
    lines.push(recentLogLines.join('\n'));
  }
  return trimToCap(lines.join('\n'), EXPORT_CAP);
}

/** CrashLogFiles-style name: {prefix}_{yyyyMMdd_HHmmss}_p{pid}.txt */
export function diagnosticFileName(kind: string, timeMs: number, pid: number): string {
  const d = new Date(timeMs);
  const pad = (n: number): string => (n < 10 ? '0' + n : `${n}`);
  const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}`
    + `${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `diag_${kind}_${stamp}_p${pid}.txt`;
}
