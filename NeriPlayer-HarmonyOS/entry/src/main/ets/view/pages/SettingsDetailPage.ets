import { promptAction } from '@kit.ArkUI';
import { SettingsRepository } from '../../data/SettingsRepository';
import { DownloadStorage } from '../../download/DownloadStorage';
import { DownloadEngine } from '../../download/DownloadEngine';
import { PlayerManager } from '../../player/PlayerManager';
import { NeteaseCookieRepository } from '../../data/auth/NeteaseCookieRepository';
import { NeteaseQrLoginClient, NeteaseQrSession } from '../../network/NeteaseQrLogin';
import { encodeQr, QrMatrix } from '../../util/QrEncoder';
import { Theme } from '../Theme';
import { SettingRow } from '../components/Ui';
import { SETTING_PLAYBACK, SETTING_DOWNLOAD, SETTING_LYRICS, SETTING_APPEARANCE,
  SETTING_TRAFFIC, SETTING_STORAGE, SETTING_ACCOUNTS, SETTING_SYNC, SETTING_DEBUG,
  SETTING_ABOUT } from './SettingsPage';
import { Router } from '../Router';

const SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const QUALITIES: string[] = ['standard', 'high', 'exhigh', 'lossless', 'hires'];
const QR_POLL_INTERVAL_MS: number = 2000;

@Component
export struct SettingsDetailPage {
  @StorageLink('route.param') section: string = '';

  @StorageProp('np.playback_speed') speed: number = 1.0;
  @StorageProp('np.audio_quality') quality: string = 'standard';
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_offset_ms') lyricOffsetMs: number = 0;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;
  @StorageProp('np.lyric_blur') lyricBlur: boolean = true;
  @StorageProp('np.download_concurrency') downloadConcurrency: number = 6;
  @StorageProp('np.download_match_lyrics') downloadMatchLyrics: boolean = true;
  @StorageProp('np.save_traffic') saveTraffic: boolean = false;
  @StorageProp('np.netease_auto_fallback') neteaseAutoFallback: boolean = true;
  @StorageProp('np.cover_policy') coverPolicy: string = 'always';
  @StorageProp('np.always_record_logs') alwaysRecordLogs: boolean = false;
  @StorageLink('np.netease_logged') neteaseLogged: boolean = false;

  @State cacheBytes: number = 0;
  @State qrPanelOpen: boolean = false;
  @State qrStatus: string = '';
  @State qrBusy: boolean = false;
  @State qrMatrix: QrMatrix | null = null;

  private qrSession: NeteaseQrSession | null = null;
  private qrTimerId: number = -1;
  private qrCanvasCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private pasteDialogController: CustomDialogController | null = null;

  private title(): string {
    if (this.section === SETTING_PLAYBACK) {
      return '播放设置';
    }
    if (this.section === SETTING_DOWNLOAD) {
      return '下载设置';
    }
    if (this.section === SETTING_LYRICS) {
      return '歌词设置';
    }
    if (this.section === SETTING_APPEARANCE) {
      return '外观与动效';
    }
    if (this.section === SETTING_TRAFFIC) {
      return '流量与封面';
    }
    if (this.section === SETTING_STORAGE) {
      return '存储与缓存';
    }
    if (this.section === SETTING_ACCOUNTS) {
      return '账号与登录';
    }
    if (this.section === SETTING_SYNC) {
      return '同步';
    }
    if (this.section === SETTING_DEBUG) {
      return '开发者';
    }
    if (this.section === SETTING_ABOUT) {
      return '关于';
    }
    return '设置';
  }

  async aboutToAppear(): Promise<void> {
    const catalog = await DownloadStorage.getCatalog();
    let bytes = 0;
    for (const entry of catalog) {
      bytes += DownloadStorage.fileSize(entry.audioPath);
    }
    this.cacheBytes = bytes;
  }

  aboutToDisappear(): void {
    this.stopQrPolling();
  }

  // ---- NetEase QR login -------------------------------------------------

  private startNeteaseLogin(): void {
    if (this.qrBusy) {
      return;
    }
    this.qrPanelOpen = true;
    this.qrStatus = '正在生成二维码...';
    this.createQrSession();
  }

