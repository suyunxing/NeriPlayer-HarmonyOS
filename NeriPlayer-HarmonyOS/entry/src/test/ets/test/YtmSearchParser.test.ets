import { describe, it, expect } from '@ohos/hypium';
import { parseYtmDurationMs, parseYtmSearchResponse } from '../../../main/ets/network/ytm/YtmSearchParser';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';
import { stableSyncId } from '../../../main/ets/sync/SyncModels';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

/** Wraps shelf sections in the envelope both search endpoints share. */
function searchResponse(sections: string): string {
  return '{"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":'
    + `{"sectionListRenderer":{"contents":[${sections}]}}}}]}}}`;
}

/**
 * One musicResponsiveListItem row: flexColumns[0] is the title, flexColumns[1]
 * the metadata runs, and fixedColumns[0] the duration when the shelf has one.
 */
function row(videoId: string, title: string, metaTexts: string[], duration: string): string {
  const runs = metaTexts.map((text: string) => `{"text":${JSON.stringify(text)}}`).join(',');
  const fixed = duration.length > 0
    ? ',"fixedColumns":[{"musicResponsiveListItemFixedColumnRenderer":'
      + `{"text":{"runs":[{"text":${JSON.stringify(duration)}}]}}}]`
    : '';
  return '{"musicResponsiveListItemRenderer":{"playlistItemData":'
    + `{"videoId":${JSON.stringify(videoId)}},"flexColumns":`
    + `[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":${JSON.stringify(title)}}]}}},`
    + `{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[${runs}]}}}]${fixed}}}`;
}

export default function ytmSearchParserTest(): void {
  describe('YtmSearchParser', () => {
    it('parsesRowsFromTheGenericSearchItemSection', 0, () => {
      // The anonymous music/search endpoint answers 404, so the generic
      // /youtubei/v1/search endpoint is the live shape (M6.5).
      const json = searchResponse(
        `{"itemSectionRenderer":{"contents":[${row('vid001', 'Numb', ['Song', 'bullet', 'Linkin Park'], '3:07')}]}}`
      );
      const items = parseYtmSearchResponse(json, 20);
      expect(items.length).assertEqual(1);
      expect(items[0].name).assertEqual('Numb');
      // 'Song' is a result-type label, not the artist.
      expect(items[0].artist).assertEqual('Linkin Park');
      expect(items[0].durationMs).assertEqual(187000);
      expect(items[0].audioId).assertEqual('vid001');
      expect(items[0].mediaUri).assertEqual('youtube_music|vid001');
      expect(items[0].channelId).assertEqual('youtube_music');
      expect(items[0].platform).assertEqual(MusicPlatform.YOUTUBE_MUSIC);
    });

    it('stillParsesTheRetiredMusicShelfShape', 0, () => {
      const json = searchResponse(
        `{"musicShelfRenderer":{"contents":[${row('vid002', 'In The End', ['Linkin Park'], '3:36')}]}}`
      );
      const items = parseYtmSearchResponse(json, 20);
      expect(items.length).assertEqual(1);
      expect(items[0].name).assertEqual('In The End');
      expect(items[0].durationMs).assertEqual(216000);
    });

    it('dedupesTheBestMatchCardRepeatedInTheItemSection', 0, () => {
      // The generic endpoint shows the top hit twice: once as a card, once as a
      // normal row. Without de-duplication the same track appears twice.
      const card = `{"musicCardShelfRenderer":{"contents":[${row('vid001', 'Numb', ['Linkin Park'], '3:07')}]}}`;
      const list = `{"itemSectionRenderer":{"contents":[${row('vid001', 'Numb', ['Song', 'bullet', 'Linkin Park'], '3:07')},`
        + `${row('vid003', 'Faint', ['Song', 'bullet', 'Linkin Park'], '2:42')}]}}`;
      const items = parseYtmSearchResponse(searchResponse(`${card},${list}`), 20);
      expect(items.length).assertEqual(2);
      // Response order is preserved: the card row wins, the duplicate is dropped.
      expect(items[0].audioId).assertEqual('vid001');
      expect(items[1].audioId).assertEqual('vid003');
    });

    it('keepsTheStableKeyIndependentOfTheAlbumColumn', 0, () => {
      // The generic endpoint's metadata runs carry no album, so the parser
      // leaves it empty. YTM identities derive from the videoId and pin the
      // album component to the 'youtube_music' constant, so the stable key must
      // not move — otherwise every persisted YTM entry would be orphaned.
      const json = searchResponse(
        `{"itemSectionRenderer":{"contents":[${row('vid001', 'Numb', ['Song', 'bullet', 'Linkin Park'], '3:07')}]}}`
      );
      const items = parseYtmSearchResponse(json, 5);
      expect(items[0].album).assertEqual('');
      expect(stableKeyOf(items[0])).assertEqual(`${stableSyncId('vid001')}|youtube_music|youtube_music|vid001`);
    });

    it('readsDurationFromMetadataWhenTheShelfHasNoFixedColumn', 0, () => {
      // Card rows put the duration last in the metadata runs instead.
      const json = searchResponse(
        '{"musicCardShelfRenderer":{"contents":['
        + `${row('vid004', 'Breaking The Habit', ['Linkin Park', 'bullet', '1.2M views', 'bullet', '3:16'], '')}]}}`
      );
      const items = parseYtmSearchResponse(json, 20);
      expect(items.length).assertEqual(1);
      expect(items[0].artist).assertEqual('Linkin Park');
      expect(items[0].durationMs).assertEqual(196000);
    });

    it('skipsUnusableRowsAndHonoursTheLimit', 0, () => {
      const usable = row('vid005', 'One Step Closer', ['Linkin Park'], '2:36');
      const noVideoId = row('', 'Advertisement', ['Sponsored'], '0:30');
      const json = searchResponse(`{"itemSectionRenderer":{"contents":[${noVideoId},${usable},${usable}]}}`);
      const items = parseYtmSearchResponse(json, 20);
      expect(items.length).assertEqual(1);
      expect(items[0].audioId).assertEqual('vid005');
      expect(parseYtmSearchResponse(json, 0).length).assertEqual(0);
      // An empty shelf list is a valid response, not a parse failure.
      expect(parseYtmSearchResponse(searchResponse(''), 20).length).assertEqual(0);
      expect(parseYtmSearchResponse('{}', 20).length).assertEqual(0);
    });

    it('parsesDurationTextAndRejectsGarbage', 0, () => {
      expect(parseYtmDurationMs('3:07')).assertEqual(187000);
      expect(parseYtmDurationMs('1:02:03')).assertEqual(3723000);
      expect(parseYtmDurationMs('45')).assertEqual(45000);
      expect(parseYtmDurationMs('abc')).assertEqual(0);
      expect(parseYtmDurationMs('-1:00')).assertEqual(0);
      expect(parseYtmDurationMs('')).assertEqual(0);
    });
  });
}
