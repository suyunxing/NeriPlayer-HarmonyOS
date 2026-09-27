// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../../model/SongItem';
import { LocalPlaylistRepository } from '../../data/LocalPlaylistRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { AlbumQuery, AlbumSongs } from '../../util/AlbumSongs';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';
import { stableKeyOf } from '../../model/SongIdentity';
import { NeteaseApi } from '../../network/NeteaseApi';
import { MusicPlatform } from '../../model/MusicPlatform';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * 「查看专辑」页：聚合本地库（全部歌单 + 当前播放曲）中同一专辑的歌曲。
 * param 为 JSON：{ album: string, albumId: number }；网易云按 albumId 精确
 * 匹配，其余平台按专辑名匹配。
 */
@Component
export struct AlbumPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  albumParam: string = '';
  @State songs: SongItem[] = [];
  @State albumName: string = '';
  @State remoteAlbum: boolean = false;
  @State loading: boolean = true;
  /** 供 HdsNavDestination.bindToScrollable 绑定的歌曲列表控制器。 */
  private scroller: Scroller = new Scroller();

  private query(): AlbumQuery {
    try {
      const raw = JSON.parse(this.albumParam) as Record<string, Object>;
      return {
        album: String(raw['album'] ?? ''),
        albumId: Number(raw['albumId'] ?? 0)
      };
    } catch (error) {
      return { album: '', albumId: 0 };
    }
  }

  async aboutToAppear(): Promise<void> {
    const query = this.query();
    this.albumName = query.album;
    const pool: SongItem[] = [];
    const playlists = await LocalPlaylistRepository.loadAll();
    for (const playlist of playlists) {
      for (const song of playlist.songs) {
        pool.push(song);
      }
    }
    // The playing song may not be in any playlist yet; it still belongs here.
    const current = PlayerManager.getCurrentSong();
    if (current !== null) {
      pool.push(current);
    }
    this.songs = AlbumSongs.collect(pool, query);
    // NetEase albums upgrade to the remote track list (backlog §3.4): the
    // local pool only knows songs the user already played somewhere.
    if (query.albumId > 0 && pool.some((song: SongItem): boolean =>
      song.platform === MusicPlatform.NETEASE && song.albumId === query.albumId)) {
      const remote = await NeteaseApi.getAlbumDetail(query.albumId);
      if (remote.length > 0) {
        this.songs = remote;
        this.remoteAlbum = true;
      }
    }
    this.loading = false;
  }

  private playFrom(index: number): void {
    PlayerManager.playPlaylist(this.songs, index);
    Router.push(Router.NOW_PLAYING);
  }


  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  private subTitleText(): string | undefined {
    if (this.songs.length === 0) {
      return undefined;
    }
    return this.remoteAlbum ? `专辑 · ${this.songs.length} 首（网易云）` : `专辑 · ${this.songs.length} 首（本地库）`;
  }

  build() {
    // 标题栏（返回 + 标题/副标题）由 HdsNavDestination 承载，滚动时列表内容
    // 穿到标题栏下方被 GRADIENT_BLUR 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        Column() {
          if (this.loading) {
            Column()
              .layoutWeight(1)
              .width('100%')
          } else if (this.songs.length === 0) {
            Column() {
              EmptyState({
                icon: '💿',
                title: '专辑内暂无本地库歌曲',
                subtitle: '收藏或加入歌单后，同专辑歌曲会出现在这里'
              })
            }
            .padding({ top: this.topInset + SUB_TITLEBAR_SPACE_VP })
            .width('100%')
          } else {
            List({ scroller: this.scroller, space: 2 }) {
            // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
              ForEach(this.songs, (song: SongItem, index: number) => {
                ListItem() {
                  SongRow({
                    songJson: song.toJson(),
                    onPlay: () => this.playFrom(index)
                  })
                }
              }, (song: SongItem) => stableKeyOf(song))
              // 尾部让位：列表延伸进底部手势条区后，末首歌滚过渐变遮罩仍可停稳。
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .width('100%')
            .padding({ left: 12, right: 12 })
            // 官方开发实例：穿透到标题栏下方的列表项预加载，避免滚入区域闪空。
            .cachedCount(3, true)
            .clip(false)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.schemeBg(Theme.isDark()))

        SubPageBottomFade()
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(subPageTitleBar(
      this.albumName.length > 0 ? this.albumName : '专辑',
      undefined,
      this.subTitleText()))
    .bindToScrollable([this.scroller])
    // 透明背景回落到 Index 沉浸背景层（深色模式手势条区不露白边，同原共享
    // NavDestination 包装层的处理）。
    .backgroundColor(Color.Transparent)
    // 内容区延伸进底部手势条区，滚动内容真实透到系统指示条后面被渐变遮罩覆盖。
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    // destination 销毁（Router.pop / 系统返回 / 侧滑 / reset）时通知常驻 Tab 页刷新。
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
