import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { DownloadStorage } from '../../download/DownloadStorage';
import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { LocalMediaScanner } from '../../data/LocalMediaScanner';
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
import { iconForLegacy } from '../../util/IconCatalog';
import { SettingRow, EmptyState, SongCountChip, ContentBand, FLOAT_TAB_CLEARANCE } from '../components/Ui';
import { SETTING_ACCOUNTS } from './SettingsPage';

/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 2;

@Component
export struct LibraryPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State playlists: Playlist[] = [];
  @State favorites: Playlist | null = null;
  @State downloadCount: number = 0;
  @State localSongCount: number = 0;
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

  private onRefreshTick(): void {
    if (this.activeTab === TAB_INDEX) {
      this.reload();
    }
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    this.playlists = playlists;
    this.favorites = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID) ?? null;
    const catalog = await DownloadStorage.getCatalog();
    this.downloadCount = catalog.length;
    this.localSongCount = (await LocalMediaScanner.loadCached()).length;
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

  private async playFavorites(): Promise<void> {
    const favorites = this.favorites;
    if (favorites === null || favorites.songs.length === 0) {
      promptAction.openToast({ message: '收藏夹为空' });
      return;
    }
    await PlayerManager.playPlaylist(favorites.songs, 0);
  }

  private async scanLocal(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
      if (context === undefined) {
        promptAction.openToast({ message: '应用上下文未就绪' });
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


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    Stack() {
      Scroll() {
        // 840vp 栏宽约束：tablet 1440vp 下这些设置行的文本原本被拉到 1300vp 以上，
        // 一行要横扫整块屏。窄屏不触发约束，布局与改造前逐像素一致。
        ContentBand({ maxWidth: BAND_LIST_VP }) {
        Column({ space: 12 }) {
        Text('资料库')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .width('100%')
          .margin({ top: 12 })

        Row({ space: 10 }) {
          StatCard({
            icon: '❤',
            value: this.favorites !== null ? `${this.favorites.songKeys.length} 首` : '0 首',
            label: '我的收藏',
            onTap: () => {
              if (this.favorites !== null) {
                Router.push(Router.PLAYLIST_DETAIL, LocalPlaylistRepository.FAVORITES_ID);
              }
            }
          })
          StatCard({
            icon: '⤓',
            value: `${this.downloadCount} 首`,
            label: '已下载',
            onTap: () => Router.push(Router.DOWNLOADS)
          })
          StatCard({
            icon: '♫',
            value: `${this.localSongCount} 首`,
            label: '本地音频',
            onTap: () => this.scanLocal()
          })
        }
        .width('100%')

        Column({ space: 1 }) {
          SettingRow({
            title: '我的收藏',
            subtitle: this.favorites !== null ? `${this.favorites.songKeys.length} 首 · 点击播放` : '还没有收藏歌曲',
            icon: '❤',
            onTap: () => {
              if (this.favorites !== null) {
                Router.push(Router.PLAYLIST_DETAIL, LocalPlaylistRepository.FAVORITES_ID);
              }
            }
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
            title: '下载管理',
            subtitle: this.downloadCount > 0 ? `已下载 ${this.downloadCount} 首` : '暂无下载内容',
            icon: '⤓',
            onTap: () => Router.push(Router.DOWNLOADS)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        Row() {
          Text('本地歌单')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Button('＋ 新建')
            .height(40)
            .fontSize(13)
            .backgroundColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.createPlaylist())
        }
        .width('100%')
        .margin({ top: 6 })

        if (this.playlists.length === 0) {
          EmptyState({
            icon: '♪',
            title: '暂无本地歌单',
            subtitle: '点击「新建」创建第一个歌单'
          })
        } else {
          Column({ space: 1 }) {
            ForEach(this.playlists, (playlist: Playlist) => {
              Row({ space: 12 }) {
                Image($r('app.media.ic_library_music_24'))
                  .width(22)
                  .height(22)
                  .fillColor(Theme.primary(Theme.isDark()))
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

        if (this.neteaseLogged) {
          Row() {
            Text('网易云歌单')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
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
          .margin({ top: 12 })

          if (this.neteaseError.length > 0) {
            Column({ space: 8 }) {
              Text(`加载失败：${this.neteaseError}`)
                .fontSize(13)
                .fontColor(Theme.textSecondary(Theme.isDark()))
              Button('重试')
                .height(40)
                .fontSize(13)
                .backgroundColor(Theme.primary(Theme.isDark()))
                .onClick(() => this.refreshNeteasePlaylists())
            }
            .width('100%')
            .padding(16)
          } else if (this.neteasePlaylists.length === 0) {
            EmptyState({
              icon: '🎵',
              title: this.neteaseLoading ? '正在加载歌单…' : '暂无歌单',
              subtitle: '下拉刷新或在网易云 App 创建歌单后刷新'
            })
          } else {
            Column({ space: 1 }) {
              ForEach(this.neteasePlaylists, (item: NeteasePlaylistSummary) => {
                Row({ space: 12 }) {
                  if (item.coverUrl.length > 0) {
                    Image(item.coverUrl)
                      .width(44)
                      .height(44)
                      .borderRadius(8)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  } else {
                    Image($r('app.media.ic_music_note_24'))
                      .width(22)
                      .height(22)
                      .fillColor(Theme.primary(Theme.isDark()))
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

        if (this.biliLogged) {
          Row() {
            Text('B 站收藏夹')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
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
          .margin({ top: 12 })

          if (this.biliError.length > 0) {
            Column({ space: 8 }) {
              Text(`加载失败：${this.biliError}`)
                .fontSize(13)
                .fontColor(Theme.textSecondary(Theme.isDark()))
              Button('重试')
                .height(40)
                .fontSize(13)
                .backgroundColor(Theme.primary(Theme.isDark()))
                .onClick(() => this.refreshBiliFavFolders())
            }
            .width('100%')
            .padding(16)
          } else if (this.biliFolders.length === 0) {
            EmptyState({
              icon: '📺',
              title: this.biliLoading ? '正在加载收藏夹…' : '暂无收藏夹',
              subtitle: '在哔哩哔哩收藏视频后刷新'
            })
          } else {
            Column({ space: 1 }) {
              ForEach(this.biliFolders, (item: BiliFavFolderSummary) => {
                Row({ space: 12 }) {
                  if (item.coverUrl.length > 0) {
                    Image(item.coverUrl)
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
        .margin({ top: 12 })

        SettingRow({
          title: '本地音乐库',
          subtitle: this.localSongCount > 0 ? `已收录 ${this.localSongCount} 首本地音频` : '点击扫描手机上的音频文件',
          icon: '🗂',
          onTap: () => this.scanLocal()
        })

        Text('平台')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .width('100%')
          .margin({ top: 12 })

        Column({ space: 1 }) {
          SettingRow({
            title: '网易云音乐',
            subtitle: this.neteaseLogged
              ? `已登录 · ${this.neteasePlaylists.length} 个歌单`
              : '未登录 · 点击扫码登录，同步我的歌单',
            icon: '🎵',
            onTap: () => {
              if (!this.neteaseLogged) {
                Router.push(Router.SETTINGS_DETAIL, SETTING_ACCOUNTS);
              } else if (this.neteasePlaylists.length === 0 && !this.neteaseLoading) {
                this.refreshNeteasePlaylists();
              }
            }
          })
          SettingRow({
            title: 'Bilibili',
            subtitle: this.biliLogged
              ? `已登录 · ${this.biliFolders.length} 个收藏夹`
              : '未登录 · 点击扫码登录，浏览我的收藏夹',
            icon: '📺',
            onTap: () => {
              if (!this.biliLogged) {
                Router.push(Router.SETTINGS_DETAIL, SETTING_ACCOUNTS);
              } else if (this.biliFolders.length === 0 && !this.biliLoading) {
                this.refreshBiliFavFolders();
              }
            }
          })
          SettingRow({
            title: '一起听',
            subtitle: '创建或加入房间，与好友同步播放',
            icon: '👥',
            onTap: () => Router.push(Router.LISTEN_TOGETHER)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 24 + FLOAT_TAB_CLEARANCE })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .backgroundColor(this.schemeBg(Theme.isDark()))

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
                .backgroundColor(Theme.primary(Theme.isDark()))
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
  }
}

@Component
struct StatCard {
  icon: string = '';
  value: string = '';
  label: string = '';
  onTap: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Image(iconForLegacy(this.icon, $r('app.media.ic_music_note_24')))
        .width(22)
        .height(22)
        .fillColor(Theme.primary(Theme.isDark()))
      Text(this.value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
      Text(this.label)
        .fontSize(11)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14, left: 6, right: 6 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(14)
    .onClick(() => this.onTap())
  }
}
