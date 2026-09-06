/**
 * GitHub API failure classification (pure logic, no platform imports).
 *
 * The Android transport (GitHubRepositorySyncTransport.throwForResponse)
 * classifies: 401 -> TokenExpired, 409 / 422+"reference" (when conflict
 * detection is on) -> ContentConflict, everything else -> GitHubApiException.
 * Rate limiting is NOT detected upstream; this port adds the RATE_LIMITED
 * class required by M5.3 (403 with exhausted X-RateLimit or 429 + Retry-After)
 * so the UI can tell users to wait instead of reporting a generic failure.
 */

export enum GitHubErrorKind {
  TOKEN_EXPIRED = 'token_expired',
  FILE_NOT_FOUND = 'file_not_found',
  REPO_NOT_FOUND = 'repo_not_found',
  CONTENT_CONFLICT = 'content_conflict',
  RATE_LIMITED = 'rate_limited',
  NETWORK = 'network',
  API = 'api'
}

const MAX_ERROR_MESSAGE_LENGTH: number = 240;

export class GitHubApiError extends Error {
  readonly kind: GitHubErrorKind;
  readonly statusCode: number;
  readonly retryAfterMs: number;

  constructor(kind: GitHubErrorKind, statusCode: number, message: string, retryAfterMs: number = 0) {
    super(message);
    this.name = 'GitHubApiError';
    this.kind = kind;
    this.statusCode = statusCode;
    this.retryAfterMs = retryAfterMs;
  }
}

export class GhClassifyOptions {
  /** Treat 409 / 422+"reference" as an optimistic-lock conflict (branch ref update). */
  detectConflict: boolean = false;
  /** Kind reported for HTTP 404 - file reads use FILE_NOT_FOUND, repo lookups REPO_NOT_FOUND. */
  notFoundKind: GitHubErrorKind = GitHubErrorKind.API;
}

/** Truncates free-form error text, mirroring Android MAX_ERROR_MESSAGE_LENGTH. */
export function trimErrorMessage(message: string): string {
  if (message.length <= MAX_ERROR_MESSAGE_LENGTH) {
    return message;
  }
  return message.substring(0, MAX_ERROR_MESSAGE_LENGTH);
}

/**
 * Maps a non-2xx GitHub response to a typed failure. Header names must be
 * lower-cased keys (x-ratelimit-remaining, retry-after, x-ratelimit-reset).
 */
export function classifyGitHubFailure(
  operation: string,
  statusCode: number,
  bodyText: string,
  headers: Map<string, string>,
  options: GhClassifyOptions,
  nowMs: number = Date.now()
): GitHubApiError {
  const bodyMessage = ghBodyErrorMessage(bodyText);
  const composed = `${operation} failed: ${statusCode} - ${bodyMessage}`;
  if (statusCode === 401) {
    return new GitHubApiError(GitHubErrorKind.TOKEN_EXPIRED, statusCode,
      `GitHub 令牌无效或已过期（${operation} 401）`);
  }
  if (options.detectConflict &&
    (statusCode === 409 || (statusCode === 422 && bodyText.toLowerCase().includes('reference')))) {
    return new GitHubApiError(GitHubErrorKind.CONTENT_CONFLICT, statusCode, trimErrorMessage(composed));
  }
  const rateLimit = rateLimitRetryMs(headers, nowMs);
  if (statusCode === 429 || (statusCode === 403 && rateLimit.kind === RateLimitEvidence.EXHAUSTED)) {
    return new GitHubApiError(GitHubErrorKind.RATE_LIMITED, statusCode,
      `GitHub API 限流，请约 ${Math.ceil(rateLimit.retryAfterMs / 1000)} 秒后重试（${operation} ${statusCode}）`,
      rateLimit.retryAfterMs);
  }
  if (statusCode === 404) {
    if (options.notFoundKind === GitHubErrorKind.FILE_NOT_FOUND) {
      return new GitHubApiError(GitHubErrorKind.FILE_NOT_FOUND, statusCode, trimErrorMessage(composed));
    }
    if (options.notFoundKind === GitHubErrorKind.REPO_NOT_FOUND) {
      return new GitHubApiError(GitHubErrorKind.REPO_NOT_FOUND, statusCode,
        `仓库不存在或令牌无访问权限（${operation} 404）`);
    }
  }
  return new GitHubApiError(GitHubErrorKind.API, statusCode, trimErrorMessage(composed));
}

enum RateLimitEvidence {
  NONE = 0,
  EXHAUSTED = 1
}

class RateLimitInfo {
  kind: RateLimitEvidence = RateLimitEvidence.NONE;
  retryAfterMs: number = 0;
}

/**
 * Extracts a retry hint from x-ratelimit-remaining/reset (epoch seconds) or
 * the plain Retry-After header (seconds). Only EXHAUSTED evidence turns a 403
 * into RATE_LIMITED; a 429 is rate-limited regardless of headers.
 */
export function rateLimitRetryMs(headers: Map<string, string>, nowMs: number): RateLimitInfo {
  const info = new RateLimitInfo();
  const remaining = headers.get('x-ratelimit-remaining');
  if (remaining !== undefined && remaining.trim() === '0') {
    info.kind = RateLimitEvidence.EXHAUSTED;
    const reset = headers.get('x-ratelimit-reset');
    if (reset !== undefined) {
      const resetMs = Number(reset) * 1000;
      if (Number.isFinite(resetMs) && resetMs > nowMs) {
        info.retryAfterMs = resetMs - nowMs;
        return info;
      }
    }
  }
  const retryAfter = headers.get('retry-after');
  if (retryAfter !== undefined) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds > 0) {
      info.retryAfterMs = seconds * 1000;
      if (info.kind === RateLimitEvidence.NONE) {
        info.kind = RateLimitEvidence.EXHAUSTED;
      }
    }
  }
  return info;
}

/**
 * GitHub error bodies are {"message": "...", ...}; without JSON just return
 * the trimmed raw text (may be empty).
 */
export function ghBodyErrorMessage(bodyText: string): string {
  const trimmed = bodyText.trim();
  if (trimmed.length === 0) {
    return 'no response body';
  }
  const needle = '"message"';
  const index = trimmed.indexOf(needle);
  if (index < 0) {
    return trimErrorMessage(trimmed);
  }
  const colon = trimmed.indexOf(':', index + needle.length);
  if (colon < 0) {
    return trimErrorMessage(trimmed);
  }
  let i = colon + 1;
  while (i < trimmed.length && (trimmed.charAt(i) === ' ' || trimmed.charAt(i) === '\t')) {
    i++;
  }
  if (i >= trimmed.length || trimmed.charAt(i) !== '"') {
    return trimErrorMessage(trimmed);
  }
  let out = '';
  while (i < trimmed.length) {
    const ch = trimmed.charAt(i);
    if (ch === '"' && out.length > 0) {
      break;
    }
    if (ch === '"' && out.length === 0) {
      i++;
      continue;
    }
    out += ch;
    i++;
  }
  return trimErrorMessage(out);
}
