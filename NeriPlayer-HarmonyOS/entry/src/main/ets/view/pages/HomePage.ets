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
import { SectionHeader, EmptyState, LoadingState, PlaylistCard } from '../components/Ui';

const BRAND_TITLES: string[] = ['NeriPlayer', '欢迎回来', 'NeriPlayer', '继续听歌'];

@Component
export struct HomePage {
  @State usage: UsageEntry[] = [];
  @State localPlaylists: Playlist[] = [];
  @State recentSongs: SongItem[] = [];
  @State neteaseRecommend: NeteasePlaylistSummary[] = [];
  @State loading: boolean = true;
  @State offline: boolean = false;
  @State titleIndex: number = 0;

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

            if (this.neteaseRecommend.length > 0) {
              SectionHeader({ title: '每日推荐', icon: '★' })
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

            if (this.localPlaylists.length > 0 || !this.offline) {
              SectionHeader({ title: '我的歌单', icon: '♪' })
              Grid() {
                ForEach(this.localPlaylists, (playlist: Playlist) => {
                  GridItem() {
                    PlaylistCard({
                      name: playlist.name,
                      trackCount: playlist.songKeys.length,
                      isFavorite: playlist.id === LocalPlaylistRepository.FAVORITES_ID,
                      onOpen: () => Router.push(Router.PLAYLIST_DETAIL, playlist.id)
                    })
                  }
                }, (playlist: Playlist) => playlist.id)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(14)
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
