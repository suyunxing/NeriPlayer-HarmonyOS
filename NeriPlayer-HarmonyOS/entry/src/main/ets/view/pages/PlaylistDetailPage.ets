// SPDX-License-Identifier: GPL-3.0

import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { Playlist } from '../../model/Playlist';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { HistoryRepository } from '../../data/HistoryRepository';
import { stableKeyOf } from '../../model/SongIdentity';
import { PlayerManager } from '../../player/PlayerManager';
import { resolvePlaylistPlaybackStartIndex } from '../../player/queue/QueueEngine';
import { SourceSyncCoordinator } from '../../sourcesync/SourceSyncCoordinator';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { SongRow } from '../components/SongRow';
import { SongListDataSource } from '../components/SongListDataSource';
import { EmptyState } from '../components/Ui';
import { PlaylistHeader, HeaderPill } from '../components/PlaylistHeader';
import { Router } from '../Router';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

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
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @Watch('onPlaylistChanged') @State playlist: Playlist | null = null;
  @Watch('onHistoryChanged') @State history: SongItem[] = [];
  @State showAddDialog: boolean = false;
  @State showRenameDialog: boolean = false;
  @State renameValue: string = '';
  /** 供 HdsNavDestination.bindToScrollable 绑定的歌曲列表控制器。 */
  private scroller: Scroller = new Scroller();

  /**
   * 歌曲列表走 LazyForEach 按需建行（长歌单进场不再一次性建满全部行）。
   * @State playlist/history 整体重赋值时由 @Watch 同步进数据源。
   */
  private songsDs: SongListDataSource = new SongListDataSource();
  private historyDs: SongListDataSource = new SongListDataSource();

  onPlaylistChanged(): void {
    this.songsDs.reset(this.playlist?.songs ?? []);
  }

  onHistoryChanged(): void {
    this.historyDs.reset(this.history);
  }

  /** 标题栏菜单：歌单管理（重命名/删除，原页内「⋯」按钮迁入；收藏夹不可改）。 */
  private titleMenu(): SubPageMenuEntry[] | undefined {
    if (this.isFavorites()) {
      return undefined;
    }
    return [{
      label: '歌单管理',
      icon: $r('app.media.ic_grid_dots_24'),
      action: (): void => {
        this.renameValue = this.playlist?.name ?? '';
        this.showRenameDialog = true;
      }
    }];
  }

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
    const startIndex = resolvePlaylistPlaybackStartIndex(
      playlist.songs.length,
      shuffle,
      Math.floor(Math.random() * playlist.songs.length)
    );
    PlayerManager.setShuffle(shuffle);
    PlayerManager.playPlaylist(playlist.songs, startIndex);
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
    // 标题栏（返回 + 歌单名 + 管理菜单）由 HdsNavDestination 承载；歌单头图、
    // 歌曲区与列表并入同一个 List，滚动时整页内容穿到标题栏下方被 GRADIENT_BLUR
    // 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        if (this.playlist !== null) {
          List({ scroller: this.scroller }) {
          // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
          ListItem() {
            Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
          }
            ListItem() {
              Column() {
                PlaylistHeader({
                  coverUrl: this.playlist.displayCoverUrl,
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
              }
              .padding({ bottom: 10 })
            }

            ListItem() {
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
            }

            if (this.playlist.songs.length === 0) {
              ListItem() {
                EmptyState({
                  icon: '♪',
                  title: '歌单为空',
                  subtitle: this.isFavorites() ? '在歌曲列表点 ♡ 收藏歌曲' :
                    (this.isMirrored() ? '等待自动同步从来源拉取歌曲，也可点「立即同步」' : '点击「添加」从播放历史选歌')
                })
              }
            } else {
              LazyForEach(this.songsDs, (song: SongItem, index: number) => {
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
              // key 含 index：删歌/重排后 key 未变的行不会重建，行内缓存 index
              // （序号徽标、onPlay 定位）会过期，靠 key 变化强制重建受影响行。
              }, (song: SongItem, index: number) => `${index}_${song.platform}_${song.audioId}_${song.id}`)
              // 尾部让位：列表延伸进底部手势条区后，末首歌滚过渐变遮罩仍可停稳。
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
          }
          // Stack 子组件不参与 layoutWeight 分配，短歌单时列表会缩成内容高度
          // 悬浮屏中，须显式撑满视口，让首项让位垫片把内容钉在标题栏下方。
          .height('100%')
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 14, right: 14 })
          // 官方开发实例：穿透到标题栏下方的列表项预加载，避免滚入区域闪空。
          .cachedCount(3, true)
          .clip(false)
        }

        SubPageBottomFade()

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
                LazyForEach(this.historyDs, (song: SongItem) => {
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
    // NavDestination 透明时转场与短内容区会直接透视栈底的资料库页，
    // 子页实色底由内容根补齐（同 RecentPage）。
    .backgroundColor(this.schemeBg(Theme.isDark()))
    }
    .titleBar(subPageTitleBar(
      this.playlist !== null ? this.playlist.name : '歌单',
      this.titleMenu()))
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
