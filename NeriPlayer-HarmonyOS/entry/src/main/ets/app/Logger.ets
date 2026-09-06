import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Thin wrapper over HiLog, mirroring NPLogger in the Android codebase.
 * Since M9.2 it also keeps an in-memory ring of recent lines that the
 * diagnostics export attaches (hilog itself is lost when the process dies;
 * crash stacks come from HiAppEvent, the ring covers the freeze/debug case).
 */
export class Logger {
  static readonly DOMAIN: number = 0x4E50; // "NP"
  static readonly TAG: string = 'NeriPlayer';
  private static readonly RING_CAP: number = 400;
  private static ring: string[] = [];

  static debug(message: string): void {
    Logger.push('D', message);
    hilog.debug(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static info(message: string): void {
    Logger.push('I', message);
    hilog.info(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    Logger.push('W', message);
    hilog.warn(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static error(message: string): void {
    Logger.push('E', message);
    hilog.error(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  /** Snapshot of the recent in-memory lines (diagnostics export only). */
  static recentLogLines(): string[] {
    return Logger.ring.slice();
  }

  private static push(level: string, message: string): void {
    const d = new Date();
    const pad = (n: number): string => (n < 10 ? '0' + n : `${n}`);
    Logger.ring.push(`${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())} ${level} ${message}`);
    if (Logger.ring.length > Logger.RING_CAP) {
      Logger.ring.splice(0, Logger.ring.length - Logger.RING_CAP);
    }
  }
}
