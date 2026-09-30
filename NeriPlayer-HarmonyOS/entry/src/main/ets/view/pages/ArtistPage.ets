// SPDX-License-Identifier: GPL-3.0

import { NeteaseApi, NeteaseArtistHead } from '../../network/NeteaseApi';
import { SongItem } from '../../model/SongItem';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * 网易云艺人页（backlog §3.4）：param 为 JSON { artist: string, artistId: number }；
 * 头部走 /api/artist/head/info/get，曲目走 /api/v1/artist/songs（hot 前 50，
 * 可切新歌）。本地无缓存，加载失败给空态。
 */
@Component
export struct ArtistPage {
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  artistParam: string = '';
  @State head: NeteaseArtistHead | null = null;
  @State songs: SongItem[] = [];
  @State orderByHot: boolean = true;
  @State loading: boolean = true;
  /** 供 HdsNavDestination.bindToScrollable 绑定的曲目列表控制器。 */
  private scroller: Scroller = new Scroller();

  private param(field: string): string {
    try {
      const raw = JSON.parse(this.artistParam) as Record<string, Object>;
      return String(raw[field] ?? '');
    } catch (_error) {
      return '';
    }
  }

  private artistId(): number {
    return Number(this.param('artistId'));
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    const id = this.artistId();
    if (id > 0) {
      this.head = await NeteaseApi.getArtistHead(id);
      this.songs = await NeteaseApi.getArtistSongs(id, this.orderByHot ? 'hot' : 'time', 50);
    }
    this.loading = false;
  }

  private title(): string {
    if (this.head !== null && this.head.name.length > 0) {
      return this.head.name;
    }
    return this.param('artist');
  }

  private schemeBg(dark: boolean): string {
    return Theme.background(dark);
  }

  build() {
    // 标题栏（返回 + 艺人名）由 HdsNavDestination 承载；艺人卡、排序胶囊与
    // 曲目并入同一个 List，滚动时整页内容穿到标题栏下方被 GRADIENT_BLUR
    // 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        Column() {
          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(Theme.primary(Theme.isDark()))
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.songs.length === 0) {
            EmptyState({ title: '没有找到该艺人的歌曲', subtitle: '网络异常或艺人不存在' })
          } else {
            List({ scroller: this.scroller }) {
            // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
              if (this.head !== null) {
                ListItem() {
                  Row({ space: 12 }) {
                    Image(this.head.coverUrl.length > 0 ? this.head.coverUrl : $r('app.media.ic_music_note_24'))
                      .width(64)
                      .height(64)
                      .borderRadius(32)
                      .fillColor(this.head.coverUrl.length > 0 ? Color.Transparent : Theme.primary(Theme.isDark()))
                      .alt($r('app.media.ic_music_note_24'))
                    Column({ space: 2 }) {
                      Text(this.title())
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.textPrimary(Theme.isDark()))
                        .maxLines(1)
                      Text(`${this.head.songCount} 首歌曲 · ${this.head.albumCount} 张专辑`
                        + (this.head.fansCount > 0 ? ` · ${this.head.fansCount} 关注` : ''))
                        .fontSize(11)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                        .maxLines(1)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor(Theme.surface(Theme.isDark()))
                }
              }

              ListItem() {
                Row({ space: 6 }) {
                  Text('热门50')
                    .fontSize(12)
                    .fontColor(this.orderByHot ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.orderByHot ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
                    .borderRadius(12)
                    .onClick(() => {
                      if (!this.orderByHot) {
                        this.orderByHot = true;
                        this.reload();
                      }
                    })
                  Text('最新作品')
                    .fontSize(12)
                    .fontColor(!this.orderByHot ? Theme.onPrimary(Theme.isDark()) : Theme.textSecondary(Theme.isDark()))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(!this.orderByHot ? Theme.primary(Theme.isDark()) : Theme.surface(Theme.isDark()))
                    .borderRadius(12)
                    .onClick(() => {
                      if (this.orderByHot) {
                        this.orderByHot = false;
                        this.reload();
                      }
                    })
                }
                .width('100%')
              }

              ForEach(this.songs, (song: SongItem, index: number) => {
                ListItem() {
                  SongRow({
                    songJson: song.toJson(),
                    index: index,
                    onPlay: (): void => {
                      PlayerManager.playPlaylist(this.songs, index);
                    }
                  })
                }
              }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
              // 尾部让位：列表延伸进底部手势条区后，末首歌滚过渐变遮罩仍可停稳。
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .width('100%')
            .padding({ left: 14, right: 14 })
            // 官方开发实例：穿透到标题栏下方的列表项预加载，避免滚入区域闪空。
            .cachedCount(3, true)
            .clip(false)
          }
        }
        .width('100%')
        .height('100%')
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
