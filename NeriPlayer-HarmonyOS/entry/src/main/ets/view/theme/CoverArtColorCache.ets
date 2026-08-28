/**
 * Platform glue for cover-seed extraction: downloads the cover, decodes a
 * tiny downsampled RGBA bitmap, and hands it to the pure Palette. Mirrors
 * CoverArtColorCache.preload/getOrLoad (96px decode size, Coil replaced by
 * @ohos http + @ohos image) and adds a generation token so a slow extraction
 * finishing after a track switch never publishes a stale seed for the new
 * song (the PlayerManager publishes songs synchronously, extraction is not).
 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { Logger } from '../../app/Logger';
import { Palette } from './Palette';
import { CoverColorCacheCore } from './CoverColorCacheCore';
import { MotionSpec } from './MotionSpec';
import { MotionCurves } from './MotionCurves';

// Android decodes at sizePx=96; that already is the low-end downsample
// strategy (9216 pixels), so no extra device-tier branching is needed.
const DECODE_SIZE = 96;
const MAX_COVER_BYTES = 8 * 1024 * 1024;

export class CoverArtColorCache {
  private static readonly core: CoverColorCacheCore = new CoverColorCacheCore(
    (coverUrl: string): Promise<string | null> => CoverArtColorCache.loadCoverSeed(coverUrl)
  );
  private static generation: number = 0;

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
      const value = hex ?? '';
      // The seed drives accent colors in MiniPlayer/NowPlaying through
      // @Watch mirrors, so wrapping the publish in animateTo recolors them
      // as a 420ms transition on track switch — the counterpart of
      // NeriTheme.kt's animateColorScheme (UI_ANIMATION_PLAN.md §4 M11.6a).
      // animateTo is best-effort: a cold-start publish racing window
      // creation must not swallow the seed, so fall back to a plain write.
      try {
        animateTo({
          duration: MotionSpec.THEME_COLOR_TRANSITION_MS,
          curve: MotionCurves.fastOutSlowIn()
        }, () => {
          AppStorage.setOrCreate('player.coverSeedHex', value);
        });
      } catch (error) {
        AppStorage.setOrCreate('player.coverSeedHex', value);
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
      return Palette.extractSeedHex(pixels, pixelInfo.size.width, pixelInfo.size.height);
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
