// SPDX-License-Identifier: GPL-3.0

import { privacyManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../app/Constants';
import { Logger } from '../app/Logger';

/**
 * AGC「隐私声明托管服务」适配层（华为官方托管方式）。
 *
 * 应用在 AppGallery Connect 控制台「服务 → 协议服务」按标准模板生成并关联
 * 托管协议后，首次打开由系统弹出标准化隐私弹窗（官方指南明确：接入托管的
 * 应用不得再自建隐私弹窗，双弹窗会被发布审核驳回），本模块负责：
 *   * 启动时判定托管是否生效（Index 据此跳过自建合规页，仅服务侧载分发）；
 *   * 解析两份文档的打开地址（与标准弹窗同源，且享受托管协议免发版的动态更新）。
 *
 * 未上架/侧载（GitHub Release 安装）时接口抛 1006700003，统一回退 Constants
 * 里的自托管 Gist 链接——该回退仅面向侧载分发，不作为 AGC 提审链接（官方
 * 《应用隐私政策链接提交及内容规范》明文排除 GitHub 类链接）。
 */

/** 托管链接解析结果；agreementUrl 可为空串（用户协议托管是官方非必须项）。 */
export interface HostedPrivacyLinks {
  privacyUrl: string;
  agreementUrl: string;
}

/** 纯逻辑：从隐私管理服务返回的链接列表提取两份文档地址；隐私声明链接缺失视为托管未生效。 */
export function pickHostedPrivacyLinks(links: privacyManager.AppPrivacyLink[]): HostedPrivacyLinks | null {
  let privacyUrl = '';
  let agreementUrl = '';
  for (const link of links) {
    if (link.url.length === 0) {
      continue;
    }
    if (link.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK) {
      privacyUrl = link.url;
    } else if (link.type === privacyManager.AppPrivacyLinkType.USER_AGREEMENT_LINK) {
      agreementUrl = link.url;
    }
  }
  return privacyUrl.length > 0 ? { privacyUrl: privacyUrl, agreementUrl: agreementUrl } : null;
}

/**
 * 查询 AGC 隐私声明托管状态，三种「未托管」形态统一归 null：设备无隐私管理
 * 服务（canIUse 不通过，如非 HMS 环境）、应用未接入托管（1006700003）、
 * 返回 UNSUPPORTED / 无隐私声明链接。调用点一律走侧载回退。
 */
export function fetchHostedPrivacyLinks(): HostedPrivacyLinks | null {
  if (!canIUse('SystemCapability.AppGalleryService.PrivacyManager')) {
    return null;
  }
  try {
    const info = privacyManager.getAppPrivacyMgmtInfo();
    if (info.type !== privacyManager.AppPrivacyMgmtType.FULL_MODE) {
      return null;
    }
    return pickHostedPrivacyLinks(info.privacyInfo);
  } catch (error) {
    const e = error as BusinessError;
    Logger.debug(`agcPrivacy: not hosted (code ${e.code})`);
    return null;
  }
}

/** 《隐私政策》打开地址：AGC 托管优先，侧载/未托管回退自托管 Gist。 */
export function resolvePrivacyDocUrl(): string {
  const hosted = fetchHostedPrivacyLinks();
  return hosted !== null ? hosted.privacyUrl : Constants.LEGAL_PRIVACY_URL;
}

/** 《用户协议》打开地址：AGC 托管优先，侧载/未托管回退自托管 Gist。 */
export function resolveAgreementDocUrl(): string {
  const hosted = fetchHostedPrivacyLinks();
  return hosted !== null && hosted.agreementUrl.length > 0
    ? hosted.agreementUrl
    : Constants.LEGAL_AGREEMENT_URL;
}
