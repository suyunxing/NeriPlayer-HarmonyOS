import { promptAction } from '@kit.ArkUI';
import { SettingsRepository } from '../../data/SettingsRepository';
import { DownloadStorage } from '../../download/DownloadStorage';
import { DownloadEngine } from '../../download/DownloadEngine';
import { PlayerManager } from '../../player/PlayerManager';
import { NeteaseCookieRepository } from '../../data/auth/NeteaseCookieRepository';
import { BiliCookieRepository } from '../../data/auth/BiliCookieRepository';
import {
  NeteaseQrLoginClient,
  NeteaseQrSession,
  NETEASE_QR_CONFIRMED,
  NETEASE_QR_EXPIRED,
  NETEASE_QR_SCANNED,
  NETEASE_QR_WAITING
} from '../../network/NeteaseQrLogin';
import {
  BiliQrLoginClient,
  BiliQrSession,
  BILI_QR_CONFIRMED,
  BILI_QR_EXPIRED,
  BILI_QR_SCANNED,
  BILI_QR_WAITING
} from '../../network/BiliQrLogin';
import {
  QrLoginPanel,
  QrLoginPanelController,
  QrLoginSessionRef,
  QrPollOutcome,
  QrPollOutcomeCode
} from '../components/QrLoginPanel';
import { Theme } from '../Theme';
import { SettingRow } from '../components/Ui';
import { SETTING_PLAYBACK, SETTING_DOWNLOAD, SETTING_LYRICS, SETTING_APPEARANCE,
  SETTING_TRAFFIC, SETTING_STORAGE, SETTING_ACCOUNTS, SETTING_SYNC, SETTING_DEBUG,
  SETTING_ABOUT } from './SettingsPage';
import { Router } from '../Router';
import { GitHubConfigRepository } from '../../sync/github/GitHubConfigRepository';
import { GitHubTransport, isValidGitHubName } from '../../sync/github/GitHubTransport';
import { OhosGhExecutor } from '../../sync/github/OhosGhExecutor';
import { GitHubSyncClient } from '../../sync/github/GitHubSyncClient';
import { GitHubApiError, GitHubErrorKind } from '../../sync/github/GitHubErrors';
import { deserializeSyncContent, getSyncFileName } from '../../sync/SyncDataJsonCodec';
import { WebDavConfigRepository } from '../../sync/webdav/WebDavConfigRepository';
import {
  WebDavSyncClient,
  WebDavTransport
} from '../../sync/webdav/WebDavTransport';
import { OhosWebDavExecutor } from '../../sync/webdav/OhosWebDavExecutor';
import { WebDavError, WebDavErrorKind } from '../../sync/webdav/WebDavErrors';
import { SyncService } from '../../sync/SyncService';
import { SyncReport } from '../../sync/SyncReport';
import { ListenTogetherApi } from '../../listentogether/network/ListenTogetherApi';
import { LISTEN_TOGETHER_TEST_INVALID_RESPONSE } from '../../listentogether/network/ListenTogetherApiRequests';
import { listenTogetherSavedCustomServer } from '../../listentogether/network/ListenTogetherServerSetting';
import {
  listenTogetherServerInput,
  saveListenTogetherServer
} from '../../listentogether/settings/ListenTogetherServerPreferences';
import {
  configuredListenTogetherBaseUrlOrNull,
  isDefaultListenTogetherBaseUrl,
  resolveListenTogetherBaseUrl
} from '../../listentogether/invite/ListenTogetherBaseUrlResolver';

const SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const QUALITIES: string[] = ['standard', 'high', 'exhigh', 'lossless', 'hires'];
const NETEASE_QR_POLL_INTERVAL_MS: number = 2000;
const BILI_QR_POLL_INTERVAL_MS: number = 1500;

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
  @StorageLink('np.bilibili_logged') biliLogged: boolean = false;

  @StorageProp('np.github_owner') githubOwner: string = '';
  @StorageProp('np.github_repo') githubRepo: string = '';
  @StorageProp('np.github_data_saver') githubDataSaver: boolean = false;
  @State githubTokenSaved: boolean = false;
  @State githubBusy: boolean = false;

  @StorageProp('np.webdav_server_url') webdavServerUrl: string = '';
  @StorageProp('np.webdav_base_path') webdavBasePath: string = '';
  @State webdavCredentialsSaved: boolean = false;
  @State webdavBusy: boolean = false;

  // Only the dialed address is mirrored here; the dialog reads its own prefill
  // from the settings store so a reopened dialog is never stale.
  @StorageProp('np.listen_together_server') listenTogetherServer: string = '';

  @State cacheBytes: number = 0;

  private neteaseQrController: QrLoginPanelController = new QrLoginPanelController();
  private biliQrController: QrLoginPanelController = new QrLoginPanelController();
  private neteasePasteController: CustomDialogController | null = null;
  private biliPasteController: CustomDialogController | null = null;
  private githubConfigController: CustomDialogController | null = null;
  private webdavConfigController: CustomDialogController | null = null;
  private listenTogetherServerController: CustomDialogController | null = null;

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
    await GitHubConfigRepository.init();
    this.githubTokenSaved = GitHubConfigRepository.tokenPreview().length > 0;
    await WebDavConfigRepository.init();
    this.webdavCredentialsSaved = WebDavConfigRepository.isConfigured();
  }

  // ---- NetEase QR login (state machine lives in QrLoginPanel) ------------

  private async createNeteaseQrSession(): Promise<QrLoginSessionRef> {
    const session = await NeteaseQrLoginClient.createSession();
    const ref = new QrLoginSessionRef();
    ref.key = session.key;
    ref.qrContent = session.qrContent;
    ref.token = session.chainId;
    return ref;
  }

  private async pollNeteaseQr(session: QrLoginSessionRef): Promise<QrPollOutcome> {
    const native = new NeteaseQrSession();
    native.key = session.key;
    native.qrContent = session.qrContent;
    native.chainId = session.token;
    const result = await NeteaseQrLoginClient.checkLogin(native);
    const outcome = new QrPollOutcome();
    outcome.message = result.message;
    if (result.code === NETEASE_QR_SCANNED) {
      outcome.code = QrPollOutcomeCode.SCANNED;
    } else if (result.code === NETEASE_QR_CONFIRMED) {
      outcome.code = QrPollOutcomeCode.CONFIRMED;
    } else if (result.code === NETEASE_QR_EXPIRED) {
      outcome.code = QrPollOutcomeCode.EXPIRED;
    } else {
      outcome.code = QrPollOutcomeCode.WAITING;
    }
    return outcome;
  }

  private onNeteaseConfirmed(): boolean {
    const saved = NeteaseCookieRepository.saveFromQrLogin(NeteaseQrLoginClient.currentCookies());
    if (saved) {
      this.neteaseLogged = true;
      promptAction.openToast({ message: '网易云登录成功' });
    }
    return saved;
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

  private openNeteasePasteDialog(): void {
    if (this.neteasePasteController === null) {
      this.neteasePasteController = new CustomDialogController({
        builder: PasteCookieDialog({
          title: '粘贴网易云 Cookie',
          hint: '从浏览器或 Android 端导出的 Cookie 文本，需包含 MUSIC_U。格式：k1=v1; k2=v2',
          placeholder: 'MUSIC_U=...; __csrf=...; os=pc',
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
    this.neteasePasteController.open();
  }

  // ---- Bilibili QR login --------------------------------------------------

  private async createBiliQrSession(): Promise<QrLoginSessionRef> {
    const session = await BiliQrLoginClient.createSession();
    const ref = new QrLoginSessionRef();
    ref.key = session.key;
    ref.qrContent = session.qrContent;
    return ref;
  }

  private async pollBiliQr(session: QrLoginSessionRef): Promise<QrPollOutcome> {
    const native = new BiliQrSession();
    native.key = session.key;
    const result = await BiliQrLoginClient.checkLogin(native);
    const outcome = new QrPollOutcome();
    outcome.message = result.message;
    if (result.code === BILI_QR_SCANNED) {
      outcome.code = QrPollOutcomeCode.SCANNED;
    } else if (result.code === BILI_QR_CONFIRMED) {
      outcome.code = QrPollOutcomeCode.CONFIRMED;
    } else if (result.code === BILI_QR_EXPIRED) {
      outcome.code = QrPollOutcomeCode.EXPIRED;
    } else {
      outcome.code = QrPollOutcomeCode.WAITING;
    }
    return outcome;
  }

  private onBiliConfirmed(): boolean {
    const saved = BiliCookieRepository.saveFromQrLogin(BiliQrLoginClient.currentCookies());
    if (saved) {
      this.biliLogged = true;
      promptAction.openToast({ message: 'Bilibili 登录成功' });
    }
    return saved;
  }

  private confirmBiliLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '确定退出 Bilibili 登录？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: Theme.danger(Theme.isDark()),
        action: () => {
          BiliCookieRepository.clear();
          this.biliLogged = false;
          promptAction.openToast({ message: '已退出 Bilibili 登录' });
        }
      }
    });
  }

  private openBiliPasteDialog(): void {
    if (this.biliPasteController === null) {
      this.biliPasteController = new CustomDialogController({
        builder: PasteCookieDialog({
          title: '粘贴 Bilibili Cookie',
          hint: '从浏览器导出的 Cookie 文本，需包含 SESSDATA。格式：k1=v1; k2=v2',
          placeholder: 'SESSDATA=...; bili_jct=...; DedeUserID=...',
          onConfirm: (text: string) => {
            const saved = BiliCookieRepository.saveFromPastedText(text);
            if (saved) {
              this.biliLogged = true;
              promptAction.openToast({ message: 'Cookie 导入成功' });
            } else {
              promptAction.openToast({ message: '导入失败：需要包含有效的 SESSDATA' });
            }
          }
        }),
        autoCancel: true,
        customStyle: false
      });
    }
    this.biliPasteController.open();
  }

  // ---- GitHub backup sync config (transport; full merge lands in M5.5) ----

  private openGithubConfigDialog(): void {
    if (this.githubConfigController === null) {
      this.githubConfigController = new CustomDialogController({
        builder: GitHubConfigDialog({
          prefillOwner: this.githubOwner,
          prefillRepo: this.githubRepo,
          onSaved: () => {
            this.githubTokenSaved = true;
          }
        }),
        autoCancel: true,
        customStyle: false
      });
    }
    this.githubConfigController.open();
  }

  private githubErrorText(error: Error): string {
    const apiError = error as GitHubApiError;
    if (apiError instanceof GitHubApiError) {
      if (apiError.kind === GitHubErrorKind.TOKEN_EXPIRED) {
        return '令牌无效或已过期，请更新 PAT';
      }
      if (apiError.kind === GitHubErrorKind.REPO_NOT_FOUND) {
        return '仓库不存在或令牌无访问权限';
      }
      if (apiError.kind === GitHubErrorKind.RATE_LIMITED) {
        return `GitHub API 限流，约 ${Math.ceil(apiError.retryAfterMs / 1000)} 秒后重试`;
      }
      if (apiError.kind === GitHubErrorKind.CONTENT_CONFLICT) {
        return '远端已被其他设备更新，请稍后重试';
      }
      if (apiError.kind === GitHubErrorKind.NETWORK) {
        return `网络错误：${apiError.message}`;
      }
      return apiError.message;
    }
    return error.message;
  }

  private async beginGithubAction(): Promise<GithubActionContext | null> {
    if (this.githubBusy) {
      return null;
    }
    const config = await GitHubConfigRepository.loadConfig();
    if (config === null) {
      promptAction.openToast({ message: '请先配置令牌与仓库' });
      return null;
    }
    this.githubBusy = true;
    const context = new GithubActionContext();
    context.transport = new GitHubTransport(new OhosGhExecutor(), config.token);
    context.owner = config.owner;
    context.repo = config.repo;
    context.dataSaver = config.dataSaver;
    return context;
  }

  private finishGithubAction(): void {
    this.githubBusy = false;
  }

  private async runGithubCheck(): Promise<void> {
    const context = await this.beginGithubAction();
    if (context === null) {
      return;
    }
    try {
      const login = await context.transport.validateToken();
      const info = await context.transport.getRepoInfo(context.owner, context.repo);
      promptAction.openToast({
        message: `连接成功：${login} · ${context.repo}（${info.isPrivate ? '私有' : '公开'} · ${info.defaultBranch} 分支）`
      });
    } catch (error) {
      promptAction.openToast({ message: this.githubErrorText(error as Error) });
    } finally {
      this.finishGithubAction();
    }
  }

  private async runGithubCreateRepo(): Promise<void> {
    const context = await this.beginGithubAction();
    if (context === null) {
      return;
    }
    try {
      const info = await context.transport.createRepository(context.repo);
      promptAction.openToast({ message: `已创建 ${info.fullName}（${info.defaultBranch} 分支）` });
    } catch (error) {
      const message = this.githubErrorText(error as Error);
      if (message.includes('already exists')) {
        promptAction.openToast({ message: '同名仓库已存在，可直接测试连接' });
      } else {
        promptAction.openToast({ message });
      }
    } finally {
      this.finishGithubAction();
    }
  }

  private async runGithubRemoteCheck(): Promise<void> {
    const context = await this.beginGithubAction();
    if (context === null) {
      return;
    }
    try {
      const client = new GitHubSyncClient(context.transport);
      const fileName = getSyncFileName(context.dataSaver);
      const snapshot = await client.fetchRemoteSnapshot(context.owner, context.repo,
        fileName, context.dataSaver);
      if (snapshot === null) {
        promptAction.openToast({ message: '远端暂无备份文件（首次同步时将创建）' });
        return;
      }
      const decoded = deserializeSyncContent(snapshot.content);
      if (decoded.data === null) {
        promptAction.openToast({ message: `远端 ${snapshot.sourceFileName} 解析失败：${decoded.errorMessage}` });
        return;
      }
      const data = decoded.data;
      const modified = data.lastModified > 0 ? new Date(data.lastModified).toLocaleString() : '未知';
      promptAction.openToast({
        message: `远端备份正常：${data.playlists.length} 歌单 · ${data.recentPlays.length} 最近播放 · ${data.playbackStats.length} 统计 · 更新于 ${modified}`
      });
    } catch (error) {
      promptAction.openToast({ message: this.githubErrorText(error as Error) });
    } finally {
      this.finishGithubAction();
    }
  }

  private confirmGithubClear(): void {
    AlertDialog.show({
      title: '清除 GitHub 配置',
      message: '将移除令牌与仓库设置，不影响本地数据。确定继续？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: Theme.danger(Theme.isDark()),
        action: (): void => {
          GitHubConfigRepository.clear().then(() => {
            this.githubTokenSaved = false;
            promptAction.openToast({ message: 'GitHub 配置已清除' });
          });
        }
      }
    });
  }

  private async runGithubSync(): Promise<void> {
    if (this.githubBusy || this.webdavBusy) {
      return;
    }
    this.githubBusy = true;
    try {
      this.showSyncReport('GitHub 同步报告', await SyncService.syncGitHub());
    } finally {
      this.githubBusy = false;
    }
  }

  // ---- WebDAV transport config and coordinated sync ----------------------

  private openWebDavConfigDialog(): void {
    if (this.webdavConfigController === null) {
      this.webdavConfigController = new CustomDialogController({
        builder: WebDavConfigDialog({
          prefillServerUrl: this.webdavServerUrl,
          prefillBasePath: this.webdavBasePath,
          onSaved: () => {
            this.webdavCredentialsSaved = true;
          }
        }),
        autoCancel: true,
        customStyle: false
      });
    }
    this.webdavConfigController.open();
  }

  // ---- Listen Together server ---------------------------------------------

  /** Re-normalizes on read: a value stored by an older build may be unusable. */
  private listenTogetherServerSubtitle(): string {
    const custom = listenTogetherSavedCustomServer(this.listenTogetherServer);
    return custom.length > 0 ? custom : '使用内置默认服务器';
  }

  private openListenTogetherServerDialog(): void {
    if (this.listenTogetherServerController === null) {
      this.listenTogetherServerController = new CustomDialogController({
        builder: ListenTogetherServerDialog(),
        autoCancel: true,
        customStyle: false
      });
    }
    this.listenTogetherServerController.open();
  }

  private webdavErrorText(error: Error): string {
    const apiError = error as WebDavError;
    if (apiError instanceof WebDavError) {
      if (apiError.kind === WebDavErrorKind.AUTH) {
        return 'WebDAV 用户名或密码错误';
      }
      if (apiError.kind === WebDavErrorKind.FILE_NOT_FOUND) {
        return '远端暂无备份文件（首次同步时将创建）';
      }
      if (apiError.kind === WebDavErrorKind.CONTENT_CONFLICT) {
        return '远端文件已被其他设备修改，请重新拉取后同步';
      }
      if (apiError.kind === WebDavErrorKind.NETWORK) {
        return `网络错误：${apiError.message}`;
      }
      return apiError.message;
    }
    return error.message;
  }

  private async beginWebDavAction(): Promise<WebDavActionContext | null> {
    if (this.webdavBusy) {
      return null;
    }
    const config = await WebDavConfigRepository.loadConfig();
    if (config === null) {
      promptAction.openToast({ message: '请先配置 WebDAV 服务器与凭据' });
      return null;
    }
    this.webdavBusy = true;
    const context = new WebDavActionContext();
    context.transport = new WebDavTransport(new OhosWebDavExecutor(), config.username, config.password);
    context.serverUrl = config.serverUrl;
    context.basePath = config.basePath;
    context.remoteFileUrl = config.remoteFileUrl();
    return context;
  }

  private async runWebDavCheck(): Promise<void> {
    const context = await this.beginWebDavAction();
    if (context === null) {
      return;
    }
    try {
      await context.transport.validateConnection(context.serverUrl, context.basePath);
      promptAction.openToast({ message: 'WebDAV 连接成功，目标目录可访问' });
    } catch (error) {
      promptAction.openToast({ message: this.webdavErrorText(error as Error) });
    } finally {
      this.webdavBusy = false;
    }
  }

  private async runWebDavRemoteCheck(): Promise<void> {
    const context = await this.beginWebDavAction();
    if (context === null) {
      return;
    }
    try {
      const snapshot = await new WebDavSyncClient(context.transport)
        .fetchRemoteSnapshot(context.remoteFileUrl);
      if (snapshot === null) {
        promptAction.openToast({ message: '远端暂无备份文件（首次同步时将创建）' });
        return;
      }
      const decoded = deserializeSyncContent(snapshot.content);
      if (decoded.data === null) {
        promptAction.openToast({ message: `远端备份解析失败：${decoded.errorMessage}` });
        return;
      }
      const data = decoded.data;
      const modified = data.lastModified > 0 ? new Date(data.lastModified).toLocaleString() : '未知';
      const tokenKind = snapshot.version.token !== null && snapshot.version.token.etag !== null ?
        'ETag' : snapshot.version.token !== null && snapshot.version.token.lastModified !== null ?
          'Last-Modified' : 'SHA-256 指纹回退';
      promptAction.openToast({
        message: `远端备份正常：${data.playlists.length} 歌单 · ${data.recentPlays.length} 最近播放 · ${tokenKind} · 更新于 ${modified}`
      });
    } catch (error) {
      promptAction.openToast({ message: this.webdavErrorText(error as Error) });
    } finally {
      this.webdavBusy = false;
    }
  }

  private async runWebDavSync(): Promise<void> {
    if (this.webdavBusy || this.githubBusy) {
      return;
    }
    this.webdavBusy = true;
    try {
      this.showSyncReport('WebDAV 同步报告', await SyncService.syncWebDav());
    } finally {
      this.webdavBusy = false;
    }
  }

  private showSyncReport(title: string, report: SyncReport): void {
    let message = report.summary();
    for (const conflict of report.conflicts) {
      message += `\n\n${conflict.description}（${conflict.resolution}）`;
    }
    AlertDialog.show({
      title: report.success ? title : `${title}失败`,
      message,
      confirm: {
        value: '确定',
        action: () => {
        }
      }
    });
  }

  private confirmWebDavClear(): void {
    AlertDialog.show({
      title: '清除 WebDAV 配置',
      message: '将移除服务器地址、用户名和密码，不影响本地或远端数据。确定继续？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: Theme.danger(Theme.isDark()),
        action: (): void => {
          WebDavConfigRepository.clear().then(() => {
            this.webdavCredentialsSaved = false;
            promptAction.openToast({ message: 'WebDAV 配置已清除' });
          });
        }
      }
    });
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
                  // Button's default horizontal padding (~16vp each side)
                  // is wider than a layoutWeight(1) sixth of the row, which
                  // ellipsized every label except "2x" to "...".
                  .padding({ left: 4, right: 4 })
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
                  this.neteaseQrController.open();
                }
              }
            })
            QrLoginPanel({
              controller: this.neteaseQrController,
              createSession: (): Promise<QrLoginSessionRef> => this.createNeteaseQrSession(),
              pollSession: (session: QrLoginSessionRef): Promise<QrPollOutcome> => this.pollNeteaseQr(session),
              onConfirmed: (): boolean => this.onNeteaseConfirmed(),
              scanHint: '请用网易云音乐 App 扫码',
              pollIntervalMs: NETEASE_QR_POLL_INTERVAL_MS
            })
            SettingRow({
              title: '粘贴 Cookie 导入（网易云）',
              subtitle: '扫码不可用时的备用登录方式',
              icon: '📋',
              onTap: () => this.openNeteasePasteDialog()
            })
            SettingRow({
              title: 'Bilibili',
              subtitle: this.biliLogged
                ? `已登录 · 凭据存储：${BiliCookieRepository.backendName()}`
                : '未登录 · 点击扫码登录',
              icon: '📺',
              onTap: () => {
                if (this.biliLogged) {
                  this.confirmBiliLogout();
                } else {
                  this.biliQrController.open();
                }
              }
            })
            QrLoginPanel({
              controller: this.biliQrController,
              createSession: (): Promise<QrLoginSessionRef> => this.createBiliQrSession(),
              pollSession: (session: QrLoginSessionRef): Promise<QrPollOutcome> => this.pollBiliQr(session),
              onConfirmed: (): boolean => this.onBiliConfirmed(),
              scanHint: '请用哔哩哔哩客户端扫码',
              pollIntervalMs: BILI_QR_POLL_INTERVAL_MS
            })
            SettingRow({
              title: '粘贴 Cookie 导入（Bilibili）',
              subtitle: '扫码不可用时的备用登录方式',
              icon: '📋',
              onTap: () => this.openBiliPasteDialog()
            })
            SettingRow({
              title: 'YouTube',
              subtitle: '未登录 · Cookie 会话待移植',
              icon: '▶',
              onTap: () => promptAction.openToast({ message: 'YouTube 登录待移植' })
            })
          } else if (this.section === SETTING_SYNC) {
            Text('GitHub 备份')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 10, bottom: 6 })
            Column({ space: 1 }) {
              SettingRow({
                title: 'GitHub 仓库与令牌',
                subtitle: this.githubTokenSaved && this.githubOwner.length > 0 && this.githubRepo.length > 0 ?
                  `${this.githubOwner}/${this.githubRepo}` : '未配置（Personal Access Token + 仓库名）',
                icon: '🐙',
                onTap: () => this.openGithubConfigDialog()
              })
              SettingRow({
                title: '测试连接',
                subtitle: this.githubBusy ? '正在请求…' : '校验令牌与仓库可达性',
                icon: '🔌',
                showArrow: false,
                onTap: () => this.runGithubCheck()
              })
              SettingRow({
                title: '创建备份仓库',
                subtitle: '在账号下新建私有仓库（需 repo 权限）',
                icon: '📦',
                showArrow: false,
                onTap: () => this.runGithubCreateRepo()
              })
              SettingRow({
                title: '检查远端备份',
                subtitle: this.githubBusy ? '正在请求…' : '拉取并解析远端备份文件',
                icon: '🛰',
                showArrow: false,
                onTap: () => this.runGithubRemoteCheck()
              })
              SettingRow({
                title: '立即同步',
                subtitle: this.githubBusy ? '正在同步…' : '拉取、三路合并并条件上传，完成后写回本地',
                icon: '↻',
                showArrow: false,
                onTap: () => this.runGithubSync()
              })
            }
            .width('100%')
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())
            .clip(true)

            Text('数据格式')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 1 }) {
              SettingRow({
                title: '省流格式',
                subtitle: this.githubDataSaver ? '已开启（读取兼容全部格式；上传仍为 JSON）' :
                  '已关闭（备份为 JSON 文本，读取兼容全部历史格式）',
                icon: '📉',
                showArrow: false,
                onTap: () => SettingsRepository.setBoolean(SettingsRepository.KEY_GITHUB_DATA_SAVER,
                  !this.githubDataSaver)
              })
              SettingRow({
                title: '清除 GitHub 配置',
                subtitle: '移除令牌与仓库设置（不影响本地数据）',
                icon: '🗑',
                danger: true,
                onTap: () => this.confirmGithubClear()
              })
            }
            .width('100%')
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())
            .clip(true)

            Text('WebDAV 备份')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 1 }) {
              SettingRow({
                title: '服务器与凭据',
                subtitle: this.webdavCredentialsSaved && this.webdavServerUrl.length > 0 ?
                  `${this.webdavServerUrl}${this.webdavBasePath.length > 0 ? `/${this.webdavBasePath}` : ''}` :
                  '未配置（服务器地址、目录、用户名与密码）',
                icon: '🗂',
                onTap: () => this.openWebDavConfigDialog()
              })
              SettingRow({
                title: '测试 WebDAV 连接',
                subtitle: this.webdavBusy ? '正在请求…' : '使用 PROPFIND 检查目录和登录凭据',
                icon: '🔌',
                showArrow: false,
                onTap: () => this.runWebDavCheck()
              })
              SettingRow({
                title: '检查 WebDAV 备份',
                subtitle: this.webdavBusy ? '正在请求…' : '读取、校验并解析 neriplayer-sync.json',
                icon: '🛰',
                showArrow: false,
                onTap: () => this.runWebDavRemoteCheck()
              })
              SettingRow({
                title: '立即同步',
                subtitle: this.webdavBusy ? '正在同步…' : '拉取、三路合并并使用 ETag/指纹条件上传',
                icon: '↻',
                showArrow: false,
                onTap: () => this.runWebDavSync()
              })
              SettingRow({
                title: '清除 WebDAV 配置',
                subtitle: '移除服务器与安全存储中的凭据',
                icon: '🗑',
                danger: true,
                onTap: () => this.confirmWebDavClear()
              })
            }
            .width('100%')
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())
            .clip(true)

            Text('其他同步方式')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            SettingRow({
              title: '一起听服务器',
              subtitle: this.listenTogetherServerSubtitle(),
              icon: '👥',
              onTap: () => this.openListenTogetherServerDialog()
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
  title: string = '粘贴 Cookie';
  hint: string = '';
  placeholder: string = '';
  onConfirm: (text: string) => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text(this.hint)
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
      TextArea({ placeholder: this.placeholder, text: this.cookieText })
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

class GithubActionContext {
  transport: GitHubTransport = new GitHubTransport(new OhosGhExecutor(), '');
  owner: string = '';
  repo: string = '';
  dataSaver: boolean = false;
}

class WebDavActionContext {
  transport: WebDavTransport = new WebDavTransport(new OhosWebDavExecutor(), '', '');
  serverUrl: string = '';
  basePath: string = '';
  remoteFileUrl: string = '';
}

@CustomDialog
struct GitHubConfigDialog {
  controller?: CustomDialogController;
  @State tokenText: string = '';
  @State ownerText: string = '';
  @State repoText: string = '';
  prefillOwner: string = '';
  prefillRepo: string = '';
  onSaved: () => void = () => {
  };

  aboutToAppear(): void {
    this.ownerText = this.prefillOwner;
    this.repoText = this.prefillRepo;
    this.tokenText = GitHubConfigRepository.tokenPreview();
  }

  private async save(): Promise<void> {
    const owner = this.ownerText.trim();
    const repo = this.repoText.trim();
    const token = this.tokenText.trim();
    if (token.length === 0) {
      promptAction.openToast({ message: '请填写 Personal Access Token' });
      return;
    }
    if (!isValidGitHubName(owner) || !isValidGitHubName(repo)) {
      promptAction.openToast({ message: '仓库名仅支持字母、数字与 - _ . 字符' });
      return;
    }
    const persisted = await GitHubConfigRepository.saveConfig(token, owner, repo);
    if (!persisted) {
      promptAction.openToast({ message: '已保存，但令牌仅本会话有效（凭据存储不可用）' });
    } else {
      promptAction.openToast({ message: 'GitHub 配置已保存' });
    }
    this.onSaved();
    this.controller?.close();
  }

  build() {
    Column({ space: 14 }) {
      Text('GitHub 同步配置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text('令牌需包含 repo 权限（用于私有备份仓库读写）。仅保存在本机安全存储，不会出现在日志中。')
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
      TextArea({ placeholder: 'ghp_… / github_pat_…', text: this.tokenText })
        .height(84)
        .fontSize(13)
        .onChange((value: string) => {
          this.tokenText = value;
        })
      TextInput({ placeholder: '用户名 / 组织名（owner）', text: this.ownerText })
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.ownerText = value;
        })
      TextInput({ placeholder: '仓库名（如 neriplayer-backup）', text: this.repoText })
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.repoText = value;
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
        Button('保存')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .fontColor(Theme.onPrimary(Theme.isDark()))
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('92%')
  }
}

@CustomDialog
struct WebDavConfigDialog {
  controller?: CustomDialogController;
  @State serverUrlText: string = '';
  @State basePathText: string = '';
  @State usernameText: string = '';
  @State passwordText: string = '';
  @State saving: boolean = false;
  prefillServerUrl: string = '';
  prefillBasePath: string = '';
  onSaved: () => void = () => {
  };

  aboutToAppear(): void {
    this.serverUrlText = this.prefillServerUrl;
    this.basePathText = this.prefillBasePath;
    this.usernameText = WebDavConfigRepository.usernamePreview();
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const serverUrl = this.serverUrlText.trim();
    const basePath = this.basePathText.trim();
    const username = this.usernameText.trim();
    const password = this.passwordText;
    if (serverUrl.length === 0 || username.length === 0 || password.length === 0) {
      promptAction.openToast({ message: '请填写服务器地址、用户名和密码' });
      return;
    }
    this.saving = true;
    try {
      const transport = new WebDavTransport(new OhosWebDavExecutor(), username, password);
      await transport.validateConnection(serverUrl, basePath);
      const persisted = await WebDavConfigRepository.saveConfig(serverUrl, basePath, username, password);
      promptAction.openToast({
        message: persisted ? 'WebDAV 配置已验证并保存' :
          '配置已验证，但凭据仅本会话有效（安全存储不可用）'
      });
      this.onSaved();
      this.controller?.close();
    } catch (error) {
      const e = error as WebDavError;
      if (e instanceof WebDavError && e.kind === WebDavErrorKind.AUTH) {
        promptAction.openToast({ message: '验证失败：用户名或密码错误' });
      } else {
        promptAction.openToast({ message: `验证失败：${(error as Error).message}` });
      }
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('WebDAV 同步配置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text('目标目录必须已存在。备份文件固定为 neriplayer-sync.json；用户名和密码仅保存在本机安全存储。')
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
      TextInput({ placeholder: 'https://dav.example.com/remote.php/dav/files/user',
        text: this.serverUrlText })
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.serverUrlText = value;
        })
      TextInput({ placeholder: '目录路径（可留空，如 NeriPlayer/Backup）', text: this.basePathText })
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.basePathText = value;
        })
      TextInput({ placeholder: '用户名', text: this.usernameText })
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.usernameText = value;
        })
      TextInput({ placeholder: '密码 / 应用专用密码', text: this.passwordText })
        .type(InputType.Password)
        .height(40)
        .fontSize(13)
        .onChange((value: string) => {
          this.passwordText = value;
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
        Button(this.saving ? '验证中…' : '验证并保存')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.saving)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .fontColor(Theme.onPrimary(Theme.isDark()))
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('92%')
  }
}

