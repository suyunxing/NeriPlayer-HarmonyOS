// SPDX-License-Identifier: GPL-3.0

import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileShare } from '@kit.CoreFileKit';
import { Playlist } from '../../model/Playlist';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlaylistDeleteSnapshot, PlaylistUndoOffer } from '../../data/LocalPlaylistRepository';
import { UndoBanner } from '../components/UndoBanner';
import { DownloadStorage } from '../../download/DownloadStorage';
import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { LocalMediaScanner } from '../../data/LocalMediaScanner';
import { LocalDirectoryScanner } from '../../data/LocalDirectoryScanner';
import { SettingsRepository } from '../../data/SettingsRepository';
import { DownloadDirectory } from '../../download/DownloadDirectory';
import { DownloadDirectoryManager } from '../../download/DownloadDirectoryManager';
import { PlayerManager } from '../../player/PlayerManager';
import { NeteaseApi } from '../../network/NeteaseApi';
import { NeteasePlaylistSummary } from '../../network/NeteasePlaylistParser';
import { NeteaseCookieRepository } from '../../data/auth/NeteaseCookieRepository';
import { BiliApi } from '../../network/BiliApi';
import { BiliFavFolderSummary } from '../../network/BiliFavParser';
import { BiliCookieRepository } from '../../data/auth/BiliCookieRepository';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { BAND_LIST_VP } from '../../util/Breakpoint';
import { SettingRow, EmptyState, ContentBand, FLOAT_TAB_CLEARANCE } from '../components/Ui';
import { coverThumbnailUrl } from '../../util/CoverUrls';
import { SETTING_ACCOUNTS } from './SettingsPage';

/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 2;

/** MINI 标题栏标准高度（MainShell 同名常量）：页内平台标签行顶部让位。 */
const TITLEBAR_SPACE_VP: number = 56;

/** 页内平台窗格下标。 */
const PANE_LOCAL: number = 0;
const PANE_NETEASE: number = 1;
const PANE_BILI: number = 2;

