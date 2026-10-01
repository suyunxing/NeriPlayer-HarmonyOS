// SPDX-License-Identifier: GPL-3.0

import { DownloadEngine, DownloadEngineListener } from '../../download/DownloadEngine';
import { DownloadStatus, isDownloadTaskClearable } from '../../download/DownloadModels';
import { buildDownloadRows, DownloadRow } from '../../download/DownloadRow';
import { DownloadStorage } from '../../download/DownloadStorage';
import { PlayerManager } from '../../player/PlayerManager';
import { SongItem } from '../../model/SongItem';
import { Theme } from '../Theme';
import { AccentScheme } from '../theme/AccentScheme';
import { EmptyState } from '../components/Ui';
import { coverThumbnailUrl } from '../../util/CoverUrls';
import { Router } from '../Router';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageBottomFade, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP, SUB_BOTTOM_CLEARANCE_VP } from '../components/HdsSubPage';

class DownloadsListener implements DownloadEngineListener {
  private page: WeakRef<DownloadsPage> | null = null;

  attach(page: DownloadsPage): void {
    this.page = new WeakRef<DownloadsPage>(page);
  }

  onTasksChanged(): void {
    const target = this.page !== null ? this.page.deref() : undefined;
    if (target !== undefined) {
      target.refreshRows();
    }
  }

  /** 完成提示由 MainShell 统一弹出，本页只随 onTasksChanged 刷新列表。 */
  onDownloadCompleted(song: SongItem, fromCache: boolean): void {
  }
}

@Component
export struct DownloadsPage {
  /**
   * S5: 订阅封面配色。Theme.*() 读 AppStorage 是无跟踪调用（M7.4），换歌后
   * 坐在本页的组件不会重建；有了这个成员并在 build 里经 schemeBg() 直读，
   * scheme 一发布本页就随新配色重染。
   */
  @StorageProp('player.coverScheme') coverScheme: AccentScheme = AccentScheme.neutralFallback();
  @StorageProp('ui.bottomLiftVp') bottomLift: number = Theme.bottomBarLift();
  /** 状态栏避让（util/WindowMetrics.ets 发布）；内容根从 y=0 起，让位 = topInset + 56。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  @State rows: DownloadRow[] = [];
  private listener: DownloadsListener = new DownloadsListener();
  /** 供 HdsNavDestination.bindToScrollable 绑定的任务列表控制器。 */
  private scroller: Scroller = new Scroller();

  /** 标题栏菜单：清空已结束任务（原页内「清空记录」按钮迁入）。 */
  private titleMenu(): SubPageMenuEntry[] {
    return [{
      label: '清空记录',
      icon: $r('app.media.ic_delete_24'),
      action: () => DownloadEngine.clearFinished()
    }];
  }

  aboutToAppear(): void {
    this.listener.attach(this);
    DownloadEngine.addListener(this.listener);
    this.refreshRows();
  }

  /** 任务记录与已下载目录合并渲染：清空记录后已下载条目仍可见可删。 */
  refreshRows(): void {
    const tasks = DownloadEngine.getTasks().slice();
    DownloadStorage.getCatalog().then((catalog) => {
      this.rows = buildDownloadRows(tasks, catalog);
    }).catch(() => {
      this.rows = buildDownloadRows(tasks, []);
    });
  }

  private statusLabel(row: DownloadRow): string {
    switch (row.status) {
      case DownloadStatus.QUEUED:
        return '排队中';
      case DownloadStatus.DOWNLOADING:
        return row.progress !== null && row.progress.percentage() >= 0
          ? `下载中 ${row.progress.percentage()}%` : '下载中';
      case DownloadStatus.WAITING_NETWORK:
        return '等待网络';
      case DownloadStatus.COMPLETED:
        // buildDownloadRows drops COMPLETED rows without a catalog entry.
        return '已下载';
      case DownloadStatus.FAILED:
        return '失败';
      default:
        return '已取消';
    }
  }

  private actionLabel(row: DownloadRow): string {
    if (row.status === DownloadStatus.QUEUED || row.status === DownloadStatus.DOWNLOADING) {
      return '取消';
    }
    if (row.status === DownloadStatus.WAITING_NETWORK || row.status === DownloadStatus.FAILED
      || row.status === DownloadStatus.CANCELLED) {
      return '重试';
    }
    return '播放';
  }

