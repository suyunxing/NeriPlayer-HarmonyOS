// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commits e95b2ef9 (collection/series archives) and 507c22d7 (uploader
// write-back for archive lists).

import { SongItem } from '../../model/SongItem';
import { BiliApi } from '../../network/BiliApi';
import {
  BiliCollectionArchiveItem,
  biliArchiveItemToSongItem
} from '../../network/BiliUploaderSpace';
import { PlayerManager } from '../../player/PlayerManager';
import { resolvePlaylistPlaybackStartIndex } from '../../player/queue/QueueEngine';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { SongListDataSource } from '../components/SongListDataSource';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * Bilibili collection (合集, seasons_archives_list) and series (系列,
 * x/series/archives) detail: header + paged video list with play/shuffle.
 * Archives carry no uploader name, so after the first page the owner is
 * resolved via acc/info and written back onto every row (upstream 507c22d7).
 */
@Component
export struct BiliCollectionPage {
  /** MainShell pageMap 传入：JSON { kind: 'collection'|'series', id, mid, title? }。 */
  @Prop collectionParam: string = '';
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @Watch('onSongsChanged') @State songs: SongItem[] = [];
  @State totalCount: number = 0;
  @State coverUrl: string = '';
  @State headerTitle: string = '';
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State loadError: string = '';
  /** 供 HdsNavDestination.bindToScrollable 绑定的列表控制器。 */
  private scroller: Scroller = new Scroller();
  private songsDs: SongListDataSource = new SongListDataSource();
  /** 原始归档条目：UP 名回填后由此重映射歌曲行，不重复请求。 */
  private items: BiliCollectionArchiveItem[] = [];
  private seenBvids: Set<string> = new Set();
  private page: number = 1;
  private hasMore: boolean = false;
  private uploaderName: string = '';
  private uploaderResolved: boolean = false;

  onSongsChanged(): void {
    this.songsDs.reset(this.songs);
  }

  private paramField(field: string): string {
    try {
      const raw = JSON.parse(this.collectionParam) as Record<string, Object>;
      return String(raw[field] ?? '');
    } catch (_error) {
      return '';
    }
  }

  private collectionId(): number {
    return Number(this.paramField('id'));
  }

  private ownerMid(): number {
    return Number(this.paramField('mid'));
  }

  private isSeries(): boolean {
    return this.paramField('kind') === 'series';
  }

  private remapSongs(): void {
    this.songs = this.items.map((item: BiliCollectionArchiveItem): SongItem =>
      biliArchiveItemToSongItem(item, this.uploaderName));
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    if (this.collectionId() <= 0 || this.ownerMid() <= 0) {
      this.loadError = '无效的合集/系列链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    this.page = 1;
    this.items = [];
    this.seenBvids = new Set<string>();
    try {
      if (this.isSeries()) {
        const first = await BiliApi.getSeriesArchives(this.ownerMid(), this.collectionId(), 1);
        this.appendArchiveItems(first.items);
        this.totalCount = first.total;
        this.hasMore = first.hasMore;
      } else {
        const first = await BiliApi.getCollectionArchives(this.ownerMid(), this.collectionId(), 1);
        this.appendArchiveItems(first.items);
        this.totalCount = first.meta.total;
        this.coverUrl = first.meta.coverUrl;
        this.headerTitle = first.meta.title;
        this.hasMore = first.hasMore;
      }
      this.remapSongs();
      if (this.items.length === 0 && this.totalCount === 0) {
        this.loadError = this.isSeries() ? '该系列没有视频' : '该合集没有视频';
      }
    } catch (error) {
      const e = error as Error;
      this.loadError = `加载失败：${e.message}`;
    }
    this.loading = false;
    this.resolveUploaderName();
  }

  /**
   * 系列/合集接口不返回 UP 主名，头部与行内艺人统一由 acc/info 补齐
   * （上游 resolveMissingArchiveUploader）：失败静默，行内回退 Bilibili。
   */
  private async resolveUploaderName(): Promise<void> {
    if (this.uploaderResolved) {
      return;
    }
    this.uploaderResolved = true;
    try {
      const profile = await BiliApi.getUploaderProfile(this.ownerMid());
      const name = profile.name.trim();
      if (name.length > 0 && this.items.length > 0) {
        this.uploaderName = name;
        this.remapSongs();
      }
    } catch (_error) {
      // 合集/系列可匿名访问而 acc/info 可能被风控拦下，保持回退名。
    }
  }

  private appendArchiveItems(items: BiliCollectionArchiveItem[]): void {
    for (const item of items) {
      if (item.bvid.length === 0 || this.seenBvids.has(item.bvid)) {
        continue;
      }
      this.seenBvids.add(item.bvid);
      this.items.push(item);
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    try {
      if (this.isSeries()) {
        const next = await BiliApi.getSeriesArchives(this.ownerMid(), this.collectionId(), this.page + 1);
        this.page += 1;
        this.hasMore = next.hasMore;
        this.appendArchiveItems(next.items);
      } else {
        const next = await BiliApi.getCollectionArchives(this.ownerMid(), this.collectionId(), this.page + 1);
        this.page += 1;
        this.hasMore = next.hasMore;
        this.appendArchiveItems(next.items);
      }
      this.remapSongs();
    } catch (error) {
      const e = error as Error;
      this.loadError = `加载更多失败：${e.message}`;
    }
    this.loadingMore = false;
  }

  private playAll(shuffle: boolean): void {
    if (this.songs.length === 0) {
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

  private title(): string {
    if (this.headerTitle.length > 0) {
      return this.headerTitle;
    }
    const fromParam = this.paramField('title');
    if (fromParam.length > 0) {
      return fromParam;
    }
    return this.isSeries() ? 'B 站系列' : 'B 站合集';
  }

  private schemeBg(dark: boolean): string {
    return Theme.background(dark);
  }

  build() {
    // 结构同 BiliFavPage：头部（PlaylistHeader 复用合集封面）与视频列表并入
    // 同一个 List，滚动穿到标题栏下方被渐变模糊覆盖。
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
              Column() {
                PlaylistHeader({
                  coverUrl: this.coverUrl,
                  title: this.title(),
                  subtitle: `${this.isSeries() ? '系列' : '合集'} · ${this.totalCount > 0 ? this.totalCount : this.songs.length} 条`
                }) {
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
              }
              .padding({ bottom: 10 })
            }

            if (this.songs.length === 0) {
              ListItem() {
                EmptyState({
                  icon: '📺',
                  title: this.isSeries() ? '系列为空' : '合集为空',
                  subtitle: '没有可播放的视频'
                })
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
              if (this.hasMore) {
                ListItem() {
                  Column({ space: 6 }) {
                    if (this.loadingMore) {
                      LoadingState()
                    } else {
                      Button('加载更多')
                        .height(40)
                        .fontSize(13)
                        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .onClick(() => this.loadMore())
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .alignItems(HorizontalAlign.Center)
                }
              }
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => this.loadMore())
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
