import { describe, it, expect } from '@ohos/hypium';
import {
  YtmStreamResolver,
  classifyYtmRestriction,
  YtmStreamError
} from '../../../main/ets/network/ytm/YtmStreamResolver';
import { YtmHttpError, YtmPlayerFetcher } from '../../../main/ets/network/ytm/YtmStreamClient';
import {
  YtmClientCatalog,
  YtmClientProfile,
  YTM_IOS_DOWNGRADED_VERSION
} from '../../../main/ets/network/ytm/YtmClientCatalog';
import { YtmQualityTier } from '../../../main/ets/network/ytm/YtmFormatSelector';

const TIER = YtmQualityTier.VERY_HIGH;
const T0 = 1_800_000_000_000;

const OK_DIRECT_RESPONSE =
  '{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"itag":251,' +
  '"mimeType":"audio/webm; codecs=\\"opus\\"","bitrate":140517,"audioSampleRate":"44100",' +
  '"contentLength":"3717234","url":"https://rr.example.com/videoplayback?itag=251&expire=99999999999"}]}}';

const CIPHER_ONLY_RESPONSE =
  '{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"itag":251,' +
  '"mimeType":"audio/webm; codecs=\\"opus\\"","bitrate":140517,' +
  '"signatureCipher":"s=AAA&url=https%3A%2F%2Frr.example.com%2Fvideoplayback"}]}}';

function loginRequiredResponse(reason: string): string {
  return `{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"${reason}"}}`;
}

/** One scripted step: a response text resolves, an YtmHttpError throws. */
class FetchStep {
  readonly responseText: string;
  readonly error: YtmHttpError | null;

  constructor(responseText: string, error: YtmHttpError | null) {
    this.responseText = responseText;
    this.error = error;
  }

  static ok(responseText: string): FetchStep {
    return new FetchStep(responseText, null);
  }

  static fail(error: YtmHttpError): FetchStep {
    return new FetchStep('', error);
  }
}

/** Records every "key@version" invocation and replays the script in order. */
class ScriptedFetcher {
  calls: string[] = [];
  private readonly script: FetchStep[];

  constructor(script: FetchStep[]) {
    this.script = script;
  }

  fetch: YtmPlayerFetcher = (profile: YtmClientProfile, _videoId: string): Promise<string> => {
    this.calls.push(`${profile.key}@${profile.clientVersion}`);
    const step = this.script[this.calls.length - 1];
    if (step.error !== null) {
      return Promise.reject(step.error);
    }
    return Promise.resolve(step.responseText);
  };
}

function httpError(code: number): YtmHttpError {
  return new YtmHttpError(code, `HTTP ${code} for POST https://www.youtube.com/youtubei/v1/player`);
}

async function expectChainError(fetcher: ScriptedFetcher): Promise<YtmStreamError> {
  try {
    await YtmStreamResolver.resolveWithClientChain('v1', TIER, fetcher.fetch, T0);
  } catch (error) {
    return error as YtmStreamError;
  }
  return new YtmStreamError('empty', 'unexpected success');
}

