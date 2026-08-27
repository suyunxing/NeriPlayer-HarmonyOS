import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { NeteaseApi } from '../../network/NeteaseApi';
import { NeteasePlaylistOverview } from '../../network/NeteasePlaylistParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';

/** Remote playlists store full SongItems; cap imports to keep one save sane. */
const IMPORT_CAP: number = 500;

/**
 * NetEase remote playlist detail: header + resolved songs, play/shuffle, and
 * one-shot import into a local playlist (full song-reference copy).
 */
@Component
export struct NeteasePlaylistPage {
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
      const capped = overview.songs.slice(0, IMPORT_CAP);
      const playlist = await LocalPlaylistRepository.createPlaylistWithSongs(
        trimmed,
        capped,
        MusicPlatform.LOCAL
      );
      const skipped = overview.songs.length - capped.length;
      const suffix = skipped > 0 ? `（超出上限，已截取前 ${IMPORT_CAP} 首）` : '';
      promptAction.openToast({ message: `已导入「${playlist.name}」${playlist.songKeys.length} 首${suffix}` });
      this.showImportDialog = false;
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `导入失败：${e.message}` });
    }
    this.importing = false;
  }

  @Builder
  coverArt(size: number) {
    Stack() {
      if (this.overview !== null && this.overview.coverUrl.length > 0) {
        Image(this.overview.coverUrl)
          .width(size)
          .height(size)
          .borderRadius(size > 60 ? 14 : 8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
      } else {
        Column() {
          Image($r('app.media.ic_music_note_24'))
            .width(size * 0.4)
            .height(size * 0.4)
            .fillColor(Theme.primary(Theme.isDark()))
        }
        .width(size)
        .height(size)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
        .borderRadius(size > 60 ? 14 : 8)
      }
    }
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
            Row({ space: 14 }) {
              this.coverArt(92)
              Column({ space: 4 }) {
                Text(this.overview.name.length > 0 ? this.overview.name : '未命名歌单')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .maxLines(2)
                Text(this.overview.trackCount > 0
                  ? `网易云 · ${this.overview.trackCount} 首`
                  : `网易云 · ${this.overview.songs.length} 首`)
                  .fontSize(13)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                // Wraps instead of a plain Row: at 1.45x system font '导入'
                // ran past the right screen edge with only a third of it
                // visible (device audit 2026-08-24).
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
                  Button('导入')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.primary(Theme.isDark()))
                    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                    .borderRadius(16)
                    .onClick(() => this.openImportDialog())
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

            if (this.overview.songs.length === 0) {
              EmptyState({ icon: '♪', title: '歌单为空', subtitle: '该歌单没有可播放的歌曲' })
            } else {
              List() {
                ForEach(this.overview.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    SongRow({
                      songJson: song.toJson(),
                      index: index,
                      showPlatform: false,
                      onPlay: () => {
                        if (this.overview !== null) {
                          PlayerManager.playPlaylist(this.overview.songs, index);
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
            Text(`将复制 ${Math.min(this.overview?.songs.length ?? 0, IMPORT_CAP)} 首歌曲到新建的本地歌单`)
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
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
