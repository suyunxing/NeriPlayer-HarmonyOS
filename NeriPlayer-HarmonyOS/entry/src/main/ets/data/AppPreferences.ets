import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';

/**
 * Shared key-value persistence wrapper (equivalent of Android SharedPreferences
 * backed repositories).
 */
export class AppPreferences {
  private static instance: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: common.Context): Promise<void> {
    if (AppPreferences.initPromise !== null) {
      return AppPreferences.initPromise;
    }
    AppPreferences.initPromise = AppPreferences.doInit(context);
    return AppPreferences.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    if (AppPreferences.instance !== null) {
      return;
    }
    try {
      // Application-level preferences dir. A UIAbilityContext would resolve
      // to a module-level dir (haps/<module>/preferences), splitting the
      // store between entry and entry_test.
      const appContext = context.getApplicationContext();
      AppPreferences.instance = await preferences.getPreferences(appContext, { name: 'neri_player_data' });
    } catch (error) {
      const e = error as Error;
      Logger.error(`AppPreferences.init failed: ${e.message}`);
    }
  }

  static async getString(key: string, def: string): Promise<string> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return def;
    }
    try {
      const value = await store.get(key, def);
      return value as string;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.getString(${key}) failed: ${e.message}`);
      return def;
    }
  }

  static async getNumber(key: string, def: number): Promise<number> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return def;
    }
    try {
      const value = await store.get(key, def);
      return value as number;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.getNumber(${key}) failed: ${e.message}`);
      return def;
    }
  }

  static async getBoolean(key: string, def: boolean): Promise<boolean> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return def;
    }
    try {
      const value = await store.get(key, def);
      return value as boolean;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.getBoolean(${key}) failed: ${e.message}`);
      return def;
    }
  }

  static async putString(key: string, value: string): Promise<void> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.putString(${key}) failed: ${e.message}`);
    }
  }

  static async putNumber(key: string, value: number): Promise<void> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.putNumber(${key}) failed: ${e.message}`);
    }
  }

  static async putBoolean(key: string, value: boolean): Promise<void> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.putBoolean(${key}) failed: ${e.message}`);
    }
  }

  static async getAll(): Promise<Record<string, preferences.ValueType>> {
    const store = await AppPreferences.readyStore();
    if (store === null) {
      return {};
    }
    try {
      return await store.getAll() as Record<string, preferences.ValueType>;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`AppPreferences.getAll failed: ${e.message}`);
      return {};
    }
  }

  private static async readyStore(): Promise<preferences.Preferences | null> {
    const initPromise = AppPreferences.initPromise;
    if (initPromise !== null) {
      await Promise.resolve(initPromise);
    }
    return AppPreferences.instance;
  }
}