/**
 * Port of the Listen Together server dialog in SettingsScreen.kt (1911-2044).
 * Copy is reused verbatim from the Android string resources.
 *
 * Two documented divergences from upstream:
 * - Upstream blocks dismissal while the availability probe is in flight. Here
 *   dismissal stays available and the in-flight result is dropped instead
 *   (`closed` is set in aboutToDisappear), so the user is never trapped in a
 *   modal by a slow server and no state is written after teardown.
 * - After saving, upstream leaves the field showing the normalized text even
 *   when that text is the built-in default (whose keys it just cleared). Here
 *   the field is refreshed from the store, so what is shown always matches what
 *   is persisted.
 */
@CustomDialog
struct ListenTogetherServerDialog {
  controller?: CustomDialogController;
  @State inputText: string = '';
  @State testMessage: string = '';
  @State testing: boolean = false;
  private closed: boolean = false;
  private api: ListenTogetherApi = new ListenTogetherApi();

  aboutToAppear(): void {
    this.inputText = listenTogetherServerInput();
  }

  aboutToDisappear(): void {
    // A probe may still be awaiting; its result must not touch @State after this.
    this.closed = true;
  }

  /** Upstream shows the default hint for a blank input *and* for the default URL. */
  private isUsingDefault(): boolean {
    const normalized = configuredListenTogetherBaseUrlOrNull(this.inputText);
    return normalized === null || isDefaultListenTogetherBaseUrl(normalized);
  }

