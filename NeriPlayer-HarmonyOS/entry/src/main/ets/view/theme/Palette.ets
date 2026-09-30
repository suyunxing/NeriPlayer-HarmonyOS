// SPDX-License-Identifier: GPL-3.0

/**
 * Cover-art color extraction, ported from Android's androidx.palette usage in
 * CoverArtColorCache.kt. Android relies on Palette.from(bitmap)
 *   .clearFilters().generate() and then nests fallbacks
 *   vibrant -> muted -> dominant -> gray. HarmonyOS has no platform Palette,
 * so this file re-implements the semantics on plain RGBA bytes:
 *   1. quantize pixels into a 5-bit-per-channel histogram (Android default
 *      maxColors=16 grid approximation; bucket color = component mean),
 *   2. keep the 16 most populated buckets as swatches,
 *   3. score swatches against the Vibrant/Muted targets with the androidx
 *      weights (saturation 0.24 / luma 0.52 / population 0.24) and the
 *      out-of-range hard cutoffs,
 *   4. fall back vibrant -> muted -> dominant -> #808080.
 * Pure ArkTS on purpose: unit-testable without any @ohos API. The platform
 * glue (http download + image decode) lives in CoverArtColorCache.ets.
 */

const VIBRANT_SAT_MIN = 0.35;
const VIBRANT_SAT_TARGET = 1.0;
const MUTED_SAT_MAX = 0.4;
const MUTED_SAT_TARGET = 0.3;
const LUMA_MIN = 0.3;
const LUMA_MAX = 0.7;
const LUMA_TARGET = 0.5;
const WEIGHT_SATURATION = 0.24;
const WEIGHT_LUMA = 0.52;
const WEIGHT_POPULATION = 0.24;
const MAX_SWATCHES = 16;
const DEFAULT_FALLBACK_HEX = '#808080';

export class PaletteSwatch {
  readonly r: number;
  readonly g: number;
  readonly b: number;
  readonly population: number;
  readonly saturation: number;
  readonly luminance: number;

  constructor(r: number, g: number, b: number, population: number) {
    this.r = r;
    this.g = g;
    this.b = b;
    this.population = population;
    const hsl = PaletteSwatch.rgbToHsl(r, g, b);
    this.saturation = hsl[1];
    this.luminance = hsl[2];
  }

  hex(): string {
    const to2 = (v: number): string => {
      const clamped = Math.max(0, Math.min(255, Math.round(v)));
      const text = clamped.toString(16).toUpperCase();
      return text.length < 2 ? `0${text}` : text;
    };
    return `#${to2(this.r)}${to2(this.g)}${to2(this.b)}`;
  }

  /** Standard sRGB -> HSL (h in [0,360), s/l in [0,1]). */
  static rgbToHsl(r: number, g: number, b: number): number[] {
    const rn = r / 255;
    const gn = g / 255;
    const bn = b / 255;
    const max = Math.max(rn, gn, bn);
    const min = Math.min(rn, gn, bn);
    const l = (max + min) / 2;
    let h = 0;
    let s = 0;
    const delta = max - min;
    if (delta > 0) {
      s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min);
      if (max === rn) {
        h = ((gn - bn) / delta + (gn < bn ? 6 : 0)) * 60;
      } else if (max === gn) {
        h = ((bn - rn) / delta + 2) * 60;
      } else {
        h = ((rn - gn) / delta + 4) * 60;
      }
    }
    return [h, s, l];
  }

  /** Standard HSL -> sRGB, each channel 0..255. */
  static hslToRgb(h: number, s: number, l: number): number[] {
    const hue = ((h % 360) + 360) % 360;
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
    const m = l - c / 2;
    let r = 0;
    let g = 0;
    let b = 0;
    if (hue < 60) {
      r = c;
      g = x;
    } else if (hue < 120) {
      r = x;
      g = c;
    } else if (hue < 180) {
      g = c;
      b = x;
    } else if (hue < 240) {
      g = x;
      b = c;
    } else if (hue < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    const to255 = (v: number): number => Math.max(0, Math.min(255, Math.round((v + m) * 255)));
    return [to255(r), to255(g), to255(b)];
  }

  static score(swatch: PaletteSwatch, maxPopulation: number, satTarget: number): number {
    const saturationScore = 1 - Math.abs(swatch.saturation - satTarget);
    const lumaScore = 1 - Math.abs(swatch.luminance - LUMA_TARGET);
    const populationScore = maxPopulation > 0 ? swatch.population / maxPopulation : 0;
    return saturationScore * WEIGHT_SATURATION + lumaScore * WEIGHT_LUMA + populationScore * WEIGHT_POPULATION;
  }
}

