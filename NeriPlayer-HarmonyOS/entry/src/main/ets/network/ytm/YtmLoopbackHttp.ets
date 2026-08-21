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

function headerValue(headers: Record<string, string>, name: string): string {
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

export function buildYtmLoopbackResponseHeaders(headers: Record<string, string>): YtmLoopbackResponseHeaders {
  const contentRange = headerValue(headers, 'content-range');
  const lengthText = headerValue(headers, 'content-length');
  const length = lengthText.length > 0 ? Number(lengthText) : -1;
  return {
    statusCode: contentRange.length > 0 ? 206 : 200,
    contentType: headerValue(headers, 'content-type') || 'audio/mp4',
    contentLength: Number.isNaN(length) ? -1 : length,
    contentRange,
    acceptRanges: headerValue(headers, 'accept-ranges'),
    etag: headerValue(headers, 'etag'),
    lastModified: headerValue(headers, 'last-modified')
  };
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
