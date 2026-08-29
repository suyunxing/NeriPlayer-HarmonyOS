import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { stableKeyOf } from '../../model/SongIdentity';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { SongRow } from '../components/SongRow';
import { EmptyState } from '../components/Ui';
import { Router } from '../Router';

@Component
export struct PlaylistDetailPage {
  /** 由 MainShell 的 navDestination builder 从路由参数传入。 */
  @Prop playlistId: string = '';
  @State playlist: Playlist | null = null;
  @State history: SongItem[] = [];
  @State showAddDialog: boolean = false;
  @State showRenameDialog: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State renameValue: string = '';

  private isFavorites(): boolean {
    return this.playlistId === LocalPlaylistRepository.FAVORITES_ID;
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
    this.history = await HistoryRepository.getRecent();
  }

  private async reload(): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    this.playlist = playlists.find((item: Playlist) => item.id === this.playlistId) ?? null;
  }

  private playAll(shuffle: boolean): void {
    const playlist = this.playlist;
    if (playlist === null || playlist.songs.length === 0) {
      promptAction.openToast({ message: '歌单为空' });
      return;
    }
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(playlist.songs, 0);
  }

  private async addSong(song: SongItem): Promise<void> {
    await LocalPlaylistRepository.addSong(this.playlistId, song);
    this.showAddDialog = false;
    await this.reload();
  }

  private async removeSong(songKey: string): Promise<void> {
    await LocalPlaylistRepository.removeSong(this.playlistId, songKey);
    await this.reload();
  }

  private async confirmRename(): Promise<void> {
    const trimmed = this.renameValue.trim();
    if (trimmed.length === 0) {
      promptAction.openToast({ message: '请输入歌单名称' });
      return;
    }
    await LocalPlaylistRepository.renamePlaylist(this.playlistId, trimmed);
    this.showRenameDialog = false;
    await this.reload();
  }

  /** Confirmation copy for the delete; there is no recycle bin to undo it. */
  private deleteWarning(): string {
    const playlist = this.playlist;
    const name = playlist !== null ? playlist.name : '';
    const count = playlist !== null ? playlist.songs.length : 0;
    return `歌单「${name}」及其 ${count} 首歌曲记录将被删除，此操作无法撤销。`;
  }

  private async deletePlaylist(): Promise<void> {
    this.showDeleteConfirm = false;
    if (this.isFavorites()) {
      return;
    }
    await LocalPlaylistRepository.removePlaylist(this.playlistId);
    Router.pop();
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 8 }) {
          Button('‹')
            .width(40)
            .height(40)
            // '‹' is punctuation to a screen reader; name the action.
            .accessibilityText('返回')
            .type(ButtonType.Circle)
            .backgroundColor(Color.Transparent)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .fontSize(20)
            .onClick(() => Router.pop())
          Text(this.playlist !== null ? this.playlist.name : '歌单')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!this.isFavorites()) {
            Button('⋯')
              .width(40)
              .height(40)
              .type(ButtonType.Circle)
              .backgroundColor(Color.Transparent)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .fontSize(18)
              .accessibilityText('歌单管理')
              .onClick(() => {
                this.renameValue = this.playlist?.name ?? '';
                this.showRenameDialog = true;
              })
          }
        }
        .width('100%')
        .padding({ left: 8, right: 12, top: 8, bottom: 8 })

        if (this.playlist !== null) {
          Column({ space: 10 }) {
            Row({ space: 14 }) {
              Column() {
                Image($r('app.media.ic_music_note_24'))
                  .width(34)
                  .height(34)
                  .fillColor(Theme.primary(Theme.isDark()))
              }
              .width(92)
              .height(92)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .borderRadius(14)

              Column({ space: 4 }) {
                Text(this.playlist.name)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .maxLines(2)
                Text(`${this.playlist.songKeys.length} 首`)
                  .fontSize(13)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                // Same X-to-Y trade as the NetEase header: the button pair sits
                // in a layoutWeight(1) column beside a 92vp cover, so at large
                // system fonts a plain Row runs off the right edge.
                Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
                  Button('全部播放')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.onPrimary(Theme.isDark()))
                    .backgroundColor(Theme.primary(Theme.isDark()))
                    .borderRadius(16)
                    .onClick(() => this.playAll(false))
                  Button('随机播放')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                    .borderRadius(16)
                    .onClick(() => this.playAll(true))
                }
                .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(Theme.cardRadius())

            Row() {
              Text('歌曲')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .layoutWeight(1)
              Button('＋ 添加')
                .height(40)
                .fontSize(12)
                .backgroundColor(Theme.surface(Theme.isDark()))
                .fontColor(Theme.primary(Theme.isDark()))
                .onClick(() => {
                  this.showAddDialog = true;
                })
            }
            .width('100%')

            if (this.playlist.songs.length === 0) {
              EmptyState({
                icon: '♪',
                title: '歌单为空',
                subtitle: this.isFavorites() ? '在歌曲列表点 ♡ 收藏歌曲' : '点击「添加」从播放历史选歌'
              })
            } else {
              List() {
                ForEach(this.playlist.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    Row() {
                      SongRow({
                        songJson: song.toJson(),
                        index: index,
                        showPlatform: true,
                        onPlay: () => {
                          if (this.playlist !== null) {
                            PlayerManager.playPlaylist(this.playlist.songs, index);
                            Router.push(Router.NOW_PLAYING);
                          }
                        }
                      })
                      Button() {
                        Image($r('app.media.ic_close_24'))
                          .width(16)
                          .height(16)
                          .fillColor(Theme.textDisabled(Theme.isDark()))
                      }
                      .width(40)
                      .height(40)
                      .type(ButtonType.Circle)
                      .backgroundColor(Color.Transparent)
                      .accessibilityText('从歌单移除')
                      .onClick(() => this.removeSong(stableKeyOf(song)))
                    }
                    .width('100%')
                  }
                }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
              }
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      if (this.showAddDialog) {
        Column() {
          Column() {
            Row() {
              Text('从播放历史添加')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .layoutWeight(1)
              Text('关闭')
                .fontSize(14)
                .fontColor(Theme.primary(Theme.isDark()))
                .onClick(() => {
                  this.showAddDialog = false;
                })
            }
            .width('100%')
            .padding({ bottom: 8 })

            if (this.history.length === 0) {
              Text('暂无播放历史')
                .fontSize(14)
                .fontColor(Theme.textSecondary(Theme.isDark()))
                .padding(24)
            } else {
              List() {
                ForEach(this.history, (song: SongItem) => {
                  ListItem() {
                    Row({ space: 10 }) {
                      Text('＋')
                        .fontSize(16)
                        .fontColor(Theme.primary(Theme.isDark()))
                        .width(28)
                      Column({ space: 2 }) {
                        Text(song.displayName)
                          .fontSize(14)
                          .fontColor(Theme.textPrimary(Theme.isDark()))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(song.displayArtist)
                          .fontSize(11)
                          .fontColor(Theme.textSecondary(Theme.isDark()))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(8)
                    .onClick(() => this.addSong(song))
                  }
                }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
              }
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .width('100%')
            }
          }
          .width('100%')
          .height('62%')
          .padding(16)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius({ topLeft: 22, topRight: 22 })
          .position({ x: 0, y: '38%' })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showAddDialog = false;
        })
      }

      if (this.showRenameDialog) {
        Column() {
          Column({ space: 12 }) {
            Text('重命名歌单')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            TextInput({ placeholder: '输入歌单名称', text: this.renameValue })
              .onChange((value: string) => {
                this.renameValue = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => {
                  this.showRenameDialog = false;
                })
              Button('保存')
                .layoutWeight(1)
                .backgroundColor(Theme.primary(Theme.isDark()))
                .onClick(() => this.confirmRename())
            }
            .width('100%')
            Button('删除歌单')
              .width('100%')
              .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
              .fontColor(Theme.danger(Theme.isDark()))
              .onClick(() => {
                // Destructive and irreversible, so it now opens a confirmation
                // instead of deleting on the first tap (static audit 2026-08-25).
                this.showRenameDialog = false;
                this.showDeleteConfirm = true;
              })
          }
          .width('86%')
          .padding(20)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showRenameDialog = false;
        })
      }

      if (this.showDeleteConfirm) {
        Column() {
          Column({ space: 12 }) {
            Text('删除歌单')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            Text(this.deleteWarning())
              .fontSize(13)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .width('100%')
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => {
                  this.showDeleteConfirm = false;
                })
              Button('删除')
                .layoutWeight(1)
                .backgroundColor(Theme.danger(Theme.isDark()))
                .onClick(() => this.deletePlaylist())
            }
            .width('100%')
          }
          .width('86%')
          .padding(20)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(Theme.isDark()))
        .onClick(() => {
          this.showDeleteConfirm = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
