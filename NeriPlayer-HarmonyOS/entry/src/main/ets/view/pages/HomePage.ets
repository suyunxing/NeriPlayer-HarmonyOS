import { SongItem } from '../../model/SongItem';
import { Playlist } from '../../model/Playlist';
import { UsageRepository, UsageEntry } from '../../data/UsageRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { NeteaseApi } from '../../network/NeteaseApi';
import { NeteasePlaylistSummary } from '../../network/NeteasePlaylistParser';
import { NetworkStatus } from '../../util/NetworkStatus';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { BAND_LIST_VP, BP_LG, BP_MD } from '../../util/Breakpoint';
import { SectionHeader, EmptyState, LoadingState, PlaylistCard, ContentBand } from '../components/Ui';

const BRAND_TITLES: string[] = ['NeriPlayer', '欢迎回来', 'NeriPlayer', '继续听歌'];
/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 0;

@Component
export struct HomePage {
  @State usage: UsageEntry[] = [];
  @State localPlaylists: Playlist[] = [];
  @State recentSongs: SongItem[] = [];
  @State neteaseRecommend: NeteasePlaylistSummary[] = [];
  @State loading: boolean = true;
  @State offline: boolean = false;
  @State titleIndex: number = 0;
  /** 由 util/WindowMetrics.ets 发布，决定网格列数与推荐区形态。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';
  /**
   * 常驻 Tab 页的显式刷新钩子。改用 Navigation 之后全屏路由不再销毁 Tab 骨架，
   * 返回时 aboutToAppear 不重跑，原先靠子树重建拿到的隐式刷新会消失（歌单改名
   * 或删除后返回会看到旧数据）。Router.notifyReturned() 自增 ui.refreshTick，
   * 这里按当前可见 Tab 过滤，避免隐藏页白跑一次网络请求。
   */
  @StorageProp('np.default_start_tab') activeTab: number = 0;
  @StorageProp('ui.refreshTick') @Watch('onRefreshTick') refreshTick: number = 0;

  private onRefreshTick(): void {
    if (this.activeTab === TAB_INDEX) {
      this.reload();
    }
  }

  /**
   * md（≥600vp）起把横向滚动的推荐区改成多列网格铺开：横向滚动在宽屏上只用掉
   * 一行高度，剩下的宽度全是空白，而内容其实有 30 条。
   */
  private wideGrid(): boolean {
    return this.breakpoint === BP_MD || this.breakpoint === BP_LG;
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.offline = !(await NetworkStatus.hasNetwork());
    const usage = await UsageRepository.load();
    this.usage = usage;
    const playlists = await LocalPlaylistRepository.loadAll();
    this.localPlaylists = playlists;
    this.recentSongs = await HistoryRepository.getRecent();
    this.loading = false;
    this.loadNeteaseRecommend();
  }

  /**
   * NetEase personalized playlists (/weapi/personalized/playlist, also works
   * anonymously). Fails silently: the section just stays hidden.
   */
  private loadNeteaseRecommend(): void {
    if (this.offline) {
      return;
    }
    NeteaseApi.getRecommendedPlaylists(30)
      .then((items: NeteasePlaylistSummary[]) => {
        this.neteaseRecommend = items;
      })
      .catch(() => {
        this.neteaseRecommend = [];
      });
  }

  private refresh(): void {
    this.titleIndex = (this.titleIndex + 1) % BRAND_TITLES.length;
    this.reload();
  }

  private openEntry(entry: UsageEntry): void {
    if (entry.subtype === 'song') {
      const song = this.recentSongs.find((item: SongItem) => item.audioId === entry.id);
      if (song !== undefined) {
        PlayerManager.playPlaylist(this.recentSongs, this.recentSongs.indexOf(song));
      }
      return;
    }
    if (entry.source === 'local') {
      Router.push(Router.PLAYLIST_DETAIL, entry.id);
    }
  }

  private playRecent(index: number): void {
    PlayerManager.playPlaylist(this.recentSongs, index);
  }

