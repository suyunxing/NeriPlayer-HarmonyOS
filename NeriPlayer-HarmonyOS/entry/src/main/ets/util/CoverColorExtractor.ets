import { image } from '@kit.ImageKit';
import { HttpClient } from '../network/HttpClient';
import { Logger } from '../app/Logger';

/**
 * Dynamic cover-color extraction (roadmap item: 动态取色).
 *
 * Downloads the cover bytes once, decodes a tiny 12x12 RGBA PixelMap and picks
 * the most saturated pixel with an acceptable brightness as the accent color.
 * The result is used by NowPlaying for slider/lyric highlights.
 */
export class CoverColorExtractor {
  private static readonly SAMPLE_SIZE: number = 12;

  static async extractAccent(coverUrl: string): Promise<string> {
    if (coverUrl.length === 0) {
      return '';
    }
    try {
      const response = await HttpClient.getBytes(coverUrl, {}, 12000, false);
      if (response.statusCode < 200 || response.statusCode >= 300 || response.body.byteLength === 0) {
        return '';
      }
      const source = image.createImageSource(response.body);
      let pixelMap: image.PixelMap | null = null;
      try {
        const options: image.DecodingOptions = {
          desiredSize: {
            width: CoverColorExtractor.SAMPLE_SIZE,
            height: CoverColorExtractor.SAMPLE_SIZE
          },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        };
        pixelMap = await source.createPixelMap(options);
        const byteLength = pixelMap.getPixelBytesNumber();
        if (byteLength <= 0) {
          return '';
        }
        const buffer = new ArrayBuffer(byteLength);
        await pixelMap.readPixelsToBuffer(buffer);
        return CoverColorExtractor.pickAccent(new Uint8Array(buffer));
      } finally {
        try {
          if (pixelMap !== null) {
            await pixelMap.release();
          }
        } catch (releaseError) {
          const e = releaseError as Error;
          Logger.debug(`CoverColorExtractor pixelMap.release failed: ${e.message}`);
        }
        try {
          await source.release();
        } catch (releaseError) {
          const e = releaseError as Error;
          Logger.debug(`CoverColorExtractor imageSource.release failed: ${e.message}`);
        }
      }
    } catch (error) {
      const e = error as Error;
      Logger.debug(`CoverColorExtractor.extractAccent failed: ${e.message}`);
      return '';
    }
  }

  private static pickAccent(bytes: Uint8Array): string {
    let bestScore = -1;
    let bestRed = 124;
    let bestGreen = 77;
    let bestBlue = 255;
    let sumRed = 0;
    let sumGreen = 0;
    let sumBlue = 0;
    let visible = 0;
    for (let i = 0; i + 3 < bytes.length; i += 4) {
      const alpha = bytes[i + 3];
      if (alpha < 200) {
        continue;
      }
      const red = bytes[i];
      const green = bytes[i + 1];
      const blue = bytes[i + 2];
      visible += 1;
      sumRed += red;
      sumGreen += green;
      sumBlue += blue;

      const max = Math.max(red, Math.max(green, blue));
      const min = Math.min(red, Math.min(green, blue));
      if (max === min) {
        continue;
      }
      const saturation = (max - min) / 255;
      const luminance = (red * 299 + green * 587 + blue * 114) / 1000;
      if (luminance < 42 || luminance > 235) {
        continue;
      }
      const score = saturation * 10 + (1 - Math.abs(luminance - 140) / 140) * 2;
      if (score > bestScore) {
        bestScore = score;
        bestRed = red;
        bestGreen = green;
        bestBlue = blue;
      }
    }
    if (bestScore < 0 && visible > 0) {
      bestRed = Math.round(sumRed / visible);
      bestGreen = Math.round(sumGreen / visible);
      bestBlue = Math.round(sumBlue / visible);
    }
    return CoverColorExtractor.toHex(bestRed, bestGreen, bestBlue);
  }

  private static toHex(red: number, green: number, blue: number): string {
    const r = CoverColorExtractor.channelHex(red);
    const g = CoverColorExtractor.channelHex(green);
    const b = CoverColorExtractor.channelHex(blue);
    return `#${r}${g}${b}`;
  }

  private static channelHex(value: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(value)));
    return clamped.toString(16).padStart(2, '0');
  }
}
