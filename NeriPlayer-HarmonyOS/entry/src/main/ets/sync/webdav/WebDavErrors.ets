// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** Typed WebDAV failures shared by transport, coordinator and settings UI. */

export enum WebDavErrorKind {
  AUTH = 'auth',
  DIRECTORY_INVALID = 'directory_invalid',
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

/**
 * Maps an HTTP status to a typed failure. `dirProbe` marks collection-level
 * operations (PROPFIND): a missing/broken path there is a configuration error,
 * not "backup file does not exist yet" and never a merge conflict.
 */
export function classifyWebDavFailure(operation: string, statusCode: number,
  bodyText: string, dirProbe: boolean = false): WebDavError {
  if (statusCode === 401 || statusCode === 403) {
    return new WebDavError(WebDavErrorKind.AUTH, statusCode,
      `WebDAV authentication failed (${operation} ${statusCode})`);
  }
  if (dirProbe && (statusCode === 404 || statusCode === 409 || statusCode === 410)) {
    return new WebDavError(WebDavErrorKind.DIRECTORY_INVALID, statusCode,
      `WebDAV directory not accessible (${operation} ${statusCode})${bodySuffix(bodyText)}`);
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

/** User-facing Chinese text for every WebDAV error kind (shared by settings UI and sync reports). */
export function describeWebDavErrorForUser(error: Error): string {
  if (error instanceof WebDavError) {
    if (error.kind === WebDavErrorKind.AUTH) {
      return 'WebDAV 用户名或密码错误';
    }
    if (error.kind === WebDavErrorKind.DIRECTORY_INVALID) {
      return 'WebDAV 目录不存在或不可访问，请检查目录配置';
    }
    if (error.kind === WebDavErrorKind.FILE_NOT_FOUND) {
      return '远端暂无备份文件（首次同步时将创建）';
    }
    if (error.kind === WebDavErrorKind.CONTENT_CONFLICT) {
      return '远端文件已被其他设备修改，请重新拉取后同步';
    }
    if (error.kind === WebDavErrorKind.NETWORK) {
      return `网络错误：${error.message}`;
    }
    return error.message;
  }
  return error.message;
}
