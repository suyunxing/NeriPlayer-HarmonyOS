// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure parsers for the youtubei/v1/player response and the bootstrap page
 * (no platform imports so the local hypium suite can exercise them).
 *
 * Field shapes follow the M6.0 spike report and the Android
 * YouTubeMusicClient/YouTubeMusicPlaybackRepository readers: numeric fields
 * may arrive as strings, and the quality fields live under
 * streamingData.{adaptiveFormats,formats}.
 */

export interface YtmPlayabilityStatusNode {
  status?: string;
  reason?: string;
  messages?: string[];
}

export interface YtmStreamingFormatNode {
  itag?: number;
  mimeType?: string;
  bitrate?: number;
  averageBitrate?: number;
  audioSampleRate?: string;
  contentLength?: string;
  approxDurationMs?: string;
  url?: string;
  signatureCipher?: string;
  cipher?: string;
}

export interface YtmStreamingDataNode {
  adaptiveFormats?: YtmStreamingFormatNode[];
  formats?: YtmStreamingFormatNode[];
}

export interface YtmVideoDetailsNode {
  videoId?: string;
  title?: string;
  lengthSeconds?: string;
  author?: string;
}

export interface YtmPlayerResponseNode {
  playabilityStatus?: YtmPlayabilityStatusNode;
  streamingData?: YtmStreamingDataNode;
  videoDetails?: YtmVideoDetailsNode;
}

/** Normalized playability verdict; ok === true passes through. */
export class YtmPlayability {
  status: string = '';
  reason: string = '';
  ok: boolean = false;
}

/** Normalized audio candidate for format selection. */
export class YtmAudioCandidate {
  itag: number = 0;
  mimeType: string = '';
  bitrate: number = 0;
  audioSampleRateHz: number = 0;
  contentLength: number = 0;
  approxDurationMs: number = 0;
  directUrl: string = '';
  hasCipher: boolean = false;
}

export class YtmBootstrapData {
  apiKey: string = '';
  visitorData: string = '';
  signatureTimestamp: number = 0;
}

function parsePositiveInt(value: string | undefined): number {
  if (value === undefined || value.length === 0) {
    return 0;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return 0;
  }
  return Math.floor(parsed);
}

/**
 * Mirrors Android requirePlayable: blank/OK statuses pass, anything else is
 * rejected with "reason" plus the messages list joined by " | ".
 */
export function parseYtmPlayability(root: YtmPlayerResponseNode): YtmPlayability {
  const verdict = new YtmPlayability();
  const node = root.playabilityStatus;
  const status = (node?.status ?? '').trim();
  verdict.status = status;
  if (status.length === 0 || status === 'OK') {
    verdict.ok = true;
    return verdict;
  }
  const parts: string[] = [];
  const reason = (node?.reason ?? '').trim();
  if (reason.length > 0) {
    parts.push(reason);
  }
  const messages = node?.messages ?? [];
  for (const message of messages) {
    const trimmed = message.trim();
    if (trimmed.length > 0 && parts.indexOf(trimmed) < 0) {
      parts.push(trimmed);
    }
  }
  verdict.reason = parts.join(' | ');
  verdict.ok = false;
  return verdict;
}

/**
 * Collects audio-only formats from both format lists (Android
 * collectAudioCandidates). Video and entry-less rows are dropped; bitrate
 * falls back to averageBitrate; numeric strings are tolerated.
 */
export function collectYtmAudioCandidates(root: YtmPlayerResponseNode): YtmAudioCandidate[] {
  const streaming = root.streamingData;
  const raw: YtmStreamingFormatNode[] = (streaming?.adaptiveFormats ?? []).concat(
    streaming?.formats ?? []
  );
  const candidates: YtmAudioCandidate[] = [];
  for (const node of raw) {
    const mimeType = node.mimeType ?? '';
    if (!mimeType.startsWith('audio/')) {
      continue;
    }
    const candidate = new YtmAudioCandidate();
    candidate.itag = node.itag ?? 0;
    candidate.mimeType = mimeType;
    candidate.bitrate = node.bitrate ?? node.averageBitrate ?? 0;
    candidate.audioSampleRateHz = parsePositiveInt(node.audioSampleRate);
    candidate.contentLength = parsePositiveInt(node.contentLength);
    candidate.approxDurationMs = parsePositiveInt(node.approxDurationMs);
    candidate.directUrl = (node.url ?? '').trim();
    candidate.hasCipher =
      (node.signatureCipher ?? '').trim().length > 0 || (node.cipher ?? '').trim().length > 0;
    candidates.push(candidate);
  }
  return candidates;
}

/**
 * Extracts INNERTUBE bootstrap values from a youtube.com/music.youtube.com
 * page (probe fetch_bootstrap): INNERTUBE_API_KEY is required, VISITOR_DATA
 * is best-effort (the 2026-08 page ships "EOM_VISITOR_DATA" instead of the
 * classic key; an empty value is fine - the spike verified IOS player
 * requests pass without it), STS falls back to "signatureTimestamp".
 * Returns null when the API key is missing.
 */
export function parseYtmBootstrapHtml(html: string): YtmBootstrapData | null {
  const apiKey = matchYtmQuoted(html, 'INNERTUBE_API_KEY');
  if (apiKey.length === 0) {
    return null;
  }
  const bootstrap = new YtmBootstrapData();
  bootstrap.apiKey = apiKey;
  const classicVisitor = matchYtmQuoted(html, 'VISITOR_DATA');
  bootstrap.visitorData =
    classicVisitor.length > 0 ? classicVisitor : matchYtmQuoted(html, 'EOM_VISITOR_DATA');
  const sts = matchYtmNumber(html, 'STS');
  if (sts > 0) {
    bootstrap.signatureTimestamp = sts;
  } else {
    const sigTs = matchYtmNumber(html, 'signatureTimestamp');
    bootstrap.signatureTimestamp = sigTs;
  }
  return bootstrap;
}

function matchYtmQuoted(html: string, key: string): string {
  const marker = `"${key}":"`;
  const start = html.indexOf(marker);
  if (start < 0) {
    return '';
  }
  const valueStart = start + marker.length;
  const end = html.indexOf('"', valueStart);
  if (end < 0) {
    return '';
  }
  return html.substring(valueStart, end);
}

function matchYtmNumber(html: string, key: string): number {
  const marker = `"${key}":`;
  const start = html.indexOf(marker);
  if (start < 0) {
    return 0;
  }
  const valueStart = start + marker.length;
  let end = valueStart;
  while (end < html.length && html.charAt(end) >= '0' && html.charAt(end) <= '9') {
    end += 1;
  }
  if (end === valueStart) {
    return 0;
  }
  return Number(html.substring(valueStart, end));
}
