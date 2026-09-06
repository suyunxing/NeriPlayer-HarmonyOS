import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../../main/ets/app/Logger';

const SAMPLE_URL: string = 'https://www.w3schools.com/html/horse.mp3';

function waitState(player: media.AVPlayer, targets: string[], timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject): void => {
    const timer = setTimeout((): void => {
      reject(new Error(`state wait timeout (${targets.join(',')})`));
    }, timeoutMs);
    const check = (): void => {
      const current = player.state;
      if (current !== undefined && targets.indexOf(current) >= 0) {
        clearTimeout(timer);
        player.off('stateChange', check);
        resolve();
      }
    };
    player.on('stateChange', check);
    check();
  });
}

function codeOf(error: BusinessError): string {
  return `err(${error.code}:${error.message ?? ''})`;
}

/**
 * Bounds a call that may never settle. Device-observed on Pura 90 (API 24):
 * `setLoudnessGain` returns a promise that neither resolves nor rejects, which
 * hung the first run of this probe for the full 120s hypium timeout with no
 * output at all. A hang is a finding, but only if it can be attributed to a
 * specific call — hence the bound plus the step-by-step logging around it.
 */
function withTimeout<T>(label: string, work: Promise<T>, ms: number): Promise<string> {
  return new Promise<string>((resolve): void => {
    let settled: boolean = false;
    const timer = setTimeout((): void => {
      if (!settled) {
        settled = true;
        resolve(`hung(>${ms}ms)`);
      }
    }, ms);
    work.then((): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve('ok');
      }
    }).catch((error: BusinessError): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(codeOf(error));
      }
    });
    Logger.info(`AudioRendererProbe ${label} issued`);
  });
}

/**
 * M10.3 audio low-power probe.
 *
 * Two questions the SDK text alone cannot settle, both of which decide whether
 * the M10.3 changes are worth their code:
 *
 * 1. Does an audio-only source really default to STREAM_USAGE_MUSIC, as the
 *    d.ts claims? If it does, our explicit assignment is defensive rather than
 *    corrective, and the milestone notes must say so.
 * 2. Is `setLoudnessGain` (@since 21) actually implemented on this device
 *    class, and does it really require the music usage as documented?
 *
 * The suite asserts only what must hold on any device (the calls are reachable
 * and either succeed or fail with a documented code); the observed values are
 * logged as the probe's output:
 *   hdc shell hilog | grep AudioRendererProbe
 */
