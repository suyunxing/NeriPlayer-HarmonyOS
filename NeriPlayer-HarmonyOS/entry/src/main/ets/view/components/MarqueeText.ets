// SPDX-License-Identifier: GPL-3.0

/**
 * 超长单行文本跑马灯，基于 Text 原生 TextOverflow.MARQUEE + marqueeOptions
 * （与官方 animation-collection 示例同源做法，未超宽时静止、超宽时由渲染
 * 引擎无限滚动）。fadeout 由引擎在文字两端做真 alpha 渐隐，毛玻璃等非纯色
 * 背景上也成立，可替代手写离屏 DST_IN 蒙版；文本更新（切歌）后按
 * MarqueeUpdatePolicy.DEFAULT 从头重滚，不停留在上一轮的滚动相位。
 */
@Component
export struct MarqueeText {
  @Prop text: string;
  @Prop fontSize: number = 14;
  @Prop fontWeight: FontWeight = FontWeight.Normal;
  @Prop fontColor: ResourceColor = '#FF000000';

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontWeight(this.fontWeight)
      .fontColor(this.fontColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.MARQUEE })
      // step 不设走引擎默认 4vp（系统调校的跑马灯速度）；loop -1 无限循环；
      // fadeout 开启后 clip 被系统锁定，滚动不会溢出组件边界。
      .marqueeOptions({
        start: true,
        loop: -1,
        fadeout: true,
        marqueeUpdatePolicy: MarqueeUpdatePolicy.DEFAULT
      })
      .width('100%')
  }
}
