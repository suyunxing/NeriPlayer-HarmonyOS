import { promptAction } from '@kit.ArkUI';
import { DownloadTask, DownloadStatus } from '../../model/DownloadTask';
import { DownloadsRepository } from '../../data/DownloadsRepository';
import { Theme } from '../Theme';
import { EmptyState } from '../components/Ui';
import { Router } from '../Router';

@Component
export struct DownloadsPage {
  @State tasks: DownloadTask[] = [];
  @State loaded: boolean = false;

  async aboutToAppear(): Promise<void> {
    await this.reload();
  }

  private async reload(): Promise<void> {
    this.tasks = await DownloadsRepository.loadAll();
    this.loaded = true;
  }

  private statusLabel(status: DownloadStatus): string {
    if (status === DownloadStatus.DOWNLOADING) {
      return '下载中';
    }
    if (status === DownloadStatus.COMPLETED) {
      return '已完成';
    }
    if (status === DownloadStatus.FAILED) {
      return '失败';
    }
    if (status === DownloadStatus.PAUSED) {
      return '已暂停';
    }
    return '等待中';
  }

  private async removeTask(id: string): Promise<void> {
    await DownloadsRepository.remove(id);
    await this.reload();
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
        Button('清空')
          .height(32)
          .fontSize(13)
          .backgroundColor(Theme.surface(Theme.isDark()))
          .fontColor(Theme.danger(Theme.isDark()))
          .onClick(async () => {
            await DownloadsRepository.clearAll();
            await this.reload();
            promptAction.openToast({ message: '已清空下载任务' });
          })
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

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
      } else if (this.tasks.length === 0) {
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
                    Text('♫')
                      .fontSize(18)
                      .width(50)
                      .height(50)
                      .textAlign(TextAlign.Center)
                      .fontColor(Theme.primary(Theme.isDark()))
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

                Column({ space: 3 }) {
                  Text(task.song.displayName)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(task.fileName)
                    .fontSize(11)
                    .fontColor(Theme.textDisabled(Theme.isDark()))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row({ space: 8 }) {
                    Text(this.statusLabel(task.status))
                      .fontSize(11)
                      .fontColor(task.status === DownloadStatus.FAILED
                        ? Theme.danger(Theme.isDark())
                        : (task.status === DownloadStatus.COMPLETED
                          ? Theme.success(Theme.isDark())
                          : Theme.textSecondary(Theme.isDark())))
                    if (task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PAUSED) {
                      Text(`${task.progressPercent}%`)
                        .fontSize(11)
                        .fontColor(Theme.textSecondary(Theme.isDark()))
                    }
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('删除')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
                  .fontColor(Theme.danger(Theme.isDark()))
                  .onClick(() => this.removeTask(task.id))
              }
              .width('100%')
              .padding(10)
              .backgroundColor(Theme.surface(Theme.isDark()))
              .borderRadius(Theme.cardRadius())
            }
          }, (task: DownloadTask) => task.id)
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
