import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../app/Logger';
import { AssetErrorKind, classifyAssetError, assetErrorName } from './AssetErrors';

/**
 * String-keyed credential storage on top of @ohos.security.asset
 * (the HarmonyOS equivalent of Android EncryptedSharedPreferences/Keystore).
 *
 * Fallback policy (recorded per M4.1): when the asset service is unavailable
 * in the running environment (see AssetErrors.FALLBACK class), the store
 * degrades to session memory - credentials work until process death but do
 * not survive restarts. Plain preferences are deliberately NOT used for
 * secrets (project red line). The active backend is exposed for DebugPage.
 */

export enum CredentialBackend {
  ASSET = 'asset',
  MEMORY = 'memory'
}

const TAG: string = 'CredentialStore';
const RETRY_DELAY_MS: number = 50;

export class CredentialStore {
  private static backend: CredentialBackend = CredentialBackend.ASSET;
  private static memory: Map<string, string> = new Map();
  private static encoder: util.TextEncoder = new util.TextEncoder();
  private static decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  static backendName(): string {
    return CredentialStore.backend;
  }

  static isPersistent(): boolean {
    return CredentialStore.backend === CredentialBackend.ASSET;
  }

  static async putString(alias: string, value: string): Promise<boolean> {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      CredentialStore.memory.set(alias, value);
      return true;
    }
    const request: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    request.set(asset.Tag.ALIAS, CredentialStore.encoder.encodeInto(alias));
    request.set(asset.Tag.SECRET, CredentialStore.encoder.encodeInto(value));
    request.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
    request.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(request);
      return true;
    } catch (error) {
      const code = CredentialStore.extractCode(error);
      const kind = classifyAssetError(code);
      if (kind === AssetErrorKind.FALLBACK) {
        CredentialStore.switchToMemory(`add failed (${assetErrorName(code)}), credentials now session-only`);
        CredentialStore.memory.set(alias, value);
        return true;
      }
      if (kind === AssetErrorKind.RETRY) {
        try {
          await CredentialStore.delay(RETRY_DELAY_MS);
          await asset.add(request);
          return true;
        } catch (retryError) {
          const retryCode = CredentialStore.extractCode(retryError);
          if (classifyAssetError(retryCode) === AssetErrorKind.FALLBACK) {
            CredentialStore.switchToMemory(`add retry failed (${assetErrorName(retryCode)})`);
            CredentialStore.memory.set(alias, value);
            return true;
          }
          Logger.error(`${TAG}.putString(${alias}) failed after retry: ${assetErrorName(retryCode)}`);
          return false;
        }
      }
      Logger.error(`${TAG}.putString(${alias}) failed: ${assetErrorName(code)}`);
      return false;
    }
  }

  static async getString(alias: string): Promise<string> {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      return CredentialStore.memory.get(alias) ?? '';
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, CredentialStore.encoder.encodeInto(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) {
        return '';
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return '';
      }
      return CredentialStore.decoder.decodeToString(secret);
    } catch (error) {
      const code = CredentialStore.extractCode(error);
      const kind = classifyAssetError(code);
      if (kind === AssetErrorKind.NOT_FOUND) {
        return '';
      }
      if (kind === AssetErrorKind.FALLBACK) {
        CredentialStore.switchToMemory(`query failed (${assetErrorName(code)}), saved credentials unavailable this session`);
        return '';
      }
      Logger.error(`${TAG}.getString(${alias}) failed: ${assetErrorName(code)}`);
      return '';
    }
  }

  static async remove(alias: string): Promise<boolean> {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      return CredentialStore.memory.delete(alias);
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, CredentialStore.encoder.encodeInto(alias));
    try {
      await asset.remove(query);
      return true;
    } catch (error) {
      const code = CredentialStore.extractCode(error);
      const kind = classifyAssetError(code);
      if (kind === AssetErrorKind.NOT_FOUND) {
        return false;
      }
      if (kind === AssetErrorKind.FALLBACK) {
        CredentialStore.switchToMemory(`remove failed (${assetErrorName(code)})`);
        return CredentialStore.memory.delete(alias);
      }
      Logger.error(`${TAG}.remove(${alias}) failed: ${assetErrorName(code)}`);
      return false;
    }
  }

  private static switchToMemory(reason: string): void {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      return;
    }
    CredentialStore.backend = CredentialBackend.MEMORY;
    CredentialStore.memory.clear();
    Logger.warn(`${TAG}: asset backend unavailable, degrading to session memory (${reason})`);
  }

  private static extractCode(error: Object): number {
    const businessError = error as Record<string, Object>;
    const code = businessError['code'];
    return code === undefined || code === null ? -1 : Number(code);
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
