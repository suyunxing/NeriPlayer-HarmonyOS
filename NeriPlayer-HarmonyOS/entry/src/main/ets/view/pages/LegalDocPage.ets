// SPDX-License-Identifier: GPL-3.0

import { Theme } from '../Theme';
import { BAND_TEXT_VP } from '../../util/Breakpoint';

export const LEGAL_PRIVACY: string = 'privacy';
export const LEGAL_AGREEMENT: string = 'agreement';

/**
 * 隐私政策 / 用户协议阅读页。
 *
 * 正文放在 resources 的 string.json 里（段落之间用 \n 分隔，Text 直接渲染换
 * 行），所以离线也能完整打开 —— 指南要求首启弹窗链接到的隐私政策与用户协议
 * 必须真的能打开，而不是一个点不动或加载不出来的外链。
 *
 * 两种用法：
 *   * 首启免责声明页内的浮层（DisclaimerPage，onClose 收起浮层）
 *   * 设置页的全屏路由（MainShell，onClose 走 Router.pop）
 */
@Component
export struct LegalDocPage {
  @Prop doc: string = LEGAL_PRIVACY;
  onClose: () => void = () => {};
  /** 正文收尾留白，跟随真实导航指示器避让区（见 util/WindowMetrics.ets）。 */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();

  private title(): Resource {
    return this.doc === LEGAL_AGREEMENT
      ? $r('app.string.user_agreement_title')
      : $r('app.string.privacy_policy_title');
  }

  private body(): Resource {
    return this.doc === LEGAL_AGREEMENT
      ? $r('app.string.user_agreement_body')
      : $r('app.string.privacy_policy_body');
  }

  build() {
    // 600vp 正文栏宽：tablet 1440vp 下这段隐私政策一行能排七八十个字，读起来
    // 要横扫整块屏。标题栏与正文一起被约束，两者左边缘才对得上。
    Row() {
    Column() {
      Row({ space: 6 }) {
        Button() {
          Image($r('app.media.ic_arrow_back_24'))
            .width(22)
            .height(22)
            .fillColor(Theme.textPrimary(Theme.isDark()))
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick(() => this.onClose())

        Text(this.title())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 6, bottom: 6 })

      Scroll() {
        Column({ space: 12 }) {
          Text($r('app.string.legal_draft_notice'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(Theme.warning(Theme.isDark()))
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .borderRadius(10)
          Text(this.body())
            .fontSize(14)
            .lineHeight(22)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .width('100%')
        }
        .width('100%')
        // 底部固定控件的上抬量同时用作滚动内容的收尾留白，保证最后一段不贴住
        // 导航条。
        .padding({ left: 16, right: 16, bottom: this.bottomLift })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: BAND_TEXT_VP })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
