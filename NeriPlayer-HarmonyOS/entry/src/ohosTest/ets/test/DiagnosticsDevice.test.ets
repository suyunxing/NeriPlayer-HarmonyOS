import { describe, it, expect } from '@ohos/hypium';
import { usbManager } from '@kit.BasicServicesKit';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { SettingsRepository } from '../../../main/ets/data/SettingsRepository';
import { DiagnosticsStore } from '../../../main/ets/app/diagnostics/DiagnosticsStore';
import { CrashEventWatcher } from '../../../main/ets/app/diagnostics/CrashEventWatcher';
import { DiagKind, DiagnosticRecord } from '../../../main/ets/app/diagnostics/DiagnosticsModels';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve): void => {
    setTimeout(resolve, ms);
  });
}

function jscrashParams(timeMs: number, pid: number): Record<string, Object> {
  const params: Record<string, Object> = {};
  params['time'] = timeMs;
  params['pid'] = pid;
  params['crashtype'] = 'TypeError';
  params['reason'] = 'ActsDiagnostics probe fault';
  params['crashstack'] = 'Error: probe\n    at Acts (DiagnosticsDevice.test.ets:1)';
  return params;
}

/**
 * The shape the subscription channel actually delivers for a crash that just
 * killed the previous process: the OS/APP_CRASH aggregate with no crashtype.
 */
function aggregateCrashParams(timeMs: number, pid: number): Record<string, Object> {
  const params: Record<string, Object> = {};
  params['time'] = timeMs;
  params['pid'] = pid;
  params['reason'] = 'ActsDiagnostics aggregate fault';
  return params;
}

/**
 * M9.2 device coverage:
 * 1. the diagnostics store round trip (index + detail file + clear);
 * 2. the watcher event pipeline arms the SafeMode flag for fatal kinds, and
 *    only inside the window since the previous launch;
 * 3. the OS/APP_CRASH aggregate arms on its own and collapses into the
 *    sharper kind the history pull resolves later;
 * 4. concurrent appends from both channels keep exactly one record, with the
 *    sharper kind and its detail file intact;
 * 5. (M9.1) the usbManager API surface is reachable on this device class.
 *
 * The end-to-end "real JSCRASH -> next launch SafeMode" path needs the main
 * process to die, which cannot be asserted from inside aa test; it is
 * verified manually via the DebugPage crash trigger.
 */
