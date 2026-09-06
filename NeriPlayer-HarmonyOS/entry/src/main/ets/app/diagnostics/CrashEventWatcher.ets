import { common } from '@kit.AbilityKit';
import { FaultLogger, hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { Logger } from '../Logger';
import { SettingsRepository } from '../../data/SettingsRepository';
import { DiagnosticsStore } from './DiagnosticsStore';
import { DiagKind, DiagnosticExtraction, faultArmsSafeModeSince, faultLogToDiagnostic, kindArmsSafeMode } from './DiagnosticsModels';

/**
 * The HiAppEvent + faultLogger seam of the M9.2 crash diagnostics loop —
 * the HarmonyOS counterpart of Android ExceptionHandler + AnrWatchdog
 * wiring. Two complementary channels, both needed:
 *
 * - startup history pull: querySelfFaultLog (deprecated since API 18, still
 *   the only way to read faults the event store no longer replays) walks the
 *   system's retained fault history and resolves each one to its exact kind,
 *   mirroring Android AnrWatchdog.capturePreviousAnrIfNeeded;
 * - live subscription: addWatcher with an OS/FAULT filter observes runtime
 *   app freezes, and also receives the crash that killed the *previous*
 *   process when it was recent enough (device-observed 2026-08-24: a crash
 *   16 s before launch arrived as the OS/APP_CRASH aggregate, while an
 *   earlier run whose newest fault was hours old received nothing but
 *   statistic noise). That delivery carries no crashtype, hence the
 *   APP_CRASH kind that the pull channel later upgrades in place.
 *
 * Fatal kinds (JS/C++/aggregate crash, app freeze) arm the SafeMode flag
 * (np.last_crash_detected) — the pending_startup_crash.flag equivalent.
 * Because the pull channel returns the system's whole retained history, that
 * flag is armed only inside the window since the previous launch
 * (faultArmsSafeModeSince + KEY_LAST_STARTUP_MS); everything older is
 * recorded for the export but never forces SafeMode.
 */
export class CrashEventWatcher {
  private static readonly WATCHER_NAME: string = 'neriCrashWatcher1';
  private static subscribed: boolean = false;
  private static watcher: hiAppEvent.Watcher | null = null;
  private static queryStarted: boolean = false;
  /** Wall clock of the previous launch; 0 until the mark has been loaded. */
  private static prevStartupMs: number = 0;
  private static markReady: Promise<void> | null = null;

  static init(context: common.Context): void {
    DiagnosticsStore.init(context);
    CrashEventWatcher.queryHistory().catch((error: Object): void => {
      Logger.warn(`CrashEventWatcher: history pull failed: ${(error as Error).message}`);
    });
    if (CrashEventWatcher.subscribed) {
      return;
    }
    const watcher: hiAppEvent.Watcher = {
      name: CrashEventWatcher.WATCHER_NAME,
      // OS + FAULT filter: without it the watcher is flooded by
      // api_diagnostic statistic noise (device-observed), while fault
      // events such as APP_FREEZE arrive from the OS domain.
      appEventFilters: [
        { domain: hiAppEvent.domain.OS, eventTypes: [hiAppEvent.EventType.FAULT] }
      ],
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): void => {
        for (const group of appEventGroups) {
          for (const info of group.appEventInfos) {
            CrashEventWatcher.processAppEvent(domain, info.name, info.params as Record<string, Object>);
          }
        }
      }
    };
    try {
      hiAppEvent.addWatcher(watcher);
      CrashEventWatcher.watcher = watcher;
      CrashEventWatcher.subscribed = true;
      Logger.info('CrashEventWatcher: fault subscription active');
    } catch (error) {
      // Never block startup on the diagnostics layer.
      Logger.warn(`CrashEventWatcher: subscribe failed: ${(error as Error).message}`);
    }
  }

  static isSubscribed(): boolean {
    return CrashEventWatcher.subscribed;
  }

  /** Previous-launch mark used as the arming window, for diagnostics UI/tests. */
  static previousStartupMs(): number {
    return CrashEventWatcher.prevStartupMs;
  }

  /**
   * Loads the startup high-water mark once per process and replaces it with
   * this launch's timestamp. SettingsRepository.initialize() is awaited first
   * because onCreate kicks that load off without awaiting it: a synchronous
   * read here would see the seeded default instead of the persisted value, and
   * a SafeMode arm written before the load lands would be overwritten by it.
   */
  private static ensureStartupMark(): Promise<void> {
    if (CrashEventWatcher.markReady === null) {
      CrashEventWatcher.markReady = CrashEventWatcher.loadStartupMark();
    }
    return CrashEventWatcher.markReady;
  }

  private static async loadStartupMark(): Promise<void> {
    await SettingsRepository.initialize();
    CrashEventWatcher.prevStartupMs = SettingsRepository.getNumber(SettingsRepository.KEY_LAST_STARTUP_MS, 0);
    SettingsRepository.setNumber(SettingsRepository.KEY_LAST_STARTUP_MS, Date.now());
  }

  /**
   * Pulls the recent fault history (JS crash / C++ crash / app freeze) and
   * persists anything not already recorded. Runs at most once per process;
   * failures degrade silently.
   */
  static async queryHistory(): Promise<void> {
    if (CrashEventWatcher.queryStarted) {
      return;
    }
    CrashEventWatcher.queryStarted = true;
    await CrashEventWatcher.ensureStartupMark();
    const queries: [FaultLogger.FaultType, string][] = [
      [FaultLogger.FaultType.JS_CRASH, DiagKind.JS_CRASH],
      [FaultLogger.FaultType.CPP_CRASH, DiagKind.CPP_CRASH],
      [FaultLogger.FaultType.APP_FREEZE, DiagKind.APP_FREEZE]
    ];
    for (const pair of queries) {
      try {
        const logs = await FaultLogger.querySelfFaultLog(pair[0]);
        for (const info of logs) {
          const extraction = faultLogToDiagnostic(pair[1], info.timestamp, info.pid, info.uid,
            info.reason, info.module, info.fullLog);
          await CrashEventWatcher.persistExtraction(extraction);
        }
      } catch (error) {
        Logger.warn(`CrashEventWatcher: query ${pair[1]} failed: ${(error as Error).message}`);
      }
    }
  }

  /**
   * Handles one live fault event (subscription channel). Public so device
   * tests can drive it directly.
   */
  static processAppEvent(domain: string, eventName: string, params: Record<string, Object>): void {
    CrashEventWatcher.handleAppEvent(domain, eventName, params).catch((error: Object): void => {
      Logger.warn(`CrashEventWatcher: handle fault failed: ${(error as Error).message}`);
    });
  }

  private static async handleAppEvent(domain: string, eventName: string,
    params: Record<string, Object>): Promise<void> {
    await CrashEventWatcher.ensureStartupMark();
    const record = await DiagnosticsStore.appendFromEvent(domain, eventName, params);
    if (record === null) {
      return;
    }
    Logger.info(`CrashEventWatcher: recorded fault ${record.kind} at ${record.timeMs}`);
    // This channel delivers faults of the running process in real time, so a
    // fatal kind always arms. The window is still applied when a mark exists,
    // as a guard against a future platform that starts replaying history to
    // fresh watchers: any fault of the live session is newer than the previous
    // launch, so a genuine event can never be filtered out here.
    const arms = CrashEventWatcher.prevStartupMs > 0
      ? faultArmsSafeModeSince(record.kind, record.timeMs, CrashEventWatcher.prevStartupMs)
      : kindArmsSafeMode(record.kind);
    if (arms) {
      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, true);
    }
  }

  private static async persistExtraction(extraction: DiagnosticExtraction): Promise<void> {
    const stored = await DiagnosticsStore.appendRecord(extraction.record, extraction.detail);
    if (!stored) {
      return;
    }
    const record = extraction.record;
    Logger.info(`CrashEventWatcher: recorded fault ${record.kind} at ${record.timeMs}`);
    // History rows reach back days; only one from the session that died may
    // force SafeMode. Older faults stay in the ring for the export only.
    if (faultArmsSafeModeSince(record.kind, record.timeMs, CrashEventWatcher.prevStartupMs)) {
      Logger.info(`CrashEventWatcher: fault ${record.id} is within the last session, arming SafeMode`);
      SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, true);
    }
  }

  static release(): void {
    if (!CrashEventWatcher.subscribed || CrashEventWatcher.watcher === null) {
      return;
    }
    try {
      hiAppEvent.removeWatcher(CrashEventWatcher.watcher);
    } catch (error) {
      Logger.warn(`CrashEventWatcher: unsubscribe failed: ${(error as Error).message}`);
    }
    CrashEventWatcher.watcher = null;
    CrashEventWatcher.subscribed = false;
  }
}
