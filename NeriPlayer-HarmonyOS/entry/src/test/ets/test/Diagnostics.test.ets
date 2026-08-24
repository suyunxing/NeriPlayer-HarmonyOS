import { describe, it, expect } from '@ohos/hypium';
import {
  DETAIL_CAP,
  DiagKind,
  DiagnosticRecord,
  EXPORT_CAP,
  diagnosticFileName,
  diagnosticKindFor,
  extractDiagnostic,
  faultArmsSafeModeSince,
  faultLogToDiagnostic,
  formatDiagnosticReport,
  formatRecordLine,
  isoTime,
  kindArmsSafeMode,
  mergeDiagnosticRecord,
  sanitizeDiagnosticText,
  trimToCap
} from '../../../main/ets/app/diagnostics/DiagnosticsModels';

function jsCrashParams(timeMs: number, pid: number): Record<string, Object> {
  const params: Record<string, Object> = {};
  params['time'] = timeMs;
  params['pid'] = pid;
  params['uid'] = 200;
  params['crashtype'] = 'TypeError';
  params['reason'] = 'Cannot read property x of undefined';
  params['crashstack'] = 'Error: boom\n    at Foo (Index.ets:42)';
  params['external_log'] = ['jscrash-20260824.txt'];
  return params;
}

export default function diagnosticsTest(): void {
  describe('DiagnosticsModels', (): void => {
    it('diagnosticKindFor maps known and unknown fault names', 0, (): void => {
      expect(diagnosticKindFor('JSCRASH', '')).assertEqual(DiagKind.JS_CRASH);
      expect(diagnosticKindFor('JS_ERROR', '')).assertEqual(DiagKind.JS_CRASH);
      expect(diagnosticKindFor('APP_CRASH', 'type_error')).assertEqual(DiagKind.JS_CRASH);
      expect(diagnosticKindFor('CPPCRASH', '')).assertEqual(DiagKind.CPP_CRASH);
      expect(diagnosticKindFor('APP_FREEZE', '')).assertEqual(DiagKind.APP_FREEZE);
      expect(diagnosticKindFor('THREAD_BLOCK', '')).assertEqual(DiagKind.APP_FREEZE);
      expect(diagnosticKindFor('ADDRESS_SANITIZER', '')).assertEqual(DiagKind.ADDRESS_SANITIZER);
      expect(diagnosticKindFor('MAIN_THREAD_JANK', '')).assertEqual(DiagKind.MAIN_THREAD_JANK);
      expect(diagnosticKindFor('SOMETHING_NEW', '')).assertEqual(DiagKind.OTHER);
      // The aggregate event the subscription delivers for the previous
      // process's crash: no crashtype to narrow it down, but it must not
      // degrade to OTHER (device-observed 2026-08-24 — OTHER never arms
      // SafeMode, so the crash would have been recorded and then ignored).
      expect(diagnosticKindFor('APP_CRASH', '')).assertEqual(DiagKind.APP_CRASH);
      // A crashtype still wins over the aggregate name.
      expect(diagnosticKindFor('APP_CRASH', 'SIGSEGV')).assertEqual(DiagKind.CPP_CRASH);
    });

    it('kindArmsSafeMode covers fatal kinds only', 0, (): void => {
      expect(kindArmsSafeMode(DiagKind.JS_CRASH)).assertTrue();
      expect(kindArmsSafeMode(DiagKind.CPP_CRASH)).assertTrue();
      expect(kindArmsSafeMode(DiagKind.APP_CRASH)).assertTrue();
      expect(kindArmsSafeMode(DiagKind.APP_FREEZE)).assertTrue();
      expect(kindArmsSafeMode(DiagKind.MAIN_THREAD_JANK)).assertFalse();
      expect(kindArmsSafeMode(DiagKind.ADDRESS_SANITIZER)).assertFalse();
      expect(kindArmsSafeMode(DiagKind.OTHER)).assertFalse();
    });

    it('extractDiagnostic normalizes ms/second timestamps and fields', 0, (): void => {
      const ms = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(1719733292909, 1234));
      expect(ms.record.kind).assertEqual(DiagKind.JS_CRASH);
      expect(ms.record.timeMs).assertEqual(1719733292909);
      expect(ms.record.pid).assertEqual(1234);
      expect(ms.record.id).assertEqual(`JS_CRASH@1719733292909@1234`);
      expect(ms.record.summary.includes('Cannot read property')).assertTrue();
      expect(ms.detail.includes('at Foo (Index.ets:42)')).assertTrue();
      expect(ms.detail.includes('jscrash-20260824.txt')).assertTrue();

      const seconds = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(1719733292, 1234));
      expect(seconds.record.timeMs).assertEqual(1719733292000);
    });

    it('extractDiagnostic tolerates missing params', 0, (): void => {
      const params: Record<string, Object> = {};
      const out = extractDiagnostic('OS', 'MYSTERY_FAULT', params);
      expect(out.record.kind).assertEqual(DiagKind.OTHER);
      expect(out.record.timeMs).assertEqual(0);
      expect(out.record.summary.includes('MYSTERY_FAULT')).assertTrue();
      expect(out.detail.includes('event: MYSTERY_FAULT')).assertTrue();
    });

    it('faultLogToDiagnostic maps faultLogger history rows', 0, (): void => {
      // Seconds shape (d.ts documentation) and milliseconds shape (what API
      // 24 devices actually deliver) both normalize to epoch milliseconds.
      const seconds = faultLogToDiagnostic(DiagKind.JS_CRASH, 1719733292, 1234, 200,
        'TypeError: boom', 'entry', 'Reason:TypeError\n    at Foo (Index.ets:42)');
      expect(seconds.record.timeMs).assertEqual(1719733292000);
      const extraction = faultLogToDiagnostic(DiagKind.JS_CRASH, 1719733292003, 1234, 200,
        'TypeError: boom', 'entry', 'Reason:TypeError\n    at Foo (Index.ets:42)');
      expect(extraction.record.kind).assertEqual(DiagKind.JS_CRASH);
      expect(extraction.record.timeMs).assertEqual(1719733292003);
      expect(extraction.record.id).assertEqual('JS_CRASH@1719733292003@1234');
      expect(extraction.record.summary.includes('TypeError')).assertTrue();
      expect(extraction.detail.includes('Reason:TypeError')).assertTrue();
      expect(extraction.detail.includes('Index.ets:42')).assertTrue();
      // Identity aligns with extractDiagnostic records: dedup works across
      // the pull and subscription channels.
      const live = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(1719733292003, 1234)).record;
      expect(live.id).assertEqual(extraction.record.id);

      // A multi-megabyte native fullLog is capped so preferences and the
      // detail file stay bounded. Uses realistic frame lines: a single
      // homogeneous run would be folded to <blob:N> by the sanitizer first
      // and never reach the cap.
      const frame = '    #12 pc 0000004a5b6c /system/lib/libark.so (Foo::bar+123)\n';
      const huge = faultLogToDiagnostic(DiagKind.CPP_CRASH, 1719733292, 1, 2, 'SIGSEGV', 'entry',
        frame.repeat(Math.ceil(DETAIL_CAP * 2 / frame.length)));
      expect(huge.detail.length < DETAIL_CAP + 1024).assertTrue();
      expect(huge.detail.includes('截断')).assertTrue();
      expect(huge.detail.includes('libark.so')).assertTrue();
    });

    it('sanitizeDiagnosticText strips URL queries and folds opaque blobs', 0, (): void => {
      const url = 'https://rr4---sn-a5mekn6k.googlevideo.com/videoplayback?id=abc&signature=huge';
      const sanitizedUrl = sanitizeDiagnosticText(url);
      expect(sanitizedUrl.includes('googlevideo.com/videoplayback')).assertTrue();
      expect(sanitizedUrl.includes('id=abc')).assertFalse();
      expect(sanitizedUrl.includes('<redacted>')).assertTrue();

      const blob = 'MUSIC_U=' + 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8s9T0u1V2w3x4';
      const sanitizedBlob = sanitizeDiagnosticText(blob);
      // The whole "MUSIC_U=<value>" run is one opaque token and folds away.
      expect(sanitizedBlob.includes('<blob:')).assertTrue();
      expect(sanitizedBlob.includes('MUSIC_U')).assertFalse();

      // Stack frames survive untouched.
      const stack = '    at loadSong (PlayerManager.ets:231)';
      expect(sanitizeDiagnosticText(stack)).assertEqual(stack);
    });

    it('mergeDiagnosticRecord dedups by identity and caps the ring', 0, (): void => {
      const baseTime = 1719730000000;
      const base: DiagnosticRecord[] = [];
      const first = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(baseTime, 1)).record;
      let ring = mergeDiagnosticRecord(base, first) ?? [];
      expect(ring.length).assertEqual(1);
      // Same fault replayed by the history replay: dropped.
      const again = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(baseTime, 1)).record;
      expect(mergeDiagnosticRecord(ring, again)).assertNull();

      for (let i = 2; i <= 30; i++) {
        const record = extractDiagnostic('OS', 'APP_FREEZE', jsCrashParams(baseTime + i * 1000, 1)).record;
        const merged = mergeDiagnosticRecord(ring, record);
        if (merged !== null) {
          ring = merged;
        }
      }
      expect(ring.length).assertEqual(20);
      // Oldest entries dropped: only the last 20 timestamps remain.
      expect(ring[0].timeMs >= baseTime + 11000).assertTrue();
      expect(ring[19].timeMs).assertEqual(baseTime + 30000);
    });

    it('mergeDiagnosticRecord upgrades a coarse record instead of listing it twice', 0, (): void => {
      const faultTime = 1719740000000;
      const pid = 4242;
      // What the subscription channel actually delivered on device: the
      // OS/APP_CRASH aggregate with no crashtype to resolve JS vs native.
      const aggregateParams: Record<string, Object> = {};
      aggregateParams['time'] = faultTime;
      aggregateParams['pid'] = pid;
      aggregateParams['reason'] = 'aggregate crash event';
      const coarse = extractDiagnostic('OS', 'APP_CRASH', aggregateParams).record;
      expect(coarse.kind).assertEqual(DiagKind.APP_CRASH);
      let ring = mergeDiagnosticRecord([], coarse) ?? [];
      expect(ring.length).assertEqual(1);

      // The history pull resolves the same fault to JS_CRASH. Identity differs
      // (it embeds the kind), so without the timeMs+pid rule the one crash
      // would occupy two ring slots and two detail files.
      const sharp = faultLogToDiagnostic(DiagKind.JS_CRASH, faultTime, pid, 200,
        'TypeError: boom', 'entry', 'Reason:TypeError').record;
      const upgraded = mergeDiagnosticRecord(ring, sharp);
      expect(upgraded !== null).assertTrue();
      ring = upgraded as DiagnosticRecord[];
      expect(ring.length).assertEqual(1);
      expect(ring[0].kind).assertEqual(DiagKind.JS_CRASH);

      // Reverse order (pull first, subscription second): the coarse view is
      // dropped rather than downgrading the record.
      expect(mergeDiagnosticRecord(ring, coarse)).assertNull();
      const other = new DiagnosticRecord(DiagKind.OTHER, 'APP_CRASH', 'OS', faultTime, pid, 200, 'x', '');
      expect(mergeDiagnosticRecord(ring, other)).assertNull();

      // Same millisecond but another process: genuinely two faults.
      const foreign = faultLogToDiagnostic(DiagKind.JS_CRASH, faultTime, pid + 1, 200,
        'TypeError: boom', 'entry', 'Reason:TypeError').record;
      const grown = mergeDiagnosticRecord(ring, foreign);
      expect(grown !== null).assertTrue();
      expect((grown as DiagnosticRecord[]).length).assertEqual(2);
    });

    it('record toJson/fromJson round trip and rejects corrupt lines', 0, (): void => {
      const record = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(2000, 7)).record;
      const restored = DiagnosticRecord.fromJson(record.toJson());
      expect(restored !== null).assertTrue();
      expect((restored as DiagnosticRecord).id).assertEqual(record.id);
      expect((restored as DiagnosticRecord).summary).assertEqual(record.summary);

      expect(DiagnosticRecord.fromJson({})).assertNull();
      const bad: Record<string, Object> = {};
      bad['kind'] = 'X';
      bad['timeMs'] = 'not-a-number';
      expect(DiagnosticRecord.fromJson(bad)).assertNull();
    });

    it('formatDiagnosticReport includes records, details, logs and caps size', 0, (): void => {
      const record = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(3000, 9)).record;
      const details = new Map<string, string>();
      details.set(record.id, 'reason: boom');
      const report = formatDiagnosticReport([record], details, ['12:00:00 I hello'], 4000);
      expect(report.includes('NeriPlayer 诊断报告')).assertTrue();
      expect(report.includes('[JS_CRASH]')).assertTrue();
      expect(report.includes('reason: boom')).assertTrue();
      expect(report.includes('12:00:00 I hello')).assertTrue();

      const huge = new Map<string, string>();
      huge.set(record.id, 'x'.repeat(200 * 1024));
      const capped = formatDiagnosticReport([record], huge, [], 5000);
      expect(capped.length <= EXPORT_CAP + 512).assertTrue();
      expect(capped.includes('截断')).assertTrue();
    });

    it('diagnosticFileName follows CrashLogFiles shape', 0, (): void => {
      const name = diagnosticFileName('JS_CRASH', 1719733292909, 4321);
      expect(name.startsWith('diag_JS_CRASH_')).assertTrue();
      expect(name.includes('_p4321.txt')).assertTrue();
      expect(name.match(/\d{8}_\d{6}/) !== null).assertTrue();
    });

    it('trimToCap keeps short text and annotates long text', 0, (): void => {
      expect(trimToCap('short', 10)).assertEqual('short');
      const long = trimToCap('a'.repeat(50), 10);
      expect(long.length < 50).assertTrue();
      expect(long.includes('截断')).assertTrue();
    });

    it('faultArmsSafeModeSince only arms inside the previous-launch window', 0, (): void => {
      const prevLaunch = 1719730000000;
      // The crash that killed the session started at prevLaunch.
      expect(faultArmsSafeModeSince(DiagKind.JS_CRASH, prevLaunch + 5000, prevLaunch)).assertTrue();
      expect(faultArmsSafeModeSince(DiagKind.CPP_CRASH, prevLaunch, prevLaunch)).assertTrue();
      expect(faultArmsSafeModeSince(DiagKind.APP_FREEZE, prevLaunch + 1, prevLaunch)).assertTrue();

      // The device-observed regression: history rows from days earlier must
      // not force SafeMode even though the kind is fatal.
      expect(faultArmsSafeModeSince(DiagKind.JS_CRASH, prevLaunch - 1, prevLaunch)).assertFalse();
      expect(faultArmsSafeModeSince(DiagKind.CPP_CRASH, prevLaunch - 86400000 * 14, prevLaunch)).assertFalse();

      // Non-fatal kinds never arm, inside the window or not.
      expect(faultArmsSafeModeSince(DiagKind.MAIN_THREAD_JANK, prevLaunch + 5000, prevLaunch)).assertFalse();
      expect(faultArmsSafeModeSince(DiagKind.OTHER, prevLaunch + 5000, prevLaunch)).assertFalse();

      // No mark yet (first launch of a diagnostics-aware build over an older
      // install): pre-existing history is informational only.
      expect(faultArmsSafeModeSince(DiagKind.JS_CRASH, prevLaunch + 5000, 0)).assertFalse();
      // Unusable fault timestamp: nothing to compare, so never arm.
      expect(faultArmsSafeModeSince(DiagKind.JS_CRASH, 0, prevLaunch)).assertFalse();
    });

    it('isoTime is reusable and formatRecordLine builds the shared listing row', 0, (): void => {
      // isoTime reuses one Date instance; consecutive calls must not leak
      // state from the previous timestamp.
      expect(isoTime(0)).assertEqual('1970-01-01T00:00:00.000Z');
      expect(isoTime(1719733292909)).assertEqual('2024-06-30T07:41:32.909Z');
      expect(isoTime(0)).assertEqual('1970-01-01T00:00:00.000Z');

      const record = extractDiagnostic('OS', 'JSCRASH', jsCrashParams(1719733292909, 4321)).record;
      const line = formatRecordLine(record);
      expect(line.startsWith('[JS_CRASH] 2024-06-30T07:41:32.909Z pid=4321 ')).assertTrue();
      expect(line.includes('Cannot read property')).assertTrue();
    });
  });
}