@Component
export struct LibraryPage {
  /** 滚动增量上报（MainShell 下发）：驱动悬浮栏组滚动自适应显隐，见 MainShell.handleTabBarScroll。 */
  onBarScroll: (yDelta: number) => void = () => {};
  /**
   * 平台窗格激活滚动器回调（MainShell 下发）：外壳标题栏渐变模糊与迷你条滚动
   * 阈值都按「每个底部 Tab 一个 Scroller」绑定（官方 FAQ 手法），页内分平台
   * 窗格各有滚动容器后，由本回调把激活窗格的滚动器上报壳层动态换绑。
   */
  onPaneScroller: (scroller: Scroller) => void = () => {};
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  /** 当前平台窗格：PANE_LOCAL / PANE_NETEASE / PANE_BILI。 */
  @State platformTab: number = PANE_LOCAL;
  /** 三个平台窗格各自的滚动器（官方要求滚动容器持独立 Scroller）；激活者上报壳层。 */
  private paneScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller()];
  @State playlists: Playlist[] = [];
  @State favorites: Playlist | null = null;
  @State downloadCount: number = 0;
  @State localSongCount: number = 0;
  @State scanning: boolean = false;
  @State playCount: number = 0;
  @State listenHours: number = 0;
  @State listenMinutes: number = 0;
  @State showCreateDialog: boolean = false;
  @State newPlaylistName: string = '';
  @State neteaseLogged: boolean = false;
  @State neteasePlaylists: NeteasePlaylistSummary[] = [];
  @State neteaseLoading: boolean = false;
  @State neteaseError: string = '';
  @State biliLogged: boolean = false;
  @State biliFolders: BiliFavFolderSummary[] = [];
  @State biliLoading: boolean = false;
  @State biliError: string = '';
  /**
   * 常驻 Tab 页的显式刷新钩子：改用 Navigation 之后返回不再重建 Tab 骨架，
   * 歌单改名/删除、下载完成后返回资料库原本会看到旧数据。详见 HomePage 同名成员。
   */
  @StorageProp('np.default_start_tab') activeTab: number = 0;
  @StorageProp('ui.refreshTick') @Watch('onRefreshTick') refreshTick: number = 0;
  /**
   * 下载引擎的目录变更信号（DownloadEngine.KEY_CATALOG_TICK，装饰器只收字面量）。
   * 停在本页时后台下载完成/删除也能实时刷新「已下载」计数，不必等返回信号。
   */
  @StorageProp('download.catalogTick') @Watch('onCatalogTick') catalogTick: number = 0;

  private onRefreshTick(): void {
    if (this.activeTab === TAB_INDEX) {
      this.reload();
    }
  }

  private onCatalogTick(): void {
    // 只刷新计数，不整页 reload（目录读失败时维持旧值，与 DownloadsPage 同策略）。
    DownloadStorage.getCatalog().then((catalog) => {
      this.downloadCount = catalog.length;
    }).catch(() => {});
  }

  /**
   * F-10 歌单删除撤销：PlaylistDetailPage 删除时写入的快照载荷
   * （ui.playlistUndoPending），返回本页后以底部横幅提供 6 秒撤销。
   */
  @StorageProp('ui.playlistUndoPending') @Watch('onPlaylistUndoOffered') playlistUndoJson: string = '';
  @State playlistUndoVisible: boolean = false;
  @State playlistUndoMessage: string = '';
  private playlistUndoSnapshot: PlaylistDeleteSnapshot | null = null;

  private onPlaylistUndoOffered(): void {
    if (this.playlistUndoJson.length === 0) {
      this.playlistUndoVisible = false;
      return;
    }
    const offer = PlaylistUndoOffer.fromJson(this.playlistUndoJson);
    if (offer === null) {
      this.dismissPlaylistUndo();
      return;
    }
    // 陈旧载荷（页面重建重放）不弹横幅。
    if (Date.now() - offer.offeredAt > 15000) {
      this.dismissPlaylistUndo();
      return;
    }
    const snapshot = PlaylistDeleteSnapshot.fromJson(offer.snapshotJson);
    if (snapshot === null) {
      this.dismissPlaylistUndo();
      return;
    }
    this.playlistUndoSnapshot = snapshot;
    this.playlistUndoMessage = `已删除「${offer.name.length > 0 ? offer.name : '歌单'}」`;
    this.playlistUndoVisible = true;
  }

  private async undoPlaylistDelete(): Promise<void> {
    const snapshot = this.playlistUndoSnapshot;
    this.dismissPlaylistUndo();
    if (snapshot === null) {
      return;
    }
    const restored = await LocalPlaylistRepository.restorePlaylistFromUndo(snapshot);
    promptAction.openToast({ message: restored ? '已恢复歌单' : '恢复失败，同 ID 歌单可能已存在' });
    await this.reload();
  }

  private dismissPlaylistUndo(): void {
    this.playlistUndoVisible = false;
    this.playlistUndoMessage = '';
    this.playlistUndoSnapshot = null;
    AppStorage.setOrCreate('ui.playlistUndoPending', '');
  }

  async aboutToAppear(): Promise<void> {
    // 首个激活窗格的滚动器先于任何滚动上报壳层，标题栏模糊换绑才不落后一拍。
    this.onPaneScroller(this.paneScrollers[this.platformTab]);
    await this.reload();
  }

  /** 平台窗格切换：onAnimationStart（动画起始，高亮即时）与 onChange（终态兜底）共用。 */
  private onPlatformChange(index: number): void {
    if (this.platformTab === index) {
      return;
    }
    this.platformTab = index;
    this.onPaneScroller(this.paneScrollers[index]);
  }

  /** 本地用户歌单：收藏是伪歌单（id 固定），单独成行展示，不混进列表。 */
  private localUserPlaylists(): Playlist[] {
    return this.playlists.filter((playlist: Playlist) => playlist.id !== LocalPlaylistRepository.FAVORITES_ID);
  }

  private async reload(): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    this.playlists = playlists;
    this.favorites = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID) ?? null;
    const catalog = await DownloadStorage.getCatalog();
    this.downloadCount = catalog.length;
    // Directory library cache (persisted) wins; picker imports stay in the
    // session memory cache as before.
    const persisted = await LocalDirectoryScanner.loadCached();
    this.localSongCount = persisted.length > 0 ? persisted.length
      : (await LocalMediaScanner.loadCached()).length;
    this.playCount = await PlaybackStatsRepository.getTotalPlayCount();
    const listenMs = await PlaybackStatsRepository.getTotalListenMs();
    this.listenHours = Math.floor(listenMs / 3600000);
    this.listenMinutes = Math.floor((listenMs % 3600000) / 60000);
    // Credential restore is fired un-awaited in EntryAbility.onCreate; wait
    // for it so a cold start never reads isLoggedIn() before the asset-backed
    // bundles have loaded (init() is idempotent and resolves once done).
    await NeteaseCookieRepository.init();
    await BiliCookieRepository.init();
    this.neteaseLogged = NeteaseCookieRepository.isLoggedIn();
    if (this.neteaseLogged) {
      this.refreshNeteasePlaylists();
    }
    this.biliLogged = BiliCookieRepository.isLoggedIn();
    if (this.biliLogged) {
      this.refreshBiliFavFolders();
    }
  }

  private refreshBiliFavFolders(): void {
    const mid = BiliCookieRepository.getMid();
    if (mid <= 0) {
      this.biliError = '无法获取用户 mid（DedeUserID 缺失）';
      return;
    }
    this.biliLoading = true;
    this.biliError = '';
    BiliApi.getUserFavFolders(mid)
      .then((folders: BiliFavFolderSummary[]) => {
        this.biliFolders = folders;
      })
      .catch((error: Error) => {
        this.biliError = error.message;
      })
      .finally(() => {
        this.biliLoading = false;
      });
  }

  private refreshNeteasePlaylists(): void {
    this.neteaseLoading = true;
    this.neteaseError = '';
    NeteaseApi.getUserPlaylists(0, 100)
      .then((items: NeteasePlaylistSummary[]) => {
        this.neteasePlaylists = items;
      })
      .catch((error: Error) => {
        this.neteaseError = error.message;
      })
      .finally(() => {
        this.neteaseLoading = false;
      });
  }

  private async createPlaylist(): Promise<void> {
    this.newPlaylistName = '';
    this.showCreateDialog = true;
  }

  private async confirmCreate(): Promise<void> {
    const trimmed = this.newPlaylistName.trim();
    if (trimmed.length === 0) {
      promptAction.openToast({ message: '请输入歌单名称' });
      return;
    }
    await LocalPlaylistRepository.createPlaylist(trimmed);
    this.showCreateDialog = false;
    await this.reload();
  }

  private async scanLocal(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
      if (context === undefined) {
        promptAction.openToast({ message: '应用上下文未就绪' });
        return;
      }
      // Directory library first (backlog §8): a persisted scan root triggers a
      // recursive refresh; without one fall back to the audio picker.
      const dirUri = SettingsRepository.getString(SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_URI, '');
      if (dirUri.length > 0) {
        this.scanning = true;
        try {
          const songs = await LocalDirectoryScanner.scanPersistedDirectory(dirUri);
          this.localSongCount = songs.length;
          promptAction.openToast({ message: `本地音乐库已刷新：${songs.length} 首` });
        } finally {
          this.scanning = false;
        }
        await this.reload();
        return;
      }
      const songs = await LocalMediaScanner.scan(context);
      this.localSongCount = songs.length;
      promptAction.openToast({ message: `已导入 ${songs.length} 首本地音乐` });
      await this.reload();
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `扫描失败：${e.message}` });
    }
  }

  /** Picks the library scan root (DocumentViewPicker FOLDER + persist). */
  private localScanDirLabel(): string {
    return SettingsRepository.getString(SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_LABEL, '');
  }

  private async playLocalLibrary(): Promise<void> {
    const songs = await LocalDirectoryScanner.loadCached();
    if (songs.length === 0) {
      promptAction.openToast({ message: '本地音乐库为空' });
      return;
    }
    PlayerManager.playPlaylist(songs, 0);
  }

  private async pickLocalScanDirectory(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
      if (context === undefined) {
        promptAction.openToast({ message: '应用上下文未就绪' });
        return;
      }
      if (!DownloadDirectoryManager.folderPickerSupported()) {
        promptAction.openToast({ message: '当前系统不支持选择文件夹' });
        return;
      }
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const dirUri = uris[0];
      const policy: fileShare.PolicyInfo = {
        uri: dirUri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      await fileShare.persistPermission([policy]);
      SettingsRepository.setString(SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_URI, dirUri);
      SettingsRepository.setString(SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_LABEL,
        DownloadDirectory.labelFromUri(dirUri));
      promptAction.openToast({ message: '已设置本地音乐库目录，正在扫描...' });
      await this.scanLocal();
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `设置目录失败：${e.message}` });
    }
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  /**
   * 同 schemeBg：强调色节点（平台标签选中态、新建/创建/重试/去登录按钮、歌单
   * 占位图标）直接写 Theme.primary() 是无跟踪调用（M7.4），换歌后不会重染；
   * 先摸被跟踪的 coverScheme 注册依赖，取值依旧交给 Theme 统一决策。
   */
  private accentPrimary(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(dark) : Theme.primary(dark);
  }

  /**
   * 平台窗格滚动容器的公共底座：滚动增量上报壳层（迷你条形变）、关闭滚动条。
   * 内容避让由各窗格自行 padding（顶部接平台标签行，底部让位悬浮栏组）。
   * 内容经 if/else 分派到各窗格 @Builder——UI 语法只能写在 @Builder 方法体里，
   * 不能装进普通函数参数（与 ContentBand 的 @BuilderParam 尾闭包同一条边界）。
   */
  @Builder
  paneScroll(paneIndex: number) {
    Scroll(this.paneScrollers[paneIndex]) {
      ContentBand({ maxWidth: BAND_LIST_VP }) {
        Column({ space: 12 }) {
          if (paneIndex === PANE_LOCAL) {
            this.localContent()
          } else if (paneIndex === PANE_NETEASE) {
            this.neteaseContent()
          } else {
            this.biliContent()
          }
        }
        .width('100%')
        .padding({ top: 12, left: 14, right: 14, bottom: 24 + FLOAT_TAB_CLEARANCE })
      }
    }
    .scrollBar(BarState.Off)
    .onScrollFrameBegin((offset: number) => {
      this.onBarScroll(offset);
      return { offsetRemain: offset };
    })
    .width('100%')
    .height('100%')
  }

  /**
   * 平台页签：文字宽度即页签宽度（BarMode.Scrollable），选中态强调色 + 底边
   * 下划线。下划线画在文字底边框上——宽度天然跟随文字，免测文字宽。
   */
  @Builder
  platformTabItem(index: number, label: string) {
    Text(label)
      .fontSize(15)
      .fontWeight(this.platformTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.platformTab === index ? this.accentPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
      .padding({ left: 14, right: 14, top: 12, bottom: 9 })
      .borderWidth({ bottom: 3 })
      .borderColor(this.platformTab === index ? this.accentPrimary(Theme.isDark()) : Color.Transparent)
  }

  @Builder
  localPane() {
    this.paneScroll(PANE_LOCAL)
  }

  @Builder
  neteasePane() {
    this.paneScroll(PANE_NETEASE)
  }

  @Builder
  biliPane() {
    this.paneScroll(PANE_BILI)
  }

  /** 本地窗格内容：新建歌单入口、我的收藏 + 用户歌单、本地音频、更多。 */
  @Builder
  localContent() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_add_24'))
        .width(20)
        .height(20)
        .fillColor(this.accentPrimary(Theme.isDark()))
      Text('新建歌单')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary(Theme.isDark()))
    }
    .width('100%')
    .height(48)
    .padding({ left: 14 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(Theme.cardRadius())
    .onClick(() => this.createPlaylist())

    if (this.favorites === null && this.localUserPlaylists().length === 0) {
      EmptyState({
        icon: '♪',
        title: '暂无本地歌单',
        subtitle: '点击「新建歌单」创建第一个歌单'
      })
    } else {
      Column({ space: 1 }) {
        if (this.favorites !== null) {
          Row({ space: 12 }) {
            Image($r('app.media.ic_baseline_favorite_24'))
              .width(22)
              .height(22)
              .fillColor(this.accentPrimary(Theme.isDark()))
              .margin({ left: 11, right: 11, top: 11, bottom: 11 })
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(8)
            Column({ space: 2 }) {
              Text('我的收藏')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.favorites.songKeys.length} 首`)
                .fontSize(12)
                .fontColor(Theme.textSecondary(Theme.isDark()))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Image($r('app.media.ic_chevron_right_24'))
              .width(18)
              .height(18)
              .fillColor(Theme.textDisabled(Theme.isDark()))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(Theme.surface(Theme.isDark()))
          .onClick(() => Router.push(Router.PLAYLIST_DETAIL, LocalPlaylistRepository.FAVORITES_ID))
        }
        ForEach(this.localUserPlaylists(), (playlist: Playlist) => {
          Row({ space: 12 }) {
            Image($r('app.media.ic_library_music_24'))
              .width(22)
              .height(22)
              .fillColor(this.accentPrimary(Theme.isDark()))
              .margin({ left: 11, right: 11, top: 11, bottom: 11 })
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(8)
            Column({ space: 2 }) {
              Text(playlist.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(playlist.songKeys.length > 0 ? `${playlist.songKeys.length} 首` : '空歌单')
                .fontSize(12)
                .fontColor(Theme.textSecondary(Theme.isDark()))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Image($r('app.media.ic_chevron_right_24'))
              .width(18)
              .height(18)
              .fillColor(Theme.textDisabled(Theme.isDark()))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(Theme.surface(Theme.isDark()))
          .onClick(() => Router.push(Router.PLAYLIST_DETAIL, playlist.id))
        }, (playlist: Playlist) => playlist.id)
      }
      .width('100%')
      .borderRadius(Theme.cardRadius())
      .clip(true)
    }

    Row() {
      Text('本地音频')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .layoutWeight(1)
      Button('扫描')
        .height(40)
        .fontSize(13)
        .backgroundColor(Theme.surface(Theme.isDark()))
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .onClick(() => this.scanLocal())
    }
    .width('100%')

    SettingRow({
      title: '本地音乐库目录',
      subtitle: this.localScanDirLabel().length > 0
        ? `${this.localScanDirLabel()} · 点击重新扫描` : '选择文件夹后自动递归收录音频（含同名 .lrc 歌词）',
      icon: '🗂',
      onTap: () => this.pickLocalScanDirectory()
    })

    if (SettingsRepository.getString(SettingsRepository.KEY_LOCAL_SCAN_DIRECTORY_URI, '').length > 0) {
      SettingRow({
        title: this.scanning ? '正在扫描本地音乐库...' : '扫描本地音乐库',
        subtitle: this.localSongCount > 0 ? `已收录 ${this.localSongCount} 首 · 点击立即播放` : '点击扫描所选目录',
        icon: '♫',
        onTap: () => {
          if (this.localSongCount > 0) {
            this.playLocalLibrary();
            return;
          }
          this.scanLocal();
        }
      })
    }

    Text('更多')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.textPrimary(Theme.isDark()))
      .width('100%')

    Column({ space: 1 }) {
      SettingRow({
        title: '已下载',
        subtitle: `${this.downloadCount} 首 · 点击管理`,
        icon: '⤓',
        onTap: () => Router.push(Router.DOWNLOADS)
      })
      SettingRow({
        title: '播放历史',
        subtitle: `累计播放 ${this.playCount} 次`,
        icon: '⏱',
        onTap: () => Router.push(Router.RECENT)
      })
      SettingRow({
        title: '播放统计',
        subtitle: `累计收听 ${this.listenHours} 小时 ${this.listenMinutes} 分钟`,
        icon: '📊',
        onTap: () => Router.push(Router.STATS)
      })
      SettingRow({
        title: '一起听',
        subtitle: '创建或加入房间，与好友同步播放',
        icon: '👥',
        onTap: () => Router.push(Router.LISTEN_TOGETHER)
      })
    }
    .width('100%')
    .borderRadius(Theme.cardRadius())
    .clip(true)
  }

  /** 网易云窗格内容：未登录给登录入口；已登录为刷新 + 错误/空态/歌单列表。 */
  @Builder
  neteaseContent() {
    if (!this.neteaseLogged) {
      this.loginPrompt('🎵', '未登录网易云音乐', '登录后同步你的网易云歌单到资料库')
    } else {
      Row() {
        Text(`共 ${this.neteasePlaylists.length} 个歌单`)
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .layoutWeight(1)
        Button(this.neteaseLoading ? '加载中…' : '刷新')
          .height(40)
          .fontSize(13)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .enabled(!this.neteaseLoading)
          .onClick(() => this.refreshNeteasePlaylists())
      }
      .width('100%')

      if (this.neteaseError.length > 0) {
        Column({ space: 8 }) {
          Text(`加载失败：${this.neteaseError}`)
            .fontSize(13)
            .fontColor(Theme.textSecondary(Theme.isDark()))
          Button('重试')
            .height(40)
            .fontSize(13)
            .backgroundColor(this.accentPrimary(Theme.isDark()))
            .onClick(() => this.refreshNeteasePlaylists())
        }
        .width('100%')
        .padding(16)
      } else if (this.neteasePlaylists.length === 0) {
        EmptyState({
          icon: '🎵',
          title: this.neteaseLoading ? '正在加载歌单…' : '暂无歌单',
          subtitle: '在网易云 App 创建歌单后点「刷新」'
        })
      } else {
        Column({ space: 1 }) {
          ForEach(this.neteasePlaylists, (item: NeteasePlaylistSummary) => {
            Row({ space: 12 }) {
              if (item.coverUrl.length > 0) {
                Image(coverThumbnailUrl(item.coverUrl, 400))
                  .autoResize(true)
                  .width(44)
                  .height(44)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              } else {
                Image($r('app.media.ic_music_note_24'))
                  .width(22)
                  .height(22)
                  .fillColor(this.accentPrimary(Theme.isDark()))
                  .margin({ left: 11, right: 11, top: 11, bottom: 11 })
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .borderRadius(8)
              }
              Column({ space: 2 }) {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.trackCount > 0 ? `${item.trackCount} 首` : '空歌单')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Image($r('app.media.ic_chevron_right_24'))
                .width(18)
                .height(18)
                .fillColor(Theme.textDisabled(Theme.isDark()))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(Theme.surface(Theme.isDark()))
            .onClick(() => Router.push(Router.NETEASE_PLAYLIST, `${item.id}`))
          }, (item: NeteasePlaylistSummary) => `${item.id}`)
        }
        .width('100%')
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
    }
  }

  /** B站窗格内容：未登录给登录入口；已登录为刷新 + 错误/空态/收藏夹列表。 */
  @Builder
  biliContent() {
    if (!this.biliLogged) {
      this.loginPrompt('📺', '未登录哔哩哔哩', '登录后浏览你的B站收藏夹')
    } else {
      Row() {
        Text(`共 ${this.biliFolders.length} 个收藏夹`)
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .layoutWeight(1)
        Button(this.biliLoading ? '加载中…' : '刷新')
          .height(40)
          .fontSize(13)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .enabled(!this.biliLoading)
          .onClick(() => this.refreshBiliFavFolders())
      }
      .width('100%')

      if (this.biliError.length > 0) {
        Column({ space: 8 }) {
          Text(`加载失败：${this.biliError}`)
            .fontSize(13)
            .fontColor(Theme.textSecondary(Theme.isDark()))
          Button('重试')
            .height(40)
            .fontSize(13)
            .backgroundColor(this.accentPrimary(Theme.isDark()))
            .onClick(() => this.refreshBiliFavFolders())
        }
        .width('100%')
        .padding(16)
      } else if (this.biliFolders.length === 0) {
        EmptyState({
          icon: '📺',
          title: this.biliLoading ? '正在加载收藏夹…' : '暂无收藏夹',
          subtitle: '在哔哩哔哩收藏视频后点「刷新」'
        })
      } else {
        Column({ space: 1 }) {
          ForEach(this.biliFolders, (item: BiliFavFolderSummary) => {
            Row({ space: 12 }) {
              if (item.coverUrl.length > 0) {
                Image(coverThumbnailUrl(item.coverUrl, 400))
                  .autoResize(true)
                  .width(44)
                  .height(44)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              } else {
                Image($r('app.media.ic_bilibili'))
                  .width(24)
                  .height(24)
                  .margin({ left: 10, right: 10, top: 10, bottom: 10 })
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .borderRadius(8)
              }
              Column({ space: 2 }) {
                Text(item.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.mediaCount > 0 ? `${item.mediaCount} 条` : '空收藏夹')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Image($r('app.media.ic_chevron_right_24'))
                .width(18)
                .height(18)
                .fillColor(Theme.textDisabled(Theme.isDark()))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(Theme.surface(Theme.isDark()))
            .onClick(() => Router.push(Router.BILI_FAV, `${item.mediaId}`))
          }, (item: BiliFavFolderSummary) => `${item.mediaId}`)
        }
        .width('100%')
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
    }
  }

  /** 平台未登录的窗格空态：空态文案 + 登录入口（接替原「平台」分区的登录行）。 */
  @Builder
  loginPrompt(icon: string, title: string, subtitle: string) {
    Column({ space: 16 }) {
      EmptyState({ icon: icon, title: title, subtitle: subtitle })
      Button('去登录')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.accentPrimary(Theme.isDark()))
        .onClick(() => Router.push(Router.SETTINGS_DETAIL, SETTING_ACCOUNTS))
    }
    .width('100%')
    .padding({ top: 96 })
  }

  build() {
    Stack() {
      // 标题「资料库」仍由 MainShell 的 HdsNavigation MINI 标题栏承载；页内改为
      // 安卓版同款平台横向标签（本地/网易云/B站），标签行固定在标题栏下方，
      // 三个平台窗格各自独立滚动（滚动态互不串扰，切回仍保留各自的阅读位置）。
      Column() {
        Tabs({ barPosition: BarPosition.Start, index: this.platformTab }) {
          TabContent() {
            this.localPane()
          }
          .tabBar(this.platformTabItem(PANE_LOCAL, '本地'))

          TabContent() {
            this.neteasePane()
          }
          .tabBar(this.platformTabItem(PANE_NETEASE, '网易云'))

          TabContent() {
            this.biliPane()
          }
          .tabBar(this.platformTabItem(PANE_BILI, 'B站'))
        }
        .vertical(false)
        // Scrollable：页签按内容实际宽度排布（同安卓版的可滚动平台标签），
        // 平台增多溢出时标签行自身可横滚。
        .barMode(BarMode.Scrollable)
        // 不开放左右滑切窗格：与外壳 HdsTabs 同一策略，避免与列表/卡片横滑手势争抢。
        .scrollable(false)
        .animationDuration(250)
        .divider({
          strokeWidth: 0.5,
          color: Theme.withAlpha(Theme.textPrimary(Theme.isDark()), 0x1F),
          startMargin: 0,
          endMargin: 0
        })
        .layoutWeight(1)
        .width('100%')
        // 高亮即时性：onChange 在切页动画结束后才回调（官方 FAQ faqs-arkui-568），
        // 动画开始的 targetIndex 先行更新选中态，onChange 兜底终态。
        .onAnimationStart((_index: number, targetIndex: number, _event: TabsAnimationEvent) => {
          this.onPlatformChange(targetIndex);
        })
        .onChange((index: number) => {
          this.onPlatformChange(index);
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: TITLEBAR_SPACE_VP })

      // F-10：歌单删除撤销横幅（底部浮层；外层透明不拦截列表触控）。
      Column() {
        Blank()
        UndoBanner({
          message: this.playlistUndoMessage,
          visible: this.playlistUndoVisible,
          onUndo: () => {
            void this.undoPlaylistDelete();
          },
          onExpire: () => {
            this.dismissPlaylistUndo();
          }
        })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showCreateDialog) {
        Column() {
          Column({ space: 12 }) {
            Text('新建歌单')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            TextInput({ placeholder: '输入歌单名称', text: this.newPlaylistName })
              .onChange((value: string) => {
                this.newPlaylistName = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => {
                  this.showCreateDialog = false;
                })
              Button('创建')
                .layoutWeight(1)
                .backgroundColor(this.accentPrimary(Theme.isDark()))
                .onClick(() => this.confirmCreate())
            }
            .width('100%')
          }
          .width('86%')
          .padding(20)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showCreateDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
