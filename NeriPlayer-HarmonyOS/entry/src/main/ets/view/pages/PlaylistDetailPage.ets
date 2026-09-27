// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { stableKeyOf } from '../../model/SongIdentity';
import { PlayerManager } from '../../player/PlayerManager';
import { SourceSyncCoordinator } from '../../sourcesync/SourceSyncCoordinator';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { EmptyState } from '../components/Ui';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';
import { Router } from '../Router';

@Component
export struct PlaylistDetailPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  /** 由 MainShell 的 navDestination builder 从路由参数传入。 */
  @Prop playlistId: string = '';
  @State playlist: Playlist | null = null;
  @State history: SongItem[] = [];
  @State showAddDialog: boolean = false;
  @State showRenameDialog: boolean = false;
  @State renameValue: string = '';
  @State syncingMirror: boolean = false;
  /** 镜像歌单后台同步完成会自增该 tick；本页不订阅就不会刷新（背景同步无导航）。 */
  @StorageProp('ui.refreshTick') @Watch('onRefreshTick') refreshTick: number = 0;

  private isFavorites(): boolean {
    return this.playlistId === LocalPlaylistRepository.FAVORITES_ID;
  }

  onRefreshTick(): void {
    this.reload();
  }

  private isMirrored(): boolean {
    return this.playlist !== null && this.playlist.syncSource !== null;
  }

  private mirrorSubtitle(): string {
    const playlist = this.playlist;
    if (playlist === null || playlist.syncSource === null) {
      return '';
    }
    const platform = playlist.syncSource.platform === MusicPlatform.BILIBILI ? 'B站' : '网易云';
    const mode = playlist.syncSource.mode === 'append' ? '仅追加' : '跟随远端';
    return `${platform} · ${mode}`;
  }

  private async syncMirrorNow(): Promise<void> {
    if (this.syncingMirror) {
      return;
    }
    this.syncingMirror = true;
    try {
      await SourceSyncCoordinator.runNow();
      await this.reload();
      promptAction.openToast({ message: '同步完成' });
    } catch (error) {
      promptAction.openToast({ message: `同步失败：${(error as Error).message}` });
    } finally {
      this.syncingMirror = false;
    }
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

  private async deletePlaylist(): Promise<void> {
    if (this.isFavorites()) {
      return;
    }
    await LocalPlaylistRepository.removePlaylist(this.playlistId);
    Router.pop();
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
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
            PlaylistHeader({
              coverUrl: '',
              title: this.playlist.name,
              subtitle: this.isMirrored() ?
                `${this.playlist.songKeys.length} 首 · ${this.mirrorSubtitle()}` :
                `${this.playlist.songKeys.length} 首`
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
              if (this.isMirrored()) {
                HeaderPill({
                  label: this.syncingMirror ? '同步中…' : '立即同步',
                  onTap: (): void => {
                    this.syncMirrorNow();
                  }
                })
              }
            }

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
                subtitle: this.isFavorites() ? '在歌曲列表点 ♡ 收藏歌曲' :
                  (this.isMirrored() ? '等待自动同步从来源拉取歌曲，也可点「立即同步」' : '点击「添加」从播放历史选歌')
              })
            } else {
              List() {
                ForEach(this.playlist.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    Row() {
                      SongRow({
                        songJson: song.toJson(),
                        index: index,
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
              .onClick(() => this.deletePlaylist())
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
