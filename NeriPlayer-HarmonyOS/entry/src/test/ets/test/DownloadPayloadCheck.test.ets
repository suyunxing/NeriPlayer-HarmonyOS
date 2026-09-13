import { describe, it, expect } from '@ohos/hypium';
import { isPlausibleAudioHead, findLongIdenticalRun, fillerRunCoverage } from '../../../main/ets/download/DownloadStorage';

function bytesOf(...values: number[]): Uint8Array {
  return new Uint8Array(values);
}

function repeatedRun(byte: number, runLen: number, tail: number): Uint8Array {
  const bytes = new Uint8Array(runLen + tail);
  bytes.fill(byte, 0, runLen);
  for (let i = runLen; i < bytes.length; i++) {
    bytes[i] = (i * 37 + 11) & 0xFF;
  }
  return bytes;
}

export default function downloadPayloadCheckTest(): void {
  describe('DownloadPayloadCheck', () => {
    it('rejectsNulHoledStagingWriterOutput', 0, () => {
      // The broken appendChunk wrote every chunk at one absolute offset:
      // committed files led with a run of NULs and AVPlayer answered 5400106.
      expect(isPlausibleAudioHead(bytesOf(0, 0, 0, 0, 0, 0, 0, 0))).assertFalse();
      expect(isPlausibleAudioHead(bytesOf(0, 0, 0, 0, 0x49, 0x44, 0x33, 0x04))).assertFalse();
    });

    it('rejectsErrorPagePayloads', 0, () => {
      // Expiring CDN links answer 200 with HTML/JSON instead of audio.
      expect(isPlausibleAudioHead(bytesOf(0x3C, 0x68, 0x74, 0x6D, 0x6C))).assertFalse(); // <html
      expect(isPlausibleAudioHead(bytesOf(0x7B, 0x22, 0x63, 0x6F, 0x64, 0x65))).assertFalse(); // {"code
      expect(isPlausibleAudioHead(bytesOf(0x5B, 0x5D))).assertFalse(); // [
    });

    it('acceptsKnownAudioContainerHeads', 0, () => {
      expect(isPlausibleAudioHead(bytesOf(0x49, 0x44, 0x33, 0x04))).assertTrue(); // ID3
      expect(isPlausibleAudioHead(bytesOf(0xFF, 0xFB, 0x90, 0x00))).assertTrue(); // mp3 frame sync
      expect(isPlausibleAudioHead(bytesOf(0x66, 0x4C, 0x61, 0x43))).assertTrue(); // fLaC
      expect(isPlausibleAudioHead(bytesOf(0x4F, 0x67, 0x67, 0x53))).assertTrue(); // OggS
      expect(isPlausibleAudioHead(bytesOf(0x52, 0x49, 0x46, 0x46))).assertTrue(); // RIFF
      expect(isPlausibleAudioHead(bytesOf(0x47, 0x40, 0x00, 0x11))).assertTrue(); // MPEG-TS sync
      // m4a: ftyp box size may lead with up to three NULs — below threshold.
      expect(isPlausibleAudioHead(bytesOf(0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70))).assertTrue();
    });

    it('rejectsTruncatedHeads', 0, () => {
      expect(isPlausibleAudioHead(new Uint8Array(3))).assertFalse();
      expect(isPlausibleAudioHead(new Uint8Array(0))).assertFalse();
    });

    it('findsFirstLongIdenticalRun', 0, () => {
      const bytes = new Uint8Array(300);
      for (let i = 0; i < bytes.length; i++) {
        bytes[i] = (i * 13 + 7) & 0xFF;
      }
      // Scattered data: no qualifying run.
      expect(findLongIdenticalRun(bytes, 64)).assertEqual(-1);
      // A 267-byte filler run is reported at its start offset.
      bytes.fill(0x5A, 120, 120 + 267);
      expect(findLongIdenticalRun(bytes, 64)).assertEqual(120);
    });

    it('fillerCoverageFlagsPoisonedPayloads', 0, () => {
      // Poisoned weapi AAC payload: ~1.2% covered by periodic non-pad runs.
      const poisoned = new Uint8Array(64 * 1024);
      for (let i = 0; i < poisoned.length; i++) {
        poisoned[i] = (i * 31 + 5) & 0xFF;
      }
      for (let start = 0; start + 267 < poisoned.length; start += 271) {
        poisoned.fill(0x69, start, start + 267);
      }
      expect(fillerRunCoverage(poisoned)).assertLarger(0.005);
      // Clean transfer: only benign ID3/0xAA padding — below threshold.
      const clean = new Uint8Array(64 * 1024);
      for (let i = 0; i < clean.length; i++) {
        clean[i] = (i * 17 + 3) & 0xFF;
      }
      clean.fill(0x00, 0, 768);
      clean.fill(0xAA, clean.length - 600, clean.length - 100);
      expect(fillerRunCoverage(clean)).assertLessOrEqual(0.005);
      // A non-pad filler run is counted even when short overall.
      expect(fillerRunCoverage(repeatedRun(0x2D, 100, 200))).assertLarger(0.3);
      // Benign pads alone never count.
      expect(fillerRunCoverage(repeatedRun(0x00, 500, 100))).assertEqual(0);
      expect(fillerRunCoverage(new Uint8Array(0))).assertEqual(0);
    });
  });
}
