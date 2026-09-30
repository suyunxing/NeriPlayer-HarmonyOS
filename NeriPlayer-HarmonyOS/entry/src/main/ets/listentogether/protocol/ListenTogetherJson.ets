// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * JSON helpers shared by the listen-together protocol codecs.
 *
 * Android uses kotlinx.serialization (@Serializable data classes). ArkTS has no
 * reflection-based serializer, so every protocol model gets a hand-written
 * record codec built on these primitives.
 *
 * Encoding rule: null fields are omitted instead of being written as `null`.
 * kotlinx defaults to `encodeDefaults = false`, so a Kotlin field left at its
 * `null` default never reaches the wire either — omitting keeps both clients
 * byte-compatible.
 *
 * No platform imports: unit-testable in the local hypium environment.
 */

export type JsonRecord = Record<string, Object>;

/** Parses text into a JSON object; malformed input and non-objects yield null. */
export function jsonRecordFromText(text: string): JsonRecord | null {
  if (text.length === 0) {
    return null;
  }
  try {
    const parsed: Object = JSON.parse(text) as Object;
    return asJsonRecord(parsed);
  } catch (err) {
    return null;
  }
}

export function asJsonRecord(value: Object | null | undefined): JsonRecord | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (value instanceof Array) {
    return null;
  }
  if (typeof value !== 'object') {
    return null;
  }
  return value as JsonRecord;
}

export function optString(raw: JsonRecord, key: string): string | null {
  const value: Object | undefined = raw[key];
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === 'string') {
    return value as string;
  }
  return null;
}

export function reqString(raw: JsonRecord, key: string, fallback: string = ''): string {
  const value = optString(raw, key);
  return value === null ? fallback : value;
}

export function optNumber(raw: JsonRecord, key: string): number | null {
  const value: Object | undefined = raw[key];
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === 'number') {
    const numeric = value as number;
    return Number.isFinite(numeric) ? numeric : null;
  }
  if (typeof value === 'string') {
    const numeric = Number(value as string);
    return Number.isFinite(numeric) ? numeric : null;
  }
  return null;
}

export function reqNumber(raw: JsonRecord, key: string, fallback: number = 0): number {
  const value = optNumber(raw, key);
  return value === null ? fallback : value;
}

export function optBoolean(raw: JsonRecord, key: string): boolean | null {
  const value: Object | undefined = raw[key];
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  return null;
}

export function reqBoolean(raw: JsonRecord, key: string, fallback: boolean = false): boolean {
  const value = optBoolean(raw, key);
  return value === null ? fallback : value;
}

export function optRecord(raw: JsonRecord, key: string): JsonRecord | null {
  return asJsonRecord(raw[key]);
}

/** Returns the raw array entries for `key`, or null when the key is absent. */
export function optArray(raw: JsonRecord, key: string): Object[] | null {
  const value: Object | undefined = raw[key];
  if (value === null || value === undefined) {
    return null;
  }
  if (!(value instanceof Array)) {
    return null;
  }
  return value as Object[];
}

export function optRecordArray(raw: JsonRecord, key: string): JsonRecord[] | null {
  const entries = optArray(raw, key);
  if (entries === null) {
    return null;
  }
  const records: JsonRecord[] = [];
  for (const entry of entries) {
    const record = asJsonRecord(entry);
    if (record !== null) {
      records.push(record);
    }
  }
  return records;
}

export function optStringArray(raw: JsonRecord, key: string): string[] | null {
  const entries = optArray(raw, key);
  if (entries === null) {
    return null;
  }
  const values: string[] = [];
  for (const entry of entries) {
    if (typeof entry === 'string') {
      values.push(entry as string);
    }
  }
  return values;
}

export function putString(target: JsonRecord, key: string, value: string | null): void {
  if (value !== null) {
    target[key] = value;
  }
}

export function putNumber(target: JsonRecord, key: string, value: number | null): void {
  if (value !== null) {
    target[key] = value;
  }
}

export function putBoolean(target: JsonRecord, key: string, value: boolean | null): void {
  if (value !== null) {
    target[key] = value;
  }
}

export function putRecord(target: JsonRecord, key: string, value: JsonRecord | null): void {
  if (value !== null) {
    target[key] = value;
  }
}

export function putRecordArray(target: JsonRecord, key: string, value: JsonRecord[] | null): void {
  if (value !== null) {
    target[key] = value;
  }
}

export function putStringArray(target: JsonRecord, key: string, value: string[] | null): void {
  if (value !== null) {
    target[key] = value;
  }
}
