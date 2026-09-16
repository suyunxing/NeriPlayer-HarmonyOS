// SPDX-License-Identifier: GPL-3.0

import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../../data/SettingsRepository';
import { AppColorMode } from '../../util/AppColorMode';
import { SystemBars } from '../../util/SystemBars';
import { DownloadStorage } from '../../download/DownloadStorage';
import { DownloadEngine } from '../../download/DownloadEngine';
import { DownloadDirectory } from '../../download/DownloadDirectory';
import { PlaylistBackupManager } from '../../data/PlaylistBackupManager';
import {
  DownloadDirectoryManager,
  DownloadDirectoryPickCode
} from '../../download/DownloadDirectoryManager';
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
import { NeteaseApi } from '../../network/NeteaseApi';
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
import { NeteasePhoneLoginPanel } from '../components/NeteasePhoneLoginPanel';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { BAND_LIST_VP } from '../../util/Breakpoint';
import { OptionEntry, OptionRow, SettingRow, SliderRow, ToggleRow } from '../components/Ui';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';
import { LyricSettingsRows, LyricStylePreview } from '../components/LyricSettingsRows';
import { SETTING_PLAYBACK, SETTING_DOWNLOAD, SETTING_LYRICS, SETTING_PLAYER,
  SETTING_APPEARANCE, SETTING_NAVIGATION, SETTING_TRAFFIC, SETTING_STORAGE,
  SETTING_ACCOUNTS, SETTING_SYNC, SETTING_DEBUG, SETTING_ABOUT } from './SettingsPage';
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
import { AutoSyncScheduler } from '../../sync/AutoSyncScheduler';

const SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const QUALITIES: string[] = ['standard', 'high', 'exhigh', 'lossless', 'hires'];
const NETEASE_QR_POLL_INTERVAL_MS: number = 2000;
const BILI_QR_POLL_INTERVAL_MS: number = 1500;

