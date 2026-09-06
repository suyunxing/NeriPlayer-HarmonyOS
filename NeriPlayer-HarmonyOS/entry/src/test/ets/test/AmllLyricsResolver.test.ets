import { describe, it, expect } from '@ohos/hypium';
import { AmllLyricsResolver, AmllLyricsService } from '../../../main/ets/lyrics/AmllLyricsResolver';
import { AmllSearchResult } from '../../../main/ets/network/AmllTtmlApi';

// Word-timed TTML body; duration is driven by the line end time.
function ttmlWithLines(pairs: [string, string, string][]): string {
  const body = pairs
    .map((pair: [string, string, string]): string => `<p begin="${pair[0]}" end="${pair[1]}"><span begin="${pair[0]}" end="${pair[1]}">${pair[2]}</span></p>`)
    .join('');
  return `<tt><body><div>${body}</div></body></tt>`;
}

function result(file: string, title: string, artist: string, score: number): AmllSearchResult {
  const r = new AmllSearchResult();
  r.file = file;
  r.title = title;
  r.artist = artist;
  r.score = score;
  return r;
}

// A 180s track (matching AmllTtmlClientTest fixtures below).
const TRACK_180S = 180000;

export default function amllLyricsResolverTest(): void {
  describe('AmllLyricsResolver', () => {
    it('normalizesSearchText', 0, () => {
      // NFKC fold of full-width latin + bracket stripping that KEEPS the
      // bracketed content (Android test: "Ｈｅｌｌｏ（World）" -> "hello world").
      expect(AmllLyricsResolver.normalizeSearchText('Ｈｅｌｌｏ（World）')).assertEqual('hello world');
      expect(AmllLyricsResolver.normalizeSearchText('A & B')).assertEqual('a and b');
      // feat marker is dropped, the credited artist text itself remains.
      expect(AmllLyricsResolver.normalizeSearchText('Song (feat. Someone)')).assertEqual('song someone');
      expect(AmllLyricsResolver.normalizeSearchText('  Multiple   Spaces  ')).assertEqual('multiple spaces');
    });

    it('scoresExactMatchAboveThreshold', 0, () => {
      const scores = AmllLyricsResolver.scoreCandidate('ME!', 'Taylor Swift', 'ME!', 'Taylor Swift');
      expect(scores[0]).assertEqual(90);
      expect(scores[1]).assertEqual(55);
      expect(scores[0] + scores[1] >= 70).assertTrue();
    });

    it('rejectsCandidatesWithoutArtistMatch', 0, () => {
      const scores = AmllLyricsResolver.scoreCandidate('ME!', 'Taylor Swift', 'ME!', 'Someone Else');
      expect(scores[1] < 30).assertTrue();
      const ranked = AmllLyricsResolver.rankCandidates('ME!', 'Taylor Swift', [
        result('a.ttml', 'ME!', 'Someone Else', 99),
        result('b.ttml', 'ME!', 'Taylor Swift', 10)
      ]);
      expect(ranked.length).assertEqual(1);
      expect(ranked[0].file).assertEqual('b.ttml');
    });

    it('durationToleranceMirrorsAndroid', 0, () => {
      // 180s track vs 188s lyrics (lyrics longer by 8s): max(30s, 15%) = 30s.
      expect(AmllLyricsResolver.isDurationCompatible(180000, 188000).compatible).assertTrue();
      // 180s vs 240s (longer by 60s): rejected.
      expect(AmllLyricsResolver.isDurationCompatible(180000, 240000).compatible).assertFalse();
      // 253s vs 231.67s (lyrics shorter by 21.33s): max(12s, 10%) = 25.3s.
      expect(AmllLyricsResolver.isDurationCompatible(253000, 231670).compatible).assertTrue();
      // 180s vs 162s (shorter by 18s): max(12s, 18s) = 18s, boundary passes.
      expect(AmllLyricsResolver.isDurationCompatible(180000, 162000).compatible).assertTrue();
      // 180s vs 150s (shorter by 30s > 18s): rejected.
      expect(AmllLyricsResolver.isDurationCompatible(180000, 150000).compatible).assertFalse();
    });

    it('resolveWalksCandidatesUntilWordTimedMatch', 0, async () => {
      // First candidate parses but has no word timings; second wins.
      const ttmls: Record<string, string> = {
        'plain.ttml': '<tt><body><div><p begin="00:00.000" end="03:00.000">plain</p></div></body></tt>',
        'words.ttml': ttmlWithLines([['00:00.000', '00:10.000', 'la']])
      };
      const fetched: string[] = [];
      const resolved = await AmllLyricsResolver.resolve(
        'ME!',
        'Taylor Swift',
        TRACK_180S,
        async (): Promise<AmllSearchResult[]> => [
          result('plain.ttml', 'ME!', 'Taylor Swift', 90),
          result('words.ttml', 'ME!', 'Taylor Swift', 50)
        ],
        async (file: string): Promise<string> => {
          fetched.push(file);
          return ttmls[file];
        },
        false
      );
      expect(resolved !== null).assertTrue();
      expect(resolved![0].words.length).assertEqual(1);
      expect(fetched.join(',')).assertEqual('plain.ttml,words.ttml');
    });

    it('resolveStrictModeRejectsDurationMismatch', 0, async () => {
      // Lyrics end at 10s against a 180s track: far outside tolerance.
      const ttml = ttmlWithLines([['00:00.000', '00:10.000', 'la']]);
      const search = async (): Promise<AmllSearchResult[]> =>
        [result('words.ttml', 'ME!', 'Taylor Swift', 90)];
      const fetchRaw = async (): Promise<string> => ttml;
      const strict = await AmllLyricsResolver.resolve(
        'ME!', 'Taylor Swift', TRACK_180S, search, fetchRaw, true);
      expect(strict).assertNull();
      const loose = await AmllLyricsResolver.resolve(
        'ME!', 'Taylor Swift', TRACK_180S, search, fetchRaw, false);
      expect(loose !== null).assertTrue();
    });

    it('resolveSkipsFetchFailuresAndReturnsNullWhenExhausted', 0, async () => {
      const outcome = await AmllLyricsResolver.resolve(
        'ME!',
        'Taylor Swift',
        TRACK_180S,
        async (): Promise<AmllSearchResult[]> => [
          result('bad.ttml', 'ME!', 'Taylor Swift', 90),
          result('bad2.ttml', 'ME!', 'Taylor Swift', 80)
        ],
        async (): Promise<string> => {
          throw new Error('boom');
        },
        false
      );
      expect(outcome).assertNull();
    });
  });

  describe('AmllLyricsService', () => {
    it('cachesResolvedResultPerKey', 0, async () => {
      AmllLyricsService.clearCache();
      let searches = 0;
      const ttml = ttmlWithLines([['00:00.000', '00:10.000', 'la']]);
      const search = async (): Promise<AmllSearchResult[]> => {
        searches += 1;
        return [result('words.ttml', 'ME!', 'Taylor Swift', 90)];
      };
      const fetchRaw = async (): Promise<string> => ttml;
      const first = await AmllLyricsService.resolveForSong(
        'stable|key', 'ME!', 'Taylor Swift', TRACK_180S, false, search, fetchRaw);
      expect(first !== null).assertTrue();
      const second = await AmllLyricsService.resolveForSong(
        'stable|key', 'ME!', 'Taylor Swift', TRACK_180S, false, search, fetchRaw);
      expect(second !== null).assertTrue();
      // Second call must hit the cache instead of re-searching.
      expect(searches).assertEqual(1);
      // A different duration-match mode is a different cache entry.
      const strict = await AmllLyricsService.resolveForSong(
        'stable|key', 'ME!', 'Taylor Swift', TRACK_180S, true, search, fetchRaw);
      expect(strict).assertNull();
      expect(searches).assertEqual(2);
    });
  });
}
