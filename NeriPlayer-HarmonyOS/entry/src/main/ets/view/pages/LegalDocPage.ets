// SPDX-License-Identifier: GPL-3.0

import { Theme } from '../Theme';
import { BAND_TEXT_VP } from '../../util/Breakpoint';
import { util } from '@kit.ArkTS';
import { Router } from '../Router';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

export const LEGAL_PRIVACY: string = 'privacy';
export const LEGAL_AGREEMENT: string = 'agreement';

/**
 * 隐私政策 / 用户协议阅读页。
 *
 * 正文放在 resources/rawfile/ 下的 Markdown 文件里（privacy_policy.md /
 * user_agreement.md），aboutToAppear 时经 getRawFileContent 异步读入——离线
 * 也能完整打开，指南要求首启弹窗链接到的隐私政策与用户协议必须真的能打
 * 开，而不是一个点不动或加载不出来的外链。文案定稿直接改 rawfile 的
 * .md 文件（将来上 AGC 时同一份文件复制到后台上传），不再改 string.json。
 *
 * 两种用法：
 *   * 首启免责声明页内的浮层（DisclaimerPage，onClose 收起浮层；页内自绘
 *     返回头部，不走导航栈）
 *   * 设置页的全屏路由（MainShell 传 asRoute: true；根为 HdsNavDestination，
 *     标题栏返回键自动出栈，与其它二、三级页同为渐变模糊沉浸标题栏）
 */
@Component
export struct LegalDocPage {
  @Prop doc: string = LEGAL_PRIVACY;
  /** 全屏路由用法（MainShell pageMap）：根节点换 HdsNavDestination。 */
  @Prop asRoute: boolean = false;
  onClose: () => void = () => {};
  /** 正文收尾留白，跟随真实导航指示器避让区（见 util/WindowMetrics.ets）。 */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State private bodyText: string = '';
  @State private loadFailed: boolean = false;
  /** 供 HdsNavDestination.bindToScrollable 绑定的正文滚动控制器。 */
  private scroller: Scroller = new Scroller();

  private title(): Resource {
    return this.doc === LEGAL_AGREEMENT
      ? $r('app.string.user_agreement_title')
      : $r('app.string.privacy_policy_title');
  }

  private rawFileName(): string {
    return this.doc === LEGAL_AGREEMENT ? 'user_agreement.md' : 'privacy_policy.md';
  }

  aboutToAppear(): void {
    this.loadBody();
  }

  private async loadBody(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) {
        this.loadFailed = true;
        return;
      }
      const content = await ctx.resourceManager.getRawFileContent(this.rawFileName());
      const text = util.TextDecoder.create('utf-8').decodeToString(content);
      // 去掉首行 Markdown 标题（页面已有标题栏），保留正文原样按 \n 渲染。
      const firstNewline = text.indexOf('\n');
      this.bodyText = firstNewline >= 0 ? text.slice(firstNewline + 1).trim() : text.trim();
    } catch (e) {
      this.loadFailed = true;
    }
  }

  /** 正文（两种用法共用）：600vp 栏宽内的滚动文本。 */
  @Builder
  body() {
    // 600vp 正文栏宽：tablet 1440vp 下这段隐私政策一行能排七八十个字，读起来
    // 要横扫整块屏。标题栏与正文一起被约束，两者左边缘才对得上。
    Row() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Text($r('app.string.legal_draft_notice'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(Theme.warning(Theme.isDark()))
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .borderRadius(10)
          if (this.loadFailed) {
            Text('文档加载失败，请重启应用重试。')
              .fontSize(14)
              .fontColor(Theme.warning(Theme.isDark()))
              .width('100%')
          } else {
            Text(this.bodyText)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .width('100%')
          }
        }
        .width('100%')
        // 底部固定控件的上抬量同时用作滚动内容的收尾留白，保证最后一段不贴住
        // 导航条；路由态正文延伸进手势条区，多让一层渐变遮罩的高度。
        .padding({ left: 16, right: 16, top: this.asRoute ? this.topInset + SUB_TITLEBAR_SPACE_VP : 0, bottom: this.bottomLift + (this.asRoute ? SUB_BOTTOM_CLEARANCE_VP : 0) })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: BAND_TEXT_VP })
  }

  build() {
    if (this.asRoute) {
      // 全屏路由用法：与其它二、三级页同款 HdsNavDestination 渐变模糊标题栏
      // （返回键自动出栈）；底部手势条区渐变遮罩与页面其余部分一致。
      HdsNavDestination() {
        Stack() {
          Column() {
            this.body()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.background(Theme.isDark()))

          SubPageBottomFade()
        }
        .width('100%')
        .height('100%')
      }
      .titleBar(subPageTitleBar(this.title()))
      .bindToScrollable([this.scroller])
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onWillDisappear(() => {
        Router.notifyReturned();
      })
    } else {
      // 免责声明浮层用法：保持页内自绘返回头部（不在导航栈内，无系统标题栏）。
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

        this.body()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .constraintSize({ maxWidth: BAND_TEXT_VP })
      .backgroundColor(Theme.background(Theme.isDark()))
    }
  }
}