  /** Terminal rows and committed downloads can be deleted outright. */
  private canDelete(row: DownloadRow): boolean {
    return row.entry !== null || isDownloadTaskClearable(row.status);
  }

  private async onAction(row: DownloadRow): Promise<void> {
    if (row.status === DownloadStatus.QUEUED || row.status === DownloadStatus.DOWNLOADING) {
      DownloadEngine.cancel(row.stableKey);
      return;
    }
    if (row.status === DownloadStatus.COMPLETED) {
      // Play the catalog-backed song with its original platform identity so
      // resolution prefers the local file and still falls back to streaming
      // when the copy was removed (self-heal or delete).
      PlayerManager.playPlaylist([SongItem.fromJson(row.song.toJson())], 0);
      return;
    }
    DownloadEngine.resume(row.stableKey);
  }

  private async onDelete(row: DownloadRow): Promise<void> {
    await DownloadEngine.deleteDownload(row.stableKey);
    this.refreshRows();
  }

  /** build 里直读被跟踪成员注册依赖；颜色本身仍由 Theme 统一决策。 */
  private schemeBg(dark: boolean): string {
    const hasScheme = this.coverScheme.light.background.length > 0;
    return hasScheme ? Theme.background(dark) : Theme.background(dark);
  }

  build() {
    // 标题栏（返回 + 标题 + 清空记录菜单）由 HdsNavDestination 承载，滚动时
    // 任务列表穿到标题栏下方被 GRADIENT_BLUR 渐变模糊覆盖（同首页外壳）。
    HdsNavDestination() {
      Stack() {
        Column() {
          if (this.rows.length === 0) {
            Column() {
              EmptyState({
                icon: '⤓',
                title: '暂无下载内容',
                subtitle: '在歌曲列表点「⋯ → 下载」，下载的歌曲会显示在这里'
              })
            }
            .padding({ top: this.topInset + SUB_TITLEBAR_SPACE_VP })
            .width('100%')
          } else {
            List({ scroller: this.scroller }) {
            // 顶部让位标题栏：让位量随内容滚走（同首页 Tab 页 padding top 56）。
            ListItem() {
              Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
            }
          ForEach(this.rows, (row: DownloadRow) => {
            ListItem() {
              Row({ space: 12 }) {
                Stack() {
                  if (row.song.effectiveCoverUrl.length > 0) {
                    Image(coverThumbnailUrl(row.song.effectiveCoverUrl, 200))
                      .autoResize(true)
                      .width(50)
                      .height(50)
                      .borderRadius(8)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Image($r('app.media.ic_music_note_24'))
                      .width(22)
                      .height(22)
                      .fillColor(Theme.primary(Theme.isDark()))
                      .margin({ left: 14, right: 14, top: 14, bottom: 14 })
                      .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                      .borderRadius(8)
                  }
                }

                Column({ space: 4 }) {
                  Text(row.song.displayName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.statusLabel(row))
                    .fontSize(11)
                    .fontColor(row.status === DownloadStatus.FAILED
                      ? Theme.danger(Theme.isDark())
                      : (row.status === DownloadStatus.COMPLETED
                        ? Theme.success(Theme.isDark())
                        : Theme.textSecondary(Theme.isDark())))
                  if (row.status === DownloadStatus.DOWNLOADING && row.progress !== null
                    && row.progress.percentage() >= 0) {
                    Progress({ value: row.progress.percentage(), total: 100, type: ProgressType.Linear })
                      .height(4)
                      .width('100%')
                      .color(Theme.primary(Theme.isDark()))
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (this.canDelete(row)) {
                  Button('删除')
                    .height(40)
                    .fontSize(12)
                    .backgroundColor(Color.Transparent)
                    .fontColor(Theme.danger(Theme.isDark()))
                    .onClick(() => {
                      this.onDelete(row);
                    })
                }
                Button(this.actionLabel(row))
                  .height(40)
                  .fontSize(12)
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .onClick(() => {
                    this.onAction(row);
                  })
              }
              .width('100%')
              .padding(10)
              .backgroundColor(Theme.surface(Theme.isDark()))
              .borderRadius(Theme.cardRadius())
            }
          }, (row: DownloadRow) => `${row.stableKey}:${row.attemptId}:${row.entry !== null ? 'f' : 't'}`)
              // 尾部让位：列表延伸进底部手势条区后，末条任务滚过渐变遮罩仍可停稳。
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
    .titleBar(subPageTitleBar('下载管理', this.titleMenu()))
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
