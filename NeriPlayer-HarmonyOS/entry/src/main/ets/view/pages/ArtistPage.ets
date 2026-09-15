// SPDX-License-Identifier: GPL-3.0

import { NeteaseApi, NeteaseArtistHead } from '../../network/NeteaseApi';
import { SongItem } from '../../model/SongItem';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';

/**
 * 网易云艺人页（backlog §3.4）：param 为 JSON { artist: string, artistId: number }；
 * 头部走 /api/artist/head/info/get，曲目走 /api/v1/artist/songs（hot 前 50，
 * 可切新歌）。本地无缓存，加载失败给空态。
 */
@Component
export struct ArtistPage {
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  artistParam: string = '';
  @State head: NeteaseArtistHead | null = null;
  @State songs: SongItem[] = [];
  @State orderByHot: boolean = true;
  @State loading: boolean = true;

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
    Column() {
      Row({ space: 8 }) {
        Button('‹')
          .width(40)
          .height(40)
          .accessibilityText('返回')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .fontSize(20)
          .onClick(() => Router.pop())
        Text(this.title())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

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
        Column() {
          EmptyState({ title: '没有找到该艺人的歌曲', subtitle: '网络异常或艺人不存在' })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 10 }) {
          if (this.head !== null) {
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

          List() {
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
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
