// SPDX-License-Identifier: GPL-3.0

/**
 * 首启合规页（免责声明/隐私政策/用户协议）的版本门控。
 *
 * 协议正文托管在应用外（2026-10-05 起，母本 docs/legal/、发布载体与 URL 见
 * docs/legal/README.md），每当正文实质修订时把 CURRENT_DISCLAIMER_VERSION 加一：
 * 已同意过旧版文本的安装会在新版本首次启动时重新进入合规页一次（Index.ets
 * 启动状态机）。版本化之前的老安装只记录过布尔同意、此键为空串，因此同样会被
 * 要求确认一次。
 */
export const CURRENT_DISCLAIMER_VERSION: string = '2';

/** 未同意过，或同意的版本与当前协议文本不一致时，需要展示合规页。 */
export function isDisclaimerConfirmationRequired(accepted: boolean, acceptedVersion: string): boolean {
  return !accepted || acceptedVersion !== CURRENT_DISCLAIMER_VERSION;
}
