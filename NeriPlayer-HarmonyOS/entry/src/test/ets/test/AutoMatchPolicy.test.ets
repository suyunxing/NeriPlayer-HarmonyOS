import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { AutoMatchPolicy, MatchDetailPatch } from '../../../main/ets/util/AutoMatchPolicy';

function localSong(name: string, artist: string): SongItem {
  const song = new SongItem(7, name, artist, '', 0, 210000, '', 'file://media/7.mp3', MusicPlatform.LOCAL);
  return song;
}

function patch(modifier: (detail: MatchDetailPatch) => void): MatchDetailPatch {
  const detail: MatchDetailPatch = {
    source: 'netease',
    id: '186016',
    name: '晴天',
    artist: '周杰伦',
    coverUrl: 'https://example.com/cover.jpg',
    lyric: '[00:00.00]故事的小黄花',
    translatedLyric: ''
  };
  modifier(detail);
  return detail;
}

export default function autoMatchPolicyTest(): void {
  describe('AutoMatchPolicy', () => {
    it('missingMetadataDetectsEachGapIndependently', 0, () => {
      expect(AutoMatchPolicy.hasMissingMetadata(localSong('晴天', ''))).assertTrue();
      expect(AutoMatchPolicy.hasMissingMetadata(localSong('晴天', '周杰伦'))).assertTrue();

      const covered = localSong('晴天', '周杰伦');
      covered.coverUrl = 'https://example.com/c.jpg';
      expect(AutoMatchPolicy.hasMissingMetadata(covered)).assertTrue();

      covered.matchedLyric = '[00:00.00]x';
      expect(AutoMatchPolicy.hasMissingMetadata(covered)).assertFalse();

      // customArtist/customCoverUrl count as present metadata.
      const customized = localSong('晴天', '');
      customized.customArtist = '周杰伦';
      expect(AutoMatchPolicy.hasMissingMetadata(customized)).assertTrue();
      customized.customCoverUrl = 'https://example.com/c.jpg';
      expect(AutoMatchPolicy.hasMissingMetadata(customized)).assertTrue();
      customized.matchedLyric = '[00:00.00]x';
      expect(AutoMatchPolicy.hasMissingMetadata(customized)).assertFalse();
    });

    it('searchKeywordPrefersExtractedArtistThenFallback', 0, () => {
      expect(AutoMatchPolicy.buildSearchKeyword({ title: '晴天', artist: '周杰伦' }, '别人'))
        .assertEqual('晴天 周杰伦');
      expect(AutoMatchPolicy.buildSearchKeyword({ title: '晴天', artist: '' }, '周杰伦'))
        .assertEqual('晴天 周杰伦');
      expect(AutoMatchPolicy.buildSearchKeyword({ title: '晴天', artist: '' }, ''))
        .assertEqual('晴天');
    });

    it('buildMatchUpdateFillsEveryMissingFieldAndStampsSource', 0, () => {
      const base = localSong('01 晴天', '');
      const updated = AutoMatchPolicy.buildMatchUpdate(base, patch((_d: MatchDetailPatch) => {})) as SongItem;
      expect(updated.customName).assertEqual('晴天');
      expect(updated.customArtist).assertEqual('周杰伦');
      expect(updated.customCoverUrl).assertEqual('https://example.com/cover.jpg');
      expect(updated.matchedLyric).assertEqual('[00:00.00]故事的小黄花');
      expect(updated.matchedSongId).assertEqual('netease:186016');
      // The base object is never mutated.
      expect(base.customName).assertEqual('');
      expect(base.matchedLyric).assertEqual('');
    });

    it('buildMatchUpdateNeverOverwritesExistingValues', 0, () => {
      const base = localSong('晴天', '周杰伦');
      base.coverUrl = 'https://example.com/old.jpg';
      const updated = AutoMatchPolicy.buildMatchUpdate(base, patch((_d: MatchDetailPatch) => {})) as SongItem;
      expect(updated.customArtist).assertEqual('');
      expect(updated.customCoverUrl).assertEqual('');
      expect(updated.matchedLyric).assertEqual('[00:00.00]故事的小黄花');
    });

    it('buildMatchUpdateReturnsNullWhenNothingImproves', 0, () => {
      const base = localSong('晴天', '周杰伦');
      expect(AutoMatchPolicy.buildMatchUpdate(base, patch((p: MatchDetailPatch) => { p.lyric = ''; p.coverUrl = ''; }))).assertNull();
      // A lyric identical to the one already matched adds nothing.
      base.matchedLyric = '[00:00.00]故事的小黄花';
      expect(AutoMatchPolicy.buildMatchUpdate(base, patch((p: MatchDetailPatch) => { p.coverUrl = ''; }))).assertNull();
    });

    it('buildMatchUpdateNameOnlyDoesNotStampMatchedSongId', 0, () => {
      const base = localSong('01 晴天', '周杰伦');
      const updated = AutoMatchPolicy.buildMatchUpdate(base, patch((p: MatchDetailPatch) => { p.lyric = ''; p.coverUrl = ''; })) as SongItem;
      expect(updated.customName).assertEqual('晴天');
      expect(updated.matchedSongId).assertEqual('');
    });
  });
}
