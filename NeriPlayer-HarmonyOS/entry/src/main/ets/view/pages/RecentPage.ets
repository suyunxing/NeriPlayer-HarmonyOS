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
  @State songs: SongItem[] = [];
  @State playCounts: Record<string, number> = {};
  @State loaded: boolean = false;
  @State query: string = '';
  @State sortByCount: boolean = false;
  @State busy: boolean = false;

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

  @Builder
  moreMenuBuilder() {
    Menu() {
      MenuItem({ content: '使用说明' })
        .onClick(() => this.showUsageNote())
      MenuItem({ content: '导出到本机' })
        .onClick(() => {
          this.exportHistory();
        })
      MenuItem({ content: '从本机导入' })
        .onClick(() => {
          this.importHistory();
        })
      MenuItem({ content: '清除所有记录' })
        .onClick(() => this.confirmClearAll())
    }
  }

  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
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
        Text('播放历史')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
        Button(this.sortByCount ? '按次数' : '按时间')
          .height(32)
          .fontSize(12)
          .padding({ left: 12, right: 12 })
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .accessibilityText(this.sortByCount ? '按播放次数排序，点击改为按时间' : '按时间排序，点击改为按播放次数')
          .onClick(() => this.toggleSort())
        Button() {
          Image($r('app.media.ic_grid_dots_24'))
            .width(22)
            .height(22)
            .fillColor(Theme.textSecondary(Theme.isDark()))
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .accessibilityText('更多操作')
        .bindMenu(this.moreMenuBuilder)
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

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
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius(19)
      .margin({ left: 14, right: 14, bottom: 8 })

      if (this.loaded && this.songs.length > 0) {
        Button() {
          Row({ space: 6 }) {
            Image($r('app.media.round_play_arrow_24'))
              .width(18)
              .height(18)
              .fillColor(Theme.onPrimary(Theme.isDark()))
            Text(`播放全部 (${this.visibleSongs().length})`)
              .fontSize(13)
              .fontColor(Theme.onPrimary(Theme.isDark()))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(Theme.primary(Theme.isDark()))
        .borderRadius(18)
        .margin({ left: 14, bottom: 8 })
        .accessibilityText('播放全部历史歌曲')
        .onClick(() => this.playAll())
      }

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
      } else if (this.songs.length === 0) {
        EmptyState({
          icon: '⏱',
          title: '暂无播放历史',
          subtitle: '去「探索」找点歌吧'
        })
      } else if (this.visibleSongs().length === 0) {
        EmptyState({
          icon: '🔍',
          title: '没有匹配的歌曲',
          subtitle: '换个关键词试试'
        })
      } else {
        List() {
          ForEach(this.visibleSongs(), (song: SongItem, index: number) => {
            ListItem() {
              SongRow({
                songJson: song.toJson(),
                index: index,
                showPlatform: true,
                playCount: this.playCountOf(song),
                onPlay: () => this.play(index)
              })
            }
          }, (song: SongItem) => `${song.platform}_${song.audioId}_${song.id}_${song.addedAt}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.schemeBg(Theme.isDark()))
  }
}