  private async createQrSession(): Promise<void> {
    this.qrBusy = true;
    this.stopQrPolling();
    try {
      this.qrSession = await NeteaseQrLoginClient.createSession();
      this.qrMatrix = encodeQr(this.qrSession.qrContent).matrix;
      this.qrStatus = '请用网易云音乐 App 扫码';
      this.drawQr();
      this.qrTimerId = setInterval(() => {
        this.pollQrOnce();
      }, QR_POLL_INTERVAL_MS);
    } catch (error) {
      const e = error as Error;
      this.qrStatus = `二维码创建失败：${e.message}`;
      promptAction.openToast({ message: '二维码创建失败' });
    }
    this.qrBusy = false;
  }

  private async pollQrOnce(): Promise<void> {
    if (this.qrSession === null || this.qrBusy) {
      return;
    }
    this.qrBusy = true;
    try {
      const result = await NeteaseQrLoginClient.checkLogin(this.qrSession);
      if (result.code === 801) {
        this.qrStatus = '请用网易云音乐 App 扫码';
      } else if (result.code === 802) {
        this.qrStatus = '已扫码，请在手机上确认';
      } else if (result.code === 803) {
        const saved = NeteaseCookieRepository.saveFromQrLogin(result.cookies);
        this.stopQrPolling();
        this.qrSession = null;
        if (saved) {
          this.neteaseLogged = true;
          this.qrPanelOpen = false;
          this.qrStatus = '';
          promptAction.openToast({ message: '网易云登录成功' });
        } else {
          this.qrStatus = '登录校验失败，请重试';
        }
      } else if (result.code === 800) {
        this.qrStatus = '二维码已过期，正在刷新...';
        this.stopQrPolling();
        this.createQrSession();
      }
    } catch (error) {
      const e = error as Error;
      this.qrStatus = `轮询失败：${e.message}`;
    }
    this.qrBusy = false;
  }

  private stopQrPolling(): void {
    if (this.qrTimerId >= 0) {
      clearInterval(this.qrTimerId);
      this.qrTimerId = -1;
    }
  }

  private cancelNeteaseLogin(): void {
    this.stopQrPolling();
    this.qrSession = null;
    this.qrMatrix = null;
    this.qrPanelOpen = false;
    this.qrStatus = '';
  }

