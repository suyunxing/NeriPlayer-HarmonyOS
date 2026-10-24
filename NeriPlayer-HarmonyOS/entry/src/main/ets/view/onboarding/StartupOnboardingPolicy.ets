// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 01c57a11 (StartupOnboardingProgress policy half). The HarmonyOS
// onboarding keeps the upstream progress math and no-platform warning; the
// permission-warning / preview-geometry helpers stay upstream-only because
// this port has no runtime-permission step and reuses the settings preview.

/** 鸿蒙引导步数（上游 9 步裁剪：无语言步/权限步，播放源与播放器拆步）。 */
export const STARTUP_ONBOARDING_STEP_COUNT: number = 7;

/** 上游 calculateStartupOnboardingProgress：(step+1)/count，夹取 0..1。 */
export function calculateStartupOnboardingProgress(stepIndex: number, stepCount: number): number {
  if (stepCount <= 0) {
    return 0;
  }
  const progress = (stepIndex + 1) / stepCount;
  if (progress < 0) {
    return 0;
  }
  if (progress > 1) {
    return 1;
  }
  return progress;
}

/**
 * 上游 shouldWarnStartupNoPlatformConnected 的鸿蒙两平台形态：网易云与
 * B 站都未登录时提示「可稍后在设置连接」（YouTube 匿名可用，不算连接态）。
 */
export function shouldWarnStartupNoPlatformConnected(
  neteaseLogged: boolean,
  biliLogged: boolean
): boolean {
  return !neteaseLogged && !biliLogged;
}
