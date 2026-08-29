/**
 * Pure color-science primitives for the dynamic cover scheme: sRGB → CIELAB,
 * LCh(uv-free polar Lab) round-trips, CIEDE2000 color difference and WCAG
 * relative-luminance contrast. No platform imports — pinned by unit tests
 * against published reference values (Sharma 2005 ΔE00 dataset, WCAG formulas).
 *
 * Why Lab/LCh instead of HSL: perceptual lightness (L*) is what the contrast
 * guardrails need; HSL "lightness" does not track perceived lightness and
 * made the old derivation unable to guarantee readable accent/surface pairs.
 */

/** CIELAB coordinates. L* in [0,100]; the a and b axes roughly [-128,128]. */
export class Lab {
  readonly l: number;
  readonly a: number;
  readonly b: number;

  constructor(l: number, a: number, b: number) {
    this.l = l;
    this.a = a;
    this.b = b;
  }
}

/** Cylindrical Lab (L*, chroma, hue in degrees [0,360)). */
export class Lch {
  readonly l: number;
  readonly c: number;
  readonly h: number;

  constructor(l: number, c: number, h: number) {
    this.l = l;
    this.c = c;
    this.h = h;
  }
}

const XN = 0.95047;
const YN = 1.0;
const ZN = 1.08883;
const EPSILON = 216.0 / 24389.0; // (6/29)^3
const KAPPA = 24389.0 / 27.0; // (29/3)^3

export class ColorScience {
  /** '#RRGGBB' or '#AARRGGBB' (hex part) → [r,g,b] 0..255; null when malformed. */
  static parseHex(hex: string): number[] | null {
    let body = hex.trim();
    if (body.startsWith('#')) {
      body = body.slice(1);
    }
    if (body.length === 8) {
      body = body.slice(2);
    }
    if (!/^[0-9a-fA-F]{6}$/.test(body)) {
      return null;
    }
    return [
      parseInt(body.slice(0, 2), 16),
      parseInt(body.slice(2, 4), 16),
      parseInt(body.slice(4, 6), 16)
    ];
  }

  static rgbToHex(r: number, g: number, b: number): string {
    const to2 = (v: number): string => {
      const clamped = Math.max(0, Math.min(255, Math.round(v)));
      const text = clamped.toString(16).toUpperCase();
      return text.length < 2 ? `0${text}` : text;
    };
    return `#${to2(r)}${to2(g)}${to2(b)}`;
  }

  /** 8-bit sRGB → linear-light value (IEC 61966-2-1). */
  static srgbToLinear(c8: number): number {
    const c = c8 / 255.0;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  }

  static linearToSrgb8(linear: number): number {
    const c = linear <= 0.0031308 ? linear * 12.92 : 1.055 * Math.pow(linear, 1 / 2.4) - 0.055;
    return Math.max(0, Math.min(255, Math.round(c * 255)));
  }

  static linearRgbToXyz(r: number, g: number, b: number): number[] {
    return [
      0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
      0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
      0.0193339 * r + 0.1191920 * g + 0.9503041 * b
    ];
  }

  static xyzToLinearRgb(x: number, y: number, z: number): number[] {
    return [
      3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
      -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
      0.0556434 * x - 0.2040259 * y + 1.0572252 * z
    ];
  }

  private static labF(t: number): number {
    return t > EPSILON ? Math.cbrt(t) : (KAPPA * t + 16.0) / 116.0;
  }

  private static labFInverse(t: number): number {
    const e = 6.0 / 29.0;
    return t > e ? t * t * t : 3 * e * e * (t - 4.0 / 29.0);
  }

