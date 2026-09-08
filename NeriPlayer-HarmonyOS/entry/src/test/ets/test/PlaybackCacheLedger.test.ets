import { describe, it, expect } from '@ohos/hypium';
import { PlaybackCacheLedger } from '../../../main/ets/player/PlaybackCacheLedger';

export default function playbackCacheLedgerTest(): void {
  describe('PlaybackCacheLedger', () => {
    it('lookupMissReturnsNullAndRecordHits', 0, () => {
      const ledger = new PlaybackCacheLedger();
      expect(ledger.lookup('k1', 100)).assertNull();
      expect(ledger.record('k1', 't1', '/cache/a', 100, 4)).assertEqual(0);
      const hit = ledger.lookup('k1', 500);
      expect(hit === null).assertFalse();
      expect(hit!.cacheDir).assertEqual('/cache/a');
      expect(hit!.lastPlayedAt).assertEqual(500);
      expect(ledger.size()).assertEqual(1);
    });

    it('evictsLeastRecentlyUsedBeyondCap', 0, () => {
      const ledger = new PlaybackCacheLedger();
      ledger.record('a', 'ta', '/cache/a', 100, 3);
      ledger.record('b', 'tb', '/cache/b', 200, 3);
      ledger.record('c', 'tc', '/cache/c', 300, 3);
      // Touch 'a' so 'b' becomes the stalest.
      ledger.lookup('a', 1000);
      const evicted = ledger.record('d', 'td', '/cache/d', 1100, 3);
      expect(evicted.length).assertEqual(1);
      expect(evicted[0]).assertEqual('b');
      expect(ledger.find('b')).assertNull();
      // 'a' was touched at 1000 and 'c' recorded at 300 — both survive.
      expect(ledger.find('a') === null).assertFalse();
      expect(ledger.find('c') === null).assertFalse();
      expect(ledger.size()).assertEqual(3);
    });

    it('recordRefreshKeepsEntryWithoutEviction', 0, () => {
      const ledger = new PlaybackCacheLedger();
      ledger.record('a', 'ta', '/cache/a', 100, 2);
      ledger.record('b', 'tb', '/cache/b', 200, 2);
      expect(ledger.record('a', 'ta2', '/cache/a2', 900, 2).length).assertEqual(0);
      expect(ledger.size()).assertEqual(2);
      const refreshed = ledger.find('a');
      expect(refreshed === null).assertFalse();
      expect(refreshed!.taskId).assertEqual('ta2');
      expect(refreshed!.cacheDir).assertEqual('/cache/a2');
    });

    it('removeDropsEntryAndReports', 0, () => {
      const ledger = new PlaybackCacheLedger();
      ledger.record('a', 'ta', '/cache/a', 100, 4);
      expect(ledger.remove('missing')).assertFalse();
      expect(ledger.remove('a')).assertTrue();
      expect(ledger.size()).assertEqual(0);
    });

    it('jsonRoundTripKeepsLruClock', 0, () => {
      const ledger = new PlaybackCacheLedger();
      ledger.record('a', 'ta', '/cache/a', 100, 4);
      ledger.record('b', 'tb', '/cache/b', 200, 4);
      ledger.lookup('a', 800);
      const restored = PlaybackCacheLedger.fromJson(ledger.toJson());
      expect(restored === null).assertFalse();
      const a = restored!.find('a');
      expect(a === null).assertFalse();
      expect(a!.lastPlayedAt).assertEqual(800);
      expect(restored!.find('b') === null).assertFalse();
      expect(restored!.size()).assertEqual(2);
    });

    it('fromJsonDegradesOnCorruptInput', 0, () => {
      expect(PlaybackCacheLedger.fromJson('not json')).assertNull();
      const empty = PlaybackCacheLedger.fromJson('{}');
      expect(empty === null).assertFalse();
      expect(empty!.size()).assertEqual(0);
      // Entries without a stable key are skipped instead of crashing the load.
      const partial = PlaybackCacheLedger.fromJson(
        '{"entries":[{"stableKey":"","taskId":"t"},{"stableKey":"k","taskId":"t2","cacheDir":"/d","createdAt":5}]}'
      );
      expect(partial === null).assertFalse();
      expect(partial!.size()).assertEqual(1);
      expect(partial!.find('k') === null).assertFalse();
    });
  });
}
