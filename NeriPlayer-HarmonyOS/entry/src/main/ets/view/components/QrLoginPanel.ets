// SPDX-License-Identifier: GPL-3.0

import { promptAction } from '@kit.ArkUI';
import { encodeQr, QrMatrix } from '../../util/QrEncoder';
import { Theme } from '../Theme';

/**
 * Normalized QR poll outcome so the shared panel stays platform-agnostic;
 * platform clients map their own status codes (NetEase 801/802/803/800,
 * Bilibili 86101/86090/0/86038) into these values.
 */
export enum QrPollOutcomeCode {
  WAITING = 0,
  SCANNED = 1,
  CONFIRMED = 2,
  EXPIRED = 3
}

/** Platform session handle; `token` carries opaque platform payload (e.g. NetEase chainId). */
export class QrLoginSessionRef {
  key: string = '';
  qrContent: string = '';
  token: string = '';
}

export class QrPollOutcome {
  code: QrPollOutcomeCode = QrPollOutcomeCode.WAITING;
  message: string = '';
}

/** Lets the host page open/close the panel imperatively. */
export class QrLoginPanelController {
  open: () => void = () => {
  };
  close: () => void = () => {
  };
}

/**
 * Shared QR login panel: renders the QR canvas, drives the create/poll state
 * machine (waiting -> scanned -> confirmed / expired -> auto refresh), and
 * delegates platform work through callbacks. Extracted from the former
 * inline NetEase panel in SettingsDetailPage.
 */
@Component
export struct QrLoginPanel {
  controller: QrLoginPanelController | null = null;
  createSession: () => Promise<QrLoginSessionRef> = async (): Promise<QrLoginSessionRef> => new QrLoginSessionRef();
  pollSession: (session: QrLoginSessionRef) => Promise<QrPollOutcome> =
    async (_session: QrLoginSessionRef): Promise<QrPollOutcome> => new QrPollOutcome();
  /**
   * Called on CONFIRMED; resolve true when the cookies were saved (closes the
   * panel). Async because persistence must settle before success is reported.
   */
  onConfirmed: () => Promise<boolean> = async (): Promise<boolean> => false;
  scanHint: string = '请扫码';
  scannedHint: string = '已扫码，请在手机上确认';
  confirmFailedText: string = '登录校验失败，请重试';
  expiredText: string = '二维码已过期，正在刷新...';
  pollIntervalMs: number = 2000;

  @State panelOpen: boolean = false;
  @State status: string = '';
  @State busy: boolean = false;
  @State matrix: QrMatrix | null = null;

  private session: QrLoginSessionRef | null = null;
  private timerId: number = -1;
  private canvasCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    if (this.controller !== null) {
      this.controller.open = (): void => {
        this.start();
      };
      this.controller.close = (): void => {
        this.cancel();
      };
    }
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private start(): void {
    if (this.busy) {
      return;
    }
    this.panelOpen = true;
    this.status = '正在生成二维码...';
    this.createQrSession();
  }

  private async createQrSession(): Promise<void> {
    this.busy = true;
    this.stopPolling();
    try {
      const session = await this.createSession();
      this.session = session;
      this.matrix = encodeQr(session.qrContent).matrix;
      this.status = this.scanHint;
      this.drawQr();
      this.timerId = setInterval(() => {
        this.pollOnce();
      }, this.pollIntervalMs);
    } catch (error) {
      const e = error as Error;
      this.status = `二维码创建失败：${e.message}`;
      promptAction.openToast({ message: '二维码创建失败' });
    }
    this.busy = false;
  }

  private async pollOnce(): Promise<void> {
    const session = this.session;
    if (session === null || this.busy) {
      return;
    }
    this.busy = true;
    try {
      const outcome = await this.pollSession(session);
      if (outcome.code === QrPollOutcomeCode.WAITING) {
        this.status = this.scanHint;
      } else if (outcome.code === QrPollOutcomeCode.SCANNED) {
        this.status = this.scannedHint;
      } else if (outcome.code === QrPollOutcomeCode.CONFIRMED) {
        this.stopPolling();
        this.session = null;
        if (await this.onConfirmed()) {
          this.panelOpen = false;
          this.status = '';
        } else {
          this.status = this.confirmFailedText;
        }
      } else if (outcome.code === QrPollOutcomeCode.EXPIRED) {
        this.status = this.expiredText;
        this.stopPolling();
        this.createQrSession();
      }
    } catch (error) {
      const e = error as Error;
      this.status = `轮询失败：${e.message}`;
    }
    this.busy = false;
  }

  private stopPolling(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private cancel(): void {
    this.stopPolling();
    this.session = null;
    this.matrix = null;
    this.panelOpen = false;
    this.status = '';
  }

  private drawQr(): void {
    const m = this.matrix;
    if (m === null) {
      return;
    }
    const ctx = this.canvasCtx;
    const canvasSize = 260;
    const scale = Math.floor(canvasSize / (m.size + 8)); // include quiet zone
    const offset = Math.floor((canvasSize - m.size * scale) / 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, canvasSize, canvasSize);
    ctx.fillStyle = '#000000';
    for (let i = 0; i < m.size; i++) {
      for (let j = 0; j < m.size; j++) {
        if (m.isDark(i, j)) {
          ctx.fillRect(offset + j * scale, offset + i * scale, scale, scale);
        }
      }
    }
  }

  build() {
    if (this.panelOpen) {
      Column({ space: 10 }) {
        if (this.matrix !== null) {
          Canvas(this.canvasCtx)
            .width(260)
            .height(260)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .onReady(() => {
              this.drawQr();
            })
        }
        Text(this.status)
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .textAlign(TextAlign.Center)
        Row({ space: 10 }) {
          Button('刷新')
            .height(40)
            .fontSize(13)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => this.createQrSession())
          Button('取消')
            .height(40)
            .fontSize(13)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => this.cancel())
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius(Theme.cardRadius())
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 8 })
    }
  }
}
