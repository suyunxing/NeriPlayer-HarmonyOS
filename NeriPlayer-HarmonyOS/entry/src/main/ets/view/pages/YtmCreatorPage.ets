// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 4c085185 (YouTube Music creator profiles, detail screen half).

import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import {
  YtmCreatorBrowseEndpoint,
  YtmCreatorDetail,
  YtmCreatorItem,
  YtmCreatorItemType,
  YtmCreatorItemsPage,
  YtmCreatorSection,
  YtmCreatorSummary,
  loadYtmCreatorPlaybackQueue,
  ytmCreatorItemToSongItem
} from '../../network/ytm/YtmCreatorParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { coverThumbnailUrl } from '../../util/CoverUrls';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/** detail 加载后预计算的分区视图：可播行或卡片形态（上游 onlyPlayableItems 分叉）。 */
class CreatorSectionUi {
  section: YtmCreatorSection = new YtmCreatorSection();
  songs: SongItem[] = [];
  playableItems: YtmCreatorItem[] = [];
  allPlayable: boolean = true;
  canShowAll: boolean = false;
  key: string = '';
}

/**
 * YouTube Music 创作者主页（上游 YouTubeMusicCreatorDetailScreen）：头部
 * 资料卡 + 各分区（歌曲行 / 混合卡片横滑），「查看全部」进 YtmCreatorItemsPage。
 * 点歌按上游语义构建完整播放队列（分区无 moreEndpoint 时直接本地队列）。
 */
