// SPDX-License-Identifier: GPL-3.0

import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SongItem } from '../../model/SongItem';
import { stableKeyOf } from '../../model/SongIdentity';
import { HistoryRepository } from '../../data/HistoryRepository';
import { PlaybackStatsRepository, StatsRoot } from '../../data/PlaybackStatsRepository';
import { PlayerManager } from '../../player/PlayerManager';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { SongRow } from '../components/SongRow';
import { Router } from '../Router';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

/**
 * 播放历史（参考应用历史页）：搜索、按时间/次数排序、播放全部、更多菜单
 * （使用说明 / 导出到本机 / 从本机导入 / 清除所有记录）。记录仅存本机、
 * FIFO 上限 1000 条（HistoryRepository.LIMIT）；播放次数取自统计仓库。
 */
@Component
export struct RecentPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State songs: SongItem[] = [];
  @State playCounts: Record<string, number> = {};
  @State loaded: boolean = false;
  @State query: string = '';
  @State sortByCount: boolean = false;
  @State busy: boolean = false;
  /** 供 HdsNavDestination.bindToScrollable 绑定的历史列表控制器。 */
  private scroller: Scroller = new Scroller();

  /**
   * 标题栏菜单（原页内排序钮 + 更多菜单迁入）：排序切换 + 说明/导出/导入/清除。
   * 超出 maxCount（默认 3）的项由 HDS 标题栏自动收进溢出菜单。
   */
  private titleMenu(): SubPageMenuEntry[] {
    return [
      {
        label: this.sortByCount ? '改为按时间排序' : '改为按次数排序',
        icon: $r('sys.symbol.sort'),
        action: () => this.toggleSort()
      },
      {
        label: '使用说明',
        icon: $r('sys.symbol.questionmark_circle'),
        action: () => this.showUsageNote()
      },
      {
        label: '导出到本机',
        icon: $r('sys.symbol.upload'),
        action: () => this.exportHistory()
      },
      {
        label: '从本机导入',
        icon: $r('sys.symbol.square_and_arrow_down'),
        action: () => this.importHistory()
      },
      {
        label: '清除所有记录',
        icon: $r('sys.symbol.trash'),
        action: () => this.confirmClearAll()
      }
    ];
  }

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    this.songs = await HistoryRepository.getRecent();
    const root: StatsRoot = await PlaybackStatsRepository.snapshot();
    const counts: Record<string, number> = {};
    for (const key of Object.keys(root.tracks)) {
      counts[key] = root.tracks[key].playCount;
    }
    this.playCounts = counts;
    this.loaded = true;
  }

  private playCountOf(song: SongItem): number {
    const count = this.playCounts[stableKeyOf(song)];
    return count === undefined ? 0 : count;
  }

  /** 搜索过滤 + 排序（时间序为存储序；次数序稳定破平）。 */
  private visibleSongs(): SongItem[] {
    const keyword = this.query.trim().toLowerCase();
    const filtered = this.songs.filter((song: SongItem) => {
      if (keyword.length === 0) {
        return true;
      }
      return song.displayName.toLowerCase().includes(keyword)
        || song.displayArtist.toLowerCase().includes(keyword);
    });
    if (!this.sortByCount) {
      return filtered;
    }
    return filtered.slice().sort((a: SongItem, b: SongItem) => {
      const diff = this.playCountOf(b) - this.playCountOf(a);
      return diff !== 0 ? diff : this.songs.indexOf(a) - this.songs.indexOf(b);
    });
  }

  private play(index: number): void {
    PlayerManager.playPlaylist(this.visibleSongs(), index);
    Router.push(Router.NOW_PLAYING);
  }

  private playAll(): void {
    const list = this.visibleSongs();
    if (list.length === 0) {
      return;
    }
    PlayerManager.playPlaylist(list, 0);
    Router.push(Router.NOW_PLAYING);
  }

  private toggleSort(): void {
    this.sortByCount = !this.sortByCount;
    this.getUIContext().getPromptAction().showToast({
      message: this.sortByCount ? '按播放次数排序' : '按时间排序',
      duration: 1200
    });
  }

  private showUsageNote(): void {
    this.getUIContext().showAlertDialog({
      title: '播放历史',
      message: `你的播放历史会被记录在这里，所有记录均保存在本机。\n最多记录 ${HistoryRepository.LIMIT} 条数据，超出后最早的记录会被自动淘汰。\n若开启了云同步（GitHub / WebDAV），最近播放会随备份一起同步。`,
      confirm: {
        value: '确定',
        action: () => {
        }
      }
    });
  }

  // ---- 导出到本机（DocumentViewPicker 保存 JSON） -------------------------

  private async exportHistory(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const docPicker = new picker.DocumentViewPicker();
      const stamp = new Date();
      const name = `neriplayer-history-${stamp.getFullYear()}${`${stamp.getMonth() + 1}`.padStart(2, '0')}${`${stamp.getDate()}`.padStart(2, '0')}.json`;
      const uris = await docPicker.save({ newFileNames: [name] });
      if (uris.length === 0) {
        return;
      }
      const text = HistoryRepository.serializeExport(this.songs, Date.now());
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }
      this.getUIContext().getPromptAction().showToast({
        message: `已导出 ${this.songs.length} 条播放历史`,
        duration: 2000
      });
    } catch (error) {
      const e = error as Error;
      this.getUIContext().getPromptAction().showToast({ message: `导出失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  // ---- 从本机导入（选择 JSON、容错解析、按稳定键合并） ---------------------

  private async importHistory(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['json']
      });
      if (uris.length === 0) {
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      let text = '';
      try {
        const stat = fileIo.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
      } finally {
        fileIo.closeSync(file);
      }
      const imported = HistoryRepository.parseImportJson(text);
      if (imported === null) {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败：不是有效的播放历史文件' });
        return;
      }
      if (imported.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '文件中没有可导入的记录' });
        return;
      }
      const total = await HistoryRepository.importSongs(imported);
      await this.refresh();
      this.getUIContext().getPromptAction().showToast({
        message: `已导入 ${imported.length} 条记录，当前共 ${total} 条`,
        duration: 2000
      });
    } catch (error) {
      const e = error as Error;
      this.getUIContext().getPromptAction().showToast({ message: `导入失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  private confirmClearAll(): void {
    this.getUIContext().showAlertDialog({
      title: '清除所有记录',
      message: `将删除本机全部播放历史（共 ${this.songs.length} 条），删除后的空档也会随云同步传播。确定继续？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: Theme.danger(Theme.isDark()),
        action: (): void => {
          HistoryRepository.clear().then(() => {
            this.songs = [];
            this.playCounts = {};
          });
        }
      }
    });
  }

  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    // 标题栏（返回 + 标题 + 排序/更多菜单）由 HdsNavDestination 承载；搜索框、
    // 播放全部与历史列表并入同一个 List，滚动时整页内容穿到标题栏下方被
    // GRADIENT_BLUR 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        if (!this.loaded) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Theme.primary(Theme.isDark()))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller }) {
          // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
          ListItem() {
            Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
          }
            ListItem() {
              // 参考截图的搜索框：透明底 + 灰描边胶囊，非实心底。
              Row({ space: 8 }) {
                Image($r('app.media.ic_tab_search_24'))
                  .width(18)
                  .height(18)
                  .fillColor(Theme.textSecondary(Theme.isDark()))
                TextInput({ placeholder: '搜索歌曲 / 歌手', text: this.query })
                  .fontSize(13)
                  .height(38)
                  .padding({ left: 0, right: 0 })
                  .backgroundColor(Color.Transparent)
                  .onChange((value: string) => {
                    this.query = value;
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 4 })
              .border({
                width: 1,
                color: Theme.withAlpha(Theme.textSecondary(Theme.isDark()), 0x40),
                radius: 24
              })
              .margin({ left: 14, right: 14, top: 4, bottom: 4 })
            }

            if (this.songs.length > 0) {
              // 参考截图：白色圆形播放钮 + 文字行（非彩色胶囊按钮）。
              ListItem() {
                Row({ space: 10 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    Column()
                      .width(32)
                      .height(32)
                      .borderRadius(16)
                      .backgroundColor('#FFFFFF')
                    Image($r('app.media.round_play_arrow_24'))
                      .width(18)
                      .height(18)
                      .fillColor('#111111')
                  }
                  Text(`播放全部 (${this.visibleSongs().length})`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 4, bottom: 8 })
                .accessibilityText('播放全部历史歌曲')
                .onClick(() => this.playAll())
                .clickEffect({ level: ClickEffectLevel.LIGHT })
              }
            }

            if (this.songs.length === 0) {
              ListItem() {
                Column() {
                  EmptyState({
                    icon: '⏱',
                    title: '暂无播放历史',
                    subtitle: '去「探索」找点歌吧'
                  })
                }
                .padding({ top: 48 })
                .width('100%')
              }
            } else if (this.visibleSongs().length === 0) {
              ListItem() {
                Column() {
                  EmptyState({
                    icon: '🔍',
                    title: '没有匹配的歌曲',
                    subtitle: '换个关键词试试'
                  })
                }
                .padding({ top: 48 })
                .width('100%')
              }
            } else {
              ForEach(this.visibleSongs(), (song: SongItem, index: number) => {
                ListItem() {
                  SongRow({
                    songJson: song.toJson(),
                    index: index,
                    playCount: this.playCountOf(song),
                    transparentBg: true,
                    onPlay: () => this.play(index)
                  })
                }
              }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}_${song.addedAt}`)
              // 尾部让位：列表延伸进底部手势条区后，末条记录滚过渐变遮罩仍可停稳。
              ListItem() {
                Column().height(this.bottomLift + SUB_BOTTOM_CLEARANCE_VP)
              }
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .width('100%')
          // 官方开发实例：穿透到标题栏下方的列表项预加载，避免滚入区域闪空。
          .cachedCount(3, true)
          .clip(false)
        }

        SubPageBottomFade()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.schemeBg(Theme.isDark()))
    }
    .titleBar(subPageTitleBar('播放历史', this.titleMenu()))
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
