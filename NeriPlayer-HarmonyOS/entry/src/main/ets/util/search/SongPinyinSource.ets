// SPDX-License-Identifier: GPL-3.0
// Han→pinyin resolver backed by ohpm pinyin-pro (MIT, offline, no platform
// APIs). Chosen over the system i18n.Transliterator after the 2026-10-11
// evaluation: the library is pure JS (hypium-testable locally), returns
// tone-less pinyin deterministically and does not drift with CLDR versions.

import { pinyin } from 'pinyin-pro';
import { PinyinResolver, SearchTextMatcher } from './SearchTextMatcher';

/**
 * 单字 → 无声调小写全拼（多音字取库内常用音，对齐上游 TinyPinyin 单音
 * 行为）；非汉字返回空串（候选生成只对汉字询问拼音）。
 */
export function pinyinProResolver(ch: string): string {
  const code = ch.charCodeAt(0);
  if (code < 0x4E00 || code > 0x9FFF) {
    return '';
  }
  const parts: string[] = pinyin(ch, { toneType: 'none', type: 'array', nonZh: 'consecutive' });
  if (parts.length === 0) {
    return '';
  }
  return parts[0].toLowerCase();
}

/** 应用启动时调用一次（EntryAbility.onCreate）：给搜索匹配器注入拼音能力。 */
export function installSearchPinyinResolver(): void {
  const resolver: PinyinResolver = pinyinProResolver;
  SearchTextMatcher.setPinyinResolver(resolver);
}