  private async runTest(): Promise<void> {
    if (this.testing) {
      return;
    }
    const normalizedCustomServer = configuredListenTogetherBaseUrlOrNull(this.inputText);
    if (this.inputText.trim().length > 0 && normalizedCustomServer === null) {
      this.testMessage = '服务器地址格式无效，请输入完整的 http:// 或 https:// 地址';
      return;
    }
    const usingDefaultServer = normalizedCustomServer === null;
    this.testing = true;
    try {
      const target = normalizedCustomServer ?? resolveListenTogetherBaseUrl(null);
      const result = await this.api.testServerAvailability(target);
      if (this.closed) {
        return;
      }
      if (result.ok) {
        this.testMessage = usingDefaultServer ? '内置默认服务器可用' : '自定义一起听服务器可用';
      } else if (result.message === LISTEN_TOGETHER_TEST_INVALID_RESPONSE) {
        this.testMessage = '该地址已响应，但看起来不是可用的一起听服务端';
      } else {
        this.testMessage = `服务器测试失败：${result.message}`;
      }
    } finally {
      if (!this.closed) {
        this.testing = false;
      }
    }
  }

  private apply(): void {
    if (this.testing) {
      return;
    }
    const saved = saveListenTogetherServer(this.inputText);
    if (saved === null) {
      this.testMessage = '服务器地址格式无效，请输入完整的 http:// 或 https:// 地址';
      return;
    }
    this.inputText = saved;
    this.testMessage = '';
    this.controller?.close();
    promptAction.openToast({ message: '一起听服务器设置已保存' });
  }

