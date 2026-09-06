/** Typed WebDAV failures shared by transport, coordinator and settings UI. */

export enum WebDavErrorKind {
  AUTH = 'auth',
  FILE_NOT_FOUND = 'file_not_found',
  CONTENT_CONFLICT = 'content_conflict',
  MISSING_CONCURRENCY_TOKEN = 'missing_concurrency_token',
  NETWORK = 'network',
  API = 'api'
}

const MAX_ERROR_MESSAGE_LENGTH: number = 240;

export class WebDavError extends Error {
  readonly kind: WebDavErrorKind;
  readonly statusCode: number;

  constructor(kind: WebDavErrorKind, statusCode: number, message: string) {
    super(message);
    this.name = 'WebDavError';
    this.kind = kind;
    this.statusCode = statusCode;
  }
}

export function classifyWebDavFailure(operation: string, statusCode: number,
  bodyText: string): WebDavError {
  if (statusCode === 401 || statusCode === 403) {
    return new WebDavError(WebDavErrorKind.AUTH, statusCode,
      `WebDAV authentication failed (${operation} ${statusCode})`);
  }
  if (statusCode === 404) {
    return new WebDavError(WebDavErrorKind.FILE_NOT_FOUND, statusCode,
      `WebDAV remote resource not found (${operation} 404)`);
  }
  if (statusCode === 409 || statusCode === 412 || statusCode === 423) {
    return new WebDavError(WebDavErrorKind.CONTENT_CONFLICT, statusCode,
      trimWebDavError(`${operation} failed: ${statusCode}${bodySuffix(bodyText)}`));
  }
  return new WebDavError(WebDavErrorKind.API, statusCode,
    trimWebDavError(`${operation} failed: ${statusCode}${bodySuffix(bodyText)}`));
}

export function missingConcurrencyTokenError(): WebDavError {
  return new WebDavError(WebDavErrorKind.MISSING_CONCURRENCY_TOKEN, 0,
    'WebDAV server does not expose a strong ETag or Last-Modified concurrency token');
}

export function trimWebDavError(message: string): string {
  return message.length <= MAX_ERROR_MESSAGE_LENGTH ? message :
    message.substring(0, MAX_ERROR_MESSAGE_LENGTH);
}

function bodySuffix(bodyText: string): string {
  const trimmed = bodyText.trim();
  return trimmed.length === 0 ? '' : ` - ${trimmed}`;
}
