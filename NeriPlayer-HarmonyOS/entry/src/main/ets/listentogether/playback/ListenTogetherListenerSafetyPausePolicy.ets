// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherListenerSafetyPausePolicy.kt.
 *
 * When member control is off, a listener's own transport must not be able to
 * start playback: the room decides. Rather than disabling the buttons and leaving
 * the user with a dead UI, the listener is allowed to press play and is then
 * immediately paused back, with the resume held until the room says so.
 */

/** Upstream `LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE`. */
export const LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE: string = 'LISTENER_SAFETY_RESUME';

/**
 * `allowMemberControl` is nullable on purpose: an unknown setting must not switch
 * the safety pause on, because a listener in a room whose settings have not
 * arrived yet would otherwise be pinned paused.
 */
export function shouldUseListenTogetherListenerSafetyPause(
  listenTogetherActive: boolean,
  isCurrentUserController: boolean,
  allowMemberControl: boolean | null
): boolean {
  return listenTogetherActive && !isCurrentUserController && allowMemberControl === false;
}

/**
 * True while a held resume must keep playback down. The resume the policy itself
 * issues is exempt, otherwise it would block the very thing it exists to release.
 */
export function shouldHoldListenTogetherPlaybackForSafetyPause(
  safetyPausePendingResume: boolean,
  causeType: string | null
): boolean {
  return safetyPausePendingResume && causeType !== LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE;
}

/**
 * 输出设备丢失（拔耳机/断蓝牙）时听友的动作（上游 #318/6308fa60）：
 * 听友暂停会与房主失步，安全恢复也只能整段追平——改为本地静音继续播，
 * 音量捕获待新输出设备接入时恢复。非听友/未在播维持原硬暂停。
 */
export function shouldMuteListenTogetherListenerForAudioRouteLoss(
  listenerSafetyPauseApplies: boolean,
  isPlaying: boolean
): boolean {
  return listenerSafetyPauseApplies && isPlaying;
}

/**
 * 静音抑制期间对播放器施加的音量（上游 volumeWhileAudioRouteMuted）：
 * 用户滑条/淡入淡出的目标音量被压到 0，静音不被旁路。
 */
export function volumeWhileListenTogetherRouteMuted(
  requestedVolume: number,
  routeMuteSuppressed: boolean
): number {
  return routeMuteSuppressed ? 0 : requestedVolume;
}

/**
 * 输出设备重新接入（REASON_NEW_DEVICE_AVAILABLE）时是否恢复被抑制的
 * 音量：仅在仍在播放时恢复，未播放只解除抑制（上游
 * restorePlaybackAfterTransientAudioRouteLoss 的 shouldRestore 判定）。
 */
export function shouldRestoreListenTogetherRouteMuteVolume(
  routeMuteSuppressed: boolean,
  isPlaying: boolean
): boolean {
  return routeMuteSuppressed && isPlaying;
}
