import abilityTest from './Ability.test';
import playbackStateRestoreTest from './PlaybackStateRestore.test';
import playbackSmokeTest from './PlaybackSmoke.test';
import schemaRecoveryTest from './SchemaRecovery.test';

export default function testsuite(): void {
  abilityTest();
  playbackStateRestoreTest();
  playbackSmokeTest();
  schemaRecoveryTest();
}
