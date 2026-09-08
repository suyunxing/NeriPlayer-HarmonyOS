import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { BiliApi } from '../../network/BiliApi';
import { BiliFavFolderSummary, biliFavMediaToSongItem } from '../../network/BiliFavParser';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';

/**
 * Bilibili favorite-folder detail: header + paged video list (loads more on
 * reach-end), play/shuffle, and one-shot full import into a local playlist.
 */
@Component
export struct BiliFavPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  /** 由 MainShell 的 navDestination builder 从路由参数传入。 */
  @Prop favParam: string = '';
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
      if (songs.length === 0) {
        promptAction.openToast({ message: '收藏夹没有可导入的内容' });
      } else {
        const playlist = await LocalPlaylistRepository.createPlaylistWithSongs(
          trimmed,
          songs,
          MusicPlatform.LOCAL
        );
        promptAction.openToast({ message: `已导入「${playlist.name}」${playlist.songKeys.length} 首` });
        this.showImportDialog = false;
      }
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
          Text(this.info !== null && this.info.title.length > 0 ? this.info.title : 'B 站收藏夹')
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
        } else {
          Column({ space: 10 }) {
            PlaylistHeader({
              coverUrl: this.info !== null ? this.info.coverUrl : '',
              title: this.info !== null && this.info.title.length > 0 ? this.info.title : 'B 站收藏夹',
              subtitle: this.totalCount > 0
                ? `Bilibili · ${this.totalCount} 条`
                : `Bilibili · ${this.songs.length} 条`
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

            if (this.songs.length === 0) {
              EmptyState({ icon: '📺', title: '收藏夹为空', subtitle: '该收藏夹没有可播放的视频' })
            } else {
              List({ space: 1 }) {
                ForEach(this.songs, (song: SongItem, index: number) => {
                  ListItem() {
                    SongRow({
                      songJson: song.toJson(),
                      index: index,
                      onPlay: () => {
                        PlayerManager.playPlaylist(this.songs, index);
                        Router.push(Router.NOW_PLAYING);
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
                          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                          .fontColor(Theme.textPrimary(Theme.isDark()))
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
              .fontColor(Theme.textPrimary(Theme.isDark()))
            Text(`将全量拉取收藏夹内容并复制到新建的本地歌单（共 ${this.totalCount} 条）`)
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
