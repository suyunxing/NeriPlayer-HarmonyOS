import { describe, it, expect } from '@ohos/hypium';
import { Palette, PaletteSwatch } from '../../../main/ets/view/theme/Palette';
import { CoverColorCacheCore } from '../../../main/ets/view/theme/CoverColorCacheCore';

function solidColorImage(width: number, height: number, r: number, g: number, b: number): Uint8Array {
  const pixels = new Uint8Array(width * height * 4);
  for (let i = 0; i + 3 < pixels.length; i += 4) {
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = 255;
  }
  return pixels;
}

/** Fills the left `leftRatio` of the image with color A and the rest with B. */
function splitColorImage(
  width: number,
  height: number,
  leftRatio: number,
  left: [number, number, number],
  right: [number, number, number]
): Uint8Array {
  const pixels = new Uint8Array(width * height * 4);
  const split = Math.floor(width * leftRatio);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const color = x < split ? left : right;
      const i = (y * width + x) * 4;
      pixels[i] = color[0];
      pixels[i + 1] = color[1];
      pixels[i + 2] = color[2];
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}

export default function paletteTest(): void {
  describe('Palette', () => {
    it('picksVibrantForFullySaturatedCover', 0, () => {
      // Pure red: saturation 1.0, luminance 0.5 -> Vibrant target hit.
      expect(Palette.extractSeedHex(solidColorImage(8, 8, 255, 0, 0), 8, 8)).assertEqual('#FF0000');
    });

    it('fallsBackToMutedForNeutralGray', 0, () => {
      // Gray has saturation 0: fails Vibrant min 0.35 but satisfies Muted
      // [0, 0.4] with luminance 0.5 in range.
      expect(Palette.extractSeedHex(solidColorImage(8, 8, 128, 128, 128), 8, 8)).assertEqual('#808080');
    });

    it('fallsBackToDominantWhenNoTargetMatches', 0, () => {
      // Pure black: luminance 0 fails both targets' [0.3, 0.7] window ->
      // dominant swatch wins.
      expect(Palette.extractSeedHex(solidColorImage(4, 4, 0, 0, 0), 4, 4)).assertEqual('#000000');
    });

    it('vibrantBeatsMutedWhenBothPresent', 0, () => {
      // Left half vivid red, right half gray: the seed must come from the
      // red half (Vibrant has strict priority in the nesting).
      const seed = Palette.extractSeedHex(splitColorImage(16, 8, 0.5, [255, 0, 0], [128, 128, 128]), 16, 8);
      const hsl = PaletteSwatch.rgbToHsl(
        parseInt(seed.slice(1, 3), 16),
        parseInt(seed.slice(3, 5), 16),
        parseInt(seed.slice(5, 7), 16)
      );
      expect(hsl[1]).assertLargerOrEqual(0.3);
    });

    it('populationBreaksTiesBetweenEquallyVividCandidates', 0, () => {
      // Blue occupies 60%, red 40%: both perfect Vibrant candidates, the
      // population weight (0.24) must break the tie for blue.
      const seed = Palette.extractSeedHex(splitColorImage(20, 8, 0.6, [0, 0, 255], [255, 0, 0]), 20, 8);
      expect(seed).assertEqual('#0000FF');
    });

    it('degenerateInputFallsBackToGray', 0, () => {
      expect(Palette.extractSeedHex(new Uint8Array(0), 0, 0)).assertEqual('#808080');
      expect(Palette.extractSeedHex(new Uint8Array(10), 4, 4)).assertEqual('#808080');
    });

    it('bucketMeanColorNotBucketCenterOnly', 0, () => {
      // 63 green pixels (G=200) + 1 pixel nudged to G=202 land in the same
      // 5-bit quantization bucket; the swatch color must be the component
      // mean (~200) rather than a bucket-center guess.
      const pixels = solidColorImage(8, 8, 0, 200, 0);
      pixels[1] = 202;
      const seed = Palette.extractSeedHex(pixels, 8, 8);
      const g = parseInt(seed.slice(3, 5), 16);
      expect(g >= 199 && g <= 201).assertTrue();
    });
  });

  describe('CoverColorCacheCore', () => {
    it('evictsOldestEntryBeyondCapacity', 0, async () => {
      const loads: string[] = [];
      const core = new CoverColorCacheCore(async (url: string): Promise<string | null> => {
        loads.push(url);
        return `#00FF00`;
      }, 2);
      expect(await core.getOrLoad('a')).assertEqual('#00FF00');
      expect(await core.getOrLoad('b')).assertEqual('#00FF00');
      expect(await core.getOrLoad('c')).assertEqual('#00FF00');
      // 'a' was evicted; touching it again must reload.
      expect(await core.getOrLoad('a')).assertEqual('#00FF00');
      expect(loads.join(',')).assertEqual('a,b,c,a');
    });

    it('peekHitsPromoteRecency', 0, async () => {
      const core = new CoverColorCacheCore(async (url: string): Promise<string | null> => `#${url}`, 2);
      await core.getOrLoad('a');
      await core.getOrLoad('b');
      expect(core.peek('a')).assertEqual('#a');
      // 'b' is now the least recent -> evicted next.
      await core.getOrLoad('c');
      expect(core.peek('b')).assertUndefined();
      expect(core.peek('a')).assertEqual('#a');
    });

    it('deduplicatesInFlightLoads', 0, async () => {
      let calls = 0;
      let release: (value: string) => void = (_value: string) => {};
      const gate = new Promise<string>((resolve) => {
        release = resolve;
      });
      const core = new CoverColorCacheCore(async (): Promise<string | null> => {
        calls += 1;
        return gate;
      });
      const first = core.getOrLoad('a');
      const second = core.getOrLoad('a');
      release('#123456');
      expect(await first).assertEqual('#123456');
      expect(await second).assertEqual('#123456');
      expect(calls).assertEqual(1);
    });

    it('loaderFailureCachesNullAndDoesNotRetry', 0, async () => {
      let calls = 0;
      const core = new CoverColorCacheCore(async (): Promise<string | null> => {
        calls += 1;
        throw new Error('boom');
      });
      expect(await core.getOrLoad('bad')).assertNull();
      expect(await core.getOrLoad('bad')).assertNull();
      expect(calls).assertEqual(1);
    });

    it('peekDoesNotTriggerLoad', 0, () => {
      let calls = 0;
      const core = new CoverColorCacheCore(async (): Promise<string | null> => {
        calls += 1;
        return '#ABCDEF';
      });
      expect(core.peek('missing')).assertUndefined();
      expect(calls).assertEqual(0);
    });
  });
}
