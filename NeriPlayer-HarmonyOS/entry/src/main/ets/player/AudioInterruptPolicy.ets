// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Decision outcome for an audio interrupt event.
 */
export enum InterruptAction {
  /** Keep paused and remember to resume when focus returns. */
  PAUSE_TRANSIENT = 0,
  /** Keep paused permanently; ignore any later resume hint. */
  PAUSE_PERMANENT = 1,
  /** Resume playback now (focus returned and we were playing before). */
  RESUME = 2,
  /** System already handled ducking/unducking; nothing to do. */
  NONE = 3
}

/**
 * Numeric interrupt values mirroring @ohos.multimedia.audio enums
 * (InterruptForceType / InterruptHint / AudioStreamDeviceChangeReason), kept
 * here so the policy stays a pure, unit-testable module without @kit imports.
 */
export class InterruptValues {
  static readonly FORCE = 0;
  static readonly SHARE = 1;

  static readonly HINT_NONE = 0;
  static readonly HINT_RESUME = 1;
  static readonly HINT_PAUSE = 2;
  static readonly HINT_STOP = 3;
  static readonly HINT_DUCK = 4;
  static readonly HINT_UNDUCK = 5;

  static readonly REASON_OLD_DEVICE_UNAVAILABLE = 2;
  /** audio.StreamChangeReason.REASON_NEW_DEVICE_AVAILABLE（路由丢失静音恢复触发）。 */
  static readonly REASON_NEW_DEVICE_AVAILABLE = 1;
}

/**
 * Pure audio-interrupt decision policy, mirroring the Android app's media3
 * default focus semantics: transient loss pauses and later resumes only if
 * playback was active; permanent loss never auto-resumes; ducking is handled
 * by the system. Device unplug maps to a hard pause without auto-resume
 * (becoming-noisy semantics).
 *
 * mixWithOthers ("允许与其他应用同时播放") opts out of cooperative pauses:
 * SHARE-type pause hints from other apps are ignored so both streams keep
 * playing. FORCED interruptions still pause — those report that the system
 * has already acted on the stream and cannot be refused.
 */
export class AudioInterruptPolicy {
  /**
   * Decides the reaction to an audioInterrupt event.
   *
   * @param hintType interrupt hint (InterruptHint numeric value)
   * @param forceType force/share (InterruptForceType numeric value)
   * @param wasPlaying whether playback was active before the interruption
   * @param resumeOnFocusRegain current auto-resume intent
   * @param mixWithOthers whether the user allowed playing alongside other apps
   */
  static decide(
    hintType: number,
    forceType: number,
    wasPlaying: boolean,
    resumeOnFocusRegain: boolean,
    mixWithOthers: boolean = false
  ): InterruptAction {
    if (forceType === InterruptValues.FORCE) {
      if (hintType === InterruptValues.HINT_PAUSE) {
        return wasPlaying ? InterruptAction.PAUSE_TRANSIENT : InterruptAction.NONE;
      }
      if (hintType === InterruptValues.HINT_STOP) {
        return InterruptAction.PAUSE_PERMANENT;
      }
      // DUCK / UNDUCK / NONE: the system already adjusted the stream.
      return InterruptAction.NONE;
    }
    if (mixWithOthers && hintType === InterruptValues.HINT_PAUSE) {
      // 允许同时播放：无视其他应用的协作暂停请求，两边一起响。
      return InterruptAction.NONE;
    }
    if (!mixWithOthers && hintType === InterruptValues.HINT_PAUSE) {
      // 独占模式：配合协作暂停请求（暂停并等待焦点回归后自动续播）。
      return wasPlaying ? InterruptAction.PAUSE_TRANSIENT : InterruptAction.NONE;
    }
    if (hintType === InterruptValues.HINT_RESUME && resumeOnFocusRegain) {
      return InterruptAction.RESUME;
    }
    return InterruptAction.NONE;
  }

  /**
   * Output device became unavailable (e.g. wired headset unplugged, see the
   * audio-output-device-change guide): hard pause without auto-resume.
   */
  static decideForDeviceChange(changeReason: number): InterruptAction {
    return changeReason === InterruptValues.REASON_OLD_DEVICE_UNAVAILABLE
      ? InterruptAction.PAUSE_PERMANENT
      : InterruptAction.NONE;
  }
}
