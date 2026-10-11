// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { HttpClient } from './HttpClient';

/**
 * Short-link expansion for the explore search box (b23.tv / 163cn.tv).
 * Upstream resolves these with OkHttp following redirects; on HarmonyOS
 * HttpClient.expandRedirectUrl records the redirect chain with a REDIRECTION
 * interceptor, and the last hop is the final URL.
 */

/** Last recorded hop wins; a chain that never redirected keeps the input. */
export function finalRedirectUrl(hops: string[], originalUrl: string): string {
  if (hops.length === 0) {
    return originalUrl;
  }
  const last = hops[hops.length - 1].trim();
  return last.length > 0 ? last : originalUrl;
}

/** True when the URL itself still looks like a short-link host. */
export function isShortLinkHost(url: string): boolean {
  return url.startsWith('https://b23.tv/') || url.startsWith('http://b23.tv/')
    || url.startsWith('https://163cn.tv/') || url.startsWith('http://163cn.tv/');
}

/**
 * Expands one short link to its final URL. Never rejects: network failures
 * return the original URL so callers can degrade with their own toast.
 */
export async function expandExploreShortLink(url: string): Promise<string> {
  try {
    return await HttpClient.expandRedirectUrl(url);
  } catch (_error) {
    return url;
  }
}
