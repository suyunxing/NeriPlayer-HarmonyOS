/**
 * Platform glue for cover color extraction: downloads the cover, decodes a
 * tiny downsampled RGBA bitmap, extracts colors with the official
 * effectKit ColorPicker (fallback: the hand-rolled Palette when effectKit
 * throws), derives the full AccentScheme, and publishes it to AppStorage
 * ('player.coverScheme') alongside the legacy seed ('player.coverSeedHex').
 *
 * Mirrors CoverArtColorCache.preload/getOrLoad (96px decode size) and keeps a
 * generation token so a slow extraction finishing after a track switch never
 * publishes a stale scheme for the new song (PlayerManager publishes songs
 * synchronously, extraction is not).
 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { Logger } from '../../app/Logger';
import { Palette } from './Palette';
import { CoverColorCacheCore } from './CoverColorCacheCore';
import { AccentScheme, CoverCandidate } from './AccentScheme';

// Android decodes at sizePx=96; that already is the low-end downsample
// strategy (9216 pixels), so no extra device-tier branching is needed.
const DECODE_SIZE = 96;
const MAX_COVER_BYTES = 8 * 1024 * 1024;
// Scheme memo: republish synchronously when a known cover re-plays.
const SCHEME_MEMO_CAPACITY = 16;

export class CoverArtColorCache {
  private static readonly core: CoverColorCacheCore = new CoverColorCacheCore(
    (coverUrl: string): Promise<string | null> => CoverArtColorCache.loadCoverSeed(coverUrl)
  );
  private static generation: number = 0;
  private static readonly schemeMemo: Map<string, AccentScheme> = new Map<string, AccentScheme>();

  static peek(coverUrl: string): string | null | undefined {
    return CoverArtColorCache.core.peek(coverUrl);
  }

  static getOrLoad(coverUrl: string): Promise<string | null> {
    return CoverArtColorCache.core.getOrLoad(coverUrl);
  }

  /**
   * PlayerManager hook: resolves (or clears) the seed for the given cover and
   * publishes it to AppStorage. Fire-and-forget; empty URLs clear the seed
   * immediately. A generation bump on every call discards late results.
   */
  static onSongChanged(coverUrl: string): void {
    const generation = ++CoverArtColorCache.generation;
    const publish = (hex: string | null): void => {
      if (generation !== CoverArtColorCache.generation) {
        return;
      }
      AppStorage.setOrCreate('player.coverSeedHex', hex ?? '');
      // Republish the memoized scheme synchronously so replaying a known
      // cover re-tints the UI on the first frame.
      const memo = CoverArtColorCache.schemeMemo.get(coverUrl.trim());
      if (memo !== undefined) {
        CoverArtColorCache.publishScheme(memo, generation);
      }
    };
    if (coverUrl.trim().length === 0) {
      publish(null);
      return;
    }
    const peeked = CoverArtColorCache.peek(coverUrl);
    if (peeked !== undefined) {
      // Cached: publish synchronously so the first frame of a known cover
      // already carries the right accent (Android peek-then-preload flow).
      publish(peeked);
      return;
    }
    CoverArtColorCache.getOrLoad(coverUrl).then(publish).catch(() => publish(null));
  }

  private static publishScheme(scheme: AccentScheme, generation: number): void {
    if (generation !== CoverArtColorCache.generation) {
      return;
    }
    AppStorage.setOrCreate('player.coverScheme', scheme);
  }

  private static stashScheme(coverUrl: string, scheme: AccentScheme): void {
    const key = coverUrl.trim();
    CoverArtColorCache.schemeMemo.delete(key);
    CoverArtColorCache.schemeMemo.set(key, scheme);
    while (CoverArtColorCache.schemeMemo.size > SCHEME_MEMO_CAPACITY) {
      const oldest = CoverArtColorCache.schemeMemo.keys().next();
      if (oldest.done) {
        break;
      }
      CoverArtColorCache.schemeMemo.delete(oldest.value);
    }
  }

  private static async loadCoverSeed(coverUrl: string): Promise<string | null> {
    const buffer = await CoverArtColorCache.download(coverUrl);
    if (buffer === null) {
      return null;
    }
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      source = image.createImageSource(buffer);
      const info = await source.getImageInfo();
      const srcW = info.size.width;
      const srcH = info.size.height;
      if (srcW <= 0 || srcH <= 0) {
        return null;
      }
      // desiredSize stretches when the ratio differs, so compute a
      // proportional target like Android's Coil centerCrop-free sizing.
      const scale = Math.min(DECODE_SIZE / srcW, DECODE_SIZE / srcH);
      const targetW = Math.max(1, Math.min(DECODE_SIZE, Math.round(srcW * scale)));
      const targetH = Math.max(1, Math.min(DECODE_SIZE, Math.round(srcH * scale)));
      pixelMap = await source.createPixelMap({
        desiredSize: { width: targetW, height: targetH },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const pixelInfo = await pixelMap.getImageInfo();
      const stride = pixelInfo.stride > 0 ? pixelInfo.stride : pixelInfo.size.width * 4;
      const raw = new ArrayBuffer(pixelInfo.size.height * stride);
      await pixelMap.readPixelsToBuffer(raw);
      const bytes = new Uint8Array(raw);
      const pixels = new Uint8Array(pixelInfo.size.width * pixelInfo.size.height * 4);
      const rowBytes = pixelInfo.size.width * 4;
      for (let row = 0; row < pixelInfo.size.height; row++) {
        pixels.set(bytes.subarray(row * stride, row * stride + rowBytes), row * rowBytes);
      }
      const seed = Palette.extractSeedHex(pixels, pixelInfo.size.width, pixelInfo.size.height);
      const scheme = await CoverArtColorCache.extractScheme(pixelMap, seed);
      if (scheme !== null) {
        CoverArtColorCache.stashScheme(coverUrl, scheme);
      }
      return seed;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`cover seed extract failed: ${e.message}`);
      return null;
    } finally {
      if (pixelMap !== null) {
        pixelMap.release().catch(() => {});
      }
      if (source !== null) {
        source.release().catch(() => {});
      }
    }
  }

  /**
   * Official extraction path: effectKit ColorPicker top colors + most-saturated
   * color → AccentScheme. Falls back to the Palette seed when effectKit is
   * unavailable on the device.
   */
  private static async extractScheme(pixelMap: image.PixelMap, paletteSeed: string | null): Promise<AccentScheme | null> {
    const candidates: CoverCandidate[] = [];
    try {
      const picker: effectKit.ColorPicker = await effectKit.createColorPicker(pixelMap);
      const largest = picker.getLargestProportionColor();
      if (largest !== null && largest.alpha > 0) {
        candidates.push({ hex: CoverArtColorCache.colorToHex(largest), proportion: 0.5 });
      }
      const tops = picker.getTopProportionColors(6);
      if (tops !== null) {
        const usable = tops.filter((c: effectKit.Color | null): boolean => c !== null && c!.alpha > 0);
        for (const color of usable) {
          candidates.push({ hex: CoverArtColorCache.colorToHex(color!), proportion: 0.4 / Math.max(1, usable.length) });
        }
      }
      const saturated = picker.getHighestSaturationColor();
      if (saturated !== null && saturated.alpha > 0) {
        candidates.push({ hex: CoverArtColorCache.colorToHex(saturated), proportion: 0.1 });
      }
    } catch (error) {
      Logger.warn(`effectKit color pick failed, falling back to Palette: ${(error as Error).message}`);
    }
    if (candidates.length === 0 && paletteSeed !== null) {
      candidates.push({ hex: paletteSeed, proportion: 1.0 });
    }
    if (candidates.length === 0) {
      return null;
    }
    return AccentScheme.from(candidates);
  }

  private static colorToHex(color: effectKit.Color): string {
    const to2 = (v: number): string => {
      const clamped = Math.max(0, Math.min(255, Math.round(v)));
      const text = clamped.toString(16).toUpperCase();
      return text.length < 2 ? `0${text}` : text;
    };
    return `#${to2(color.red)}${to2(color.green)}${to2(color.blue)}`;
  }

  private static async download(coverUrl: string): Promise<ArrayBuffer | null> {
    const client = http.createHttp();
    try {
      const response = await client.request(coverUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 8000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        Logger.warn(`cover seed download failed: HTTP ${response.responseCode}`);
        return null;
      }
      const data = response.result as ArrayBuffer;
      if (data.byteLength <= 0 || data.byteLength > MAX_COVER_BYTES) {
        return null;
      }
      return data;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`cover seed download failed: ${e.message}`);
      return null;
    } finally {
      client.destroy();
    }
  }
}