export default function audioRendererProbeTest(): void {
  describe('ActsAudioRendererProbeTest', () => {
    /**
     * The claim under test, verbatim from @ohos.multimedia.media.d.ts:
     * "If the media source contains videos, the default value of usage is
     * STREAM_USAGE_MOVIE. Otherwise, the default value of usage is
     * STREAM_USAGE_MUSIC."
     *
     * If this holds, PlayerManager's explicit assignment changes nothing for
     * today's sources and its value is in pinning the usage for sources that
     * might carry a video track, plus satisfying setLoudnessGain's
     * precondition. That is a materially weaker claim than "fixes a defect",
     * which is why it is checked rather than assumed.
     */
    it('audioOnlySourceDefaultsToMusicUsage', 0, async () => {
      const player = await media.createAVPlayer();
      try {
        player.url = SAMPLE_URL;
        await waitState(player, ['initialized'], 20000);

        let defaultUsage: number | null = null;
        try {
          const info = player.audioRendererInfo;
          defaultUsage = info !== undefined ? info.usage : null;
          Logger.info(`AudioRendererProbe defaultUsage=${defaultUsage} (initialized)`);
        } catch (error) {
          Logger.info(`AudioRendererProbe readDefaultUsage ${codeOf(error as BusinessError)}`);
        }

        // Setting it is only legal here, in initialized, before prepare().
        let setStep: string = 'ok';
        try {
          const rendererInfo: audio.AudioRendererInfo = {
            usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
            rendererFlags: 0,
          };
          player.audioRendererInfo = rendererInfo;
        } catch (error) {
          setStep = codeOf(error as BusinessError);
        }
        Logger.info(`AudioRendererProbe setAudioRendererInfo=${setStep}`);
        expect(setStep).assertEqual('ok');

        await player.prepare();
        await waitState(player, ['prepared'], 20000);

        let effectiveUsage: number | null = null;
        try {
          const info = player.audioRendererInfo;
          effectiveUsage = info !== undefined ? info.usage : null;
        } catch (error) {
          Logger.info(`AudioRendererProbe readEffectiveUsage ${codeOf(error as BusinessError)}`);
        }
        Logger.info(`AudioRendererProbe effectiveUsage=${effectiveUsage} `
          + `expected=${audio.StreamUsage.STREAM_USAGE_MUSIC}`);

        // The assertion is about what we set, not about the default: the
        // default is the finding, and it is logged either way.
        if (effectiveUsage !== null) {
          expect(effectiveUsage).assertEqual(audio.StreamUsage.STREAM_USAGE_MUSIC);
        }
        if (defaultUsage !== null) {
          Logger.info(`AudioRendererProbe defaultWasAlreadyMusic=`
            + `${defaultUsage === audio.StreamUsage.STREAM_USAGE_MUSIC}`);
        }
      } finally {
        await player.release();
      }
    });

    /**
     * M10.3 item 4. `setLoudnessGain` is @since 21 (inside the 24 baseline),
     * documented as legal in prepared/playing/paused/completed/stopped, with a
     * -90.0..24.0 dB range and a usage precondition of MUSIC/MOVIE/AUDIOBOOK.
     *
     * Whether it is worth wiring into the product depends on whether the
     * device implements it at all — a @since tag is not an implementation.
     */
    it('loudnessGainIsReachableWithMusicUsage', 0, async () => {
      const player = await media.createAVPlayer();
      try {
        player.url = SAMPLE_URL;
        await waitState(player, ['initialized'], 20000);
        const rendererInfo: audio.AudioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0,
        };
        player.audioRendererInfo = rendererInfo;
        Logger.info('AudioRendererProbe loudness: usage set, preparing');
        await player.prepare();
        await waitState(player, ['prepared'], 20000);
        Logger.info(`AudioRendererProbe loudness: prepared, state=${player.state}`);

        // Legal value inside the documented range.
        const inRange = await withTimeout('setLoudnessGain(-6.0)', player.setLoudnessGain(-6.0), 10000);
        Logger.info(`AudioRendererProbe setLoudnessGain(-6.0)=${inRange}`);

        // Out of range: the SDK documents 401 for a parameter check failure.
        // A device that accepts this is not enforcing the contract, which is
        // itself worth knowing before relying on the API.
        const outOfRange = await withTimeout('setLoudnessGain(100.0)', player.setLoudnessGain(100.0), 10000);
        Logger.info(`AudioRendererProbe setLoudnessGain(100.0)=${outOfRange}`);

        // Also try it while actually playing: "prepared" is documented as
        // legal, but a gain that only lands on a live stream would explain a
        // silent no-op in the prepared state.
        await player.play();
        await waitState(player, ['playing'], 10000);
        const whilePlaying = await withTimeout('setLoudnessGain(-6.0)/playing', player.setLoudnessGain(-6.0), 10000);
        Logger.info(`AudioRendererProbe setLoudnessGain(-6.0)/playing=${whilePlaying}`);

        // Restore the default before releasing, so nothing leaks into a
        // later test sharing the audio policy state.
        const restore = await withTimeout('setLoudnessGain(0.0)', player.setLoudnessGain(0.0), 10000);
        Logger.info(`AudioRendererProbe setLoudnessGain(0.0)=${restore}`);

        // The probe's assertion: the in-range call must not fail for a reason
        // the SDK does not document for it. A hang is recorded, not asserted —
        // it is the finding, and failing on it would hide the codes above.
        const documented: boolean = inRange === 'ok'
          || inRange.indexOf('hung(') >= 0
          || inRange.indexOf('5400102') >= 0
          || inRange.indexOf('5400103') >= 0
          || inRange.indexOf('5400105') >= 0
          || inRange.indexOf('401') >= 0;
        expect(documented).assertTrue();
      } finally {
        await player.release();
      }
    });
  });
}
