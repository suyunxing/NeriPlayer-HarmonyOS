// SPDX-License-Identifier: GPL-3.0

import { promptAction } from '@kit.ArkUI';
import { Theme } from '../Theme';
import { NeteaseLoginResult, NeteasePhoneLoginClient } from '../../network/NeteasePhoneLogin';

/**
 * 网易云手机号登录面板（清单 §3.3，对齐 Android NeteaseLoginContent）：短信验证码
 * 与密码双模式切换、60 秒发送倒计时、脱敏确认弹层。登录成功经 onConfirmed
 * （宿主页保存 cookie）后自动收起。
 */
@Component
export struct NeteasePhoneLoginPanel {
  /** resolve true = 登录成功（宿主页已保存 cookie），面板自动收起。 */
  onConfirmed: (cookies: Map<string, string>) => Promise<boolean> = async (): Promise<boolean> => false;
  @State useCaptcha: boolean = true;
  @State phone: string = '';
  @State code: string = '';
  @State password: string = '';
  @State sending: boolean = false;
  @State loggingIn: boolean = false;
  @State countdownSec: number = 0;
  private countdownTimer: number = -1;

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  private stopCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private digitsOnly(value: string, max: number): string {
    let out = '';
    for (const ch of value) {
      if (ch >= '0' && ch <= '9') {
        out += ch;
      }
      if (out.length >= max) {
        break;
      }
    }
    return out;
  }

  private validPhone(): boolean {
    return this.phone.length === 11;
  }

  private maskedPhone(): string {
    return this.phone.substring(0, 3) + '****' + this.phone.substring(7);
  }

  private startCountdown(): void {
    this.stopCountdown();
    this.countdownSec = 60;
    this.countdownTimer = setInterval(() => {
      this.countdownSec -= 1;
      if (this.countdownSec <= 0) {
        this.stopCountdown();
        this.countdownSec = 0;
      }
    }, 1000);
  }

  private async sendCaptcha(): Promise<void> {
    if (!this.validPhone() || this.sending || this.countdownSec > 0) {
      if (!this.validPhone()) {
        promptAction.openToast({ message: '请输入 11 位手机号' });
      }
      return;
    }
    this.sending = true;
    try {
      const result = await NeteasePhoneLoginClient.sendCaptcha(this.phone, 86);
      if (result.ok) {
        this.startCountdown();
        promptAction.openToast({ message: `验证码已发送至 ${this.maskedPhone()}` });
      } else {
        promptAction.openToast({ message: `发送失败：${result.message.length > 0 ? result.message : `code ${result.code}`}` });
      }
    } catch (error) {
      promptAction.openToast({ message: `发送失败：${(error as Error).message}` });
    } finally {
      this.sending = false;
    }
  }

  private async login(): Promise<void> {
    if (this.loggingIn) {
      return;
    }
    if (!this.validPhone()) {
      promptAction.openToast({ message: '请输入 11 位手机号' });
      return;
    }
    const secret = this.useCaptcha ? this.code : this.password;
    if (secret.length === 0) {
      promptAction.openToast({ message: this.useCaptcha ? '请输入验证码' : '请输入密码' });
      return;
    }
    this.loggingIn = true;
    try {
      const result: NeteaseLoginResult = this.useCaptcha
        ? await NeteasePhoneLoginClient.loginByCaptcha(this.phone, this.code, 86)
        : await NeteasePhoneLoginClient.loginByPassword(this.phone, this.password, 86);
      if (!result.ok) {
        promptAction.openToast({ message: `登录失败：${result.message.length > 0 ? result.message : `code ${result.code}`}` });
        return;
      }
      const saved = await this.onConfirmed(result.cookies);
      if (saved) {
        promptAction.openToast({ message: '网易云登录成功' });
      } else {
        promptAction.openToast({ message: '登录校验失败：未取得有效登录凭据' });
      }
    } catch (error) {
      promptAction.openToast({ message: `登录失败：${(error as Error).message}` });
    } finally {
      this.loggingIn = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('短信验证码')
          .fontSize(13)
          .fontColor(this.useCaptcha ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.useCaptcha ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
          .borderRadius(12)
          .onClick(() => {
            this.useCaptcha = true;
          })
        Text('密码')
          .fontSize(13)
          .fontColor(!this.useCaptcha ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(!this.useCaptcha ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
          .borderRadius(12)
          .onClick(() => {
            this.useCaptcha = false;
          })
      }
      .width('100%')

      TextInput({ placeholder: '手机号', text: this.phone })
        .type(InputType.PhoneNumber)
        .fontSize(14)
        .maxLength(11)
        .width('100%')
        .onChange((value: string) => {
          this.phone = this.digitsOnly(value, 11);
        })

      if (this.useCaptcha) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '验证码', text: this.code })
            .type(InputType.Number)
            .fontSize(14)
            .maxLength(6)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.code = this.digitsOnly(value, 6);
            })
          Button(this.countdownSec > 0 ? `重新发送(${this.countdownSec}s)` : (this.sending ? '发送中...' : '获取验证码'))
            .fontSize(12)
            .enabled(this.countdownSec === 0 && !this.sending && this.validPhone())
            .fontColor(Theme.onPrimary(Theme.isDark()))
            .backgroundColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.sendCaptcha())
        }
        .width('100%')
      } else {
        TextInput({ placeholder: '密码', text: this.password })
          .type(InputType.Password)
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.password = value;
          })
      }

      Button(this.loggingIn ? '登录中...' : '登录')
        .height(40)
        .fontSize(14)
        .width('100%')
        .enabled(!this.loggingIn)
        .fontColor(Theme.onPrimary(Theme.isDark()))
        .backgroundColor(Theme.primary(Theme.isDark()))
        .onClick(() => this.login())

      Text('登录凭据仅保存在本机安全存储；密码以 MD5 摘要形式传输（网易云登录协议要求）')
        .fontSize(11)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Theme.surface(Theme.isDark()))
  }
}
