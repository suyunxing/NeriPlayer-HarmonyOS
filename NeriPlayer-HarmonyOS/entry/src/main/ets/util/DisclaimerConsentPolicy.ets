// SPDX-License-Identifier: GPL-3.0

/**
 * 首启合规页（免责声明/隐私政策/用户协议）的版本门控。
 *
 * 协议正文存于 resources/rawfile（privacy_policy.md / user_agreement.md），
 * 每当正文实质修订时把 CURRENT_DISCLAIMER_VERSION 加一：已同意过旧版文本的
 * 安装会在新版本首次启动时重新进入合规页一次（Index.ets 启动状态机）。
 * 版本化之前的老安装只记录过布尔同意、此键为空串，因此同样会被要求确认一次。
 */
export const CURRENT_DISCLAIMER_VERSION: string = '2';

/** 未同意过，或同意的版本与当前协议文本不一致时，需要展示合规页。 */
export function isDisclaimerConfirmationRequired(accepted: boolean, acceptedVersion: string): boolean {
  return !accepted || acceptedVersion !== CURRENT_DISCLAIMER_VERSION;
}