  build() {
    Column({ space: 12 }) {
      Text('一起听服务器')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text(this.isUsingDefault() ? '留空即可使用内置默认服务器' :
        '当前使用自定义一起听服务器，分享邀请时会附带服务器地址')
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
      TextInput({ placeholder: '示例：https://example.com，留空使用内置默认服务器', text: this.inputText })
        .height(40)
        .fontSize(13)
        .enabled(!this.testing)
        .onChange((value: string) => {
          // Assigning inputText makes the TextInput echo the same value back
          // through onChange. Without this guard the echo wipes the message that
          // 重置 / 应用 just set, so the reset hint never became visible on device.
          // A real keystroke or deletion always yields a value that differs.
          if (value === this.inputText) {
            return;
          }
          this.inputText = value;
          this.testMessage = '';
        })
      if (this.testing) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
          Text('正在测试服务器可用性')
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }
        .width('100%')
      } else if (this.testMessage.length > 0) {
        Text(this.testMessage)
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .width('100%')
      }
      Row({ space: 10 }) {
        Button('测试可用性')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.runTest();
          })
        Button('重置')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            // Upstream only clears the field; nothing is stored until 应用.
            this.inputText = '';
            this.testMessage = '已恢复使用内置默认服务器';
          })
      }
      .width('100%')
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button('应用')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.primary(Theme.isDark()))
          .fontColor(Theme.onPrimary(Theme.isDark()))
          .onClick(() => {
            this.apply();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('92%')
  }
}
