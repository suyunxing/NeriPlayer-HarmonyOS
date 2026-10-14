// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit e95b2ef9 (uploader profile / archives / collections / series).

import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { BiliApi } from '../../network/BiliApi';
import {
  BiliUploaderProfile,
  BiliUploaderVideo,
  BiliUploaderContent,
  BiliUploaderContentKind,
  biliUploaderVideoToSongItem
} from '../../network/BiliUploaderSpace';
import { PlayerManager } from '../../player/PlayerManager';
import { resolvePlaylistPlaybackStartIndex } from '../../player/queue/QueueEngine';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { SongListDataSource } from '../components/SongListDataSource';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';
import { HeaderPill } from '../components/PlaylistHeader';
import { coverThumbnailUrl } from '../../util/CoverUrls';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * Bilibili uploader space (x/space/wbi/acc/info + arc/search +
 * seasons_series_list): avatar/sign header, three tabs — 投稿 (paged video
 * list, play/shuffle), 合集 and 系列 (cards opening BiliCollectionPage).
 * Upstream splits this into ViewModel + Screen; on HarmonyOS the page holds
 * the state directly (no cross-page reuse to extract).
 */
@Component
export struct BiliUploaderPage {
  /** MainShell pageMap 传入：JSON { mid: number, name?: string }。 */
  @Prop uploaderParam: string = '';
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State profile: BiliUploaderProfile | null = null;
  @Watch('onSongsChanged') @State songs: SongItem[] = [];
  @State collections: BiliUploaderContent[] = [];
  @State series: BiliUploaderContent[] = [];
  @State tab: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State videosHasMore: boolean = false;
  @State contentsHasMore: boolean = false;
  @State videosLoadingMore: boolean = false;
  @State contentsLoadingMore: boolean = false;
  /** 供 HdsNavDestination.bindToScrollable 绑定的投稿列表控制器。 */
  private scroller: Scroller = new Scroller();
  private songsDs: SongListDataSource = new SongListDataSource();
  private videoItems: BiliUploaderVideo[] = [];
  private seenBvids: Set<string> = new Set();
  private videoPage: number = 1;
  private contentPage: number = 1;
  private seenContentIds: Set<number> = new Set();

  onSongsChanged(): void {
    this.songsDs.reset(this.songs);
  }

  private paramField(field: string): string {
    try {
      const raw = JSON.parse(this.uploaderParam) as Record<string, Object>;
      return String(raw[field] ?? '');
    } catch (_error) {
      return '';
    }
  }

