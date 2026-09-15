// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** Pure HTTP helpers shared by the YTM loopback bridge and local tests. */
export interface YtmLoopbackRequest {
  method: string;
  path: string;
  range: string;
}

export interface YtmLoopbackResponseHeaders {
  statusCode: number;
  contentType: string;
  contentLength: number;
  contentRange: string;
  acceptRanges: string;
  etag: string;
  lastModified: string;
}

/** Case-insensitive lookup for a header in a NetworkKit header record. */
export function readYtmHeader(headers: Record<string, string>, name: string): string {
  const target = name.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === target) {
      return headers[key];
    }
  }
  return '';
}

/** Parses the first request line and the Range header from an HTTP request. */
export function parseYtmLoopbackRequest(requestText: string): YtmLoopbackRequest | null {
  const lines = requestText.split(/\r?\n/);
  if (lines.length === 0) {
    return null;
  }
  const first = lines[0].trim().split(/\s+/);
  if (first.length < 2) {
    return null;
  }
  let range = '';
  for (let i = 1; i < lines.length; i++) {
    const colon = lines[i].indexOf(':');
    if (colon > 0 && lines[i].substring(0, colon).trim().toLowerCase() === 'range') {
      range = lines[i].substring(colon + 1).trim();
    }
  }
  return { method: first[0].toUpperCase(), path: first[1], range };
}

/** Accepts a single bytes=start-end range and returns its normalized header. */
export function normalizeYtmRange(range: string): string {
  const match = /^bytes=(\d+)-(\d*)$/i.exec(range.trim());
  if (match === null) {
    return '';
  }
  return `bytes=${match[1]}-${match[2]}`;
}

/** Reduces a URL to its host so redacted diagnostics carry no credentials. */
function hostOf(url: string): string {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return 'redacted';
  }
  const rest = url.substring(schemeEnd + 3);
  const slash = rest.indexOf('/');
  return slash > 0 ? rest.substring(0, slash) : rest;
}

/**
 * Diagnostic one-liner for an upstream header block. Values that can carry
 * auth material are redacted: a googlevideo redirect target keeps its auth
 * tokens in the query string, so Location degrades to a bare host.
 */
export function summarizeYtmLoopbackHeaders(headers: Record<string, string>): string {
  const parts: string[] = [];
  for (const key of Object.keys(headers)) {
    const lower = key.toLowerCase();
    const value = headers[key];
    if (lower === 'location' || lower === 'content-location' || lower === 'refresh') {
      parts.push(`${lower}=<${hostOf(value)}>`);
    } else if (lower === 'set-cookie' || lower === 'authorization') {
      parts.push(`${lower}=<redacted>`);
    } else {
      parts.push(`${lower}=${value}`);
    }
  }
  return parts.join(' ');
}

export function serializeYtmLoopbackResponseHeaders(response: YtmLoopbackResponseHeaders): string {
  const reason = response.statusCode === 206 ? 'Partial Content' : 'OK';
  const lines: string[] = [
    `HTTP/1.1 ${response.statusCode} ${reason}`,
    `Content-Type: ${response.contentType}`,
    'Connection: close'
  ];
  if (response.contentLength >= 0) {
    lines.push(`Content-Length: ${response.contentLength}`);
  }
  if (response.contentRange.length > 0) {
    lines.push(`Content-Range: ${response.contentRange}`);
  }
  if (response.acceptRanges.length > 0) {
    lines.push(`Accept-Ranges: ${response.acceptRanges}`);
  }
  if (response.etag.length > 0) {
    lines.push(`ETag: ${response.etag}`);
  }
  if (response.lastModified.length > 0) {
    lines.push(`Last-Modified: ${response.lastModified}`);
  }
  return `${lines.join('\r\n')}\r\n\r\n`;
}

