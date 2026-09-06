import { describe, it, expect } from '@ohos/hypium';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Logger } from '../../../main/ets/app/Logger';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve): void => {
    setTimeout(resolve, ms);
  });
}

/**
 * How long the probe holds the lyric window open before destroying the
 * session. Long enough that an operator can grab a screenshot concurrently
 * (`hdc shell snapshot_display`) while the window is still up — the API
 * returning `ok` says nothing about whether anything was actually rendered,
 * and that question can only be answered by looking at the screen.
 */
const OBSERVE_MS: number = 6000;

/** Error code -> meaning, per @ohos.multimedia.avsession.d.ts. */
const ERR_SERVICE_EXCEPTION: number = 6600101;
const ERR_SESSION_NOT_EXIST: number = 6600102;
const ERR_NOT_ENABLED: number = 6600110;
const ERR_NOT_SUPPORTED: number = 6600111;

/**
 * Outcome of one desktop-lyric call: either it resolved, or it threw a
 * BusinessError whose code we keep verbatim. Both are results for a spike —
 * the point is to record what this device class actually does.
 */
interface ProbeStep {
  name: string;
  ok: boolean;
  code: number;
  message: string;
}

function stepOk(name: string): ProbeStep {
  return { name, ok: true, code: 0, message: '' };
}

function stepFailed(name: string, error: BusinessError): ProbeStep {
  return { name, ok: false, code: error.code, message: error.message ?? '' };
}

function describeStep(step: ProbeStep): string {
  return step.ok ? `${step.name}=ok` : `${step.name}=err(${step.code}:${step.message})`;
}

/**
 * M10.2 desktop-lyric spike probe.
 *
 * All of `isDesktopLyricSupported` / `enableDesktopLyric` /
 * `setDesktopLyricVisible` / `isDesktopLyricVisible` /
 * `onDesktopLyricVisibilityChanged` are `@since 23` with no `@permission` and
 * no `@systemapi`, so on the 6.1.1(24) baseline an ordinary app may call them.
 * Whether the *device* implements the feature is a separate question, which is
 * exactly what `isDesktopLyricSupported()` (and error 6600111) answers.
 *
 * This suite therefore asserts only what holds on every device class:
 * the API surface is reachable and each call either succeeds or fails with a
 * documented code. The actual returned values are logged, not asserted — they
 * are the spike's output. Read them with:
 *   hdc shell hilog | grep DesktopLyricProbe
 */
