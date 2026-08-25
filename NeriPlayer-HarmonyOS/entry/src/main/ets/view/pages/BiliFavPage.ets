import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { BiliApi } from '../../network/BiliApi';
import { BiliFavFolderSummary, biliFavMediaToSongItem } from '../../network/BiliFavParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';

/** Remote fav items store full SongItems; cap imports to keep one save sane. */
const IMPORT_CAP: number = 500;

/**
 * Bilibili favorite-folder detail: header + paged video list (loads more on
 * reach-end), play/shuffle, and one-shot full import into a local playlist.
 */
@Component
export struct BiliFavPage {
  @StorageProp('theme.isDark') isDark: boolean = false; // see Theme.IS_DARK_KEY
  @StorageLink('route.param') favParam: string = '';
  @State info: BiliFavFolderSummary | null = null;
  @State songs: SongItem[] = [];
  @State totalCount: number = 0;
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State loadError: string = '';
  @State importing: boolean = false;
  @State showImportDialog: boolean = false;
  @State importName: string = '';

  private page: number = 1;
  private hasMore: boolean = false;
  private seenBvids: Set<string> = new Set();

  private mediaId(): number {
    const id = Number(this.favParam);
    return Number.isFinite(id) && id > 0 ? Math.floor(id) : 0;
  }

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    if (this.mediaId() <= 0) {
      this.loadError = '无效的收藏夹链接';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const first = await BiliApi.getFavFolderPage(this.mediaId(), 1);
      this.info = first.info;
      this.totalCount = first.totalCount;
      this.hasMore = first.hasMore;
      this.page = 1;
      this.seenBvids = new Set<string>();
      this.appendItems(first.items.map((media) => biliFavMediaToSongItem(media)));
      if (first.totalCount === 0 && first.items.length === 0 && first.info === null) {
        this.loadError = '收藏夹为空或未登录（Cookie 可能已失效）';
      }
    } catch (error) {
      const e = error as Error;
      this.loadError = `收藏夹加载失败：${e.message}`;
    }
    this.loading = false;
  }

  private appendItems(items: SongItem[]): void {
    const next: SongItem[] = this.songs.slice(0, this.songs.length);
    for (const song of items) {
      const key = song.audioId.length > 0 ? song.audioId : song.name;
      if (this.seenBvids.has(key)) {
        continue;
      }
      this.seenBvids.add(key);
      next.push(song);
    }
    this.songs = next;
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    try {
      const next = await BiliApi.getFavFolderPage(this.mediaId(), this.page + 1);
      this.page += 1;
      this.hasMore = next.hasMore;
      this.appendItems(next.items.map((media) => biliFavMediaToSongItem(media)));
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `加载更多失败：${e.message}` });
    }
    this.loadingMore = false;
  }

  private playAll(shuffle: boolean): void {
    if (this.songs.length === 0) {
      promptAction.openToast({ message: '收藏夹为空' });
      return;
    }
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(this.songs, 0);
  }

  private openImportDialog(): void {
    if (this.songs.length === 0 && this.totalCount === 0) {
      return;
    }
    const info = this.info;
    this.importName = info !== null && info.title.length > 0 ? info.title : 'B 站收藏夹';
    this.showImportDialog = true;
  }

  private async confirmImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    const trimmed = this.importName.trim();
    if (trimmed.length === 0) {
      promptAction.openToast({ message: '请输入歌单名称' });
      return;
    }
    this.importing = true;
    try {
      const mediaItems = await BiliApi.getAllFavFolderItems(this.mediaId());
      const songs = mediaItems.map((media) => biliFavMediaToSongItem(media));
      const capped = songs.slice(0, IMPORT_CAP);
      if (capped.length === 0) {
        promptAction.openToast({ message: '收藏夹没有可导入的内容' });
      } else {
        const playlist = await LocalPlaylistRepository.createPlaylistWithSongs(
          trimmed,
          capped,
          MusicPlatform.LOCAL
        );
        const skipped = songs.length - capped.length;
        const suffix = skipped > 0 ? `（超出上限，已截取前 ${IMPORT_CAP} 首）` : '';
        promptAction.openToast({ message: `已导入「${playlist.name}」${playlist.songKeys.length} 首${suffix}` });
        this.showImportDialog = false;
      }
    } catch (error) {
      const e = error as Error;
      promptAction.openToast({ message: `导入失败：${e.message}` });
    }
    this.importing = false;
  }

  @Builder
  coverArt(size: number) {
    Stack() {
      if (this.info !== null && this.info.coverUrl.length > 0) {
        Image(this.info.coverUrl)
          .width(size)
          .height(size)
          .borderRadius(size > 60 ? 14 : 8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceVariant(this.isDark))
      } else {
        Column() {
          Image($r('app.media.ic_bilibili'))
            .width(size * 0.36)
            .height(size * 0.36)
        }
        .width(size)
        .height(size)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.surfaceVariant(this.isDark))
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
            .fontColor(Theme.textPrimary(this.isDark))
            .fontSize(20)
            .onClick(() => Router.pop())
          Text(this.info !== null && this.info.title.length > 0 ? this.info.title : 'B 站收藏夹')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(this.isDark))
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
              .backgroundColor(Theme.primary(this.isDark))
              .onClick(() => this.reload())
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column({ space: 10 }) {
            Row({ space: 14 }) {
              this.coverArt(92)
              Column({ space: 4 }) {
                Text(this.info !== null && this.info.title.length > 0 ? this.info.title : 'B 站收藏夹')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.textPrimary(this.isDark))
                  .maxLines(2)
                Text(this.totalCount > 0
                  ? `Bilibili · ${this.totalCount} 条`
                  : `Bilibili · ${this.songs.length} 条`)
                  .fontSize(13)
                  .fontColor(Theme.textSecondary(this.isDark))
                Row({ space: 8 }) {
                  Button('全部播放')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.onPrimary(this.isDark))
                    .backgroundColor(Theme.primary(this.isDark))
                    .borderRadius(16)
                    .onClick(() => this.playAll(false))
                  Button('随机播放')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.textPrimary(this.isDark))
                    .backgroundColor(Theme.surfaceVariant(this.isDark))
                    .borderRadius(16)
                    .onClick(() => this.playAll(true))
                  Button('导入')
                    .height(40)
                    .fontSize(12)
                    .fontColor(Theme.primary(this.isDark))
                    .backgroundColor(Theme.surfaceVariant(this.isDark))
                    .borderRadius(16)
                    .onClick(() => this.openImportDialog())
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.surface(this.isDark))
            .borderRadius(Theme.cardRadius())

            if (this.songs.length === 0) {
              EmptyState({ icon: '📺', title: '收藏夹为空', subtitle: '该收藏夹没有可播放的视频' })
            } else {
              List({ space: 1 }) {
                ForEach(this.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    SongRow({
                      songJson: song.toJson(),
                      index: index,
                      showPlatform: false,
                      onPlay: () => {
                        PlayerManager.playPlaylist(this.songs, index);
                      }
                    })
                  }
                }, (song: SongItem) => `${song.platform}_${song.audioId}`)
                if (this.hasMore) {
                  ListItem() {
                    Column({ space: 6 }) {
                      if (this.loadingMore) {
                        LoadingState()
                      } else {
                        Button('加载更多')
                          .height(40)
                          .fontSize(13)
                          .backgroundColor(Theme.surfaceVariant(this.isDark))
                          .fontColor(Theme.textPrimary(this.isDark))
                          .onClick(() => this.loadMore())
                      }
                    }
                    .width('100%')
                    .padding(14)
                    .alignItems(HorizontalAlign.Center)
                  }
                }
              }
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .width('100%')
              .onReachEnd(() => this.loadMore())
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
              .fontColor(Theme.textPrimary(this.isDark))
            Text(`将全量拉取收藏夹内容并复制到新建的本地歌单（上限 ${IMPORT_CAP} 条）`)
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.isDark))
            TextInput({ placeholder: '输入歌单名称', text: this.importName })
              .onChange((value: string) => {
                this.importName = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Theme.surfaceVariant(this.isDark))
                .fontColor(Theme.textPrimary(this.isDark))
                .onClick(() => {
                  this.showImportDialog = false;
                })
              Button(this.importing ? '导入中…' : '导入')
                .layoutWeight(1)
                .backgroundColor(Theme.primary(this.isDark))
                .onClick(() => this.confirmImport())
            }
            .width('100%')
          }
          .width('86%')
          .padding(20)
          .backgroundColor(Theme.surface(this.isDark))
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.scrim(this.isDark))
        .onClick(() => {
          this.showImportDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(this.isDark))
  }
}
