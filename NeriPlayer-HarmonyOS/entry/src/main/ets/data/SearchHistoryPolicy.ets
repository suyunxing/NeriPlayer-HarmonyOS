// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commits dfa37db0 / bf50094e (data/search/ExploreSearchHistoryPolicy). Pure
// history-update and query-alias helpers shared by the explore page.

import {
  HISTORY_SEARCH_ALIAS_MAX_SCORE,
  NO_SEARCH_MATCH,
  SearchTextMatcher,
  SearchValue
} from '../util/search/SearchTextMatcher';

export const DEFAULT_SEARCH_HISTORY_LIMIT: number = 12;

/**
 * 上游 updatedExploreSearchHistory：新查询置顶，忽略大小写去重，
 * trim 空白，超限截断。
 */
export function updatedSearchHistory(
  current: string[],
  query: string,
  limit: number = DEFAULT_SEARCH_HISTORY_LIMIT
): string[] {
  const normalizedQuery = query.trim();
  if (normalizedQuery.length === 0 || limit <= 0) {
    return current.slice(0, Math.max(0, limit));
  }
  const seenLower = new Set<string>();
  seenLower.add(normalizedQuery.toLowerCase());
  const out: string[] = [normalizedQuery];
  for (const item of current) {
    const normalizedItem = item.trim();
    const key = normalizedItem.toLowerCase();
    if (normalizedItem.length === 0 || seenLower.has(key)) {
      continue;
    }
    seenLower.add(key);
    out.push(normalizedItem);
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}

/**
 * 上游 resolveExploreSearchKeyword：查询 >= 2 字符时，若历史里有低分
 * （强匹配：整串/前缀级）别名则替换为该历史词——「搜过完整名后输入缩写」
 * 场景自动换回全称。
 */
export function resolveExploreSearchKeyword(query: string, history: string[]): string {
  const normalizedQuery = query.trim();
  if (normalizedQuery.length < 2) {
    return normalizedQuery;
  }
  let bestKeyword = '';
  let bestScore: number = NO_SEARCH_MATCH;
  let bestLength: number = 0;
  for (const item of history) {
    const normalizedItem = item.trim();
    if (normalizedItem.length === 0
      || normalizedItem.toLowerCase() === normalizedQuery.toLowerCase()) {
      continue;
    }
    const aliasValues: SearchValue[] = [SearchTextMatcher.value(normalizedItem)];
    const score = SearchTextMatcher.score(normalizedQuery, aliasValues);
    if (score === NO_SEARCH_MATCH || score > HISTORY_SEARCH_ALIAS_MAX_SCORE) {
      continue;
    }
    if (bestScore === NO_SEARCH_MATCH || score < bestScore
      || (score === bestScore && normalizedItem.length < bestLength)) {
      bestKeyword = normalizedItem;
      bestScore = score;
      bestLength = normalizedItem.length;
    }
  }
  return bestKeyword.length > 0 ? bestKeyword : normalizedQuery;
}
