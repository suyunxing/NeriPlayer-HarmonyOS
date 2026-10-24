// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 4c085185 (YouTube Music creator profiles, section "view all" screen).

import { SongItem } from '../../model/SongItem';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import {
  YtmCreatorBrowseEndpoint,
  YtmCreatorItem,
  mergeYtmCreatorItems,
  ytmCreatorItemToSongItem
} from '../../network/ytm/YtmCreatorParser';
import { YtmCreatorItemsPage as YtmCreatorItemsPageModel } from '../../network/ytm/YtmCreatorParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { SongListDataSource } from '../components/SongListDataSource';
import { EmptyState, LoadingState } from '../components/Ui';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * 创作者分区「查看全部」页（上游 YouTubeMusicCreatorItemsScreen）：moreEndpoint
 * 全量列表 + continuation 加载更多，点击按当前列表构建队列起播。
 */
@Component
export struct YtmCreatorItemsPage {
  /** MainShell pageMap 传入：JSON { browseId, params, title }。 */
  @Prop itemsParam: string = '';
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State pageTitle: string = '';
  @Watch('onSongsChanged') @State songs: SongItem[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State hasMore: boolean = false;
  @State loadingMore: boolean = false;
  private scroller: Scroller = new Scroller();
  private songsDs: SongListDataSource = new SongListDataSource();
  private items: YtmCreatorItem[] = [];
  /** reload/loadMore 写入、loadMore 读取的下一页 token。 */
  private pendingContinuation: string = '';

  onSongsChanged(): void {
    this.songsDs.reset(this.songs);
  }

  private paramField(field: string): string {
    try {
      const raw = JSON.parse(this.itemsParam) as Record<string, Object>;
      return String(raw[field] ?? '');
    } catch (_error) {
      return '';
    }
  }

  private endpoint(): YtmCreatorBrowseEndpoint {
    const endpoint = new YtmCreatorBrowseEndpoint();
    endpoint.browseId = this.paramField('browseId');
    endpoint.params = this.paramField('params');
    return endpoint;
  }

  async aboutToAppear(): Promise<void> {
    this.pageTitle = this.paramField('title');
    await this.reload();
  }

  private remapSongs(): void {
    const songs: SongItem[] = [];
    for (const item of this.items) {
      const song = ytmCreatorItemToSongItem(item);
      if (song !== null) {
        songs.push(song);
      }
    }
    this.songs = songs;
  }

  private async reload(): Promise<void> {
    const endpoint = this.endpoint();
    if (endpoint.browseId.length === 0) {
      this.loadError = '无效的分区链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const page: YtmCreatorItemsPageModel = await YouTubeMusicApi.getCreatorItems(endpoint, this.pageTitle);
      this.items = mergeYtmCreatorItems(page.items);
      if (page.title.length > 0) {
        this.pageTitle = page.title;
      }
      this.hasMore = page.continuation.length > 0 && this.items.length > 0;
      this.pendingContinuation = page.continuation;
      this.remapSongs();
      if (this.items.length === 0) {
        this.loadError = '该分区没有内容';
      }
    } catch (error) {
      const e = error as Error;
      this.loadError = `列表加载失败：${e.message}`;
    }
    this.loading = false;
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    try {
      const page = await YouTubeMusicApi.getCreatorItemsContinuation(this.pendingContinuation);
      const merged = mergeYtmCreatorItems([...this.items, ...page.items]);
      // 上游 continuation 去抖：token 未变且没有新增条目时终止分页。
      const stalled = page.continuation === this.pendingContinuation
        && merged.length === this.items.length;
      this.items = merged;
      this.hasMore = !stalled && page.continuation.length > 0;
      this.pendingContinuation = stalled ? '' : page.continuation;
      this.remapSongs();
    } catch (error) {
      const e = error as Error;
      this.loadError = `加载更多失败：${e.message}`;
    }
    this.loadingMore = false;
  }

  private play(index: number): void {
    if (this.songs.length === 0) {
      return;
    }
    PlayerManager.playPlaylist(this.songs, index);
    Router.push(Router.NOW_PLAYING);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        if (this.loading && this.songs.length === 0) {
          Column() {
            LoadingState()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.background(Theme.isDark()))
        } else if (this.songs.length === 0) {
          Column() {
            EmptyState({ icon: '🎵', title: '没有内容', subtitle: this.loadError })
            Button('重试')
              .height(40)
              .fontSize(13)
              .backgroundColor(Theme.primary(Theme.isDark()))
              .onClick(() => this.reload())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.background(Theme.isDark()))
        } else {
          List({ scroller: this.scroller }) {
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
            LazyForEach(this.songsDs, (song: SongItem, index: number) => {
              ListItem() {
                SongRow({
                  songJson: song.toJson(),
                  index: index,
                  onPlay: (): void => {
                    this.play(index);
                  }
                })
              }
            }, (song: SongItem, index: number) => `${index}_${song.audioId}`)
            if (this.hasMore) {
              ListItem() {
                Column() {
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
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => this.loadMore())
          .cachedCount(3, true)
          .clip(false)
          .backgroundColor(Theme.background(Theme.isDark()))
        }

        SubPageBottomFade()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background(Theme.isDark()))
    }
    .titleBar(subPageTitleBar(this.pageTitle))
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
