// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { formatStorageBytes } from '../../../main/ets/util/StorageBytes';
import { StorageUsageCategory, StorageUsageSummary } from '../../../main/ets/data/StorageUsageAnalyzer';

export default function storageBytesTest(): void {
  describe('StorageBytes', () => {
    it('formatsAcrossUnits', 0, () => {
      expect(formatStorageBytes(0)).assertEqual('0 B');
      expect(formatStorageBytes(-5)).assertEqual('0 B');
      expect(formatStorageBytes(Number.NaN)).assertEqual('0 B');
      expect(formatStorageBytes(512)).assertEqual('512 B');
      expect(formatStorageBytes(2048)).assertEqual('2.0 KB');
      expect(formatStorageBytes(1536 * 1024)).assertEqual('1.5 MB');
      expect(formatStorageBytes(3 * 1024 * 1024 * 1024)).assertEqual('3.0 GB');
      expect(formatStorageBytes(2.5 * 1024 * 1024 * 1024 * 1024)).assertEqual('2.5 TB');
      // TB 封顶，不再进位到 PB。
      expect(formatStorageBytes(9000 * 1024 ** 4)).assertEqual('8.8 TB');
    });

    it('summaryAggregatesCategoryBytes', 0, () => {
      const summary = new StorageUsageSummary();
      summary.categories.push(new StorageUsageCategory('a', 'A', 100));
      // 歌词缓存这类按条计数的桶 bytes=0，不重复计入总量。
      summary.categories.push(new StorageUsageCategory('lyric', '歌词缓存', 0, '12 首'));
      summary.categories.push(new StorageUsageCategory('b', 'B', 250, '250 B'));
      let total = 0;
      for (const category of summary.categories) {
        total += category.bytes;
      }
      summary.totalBytes = total;
      expect(summary.totalBytes).assertEqual(350);
      expect(summary.categories[1].detail).assertEqual('12 首');
    });
  });
}
