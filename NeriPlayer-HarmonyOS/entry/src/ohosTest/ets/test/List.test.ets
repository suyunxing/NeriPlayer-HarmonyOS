import abilityTest from './Ability.test';
import playbackStateRestoreTest from './PlaybackStateRestore.test';
import playbackSmokeTest from './PlaybackSmoke.test';
import schemaRecoveryTest from './SchemaRecovery.test';
import downloadSmokeTest from './DownloadSmoke.test';
import authDeviceTest from './AuthDevice.test';
import neteaseLibraryTest from './NeteaseLibrary.test';

export default function testsuite(): void {
  abilityTest();
  playbackStateRestoreTest();
  playbackSmokeTest();
  schemaRecoveryTest();
  downloadSmokeTest();
  authDeviceTest();
  neteaseLibraryTest();
}