/**
 * How much of one AVPlayer request the bridge fetches upstream at a time.
 *
 * An anonymous IOS-minted googlevideo URL only serves an opening prefix of the
 * entity and answers 403 (`Content-Type: text/plain`, `Content-Length: 0`,
 * `server=gvs 1.0`) for anything past it. Measured on the emulator on
 * 2026-08-21 across 4 tracks x 5 audio itags: every URL answered 206 at offset
 * 0 and 403 at the tail, and the boundary tracked the format rather than the
 * track — itag 140 stopped at 1059143..1061705 bytes even as the entity grew
 * from 3037696 to 4064243 bytes, while itag 139 stopped near 455000. By the
 * reported average bitrate that is roughly the first 55..73 seconds of every
 * track. It is therefore neither a fraction of the entity nor a single global
 * byte count. Open-ended (`bytes=N-`) and Range-less requests are refused
 * outright, and neither the User-Agent nor the `&range=` query form changes the
 * verdict.
 *
 * No per-request span limit was observed: every refusal is explained by the
 * requested END offset leaving that reachable prefix. Chunking still matters,
 * because AVPlayer asks for 2 MiB at a time and forwarding such a range
 * verbatim yields a single 403 and no audio at all. Splitting it delivers every
 * chunk that lies inside the prefix before the first refusal, which is what
 * lets AVPlayer prepare and play the opening stretch. One mebibyte keeps the
 * request count low while staying well inside the smallest measured prefix.
 */
export const YTM_UPSTREAM_CHUNK_BYTES = 1048576;

/** The byte interval the loopback will serve, resolved against the entity total. */
export interface YtmServedRange {
  start: number;
  /** Inclusive, already clamped to the last byte of the entity. */
  end: number;
  total: number;
  /** True when AVPlayer asked for a range, so the reply must be a 206. */
  partial: boolean;
}

/** Reads the entity total out of a `bytes start-end/total` Content-Range. */
export function parseYtmContentRangeTotal(contentRange: string): number {
  const match = /\/\s*(\d+)\s*$/.exec(contentRange.trim());
  if (match === null) {
    return -1;
  }
  const total = Number(match[1]);
  return Number.isNaN(total) ? -1 : total;
}

/**
 * Resolves AVPlayer's Range header against a known entity total.
 *
 * An absent or unparsable Range serves the whole entity as a 200; `bytes=N-`
 * and an end past the last byte both clamp to the entity end. Returns null when
 * the start is past the end of the entity, which is a 416 for the caller.
 */
export function resolveYtmServedRange(range: string, total: number): YtmServedRange | null {
  if (total <= 0) {
    return null;
  }
  const last = total - 1;
  const match = /^bytes=(\d+)-(\d*)$/i.exec(range.trim());
  if (match === null) {
    return { start: 0, end: last, total, partial: false };
  }
  const start = Number(match[1]);
  if (Number.isNaN(start) || start > last) {
    return null;
  }
  let end = last;
  if (match[2].length > 0) {
    const requested = Number(match[2]);
    if (!Number.isNaN(requested) && requested < last) {
      end = requested;
    }
  }
  if (end < start) {
    return null;
  }
  return { start, end, total, partial: true };
}

/**
 * Splits a served interval into upstream Range headers googlevideo accepts.
 * Every chunk is a closed interval of at most chunkSize bytes; the last one is
 * short. See YTM_UPSTREAM_CHUNK_BYTES for why open-ended ranges are unusable.
 */
export function planYtmUpstreamChunks(start: number, end: number, chunkSize: number): string[] {
  if (chunkSize <= 0 || end < start) {
    return [];
  }
  const chunks: string[] = [];
  let position = start;
  while (position <= end) {
    const chunkEnd = Math.min(position + chunkSize - 1, end);
    chunks.push(`bytes=${position}-${chunkEnd}`);
    position = chunkEnd + 1;
  }
  return chunks;
}

/**
 * Builds the single response header block the loopback sends for a served
 * interval. The bridge stitches many upstream chunks into this one body, so the
 * headers describe what AVPlayer asked for, not what any chunk returned.
 */
export function buildYtmServedResponseHeaders(
  served: YtmServedRange,
  contentType: string
): YtmLoopbackResponseHeaders {
  return {
    statusCode: served.partial ? 206 : 200,
    contentType: contentType.length > 0 ? contentType : 'audio/mp4',
    contentLength: served.end - served.start + 1,
    contentRange: served.partial ? `bytes ${served.start}-${served.end}/${served.total}` : '',
    acceptRanges: 'bytes',
    etag: '',
    lastModified: ''
  };
}
