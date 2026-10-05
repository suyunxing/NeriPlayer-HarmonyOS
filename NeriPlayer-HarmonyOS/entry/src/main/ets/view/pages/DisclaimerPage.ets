// SPDX-License-Identifier: GPL-3.0

import { common } from '@kit.AbilityKit';
import { Logger } from '../../app/Logger';
import { Constants } from '../../app/Constants';
import { Theme } from '../Theme';
import { BAND_BUTTON_VP, BAND_TEXT_VP, BP_LG, BP_MD } from '../../util/Breakpoint';
import { openExternalLink } from '../../util/LinkLauncher';

/**
 * 首启合规页。
 *
 * 指南要求首次启动的隐私弹窗必须提供「不同意」选项，且不同意之后要么进入访客
 * 或受限模式继续，要么礼貌退出 —— 不允许反复弹窗，也不允许强行退出后再提示
 * 「请同意后继续」。本应用的在线能力全部依赖网络与第三方平台授权，没有可用的
 * 受限模式，因此按礼貌退出处理：二次确认后调用 terminateSelf()。
 *
 * 《隐私政策》《用户协议》正文托管在应用外（GitHub Gist，母本与修订流程见仓库
 * docs/legal/README.md；2026-10-05 起取消应用内离线渲染页 LegalDocPage），文字链
 * 经系统浏览器打开，阅读依赖网络。
 */
@Component
export struct DisclaimerPage {
  onAgree: () => void = () => {};
  /** 协议文本较用户上次同意的版本有修订：标题下多一行更新提示。父组件传入状态变量，须用 @Prop 建立单向同步。 */
  @Prop reconfirmAfterUpdate: boolean = false;
  @State countdown: number = 5;
  /**
   * 底部固定按钮区的上抬量，由 util/WindowMetrics.ets 按真实导航指示器避让区
   * 发布；默认值是指南常量，只在还没采到样时短暂生效。
   */
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 由 util/WindowMetrics.ets 发布，决定正文是否竖向居中。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';

  private wideLayout(): boolean {
    return this.breakpoint === BP_MD || this.breakpoint === BP_LG;
  }

  aboutToAppear(): void {
    this.tick();
  }

  private tick(): void {
    const timer = setInterval(() => {
      if (this.countdown > 0) {
        this.countdown -= 1;
      } else {
        clearInterval(timer);
      }
    }, 1000);
  }

  /** 二次确认后退出：避免误触，同时不把「不同意」做成走不通的死路。 */
  private confirmDisagree(): void {
    this.getUIContext().showAlertDialog({
      title: '不同意并退出',
      message: '本应用的在线功能依赖网络与你在第三方平台的账号授权，不同意时无法提供可用的受限模式。点击「退出应用」将结束本次运行，下次启动会再次询问。',
      primaryButton: {
        value: '返回阅读',
        action: (): void => {}
      },
      secondaryButton: {
        value: '退出应用',
        fontColor: Theme.danger(Theme.isDark()),
        action: (): void => {
          this.exitApp();
        }
      }
    });
  }

  private exitApp(): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined || context === null) {
      Logger.warn('disclaimer: ability context unavailable, cannot terminate');
      return;
    }
    context.terminateSelf().catch((error: Error) => {
      Logger.warn(`disclaimer: terminateSelf failed: ${error.message}`);
    });
  }

  /** 打开托管的法律文档：拉起系统浏览器；失败只记日志，不打断合规流程。 */
  private openDoc(url: string): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined || context === null) {
      Logger.warn('disclaimer: ability context unavailable, cannot open legal doc');
      return;
    }
    openExternalLink(context, url);
  }

  @Builder
  docLink(label: string, url: string) {
    Text(label)
      .fontSize(13)
      .fontColor(Theme.primary(Theme.isDark()))
      .decoration({ type: TextDecorationType.Underline, color: Theme.primary(Theme.isDark()) })
      // 纯文字入口也要够点：40vp 是本移植版守的触控下限。
      .height(40)
      .padding({ left: 4, right: 4 })
      .onClick(() => {
        this.openDoc(url);
      })
  }

  build() {
    // 600vp 正文栏宽 + 居中：这是首启第一屏，tablet 上原本一行排七八十个字。
    Row() {
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            Text('免责声明 / Disclaimer')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            if (this.reconfirmAfterUpdate) {
              Text('《隐私政策》与《用户协议》已更新，请重新阅读并确认。')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.primary(Theme.isDark()))
            }
            Text('本项目仅供学习与研究使用，请勿用于任何非法用途。')
              .fontSize(15)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            Text('本项目不提供公共云端曲库或媒体分发服务。在线音频能力依赖您在第三方平台的账号授权；VIP 或受限内容仍遵循原平台规则。')
              .fontSize(14)
              .fontColor(Theme.textSecondary(Theme.isDark()))
            Text('第三方平台日志与风控策略由对应平台按其自身隐私政策处理。请合理配置代理规则。')
              .fontSize(14)
              .fontColor(Theme.textSecondary(Theme.isDark()))
            Text('本应用不收集你的个人信息，不内置统计、广告或崩溃上报组件；登录凭据只保存在本机的系统级密钥库中。详见下列文档。')
              .fontSize(14)
              .fontColor(Theme.textSecondary(Theme.isDark()))

            Row({ space: 8 }) {
              this.docLink('《隐私政策》', Constants.LEGAL_PRIVACY_URL)
              Text('·')
                .fontSize(13)
                .fontColor(Theme.textDisabled(Theme.isDark()))
              this.docLink('《用户协议》', Constants.LEGAL_AGREEMENT_URL)
            }
            .width('100%')

            Text('点击「我已阅读并同意」表示你已阅读并接受上述免责声明、《隐私政策》与《用户协议》。')
              .fontSize(12)
              .fontColor(Theme.textDisabled(Theme.isDark()))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(20)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // md/lg 下正文本身撑不满高度，竖向居中比顶着上边缘好看；窄屏保持顶部对齐。
        .align(this.wideLayout() ? Alignment.Center : Alignment.Top)

        Column({ space: 6 }) {
          Button(this.countdown > 0 ? `请阅读免责声明 (${this.countdown})` : '我已阅读并同意')
            .width('90%')
            .constraintSize({ maxWidth: BAND_BUTTON_VP })
            .height(48)
            .enabled(this.countdown === 0)
            .backgroundColor(this.countdown === 0
              ? Theme.primary(Theme.isDark())
              : Theme.surfaceVariant(Theme.isDark()))
            .fontColor(this.countdown === 0
              ? Theme.onPrimary(Theme.isDark())
              : Theme.textDisabled(Theme.isDark()))
            .onClick(() => {
              this.onAgree();
            })
          // 「不同意」必须是一个真实可见、可点的选项，不能藏起来或做成禁用态。
          Button('不同意')
            .width('90%')
            .constraintSize({ maxWidth: BAND_BUTTON_VP })
            .height(48)
            .backgroundColor(Color.Transparent)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .onClick(() => {
              this.confirmDisagree();
            })
        }
        .width('100%')
        // 底部固定按钮区相对系统导航条上抬；有指示器的形态为 28vp，2in1 自由
        // 窗口这类避让区为 0 的形态不再留死区。
        .padding({ bottom: this.bottomLift })
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
