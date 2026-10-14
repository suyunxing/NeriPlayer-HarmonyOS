// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../../model/SongItem';
import { Playlist } from '../../model/Playlist';
import { UsageRepository, UsageEntry } from '../../data/UsageRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { NeteaseApi } from '../../network/NeteaseApi';
import { NeteasePlaylistSummary } from '../../network/NeteasePlaylistParser';
import {
  NETEASE_RADAR_PLAYLIST_DEFINITIONS,
  radarDefinitionToSummary
} from '../../network/NeteaseHomeRecommendations';
import { NetworkStatus } from '../../util/NetworkStatus';
import { Logger } from '../../app/Logger';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { BAND_LIST_VP, BP_LG, BP_MD } from '../../util/Breakpoint';
import { SectionHeader, EmptyState, LoadingState, PlaylistCard, ContentBand , FLOAT_TAB_CLEARANCE } from '../components/Ui';
import { coverThumbnailUrl } from '../../util/CoverUrls';
import { promptAction } from '@kit.ArkUI';

/** 本页在 MainShell 的 Tabs 里的下标，用于过滤刷新信号。 */
const TAB_INDEX: number = 0;
/** MINI 标题栏标准高度（MainShell 同名常量）：内容顶部让位，滚动时从标题栏背后滚过。 */
const TITLEBAR_SPACE_VP: number = 56;

@Component
export struct HomePage {
  /** 滚动控制器：实例由 MainShell 下发，壳层标题栏 bindToScrollable 绑定当前 Tab 的它。 */
  scroller: Scroller = new Scroller();
  /** 滚动增量上报（MainShell 下发）：驱动悬浮栏组滚动自适应显隐，见 MainShell.handleTabBarScroll。 */
  onBarScroll: (yDelta: number) => void = () => {};
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @State usage: UsageEntry[] = [];
  @State localPlaylists: Playlist[] = [];
  @State recentSongs: SongItem[] = [];
  @State neteaseRecommend: NeteasePlaylistSummary[] = [];
  // 雷达歌单（F-5）：静态定义兜底 + 并发元数据升级（上游 #319/#338）。
  @State radarPlaylists: NeteasePlaylistSummary[] = [];
  @State loading: boolean = true;
  @State offline: boolean = false;
  /** 每日推荐 FAB 开播进行中：按钮转圈并禁触，防止重复拉歌单。 */
  @State heroPlayBusy: boolean = false;
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
  // 手势条避让：Scroll 延伸进底部安全区后，列表尾部的额外让位高度。
  @StorageProp('ui.bottomLiftVp') bottomLift: number = 0;

