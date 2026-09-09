/**
 * Pure byte-level chunking for CredentialStore on @ohos.security.asset:
 * ASSET_TAG_SECRET accepts 1-1024 bytes per record (official Asset Store Kit
 * constraint), while a full modern login bundle (NetEase MUSIC_U plus the
 * MUSIC_A_T / MUSIC_R_T token family) serializes well past that. Values are
 * UTF-8 encoded, split on byte boundaries, and stored as one manifest record
 * at the base alias plus N chunk records; reads reassemble in order before
 * decoding, so multi-byte characters split across chunks stay intact.
 *
 * The manifest is a plain-text prefix + JSON so legacy single-record values
 * (which are JSON and never start with '#') are unambiguous on read.
 */

export const ASSET_SECRET_MAX_BYTES: number = 1024;
/** Manifest + safety margin below the 1024-byte SECRET cap. */
export const ASSET_CHUNK_MAX_BYTES: number = 1000;
export const ASSET_CHUNK_MAX_COUNT: number = 64;
/** Legacy single-record values are JSON; this prefix can never collide. */
export const ASSET_MANIFEST_PREFIX: string = '#CHUNKED#';

export class AssetChunkManifest {
  count: number = 0;
  totalBytes: number = 0;
}

export class AssetChunking {
  static chunkAlias(alias: string, index: number): string {
    return `${alias}#${index}`;
  }

  static buildManifest(count: number, totalBytes: number): string {
    const manifest: Record<string, Object> = {};
    manifest['count'] = count;
    manifest['bytes'] = totalBytes;
    return `${ASSET_MANIFEST_PREFIX}${JSON.stringify(manifest)}`;
  }

  static parseManifest(text: string): AssetChunkManifest | null {
    if (!text.startsWith(ASSET_MANIFEST_PREFIX)) {
      return null;
    }
    try {
      const root = JSON.parse(text.substring(ASSET_MANIFEST_PREFIX.length)) as Record<string, Object>;
      const count = root['count'];
      const bytes = root['bytes'];
      if (count === undefined || count === null || bytes === undefined || bytes === null) {
        return null;
      }
      const parsedCount = Number(count);
      const parsedBytes = Number(bytes);
      if (!Number.isInteger(parsedCount) || parsedCount < 1 || parsedCount > ASSET_CHUNK_MAX_COUNT
        || !Number.isInteger(parsedBytes) || parsedBytes < 1) {
        return null;
      }
      const out = new AssetChunkManifest();
      out.count = parsedCount;
      out.totalBytes = parsedBytes;
      return out;
    } catch (error) {
      return null;
    }
  }

  /** True when the value fits a single asset record (no chunking needed). */
  static fitsSingleRecord(byteLength: number): boolean {
    return byteLength > 0 && byteLength <= ASSET_SECRET_MAX_BYTES;
  }

  static splitBytes(data: Uint8Array, maxChunkBytes: number): Uint8Array[] {
    if (data.length === 0) {
      return [];
    }
    const chunkSize = Math.max(1, maxChunkBytes);
    const chunks: Uint8Array[] = [];
    for (let offset = 0; offset < data.length; offset += chunkSize) {
      const end = Math.min(offset + chunkSize, data.length);
      chunks.push(data.slice(offset, end));
    }
    return chunks;
  }
}
