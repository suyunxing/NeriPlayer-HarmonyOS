import { describe, it, expect } from '@ohos/hypium';
import {
  shouldSupplementLyrics,
  pickBestNeteaseCandidate
} from '../../../main/ets/lyrics/LyricDispatcher';
import { isLrcLibDurationPlausible } from '../../../main/ets/network/LyricApi';
import { LyricLine } from '../../../main/ets/model/LyricLine';
import { SongItem } from '../../../main/ets/model/SongItem';

function line(text: string, translated: string = '', phonetic: string = ''): LyricLine {
  return new LyricLine(1000, text, translated, phonetic);
}

function songOf(name: string, artist: string, durationMs: number): SongItem {
  const song = new SongItem(1, name, artist, 'Album', 0, durationMs);
  song.channelId = 'bilibili';
  song.audioId = '1';
  return song;
}

export default function lyricDispatcherTest(): void {
  describe('LyricSupplementPolicy', () => {
    it('emptyOrIncompleteLinesRequestSupplement', 0, () => {
      expect(shouldSupplementLyrics([])).assertTrue();
      expect(shouldSupplementLyrics([line('歌詞')])).assertTrue();
      expect(shouldSupplementLyrics([line('歌詞', 'translation')])).assertTrue();
      expect(shouldSupplementLyrics([line('歌詞', '', 'romaji')])).assertTrue();
      expect(shouldSupplementLyrics([line('歌詞', 'translation', 'romaji')])).assertFalse();
      // One filled row per channel is enough to skip the extra lookup.
      expect(shouldSupplementLyrics([line('a'), line('b', 'tr', 'ro')])).assertFalse();
    });

    it('pickBestAppliesDurationAndKeywordGuard', 0, () => {
      const expected = songOf('晴天', '周杰伦', 269000);
      const good = songOf('晴天', '周杰伦', 270000);
      good.channelId = 'netease';
      good.audioId = '100';
      expect(pickBestNeteaseCandidate(expected, [good]) !== null).assertTrue();
      // Unrelated artist with matching title: keyword-drift rejection.
      const drift = songOf('晴天', '不知名歌手', 269000);
      drift.channelId = 'netease';
      expect(pickBestNeteaseCandidate(expected, [drift])).assertNull();
      // Empty candidate list never matches.
      expect(pickBestNeteaseCandidate(expected, [])).assertNull();
    });

    it('lrclibDurationGuardTolerance', 0, () => {
      expect(isLrcLibDurationPlausible(269000, 269)).assertTrue();
      expect(isLrcLibDurationPlausible(269000, 262)).assertTrue();
      expect(isLrcLibDurationPlausible(269000, 280)).assertFalse();
      expect(isLrcLibDurationPlausible(0, 280)).assertTrue();
      expect(isLrcLibDurationPlausible(269000, 0)).assertTrue();
    });
  });

  describe('MatchedPhoneticRoundTrip', () => {
    it('songItemKeepsMatchedPhoneticAcrossJson', 0, () => {
      const song = new SongItem(2, 'T', 'A', 'Album', 0, 200000);
      song.matchedLyric = '[00:01.00]歌詞';
      song.matchedTranslatedLyric = '[00:01.00]translation';
      song.matchedPhoneticLyric = '[00:01.00]romaji';
      const restored = SongItem.fromJson(song.toJson());
      expect(restored.matchedPhoneticLyric).assertEqual('[00:01.00]romaji');
      // Legacy JSON without the field loads as empty, not undefined.
      const fromLegacy = SongItem.fromJson('{"id":3,"name":"T","artist":"A","matchedLyric":"x"}');
      expect(fromLegacy.matchedPhoneticLyric).assertEqual('');
    });
  });
}
