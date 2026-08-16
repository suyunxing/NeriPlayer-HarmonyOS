import lrcParserTest from './ets/test/LrcParser.test';
import persistedPlaybackStateTest from './ets/test/PersistedPlaybackState.test';
import queueEngineTest from './ets/test/QueueEngine.test';
import audioInterruptPolicyTest from './ets/test/AudioInterruptPolicy.test';
import sleepTimerTest from './ets/test/SleepTimer.test';
import androidDataParserTest from './ets/test/AndroidDataParser.test';
import downloadTaskStoreTest from './ets/test/DownloadTaskStore.test';
import qrEncoderTest from './ets/test/QrEncoder.test';
import neteaseAuthTest from './ets/test/NeteaseAuth.test';

export default function testsuite(): void {
  lrcParserTest();
  persistedPlaybackStateTest();
  queueEngineTest();
  audioInterruptPolicyTest();
  sleepTimerTest();
  androidDataParserTest();
  downloadTaskStoreTest();
  qrEncoderTest();
  neteaseAuthTest();
}