  build() {
    Column() {
      Row() {
        Text(BRAND_TITLES[this.titleIndex])
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
        Button() {
          Image($r('app.media.outline_refresh_24'))
            .width(22)
            .height(22)
            .fillColor(Theme.textPrimary(Theme.isDark()))
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(Theme.surface(Theme.isDark()))
        .accessibilityText('刷新推荐')
        .onClick(() => this.refresh())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 8 })

      Scroll() {
        Column() {
          if (this.loading) {
            LoadingState()
          } else if (this.offline && this.usage.length === 0 && this.localPlaylists.length === 0) {
            EmptyState({
              icon: '📴',
              title: '离线模式',
              subtitle: '暂无本地内容，联网后可继续浏览推荐'
            })
          } else {
            if (this.usage.length > 0) {
              SectionHeader({ title: '继续收听', icon: '↻' })
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.usage, (entry: UsageEntry) => {
                    Column({ space: 6 }) {
                      Stack() {
                        if (entry.picUrl.length > 0) {
                          Image(entry.picUrl)
                            .width(132)
                            .height(132)
                            .borderRadius(16)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(40)
                            .height(40)
                            .fillColor(Theme.primary(Theme.isDark()))
                            .margin({ left: 46, right: 46, top: 46, bottom: 46 })
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                            .borderRadius(16)
                        }
                      }
                      Text(entry.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width(132)
                      Text(entry.trackCount > 0 ? `${entry.trackCount} 首` : '播放历史')
                        .fontSize(11)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                        .width(132)
                    }
                    .onClick(() => this.openEntry(entry))
                  }, (entry: UsageEntry) => `${entry.source}_${entry.id}_${entry.subtype}`)
                }
                .padding({ left: 4, right: 4 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }

            if (this.recentSongs.length > 0) {
              // 最近播放是列表而不是卡片网格：tablet 1440vp 下实测单行文本节点
              // 宽 1216vp，一行横扫整块屏。按 840vp 收口，与设置页、资料库同一
              // 档；同页的卡片网格不套栏宽，密度交给 GridRow 分列消化。
              ContentBand({ maxWidth: BAND_LIST_VP }) {
                SectionHeader({ title: '最近播放', icon: '⏱' })
                Column({ space: 2 }) {
                  ForEach(this.recentSongs.slice(0, 5), (song: SongItem, index: number) => {
                    Row({ space: 12 }) {
                      Stack() {
                        if (song.effectiveCoverUrl.length > 0) {
                          Image(song.effectiveCoverUrl)
                            .width(46)
                            .height(46)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(22)
                            .height(22)
                            .fillColor(Theme.primary(Theme.isDark()))
                            .margin({ left: 12, right: 12, top: 12, bottom: 12 })
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                            .borderRadius(8)
                        }
                      }
                      Column({ space: 2 }) {
                        Text(song.displayName)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Theme.textPrimary(Theme.isDark()))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(song.displayArtist)
                          .fontSize(12)
                          .fontColor(Theme.textSecondary(Theme.isDark()))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      Text('›')
                        .fontSize(18)
                        .fontColor(Theme.textDisabled(Theme.isDark()))
                    }
                    .width('100%')
                    .padding(8)
                    .onClick(() => this.playRecent(index))
                  }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
                }
                .width('100%')
                .padding(4)
                .backgroundColor(Theme.surface(Theme.isDark()))
                .borderRadius(Theme.cardRadius())
              }
            }

            if (this.neteaseRecommend.length > 0) {
              SectionHeader({ title: '每日推荐', icon: '★' })
              if (this.wideGrid()) {
                // md 每行 4 张、lg 每行 6 张（span 2 配 8/12 列）。列数断点与
                // GridRow 默认的 320/600/840vp 同源，所以侧边导航栏出现的那一刻
                // 网格刚好换到 6 列，两套响应式规则不会互相打架。
                GridRow({
                  columns: { xs: 4, sm: 4, md: 8, lg: 12 },
                  gutter: { x: 12, y: 14 }
                }) {
                  ForEach(this.neteaseRecommend, (item: NeteasePlaylistSummary) => {
                    GridCol({ span: 2 }) {
                      PlaylistCard({
                        name: item.name,
                        subtitle: item.trackCount > 0 ? `${item.trackCount} 首` : '网易云歌单',
                        coverUrl: item.coverUrl,
                        onOpen: () => Router.push(Router.NETEASE_PLAYLIST, `${item.id}`)
                      })
                    }
                  }, (item: NeteasePlaylistSummary) => `${item.id}`)
                }
                .width('100%')
                .padding({ left: 2, right: 2 })
              } else {
                Scroll() {
                  Row({ space: 12 }) {
                    ForEach(this.neteaseRecommend, (item: NeteasePlaylistSummary) => {
                      Column({ space: 6 }) {
                        if (item.coverUrl.length > 0) {
                          Image(item.coverUrl)
                            .width(132)
                            .height(132)
                            .borderRadius(16)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(40)
                            .height(40)
                            .fillColor(Theme.primary(Theme.isDark()))
                            .margin({ left: 46, right: 46, top: 46, bottom: 46 })
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                            .borderRadius(16)
                        }
                        Text(item.name)
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Theme.textPrimary(Theme.isDark()))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width(132)
                        Text(item.trackCount > 0 ? `${item.trackCount} 首` : '网易云歌单')
                          .fontSize(11)
                          .fontColor(Theme.textSecondary(Theme.isDark()))
                          .width(132)
                      }
                      .onClick(() => Router.push(Router.NETEASE_PLAYLIST, `${item.id}`))
                    }, (item: NeteasePlaylistSummary) => `${item.id}`)
                  }
                  .padding({ left: 4, right: 4 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }
            }

            if (this.localPlaylists.length > 0 || !this.offline) {
              SectionHeader({ title: '我的歌单', icon: '♪' })
              // 原为 Grid + columnsTemplate('1fr 1fr')：列数写死成 2，1440vp 的
              // tablet 上单卡被拉到 700vp。改用 GridRow 按窗口断点分列，
              // 每行 2 / 4 / 6 张，单卡宽度回到 160~210vp 的合理区间。
              GridRow({
                columns: { xs: 4, sm: 4, md: 8, lg: 12 },
                gutter: { x: 12, y: 14 }
              }) {
                ForEach(this.localPlaylists, (playlist: Playlist) => {
                  GridCol({ span: 2 }) {
                    PlaylistCard({
                      name: playlist.name,
                      trackCount: playlist.songKeys.length,
                      isFavorite: playlist.id === LocalPlaylistRepository.FAVORITES_ID,
                      onOpen: () => Router.push(Router.PLAYLIST_DETAIL, playlist.id)
                    })
                  }
                }, (playlist: Playlist) => playlist.id)
              }
              .width('100%')
              .padding({ left: 2, right: 2 })

              if (this.localPlaylists.length === 0) {
                EmptyState({
                  icon: '♪',
                  title: '暂无本地歌单',
                  subtitle: '先在「资料库」创建歌单，或去「探索」搜索歌曲'
                })
              }
            }
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
