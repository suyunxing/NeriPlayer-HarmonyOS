// SPDX-License-Identifier: GPL-3.0

/** 每轮滚动前在起始位置的停留时长（含挂载与切歌后的首轮展示）。 */
const MARQUEE_HOLD_MS = 2000;

/**
 * 超长单行文本跑马灯，基于 Text 原生 TextOverflow.MARQUEE + marqueeOptions
 * （与官方 animation-collection 示例同源做法，未超宽时静止、超宽时由渲染
 * 引擎无限滚动）。fadeout 由引擎在文字两端做真 alpha 渐隐，毛玻璃等非纯色
 * 背景上也成立，可替代手写离屏 DST_IN 蒙版；文本更新（切歌）后按
 * MarqueeUpdatePolicy.DEFAULT 从头重滚，不停留在上一轮的滚动相位。
 *
 * 「开头停留」节奏：原生 delay 只作用于两轮之间（引擎对首轮启动强制无
 * 延迟），所以首轮与切歌后的那一轮由组件自管——先保持 start=false 静止
 * 在起点，停满 MARQUEE_HOLD_MS 再放行；轮与轮之间的停顿交给原生 delay。
 */
@Component
export struct MarqueeText {
  @Prop @Watch('onTextChange') text: string;
  @Prop fontSize: number = 14;
  @Prop fontWeight: FontWeight = FontWeight.Normal;
  @Prop fontColor: ResourceColor = '#FF000000';
  // 跑马灯放行开关：false 时引擎停在起点（超宽与否由引擎自行判定）。
  @State marqueeRunning: boolean = false;
  private holdTimer: number = -1;

  private scheduleStart(): void {
    if (this.holdTimer >= 0) {
      clearTimeout(this.holdTimer);
      this.holdTimer = -1;
    }
    this.marqueeRunning = false;
    this.holdTimer = setTimeout(() => {
      this.holdTimer = -1;
      this.marqueeRunning = true;
    }, MARQUEE_HOLD_MS);
  }

  // @Watch 初始化不回调：首轮停留由 aboutToAppear 兜底，切歌重置走这里。
  onTextChange(): void {
    this.scheduleStart();
  }

  aboutToAppear(): void {
    this.scheduleStart();
  }

  aboutToDisappear(): void {
    // MiniPlayer 槽位随切 Tab 重建，挂载期未到点的停留定时器必须随组件销毁释放。
    if (this.holdTimer >= 0) {
      clearTimeout(this.holdTimer);
      this.holdTimer = -1;
    }
  }

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontWeight(this.fontWeight)
      .fontColor(this.fontColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.MARQUEE })
      // step 不设走引擎默认 4vp（系统调校的跑马灯速度）；loop -1 无限循环；
      // delay 为轮与轮之间在起点的停顿（首轮启动由 scheduleStart 自管）；
      // fadeout 开启后 clip 被系统锁定，滚动不会溢出组件边界。
      .marqueeOptions({
        start: this.marqueeRunning,
        delay: MARQUEE_HOLD_MS,
        loop: -1,
        fadeout: true,
        marqueeUpdatePolicy: MarqueeUpdatePolicy.DEFAULT
      })
      .width('100%')
  }
}