@Component
export struct SettingsDetailPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  /** 供 HdsNavDestination.bindToScrollable 绑定的整页滚动控制器。 */
  private scroller: Scroller = new Scroller();
  /** 由 MainShell 的 navDestination builder 从路由参数传入。 */
  @Prop section: string = '';

  @StorageProp('np.playback_speed') speed: number = 1.0;
  @StorageProp('np.audio_quality') quality: string = 'standard';
  @StorageProp('np.audio_quality_wifi') qualityWifi: string = '';
  @StorageProp('np.audio_quality_cellular') qualityCellular: string = '';
  @StorageProp('np.mix_audio') mixAudio: boolean = true;
  @StorageProp('np.playback_volume') playbackVolume: number = 1.0;
  @StorageProp('np.playback_fade') playbackFade: boolean = true;
  @StorageProp('np.playback_fade_in_ms') playbackFadeInMs: number = 500;
  @StorageProp('np.playback_fade_out_ms') playbackFadeOutMs: number = 500;
  @StorageProp('np.autoplay_on_launch') autoplayOnLaunch: boolean = false;
  @StorageProp('np.keep_playback_mode_state') keepPlaybackMode: boolean = true;
  @StorageProp('np.nowplaying_bg_style') nowplayingBgStyle: string = 'blur';
  @StorageProp('np.keep_screen_on') keepScreenOn: boolean = false;
  @StorageProp('np.dynamic_color') dynamicColor: boolean = true;
  @StorageProp('np.circular_cover') circularCover: boolean = false;
  @StorageProp('np.lyric_page_controls') lyricPageControls: boolean = true;
  @StorageProp('np.mini_next_button') miniNextButton: boolean = true;
  @StorageProp('np.mini_show_lyric') miniShowLyric: boolean = true;
  @StorageProp('np.mini_expand_autoplay') miniExpandAutoplay: boolean = false;
  @StorageProp('np.start_page') startPage: string = 'last';
  @StorageProp('np.dark_mode') darkMode: string = 'auto';
  @StorageProp('np.lyric_font_size') lyricFontSize: number = 16;
  @StorageProp('np.lyric_offset_ms') lyricOffsetMs: number = 0;
  @StorageProp('np.lyric_translation') lyricTranslation: boolean = true;
  @StorageProp('np.amll_lyrics') amllLyrics: boolean = true;
  @StorageProp('np.nowplaying_blur_strength') nowplayingBlurStrength: number = 300;
  @StorageProp('np.floating_lyric') floatingLyric: boolean = false;
  @StorageProp('np.bt_lyric') btLyric: boolean = false;
  @StorageProp('np.lyric_phonetic') lyricPhonetic: boolean = false;
  @StorageProp('np.lyric_blur') lyricBlur: boolean = true;
  @StorageProp('np.download_concurrency') downloadConcurrency: number = 6;
  @StorageProp('np.download_match_lyrics') downloadMatchLyrics: boolean = true;
  @StorageProp('np.playback_cache') playbackCache: boolean = false;
  @StorageProp('np.download_directory_uri') downloadDirectoryUri: string = '';
  @StorageProp('np.download_directory_label') downloadDirectoryLabel: string = '';
  @StorageProp('np.save_traffic') saveTraffic: boolean = false;
  @StorageProp('np.cellular_follow_default_quality') cellularFollowDefault: boolean = true;
  @StorageProp('np.cellular_netease_quality') cellularNeteaseQuality: string = '';
  @StorageProp('np.cellular_bili_quality') cellularBiliQuality: string = '';
  @StorageProp('np.cellular_youtube_quality') cellularYoutubeQuality: string = '';
  @StorageProp('np.netease_auto_fallback') neteaseAutoFallback: boolean = true;
  @StorageProp('np.cover_policy') coverPolicy: string = 'always';
  @StorageProp('np.always_record_logs') alwaysRecordLogs: boolean = false;
  @StorageLink('np.netease_logged') neteaseLogged: boolean = false;
  @StorageLink('np.bilibili_logged') biliLogged: boolean = false;
  @StorageLink('player.shuffle') shuffle: boolean = false;

  @StorageProp('np.github_owner') githubOwner: string = '';
  @StorageProp('np.github_repo') githubRepo: string = '';
  @StorageProp('np.github_data_saver') githubDataSaver: boolean = false;
  @StorageProp('np.sync_auto') syncAuto: boolean = false;
  @State githubTokenSaved: boolean = false;
  @State githubBusy: boolean = false;

  @StorageProp('np.webdav_server_url') webdavServerUrl: string = '';
  @StorageProp('np.webdav_base_path') webdavBasePath: string = '';
  @State webdavCredentialsSaved: boolean = false;
  @State webdavBusy: boolean = false;

  // Only the dialed address is mirrored here; the dialog reads its own prefill
  // from the settings store so a reopened dialog is never stale.
  @StorageProp('np.listen_together_server') listenTogetherServer: string = '';
  @StorageProp('np.listen_together_allow_member_control') ltAllowMemberControl: boolean = true;
  @StorageProp('np.listen_together_auto_pause_on_member_change') ltAutoPauseOnMemberChange: boolean = true;
  @StorageProp('np.listen_together_share_audio_links') ltShareAudioLinks: boolean = true;
  @State showNeteasePhoneLogin: boolean = false;

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
    if (this.section === SETTING_PLAYER) {
      return '播放器设置';
    }
    if (this.section === SETTING_APPEARANCE) {
      return '外观与动效';
    }
    if (this.section === SETTING_NAVIGATION) {
      return '页面与导航';
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

  private darkModeOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'auto', label: '跟随系统' },
      { value: 'light', label: '浅色' },
      { value: 'dark', label: '深色' }
    ];
    return options;
  }

  private applyDarkMode(mode: string): void {
    if (mode === this.darkMode) {
      return;
    }
    SettingsRepository.setString(SettingsRepository.KEY_DARK_MODE, mode);
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context !== undefined) {
      // setColorMode 触发配置变更、重建整棵组件树，否则本页与 MainShell 的
      // 颜色表达式不引用可观察状态，切换后不会重绘（见 AppColorMode 注释）。
      AppColorMode.apply(context, mode);
      // 系统栏内容色仍显式跟一次：setColorMode 抛错时这里是兜底。
      SystemBars.apply(context, Theme.isDark());
    }
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

  // ---- Download directory (picker + persisted URI grant) ------------------

  private async pickDownloadDirectory(): Promise<void> {
    if (!DownloadDirectoryManager.folderPickerSupported()) {
      promptAction.openToast({ message: '当前系统版本不支持选择下载目录' });
      return;
    }
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined) {
      promptAction.openToast({ message: '应用上下文未就绪' });
      return;
    }
    const result = await DownloadDirectoryManager.pickAndApply(context);
    if (result.code === DownloadDirectoryPickCode.APPLIED) {
      promptAction.openToast({ message: `下载目录已切换为「${result.label}」` });
    } else if (result.code === DownloadDirectoryPickCode.FAILED) {
      promptAction.openToast({ message: result.message });
    }
    // CANCELLED: 用户在选择器中退出，保持原目录，无需提示。
  }

  private confirmResetDownloadDirectory(): void {
    this.getUIContext().showAlertDialog({
      title: '恢复默认目录',
      message: '之后的下载将保存到应用内部 Download/NeriPlayer 目录；已下载文件保留在原目录，仍可播放。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '恢复',
        action: () => {
          DownloadDirectoryManager.resetToDefault();
          promptAction.openToast({ message: '已恢复默认下载目录' });
        }
      }
    });
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

  private async onNeteaseConfirmed(): Promise<boolean> {
    const saved = await NeteaseCookieRepository.saveFromQrLogin(NeteaseQrLoginClient.currentCookies());
    if (saved) {
      this.neteaseLogged = true;
      NeteaseApi.resetSession();
      promptAction.openToast({ message: '网易云登录成功' });
    }
    return saved;
  }

  private async onNeteasePhoneConfirmed(cookies: Map<string, string>): Promise<boolean> {
    const saved = await NeteaseCookieRepository.saveFromPhoneLogin(cookies);
    if (saved) {
      this.neteaseLogged = true;
      this.showNeteasePhoneLogin = false;
      NeteaseApi.resetSession();
    }
    return saved;
  }

  /** Exports playlists + history to a user-picked JSON file. */
  private async exportPlaylistBackup(): Promise<void> {
    try {
      const message = await PlaylistBackupManager.exportViaPicker();
      if (message.length > 0) {
        promptAction.openToast({ message, duration: 2000 });
      }
    } catch (error) {
      promptAction.openToast({ message: `导出失败：${(error as Error).message}` });
    }
  }

  /** Imports playlists + history from a picked backup JSON. */
  private async importPlaylistBackup(): Promise<void> {
    try {
      const result = await PlaylistBackupManager.importViaPicker();
      if (result.message.length > 0) {
        promptAction.openToast({ message: result.message, duration: 2500 });
      }
    } catch (error) {
      promptAction.openToast({ message: `导入失败：${(error as Error).message}` });
    }
  }

  private confirmNeteaseLogout(): void {
    this.getUIContext().showAlertDialog({
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
          NeteaseCookieRepository.clear()
            .then(() => {
              NeteaseApi.resetSession();
              promptAction.openToast({ message: '已退出网易云登录' });
            });
          this.neteaseLogged = false;
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
            NeteaseCookieRepository.saveFromPastedText(text)
              .then((saved: boolean) => {
                if (saved) {
                  this.neteaseLogged = true;
                  NeteaseApi.resetSession();
                  promptAction.openToast({ message: 'Cookie 导入成功' });
                } else {
                  promptAction.openToast({ message: '导入失败：需要包含有效的 MUSIC_U' });
                }
              });
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

  private async onBiliConfirmed(): Promise<boolean> {
    const saved = await BiliCookieRepository.saveFromQrLogin(BiliQrLoginClient.currentCookies());
    if (saved) {
      this.biliLogged = true;
      promptAction.openToast({ message: 'Bilibili 登录成功' });
    }
    return saved;
  }

  private confirmBiliLogout(): void {
    this.getUIContext().showAlertDialog({
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
          BiliCookieRepository.clear()
            .then(() => {
              promptAction.openToast({ message: '已退出 Bilibili 登录' });
            });
          this.biliLogged = false;
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
            BiliCookieRepository.saveFromPastedText(text)
              .then((saved: boolean) => {
                if (saved) {
                  this.biliLogged = true;
                  promptAction.openToast({ message: 'Cookie 导入成功' });
                } else {
                  promptAction.openToast({ message: '导入失败：需要包含有效的 SESSDATA' });
                }
              });
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
    this.getUIContext().showAlertDialog({
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
    this.getUIContext().showAlertDialog({
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
    this.getUIContext().showAlertDialog({
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

  // ---- OptionRow option sets (UX rule: non-binary choices get a menu) ----

  private speedOptions(): OptionEntry[] {
    const options: OptionEntry[] = [];
    for (const speedValue of SPEEDS) {
      options.push({ value: `${speedValue}`, label: speedValue === 1.0 ? '1.0x' : `${speedValue}x` });
    }
    return options;
  }

  private qualityOptions(): OptionEntry[] {
    const options: OptionEntry[] = [];
    for (const qualityValue of QUALITIES) {
      options.push({ value: qualityValue, label: qualityLabel(qualityValue) });
    }
    return options;
  }

  private concurrencyOptions(): OptionEntry[] {
    const options: OptionEntry[] = [];
    for (const concurrency of [1, 2, 4, 6, 8]) {
      options.push({ value: `${concurrency}`, label: `${concurrency} 个并发` });
    }
    return options;
  }

  private blurStrengthOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: '0', label: '关闭' },
      { value: '100', label: '较弱' },
      { value: '300', label: '适中' },
      { value: '500', label: '较强' }
    ];
    return options;
  }

  private bgStyleOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'blur', label: '封面模糊' },
      { value: 'solid', label: '纯色' },
      { value: 'gradient', label: '流光' }
    ];
    return options;
  }

  private startPageOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'last', label: '跟随上次' },
      { value: '0', label: '首页' },
      { value: '1', label: '探索' },
      { value: '2', label: '资料库' },
      { value: '3', label: '设置' }
    ];
    return options;
  }

  private coverPolicyOptions(): OptionEntry[] {
    const options: OptionEntry[] = [
      { value: 'always', label: '始终加载' },
      { value: 'wifi', label: '仅 Wi-Fi' },
      { value: 'off', label: '不加载' }
    ];
    return options;
  }

  @Builder
  optionRow(label: string, value: string, onTap: () => void) {
    SettingRow({ title: label, subtitle: value, onTap: onTap })
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    // 标题栏（返回 + 分区标题）由 HdsNavDestination 承载，滚动时设置项穿到
    // 标题栏下方被 GRADIENT_BLUR 渐变模糊覆盖（同首页外壳）。840vp 列表栏宽 +
    // 居中；约束手写在这里而不套 ContentBand，因为内容区靠 layoutWeight(1) 撑满
    // 剩余高度，需要 height('100%') 一路传到被约束的那一层。
    HdsNavDestination() {
      Stack() {
        Row() {
          Column() {
            Scroll(this.scroller) {
        Column({ space: 10 }) {
          if (this.section === SETTING_PLAYBACK) {
            OptionRow({
              title: '播放速度',
              icon: '▶',
              options: this.speedOptions(),
              current: `${this.speed}`,
              onPick: (value: string) => this.setSpeed(Number(value))
            })

            OptionRow({
              title: 'Wi-Fi 网络音质',
              icon: '📶',
              options: this.qualityOptions(),
              current: this.qualityWifi.length > 0 ? this.qualityWifi : this.quality,
              onPick: (value: string) =>
                SettingsRepository.setString(SettingsRepository.KEY_AUDIO_QUALITY_WIFI, value)
            })

            OptionRow({
              title: '非 Wi-Fi 网络音质',
              subtitle: '蜂窝网络下请求的音质档位',
              icon: '📡',
              options: this.qualityOptions(),
              current: this.qualityCellular.length > 0 ? this.qualityCellular : this.quality,
              onPick: (value: string) =>
                SettingsRepository.setString(SettingsRepository.KEY_AUDIO_QUALITY_CELLULAR, value)
            })

            ToggleRow({
              title: '允许与其他应用同时播放',
              subtitle: '其他应用开始播放时尽量不暂停本应用（系统强制抢占除外）',
              icon: '🔀',
              value: this.mixAudio,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_MIX_AUDIO, on)
            })

            SliderRow({
              title: '播放音量',
              icon: '🔊',
              min: 0,
              max: 1,
              step: 0.05,
              value: this.playbackVolume,
              format: (value: number) => `${Math.round(value * 100)}%`,
              onPick: (value: number) => PlayerManager.setVolume(value)
            })

            ToggleRow({
              title: '播放淡入淡出',
              subtitle: '开始播放时淡入，暂停与切歌时淡出',
              icon: '🎚',
              value: this.playbackFade,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_PLAYBACK_FADE, on)
            })

            if (this.playbackFade) {
              SliderRow({
                title: '播放淡入时长',
                icon: '🎚',
                min: 0,
                max: 3,
                step: 0.1,
                value: this.playbackFadeInMs / 1000,
                format: (value: number) => `当前：${value.toFixed(1)} 秒${value <= 0 ? '（禁用）' : ''}`,
                onPick: (value: number) =>
                  SettingsRepository.setNumber(SettingsRepository.KEY_PLAYBACK_FADE_IN_MS,
                    Math.round(value * 1000))
              })

              SliderRow({
                title: '播放淡出时长',
                icon: '🎚',
                min: 0,
                max: 3,
                step: 0.1,
                value: this.playbackFadeOutMs / 1000,
                format: (value: number) => `当前：${value.toFixed(1)} 秒${value <= 0 ? '（禁用）' : ''}`,
                onPick: (value: number) =>
                  SettingsRepository.setNumber(SettingsRepository.KEY_PLAYBACK_FADE_OUT_MS,
                    Math.round(value * 1000))
              })
            }

            ToggleRow({
              title: '启动应用时自动播放',
              subtitle: '启动后自动继续播放上次的歌曲',
              icon: '▷',
              value: this.autoplayOnLaunch,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_AUTOPLAY_ON_LAUNCH, on)
            })

            ToggleRow({
              title: '记住循环/随机模式',
              subtitle: '开启时恢复上次的循环与随机设置；关闭则每次启动回到列表循环',
              icon: '♻',
              value: this.keepPlaybackMode,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_KEEP_PLAYBACK_MODE_STATE, on)
            })

            ToggleRow({
              title: '随机播放',
              subtitle: '在播放页切换，此处仅显示状态',
              icon: '🔀',
              value: this.shuffle,
              onChange: (on: boolean) => PlayerManager.setShuffle(on)
            })

            ToggleRow({
              title: '播放缓存（实验）',
              subtitle: 'Wi-Fi 下缓存在线歌曲，重播秒开且不重复请求',
              icon: '⤓',
              value: this.playbackCache,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_PLAYBACK_CACHE, on)
            })
          } else if (this.section === SETTING_DOWNLOAD) {
            OptionRow({
              title: '下载并发数',
              icon: '⤓',
              options: this.concurrencyOptions(),
              current: `${this.downloadConcurrency}`,
              onPick: (value: string) =>
                SettingsRepository.setNumber(SettingsRepository.KEY_DOWNLOAD_CONCURRENCY, Number(value))
            })

            ToggleRow({
              title: '下载伴生歌词',
              subtitle: '下载完成后抓取歌词，与音频同名存为 .lrc 伴生文件',
              icon: '词',
              value: this.downloadMatchLyrics,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_DOWNLOAD_MATCH_LYRICS, on)
            })

            SettingRow({
              title: '下载目录',
              subtitle: DownloadDirectory.describeDirectory(this.downloadDirectoryUri, this.downloadDirectoryLabel),
              icon: '📁',
              onTap: () => this.pickDownloadDirectory()
            })
            if (this.downloadDirectoryUri.length > 0) {
              SettingRow({
                title: '恢复默认目录',
                subtitle: '之后的下载存回应用内部目录，已下载文件保留原处',
                icon: '↩',
                onTap: () => this.confirmResetDownloadDirectory()
              })
            }
          } else if (this.section === SETTING_LYRICS) {
            // 行组已抽成共享组件：播放页「词」面板展示同一组设置（LyricSettingsRows）。
            LyricSettingsRows()
            LyricStylePreview()
          } else if (this.section === SETTING_PLAYER) {
            Text('全屏播放器')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 10, bottom: 6 })
            Column({ space: 10 }) {
              OptionRow({
                title: '背景样式',
                icon: '🖼',
                options: this.bgStyleOptions(),
                current: this.nowplayingBgStyle,
                onPick: (value: string) =>
                  SettingsRepository.setString(SettingsRepository.KEY_NOWPLAYING_BG_STYLE, value)
              })
              ToggleRow({
                title: '保持屏幕常亮',
                subtitle: '全屏播放时屏幕不会自动熄灭',
                icon: '☀',
                value: this.keepScreenOn,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_KEEP_SCREEN_ON, on)
              })
              ToggleRow({
                title: '沉浸式取色',
                subtitle: '播放器背景随封面自动取色',
                icon: '🎨',
                value: this.dynamicColor,
                onChange: (on: boolean) => {
                  SettingsRepository.setBoolean(SettingsRepository.KEY_DYNAMIC_COLOR, on);
                  promptAction.openToast({
                    message: on
                      ? '已开启：主题色跟随当前歌曲封面'
                      : '已关闭：主题与播放页使用默认配色'
                  });
                }
              })
              ToggleRow({
                title: '圆形封面',
                subtitle: '封面以圆形唱片样式展示，播放时旋转',
                icon: '💿',
                value: this.circularCover,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_CIRCULAR_COVER, on)
              })
              ToggleRow({
                title: '歌词页显示播控按钮',
                subtitle: '在歌词页底部展示播放控制按钮',
                icon: '🎛',
                value: this.lyricPageControls,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_LYRIC_PAGE_CONTROLS, on)
              })
            }
            .width('100%')

            Text('底部 Mini 播放器')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 10 }) {
              ToggleRow({
                title: '下一首按钮',
                icon: '⏭',
                value: this.miniNextButton,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_MINI_NEXT_BUTTON, on)
              })
              ToggleRow({
                title: '展示歌词',
                subtitle: '在 Mini 播放器上显示当前歌词行',
                icon: '♪',
                value: this.miniShowLyric,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_MINI_SHOW_LYRIC, on)
              })
              ToggleRow({
                title: '展开时自动播放',
                subtitle: '从底部播放器展开到全屏播放页时自动续播',
                icon: '▷',
                value: this.miniExpandAutoplay,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_MINI_EXPAND_AUTOPLAY, on)
              })
            }
            .width('100%')

            // 参考截图底部的 (i) 脚注：交代开关的生效边界。
            Row({ space: 6 }) {
              Text('ⓘ')
                .fontSize(13)
                .fontColor(Theme.danger(Theme.isDark()))
              Text('“展开时自动播放”在从底部 Mini 播放器展开到全屏播放页时触发；播放中展开不重复操作')
                .fontSize(12)
                .fontColor(Theme.textSecondary(Theme.isDark()))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 6, right: 6, top: 6 })
            .alignItems(VerticalAlign.Top)
          } else if (this.section === SETTING_APPEARANCE) {
            OptionRow({
              title: '深色模式',
              icon: '◐',
              options: this.darkModeOptions(),
              current: this.darkMode,
              onPick: (mode: string) => this.applyDarkMode(mode)
            })
            OptionRow({
              title: '语言',
              icon: '🌐',
              options: [{ value: 'zh', label: '简体中文' }],
              current: 'zh',
              onPick: (_value: string) => promptAction.openToast({ message: '更多语言待移植' })
            })
            OptionRow({
              title: '播放页背景模糊',
              icon: '🌫',
              options: this.blurStrengthOptions(),
              current: `${this.nowplayingBlurStrength}`,
              onPick: (value: string) =>
                SettingsRepository.setNumber(SettingsRepository.KEY_NOWPLAYING_BLUR_STRENGTH, Number(value))
            })
          } else if (this.section === SETTING_NAVIGATION) {
            OptionRow({
              title: '默认启动页',
              subtitle: '冷启动后首先展示的页面',
              icon: '🧭',
              options: this.startPageOptions(),
              current: this.startPage,
              onPick: (value: string) =>
                SettingsRepository.setString(SettingsRepository.KEY_START_PAGE, value)
            })
          } else if (this.section === SETTING_TRAFFIC) {
            ToggleRow({
              title: '网易失效自动换源',
              subtitle: '网易取流失败时自动匹配 B 站音源',
              icon: '🔄',
              value: this.neteaseAutoFallback,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_NETEASE_AUTO_FALLBACK, on)
            })
            ToggleRow({
              title: '省流量模式',
              icon: '📶',
              value: this.saveTraffic,
              onChange: (on: boolean) => SettingsRepository.setBoolean(SettingsRepository.KEY_SAVE_TRAFFIC, on)
            })
            OptionRow({
              title: '封面加载策略',
              icon: '🖼',
              options: this.coverPolicyOptions(),
              current: this.coverPolicy,
              onPick: (value: string) => SettingsRepository.setString(SettingsRepository.KEY_COVER_POLICY, value)
            })
            ToggleRow({
              title: '蜂窝分平台音质',
              subtitle: '关闭后可为网易云 / Bilibili / YouTube 分别指定蜂窝网络音质',
              icon: '📶',
              value: this.cellularFollowDefault,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_CELLULAR_FOLLOW_DEFAULT, on)
            })
            if (!this.cellularFollowDefault) {
              OptionRow({
                title: '蜂窝 · 网易云',
                icon: '🎵',
                options: this.qualityOptions(),
                current: this.cellularNeteaseQuality,
                onPick: (value: string) =>
                  SettingsRepository.setString(SettingsRepository.KEY_CELLULAR_NETEASE_QUALITY, value)
              })
              OptionRow({
                title: '蜂窝 · Bilibili',
                icon: '📺',
                options: this.qualityOptions(),
                current: this.cellularBiliQuality,
                onPick: (value: string) =>
                  SettingsRepository.setString(SettingsRepository.KEY_CELLULAR_BILI_QUALITY, value)
              })
              OptionRow({
                title: '蜂窝 · YouTube',
                icon: '▶',
                options: this.qualityOptions(),
                current: this.cellularYoutubeQuality,
                onPick: (value: string) =>
                  SettingsRepository.setString(SettingsRepository.KEY_CELLULAR_YOUTUBE_QUALITY, value)
              })
            }
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
              onConfirmed: (): Promise<boolean> => this.onNeteaseConfirmed(),
              scanHint: '请用网易云音乐 App 扫码',
              pollIntervalMs: NETEASE_QR_POLL_INTERVAL_MS
            })
            SettingRow({
              title: '粘贴 Cookie 导入（网易云）',
              subtitle: '扫码不可用时的备用登录方式',
              icon: '📋',
              onTap: () => this.openNeteasePasteDialog()
            })
            if (!this.neteaseLogged) {
              SettingRow({
                title: '手机号登录（网易云）',
                subtitle: '短信验证码或密码登录',
                icon: '📱',
                onTap: () => {
                  this.showNeteasePhoneLogin = !this.showNeteasePhoneLogin;
                }
              })
              if (this.showNeteasePhoneLogin) {
                NeteasePhoneLoginPanel({
                  onConfirmed: (cookies: Map<string, string>): Promise<boolean> =>
                    this.onNeteasePhoneConfirmed(cookies)
                })
              }
            }
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
              onConfirmed: (): Promise<boolean> => this.onBiliConfirmed(),
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
            Text('本地备份')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 8, bottom: 6 })
            SettingRow({
              title: '导出歌单备份到本机',
              subtitle: '生成 JSON 文件（含歌单与播放历史，与云端备份同格式）',
              icon: '⬆',
              onTap: () => this.exportPlaylistBackup()
            })
            SettingRow({
              title: '从本机导入歌单备份',
              subtitle: '选择备份 JSON，按歌单名与歌曲稳定键合并（不覆盖本地已有）',
              icon: '⬇',
              onTap: () => this.importPlaylistBackup()
            })
            Text('GitHub 备份')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 10, bottom: 6 })
            Column({ space: 10 }) {
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

            Text('数据格式')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 10 }) {
              ToggleRow({
                title: '自动同步',
                subtitle: '变更后 5 秒静默同步；启动时补偿同步；并注册 ≥2 小时后台延迟任务',
                icon: '⚡',
                value: this.syncAuto,
                onChange: (on: boolean) => {
                  SettingsRepository.setBoolean(SettingsRepository.KEY_SYNC_AUTO, on);
                  AutoSyncScheduler.updateDelayedWorkRegistration();
                }
              })
              ToggleRow({
                title: '省流格式',
                subtitle: '上传写 Gzip Protobuf（backup-raw.bin，约 JSON 的 15%）；关闭时写 JSON',
                icon: '📉',
                value: this.githubDataSaver,
                onChange: (on: boolean) =>
                  SettingsRepository.setBoolean(SettingsRepository.KEY_GITHUB_DATA_SAVER, on)
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

            Text('WebDAV 备份')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            Column({ space: 10 }) {
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

            Text('一起听房间默认设置')
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
              .margin({ left: 6, top: 14, bottom: 6 })
            ToggleRow({
              title: '允许听众操作',
              subtitle: '建房默认：听众可切歌、播放暂停与拖动进度（房主可随时改）',
              icon: '🎚',
              value: this.ltAllowMemberControl,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_ALLOW_MEMBER_CONTROL, on)
            })
            ToggleRow({
              title: '成员变动自动暂停',
              subtitle: '建房默认：成员进入或离开时自动暂停',
              icon: '⏸',
              value: this.ltAutoPauseOnMemberChange,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_AUTO_PAUSE_ON_MEMBER_CHANGE, on)
            })
            ToggleRow({
              title: '下发音频直链',
              subtitle: '建房默认：可用时向听众下发可播放的音频直链',
              icon: '🔗',
              value: this.ltShareAudioLinks,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_LISTEN_TOGETHER_SHARE_AUDIO_LINKS, on)
            })
          } else if (this.section === SETTING_DEBUG) {
            ToggleRow({
              title: '始终记录日志',
              icon: '📝',
              value: this.alwaysRecordLogs,
              onChange: (on: boolean) =>
                SettingsRepository.setBoolean(SettingsRepository.KEY_ALWAYS_RECORD_LOGS, on)
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
              Text('版本 1.0.0 (HarmonyOS 26 / API 26)')
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
        .padding({ left: 14, right: 14, top: this.topInset + SUB_TITLEBAR_SPACE_VP, bottom: this.bottomLift + SUB_BOTTOM_CLEARANCE_VP })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            // 同 SettingsPage：Scroll 的 align 默认 Alignment.Center，tablet 实测「外观
            // 与动效」只有 3 行时整块内容悬在屏幕正中、与顶部标题之间空出 347vp。
            .align(Alignment.Top)
            .width('100%')
            // 视口延伸进底部手势条区 + 放行内容画出视口上沿滚入标题栏渐变模糊区。
            .clip(false)
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: BAND_LIST_VP })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.schemeBg(Theme.isDark()))

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
          .height(40)
          .fontSize(14)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button('导入')
          .layoutWeight(1)
          .height(40)
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
      Text('支持经典 PAT（repo 权限）与精细化令牌（Fine-grained PAT：选中备份仓库，权限给 Contents: Read and write + Metadata: Read-only；「创建备份仓库」还需 Administration: Read and write）。仅保存在本机安全存储，不会出现在日志中。')
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
          .height(40)
          .fontSize(14)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button('保存')
          .layoutWeight(1)
          .height(40)
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
          .height(40)
          .fontSize(14)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button(this.saving ? '验证中…' : '验证并保存')
          .layoutWeight(1)
          .height(40)
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
          .height(40)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.runTest();
          })
        Button('重置')
          .layoutWeight(1)
          .height(40)
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
          .height(40)
          .fontSize(14)
          .enabled(!this.testing)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .onClick(() => {
            this.controller?.close();
          })
        Button('应用')
          .layoutWeight(1)
          .height(40)
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