export default function diagnosticsDeviceTest(): void {
  describe('ActsDiagnosticsDeviceTest', () => {
    const probeTime = Date.now() - 60000;

    it('storeRoundTripPersistsAndClears', 0, async () => {
      await DiagnosticsStore.clearAll();
      const first = await DiagnosticsStore.appendFromEvent('OS', 'JSCRASH', jscrashParams(probeTime, 111));
      expect(first !== null).assertTrue();
      const duplicate = await DiagnosticsStore.appendFromEvent('OS', 'JSCRASH', jscrashParams(probeTime, 111));
      expect(duplicate).assertNull();

      const records = await DiagnosticsStore.listRecords();
      expect(records.length).assertEqual(1);
      const record = records[0];
      expect(record.kind).assertEqual(DiagKind.JS_CRASH);
      expect(record.fileName.length > 0).assertTrue();

      const detail = await DiagnosticsStore.readDetail(record.id);
      expect(detail.includes('ActsDiagnostics probe fault')).assertTrue();
      expect(detail.includes('DiagnosticsDevice.test.ets:1')).assertTrue();

      const report = await DiagnosticsStore.buildExportReport(['probe log line'], Date.now());
      expect(report.includes('NeriPlayer 诊断报告')).assertTrue();
      expect(report.includes('probe log line')).assertTrue();
      expect(report.includes('ActsDiagnostics probe fault')).assertTrue();

      await DiagnosticsStore.clearAll();
      const after = await DiagnosticsStore.listRecords();
      expect(after.length).assertEqual(0);
    });

    it('processAppEventArmsSafeModeFlagForFatalKind', 0, async () => {
      await DiagnosticsStore.clearAll();
      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
      // Seed the arming window before the watcher loads it (the load is
      // memoized on first use, and this suite is its only user in the test
      // process). Preferences are application-level, so this also replaces the
      // real app's mark — dev-only side effect of running the device suite.
      const windowStart = probeTime - 10000;
      SettingsRepository.setNumber(SettingsRepository.KEY_LAST_STARTUP_MS, windowStart);

      CrashEventWatcher.processAppEvent('OS', 'JSCRASH', jscrashParams(probeTime + 1000, 222));
      // processAppEvent persists asynchronously; give the pipeline a beat.
      await sleep(800);
      expect(CrashEventWatcher.previousStartupMs()).assertEqual(windowStart);
      const records = await DiagnosticsStore.listRecords();
      expect(records.length).assertEqual(1);
      expect(records[0].pid).assertEqual(222);
      expect(SettingsRepository.getBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false)).assertTrue();

      // MAIN_THREAD_JANK is recorded but does not arm SafeMode.
      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
      CrashEventWatcher.processAppEvent('OS', 'MAIN_THREAD_JANK', jscrashParams(probeTime + 2000, 222));
      await sleep(800);
      expect(SettingsRepository.getBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false)).assertFalse();

      // A fatal fault older than the previous launch is kept for the export
      // but must not force SafeMode (the device-observed M9.2 regression).
      CrashEventWatcher.processAppEvent('OS', 'JSCRASH', jscrashParams(windowStart - 60000, 333));
      await sleep(800);
      const aged = await DiagnosticsStore.listRecords();
      expect(aged.some((item): boolean => item.pid === 333)).assertTrue();
      expect(SettingsRepository.getBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false)).assertFalse();

      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
      await DiagnosticsStore.clearAll();
    });

    it('aggregateCrashArmsSafeModeAndCollapsesIntoResolvedKind', 0, async () => {
      await DiagnosticsStore.clearAll();
      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
      const faultTime = probeTime + 3000;
      const pid = 444;
      // Keep the fault inside the arming window whatever the previous launch
      // mark happens to be, so this case does not depend on case order.
      SettingsRepository.setNumber(SettingsRepository.KEY_LAST_STARTUP_MS, faultTime - 5000);
      expect(CrashEventWatcher.previousStartupMs() < faultTime).assertTrue();
      // The aggregate event alone must arm: on device this is the only shape
      // the subscription delivers for the crash that killed the previous
      // process, and before the APP_CRASH kind existed it landed as OTHER and
      // was silently ignored (device-observed 2026-08-24).
      CrashEventWatcher.processAppEvent('OS', 'APP_CRASH', aggregateCrashParams(faultTime, pid));
      await sleep(800);
      const coarse = await DiagnosticsStore.listRecords();
      expect(coarse.length).assertEqual(1);
      expect(coarse[0].kind).assertEqual(DiagKind.APP_CRASH);
      expect(SettingsRepository.getBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false)).assertTrue();

      // The history pull then resolves the same fault to JS_CRASH. One fault,
      // one ring slot, and the orphaned detail file is swept.
      const resolved = await DiagnosticsStore.appendFromEvent('OS', 'JSCRASH', jscrashParams(faultTime, pid));
      expect(resolved !== null).assertTrue();
      const merged = await DiagnosticsStore.listRecords();
      expect(merged.length).assertEqual(1);
      expect(merged[0].kind).assertEqual(DiagKind.JS_CRASH);
      const detail = await DiagnosticsStore.readDetail(merged[0].id);
      expect(detail.includes('ActsDiagnostics probe fault')).assertTrue();
      // The replaced record's file no longer resolves through the index.
      expect((await DiagnosticsStore.readDetail(`${DiagKind.APP_CRASH}@${faultTime}@${pid}`)).length).assertEqual(0);

      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, false);
      await DiagnosticsStore.clearAll();
    });

    it('concurrentChannelAppendsKeepTheSharperKind', 0, async () => {
      await DiagnosticsStore.clearAll();
      const faultTime = probeTime + 7000;
      const pid = 555;
      // Both channels racing on the same fault, exactly as they do on a real
      // launch: the pull resolves JS_CRASH while the subscription delivers the
      // APP_CRASH aggregate. Unserialized, the second read-modify-write
      // overwrote the first record and the prune then deleted its detail file
      // as an orphan (device-observed 2026-08-24).
      const pending: Promise<DiagnosticRecord | null>[] = [
        DiagnosticsStore.appendFromEvent('OS', 'JSCRASH', jscrashParams(faultTime, pid)),
        DiagnosticsStore.appendFromEvent('OS', 'APP_CRASH', aggregateCrashParams(faultTime, pid))
      ];
      const results = await Promise.all(pending);
      expect(results.some((item): boolean => item !== null)).assertTrue();

      const records = await DiagnosticsStore.listRecords();
      expect(records.length).assertEqual(1);
      expect(records[0].kind).assertEqual(DiagKind.JS_CRASH);
      // The surviving record's detail file must still be readable and hold the
      // sharper channel's text — the exact pair the race used to destroy.
      const detail = await DiagnosticsStore.readDetail(records[0].id);
      expect(detail.includes('ActsDiagnostics probe fault')).assertTrue();

      await DiagnosticsStore.clearAll();
    });

    it('usbManagerApiReachable', 0, async () => {
      // M9.1 probe: the usbManager module is reachable and enumeration does
      // not throw on this device class (emulator: empty list is expected).
      const devices = usbManager.getDevices();
      expect(Array.isArray(devices)).assertTrue();
      expect(devices.length >= 0).assertTrue();
    });
  });
}
