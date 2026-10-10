// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import {
  LyricCacheStore,
  LyricSourceTag,
  parseLyricSourceTag,
  DEFAULT_LYRIC_CACHE_ENTRIES
} from '../../../main/ets/lyrics/LyricCacheStore';
import { LyricLine } from '../../../main/ets/model/LyricLine';

function line(timeMs: number, text: string, translated: string = '', phonetic: string = ''): LyricLine {
  const l = new LyricLine(timeMs, text, translated, phonetic);
  l.endTimeMs = timeMs + 3000;
  return l;
}

export default function lyricCacheStoreTest(): void {
  describe('LyricCacheStore', () => {
    it('recordAndLookupRoundTrip', 0, () => {
      const store = new LyricCacheStore();
      expect(store.lookup('k1', 100)).assertNull();
      const lines = [line(0, '第一句'), line(4000, 'second', '翻译', 'romaji')];
      expect(store.record('k1', LyricSourceTag.LRCLIB, lines, 200, 10)).assertTrue();
      const hit = store.lookup('k1', 300);
      expect(hit !== null).assertTrue();
      expect(hit!.source).assertEqual(LyricSourceTag.LRCLIB);
      expect(hit!.lines.length).assertEqual(2);
      expect(hit!.lines[1].timeMs).assertEqual(4000);
      expect(hit!.lines[1].text).assertEqual('second');
      expect(hit!.lines[1].translated).assertEqual('翻译');
      expect(hit!.lines[1].phonetic).assertEqual('romaji');
      expect(hit!.lines[1].endTimeMs).assertEqual(7000);
      expect(hit!.lastUsedAt).assertEqual(300);
    });

    it('lookupRefreshesLruClockForEviction', 0, () => {
      const store = new LyricCacheStore();
      store.record('old', LyricSourceTag.LRCLIB, [line(0, 'a')], 100, 3);
      store.record('mid', LyricSourceTag.NETEASE, [line(0, 'b')], 200, 3);
      store.record('new', LyricSourceTag.LRCLIB, [line(0, 'c')], 300, 3);
      // Touch 'old' so 'mid' becomes the least recently used.
      store.lookup('old', 400);
      store.record('fresh', LyricSourceTag.LRCLIB, [line(0, 'd')], 500, 3);
      expect(store.find('mid')).assertNull();
      expect(store.find('old') !== null).assertTrue();
      expect(store.size()).assertEqual(3);
    });

    it('recordUpdatesExistingEntryWithoutEviction', 0, () => {
      const store = new LyricCacheStore();
      store.record('k', LyricSourceTag.LRCLIB, [line(0, 'a')], 100, 2);
      store.record('k', LyricSourceTag.NETEASE, [line(0, 'b'), line(1, 'c')], 200, 2);
      const hit = store.lookup('k', 300)!;
      expect(hit.source).assertEqual(LyricSourceTag.NETEASE);
      expect(hit.lines.length).assertEqual(2);
      expect(store.size()).assertEqual(1);
    });

    it('emptyLinesAndEmptyKeyAreNeverCached', 0, () => {
      const store = new LyricCacheStore();
      expect(store.record('k', LyricSourceTag.LRCLIB, [], 100, 10)).assertFalse();
      expect(store.record('', LyricSourceTag.LRCLIB, [line(0, 'a')], 100, 10)).assertFalse();
      expect(store.size()).assertEqual(0);
    });

    it('removeAndClear', 0, () => {
      const store = new LyricCacheStore();
      store.record('a', LyricSourceTag.LRCLIB, [line(0, 'a')], 100, 10);
      store.record('b', LyricSourceTag.LRCLIB, [line(0, 'b')], 100, 10);
      expect(store.remove('a')).assertTrue();
      expect(store.remove('a')).assertFalse();
      expect(store.size()).assertEqual(1);
      store.clear();
      expect(store.size()).assertEqual(0);
    });

    it('jsonRoundTripKeepsEntriesSourceAndLines', 0, () => {
      const store = new LyricCacheStore();
      store.record('k1', LyricSourceTag.NETEASE, [line(1000, '你好', 'hello', 'ni hao')], 123, 10);
      store.record('k2', LyricSourceTag.LRCLIB, [line(0, 'x'), line(50, '')], 456, 10);
      const revived = LyricCacheStore.fromJson(store.toJson())!;
      expect(revived.size()).assertEqual(2);
      const hit1 = revived.lookup('k1', 999)!;
      expect(hit1.source).assertEqual(LyricSourceTag.NETEASE);
      expect(hit1.lines.length).assertEqual(1);
      expect(hit1.lines[0].text).assertEqual('你好');
      expect(hit1.lines[0].translated).assertEqual('hello');
      expect(hit1.lines[0].phonetic).assertEqual('ni hao');
      // 空文本行（时间轴占位）在解析时被丢弃，不产生脏条目。
      const hit2 = revived.lookup('k2', 999)!;
      expect(hit2.lines.length).assertEqual(1);
      expect(revived.toJson().length > 0).assertTrue();
    });

    it('fromJsonToleratesGarbage', 0, () => {
      expect(LyricCacheStore.fromJson('not json')).assertNull();
      const empty = LyricCacheStore.fromJson('{}')!;
      expect(empty.size()).assertEqual(0);
      // 无 key / 空行的条目直接跳过，不炸整个表。
      const revived = LyricCacheStore.fromJson(
        '{"entries":[{}, {"k":"x","l":[]}, {"k":"y","s":"netease","l":[[100,"hi"]],"u":5}]}'
      )!;
      expect(revived.size()).assertEqual(1);
      const hit = revived.lookup('y', 9)!;
      expect(hit.source).assertEqual(LyricSourceTag.NETEASE);
      expect(hit.lines.length).assertEqual(1);
    });

    it('parseLyricSourceTagFallsBackToLrclib', 0, () => {
      expect(parseLyricSourceTag('matched')).assertEqual(LyricSourceTag.MATCHED);
      expect(parseLyricSourceTag('netease')).assertEqual(LyricSourceTag.NETEASE);
      expect(parseLyricSourceTag('lrclib')).assertEqual(LyricSourceTag.LRCLIB);
      expect(parseLyricSourceTag('whatever')).assertEqual(LyricSourceTag.LRCLIB);
    });

    it('defaultCapacityIsBounded', 0, () => {
      expect(DEFAULT_LYRIC_CACHE_ENTRIES).assertEqual(200);
    });
  });
}
