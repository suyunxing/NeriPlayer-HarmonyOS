// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics } from '@kit.ArkUI';
import { Theme } from '../Theme';
import { coverThumbnailUrl } from '../../util/CoverUrls';

/**
 * S5: 三张歌单页（本地 / 网易云 / B 站收藏夹）共用的参考图头部：
 * 120vp 大封面(radius 20) + 24fp 两行粗标题 + 副标题 + 调用方自带的操作
 * pills（各页动作不同：导入/添加/管理由 @BuilderParam 注入）。
 * 透明底，列表直接坐在页面背景上。
 */

/** 头部操作 pill：filled=重点色实心（全部播放），否则中性表面色。 */
@Component
export struct HeaderPill {
  @Prop label: string = '';
  @Prop filled: boolean = false;
  onTap: () => void = () => {};

  build() {
    Button(this.label)
      .height(40)
      .fontSize(13)
      .fontColor(this.filled ? Theme.onPrimary(Theme.isDark()) : Theme.textPrimary(Theme.isDark()))
      .backgroundColor(this.filled ? Theme.primary(Theme.isDark()) : Theme.surfaceVariant(Theme.isDark()))
      .borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => this.onTap())
  }
}

@Component
export struct PlaylistHeader {
  /** 封面 URL；空串渲染音符占位。 */
  @Prop coverUrl: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 各页自己的操作 pills（HeaderPill 组合）。 */
  @BuilderParam actions: () => void = emptyActions;
  onTap: () => void = () => {};

  build() {
    Row({ space: 16 }) {
      if (this.coverUrl.length > 0) {
        Image(coverThumbnailUrl(this.coverUrl, 400))
          .autoResize(true)
          .width(120)
          .height(120)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      } else {
        Column() {
          Image($r('app.media.ic_music_note_24'))
            .width(40)
            .height(40)
            .fillColor(Theme.primary(Theme.isDark()))
        }
        .width(120)
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .borderRadius(20)
      }

      Column({ space: 8 }) {
        Text(this.title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(14)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        // Flex wrap：1.45x 系统字体下第三个 pill 会溢出右边缘（设备审计
        // 2026-08-24），换行保住可点性。
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          this.actions()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onTap())
  }
}

@Builder
function emptyActions() {
}
