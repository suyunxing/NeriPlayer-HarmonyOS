// SPDX-License-Identifier: GPL-3.0

import { fileIo } from '@kit.CoreFileKit';

/** Safety cap for the recursive walk: a runaway directory must not hang the
 * settings page (same ceiling as LocalDirectoryScanner). */
const MAX_WALK_FILES: number = 20000;

/**
 * Storage usage helpers for the settings storage-analysis section
 * (UPSTREAM_SYNC_PLAN F-8, upstream #328/#335): recursive directory size and
 * a human-readable byte formatter. Pure formatting is unit-testable; the
 * walk is @ohos-bound and degrades to 0 on any error.
 */

/** Synchronous recursive byte sum of a directory; 0 when unreadable/absent. */
export function dirSizeBytes(path: string): number {
  if (path.length === 0) {
    return 0;
  }
  return sumDir(path, { count: 0 });
}

function sumDir(path: string, budget: WalkBudget): number {
  let total = 0;
  let names: string[] = [];
  try {
    names = fileIo.listFileSync(path);
  } catch (error) {
    return 0;
  }
  for (const name of names) {
    if (budget.count >= MAX_WALK_FILES) {
      return total;
    }
    const child = `${path}/${name}`;
    try {
      const stat = fileIo.statSync(child);
      budget.count++;
      if (stat.isDirectory()) {
        total += sumDir(child, budget);
      } else {
        total += stat.size;
      }
    } catch (error) {
      // Unreadable entries are skipped, not fatal.
    }
  }
  return total;
}

/** Single-file byte size; 0 when unreadable/absent. */
export function fileSizeBytes(path: string): number {
  if (path.length === 0) {
    return 0;
  }
  try {
    return fileIo.statSync(path).size;
  } catch (error) {
    return 0;
  }
}

class WalkBudget {
  count: number = 0;
}

/** 1.2 MB / 3.4 GB style formatting; sub-KB values stay in B. */
export function formatStorageBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  const text = unit === 0 ? `${Math.round(value)}` : value.toFixed(1);
  return `${text} ${units[unit]}`;
}
