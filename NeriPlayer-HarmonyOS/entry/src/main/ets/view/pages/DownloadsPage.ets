import { DownloadEngine, DownloadEngineListener } from '../../download/DownloadEngine';
import { DownloadStatus, DownloadTask } from '../../download/DownloadModels';
import { DownloadStorage } from '../../download/DownloadStorage';
import { PlayerManager } from '../../player/PlayerManager';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { stableKeyOf } from '../../model/SongIdentity';
import { Theme } from '../Theme';
import { EmptyState } from '../components/Ui';
import { Router } from '../Router';

class DownloadsListener implements DownloadEngineListener {
  private page: WeakRef<DownloadsPage> | null = null;

  attach(page: DownloadsPage): void {
    this.page = new WeakRef<DownloadsPage>(page);
  }

  onTasksChanged(): void {
    const target = this.page !== null ? this.page.deref() : undefined;
    if (target !== undefined) {
      target.tasks = DownloadEngine.getTasks().slice();
    }
  }
}

@Component
export struct DownloadsPage {
  @State tasks: DownloadTask[] = [];
  private listener: DownloadsListener = new DownloadsListener();

  aboutToAppear(): void {
    this.listener.attach(this);
    DownloadEngine.addListener(this.listener);
    this.tasks = DownloadEngine.getTasks().slice();
  }

  private statusLabel(task: DownloadTask): string {
    switch (task.status) {
      case DownloadStatus.QUEUED:
        return '排队中';
      case DownloadStatus.DOWNLOADING:
        return task.progress !== null && task.progress.percentage() >= 0
          ? `下载中 ${task.progress.percentage()}%` : '下载中';
      case DownloadStatus.WAITING_NETWORK:
        return '等待网络';
      case DownloadStatus.COMPLETED:
        return '已完成';
      case DownloadStatus.FAILED:
        return '失败';
      default:
        return '已取消';
    }
  }

  private actionLabel(task: DownloadTask): string {
    if (task.status === DownloadStatus.QUEUED || task.status === DownloadStatus.DOWNLOADING) {
      return '取消';
    }
    if (task.status === DownloadStatus.WAITING_NETWORK || task.status === DownloadStatus.FAILED
      || task.status === DownloadStatus.CANCELLED) {
      return '重试';
    }
    return '播放';
  }

  private async onAction(task: DownloadTask): Promise<void> {
    const key = stableKeyOf(task.song);
    if (task.status === DownloadStatus.QUEUED || task.status === DownloadStatus.DOWNLOADING) {
      DownloadEngine.cancel(key);
      return;
    }
    if (task.status === DownloadStatus.COMPLETED) {
      // Play the committed local file from the download catalog.
      const entry = await DownloadStorage.findCatalogEntry(task.song);
      if (entry !== null && entry.audioPath.length > 0) {
        const local = SongItem.fromJson(task.song.toJson());
        local.platform = MusicPlatform.LOCAL;
        local.localFilePath = entry.audioPath;
        PlayerManager.playPlaylist([local], 0);
      }
      return;
    }
    DownloadEngine.resume(key);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹')
          .width(38)
          .height(38)
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .fontSize(20)
          .onClick(() => Router.pop())
        Text('下载管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .layoutWeight(1)
        Button('清空记录')
          .height(32)
          .fontSize(13)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.danger(Theme.isDark()))
          .onClick(() => DownloadEngine.clearFinished())
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

      if (this.tasks.length === 0) {
        EmptyState({
          icon: '⤓',
          title: '暂无下载任务',
          subtitle: '在歌曲列表点「⋯ → 下载」添加任务'
        })
      } else {
        List() {
          ForEach(this.tasks, (task: DownloadTask) => {
            ListItem() {
              Row({ space: 12 }) {
                Stack() {
                  if (task.song.effectiveCoverUrl.length > 0) {
                    Image(task.song.effectiveCoverUrl)
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
                  if (task.status === DownloadStatus.COMPLETED) {
                    Text('✓')
                      .fontSize(12)
                      .fontColor('#FFFFFF')
                      .width(20)
                      .height(20)
                      .textAlign(TextAlign.Center)
                      .backgroundColor(Theme.success(Theme.isDark()))
                      .borderRadius(10)
                      .position({ x: '70%', y: '2%' })
                  }
                }

                Column({ space: 4 }) {
                  Text(task.song.displayName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.statusLabel(task))
                    .fontSize(11)
                    .fontColor(task.status === DownloadStatus.FAILED
                      ? Theme.danger(Theme.isDark())
                      : (task.status === DownloadStatus.COMPLETED
                        ? Theme.success(Theme.isDark())
                        : Theme.textSecondary(Theme.isDark())))
                  if (task.status === DownloadStatus.DOWNLOADING && task.progress !== null
                    && task.progress.percentage() >= 0) {
                    Progress({ value: task.progress.percentage(), total: 100, type: ProgressType.Linear })
                      .height(4)
                      .width('100%')
                      .color(Theme.primary(Theme.isDark()))
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button(this.actionLabel(task))
                  .height(30)
                  .fontSize(12)
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .onClick(() => {
                    this.onAction(task);
                  })
              }
              .width('100%')
              .padding(10)
              .backgroundColor(Theme.surface(Theme.isDark()))
              .borderRadius(Theme.cardRadius())
            }
          }, (task: DownloadTask) => `${stableKeyOf(task.song)}:${task.attemptId}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
