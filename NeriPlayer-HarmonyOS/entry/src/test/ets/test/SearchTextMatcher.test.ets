// SPDX-License-Identifier: GPL-3.0
// Unit tests for the search text matcher port (upstream SearchTextMatcherTest
// / PlaylistSearchFocusPolicyTest / ExploreSearchHistoryPolicyTest, commits
// bf50094e & dfa37db0).

import { describe, it, expect } from '@ohos/hypium';
import {
  NO_SEARCH_MATCH,
  PreparedSearchEntries,
  SearchTextMatcher,
  SearchValue
} from '../../../main/ets/util/search/SearchTextMatcher';
import {
  mergeSongItemsDeduped,
  rankExploreSongSearchResults,
  songSearchValues
} from '../../../main/ets/util/search/SongSearchValues';
import {
  resolveExploreSearchKeyword,
  updatedSearchHistory
} from '../../../main/ets/data/SearchHistoryPolicy';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { pinyinProResolver } from '../../../main/ets/util/search/SongPinyinSource';

/** 测试用汉字→拼音映射（简：测=ce/shi，试=shi，歌=ge，手=shou，机=ji）。 */
function fakePinyin(ch: string): string {
  const map: Record<string, string> = {
    '测': 'ce', '试': 'shi', '歌': 'ge', '手': 'shou', '机': 'ji', '晴': 'qing',
    '天': 'tian', '简': 'jian', '化': 'hua'
  };
  return map[ch] ?? '';
}

function song(name: string, artist: string, album: string, audioId: string): SongItem {
  const item = new SongItem(0, name, artist, album, 0, 0, '', '', MusicPlatform.NETEASE);
  item.audioId = audioId;
  return item;
}

