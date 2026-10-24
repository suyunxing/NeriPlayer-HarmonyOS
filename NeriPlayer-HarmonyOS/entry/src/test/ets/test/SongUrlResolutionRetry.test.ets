import { describe, it, expect } from '@ohos/hypium';
import {
  SONG_URL_RESOLUTION_RETRY_COUNT,
  immediateSongUrlResolutionDelay,
  resolveSongUrlOrWaitForAuthoritativeStream,
  retrySongUrlResolution
} from '../../../main/ets/player/SongUrlResolutionRetry';

class ResolvedShim {
  url: string = '';
  waiting: boolean = false;
}

function shim(url: string, waiting: boolean): ResolvedShim {
  const resolved = new ResolvedShim();
  resolved.url = url;
  resolved.waiting = waiting;
  return resolved;
}

export default function songUrlResolutionRetryTest(): void {
  describe('SongUrlResolutionRetry', () => {
    it('returnsTheFirstSuccessWithoutRetrying', 0, async () => {
      let attempts = 0;
      const url = await retrySongUrlResolution<string>(
        (): Promise<string> => {
          attempts++;
          return Promise.resolve('https://m701.music.126.net/ok.mp3');
        },
        (candidate: string): boolean => candidate.length === 0,
        SONG_URL_RESOLUTION_RETRY_COUNT,
        immediateSongUrlResolutionDelay
      );
      expect(url).assertEqual('https://m701.music.126.net/ok.mp3');
      expect(attempts).assertEqual(1);
    });

    it('retriesOnlyWhileTheResultKeepsFailing', 0, async () => {
      const attemptsSeen: number[] = [];
      const value = await retrySongUrlResolution<number>(
        (attempt: number): Promise<number> => {
          attemptsSeen.push(attempt);
          // Attempts 0 and 1 fail, attempt 2 succeeds.
          return Promise.resolve(attempt < 2 ? 0 : attempt);
        },
        (candidate: number): boolean => candidate === 0,
        SONG_URL_RESOLUTION_RETRY_COUNT,
        immediateSongUrlResolutionDelay
      );
      expect(value).assertEqual(2);
      expect(attemptsSeen.length).assertEqual(3);
      expect(attemptsSeen[0]).assertEqual(0);
      expect(attemptsSeen[1]).assertEqual(1);
      expect(attemptsSeen[2]).assertEqual(2);
    });

    it('exhaustsTheBudgetAndReturnsTheLastFailure', 0, async () => {
      let attempts = 0;
      const url = await retrySongUrlResolution<string>(
        (): Promise<string> => {
          attempts++;
          return Promise.resolve('');
        },
        (candidate: string): boolean => candidate.length === 0,
        SONG_URL_RESOLUTION_RETRY_COUNT,
        immediateSongUrlResolutionDelay
      );
      // One initial attempt plus the five retries.
      expect(url).assertEqual('');
      expect(attempts).assertEqual(SONG_URL_RESOLUTION_RETRY_COUNT + 1);
    });

    it('escalatesTheDelayByRetryNumber', 0, async () => {
      const delays: number[] = [];
      await retrySongUrlResolution<number>(
        (attempt: number): Promise<number> => Promise.resolve(attempt < 3 ? 0 : 1),
        (candidate: number): boolean => candidate === 0,
        3,
        (retryNumber: number): Promise<void> => {
          delays.push(retryNumber);
          return immediateSongUrlResolutionDelay(retryNumber);
        }
      );
      expect(delays.length).assertEqual(3);
      expect(delays[0]).assertEqual(1);
      expect(delays[1]).assertEqual(2);
      expect(delays[2]).assertEqual(3);
    });

    it('rejectsANegativeRetryBudget', 0, async () => {
      let rejected = false;
      try {
        await retrySongUrlResolution<number>(
          (): Promise<number> => Promise.resolve(1),
          (candidate: number): boolean => candidate === 0,
          -1,
          immediateSongUrlResolutionDelay
        );
      } catch {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('waitsForTheAuthoritativeStreamInsteadOfResolving', 0, async () => {
      let resolved = false;
      const waited = await resolveSongUrlOrWaitForAuthoritativeStream<ResolvedShim>(
        true,
        (): ResolvedShim => shim('', true),
        (): Promise<ResolvedShim> => {
          resolved = true;
          return Promise.resolve(shim('https://m701.music.126.net/local.mp3', false));
        }
      );
      expect(waited.waiting).assertTrue();
      expect(waited.url).assertEqual('');
      expect(resolved).assertFalse();

      const notWaited = await resolveSongUrlOrWaitForAuthoritativeStream<ResolvedShim>(
        false,
        (): ResolvedShim => shim('', true),
        (): Promise<ResolvedShim> =>
          Promise.resolve(shim('https://m701.music.126.net/local.mp3', false))
      );
      expect(notWaited.waiting).assertFalse();
      expect(notWaited.url).assertEqual('https://m701.music.126.net/local.mp3');
    });
  });
}
