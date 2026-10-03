// SPDX-License-Identifier: GPL-3.0

import { CoverCache } from '../../data/CoverCache';
import { Theme } from '../Theme';

/**
 * 小尺寸网络封面组件：渲染经 CoverCache 的进程内 LRU。列表行被 LazyForEach
 * 销毁重建时 aboutToAppear 同步命中缓存直接出图（未命中先给占位底色，取回
 * 后落地），不再出现「下滑再上滑全部重新加载」。
 */
@Component
export struct CoverImage {
  @Prop @Watch('onUrlChanged') url: string = '';
  /** 显示边长（vp）。 */
  @Prop sideVp: number = 52;
  @Prop radiusVp: number = 8;
  @State pixelMap: PixelMap | null = null;
  private requestedUrl: string = '';

  aboutToAppear(): void {
    this.loadFor(this.url);
  }

  onUrlChanged(): void {
    this.loadFor(this.url);
  }

  private loadFor(url: string): void {
    this.requestedUrl = url;
    const cached = CoverCache.peek(url);
    if (cached !== null) {
      this.pixelMap = cached;
      return;
    }
    this.pixelMap = null;
    CoverCache.fetch(url).then((pixelMap: PixelMap | null): void => {
      // @Prop 可能已重同步到另一首歌，过期响应直接丢弃。
      if (pixelMap !== null && this.requestedUrl === url) {
        this.pixelMap = pixelMap;
      }
    });
  }

  build() {
    if (this.pixelMap !== null) {
      Image(this.pixelMap)
        .width(this.sideVp)
        .height(this.sideVp)
        .borderRadius(this.radiusVp)
        .objectFit(ImageFit.Cover)
    } else {
      // 加载中占位：与旧 Image(src).backgroundColor 同观感的纯底色块。
      Column()
        .width(this.sideVp)
        .height(this.sideVp)
        .borderRadius(this.radiusVp)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
    }
  }
}
