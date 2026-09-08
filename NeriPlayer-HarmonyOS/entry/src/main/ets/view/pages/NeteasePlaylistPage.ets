import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { NeteaseApi } from '../../network/NeteaseApi';
import { NeteasePlaylistOverview } from '../../network/NeteasePlaylistParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';
import { Router } from '../Router';

/**
 * NetEase remote playlist detail: header + resolved songs, play/shuffle, and
 * one-shot import into a local playlist (full song-reference copy).
 */
@Component
export struct NeteasePlaylistPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  /** 由 MainShell 的 navDestination builder 从路由参数传入。 */
  @Prop playlistParam: string = '';
  @State overview: NeteasePlaylistOverview | null = null;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State importing: boolean = false;
  @State showImportDialog: boolean = false;
  @State importName: string = '';

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    const id = Number(this.playlistParam);
    if (!Number.isFinite(id) || id <= 0) {
      this.loadError = '无效的歌单链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      this.overview = await NeteaseApi.getPlaylistOverview(id);
    } catch (error) {
      const e = error as Error;
      this.loadError = `歌单加载失败：${e.message}`;
    }
    this.loading = false;
  }

  private playAll(shuffle: boolean): void {
    const overview = this.overview;
    if (overview === null || overview.songs.length === 0) {
      promptAction.openToast({ message: '歌单为空' });
      return;
    }
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(overview.songs, 0);
  }

  private openImportDialog(): void {
    const overview = this.overview;
    if (overview === null || overview.songs.length === 0) {
      return;
    }
    this.importName = overview.name;
    this.showImportDialog = true;
  }

  private async confirmImport(): Promise<void> {
    const overview = this.overview;
    if (overview === null || this.importing) {
      return;
    }
    const trimmed = this.importName.trim();
    if (trimmed.length === 0) {
      promptAction.openToast({ message: '请输入歌单名称' });
      return;
    }
    this.importing = true;
    try {
      const playlist = await LocalPlaylistRepository.createPlaylistWithSongs(
        trimmed,
        overview.songs,
        MusicPlatform.LOCAL
      );
      promptAction.openToast({ message: `已导入「${playlist.name}」${playlist.songKeys.length} 首` });
      this.showImportDialog = false;
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `导入失败：${e.message}` });
    }
    this.importing = false;
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
          Text(this.overview !== null && this.overview.name.length > 0 ? this.overview.name : '网易云歌单')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 8, right: 12, top: 8, bottom: 8 })

        if (this.loading) {
          Column() {
            LoadingState()
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError.length > 0) {
          Column() {
            EmptyState({ icon: '⚠', title: '加载失败', subtitle: this.loadError })
            Button('重试')
              .height(40)
              .fontSize(13)
              .backgroundColor(Theme.primary(Theme.isDark()))
              .onClick(() => this.reload())
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.overview !== null) {
          Column({ space: 10 }) {
            PlaylistHeader({
              coverUrl: this.overview.coverUrl,
              title: this.overview.name.length > 0 ? this.overview.name : '未命名歌单',
              subtitle: this.overview.trackCount > 0
                ? `网易云 · ${this.overview.trackCount} 首`
                : `网易云 · ${this.overview.songs.length} 首`
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
              HeaderPill({
                label: '导入',
                onTap: (): void => this.openImportDialog()
              })
            }

            if (this.overview.songs.length === 0) {
              EmptyState({ icon: '♪', title: '歌单为空', subtitle: '该歌单没有可播放的歌曲' })
            } else {
              List() {
                ForEach(this.overview.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    SongRow({
                      songJson: song.toJson(),
                      index: index,
                      onPlay: () => {
                        if (this.overview !== null) {
                          PlayerManager.playPlaylist(this.overview.songs, index);
                          Router.push(Router.NOW_PLAYING);
                        }
                      }
                    })
                  }
                }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}`)
              }
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 12 })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      if (this.showImportDialog) {
        Column() {
          Column({ space: 12 }) {
            Text('导入到本地歌单')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
            Text(`将复制 ${this.overview?.songs.length ?? 0} 首歌曲到新建的本地歌单`)
              .fontSize(12)
              .fontColor(Theme.textSecondary(Theme.isDark()))
            TextInput({ placeholder: '输入歌单名称', text: this.importName })
              .onChange((value: string) => {
                this.importName = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                .fontColor(Theme.textPrimary(Theme.isDark()))
                .onClick(() => {
                  this.showImportDialog = false;
                })
              Button(this.importing ? '导入中…' : '导入')
                .layoutWeight(1)
                .backgroundColor(Theme.primary(Theme.isDark()))
                .onClick(() => this.confirmImport())
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
          this.showImportDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
