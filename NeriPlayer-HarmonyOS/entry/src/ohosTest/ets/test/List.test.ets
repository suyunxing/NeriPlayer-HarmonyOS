import abilityTest from './Ability.test';
import playbackStateRestoreTest from './PlaybackStateRestore.test';
import playbackSmokeTest from './PlaybackSmoke.test';
import biliPlaybackSmokeTest from './BiliPlaybackSmoke.test';
import ytmPlaybackSmokeTest from './YtmPlaybackSmoke.test';
import schemaRecoveryTest from './SchemaRecovery.test';
import downloadSmokeTest from './DownloadSmoke.test';
import authDeviceTest from './AuthDevice.test';
import neteaseLibraryTest from './NeteaseLibrary.test';
import githubTransportDeviceTest from './GitHubTransportDevice.test';
import listenTogetherNetworkDeviceTest from './ListenTogetherNetworkDevice.test';
import listenTogetherRoomSmokeDeviceTest from './ListenTogetherRoomSmokeDevice.test';
import listenTogetherReconnectProbeTest from './ListenTogetherReconnectProbe.test';
import syncWebdavDeviceTest from './SyncWebdavDevice.test';
import diagnosticsDeviceTest from './DiagnosticsDevice.test';

export default function testsuite(): void {
  abilityTest();
  playbackStateRestoreTest();
  playbackSmokeTest();
  biliPlaybackSmokeTest();
  ytmPlaybackSmokeTest();
  schemaRecoveryTest();
  downloadSmokeTest();
  authDeviceTest();
  neteaseLibraryTest();
  githubTransportDeviceTest();
  listenTogetherNetworkDeviceTest();
  listenTogetherRoomSmokeDeviceTest();
  listenTogetherReconnectProbeTest();
  syncWebdavDeviceTest();
  diagnosticsDeviceTest();
}
