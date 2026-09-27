// SPDX-License-Identifier: GPL-3.0

import { promptAction } from '@kit.ArkUI';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { BiliApi } from '../../network/BiliApi';
import { BiliFavFolderSummary, biliFavMediaToSongItem } from '../../network/BiliFavParser';
import { PlayerManager } from '../../player/PlayerManager';
import { resolvePlaylistPlaybackStartIndex } from '../../player/queue/QueueEngine';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { EmptyState, LoadingState } from '../components/Ui';
import { Router } from '../Router';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

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
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State info: BiliFavFolderSummary | null = null;
  @State songs: SongItem[] = [];
  @State totalCount: number = 0;
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State loadError: string = '';
  @State importing: boolean = false;
  @State showImportDialog: boolean = false;
  @State importName: string = '';
  /** 供 HdsNavDestination.bindToScrollable 绑定的收藏夹列表控制器。 */
  private scroller: Scroller = new Scroller();

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
    const startIndex = resolvePlaylistPlaybackStartIndex(
      this.songs.length,
      shuffle,
      Math.floor(Math.random() * this.songs.length)
    );
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(this.songs, startIndex);
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
    // 标题栏（返回 + 收藏夹名）由 HdsNavDestination 承载；收藏夹头图、视频列
    // 表与「加载更多」并入同一个 List，滚动时整页内容穿到标题栏下方被
    // GRADIENT_BLUR 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        if (this.loading) {
          Column() {
            LoadingState()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        } else if (this.loadError.length > 0) {
          Column() {
            EmptyState({ icon: '⚠', title: '加载失败', subtitle: this.loadError })
            Button('重试')
              .height(40)
              .fontSize(13)
              .backgroundColor(Theme.primary(Theme.isDark()))
              .onClick(() => this.reload())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        } else {
          List({ scroller: this.scroller, space: 1 }) {
          // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
          ListItem() {
            Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
          }
            ListItem() {
              Column() {
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
              }
              .padding({ bottom: 10 })
            }

            if (this.songs.length === 0) {
              ListItem() {
                EmptyState({ icon: '📺', title: '收藏夹为空', subtitle: '该收藏夹没有可播放的视频' })
              }
            } else {
              ForEach(this.songs, (song: SongItem, index: number) => {
                ListItem() {
                  SongRow({
                    songJson: song.toJson(),
                    index: index,
                    onPlay: () => {
                      PlayerManager.playPlaylist(this.songs, index);
                      Router.pushNowPlaying(); // 歌曲行入口暂不带触发 id，走系统默认转场（M4 真机评估后铺 id）
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
              // 尾部让位：列表延伸进底部手势条区后，末条视频滚过渐变遮罩仍可停稳。
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
          .onReachEnd(() => this.loadMore())
          // 官方开发实例：穿透到标题栏下方的列表项预加载，避免滚入区域闪空。
          .cachedCount(3, true)
          .clip(false)
          .backgroundColor(this.schemeBg(Theme.isDark()))
        }

        SubPageBottomFade()

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
    // NavDestination 透明时短内容区会透视栈底 Tab 页，实色底由内容根补齐。
    .backgroundColor(this.schemeBg(Theme.isDark()))
    }
    .titleBar(subPageTitleBar(
      this.info !== null && this.info.title.length > 0 ? this.info.title : 'B 站收藏夹'))
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
