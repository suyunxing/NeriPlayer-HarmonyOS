import { describe, it, expect } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import {
  ASSET_CHUNK_MAX_BYTES,
  ASSET_CHUNK_MAX_COUNT,
  ASSET_MANIFEST_PREFIX,
  ASSET_SECRET_MAX_BYTES,
  AssetChunking
} from '../../../main/ets/data/auth/AssetChunking';

/**
 * Regression tests for the real-device NetEase QR login failure
 * (AssetError 401): ASSET_TAG_SECRET accepts at most 1024 bytes, and the
 * full modern cookie bundle (MUSIC_U + MUSIC_A_T / MUSIC_R_T token family)
 * exceeds it, so CredentialStore now transparently chunks oversize values.
 */
export default function assetChunkingTest(): void {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  describe('AssetChunking', () => {
    it('chunkAliasAppendsIndex', 0, () => {
      expect(AssetChunking.chunkAlias('netease_auth_bundle', 1)).assertEqual('netease_auth_bundle#1');
      expect(AssetChunking.chunkAlias('a', 12)).assertEqual('a#12');
    });

    it('manifestRoundtripAndValidation', 0, () => {
      const text = AssetChunking.buildManifest(3, 2500);
      expect(text.startsWith(ASSET_MANIFEST_PREFIX)).assertTrue();
      const parsed = AssetChunking.parseManifest(text);
      expect(parsed !== null).assertTrue();
      expect(parsed!.count).assertEqual(3);
      expect(parsed!.totalBytes).assertEqual(2500);
      // Legacy JSON values are never manifests.
      expect(AssetChunking.parseManifest('{"cookies":{"MUSIC_U":"x"},"savedAt":1}')).assertNull();
      expect(AssetChunking.parseManifest('')).assertNull();
      expect(AssetChunking.parseManifest('#CHUNKED#not json')).assertNull();
      expect(AssetChunking.parseManifest('#CHUNKED#{"count":0,"bytes":10}')).assertNull();
      expect(AssetChunking.parseManifest(`#CHUNKED#{"count":${ASSET_CHUNK_MAX_COUNT + 1},"bytes":10}`)).assertNull();
    });

    it('fitsSingleRecordBoundary', 0, () => {
      expect(AssetChunking.fitsSingleRecord(0)).assertFalse();
      expect(AssetChunking.fitsSingleRecord(1)).assertTrue();
      expect(AssetChunking.fitsSingleRecord(ASSET_SECRET_MAX_BYTES)).assertTrue();
      expect(AssetChunking.fitsSingleRecord(ASSET_SECRET_MAX_BYTES + 1)).assertFalse();
    });

    it('splitBytesSplitsOnBoundariesAndMergesBack', 0, () => {
      // ~2600 bytes of ASCII, like an oversize login bundle.
      const payload = 'x'.repeat(2600);
      const bytes = encoder.encodeInto(payload);
      const chunks = AssetChunking.splitBytes(bytes, ASSET_CHUNK_MAX_BYTES);
      expect(chunks.length).assertEqual(3);
      for (const chunk of chunks) {
        expect(chunk.length <= ASSET_CHUNK_MAX_BYTES).assertTrue();
      }
      const total = new Uint8Array(bytes.length);
      let offset = 0;
      for (const chunk of chunks) {
        total.set(chunk, offset);
        offset += chunk.length;
      }
      expect(offset).assertEqual(bytes.length);
      expect(decoder.decodeToString(total)).assertEqual(payload);
    });

    it('splitBytesKeepsMultiByteCharsAcrossChunks', 0, () => {
      // Chinese characters are 3 UTF-8 bytes each; chunking must split on
      // byte boundaries and reassemble before decoding, never mid-decode.
      const payload = '登录凭据测试'.repeat(200);
      const bytes = encoder.encodeInto(payload);
      const chunks = AssetChunking.splitBytes(bytes, 7);
      const total = new Uint8Array(bytes.length);
      let offset = 0;
      for (const chunk of chunks) {
        total.set(chunk, offset);
        offset += chunk.length;
      }
      expect(decoder.decodeToString(total)).assertEqual(payload);
    });

    it('splitBytesHandlesEmptyAndSmall', 0, () => {
      expect(AssetChunking.splitBytes(new Uint8Array(0), ASSET_CHUNK_MAX_BYTES).length).assertEqual(0);
      const small = encoder.encodeInto('abc');
      const chunks = AssetChunking.splitBytes(small, ASSET_CHUNK_MAX_BYTES);
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].length).assertEqual(3);
    });
  });
}
