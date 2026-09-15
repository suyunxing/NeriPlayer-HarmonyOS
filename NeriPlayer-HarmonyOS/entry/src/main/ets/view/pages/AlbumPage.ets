// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { AlbumQuery, AlbumSongs } from '../../util/AlbumSongs';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';
import { stableKeyOf } from '../../model/SongIdentity';

/**
 * 「查看专辑」页：聚合本地库（全部歌单 + 当前播放曲）中同一专辑的歌曲。
 * param 为 JSON：{ album: string, albumId: number }；网易云按 albumId 精确
 * 匹配，其余平台按专辑名匹配。
 */
@Component
export struct AlbumPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  albumParam: string = '';
  @State songs: SongItem[] = [];
  @State albumName: string = '';
  @State loading: boolean = true;

  private query(): AlbumQuery {
    try {
      const raw = JSON.parse(this.albumParam) as Record<string, Object>;
      return {
        album: String(raw['album'] ?? ''),
        albumId: Number(raw['albumId'] ?? 0)
      };
    } catch (error) {
      return { album: '', albumId: 0 };
    }
  }

  async aboutToAppear(): Promise<void> {
    const query = this.query();
    this.albumName = query.album;
    const pool: SongItem[] = [];
    const playlists = await LocalPlaylistRepository.loadAll();
    for (const playlist of playlists) {
      for (const song of playlist.songs) {
        pool.push(song);
      }
    }
    // The playing song may not be in any playlist yet; it still belongs here.
    const current = PlayerManager.getCurrentSong();
    if (current !== null) {
      pool.push(current);
    }
    this.songs = AlbumSongs.collect(pool, query);
    this.loading = false;
  }

  private playFrom(index: number): void {
    PlayerManager.playPlaylist(this.songs, index);
    Router.push(Router.NOW_PLAYING);
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
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
        Column({ space: 2 }) {
          Text(this.albumName.length > 0 ? this.albumName : '专辑')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.songs.length > 0) {
            Text(`专辑 · ${this.songs.length} 首（本地库）`)
              .fontSize(11)
              .fontColor(Theme.textSecondary(Theme.isDark()))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

      if (this.loading) {
        Column()
          .layoutWeight(1)
          .width('100%')
      } else if (this.songs.length === 0) {
        EmptyState({
          icon: '💿',
          title: '专辑内暂无本地库歌曲',
          subtitle: '收藏或加入歌单后，同专辑歌曲会出现在这里'
        })
      } else {
        List({ space: 2 }) {
          ForEach(this.songs, (song: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: song.toJson(),
                onPlay: () => this.playFrom(index)
              })
            }
          }, (song: SongItem) => stableKeyOf(song))
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
