// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Pure decision helpers for the managed download directory (Android
 * ManagedDownloadStorageSettings / ManagedDownloadRootResolver): the custom
 * directory is a user-picked document URI persisted next to a display label,
 * and absence means the sandbox default <filesDir>/Download/NeriPlayer.
 *
 * No Kit imports here: the rules stay unit-testable in the local test VM.
 */
export class DownloadDirectory {
  static readonly URI_SCHEME_FILE: string = 'file://';
  static readonly DEFAULT_PATH_SUFFIX: string = '/Download/NeriPlayer';
  static readonly DEFAULT_DESCRIPTION: string = '应用内部 Download/NeriPlayer（默认）';

  /** A persisted custom directory is usable only as a non-empty file URI. */
  static isCustomUri(uri: string): boolean {
    return uri.length > DownloadDirectory.URI_SCHEME_FILE.length + 1
      && uri.startsWith(DownloadDirectory.URI_SCHEME_FILE);
  }

  /** Sandbox default: <filesDir>/Download/NeriPlayer. */
  static sandboxDefaultDir(filesDir: string): string {
    return `${filesDir}${DownloadDirectory.DEFAULT_PATH_SUFFIX}`;
  }

  /** Active download root: the custom URI when configured, else the default. */
  static resolveActiveDir(customUri: string, filesDir: string): string {
    return DownloadDirectory.isCustomUri(customUri)
      ? customUri
      : DownloadDirectory.sandboxDefaultDir(filesDir);
  }

  /** Display name for a picked folder URI: decoded last path segment. */
  static labelFromUri(uri: string): string {
    if (!DownloadDirectory.isCustomUri(uri)) {
      return '';
    }
    let path = uri.substring(DownloadDirectory.URI_SCHEME_FILE.length);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    const slash = path.lastIndexOf('/');
    const segment = slash >= 0 ? path.substring(slash + 1) : path;
    let decoded = segment;
    try {
      decoded = decodeURIComponent(segment);
    } catch (error) {
      // Malformed percent escapes: keep the raw segment.
    }
    return decoded.trim();
  }

  /** Settings row subtitle: stored label wins, then derived, then default. */
  static describeDirectory(uri: string, label: string): string {
    if (!DownloadDirectory.isCustomUri(uri)) {
      return DownloadDirectory.DEFAULT_DESCRIPTION;
    }
    const stored = label.trim();
    if (stored.length > 0) {
      return stored;
    }
    const derived = DownloadDirectory.labelFromUri(uri);
    return derived.length > 0 ? derived : uri;
  }

  /** Final file address inside a directory (URI or sandbox path). */
  static fileInDir(dir: string, fileName: string): string {
    const separator = dir.endsWith('/') ? '' : '/';
    return `${dir}${separator}${fileName}`;
  }

  /** Splits the persisted history blob (\n-joined URIs) into a clean list. */
  static historyUrisOf(stored: string): string[] {
    return stored.split('\n').map((line: string) => line.trim())
      .filter((line: string) => DownloadDirectory.isCustomUri(line));
  }

  /**
   * Merges a newly applied directory into the history blob: newest first,
   * de-duplicated, capped (catalog playback only needs the recent few). Old
   * directories stay listed so cold start can re-activate their grants —
   * committed files there must remain playable after switching away.
   */
  static mergeHistoryUris(stored: string, appliedUri: string, cap: number = 8): string {
    const merged: string[] = [appliedUri];
    for (const uri of DownloadDirectory.historyUrisOf(stored)) {
      if (merged.indexOf(uri) < 0) {
        merged.push(uri);
      }
    }
    return merged.slice(0, Math.max(1, cap)).join('\n');
  }
}
