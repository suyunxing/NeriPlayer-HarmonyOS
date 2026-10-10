// SPDX-License-Identifier: GPL-3.0

import { Theme } from '../Theme';

/**
 * F-10 删除撤销横幅（上游 90ee4f46 PlaylistDeleteFeedback 的鸿蒙对应物：
 * Android snackbar-with-action 在鸿蒙侧没有系统件，用页面内底部浮层）。
 * 宿主控制 visible；出现时起 UNDO_TTL_MS 倒计时，到点回调 onExpire 由
 * 宿主收起并清理载荷。撤销按钮回调 onUndo。
 */
@Component
export struct UndoBanner {
  @Prop @Watch('onVisibleChanged') message: string = '';
  @Prop visible: boolean = false;
  onUndo: () => void = () => {};
  onExpire: () => void = () => {};

  private timerId: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private onVisibleChanged(): void {
    this.clearTimer();
    if (this.visible && this.message.length > 0) {
      this.timerId = setTimeout(() => {
        this.timerId = -1;
        this.onExpire();
      }, 6000);
    }
  }

  build() {
    if (this.visible && this.message.length > 0) {
      Row({ space: 12 }) {
        Text(this.message)
          .fontSize(14)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('撤销')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.primary(Theme.isDark()))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.clearTimer();
            this.onUndo();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 12 })
      .backgroundColor(Theme.surfaceHigh(Theme.isDark()))
      .borderRadius(14)
      .shadow(Theme.shadow(Theme.isDark()))
      .margin({ left: 16, right: 16, bottom: 12 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 160 }).combine(
        TransitionEffect.translate({ y: 24 }).animation({ duration: 160 })))
    }
  }
}
