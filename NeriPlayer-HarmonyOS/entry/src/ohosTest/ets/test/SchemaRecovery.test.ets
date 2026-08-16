import { describe, it, expect } from '@ohos/hypium';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { SchemaStore } from '../../../main/ets/data/schema/SchemaStore';

function parseStringList(json: string): string[] | null {
  const parsed = JSON.parse(json) as Object[];
  if (!Array.isArray(parsed)) {
    return null;
  }
  return parsed.map((item: Object) => String(item));
}

export default function schemaRecoveryTest(): void {
  describe('ActsSchemaRecoveryTest', () => {
    const key = 'schema_recovery_probe';

    it('recoversFromBackupWhenPrimaryCorrupt', 0, async () => {
      await AppPreferences.putString(key, 'corrupted {');
      await AppPreferences.putString(key + '.bak', '["a","b"]');

      const loaded = await SchemaStore.load<string[]>(key, [] as string[], parseStringList);
      expect(loaded.length).assertEqual(2);
      expect(loaded[0]).assertEqual('a');
      // The recovered payload is written back to the primary key.
      const primary = await AppPreferences.getString(key, '');
      expect(primary).assertEqual('["a","b"]');
      await AppPreferences.putString(key, '');
      await AppPreferences.putString(key + '.bak', '');
    });

    it('fallsBackToDefaultWhenBothCorrupt', 0, async () => {
      await AppPreferences.putString(key, '{bad');
      await AppPreferences.putString(key + '.bak', 'also bad');

      const loaded = await SchemaStore.load<string[]>(key, ['default'] as string[], parseStringList);
      expect(loaded.length).assertEqual(1);
      expect(loaded[0]).assertEqual('default');
      await AppPreferences.putString(key, '');
      await AppPreferences.putString(key + '.bak', '');
    });

    it('saveRotatesPreviousValueIntoBackup', 0, async () => {
      await AppPreferences.putString(key, '');
      await AppPreferences.putString(key + '.bak', '');
      await SchemaStore.save(key, '["v1"]' as string, (value: string) => value);
      await SchemaStore.save(key, '["v2"]' as string, (value: string) => value);

      const primary = await AppPreferences.getString(key, '');
      const backup = await AppPreferences.getString(key + '.bak', '');
      expect(primary).assertEqual('["v2"]');
      expect(backup).assertEqual('["v1"]');
      await AppPreferences.putString(key, '');
      await AppPreferences.putString(key + '.bak', '');
    });
  });
}