  private confirmNeteaseLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '确定退出网易云音乐登录？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: Theme.danger(Theme.isDark()),
        action: () => {
          NeteaseCookieRepository.clear();
          this.neteaseLogged = false;
          promptAction.openToast({ message: '已退出网易云登录' });
        }
      }
    });
  }

  private drawQr(): void {
    const m = this.qrMatrix;
    if (m === null) {
      return;
    }
    const ctx = this.qrCanvasCtx;
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

  private openPasteDialog(): void {
    if (this.pasteDialogController === null) {
      this.pasteDialogController = new CustomDialogController({
        builder: PasteCookieDialog({
          onConfirm: (text: string) => {
            const saved = NeteaseCookieRepository.saveFromPastedText(text);
            if (saved) {
              this.neteaseLogged = true;
              promptAction.openToast({ message: 'Cookie 导入成功' });
            } else {
              promptAction.openToast({ message: '导入失败：需要包含有效的 MUSIC_U' });
            }
          }
        }),
        autoCancel: true,
        customStyle: false
      });
    }
    this.pasteDialogController.open();
  }

  private setSpeed(value: number): void {
    SettingsRepository.setNumber(SettingsRepository.KEY_PLAYBACK_SPEED, value);
    PlayerManager.setSpeed(value);
  }

  private adjustLyricOffset(deltaMs: number): void {
    const next = this.lyricOffsetMs + deltaMs;
    SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, next);
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button('‹')
        .width(38)
        .height(38)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .fontSize(20)
        .onClick(() => Router.pop())
      Text(this.title())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
    }
    .width('100%')
    .padding({ left: 8, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  optionRow(label: string, value: string, onTap: () => void) {
    SettingRow({ title: label, subtitle: value, onTap: onTap })
  }

  build() {
    Column() {
      this.header()

      Scroll() {
        Column({ space: 1 }) {
          if (this.section === SETTING_PLAYBACK) {
            Text('播放速度')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 10, bottom: 6 })
            Row({ space: 8 }) {
              ForEach(SPEEDS, (speedValue: number) => {
                Button(speedValue === 1.0 ? '1.0x' : `${speedValue}x`)
                  .height(34)
                  .fontSize(13)
                  .layoutWeight(1)
                  .fontColor(this.speed === speedValue ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
                  .backgroundColor(this.speed === speedValue ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
                  .borderRadius(17)
                  .onClick(() => this.setSpeed(speedValue))
              }, (speedValue: number) => `${speedValue}`)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())

            Text('默认音质')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 1 }) {
              ForEach(QUALITIES, (qualityValue: string) => {
                SettingRow({
                  title: qualityLabel(qualityValue),
                  subtitle: this.quality === qualityValue ? '当前选择' : '',
                  showArrow: false,
                  onTap: () => SettingsRepository.setString(SettingsRepository.KEY_AUDIO_QUALITY, qualityValue)
                })
              }, (qualityValue: string) => qualityValue)
            }
            .width('100%')
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())
            .clip(true)

            SettingRow({
              title: '随机播放',
              subtitle: '在播放页切换，此处仅显示状态',
              icon: '🔀',
              showArrow: false,
              onTap: () => PlayerManager.setShuffle(!AppStorage.get<boolean>('player.shuffle'))
            })
          } else if (this.section === SETTING_DOWNLOAD) {
            Text('下载并发数')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 10, bottom: 6 })
            Row({ space: 8 }) {
              ForEach([1, 2, 4, 6, 8], (concurrency: number) => {
                Button(`${concurrency}`)
                  .height(34)
                  .fontSize(13)
                  .layoutWeight(1)
                  .fontColor(this.downloadConcurrency === concurrency ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
                  .backgroundColor(this.downloadConcurrency === concurrency ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
                  .borderRadius(17)
                  .onClick(() => SettingsRepository.setNumber(SettingsRepository.KEY_DOWNLOAD_CONCURRENCY, concurrency))
              }, (concurrency: number) => `${concurrency}`)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())

            SettingRow({
              title: '下载完成后匹配歌词',
              subtitle: this.downloadMatchLyrics ? '已开启' : '已关闭',
              icon: '♪',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, !this.downloadMatchLyrics)
            })
            SettingRow({
              title: '下载目录',
              subtitle: '应用沙箱 Download 目录（当前版本）',
              icon: '📁',
              onTap: () => promptAction.openToast({ message: '目录选择待移植' })
            })
          } else if (this.section === SETTING_LYRICS) {
            SettingRow({
              title: '歌词字号',
              subtitle: `${this.lyricFontSize} sp`,
              icon: '🔠',
              onTap: () => {
                const next = this.lyricFontSize >= 24 ? 14 : this.lyricFontSize + 2;
                SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_FONT_SIZE, next);
              }
            })
            SettingRow({
              title: '歌词偏移',
              subtitle: this.lyricOffsetMs > 0 ? `提前 ${this.lyricOffsetMs} ms` :
                (this.lyricOffsetMs < 0 ? `延后 ${-this.lyricOffsetMs} ms` : '无偏移'),
              icon: '⏱',
              onTap: () => this.adjustLyricOffset(250)
            })
            Row({ space: 10 }) {
              Button('-250ms')
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .backgroundColor(Theme.surface(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => this.adjustLyricOffset(-250))
              Button('+250ms')
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .backgroundColor(Theme.surface(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => this.adjustLyricOffset(250))
              Button('重置')
                .layoutWeight(1)
                .height(36)
                .fontSize(13)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => SettingsRepository.setNumber(SettingsRepository.KEY_LYRIC_OFFSET_MS, 0))
            }
            .width('100%')
            .padding(10)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())

            SettingRow({
              title: '显示翻译',
              subtitle: this.lyricTranslation ? '已开启' : '已关闭',
              icon: '🌐',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_TRANSLATION, !this.lyricTranslation)
            })
            SettingRow({
              title: '音译显示',
              subtitle: this.lyricPhonetic ? '已开启' : '已关闭',
              icon: '🗣',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_PHONETIC, !this.lyricPhonetic)
            })
            SettingRow({
              title: '歌词模糊效果',
              subtitle: this.lyricBlur ? '已开启' : '已关闭',
              icon: '🌫',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_BLUR, !this.lyricBlur)
            })
          } else if (this.section === SETTING_APPEARANCE) {
            SettingRow({
              title: '语言',
              subtitle: '简体中文（更多语言待移植）',
              icon: '🌐',
              onTap: () => promptAction.openToast({ message: '语言切换待移植' })
            })
            SettingRow({
              title: '高级毛玻璃',
              subtitle: '封面背景模糊（Now Playing）',
              icon: '✨',
              showArrow: false,
              onTap: () => promptAction.openToast({ message: '高级毛玻璃待移植' })
            })
          } else if (this.section === SETTING_TRAFFIC) {
            SettingRow({
              title: '网易失效自动换源',
              subtitle: this.neteaseAutoFallback ? '已开启：网易取流失败时自动匹配 B 站音源' : '已关闭',
              icon: '🔄',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_NETEASE_AUTO_FALLBACK, !this.neteaseAutoFallback)
            })
            SettingRow({
              title: '省流量模式',
              subtitle: this.saveTraffic ? '已开启' : '已关闭',
              icon: '📶',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_SAVE_TRAFFIC, !this.saveTraffic)
            })
            SettingRow({
              title: '封面加载策略',
              subtitle: this.coverPolicy === 'always' ? '始终加载' :
                (this.coverPolicy === 'wifi' ? '仅 Wi-Fi' : '不加载'),
              icon: '🖼',
              onTap: () => {
                const next = this.coverPolicy === 'always' ? 'wifi' : (this.coverPolicy === 'wifi' ? 'off' : 'always');
                SettingsRepository.setString(SettingsRepository.KEY_COVER_POLICY, next);
              }
            })
          } else if (this.section === SETTING_STORAGE) {
            SettingRow({
              title: '缓存占用',
              subtitle: this.cacheBytes > 0 ? `${(this.cacheBytes / 1024 / 1024).toFixed(1)} MB` : '暂无下载缓存',
              icon: '🗄',
              showArrow: false,
              onTap: () => {
              }
            })
            SettingRow({
              title: '清理下载任务',
              subtitle: '清除已完成任务记录',
              icon: '🧹',
              onTap: async () => {
                DownloadEngine.clearFinished();
                promptAction.openToast({ message: '已清除已完成任务' });
                await this.aboutToAppear();
              }
            })
          } else if (this.section === SETTING_ACCOUNTS) {
            SettingRow({
              title: '网易云音乐',
              subtitle: this.neteaseLogged
                ? `已登录 · 凭据存储：${NeteaseCookieRepository.backendName()}`
                : '未登录 · 点击扫码登录',
              icon: '🎵',
              onTap: () => {
                if (this.neteaseLogged) {
                  this.confirmNeteaseLogout();
                } else {
                  this.startNeteaseLogin();
                }
              }
            })
            if (this.qrPanelOpen) {
              Column({ space: 10 }) {
                if (this.qrMatrix !== null) {
                  Canvas(this.qrCanvasCtx)
                    .width(260)
                    .height(260)
                    .backgroundColor('#FFFFFF')
                    .borderRadius(12)
                    .onReady(() => {
                      this.drawQr();
                    })
                }
                Text(this.qrStatus)
                  .fontSize(13)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .textAlign(TextAlign.Center)
                Row({ space: 10 }) {
                  Button('刷新')
                    .height(36)
                    .fontSize(13)
                    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .onClick(() => this.createQrSession())
                  Button('取消')
                    .height(36)
                    .fontSize(13)
                    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .onClick(() => this.cancelNeteaseLogin())
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor(Theme.surface(Theme.isDark()))
              .borderRadius(Theme.cardRadius())
              .alignItems(HorizontalAlign.Center)
              .margin({ bottom: 8 })
            }
            SettingRow({
              title: '粘贴 Cookie 导入（网易云）',
              subtitle: '扫码不可用时的备用登录方式',
              icon: '📋',
              onTap: () => this.openPasteDialog()
            })
            SettingRow({
              title: 'Bilibili',
              subtitle: '未登录 · 二维码登录待移植',
              icon: '📺',
              onTap: () => promptAction.openToast({ message: 'Bilibili 登录待移植' })
            })
            SettingRow({
              title: 'YouTube',
              subtitle: '未登录 · Cookie 会话待移植',
              icon: '▶',
              onTap: () => promptAction.openToast({ message: 'YouTube 登录待移植' })
            })
          } else if (this.section === SETTING_SYNC) {
            SettingRow({
              title: 'GitHub 同步',
              subtitle: '自建私有仓库元数据同步（待移植）',
              icon: '🐙',
              onTap: () => promptAction.openToast({ message: 'GitHub 同步待移植' })
            })
            SettingRow({
              title: 'WebDAV 同步',
              subtitle: '远端文件元数据同步（待移植）',
              icon: '🗂',
              onTap: () => promptAction.openToast({ message: 'WebDAV 同步待移植' })
            })
            SettingRow({
              title: '一起听服务器',
              subtitle: '自定义服务器地址（待移植）',
              icon: '👥',
              onTap: () => promptAction.openToast({ message: 'Listen Together 待移植' })
            })
          } else if (this.section === SETTING_DEBUG) {
            SettingRow({
              title: '始终记录日志',
              subtitle: this.alwaysRecordLogs ? '已开启' : '已关闭',
              icon: '📝',
              showArrow: false,
              onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_ALWAYS_RECORD_LOGS, !this.alwaysRecordLogs)
            })
            SettingRow({
              title: '打开调试工具',
              subtitle: 'API 探测、播放统计与崩溃模拟',
              icon: '🔧',
              onTap: () => Router.push(Router.DEBUG)
            })
          } else if (this.section === SETTING_ABOUT) {
            Column({ space: 8 }) {
              Text('NeriPlayer')
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .margin({ top: 20 })
              Text('欢迎回来！')
                .fontSize(15)
                .fontColor(Theme.textSecondary(Theme.isDark()))
              Text('版本 1.0.0 (HarmonyOS 6.1.1 / API 24)')
                .fontSize(13)
                .fontColor(Theme.textDisabled(Theme.isDark()))
              Text('多源在线播放：网易云 / Bilibili / YouTube Music；本地音乐、歌词、歌单与统计。\n本项目仅供学习与研究使用，请勿用于任何非法用途。')
                .fontSize(13)
                .fontColor(Theme.textSecondary(Theme.isDark()))
                .textAlign(TextAlign.Center)
                .margin({ top: 10 })
              Text('GPL-3.0 · github.com/cwuom/NeriPlayer')
                .fontSize(12)
                .fontColor(Theme.primary(Theme.isDark()))
                .margin({ top: 6 })
            }
            .width('100%')
            .padding(20)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}

function qualityLabel(quality: string): string {
  if (quality === 'standard') {
    return '标准';
  }
  if (quality === 'high') {
    return '较高';
  }
  if (quality === 'exhigh') {
    return '极高';
  }
  if (quality === 'lossless') {
    return '无损';
  }
  return 'Hi-Res';
}

@CustomDialog
struct PasteCookieDialog {
  controller?: CustomDialogController;
  @State cookieText: string = '';
  onConfirm: (text: string) => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Text('粘贴网易云 Cookie')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text('从浏览器或 Android 端导出的 Cookie 文本，需包含 MUSIC_U。格式：k1=v1; k2=v2')
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
      TextArea({ placeholder: 'MUSIC_U=...; __csrf=...; os=pc', text: this.cookieText })
        .height(110)
        .fontSize(13)
        .onChange((value: string) => {
          this.cookieText = value;
        })
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button('导入')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .fontColor(Theme.onPrimary(Theme.isDark()))
          .onClick(() => {
            this.onConfirm(this.cookieText);
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('92%')
  }
}
