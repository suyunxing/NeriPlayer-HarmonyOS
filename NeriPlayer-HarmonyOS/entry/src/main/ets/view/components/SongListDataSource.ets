// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../../model/SongItem';

/**
 * LazyForEach 数据源：承载整表 SongItem 数组，供 List 按可视区按需建行。
 * 之前歌单/专辑/歌手等长列表用 ForEach 一次性建满全部行（千首级歌单进场即
 * 建数千组件并发拉图），滑动掉帧；改走 LazyForEach 后仅视口 + cachedCount 行存活。
 * 页面在自己的 @State 数组整体替换后必须调用 reset() —— @State 重赋值不会
 * 自动通知 IDataSource，漏调会导致列表不刷新。
 */
export class SongListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: SongItem[] = [];

  constructor(items: SongItem[] = []) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SongItem {
    return this.items[index];
  }

  /**
   * 整表替换。LazyForEach 按 keyGenerator diff：key 未变的行保留（不重建、
   * 不重放 aboutToAppear），仅增删的行建/销，因此排序、过滤、增删都是低成本更新。
   */
  reset(items: SongItem[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