export class PaletteResult {
  readonly swatches: PaletteSwatch[];

  constructor(swatches: PaletteSwatch[]) {
    this.swatches = swatches;
  }

  getDominant(): PaletteSwatch | null {
    let best: PaletteSwatch | null = null;
    for (const swatch of this.swatches) {
      if (best === null || swatch.population > best.population) {
        best = swatch;
      }
    }
    return best;
  }

  getVibrant(): PaletteSwatch | null {
    return this.selectScored(VIBRANT_SAT_MIN, 1.0, VIBRANT_SAT_TARGET);
  }

  getMuted(): PaletteSwatch | null {
    return this.selectScored(0.0, MUTED_SAT_MAX, MUTED_SAT_TARGET);
  }

  private selectScored(satMin: number, satMax: number, satTarget: number): PaletteSwatch | null {
    let best: PaletteSwatch | null = null;
    let bestScore = 0;
    const maxPopulation = this.maxPopulation();
    for (const swatch of this.swatches) {
      if (swatch.saturation < satMin || swatch.saturation > satMax) {
        continue;
      }
      if (swatch.luminance < LUMA_MIN || swatch.luminance > LUMA_MAX) {
        continue;
      }
      const score = PaletteSwatch.score(swatch, maxPopulation, satTarget);
      if (best === null || score > bestScore) {
        best = swatch;
        bestScore = score;
      }
    }
    return best;
  }

  private maxPopulation(): number {
    let max = 0;
    for (const swatch of this.swatches) {
      if (swatch.population > max) {
        max = swatch.population;
      }
    }
    return max;
  }
}

export class Palette {
  /**
   * Quantizes packed RGBA bytes (memory order R,G,B,A per pixel, no stride
   * padding) into a ranked swatch list. Empty or truncated input yields an
   * empty result.
   */
  static extract(pixels: Uint8Array, width: number, height: number): PaletteResult {
    const expected = width * height * 4;
    if (width <= 0 || height <= 0 || pixels.length < expected) {
      return new PaletteResult([]);
    }
    const sums = new Map<number, number[]>();
    for (let i = 0; i + 3 < expected; i += 4) {
      const r = pixels[i];
      const g = pixels[i + 1];
      const b = pixels[i + 2];
      const index = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      const bucket = sums.get(index);
      if (bucket === undefined) {
        sums.set(index, [r, g, b, 1]);
      } else {
        bucket[0] += r;
        bucket[1] += g;
        bucket[2] += b;
        bucket[3] += 1;
      }
    }
    const buckets: number[][] = [];
    sums.forEach((bucket) => {
      buckets.push(bucket);
    });
    buckets.sort((a: number[], b: number[]) => b[3] - a[3]);
    const swatches: PaletteSwatch[] = [];
    const count = Math.min(MAX_SWATCHES, buckets.length);
    for (let i = 0; i < count; i++) {
      const bucket = buckets[i];
      swatches.push(new PaletteSwatch(bucket[0] / bucket[3], bucket[1] / bucket[3], bucket[2] / bucket[3], bucket[3]));
    }
    return new PaletteResult(swatches);
  }

  /** CoverArtColorCache nesting: vibrant -> muted -> dominant -> gray. */
  static extractSeedHex(pixels: Uint8Array, width: number, height: number): string {
    const result = Palette.extract(pixels, width, height);
    const vibrant = result.getVibrant();
    if (vibrant !== null) {
      return vibrant.hex();
    }
    const muted = result.getMuted();
    if (muted !== null) {
      return muted.hex();
    }
    const dominant = result.getDominant();
    return dominant !== null ? dominant.hex() : DEFAULT_FALLBACK_HEX;
  }
}