@Component
export struct YtmCreatorPage {
  /** MainShell pageMap 传入：JSON { browseId, title?, subtitle?, coverUrl? }。 */
  @Prop creatorParam: string = '';
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State detail: YtmCreatorDetail | null = null;
  @State sections: CreatorSectionUi[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State playbackLoadingKey: string = '';
  @State playbackErrorKey: string = '';
  @State playbackError: string = '';
  private scroller: Scroller = new Scroller();
  private fallback: YtmCreatorSummary = new YtmCreatorSummary();

  private paramField(field: string): string {
    try {
      const raw = JSON.parse(this.creatorParam) as Record<string, Object>;
      return String(raw[field] ?? '');
    } catch (_error) {
      return '';
    }
  }

  async aboutToAppear(): Promise<void> {
    this.fallback.browseId = this.paramField('browseId');
    this.fallback.title = this.paramField('title');
    this.fallback.subtitle = this.paramField('subtitle');
    this.fallback.coverUrl = this.paramField('coverUrl');
    await this.reload();
  }

  private async reload(): Promise<void> {
    if (this.fallback.browseId.length === 0) {
      this.loadError = '无效的创作者链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const detail = await YouTubeMusicApi.getCreatorDetail(this.fallback);
      this.detail = detail;
      this.rebuildSections(detail);
      if (detail.sections.length === 0) {
        this.loadError = '该创作者暂无公开内容';
      }
    } catch (error) {
      const e = error as Error;
      this.loadError = `创作者主页加载失败：${e.message}`;
    }
    this.loading = false;
  }

  private rebuildSections(detail: YtmCreatorDetail): void {
    const out: CreatorSectionUi[] = [];
    for (const section of detail.sections) {
      const ui = new CreatorSectionUi();
      ui.section = section;
      ui.allPlayable = true;
      for (const item of section.items) {
        const song = ytmCreatorItemToSongItem(item);
        if (song === null) {
          ui.allPlayable = false;
          continue;
        }
        ui.playableItems.push(item);
        ui.songs.push(song);
      }
      ui.canShowAll = section.moreEndpoint !== null && ui.songs.length > 0;
      ui.key = `${section.moreEndpoint?.browseId ?? ''}|${section.moreEndpoint?.params ?? ''}|${section.title}`;
      out.push(ui);
    }
    this.sections = out;
  }

  /**
   * 上游 playSectionSong：无 moreEndpoint 直接本地队列；有则拉完整分区
   * （首页 + continuation，页数上限 80）构建队列后按点击项起播。
   */
  private async playSectionSong(ui: CreatorSectionUi, item: YtmCreatorItem): Promise<void> {
    if (this.playbackLoadingKey.length > 0) {
      return;
    }
    this.playbackLoadingKey = ui.key;
    this.playbackErrorKey = '';
    this.playbackError = '';
    try {
      const queue = await loadYtmCreatorPlaybackQueue(ui.section, item,
        (endpoint: YtmCreatorBrowseEndpoint, title: string): Promise<YtmCreatorItemsPage> =>
          YouTubeMusicApi.getCreatorItems(endpoint, title),
        (continuation: string): Promise<YtmCreatorItemsPage> =>
          YouTubeMusicApi.getCreatorItemsContinuation(continuation));
      if (queue === null || queue.songs.length === 0) {
        this.playbackErrorKey = ui.key;
        this.playbackError = `「${ui.section.title}」没有可播放的内容`;
        return;
      }
      await PlayerManager.playPlaylist(queue.songs, queue.startIndex);
      Router.push(Router.NOW_PLAYING);
    } catch (error) {
      const e = error as Error;
      this.playbackErrorKey = ui.key;
      this.playbackError = `「${ui.section.title}」队列加载失败：${e.message}`;
    } finally {
      this.playbackLoadingKey = '';
    }
  }

  private onSectionRowTap(ui: CreatorSectionUi, index: number): void {
    if (ui.section.moreEndpoint === null) {
      PlayerManager.playPlaylist(ui.songs, index);
      Router.push(Router.NOW_PLAYING);
      return;
    }
    this.playSectionSong(ui, ui.playableItems[index]);
  }

  private onCardTap(item: YtmCreatorItem): void {
    const song = ytmCreatorItemToSongItem(item);
    if (song !== null) {
      PlayerManager.playPlaylist([song], 0);
      Router.push(Router.NOW_PLAYING);
      return;
    }
    if (item.type === YtmCreatorItemType.CREATOR && item.browseId.length > 0) {
      Router.push(Router.YTM_CREATOR, JSON.stringify({
        browseId: item.browseId,
        title: item.title,
        subtitle: item.subtitle,
        coverUrl: item.coverUrl
      }));
      return;
    }
    promptAction.openToast({ message: 'YouTube Music 专辑/歌单详情暂未支持', duration: 2500 });
  }

  private openSectionAll(ui: CreatorSectionUi): void {
    const endpoint = ui.section.moreEndpoint;
    if (endpoint === null) {
      return;
    }
    Router.push(Router.YTM_CREATOR_ITEMS, JSON.stringify({
      browseId: endpoint.browseId,
      params: endpoint.params,
      title: ui.section.title
    }));
  }

  private title(): string {
    if (this.detail !== null && this.detail.header.title.length > 0) {
      return this.detail.header.title;
    }
    return this.fallback.title.length > 0 ? this.fallback.title : '创作者';
  }

  private schemeBg(dark: boolean): string {
    return Theme.background(dark);
  }

  @Builder
  sectionHeader(ui: CreatorSectionUi) {
    Row({ space: 8 }) {
      Text(ui.section.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (ui.canShowAll) {
        Image($r('app.media.ic_chevron_right_24'))
          .width(18)
          .height(18)
          .fillColor(Theme.textSecondary(Theme.isDark()))
          .onClick(() => this.openSectionAll(ui))
      }
      if (this.playbackLoadingKey === ui.key) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(Theme.primary(Theme.isDark()))
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 6 })
  }

  @Builder
  sectionCard(item: YtmCreatorItem) {
    Column({ space: 7 }) {
      if (item.coverUrl.length > 0) {
        Image(coverThumbnailUrl(item.coverUrl, 320))
          .width(118)
          .height(118)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .alt($r('app.media.ic_music_note_24'))
      } else {
        Column() {
          Image($r('app.media.ic_music_note_24'))
            .width(36)
            .height(36)
            .fillColor(Theme.textSecondary(Theme.isDark()))
        }
        .width(118)
        .height(118)
        .borderRadius(12)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .justifyContent(FlexAlign.Center)
      }
      Text(item.title)
        .fontSize(13)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.subtitle.length > 0) {
        Text(item.subtitle)
          .fontSize(11)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width(118)
    .alignItems(HorizontalAlign.Start)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => this.onCardTap(item))
  }

  build() {
    // 结构同 BiliUploaderPage：头部资料卡 + 各分区并入同一个 List 穿透滚动。
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
        } else if (this.detail === null) {
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
          List({ scroller: this.scroller }) {
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
            ListItem() {
              Row({ space: 12 }) {
                Image(this.detail.header.coverUrl.length > 0
                  ? this.detail.header.coverUrl : $r('app.media.ic_music_note_24'))
                  .width(64)
                  .height(64)
                  .borderRadius(32)
                  .objectFit(ImageFit.Cover)
                  .fillColor(this.detail.header.coverUrl.length > 0
                    ? Color.Transparent : Theme.primary(Theme.isDark()))
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .alt($r('app.media.ic_music_note_24'))
                Column({ space: 4 }) {
                  Text(this.detail.header.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.detail.header.subtitle.length > 0) {
                    Text(this.detail.header.subtitle)
                      .fontSize(12)
                      .fontColor(Theme.textSecondary(Theme.isDark()))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 4, bottom: 8 })
            }
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  if (this.detail.header.monthlyListenerCountText.length > 0) {
                    Text(this.detail.header.monthlyListenerCountText)
                      .fontSize(11)
                      .fontColor(Theme.textSecondary(Theme.isDark()))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                      .borderRadius(12)
                  }
                  if (this.detail.header.subscriberCountText.length > 0
                    && this.detail.header.subscriberCountText !== this.detail.header.monthlyListenerCountText) {
                    Text(this.detail.header.subscriberCountText)
                      .fontSize(11)
                      .fontColor(Theme.textSecondary(Theme.isDark()))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                      .borderRadius(12)
                  }
                }
                if (this.detail.header.description.length > 0) {
                  Text(this.detail.header.description)
                    .fontSize(12)
                    .fontColor(Theme.textSecondary(Theme.isDark()))
                    .maxLines(4)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ bottom: 6 })
            }

            ForEach(this.sections, (ui: CreatorSectionUi) => {
              ListItem() {
                Column() {
                  this.sectionHeader(ui)
                  if (this.playbackErrorKey === ui.key && this.playbackError.length > 0) {
                    Text(this.playbackError)
                      .fontSize(11)
                      .fontColor(Theme.danger(Theme.isDark()))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  if (ui.allPlayable) {
                    ForEach(ui.songs, (song: SongItem, index: number) => {
                      SongRow({
                        songJson: song.toJson(),
                        index: index,
                        onPlay: (): void => {
                          this.onSectionRowTap(ui, index);
                        }
                      })
                    }, (song: SongItem, index: number) => `${ui.key}_${index}_${song.audioId}`)
                  } else {
                    Scroll() {
                      Row({ space: 12 }) {
                        ForEach(ui.section.items, (item: YtmCreatorItem) => {
                          this.sectionCard(item)
                        }, (item: YtmCreatorItem, index: number) =>
                          `${item.type}_${item.browseId}_${item.videoId}_${index}`)
                      }
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .scrollBar(BarState.Off)
                    .width('100%')
                  }
                }
                .width('100%')
                .padding({ bottom: 10 })
              }
            }, (ui: CreatorSectionUi) => ui.key)

            ListItem() {
              Column()
                .width('100%')
                .height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
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
