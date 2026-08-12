import { connection } from '@kit.NetworkKit';
import { Logger } from '../app/Logger';

/**
 * Online/offline detection, mirroring NetworkStatusMonitor.
 */
export class NetworkStatus {
  static async hasNetwork(): Promise<boolean> {
    try {
      return await connection.hasDefaultNet();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NetworkStatus.hasNetwork failed: ${e.message}`);
      return false;
    }
  }
}
