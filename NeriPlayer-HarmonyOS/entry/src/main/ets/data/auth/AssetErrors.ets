// SPDX-License-Identifier: GPL-3.0

/**
 * Classification of @ohos.security.asset error codes, used by CredentialStore
 * to decide between retry, memory fallback, and hard failure.
 * Codes verified against the API 24 SDK d.ts
 * (sdk/default/openharmony/ets/api/@ohos.security.asset.d.ts, ErrorCode enum).
 */

export enum AssetErrorKind {
  /** 24000002: no asset with the requested alias (benign for reads). */
  NOT_FOUND = 0,
  /** 24000003: alias already exists (handled by OVERWRITE conflict policy). */
  DUPLICATED = 1,
  /** Service unusable in this environment: fall back to session memory. */
  FALLBACK = 2,
  /** Transient failure: worth one retry before surfacing an error. */
  RETRY = 3,
  /** Programming error or persistent corruption: surface to caller. */
  FATAL = 4
}

export const ASSET_ERR_SERVICE_UNAVAILABLE: number = 24000001;
export const ASSET_ERR_NOT_FOUND: number = 24000002;
export const ASSET_ERR_DUPLICATED: number = 24000003;
export const ASSET_ERR_ACCESS_DENIED: number = 24000004;
export const ASSET_ERR_STATUS_MISMATCH: number = 24000005;
export const ASSET_ERR_OUT_OF_MEMORY: number = 24000006;
export const ASSET_ERR_DATA_CORRUPTED: number = 24000007;
export const ASSET_ERR_DATABASE_ERROR: number = 24000008;
export const ASSET_ERR_CRYPTO_ERROR: number = 24000009;
export const ASSET_ERR_IPC_ERROR: number = 24000010;
export const ASSET_ERR_BMS_ERROR: number = 24000011;
export const ASSET_ERR_ACCOUNT_ERROR: number = 24000012;
export const ASSET_ERR_ACCESS_TOKEN_ERROR: number = 24000013;
export const ASSET_ERR_FILE_OPERATION_ERROR: number = 24000014;
export const ASSET_ERR_GET_SYSTEM_TIME_ERROR: number = 24000015;
export const ASSET_ERR_LIMIT_EXCEEDED: number = 24000016;
export const ASSET_ERR_UNSUPPORTED: number = 24000017;
export const ASSET_ERR_PARAM_VERIFICATION_FAILED: number = 24000018;

export function classifyAssetError(code: number): AssetErrorKind {
  if (code === ASSET_ERR_NOT_FOUND) {
    return AssetErrorKind.NOT_FOUND;
  }
  if (code === ASSET_ERR_DUPLICATED) {
    return AssetErrorKind.DUPLICATED;
  }
  // The asset service itself is missing/unreachable in this environment
  // (emulator images without the SystemCapability, IPC/BMS/account issues):
  // degrade to session memory instead of failing every login flow.
  if (code === ASSET_ERR_SERVICE_UNAVAILABLE || code === ASSET_ERR_IPC_ERROR
    || code === ASSET_ERR_BMS_ERROR || code === ASSET_ERR_ACCOUNT_ERROR
    || code === ASSET_ERR_ACCESS_TOKEN_ERROR || code === ASSET_ERR_UNSUPPORTED) {
    return AssetErrorKind.FALLBACK;
  }
  if (code === ASSET_ERR_OUT_OF_MEMORY || code === ASSET_ERR_DATABASE_ERROR
    || code === ASSET_ERR_GET_SYSTEM_TIME_ERROR) {
    return AssetErrorKind.RETRY;
  }
  return AssetErrorKind.FATAL;
}

export function assetErrorName(code: number): string {
  return `AssetError(${code})`;
}
