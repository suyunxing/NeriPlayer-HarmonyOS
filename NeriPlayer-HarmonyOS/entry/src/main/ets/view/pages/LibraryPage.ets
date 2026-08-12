import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { DownloadsRepository } from '../../data/DownloadsRepository';
import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { LocalMediaScanner } from '../../data/LocalMediaScanner';
import { PlayerManager } from '../../player/PlayerManager';
import { Router } from '../Router';
import { Theme } from '../Theme';
import { SettingRow, EmptyState, SongCountChip } from '../components/Ui';

@Component
export struct LibraryPage {
  @State playlists: Playlist[] = [];
  @State favorites: Playlist | null = null;
  @State downloadCount: number = 0;
  @State localSongCount: number = 0;
  @State playCount: number = 0;
  @State listenHours: number = 0;
  @State listenMinutes: number = 0;
  @State showCreateDialog: boolean = false;
  @State newPlaylistName: string = '';

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    this.playlists = playlists;
    this.favorites = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID) ?? null;
    const tasks = await DownloadsRepository.loadAll();
    this.downloadCount = tasks.length;
    this.localSongCount = (await LocalMediaScanner.loadCached()).length;
    this.playCount = await PlaybackStatsRepository.getTotalPlayCount();
    const listenMs = await PlaybackStatsRepository.getTotalListenMs();
    this.listenHours = Math.floor(listenMs / 3600000);
    this.listenMinutes = Math.floor((listenMs % 3600000) / 60000);
  }

  private async createPlaylist(): Promise<void> {
    this.newPlaylistName = '';
    this.showCreateDialog = true;
  }

  private async confirmCreate(): Promise<void> {
    const trimmed = this.newPlaylistName.trim();
    if (trimmed.length === 0) {
      promptAction.openToast({ message: '请输入歌单名称' });
      return;
    }
    await LocalPlaylistRepository.createPlaylist(trimmed);
    this.showCreateDialog = false;
    await this.reload();
  }

  private async playFavorites(): Promise<void> {
    const favorites = this.favorites;
    if (favorites === null || favorites.songs.length === 0) {
      promptAction.openToast({ message: '收藏夹为空' });
      return;
    }
    await PlayerManager.playPlaylist(favorites.songs, 0);
  }

  private async scanLocal(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
      if (context === undefined) {
        promptAction.openToast({ message: '应用上下文未就绪' });
        return;
      }
      const songs = await LocalMediaScanner.scan(context);
      this.localSongCount = songs.length;
      promptAction.openToast({ message: `已导入 ${songs.length} 首本地音乐` });
      await this.reload();
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `扫描失败：${e.message}` });
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
        Text('资料库')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .width('100%')
          .margin({ top: 12 })

        Row({ space: 10 }) {
          StatCard({
            icon: '❤',
            value: this.favorites !== null ? `${this.favorites.songKeys.length} 首` : '0 首',
            label: '我的收藏',
            onTap: () => {
              if (this.favorites !== null) {
                Router.push(Router.PLAYLIST_DETAIL, LocalPlaylistRepository.FAVORITES_ID);
              }
            }
          })
          StatCard({
            icon: '⤓',
            value: `${this.downloadCount} 个任务`,
            label: '下载管理',
            onTap: () => Router.push(Router.DOWNLOADS)
          })
          StatCard({
            icon: '♫',
            value: `${this.localSongCount} 首`,
            label: '本地音频',
            onTap: () => this.scanLocal()
          })
        }
        .width('100%')

        Column({ space: 1 }) {
          SettingRow({
            title: '我的收藏',
            subtitle: this.favorites !== null ? `${this.favorites.songKeys.length} 首 · 点击播放` : '还没有收藏歌曲',
            icon: '❤',
            onTap: () => {
              if (this.favorites !== null) {
                Router.push(Router.PLAYLIST_DETAIL, LocalPlaylistRepository.FAVORITES_ID);
              }
            }
          })
          SettingRow({
            title: '播放历史',
            subtitle: `累计播放 ${this.playCount} 次`,
            icon: '⏱',
            onTap: () => Router.push(Router.RECENT)
          })
          SettingRow({
            title: '播放统计',
            subtitle: `累计收听 ${this.listenHours} 小时 ${this.listenMinutes} 分钟`,
            icon: '📊',
            onTap: () => Router.push(Router.STATS)
          })
          SettingRow({
            title: '下载管理',
            subtitle: this.downloadCount > 0 ? `${this.downloadCount} 个下载任务` : '暂无下载任务',
            icon: '⤓',
            onTap: () => Router.push(Router.DOWNLOADS)
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)

        Row() {
          Text('本地歌单')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Button('＋ 新建')
            .height(32)
            .fontSize(13)
            .backgroundColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.createPlaylist())
        }
        .width('100%')
        .margin({ top: 6 })

        if (this.playlists.length === 0) {
          EmptyState({
            icon: '♪',
            title: '暂无本地歌单',
            subtitle: '点击「新建」创建第一个歌单'
          })
        } else {
          Column({ space: 1 }) {
            ForEach(this.playlists, (playlist: Playlist) => {
              Row({ space: 12 }) {
                Text('♪')
                  .fontSize(20)
                  .width(44)
                  .height(44)
                  .textAlign(TextAlign.Center)
                  .fontColor(Theme.primary(Theme.isDark()))
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .borderRadius(8)
                Column({ space: 2 }) {
                  Text(playlist.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(playlist.songKeys.length > 0 ? `${playlist.songKeys.length} 首` : '空歌单')
                    .fontSize(12)
                    .fontColor(Theme.textSecondary(Theme.isDark()))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text('›')
                  .fontSize(18)
                  .fontColor(Theme.textDisabled(Theme.isDark()))
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface(Theme.isDark()))
              .onClick(() => Router.push(Router.PLAYLIST_DETAIL, playlist.id))
            }, (playlist: Playlist) => playlist.id)
          }
          .width('100%')
          .borderRadius(Theme.cardRadius())
          .clip(true)
        }

        Row() {
          Text('本地音频')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Button('扫描')
            .height(32)
            .fontSize(13)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => this.scanLocal())
        }
        .width('100%')
        .margin({ top: 12 })

        SettingRow({
          title: '本地音乐库',
          subtitle: this.localSongCount > 0 ? `已收录 ${this.localSongCount} 首本地音频` : '点击扫描手机上的音频文件',
          icon: '🗂',
          onTap: () => this.scanLocal()
        })

        Text('平台')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .width('100%')
          .margin({ top: 12 })

        Column({ space: 1 }) {
          SettingRow({
            title: '网易云音乐',
            subtitle: '登录与歌单同步（待移植）',
            icon: '🎵',
            onTap: () => promptAction.openToast({ message: '网易云登录待移植' })
          })
          SettingRow({
            title: 'Bilibili',
            subtitle: '收藏夹与音频（待移植）',
            icon: '📺',
            onTap: () => promptAction.openToast({ message: 'Bilibili 登录待移植' })
          })
          SettingRow({
            title: '一起听',
            subtitle: 'Listen Together（待移植）',
            icon: '👥',
            onTap: () => promptAction.openToast({ message: 'Listen Together 待移植' })
          })
        }
        .width('100%')
        .backgroundColor(Theme.surface(Theme.isDark()))
        .borderRadius(Theme.cardRadius())
        .clip(true)
      }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.background(Theme.isDark()))

      if (this.showCreateDialog) {
        Column() {
          Column({ space: 12 }) {
            Text('新建歌单')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            TextInput({ placeholder: '输入歌单名称', text: this.newPlaylistName })
              .onChange((value: string) => {
                this.newPlaylistName = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => {
                  this.showCreateDialog = false;
                })
              Button('创建')
                .layoutWeight(1)
                .backgroundColor(Theme.primary(Theme.isDark()))
                .onClick(() => this.confirmCreate())
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
          this.showCreateDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct StatCard {
  icon: string = '';
  value: string = '';
  label: string = '';
  onTap: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Text(this.icon)
        .fontSize(22)
      Text(this.value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .maxLines(1)
      Text(this.label)
        .fontSize(11)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14, left: 6, right: 6 })
    .backgroundColor(Theme.surface(Theme.isDark()))
    .borderRadius(14)
    .onClick(() => this.onTap())
  }
}
