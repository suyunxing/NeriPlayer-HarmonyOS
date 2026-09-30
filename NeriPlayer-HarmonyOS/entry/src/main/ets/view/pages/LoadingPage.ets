// SPDX-License-Identifier: GPL-3.0

import { Constants } from '../../app/Constants';
import { Theme } from '../Theme';

/**
 * Bridges the system launch page and the first real frame. The background is
 * the same resource startWindowBackground uses (the icon backplate), so the
 * handover shows no colour flash — which also means this page is always
 * light-on-dark and must not follow the light palette.
 */
@Component
export struct LoadingPage {
  build() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_neriplayer'))
        .width(96)
        .height(96)
      Text(Constants.APP_NAME)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(true))
      // The dark-mode accent is a light tone by construction (M3 tone 80), so
      // it stays legible on the fixed dark backplate even under dynamic color.
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Theme.primary(true))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.start_window_background'))
  }
}