  private onRefreshTick(): void {
    // 变动也可能发生在其它 Tab（资料库进歌单删歌后返回、播放页收藏等），
    // 隐藏时也要把本地数据刷进来，否则切回首页时封面/曲数停在旧值；只是
    // 隐藏时不重置 loading、不发网络推荐请求。
    this.reload(this.activeTab === TAB_INDEX);
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

  private async reload(withNetwork: boolean = true): Promise<void> {
    if (withNetwork) {
      this.loading = true;
      this.offline = !(await NetworkStatus.hasNetwork());
    }
    const usage = await UsageRepository.load();
    this.usage = usage;
    const playlists = await LocalPlaylistRepository.loadAll();
    this.localPlaylists = playlists;
    this.recentSongs = await HistoryRepository.getRecent();
    this.loading = false;
    if (withNetwork) {
      this.loadNeteaseRecommend();
    }
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
    this.loadRadarPlaylists();
  }

  /**
   * 雷达歌单（上游 #319/#338）：5 个官方雷达歌单，静态定义先上屏（无网也有
   * 入口），随后并发拉各自详情摘要升级封面/曲目数；单曲元数据失败保留
   * 静态定义（上游 loadNeteaseRadarPlaylistSummaries 语义）。
   */
  private loadRadarPlaylists(): void {
    const fallback: NeteasePlaylistSummary[] = [];
    for (const definition of NETEASE_RADAR_PLAYLIST_DEFINITIONS) {
      fallback.push(radarDefinitionToSummary(definition));
    }
    this.radarPlaylists = fallback;
    const fetches: Promise<NeteasePlaylistSummary | null>[] = [];
    for (const definition of NETEASE_RADAR_PLAYLIST_DEFINITIONS) {
      const id = definition.id;
      fetches.push(NeteaseApi.getPlaylistSummary(id)
        .then((summary: NeteasePlaylistSummary | null): NeteasePlaylistSummary | null =>
          summary !== null && summary.id === id ? summary : null)
        .catch((): NeteasePlaylistSummary | null => null));
    }
    Promise.all(fetches).then((results: (NeteasePlaylistSummary | null)[]) => {
      const merged: NeteasePlaylistSummary[] = [];
      for (let i = 0; i < results.length; i++) {
        merged.push(results[i] !== null ? results[i] as NeteasePlaylistSummary : fallback[i]);
      }
      this.radarPlaylists = merged;
    }).catch(() => {
      // 全军覆没时保留静态定义。
    });
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

  /**
   * 播放 FAB 的专属动作：拉取歌单全量歌曲，作为当前播放列表直接开播，
   * 不再借用整卡的进详情路由（2026-08-30）。走歌单详情页同一条
   * getPlaylistOverview 路径；失败 toast 提示，卡片本体仍可点进详情。
   */
  private async playNeteaseHero(item: NeteasePlaylistSummary): Promise<void> {
    if (this.heroPlayBusy) {
      return;
    }
    this.heroPlayBusy = true;
    try {
      const overview = await NeteaseApi.getPlaylistOverview(item.id);
      if (overview.songs.length === 0) {
        promptAction.openToast({ message: '歌单为空' });
        return;
      }
      PlayerManager.playPlaylist(overview.songs, 0);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`playNeteaseHero id=${item.id} failed: ${e.message}`);
      promptAction.openToast({ message: `开播失败：${e.message}` });
    } finally {
      this.heroPlayBusy = false;
    }
  }

  /**
   * S5: 参考图「每日推荐」Hero 卡——大封面 + 重点色标签 pill + 两行粗标题 +
   * 播放 FAB。点卡进歌单详情；点 FAB 直接开播整个歌单（子组件 onClick 消费
   * 点击，不会再触发整卡的进详情路由）。
   */
  @Builder
  recommendHero(item: NeteasePlaylistSummary) {
    Row({ space: 14 }) {
      if (item.coverUrl.length > 0) {
        Image(coverThumbnailUrl(item.coverUrl, 400))
          .autoResize(true)
          .width(118)
          .height(118)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      } else {
        Image($r('app.media.ic_music_note_24'))
          .width(40)
          .height(40)
          .fillColor(this.accentPrimary(Theme.isDark()))
          .margin({ left: 39, right: 39, top: 39, bottom: 39 })
          .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
          .borderRadius(18)
      }
      Column({ space: 8 }) {
        Text('每日推荐')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentTagText(Theme.isDark()))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.accentTagBg(Theme.isDark()))
          .borderRadius(12)
        Text(item.name)
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.trackCount > 0 ? `共 ${item.trackCount} 首` : '网易云歌单')
          .fontSize(13)
          .fontColor(Theme.textSecondary(Theme.isDark()))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.Center }) {
        // FAB 保持无阴影：shadow() 是通用属性，作用在节点矩形边界上，
        // Circle 之外会露出一圈方形阴影（2026-08-30 实测），扁平圆最干净。
        Circle()
          .width(52)
          .height(52)
          .fill(this.accentPrimary(Theme.isDark()))
        if (this.heroPlayBusy) {
          LoadingProgress()
            .width(26)
            .height(26)
            .color(this.accentOnPrimary(Theme.isDark()))
        } else {
          Image($r('app.media.round_play_arrow_24'))
            .width(26)
            .height(26)
            .fillColor(this.accentOnPrimary(Theme.isDark()))
        }
      }
      .width(52)
      .height(52)
      .accessibilityText('播放每日推荐')
      .onClick(() => this.playNeteaseHero(item))
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(Theme.cardRadius())
    .margin({ bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => Router.push(Router.NETEASE_PLAYLIST, `${item.id}`))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  /**
   * M7.4 的另一半：schemeBg 只让页面背景随取色重染，强调色节点（占位图标、
   * 标签 pill、播放 FAB）直接写 Theme.*() 仍是无跟踪调用，换歌后不动。下面
   * 的读法与 schemeBg 相同——先摸被跟踪的 coverScheme 注册依赖，取值依旧
   * 交给 Theme 统一决策（动态取色关闭、legacy seed 等回退路径不变）。
   */
  private accentPrimary(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.primary(dark) : Theme.primary(dark);
  }

  private accentOnPrimary(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.onPrimary(dark) : Theme.onPrimary(dark);
  }

  private accentSurfaceVariant(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.surfaceVariant(dark) : Theme.surfaceVariant(dark);
  }

  private accentTagBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.tagBg(dark) : Theme.tagBg(dark);
  }

  private accentTagText(dark: boolean): string {
    const hasScheme = this.coverScheme.light.primary.length > 0;
    return hasScheme ? Theme.tagText(dark) : Theme.tagText(dark);
  }

  build() {
    // 页内不再自绘标题栏：标题与刷新动作由 MainShell 的 HdsNavigation MINI
    // 标题栏（GRADIENT_BLUR 渐变模糊）承载，本页只做内容 + 顶部让位，滚动时
    // 内容从标题栏背后滚过。
    Scroll(this.scroller) {
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
                          Image(coverThumbnailUrl(entry.picUrl, 400))
                            .autoResize(true)
                            .width(132)
                            .height(132)
                            .borderRadius(16)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(40)
                            .height(40)
                            .fillColor(this.accentPrimary(Theme.isDark()))
                            .margin({ left: 46, right: 46, top: 46, bottom: 46 })
                            .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
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
                          Image(coverThumbnailUrl(song.effectiveCoverUrl, 200))
                            .autoResize(true)
                            .width(46)
                            .height(46)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(22)
                            .height(22)
                            .fillColor(this.accentPrimary(Theme.isDark()))
                            .margin({ left: 12, right: 12, top: 12, bottom: 12 })
                            .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
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
              this.recommendHero(this.neteaseRecommend[0])
              if (this.wideGrid()) {
                // md 每行 4 张、lg 每行 6 张（span 2 配 8/12 列）。列数断点与
                // GridRow 默认的 320/600/840vp 同源，所以侧边导航栏出现的那一刻
                // 网格刚好换到 6 列，两套响应式规则不会互相打架。
                GridRow({
                  columns: { xs: 4, sm: 4, md: 8, lg: 12 },
                  gutter: { x: 12, y: 14 }
                }) {
                  ForEach(this.neteaseRecommend.slice(1), (item: NeteasePlaylistSummary) => {
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
                    ForEach(this.neteaseRecommend.slice(1), (item: NeteasePlaylistSummary) => {
                      Column({ space: 6 }) {
                        if (item.coverUrl.length > 0) {
                          Image(coverThumbnailUrl(item.coverUrl, 400))
                            .autoResize(true)
                            .width(132)
                            .height(132)
                            .borderRadius(16)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                        } else {
                          Image($r('app.media.ic_music_note_24'))
                            .width(40)
                            .height(40)
                            .fillColor(this.accentPrimary(Theme.isDark()))
                            .margin({ left: 46, right: 46, top: 46, bottom: 46 })
                            .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
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

            // F-5：雷达歌单（时光/宝藏/新歌/乐迷/神秘）。静态定义先上屏，
            // 元数据到位后原地升级封面/曲目数（宽屏也保持横滑：只有 5 张）。
            if (this.radarPlaylists.length > 0) {
              SectionHeader({ title: '雷达歌单', icon: '◎' })
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.radarPlaylists, (item: NeteasePlaylistSummary) => {
                    Column({ space: 6 }) {
                      if (item.coverUrl.length > 0) {
                        Image(coverThumbnailUrl(item.coverUrl, 300))
                          .autoResize(true)
                          .width(112)
                          .height(112)
                          .borderRadius(16)
                          .objectFit(ImageFit.Cover)
                          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                      } else {
                        Image($r('app.media.ic_music_note_24'))
                          .width(36)
                          .height(36)
                          .fillColor(this.accentPrimary(Theme.isDark()))
                          .margin({ left: 38, right: 38, top: 38, bottom: 38 })
                          .backgroundColor(this.accentSurfaceVariant(Theme.isDark()))
                          .borderRadius(16)
                      }
                      Text(item.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width(112)
                      Text(item.trackCount > 0 ? `${item.trackCount} 首` : '网易云歌单')
                        .fontSize(11)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                        .width(112)
                    }
                    .onClick(() => Router.push(Router.NETEASE_PLAYLIST, `${item.id}`))
                  }, (item: NeteasePlaylistSummary) => `${item.id}_${item.coverUrl}`)
                }
                .padding({ left: 4, right: 4 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
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
                // 键拼 updatedAt：同键的卡片会被 ForEach 复用而拿不到新参数，
                // 拼上数据层在增删歌/改名时刷新的版本号，封面/曲数必然重建。
                ForEach(this.localPlaylists, (playlist: Playlist) => {
                  GridCol({ span: 2 }) {
                    PlaylistCard({
                      name: playlist.name,
                      coverUrl: playlist.displayCoverUrl,
                      trackCount: playlist.songKeys.length,
                      isFavorite: playlist.id === LocalPlaylistRepository.FAVORITES_ID,
                      onOpen: () => Router.push(Router.PLAYLIST_DETAIL, playlist.id)
                    })
                  }
                }, (playlist: Playlist) => `${playlist.id}_${playlist.updatedAt}`)
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
        .padding({ top: TITLEBAR_SPACE_VP, left: 14, right: 14, bottom: 24 + FLOAT_TAB_CLEARANCE + this.bottomLift })
      }
      .scrollBar(BarState.Off)
      // 滚动自适应悬浮栏：纵向增量交壳层驱动显隐（本组件不消费增量，
      // offsetRemain 原样放行，见 MainShell.handleTabBarScroll）。
      .onScrollFrameBegin((offset: number) => {
        this.onBarScroll(offset);
        return { offsetRemain: offset };
      })
      .align(Alignment.Top)
      .width('100%')
      .height('100%')
      // 视口延伸进底部手势条区域：滚动内容真实透到系统指示条后面，配
      // MainShell 底部渐变遮罩保证可读性（不再垫纯色带）。顶部同向延伸：
      // 滚过标题栏的内容继续钻到状态栏后被渐变模糊覆盖（沉浸顶栏）；
      // clip(false) 放行内容画出视口上沿，否则像素在标题栏下缘被裁掉。
      // expandSafeArea 只扩绘制区不改布局，首屏仍从 TITLEBAR_SPACE_VP 让位。
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
