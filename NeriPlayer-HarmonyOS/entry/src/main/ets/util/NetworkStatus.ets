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

  /**
   * Whether the default network's bearers include Wi-Fi. Unknown/offline
   * returns true so callers (audio quality selection) fall back to the
   * Wi-Fi tier instead of blocking stream resolution.
   */
  static async isWifi(): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      const caps = await connection.getNetCapabilities(netHandle);
      if (caps === undefined || caps.bearerTypes === undefined) {
        return true;
      }
      return caps.bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`NetworkStatus.isWifi failed: ${e.message}`);
      return true;
    }
  }
}
