// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/invite/ListenTogetherBaseUrlResolver.kt.
 */
import { ListenTogetherInvite } from './ListenTogetherInvite';
import {
  normalizeListenTogetherBaseUrl,
  normalizedListenTogetherHttpBaseUrlOrNull
} from '../network/ListenTogetherBaseUrl';

export const DEFAULT_LISTEN_TOGETHER_BASE_URL: string = 'https://neriplayer.hancat.work/';

export function configuredListenTogetherBaseUrlOrNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return normalizedListenTogetherHttpBaseUrlOrNull(trimmed);
}

/**
 * 邀请链接来自外部不可信来源，强制 https，避免被诱导连接明文 http 端点遭中间人劫持。
 * 手动配置的自建服务器仍可用明文（走 configuredListenTogetherBaseUrlOrNull）。
 */
export function configuredListenTogetherInviteBaseUrlOrNull(value: string | null): string | null {
  const normalized = configuredListenTogetherBaseUrlOrNull(value);
  if (normalized === null) {
    return null;
  }
  return normalized.toLowerCase().startsWith('https://') ? normalized : null;
}

export function resolveListenTogetherBaseUrl(value: string | null): string {
  const configured = configuredListenTogetherBaseUrlOrNull(value);
  if (configured !== null) {
    return configured;
  }
  return normalizeListenTogetherBaseUrl(DEFAULT_LISTEN_TOGETHER_BASE_URL);
}

/** Priority: invite base URL -> the unsaved input -> the saved value -> default. */
export function resolveListenTogetherInviteJoinBaseUrl(
  invite: ListenTogetherInvite,
  savedBaseUrlInput: string | null,
  savedBaseUrl: string | null
): string {
  const fromInvite = configuredListenTogetherBaseUrlOrNull(invite.baseUrl);
  if (fromInvite !== null) {
    return fromInvite;
  }
  const fromInput = configuredListenTogetherBaseUrlOrNull(savedBaseUrlInput);
  if (fromInput !== null) {
    return fromInput;
  }
  const fromSaved = configuredListenTogetherBaseUrlOrNull(savedBaseUrl);
  if (fromSaved !== null) {
    return fromSaved;
  }
  return resolveListenTogetherBaseUrl(null);
}

export function isDefaultListenTogetherBaseUrl(value: string | null): boolean {
  return configuredListenTogetherBaseUrlOrNull(value) ===
    normalizeListenTogetherBaseUrl(DEFAULT_LISTEN_TOGETHER_BASE_URL);
}
