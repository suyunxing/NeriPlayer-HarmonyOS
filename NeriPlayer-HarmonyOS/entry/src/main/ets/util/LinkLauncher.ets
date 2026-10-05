// SPDX-License-Identifier: GPL-3.0

import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';

/**
 * 外部链接统一出口：openLink 优先匹配声明了 App Linking / Deep Linking 的
 * 应用，无匹配（appLinkingOnly=false）时回落系统默认浏览器。失败只记日志，
 * 不打断调用方 UI。
 */
export async function openExternalLink(context: common.UIAbilityContext, url: string): Promise<void> {
  const options: OpenLinkOptions = { appLinkingOnly: false };
  try {
    await context.openLink(url, options);
  } catch (error) {
    const e = error as Error;
    Logger.warn(`LinkLauncher.openExternalLink failed: ${e.message}`);
  }
}