export default function desktopLyricProbeTest(): void {
  describe('ActsDesktopLyricProbeTest', () => {
    it('desktopLyricSupportQueryIsReachable', 0, async () => {
      // Top-level namespace function: needs no session instance, so this runs
      // even if session creation is unavailable.
      let supported: boolean | null = null;
      let failure: ProbeStep | null = null;
      try {
        supported = await avSession.isDesktopLyricSupported();
      } catch (error) {
        failure = stepFailed('isDesktopLyricSupported', error as BusinessError);
      }

      if (failure !== null) {
        Logger.info(`DesktopLyricProbe ${describeStep(failure)}`);
        // 6600101 (service exception) is the only code the SDK documents here.
        expect(failure.code).assertEqual(ERR_SERVICE_EXCEPTION);
        return;
      }

      Logger.info(`DesktopLyricProbe isDesktopLyricSupported=${supported}`);
      expect(typeof supported).assertEqual('boolean');
    });

    it('desktopLyricEnableAndVisibilityPathIsDocumented', 0, async () => {
      let supported: boolean = false;
      try {
        supported = await avSession.isDesktopLyricSupported();
      } catch (error) {
        const step = stepFailed('isDesktopLyricSupported', error as BusinessError);
        Logger.info(`DesktopLyricProbe skipped, ${describeStep(step)}`);
        expect(step.code).assertEqual(ERR_SERVICE_EXCEPTION);
        return;
      }
      Logger.info(`DesktopLyricProbe supported=${supported}`);

      // A dedicated session so the probe never mutates the real player's one.
      // Note the SDK's constraint: "An ability can only create one AVSession".
      // The test runs in its own TestAbility, so this is a distinct ability
      // from the app's EntryAbility — but if creation is refused anyway, that
      // refusal is itself a spike finding and is recorded rather than thrown.
      //
      // createAVSession needs an *ability* context: delegator.getAppContext()
      // returns the application context and is rejected at runtime with
      // 401 "invalid context" (device-observed 2026-08-25), even though it
      // type-checks as common.Context.
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      let session: avSession.AVSession | null = null;
      let context: common.UIAbilityContext | null = null;
      try {
        const ability = await delegator.getCurrentTopAbility();
        context = ability.context;
      } catch (error) {
        const step = stepFailed('getCurrentTopAbility', error as BusinessError);
        Logger.info(`DesktopLyricProbe ${describeStep(step)}`);
        return;
      }
      if (context === null) {
        Logger.info('DesktopLyricProbe no ability context, skipped');
        return;
      }
      try {
        session = await avSession.createAVSession(context, 'NeriPlayerLyricProbe', 'audio');
      } catch (error) {
        const step = stepFailed('createAVSession', error as BusinessError);
        Logger.info(`DesktopLyricProbe ${describeStep(step)}`);
        // Nothing further is assertable without a session; record and stop.
        expect(step.code === ERR_SERVICE_EXCEPTION || step.code === ERR_SESSION_NOT_EXIST).assertTrue();
        return;
      }

      const steps: ProbeStep[] = [];
      let visibilityCallbacks: number = 0;
      let lastVisibility: boolean | null = null;
      try {
        // Publish a standard-LRC lyric first: on a device that renders the
        // system lyric window, this is what it would draw.
        const metadata: avSession.AVMetadata = {
          assetId: 'probe:desktop-lyric',
          title: 'NeriPlayer 探针',
          artist: 'M10.2',
          duration: 60000,
          lyric: '[00:00.000] desktop lyric probe line one\n[00:03.000] probe line two\n',
          singleLyricText: 'desktop lyric probe line one',
        };
        try {
          await session.setAVMetadata(metadata);
          steps.push(stepOk('setAVMetadata'));
        } catch (error) {
          steps.push(stepFailed('setAVMetadata', error as BusinessError));
        }

        // Activate + report a playing state. The desktop-lyric methods do not
        // document this as a precondition, but an inactive session with no
        // playback state is not a media session the system has any reason to
        // draw a lyric window for. Recorded as steps so that if the window
        // still never appears, "we did activate it" is part of the evidence.
        try {
          await session.activate();
          steps.push(stepOk('activate'));
        } catch (error) {
          steps.push(stepFailed('activate', error as BusinessError));
        }

        try {
          const playbackState: avSession.AVPlaybackState = {
            state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
            position: { elapsedTime: 1000, updateTime: Date.now() },
            duration: 60000,
          };
          await session.setAVPlaybackState(playbackState);
          steps.push(stepOk('setAVPlaybackState'));
        } catch (error) {
          steps.push(stepFailed('setAVPlaybackState', error as BusinessError));
        }

        // Subscribing before enabling: the SDK documents only 6600101/6600102
        // for the registration itself, not the not-supported code.
        try {
          session.onDesktopLyricVisibilityChanged((visible: boolean): void => {
            visibilityCallbacks += 1;
            lastVisibility = visible;
            Logger.info(`DesktopLyricProbe onDesktopLyricVisibilityChanged=${visible}`);
          });
          steps.push(stepOk('onDesktopLyricVisibilityChanged'));
        } catch (error) {
          steps.push(stepFailed('onDesktopLyricVisibilityChanged', error as BusinessError));
        }

        try {
          await session.enableDesktopLyric(true);
          steps.push(stepOk('enableDesktopLyric'));
        } catch (error) {
          steps.push(stepFailed('enableDesktopLyric', error as BusinessError));
        }

        try {
          await session.setDesktopLyricVisible(true);
          steps.push(stepOk('setDesktopLyricVisible'));
        } catch (error) {
          steps.push(stepFailed('setDesktopLyricVisible', error as BusinessError));
        }

        try {
          const visible = await session.isDesktopLyricVisible();
          Logger.info(`DesktopLyricProbe isDesktopLyricVisible=${visible}`);
          steps.push(stepOk('isDesktopLyricVisible'));
        } catch (error) {
          steps.push(stepFailed('isDesktopLyricVisible', error as BusinessError));
        }

        try {
          const state = await session.getDesktopLyricState();
          Logger.info(`DesktopLyricProbe getDesktopLyricState.isLocked=${state.isLocked}`);
          steps.push(stepOk('getDesktopLyricState'));
        } catch (error) {
          steps.push(stepFailed('getDesktopLyricState', error as BusinessError));
        }

        // Hold the window open: gives the system a beat to deliver a
        // visibility callback, and an operator a window to screenshot in.
        Logger.info('DesktopLyricProbe observation window open');
        await sleep(OBSERVE_MS);
        // Toggle back off and re-query, so the visibility round-trip is
        // covered in both directions rather than only the "on" edge.
        try {
          await session.setDesktopLyricVisible(false);
          steps.push(stepOk('setDesktopLyricVisible(false)'));
        } catch (error) {
          steps.push(stepFailed('setDesktopLyricVisible(false)', error as BusinessError));
        }
        try {
          const visibleAfterOff = await session.isDesktopLyricVisible();
          Logger.info(`DesktopLyricProbe isDesktopLyricVisibleAfterOff=${visibleAfterOff}`);
          steps.push(stepOk('isDesktopLyricVisible(afterOff)'));
        } catch (error) {
          steps.push(stepFailed('isDesktopLyricVisible(afterOff)', error as BusinessError));
        }

        Logger.info(`DesktopLyricProbe visibilityCallbacks=${visibilityCallbacks} last=${lastVisibility}`);
        Logger.info(`DesktopLyricProbe steps ${steps.map(describeStep).join(' ')}`);

        // The spike's assertion: every call either succeeded or failed with a
        // code the SDK documents for it. An undocumented code means the d.ts
        // and the device disagree, which is the finding worth failing on.
        const documented: number[] = [
          ERR_SERVICE_EXCEPTION, ERR_SESSION_NOT_EXIST, ERR_NOT_ENABLED, ERR_NOT_SUPPORTED
        ];
        for (const step of steps) {
          if (!step.ok) {
            expect(documented.includes(step.code)).assertTrue();
          }
        }

        // Cross-check the SDK's own contract: if the device reports the
        // feature unsupported, enableDesktopLyric must say 6600111.
        const enableStep = steps.find((item): boolean => item.name === 'enableDesktopLyric');
        if (!supported && enableStep !== undefined && !enableStep.ok) {
          expect(enableStep.code).assertEqual(ERR_NOT_SUPPORTED);
        }
      } finally {
        try {
          session.offDesktopLyricVisibilityChanged();
        } catch (error) {
          Logger.info(`DesktopLyricProbe off failed: ${(error as BusinessError).message}`);
        }
        try {
          await session.destroy();
        } catch (error) {
          Logger.info(`DesktopLyricProbe destroy failed: ${(error as BusinessError).message}`);
        }
      }
    });

    /**
     * The one negative case, and the reason it matters: if every desktop-lyric
     * call returned success unconditionally, the whole API surface could be a
     * no-op stub and the "everything=ok" result above would mean nothing.
     * `setDesktopLyricVisible` on a session that never called
     * `enableDesktopLyric` must be refused with 6600110. A refusal here proves
     * the service is tracking per-application state for real.
     */
    it('desktopLyricVisibleWithoutEnableIsRefused', 0, async () => {
      let supported: boolean = false;
      try {
        supported = await avSession.isDesktopLyricSupported();
      } catch (error) {
        const step = stepFailed('isDesktopLyricSupported', error as BusinessError);
        Logger.info(`DesktopLyricProbe negative skipped, ${describeStep(step)}`);
        expect(step.code).assertEqual(ERR_SERVICE_EXCEPTION);
        return;
      }

      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      let context: common.UIAbilityContext | null = null;
      try {
        const ability = await delegator.getCurrentTopAbility();
        context = ability.context;
      } catch (error) {
        const step = stepFailed('getCurrentTopAbility', error as BusinessError);
        Logger.info(`DesktopLyricProbe negative ${describeStep(step)}`);
        return;
      }
      if (context === null) {
        Logger.info('DesktopLyricProbe negative no ability context, skipped');
        return;
      }

      let session: avSession.AVSession | null = null;
      try {
        session = await avSession.createAVSession(context, 'NeriPlayerLyricNeg', 'audio');
      } catch (error) {
        const step = stepFailed('createAVSession', error as BusinessError);
        Logger.info(`DesktopLyricProbe negative ${describeStep(step)}`);
        return;
      }

      try {
        // Deliberately no enableDesktopLyric() call before this.
        let refusal: ProbeStep | null = null;
        try {
          await session.setDesktopLyricVisible(true);
        } catch (error) {
          refusal = stepFailed('setDesktopLyricVisible/noEnable', error as BusinessError);
        }

        if (refusal === null) {
          // Not a documented outcome, but record it plainly rather than
          // asserting a shape the device did not produce.
          Logger.info('DesktopLyricProbe negative setDesktopLyricVisible/noEnable=ok (not refused)');
          expect(supported).assertTrue();
          return;
        }

        Logger.info(`DesktopLyricProbe negative ${describeStep(refusal)}`);
        expect(refusal.code === ERR_NOT_ENABLED || refusal.code === ERR_NOT_SUPPORTED).assertTrue();
      } finally {
        try {
          await session.destroy();
        } catch (error) {
          Logger.info(`DesktopLyricProbe negative destroy failed: ${(error as BusinessError).message}`);
        }
      }
    });
  });
}