  private mid(): number {
    return Number(this.paramField('mid'));
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    const mid = this.mid();
    if (mid <= 0) {
      this.loadError = '无效的 UP 主链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    this.videoPage = 1;
    this.contentPage = 1;
    this.videoItems = [];
    this.seenBvids = new Set<string>();
    this.seenContentIds = new Set<number>();
    // 头部（acc/info）失败不阻塞列表：名字回退 param 里的 mid 兜底文案。
    const profileTask = BiliApi.getUploaderProfile(mid)
      .then((profile: BiliUploaderProfile): BiliUploaderProfile => profile)
      .catch((_error: object): BiliUploaderProfile | null => null);
    try {
      const videosTask = BiliApi.getUploaderVideos(mid, 1);
      const contentsTask = BiliApi.getUploaderContents(mid, 1);
      const profile = await profileTask;
      if (profile !== null) {
        this.profile = profile;
      }
      const videos = await videosTask;
      this.appendVideos(videos.items);
      this.videoPage = videos.page;
      this.videosHasMore = videos.hasMore;
      const contents = await contentsTask;
      this.appendContents(contents.collections, contents.series);
      this.contentPage = contents.page;
      this.contentsHasMore = contents.hasMore;
      this.remapSongs();
      if (this.videoItems.length === 0 && this.collections.length === 0 && this.series.length === 0) {
        this.loadError = '该 UP 主没有公开投稿';
      }
    } catch (error) {
      const e = error as Error;
      this.loadError = `UP 主空间加载失败：${e.message}`;
    }
    this.loading = false;
  }

  private remapSongs(): void {
    this.songs = this.videoItems.map((video: BiliUploaderVideo): SongItem =>
      biliUploaderVideoToSongItem(video));
  }

  private appendVideos(items: BiliUploaderVideo[]): void {
    for (const video of items) {
      if (video.bvid.length === 0 || this.seenBvids.has(video.bvid)) {
        continue;
      }
      this.seenBvids.add(video.bvid);
      this.videoItems.push(video);
    }
  }

  private appendContents(collections: BiliUploaderContent[], series: BiliUploaderContent[]): void {
    for (const content of collections) {
      if (!this.seenContentIds.has(content.id)) {
        this.seenContentIds.add(content.id);
        this.collections.push(content);
      }
    }
    for (const content of series) {
      if (!this.seenContentIds.has(content.id)) {
        this.seenContentIds.add(content.id);
        this.series.push(content);
      }
    }
  }

  private async loadMoreVideos(): Promise<void> {
    if (!this.videosHasMore || this.videosLoadingMore || this.loading) {
      return;
    }
    this.videosLoadingMore = true;
    try {
      const page = await BiliApi.getUploaderVideos(this.mid(), this.videoPage + 1);
      this.videoPage = page.page;
      this.videosHasMore = page.hasMore;
      this.appendVideos(page.items);
      this.remapSongs();
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `加载更多失败：${e.message}` });
    }
    this.videosLoadingMore = false;
  }

  private async loadMoreContents(): Promise<void> {
    if (!this.contentsHasMore || this.contentsLoadingMore || this.loading) {
      return;
    }
    this.contentsLoadingMore = true;
    try {
      const page = await BiliApi.getUploaderContents(this.mid(), this.contentPage + 1);
      this.contentPage = page.page;
      this.contentsHasMore = page.hasMore;
      this.appendContents(page.collections, page.series);
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `加载更多失败：${e.message}` });
    }
    this.contentsLoadingMore = false;
  }

  private playAll(shuffle: boolean): void {
    if (this.songs.length === 0) {
      promptAction.openToast({ message: '该 UP 主没有可播放的投稿' });
      return;
    }
    const startIndex = resolvePlaylistPlaybackStartIndex(
      this.songs.length,
      shuffle,
      Math.floor(Math.random() * this.songs.length)
    );
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(this.songs, startIndex);
    Router.push(Router.NOW_PLAYING);
  }

  private openContent(content: BiliUploaderContent): void {
    Router.push(Router.BILI_COLLECTION, JSON.stringify({
      kind: content.kind === BiliUploaderContentKind.SERIES ? 'series' : 'collection',
      id: content.id,
      mid: content.mid,
      title: content.title
    }));
  }

  private title(): string {
    if (this.profile !== null && this.profile.name.length > 0) {
      return this.profile.name;
    }
    const fromParam = this.paramField('name');
    return fromParam.length > 0 ? fromParam : 'UP 主空间';
  }

  private schemeBg(dark: boolean): string {
    return Theme.background(dark);
  }

  @Builder
  tabButton(index: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tab === index ? Theme.textPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.tab === index
        ? Theme.primary(Theme.isDark()) : Theme.surfaceVariant(Theme.isDark()))
      .borderRadius(17)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.tab = index;
      })
  }

  @Builder
  contentCard(content: BiliUploaderContent) {
    Row({ space: 12 }) {
      if (content.coverUrl.length > 0) {
        Image(coverThumbnailUrl(content.coverUrl, 320))
          .autoResize(true)
          .width(96)
          .height(60)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      } else {
        Column() {
          Text(content.kind === BiliUploaderContentKind.SERIES ? '系' : '合')
            .fontSize(16)
            .fontColor(Theme.primary(Theme.isDark()))
        }
        .width(96)
        .height(60)
        .borderRadius(8)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text(content.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(content.total > 0 ? `${content.total} 个视频` : '视频合集')
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(Theme.surface(Theme.isDark()))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => this.openContent(content))
  }

  @Builder
  loadMoreRow(busy: boolean, hasMore: boolean, onTap: () => void) {
    if (hasMore) {
      Column({ space: 6 }) {
        if (busy) {
          LoadingState()
        } else {
          Button('加载更多')
            .height(40)
            .fontSize(13)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => onTap())
        }
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Center)
    }
  }

  build() {
    // 结构同 BiliFavPage：头部（头像 + 名字/签名 + 播放 pills）、Tab chips
    // 与当前 Tab 内容并入同一个 List，滚动穿到标题栏下方被渐变模糊覆盖。
    HdsNavDestination() {
      Stack() {
        if (this.loading) {
          Column() {
            LoadingState()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        } else if (this.loadError.length > 0) {
          Column() {
            EmptyState({ icon: '⚠', title: '加载失败', subtitle: this.loadError })
            Button('重试')
              .height(40)
              .fontSize(13)
              .backgroundColor(Theme.primary(Theme.isDark()))
              .onClick(() => this.reload())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        } else {
          List({ scroller: this.scroller, space: 1 }) {
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
            ListItem() {
              Row({ space: 12 }) {
                Image(this.profile !== null && this.profile.faceUrl.length > 0
                  ? this.profile.faceUrl : $r('app.media.ic_music_note_24'))
                  .width(64)
                  .height(64)
                  .borderRadius(32)
                  .objectFit(ImageFit.Cover)
                  .fillColor(this.profile !== null && this.profile.faceUrl.length > 0
                    ? Color.Transparent : Theme.primary(Theme.isDark()))
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .alt($r('app.media.ic_music_note_24'))
                Column({ space: 4 }) {
                  Text(this.title())
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.profile !== null && this.profile.sign.length > 0
                    ? this.profile.sign : `投稿 ${this.songs.length} 个视频`)
                    .fontSize(12)
                    .fontColor(Theme.textSecondary(Theme.isDark()))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 4, bottom: 8 })
            }
            ListItem() {
              Row({ space: 10 }) {
                HeaderPill({
                  label: '全部播放',
                  filled: true,
                  onTap: (): void => this.playAll(false)
                })
                HeaderPill({
                  label: '随机播放',
                  onTap: (): void => this.playAll(true)
                })
              }
              .padding({ bottom: 10 })
            }
            ListItem() {
              Row({ space: 8 }) {
                this.tabButton(0, `投稿 ${this.songs.length}`)
                this.tabButton(1, `合集 ${this.collections.length}`)
                this.tabButton(2, `系列 ${this.series.length}`)
              }
              .padding({ bottom: 8 })
            }

            if (this.tab === 0) {
              if (this.songs.length === 0) {
                ListItem() {
                  EmptyState({ icon: '📺', title: '没有投稿', subtitle: '该 UP 主没有公开的视频投稿' })
                }
              } else {
                LazyForEach(this.songsDs, (song: SongItem, index: number) => {
                  ListItem() {
                    SongRow({
                      songJson: song.toJson(),
                      index: index,
                      onPlay: () => {
                        PlayerManager.playPlaylist(this.songs, index);
                        Router.push(Router.NOW_PLAYING);
                      }
                    })
                  }
                }, (song: SongItem, index: number) => `${index}_${song.platform}_${song.audioId}`)
                ListItem() {
                  this.loadMoreRow(this.videosLoadingMore, this.videosHasMore, (): void => {
                    this.loadMoreVideos();
                  })
                }
                ListItem() {
                  Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
                }
              }
            } else if (this.tab === 1) {
              if (this.collections.length === 0) {
                ListItem() {
                  EmptyState({ icon: '📚', title: '没有合集', subtitle: '该 UP 主没有公开的合集' })
                }
                ListItem() {
                  Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
                }
              } else {
                ForEach(this.collections, (content: BiliUploaderContent) => {
                  ListItem() {
                    this.contentCard(content)
                  }
                }, (content: BiliUploaderContent) => `c_${content.id}`)
                ListItem() {
                  this.loadMoreRow(this.contentsLoadingMore, this.contentsHasMore, (): void => {
                    this.loadMoreContents();
                  })
                }
                ListItem() {
                  Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
                }
              }
            } else {
              if (this.series.length === 0) {
                ListItem() {
                  EmptyState({ icon: '🎞️', title: '没有系列', subtitle: '该 UP 主没有公开的视频系列' })
                }
                ListItem() {
                  Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
                }
              } else {
                ForEach(this.series, (content: BiliUploaderContent) => {
                  ListItem() {
                    this.contentCard(content)
                  }
                }, (content: BiliUploaderContent) => `s_${content.id}`)
                ListItem() {
                  this.loadMoreRow(this.contentsLoadingMore, this.contentsHasMore, (): void => {
                    this.loadMoreContents();
                  })
                }
                ListItem() {
                  Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
                }
              }
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => {
            if (this.tab === 0) {
              this.loadMoreVideos();
            } else {
              this.loadMoreContents();
            }
          })
          .cachedCount(3, true)
          .clip(false)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        }

        SubPageBottomFade()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.schemeBg(Theme.isDark()))
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
