import { describe, it, expect } from '@ohos/hypium';
import { HistoryRepository } from '../../../main/ets/data/HistoryRepository';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';

function song(id: number, name: string): SongItem {
  return new SongItem(id, name, 'Artist', 'Album', 0, 200000, '', `netease://${id}`);
}

export default function historyRepositoryTest(): void {
  describe('HistoryRepository', () => {
    it('exportImportRoundTripsThroughJson', 0, () => {
      const songs = [song(1, 'A'), song(2, 'B')];
      const json = HistoryRepository.serializeExport(songs, 1700000000000);
      const parsed = HistoryRepository.parseImportJson(json);
      expect(parsed !== null).assertTrue();
      expect(parsed!.length).assertEqual(2);
      expect(parsed![0].name).assertEqual('A');
      expect(parsed![1].displayName).assertEqual('B');
    });

    it('parseAcceptsLegacyBareArray', 0, () => {
      const songs = [song(1, 'A')];
      const json = JSON.stringify(songs.map((item: SongItem) => item.toJson()));
      const parsed = HistoryRepository.parseImportJson(json);
      expect(parsed !== null).assertTrue();
      expect(parsed!.length).assertEqual(1);
      expect(parsed![0].name).assertEqual('A');
    });

    it('parseRejectsCorruptedPayload', 0, () => {
      expect(HistoryRepository.parseImportJson('not json')).assertNull();
      expect(HistoryRepository.parseImportJson('{"version": 1}')).assertNull();
    });

    it('parseSkipsBrokenEntriesButKeepsValidOnes', 0, () => {
      const payload = '{"version":1,"songs":[{"id":1,"name":"A"},null,{"id":2,"name":"B"}]}';
      const parsed = HistoryRepository.parseImportJson(payload);
      expect(parsed !== null).assertTrue();
      expect(parsed!.length).assertEqual(2);
    });

    it('importedSongsWinAndDedupeByStableKey', 0, () => {
      const existing = [song(1, 'Old A'), song(2, 'B')];
      const imported = [song(1, 'New A'), song(3, 'C')];
      const merged = HistoryRepository.mergeForImport(existing, imported);
      expect(merged.length).assertEqual(3);
      expect(merged[0].name).assertEqual('New A');
      expect(merged[1].name).assertEqual('C');
      expect(merged[2].name).assertEqual('B');
    });

    it('mergeCapsAtHistoryLimit', 0, () => {
      expect(HistoryRepository.LIMIT).assertEqual(1000);
      const existing: SongItem[] = [];
      for (let i = 0; i < 600; i++) {
        existing.push(song(i, `E${i}`));
      }
      const imported: SongItem[] = [];
      for (let i = 600; i < 1100; i++) {
        imported.push(song(i, `I${i}`));
      }
      const merged = HistoryRepository.mergeForImport(existing, imported);
      expect(merged.length).assertEqual(1000);
      // 导入序优先，被挤出的是 existing 列表尾部（较旧的记录）。
      expect(merged[0].name).assertEqual('I600');
      expect(merged.indexOf(existing[500])).assertEqual(-1);
      expect(stableKeyOf(merged[merged.length - 1])).assertEqual(stableKeyOf(existing[499]));
    });
  });
}
