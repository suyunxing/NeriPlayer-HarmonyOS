/**
 * Standard color card used to snap the cover's dominant color to a
 * designer-grade "重点色" (accent). Nearest match is by CIEDE2000 over the
 * GENERATED_SWATCHES table.
 *
 * Compliance note: the table carries only swatch numbers and sRGB hex
 * approximations generated from the MIT-licensed `pantone-colors` dataset
 * (github.com/tranvansang/pantone-colors). No trademarked color names are
 * embedded; values are unofficial approximations and this project is not
 * affiliated with Pantone LLC. "PANTONE" must not appear in user-facing
 * strings, the app name, or store keywords.
 */
import { ColorScience, Lab, Lch } from './ColorScience';
import { GENERATED_SWATCHES } from './SwatchData';

export interface Swatch {
  /** Card number, e.g. '1788'. */
  code: string;
  /** sRGB approximation, '#RRGGBB'. */
  hex: string;
}

export interface NearestSwatch {
  swatch: Swatch;
  /** CIEDE2000 distance to the query color. */
  deltaE: number;
}

/** Cached Lab/LCh per swatch hex, built once per process. */
class SwatchLabCache {
  readonly labs: Lab[] = [];
  readonly lchs: Lch[] = [];

  constructor() {
    for (const swatch of GENERATED_SWATCHES) {
      const lab = ColorScience.hexToLab(swatch.hex);
      if (lab !== null) {
        this.labs.push(lab);
        this.lchs.push(ColorScience.labToLch(lab));
      } else {
        // Malformed generated data would be a build-data bug; keep index
        // alignment with a neutral placeholder.
        this.labs.push(new Lab(50, 0, 0));
        this.lchs.push(new Lch(50, 0, 0));
      }
    }
  }
}

export class SwatchCard {
  private static cache: SwatchLabCache | null = null;

  static all(): Swatch[] {
    return GENERATED_SWATCHES;
  }

  private static labCache(): SwatchLabCache {
    if (SwatchCard.cache === null) {
      SwatchCard.cache = new SwatchLabCache();
    }
    return SwatchCard.cache;
  }

  /** Exact table lookup by code; null when unknown. */
  static byCode(code: string): Swatch | null {
    for (const swatch of GENERATED_SWATCHES) {
      if (swatch.code === code) {
        return swatch;
      }
    }
    return null;
  }

  /**
   * Nearest swatch by CIEDE2000. 907 candidates × one Lab conversion is a
   * few milliseconds — no spatial index needed.
   */
  static nearest(hex: string): NearestSwatch | null {
    const lab = ColorScience.hexToLab(hex);
    if (lab === null) {
      return null;
    }
    const cache = SwatchCard.labCache();
    let bestIndex = -1;
    let bestDelta = Number.MAX_VALUE;
    for (let i = 0; i < cache.labs.length; i++) {
      const delta = ColorScience.deltaE2000(lab, cache.labs[i]);
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) {
      return null;
    }
    return {
      swatch: GENERATED_SWATCHES[bestIndex],
      deltaE: bestDelta
    };
  }

  /** LCh of a swatch by code (for hue-locked derivation); null when unknown. */
  static lchByCode(code: string): Lch | null {
    const cache = SwatchCard.labCache();
    for (let i = 0; i < GENERATED_SWATCHES.length; i++) {
      if (GENERATED_SWATCHES[i].code === code) {
        return cache.lchs[i];
      }
    }
    return null;
  }
}