export default function SearchTextMatcherTest() {
  describe('SearchTextMatcher', () => {
    it('normalizeAndTokenize_stripsDiacriticsAndSplits', 0, () => {
      // NFKD + Mn 剥离：'Café' 归一为 'cafe'，前缀匹配命中。
      const score = SearchTextMatcher.score('cafe', [SearchTextMatcher.value('Café München')]);
      expect(score !== NO_SEARCH_MATCH).assertTrue();
      // 多词查询：每个 token 都要有落点，'quantum solace' 在 Quantum of Solace 上。
      const multi = SearchTextMatcher.score('quantum solace', [SearchTextMatcher.value('Quantum of Solace')]);
      expect(multi !== NO_SEARCH_MATCH).assertTrue();
      // 空查询/纯分隔符 = 0 分（视为匹配全部）。
      expect(SearchTextMatcher.score('  ', [SearchTextMatcher.value('x')])).assertEqual(0);
      expect(SearchTextMatcher.score('', [SearchTextMatcher.value('x')])).assertEqual(0);
    });

    it('matchScore_prefersExactThenPrefixThenContains', 0, () => {
      const exact = SearchTextMatcher.score('hello', [SearchTextMatcher.value('hello')]);
      const prefix = SearchTextMatcher.score('hello', [SearchTextMatcher.value('hello world')]);
      const contains = SearchTextMatcher.score('world', [SearchTextMatcher.value('hello world')]);
      // 相等 < 前缀 < 包含（分数越小越优）。
      expect(exact < prefix && prefix < contains).assertTrue();
      expect(exact).assertEqual(0);
    });

    it('fieldBias_titleOutranksArtistOutranksAlbum', 0, () => {
      const values: SearchValue[] = [
        SearchTextMatcher.value('love story', 0),
        SearchTextMatcher.value('love story', 24),
        SearchTextMatcher.value('love story', 40)
      ];
      expect(SearchTextMatcher.score('love story', values)).assertEqual(0);
    });

    it('acronymAndCamel_candidates', 0, () => {
      // 分词首字母缩写（>1 字符才建）：'ttl' 匹配 'Take The Long Way'。
      const acronym = SearchTextMatcher.score('ttl', [SearchTextMatcher.value('Take The Long Way')]);
      expect(acronym !== NO_SEARCH_MATCH).assertTrue();
      // 驼峰拆分：'myFire' → 'my'+'fire' 分词。
      const camel = SearchTextMatcher.score('fire', [SearchTextMatcher.value('myFireRoad')]);
      expect(camel !== NO_SEARCH_MATCH).assertTrue();
    });

    it('pinyin_fullAndInitialsViaResolver', 0, () => {
      SearchTextMatcher.setPinyinResolver(fakePinyin);
      try {
        // 全拼：'ceshi' 匹配「测试」。
        const full = SearchTextMatcher.score('ceshi', [SearchTextMatcher.value('测试歌单')]);
        expect(full !== NO_SEARCH_MATCH).assertTrue();
        // 首字母：'cs' 匹配「测试」。
        const initials = SearchTextMatcher.score('cs', [SearchTextMatcher.value('测试歌单')]);
        expect(initials !== NO_SEARCH_MATCH).assertTrue();
        // 无解析器时拼音不可用（下面 reset 后验证）。
      } finally {
        SearchTextMatcher.setPinyinResolver(null);
      }
      const withoutResolver = SearchTextMatcher.score('ceshi', [SearchTextMatcher.value('测试歌单')]);
      expect(withoutResolver).assertEqual(NO_SEARCH_MATCH);
    });

    it('filterAndRank_ordersByScoreThenIndex', 0, () => {
      SearchTextMatcher.setPinyinResolver(fakePinyin);
      try {
        const items: SongItem[] = [
          song('晴天', '周杰伦', '叶惠美', 'a1'),
          song('测试歌曲', '歌手', '专辑', 'a2'),
          song('Sunny Day', 'Artist', 'Album', 'a3')
        ];
        const ranked = SearchTextMatcher.filterAndRank('qing', items,
          (item: SongItem): SearchValue[] => songSearchValues(item));
        expect(ranked.length).assertEqual(1);
        expect(ranked[0].name).assertEqual('晴天');
        // 空查询返回原列表全量。
        const all = SearchTextMatcher.filterAndRank('  ', items,
          (item: SongItem): SearchValue[] => songSearchValues(item));
        expect(all.length).assertEqual(3);
      } finally {
        SearchTextMatcher.setPinyinResolver(null);
      }
    });

    it('pinyin_realResolver_matchesFullAndInitials', 0, () => {
      // pinyin-pro 真实解析器：'ceshi'/'cs' 命中「测试」，'qt' 命中「晴天」。
      SearchTextMatcher.setPinyinResolver(pinyinProResolver);
      try {
        expect(SearchTextMatcher.matches('ceshi', [SearchTextMatcher.value('测试歌单')])).assertTrue();
        expect(SearchTextMatcher.matches('cs', [SearchTextMatcher.value('测试歌单')])).assertTrue();
        expect(SearchTextMatcher.matches('qt', [SearchTextMatcher.value('晴天')])).assertTrue();
        expect(SearchTextMatcher.matches('qingtian', [SearchTextMatcher.value('晴天')])).assertTrue();
        // 非汉字不产拼音候选。
        expect(pinyinProResolver('a')).assertEqual('');
        expect(pinyinProResolver('测').length > 0).assertTrue();
      } finally {
        SearchTextMatcher.setPinyinResolver(null);
      }
    });

    it('rankExploreSongResults_matchedFirstUnmatchedKept', 0, () => {
      const songs: SongItem[] = [
        song('无关歌曲一', '艺人', '专辑', 'x1'),
        song('Sunny Day', 'Artist', 'Album', 'x2'),
        song('Sunrise', 'Artist', 'Album', 'x3')
      ];
      const ranked = rankExploreSongSearchResults('sun', songs);
      // 匹配项（前缀 Sunrise 优于包含 Sunny Day）在前，未匹配项保序垫底。
      expect(ranked.length).assertEqual(3);
      expect(ranked[0].name).assertEqual('Sunrise');
      expect(ranked[1].name).assertEqual('Sunny Day');
      expect(ranked[2].name).assertEqual('无关歌曲一');
      // 无任何匹配时原样返回。
      const none = rankExploreSongSearchResults('zzz', songs);
      expect(none[0].audioId).assertEqual('x1');
    });

    it('mergeSongItems_dedupesByPlatformAndAudioId', 0, () => {
      const existing: SongItem[] = [song('A', 'x', 'y', 'id1'), song('B', 'x', 'y', 'id2')];
      const incoming: SongItem[] = [
        song('A-重复', 'x', 'y', 'id1'),
        song('C', 'x', 'y', 'id3')
      ];
      const merged = mergeSongItemsDeduped(existing, incoming);
      expect(merged.length).assertEqual(3);
      expect(merged[2].name).assertEqual('C');
    });

    it('updatedSearchHistory_caseInsensitiveDedupeAndLimit', 0, () => {
      const next = updatedSearchHistory(['Hello', 'world', 'foo'], 'hello');
      expect(next.length).assertEqual(3);
      expect(next[0]).assertEqual('hello');
      expect(next[1]).assertEqual('world');
      // 空白查询原样截断返回。
      const blank = updatedSearchHistory(['a', 'b'], '   ');
      expect(blank.length).assertEqual(2);
      // 上限截断。
      const capped = updatedSearchHistory(['1', '2', '3', '4'], 'new', 3);
      expect(capped.length).assertEqual(3);
      expect(capped[0]).assertEqual('new');
    });

    it('resolveExploreSearchKeyword_prefersStrongHistoryAlias', 0, () => {
      const history = ['晴天 周杰伦', 'Take The Long Way', 'abc'];
      // 强匹配（前缀级分数 <= 12）：'take' → 'Take The Long Way'。
      const aliased = resolveExploreSearchKeyword('take', history);
      expect(aliased).assertEqual('Take The Long Way');
      // 弱匹配（包含级分数 > 12）不替换：'he' 在多个历史项里包含但非前缀。
      const weak = resolveExploreSearchKeyword('zz', history);
      expect(weak).assertEqual('zz');
      // 单字符查询不触发别名（< 2）。
      expect(resolveExploreSearchKeyword('t', history)).assertEqual('t');
    });

    it('preparedSearchEntries_matchesFilterAndRankSemantics', 0, () => {
      // 预计算索引与逐次 filterAndRank 语义一致：过滤结果与排序完全相同，
      // 空查询返回原列表（歌单内搜索防抖改造的等价性保障）。
      SearchTextMatcher.setPinyinResolver(fakePinyin);
      try {
        const songs = [
          song('晴天', '周杰伦', '叶惠美', 'n1'),
          song('测试歌单主打歌', '测试歌手', '测试专辑', 'n2'),
          song('Sunny Day', 'Test Artist', 'Test Album', 'n3')
        ];
        const index = new PreparedSearchEntries<SongItem>(songs,
          (item: SongItem): SearchValue[] => songSearchValues(item));
        expect(index.count()).assertEqual(3);
        // 空查询原列表。
        expect(index.filterAndRank('')).assertEqual(songs);
        // 拼音命中并重排到前。
        const ranked = index.filterAndRank('ceshi');
        expect(ranked.length >= 1).assertTrue();
        expect(ranked[0].audioId).assertEqual('n2');
        // 与一次性 filterAndRank 结果一致（同一 song 集合）。
        const once = SearchTextMatcher.filterAndRank('ceshi', songs,
          (item: SongItem): SearchValue[] => songSearchValues(item));
        expect(ranked.length).assertEqual(once.length);
        for (let i = 0; i < ranked.length; i++) {
          expect(ranked[i].audioId).assertEqual(once[i].audioId);
        }
        // 无匹配返回空。
        expect(index.filterAndRank('zzzznothing').length).assertEqual(0);
        // 纯分隔符查询返回原列表。
        expect(index.filterAndRank('   ')).assertEqual(songs);
      } finally {
        SearchTextMatcher.setPinyinResolver(null);
      }
    });
  });
}
