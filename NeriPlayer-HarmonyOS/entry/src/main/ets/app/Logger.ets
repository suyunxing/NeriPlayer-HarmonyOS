import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Thin wrapper over HiLog, mirroring NPLogger in the Android codebase.
 */
export class Logger {
  static readonly DOMAIN: number = 0x4E50; // "NP"
  static readonly TAG: string = 'NeriPlayer';

  static debug(message: string): void {
    hilog.debug(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static info(message: string): void {
    hilog.info(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(Logger.DOMAIN, Logger.TAG, '%{public}s', message);
  }
}
