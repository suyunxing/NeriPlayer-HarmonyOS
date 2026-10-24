// SPDX-License-Identifier: GPL-3.0

/**
 * Detection helpers for the Android upstream ZSTD archive sync layout
 * (upstream #475, protocol v3/v4): a fixed-name manifest entry file plus
 * content-addressed `neriplayer-sync-v[34]-<sha256>.zst` objects. New Android
 * builds never read or write the legacy backup files after migrating a
 * repository to this layout, so syncing through `neriplayer-sync.json` /
 * `backup.json` would merge against a stale snapshot and silently fork the
 * dataset. The HarmonyOS side cannot decode the zstd payload yet (SDK ships
 * no zstd API; zlib covers Deflate only), so both backends refuse to sync
 * once this manifest is present.
 */

export const UPSTREAM_ARCHIVE_MANIFEST_FILE_NAME: string = 'neriplayer-sync-v3.manifest';

/**
 * Protocol digit carried by the manifest envelope magic (`NPSYNC0N`, e.g.
 * `NPSYNC04`), or -1 when the bytes are not an archive manifest.
 */
export function upstreamArchiveProtocolVersion(content: Uint8Array): number {
  const magic = 'NPSYNC0';
  if (content.length <= magic.length) {
    return -1;
  }
  for (let i = 0; i < magic.length; i++) {
    if (content[i] !== magic.charCodeAt(i)) {
      return -1;
    }
  }
  const digit = content[magic.length] - '0'.charCodeAt(0);
  return digit >= 0 && digit <= 9 ? digit : -1;
}

export function isUpstreamArchiveManifest(content: Uint8Array): boolean {
  return upstreamArchiveProtocolVersion(content) > 0;
}

export function describeUpstreamArchiveProtocolForUser(protocol: number): string {
  return `远端是 Android 新版归档同步格式（协议 v${protocol}），鸿蒙版暂不支持读写；已阻止同步以避免数据分叉，请使用 Android 端同步该目录/仓库`;
}