export default function ytmClientChainTest(): void {
  describe('YtmClientChain', () => {
    it('iosOkResolvesWithoutFallbackClient', 0, async () => {
      YtmStreamResolver.resetForTest();
      const fetcher = new ScriptedFetcher([FetchStep.ok(OK_DIRECT_RESPONSE)]);
      const url = await YtmStreamResolver.resolveWithClientChain('v1', TIER, fetcher.fetch, T0);
      expect(url.includes('itag=251')).assertTrue();
      expect(fetcher.calls.length).assertEqual(1);
      expect(fetcher.calls[0]).assertEqual('ios@21.03.2');
    });

    it('iosCipherOnlyFallsThroughToDowngradedThenNeedsDecrypt', 0, async () => {
      YtmStreamResolver.resetForTest();
      const fetcher = new ScriptedFetcher([
        FetchStep.ok(CIPHER_ONLY_RESPONSE),
        FetchStep.ok(CIPHER_ONLY_RESPONSE)
      ]);
      const streamError = await expectChainError(fetcher);
      expect(streamError.kind).assertEqual('needs_decrypt');
      expect(streamError.message.includes('M6.3')).assertTrue();
      expect(fetcher.calls.length).assertEqual(2);
      expect(fetcher.calls[1]).assertEqual('tvhtml5_downgraded@5.20260114');
    });

    it('iosLoginRequiredRecoveredByDowngradedDirect', 0, async () => {
      YtmStreamResolver.resetForTest();
      const fetcher = new ScriptedFetcher([
        FetchStep.ok(loginRequiredResponse('Please sign in')),
        FetchStep.ok(OK_DIRECT_RESPONSE)
      ]);
      const url = await YtmStreamResolver.resolveWithClientChain('v1', TIER, fetcher.fetch, T0);
      expect(url.includes('itag=251')).assertTrue();
      expect(fetcher.calls[1]).assertEqual('tvhtml5_downgraded@5.20260114');
    });

    it('http400OnIosRetriesOnceOnDowngradedVersion', 0, async () => {
      YtmStreamResolver.resetForTest();
      const fetcher = new ScriptedFetcher([
        FetchStep.fail(httpError(400)),
        FetchStep.ok(OK_DIRECT_RESPONSE)
      ]);
      const url = await YtmStreamResolver.resolveWithClientChain('v1', TIER, fetcher.fetch, T0);
      expect(url.includes('itag=251')).assertTrue();
      expect(fetcher.calls.length).assertEqual(2);
      expect(fetcher.calls[0]).assertEqual('ios@21.03.2');
      expect(fetcher.calls[1]).assertEqual(`ios@${YTM_IOS_DOWNGRADED_VERSION}`);
    });

    it('nonRetryableHttpErrorsSuppressIosAfterThreeRounds', 0, async () => {
      YtmStreamResolver.resetForTest();
      // Round = ios 403 + downgraded code-0 network failure.
      const round: FetchStep[] = [FetchStep.fail(httpError(403)), FetchStep.fail(httpError(0))];
      for (let i = 0; i < 3; i++) {
        const fetcher = new ScriptedFetcher(round.slice());
        await expectChainError(fetcher);
      }
      // Fourth round: ios is suppressed, the chain starts at downgraded.
      const probe = new ScriptedFetcher([FetchStep.ok(OK_DIRECT_RESPONSE)]);
      const url = await YtmStreamResolver.resolveWithClientChain('v2', TIER, probe.fetch, T0);
      expect(url.includes('itag=251')).assertTrue();
      expect(probe.calls.length).assertEqual(1);
      expect(probe.calls[0]).assertEqual('tvhtml5_downgraded@5.20260114');
    });

    it('retryable429DoesNotRecordRejection', 0, async () => {
      YtmStreamResolver.resetForTest();
      for (let i = 0; i < 3; i++) {
        const fetcher = new ScriptedFetcher([FetchStep.fail(httpError(429))]);
        await expectChainError(fetcher);
      }
      const probe = new ScriptedFetcher([FetchStep.ok(OK_DIRECT_RESPONSE)]);
      const url = await YtmStreamResolver.resolveWithClientChain('v2', TIER, probe.fetch, T0);
      expect(url.includes('itag=251')).assertTrue();
      // 429 is retryable: ios never got suppressed, still leads the chain.
      expect(probe.calls[0]).assertEqual('ios@21.03.2');
    });

    it('aggregateErrorCarriesEveryClientAttempt', 0, async () => {
      YtmStreamResolver.resetForTest();
      const fetcher = new ScriptedFetcher([
        FetchStep.ok(loginRequiredResponse('This video is private')),
        FetchStep.ok(loginRequiredResponse('This video is private'))
      ]);
      const streamError = await expectChainError(fetcher);
      expect(streamError.kind).assertEqual('login_required');
      expect(streamError.message.includes('ios@21.03.2')).assertTrue();
      expect(streamError.message.includes('tvhtml5_downgraded@5.20260114')).assertTrue();
      expect(streamError.message.includes('private video')).assertTrue();
    });

    it('classifiesRestrictionShapes', 0, () => {
      expect(classifyYtmRestriction('LOGIN_REQUIRED', 'Sorry, this content is age-restricted'))
        .assertEqual('age-restricted content requires sign-in');
      expect(classifyYtmRestriction('UNPLAYABLE', 'This video is unavailable in your country'))
        .assertEqual('content unavailable in this region');
      expect(classifyYtmRestriction('LOGIN_REQUIRED', 'Sign in to confirm you are not a bot'))
        .assertEqual('bot verification wall (client rotation may help)');
      expect(classifyYtmRestriction('LOGIN_REQUIRED', 'This video is private'))
        .assertEqual('private video');
      expect(classifyYtmRestriction('UNPLAYABLE', 'Embedded playback disabled'))
        .assertEqual('embedded playback disabled');
      expect(classifyYtmRestriction('UNPLAYABLE', 'Something else')).assertEqual('');
    });

    it('withVersionClonesProfileAndUaVersion', 0, () => {
      const ios = YtmClientCatalog.IOS;
      const older = ios.withVersion(YTM_IOS_DOWNGRADED_VERSION);
      expect(older.clientVersion).assertEqual(YTM_IOS_DOWNGRADED_VERSION);
      expect(older.userAgent.includes(`/${YTM_IOS_DOWNGRADED_VERSION}(`)).assertTrue();
      expect(older.key).assertEqual(ios.key);
      // Canonical profile untouched.
      expect(ios.clientVersion).assertEqual('21.03.2');
      // TV profile without an embedded version keeps its UA unchanged.
      const tv = YtmClientCatalog.TVHTML5_DOWNGRADED.withVersion('4.20240101');
      expect(tv.userAgent).assertEqual(YtmClientCatalog.TVHTML5_DOWNGRADED.userAgent);
      expect(tv.platform).assertEqual('TV');
    });
  });
}
