import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../app/Logger';
import { AssetErrorKind, classifyAssetError, assetErrorName } from './AssetErrors';
import {
  ASSET_CHUNK_MAX_BYTES,
  ASSET_CHUNK_MAX_COUNT,
  AssetChunking,
  AssetChunkManifest
} from './AssetChunking';

/**
 * String-keyed credential storage on top of @ohos.security.asset
 * (the HarmonyOS equivalent of Android EncryptedSharedPreferences/Keystore).
 *
 * Values whose UTF-8 form exceeds the 1024-byte ASSET_TAG_SECRET cap are
 * transparently split into chunk records (alias#1..alias#N) behind a small
 * manifest at the base alias; see AssetChunking. Reads treat any non-manifest
 * value as a legacy single record, so pre-chunking bundles stay readable.
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
    const bytes = CredentialStore.encoder.encodeInto(value);
    const saved = AssetChunking.fitsSingleRecord(bytes.length)
      ? await CredentialStore.putRecord(alias, bytes)
      : await CredentialStore.putChunked(alias, bytes);
    // Read through backendName(): the early MEMORY return above narrows the
    // static field to ASSET for the compiler, and an awaited write may still
    // switch it to MEMORY mid-call (FALLBACK classification).
    if (!saved && CredentialStore.backendName() === CredentialBackend.MEMORY) {
      // A record write classified as FALLBACK switched the backend mid-call;
      // mirror the original degradation contract: session memory keeps the
      // credential and the caller still sees a successful save.
      CredentialStore.memory.set(alias, value);
      return true;
    }
    return saved;
  }

  static async getString(alias: string): Promise<string> {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      return CredentialStore.memory.get(alias) ?? '';
    }
    const head = await CredentialStore.queryRaw(alias);
    if (head === null) {
      return '';
    }
    const manifest = AssetChunking.parseManifest(head);
    if (manifest === null) {
      return head;
    }
    return CredentialStore.readChunks(alias, manifest);
  }

  static async remove(alias: string): Promise<boolean> {
    if (CredentialStore.backend === CredentialBackend.MEMORY) {
      return CredentialStore.memory.delete(alias);
    }
    const head = await CredentialStore.queryRaw(alias);
    if (head === null) {
      return false;
    }
    const manifest = AssetChunking.parseManifest(head);
    if (manifest !== null) {
      for (let i = 1; i <= manifest.count; i++) {
        await CredentialStore.removeSingle(AssetChunking.chunkAlias(alias, i));
      }
    }
    return CredentialStore.removeSingle(alias);
  }

  // -------------------------------------------------------------------------
  // Write paths. putRecord keeps the original retry/fallback classification;
  // FALLBACK switches the backend and reports failure so putString can
  // re-route the value into session memory.
  // -------------------------------------------------------------------------

  private static async putRecord(alias: string, bytes: Uint8Array): Promise<boolean> {
    try {
      await asset.add(CredentialStore.buildRequest(alias, bytes));
      return true;
    } catch (error) {
      const code = CredentialStore.extractCode(error);
      const kind = classifyAssetError(code);
      if (kind === AssetErrorKind.FALLBACK) {
        CredentialStore.switchToMemory(`add failed (${assetErrorName(code)}), credentials now session-only`);
        return false;
      }
      if (kind === AssetErrorKind.RETRY) {
        try {
          await CredentialStore.delay(RETRY_DELAY_MS);
          await asset.add(CredentialStore.buildRequest(alias, bytes));
          return true;
        } catch (retryError) {
          const retryCode = CredentialStore.extractCode(retryError);
          if (classifyAssetError(retryCode) === AssetErrorKind.FALLBACK) {
            CredentialStore.switchToMemory(`add retry failed (${assetErrorName(retryCode)})`);
            return false;
          }
          Logger.error(`${TAG}.putString(${alias}) failed after retry: ${assetErrorName(retryCode)}`);
          return false;
        }
      }
      Logger.error(`${TAG}.putString(${alias}) failed: ${assetErrorName(code)} valueBytes=${bytes.length}`);
      return false;
    }
  }

  // Chunked path: chunks first, manifest last (a torn write leaves either the
  // old state or no manifest, never a manifest pointing at partial data).
  private static async putChunked(alias: string, bytes: Uint8Array): Promise<boolean> {
    const chunks = AssetChunking.splitBytes(bytes, ASSET_CHUNK_MAX_BYTES);
    if (chunks.length === 0 || chunks.length > ASSET_CHUNK_MAX_COUNT) {
      Logger.error(`${TAG}.putString(${alias}) rejected: ${bytes.length}B needs ${chunks.length} chunks (max ${ASSET_CHUNK_MAX_COUNT})`);
      return false;
    }
    const previous = await CredentialStore.queryRaw(alias);
    const previousManifest = previous === null ? null : AssetChunking.parseManifest(previous);
    if (previousManifest !== null) {
      // Drop the old manifest first so a torn overwrite cannot reassemble
      // mixed old/new chunks under the still-valid old count.
      await CredentialStore.removeSingle(alias);
    }
    for (let i = 0; i < chunks.length; i++) {
      const ok = await CredentialStore.putRecord(AssetChunking.chunkAlias(alias, i + 1), chunks[i]);
      if (!ok) {
        Logger.error(`${TAG}.putString(${alias}) chunk ${i + 1}/${chunks.length} write failed, rolling back`);
        for (let j = 1; j <= i + 1; j++) {
          await CredentialStore.removeSingle(AssetChunking.chunkAlias(alias, j));
        }
        return false;
      }
    }
    const manifestBytes = CredentialStore.encoder.encodeInto(AssetChunking.buildManifest(chunks.length, bytes.length));
    const saved = await CredentialStore.putRecord(alias, manifestBytes);
    if (!saved) {
      Logger.error(`${TAG}.putString(${alias}) manifest write failed, rolling back ${chunks.length} chunks`);
      for (let j = 1; j <= chunks.length; j++) {
        await CredentialStore.removeSingle(AssetChunking.chunkAlias(alias, j));
      }
      return false;
    }
    if (previousManifest !== null && previousManifest.count > chunks.length) {
      for (let j = chunks.length + 1; j <= previousManifest.count; j++) {
        await CredentialStore.removeSingle(AssetChunking.chunkAlias(alias, j));
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Shared asset primitives
  // -------------------------------------------------------------------------

  private static buildRequest(alias: string, bytes: Uint8Array): asset.AssetMap {
    const request: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    request.set(asset.Tag.ALIAS, CredentialStore.encoder.encodeInto(alias));
    request.set(asset.Tag.SECRET, bytes);
    request.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
    request.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    return request;
  }

  /** Raw record text at this exact alias; null when absent or unusable. */
  private static async queryRaw(alias: string): Promise<string | null> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, CredentialStore.encoder.encodeInto(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) {
        return null;
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return null;
      }
      return CredentialStore.decoder.decodeToString(secret);
    } catch (error) {
      const code = CredentialStore.extractCode(error);
      const kind = classifyAssetError(code);
      if (kind === AssetErrorKind.NOT_FOUND) {
        return null;
      }
      if (kind === AssetErrorKind.FALLBACK) {
        CredentialStore.switchToMemory(`query failed (${assetErrorName(code)}), saved credentials unavailable this session`);
        return null;
      }
      Logger.error(`${TAG}.getString(${alias}) failed: ${assetErrorName(code)}`);
      return null;
    }
  }

  private static async readChunks(alias: string, manifest: AssetChunkManifest): Promise<string> {
    const assembled = new Uint8Array(manifest.totalBytes);
    let offset = 0;
    for (let i = 1; i <= manifest.count; i++) {
      const chunk = await CredentialStore.queryRaw(AssetChunking.chunkAlias(alias, i));
      if (chunk === null) {
        Logger.error(`${TAG}.getString(${alias}) chunk ${i}/${manifest.count} missing, credential unreadable`);
        return '';
      }
      const chunkBytes = CredentialStore.encoder.encodeInto(chunk);
      if (offset + chunkBytes.length > assembled.length) {
        Logger.error(`${TAG}.getString(${alias}) chunk ${i} overflows manifest total, credential unreadable`);
        return '';
      }
      assembled.set(chunkBytes, offset);
      offset += chunkBytes.length;
    }
    if (offset !== assembled.length) {
      Logger.error(`${TAG}.getString(${alias}) chunks total ${offset}B != manifest ${assembled.length}B, credential unreadable`);
      return '';
    }
    return CredentialStore.decoder.decodeToString(assembled);
  }

  private static async removeSingle(alias: string): Promise<boolean> {
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
        return false;
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