  static rgbToLab(r8: number, g8: number, b8: number): Lab {
    const xyz = ColorScience.linearRgbToXyz(
      ColorScience.srgbToLinear(r8),
      ColorScience.srgbToLinear(g8),
      ColorScience.srgbToLinear(b8)
    );
    const fx = ColorScience.labF(xyz[0] / XN);
    const fy = ColorScience.labF(xyz[1] / YN);
    const fz = ColorScience.labF(xyz[2] / ZN);
    return new Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  static hexToLab(hex: string): Lab | null {
    const rgb = ColorScience.parseHex(hex);
    if (rgb === null) {
      return null;
    }
    return ColorScience.rgbToLab(rgb[0], rgb[1], rgb[2]);
  }

  static labToHex(lab: Lab): string {
    // Invert f() around the whole sums: X/Xn = f⁻¹(a/500 + f(Y/Yn)), not
    // a/500 + f⁻¹(f(Y/Yn)) — inverting the wrong term shifts hue badly on
    // saturated colors.
    const fyf = (lab.l + 16.0) / 116.0;
    const fx = ColorScience.labFInverse(lab.a / 500.0 + fyf);
    const fy = ColorScience.labFInverse(fyf);
    const fz = ColorScience.labFInverse(fyf - lab.b / 200.0);
    const xyz = [fx * XN, fy * YN, fz * ZN];
    const lin = ColorScience.xyzToLinearRgb(xyz[0], xyz[1], xyz[2]);
    return ColorScience.rgbToHex(
      ColorScience.linearToSrgb8(lin[0]),
      ColorScience.linearToSrgb8(lin[1]),
      ColorScience.linearToSrgb8(lin[2])
    );
  }

  static labToLch(lab: Lab): Lch {
    const c = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
    let h = Math.atan2(lab.b, lab.a) * 180.0 / Math.PI;
    if (h < 0) {
      h += 360.0;
    }
    return new Lch(lab.l, c, h);
  }

  static lchToLab(lch: Lch): Lab {
    const rad = lch.h * Math.PI / 180.0;
    return new Lab(lch.l, lch.c * Math.cos(rad), lch.c * Math.sin(rad));
  }

  static lchToHex(lch: Lch): string {
    return ColorScience.labToHex(ColorScience.lchToLab(lch));
  }

  private static lchToSrgbFloats(l: number, c: number, h: number): number[] {
    const rad = h * Math.PI / 180.0;
    const lab = new Lab(l, c * Math.cos(rad), c * Math.sin(rad));
    const fyf = (lab.l + 16.0) / 116.0;
    const fx = ColorScience.labFInverse(lab.a / 500.0 + fyf);
    const fy = ColorScience.labFInverse(fyf);
    const fz = ColorScience.labFInverse(fyf - lab.b / 200.0);
    const lin = ColorScience.xyzToLinearRgb(fx * XN, fy * YN, fz * ZN);
    return lin.map((v: number): number => {
      const s = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
      return s * 255.0;
    });
  }

  /**
   * LCh → hex with gamut mapping: instead of clamping out-of-range sRGB
   * channels (which shifts hue on saturated colors), binary-search the
   * largest chroma at or below the requested value that fits the sRGB gamut
   * at this lightness and hue.
   */
  static lchToHexInGamut(l: number, c: number, h: number): string {
    const fits = (chroma: number): boolean => {
      const rgb = ColorScience.lchToSrgbFloats(l, chroma, h);
      return rgb[0] >= -0.5 && rgb[0] <= 255.5
        && rgb[1] >= -0.5 && rgb[1] <= 255.5
        && rgb[2] >= -0.5 && rgb[2] <= 255.5;
    };
    let chroma = c;
    if (!fits(chroma)) {
      let lo = 0;
      let hi = chroma;
      for (let i = 0; i < 24; i++) {
        const mid = (lo + hi) / 2;
        if (fits(mid)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      chroma = lo;
    }
    return ColorScience.lchToHex(new Lch(l, chroma, h));
  }

  static hexToLch(hex: string): Lch | null {
    const lab = ColorScience.hexToLab(hex);
    return lab !== null ? ColorScience.labToLch(lab) : null;
  }

  /**
   * CIEDE2000 ΔE00 (kL=kC=kH=1). Full formula incl. hue-term rotation;
   * reference values from Sharma et al. 2005 implementation notes are pinned
   * by unit tests.
   */
  static deltaE2000(lab1: Lab, lab2: Lab): number {
    const c1 = Math.sqrt(lab1.a * lab1.a + lab1.b * lab1.b);
    const c2 = Math.sqrt(lab2.a * lab2.a + lab2.b * lab2.b);
    const cBar = (c1 + c2) / 2.0;
    const cBar7 = Math.pow(cBar, 7);
    const g = 0.5 * (1 - Math.sqrt(cBar7 / (cBar7 + Math.pow(25, 7))));
    const a1p = lab1.a * (1 + g);
    const a2p = lab2.a * (1 + g);
    const c1p = Math.sqrt(a1p * a1p + lab1.b * lab1.b);
    const c2p = Math.sqrt(a2p * a2p + lab2.b * lab2.b);
    const h1p = c1p === 0 ? 0 : ColorScience.normalizedHueDeg(lab1.b, a1p);
    const h2p = c2p === 0 ? 0 : ColorScience.normalizedHueDeg(lab2.b, a2p);

    const dLp = lab2.l - lab1.l;
    const dCp = c2p - c1p;
    let dhp = 0;
    if (c1p * c2p !== 0) {
      dhp = h2p - h1p;
      if (dhp > 180) {
        dhp -= 360;
      } else if (dhp < -180) {
        dhp += 360;
      }
    }
    const dHp = 2 * Math.sqrt(c1p * c2p) * Math.sin(dhp * Math.PI / 360.0);

    const lBarP = (lab1.l + lab2.l) / 2.0;
    const cBarP = (c1p + c2p) / 2.0;
    let hBarP = h1p + h2p;
    if (c1p * c2p !== 0) {
      if (Math.abs(h1p - h2p) <= 180) {
        hBarP = (h1p + h2p) / 2.0;
      } else if (h1p + h2p < 360) {
        hBarP = (h1p + h2p + 360) / 2.0;
      } else {
        hBarP = (h1p + h2p - 360) / 2.0;
      }
    }
    const t = 1
      - 0.17 * Math.cos((hBarP - 30) * Math.PI / 180)
      + 0.24 * Math.cos(2 * hBarP * Math.PI / 180)
      + 0.32 * Math.cos((3 * hBarP + 6) * Math.PI / 180)
      - 0.20 * Math.cos((4 * hBarP - 63) * Math.PI / 180);
    const dTheta = 30 * Math.exp(-Math.pow((hBarP - 275) / 25, 2));
    const cBarP7 = Math.pow(cBarP, 7);
    const rc = 2 * Math.sqrt(cBarP7 / (cBarP7 + Math.pow(25, 7)));
    const sl = 1 + 0.015 * Math.pow(lBarP - 50, 2) / Math.sqrt(20 + Math.pow(lBarP - 50, 2));
    const sc = 1 + 0.045 * cBarP;
    const sh = 1 + 0.015 * cBarP * t;
    const rt = -Math.sin(2 * dTheta * Math.PI / 180) * rc;

    const termL = dLp / sl;
    const termC = dCp / sc;
    const termH = dHp / sh;
    return Math.sqrt(termL * termL + termC * termC + termH * termH + rt * termC * termH);
  }

  private static normalizedHueDeg(b: number, ap: number): number {
    const h = Math.atan2(b, ap) * 180.0 / Math.PI;
    return h < 0 ? h + 360.0 : h;
  }

  /** WCAG 2.1 relative luminance of an sRGB hex. */
  static relativeLuminance(hex: string): number {
    const rgb = ColorScience.parseHex(hex);
    if (rgb === null) {
      return 0;
    }
    return 0.2126 * ColorScience.srgbToLinear(rgb[0])
      + 0.7152 * ColorScience.srgbToLinear(rgb[1])
      + 0.0722 * ColorScience.srgbToLinear(rgb[2]);
  }

  /** WCAG contrast ratio in [1,21]. */
  static contrastRatio(hexA: string, hexB: string): number {
    const la = ColorScience.relativeLuminance(hexA);
    const lb = ColorScience.relativeLuminance(hexB);
    const lighter = Math.max(la, lb);
    const darker = Math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /** True when the two hues are within `toleranceDeg` on the short arc. */
  static hueWithin(h1: number, h2: number, toleranceDeg: number): boolean {
    let diff = Math.abs(h1 - h2) % 360;
    if (diff > 180) {
      diff = 360 - diff;
    }
    return diff <= toleranceDeg;
  }
}
