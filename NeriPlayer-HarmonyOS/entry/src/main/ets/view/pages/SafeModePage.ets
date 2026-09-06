import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../Theme';
import { DiagnosticsStore } from '../../app/diagnostics/DiagnosticsStore';
import { formatRecordLine } from '../../app/diagnostics/DiagnosticsModels';
import { Logger } from '../../app/Logger';

@Component
export struct SafeModePage {
  onRestoreNormal: () => void = () => {};

  private async exportDiagnostics(): Promise<void> {
    try {
      const report = await DiagnosticsStore.buildExportReport(Logger.recentLogLines(), Date.now());
      const message = await DiagnosticsStore.exportViaPicker(report);
      promptAction.openToast({ message });
    } catch (error) {
      promptAction.openToast({ message: `导出失败：${(error as Error).message}` });
    }
  }

  private async copyDiagnosticsSummary(): Promise<void> {
    try {
      const records = await DiagnosticsStore.listRecords();
      if (records.length === 0) {
        promptAction.openToast({ message: '暂无诊断记录' });
        return;
      }
      const lines = records.map((record): string => formatRecordLine(record));
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      pasteboard.getSystemPasteboard().setData(pasteData);
      promptAction.openToast({ message: `已复制 ${records.length} 条诊断摘要` });
    } catch (error) {
      promptAction.openToast({ message: `复制失败：${(error as Error).message}` });
    }
  }

  build() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_warning_24'))
        .width(64)
        .height(64)
        .fillColor(Theme.warning(Theme.isDark()))
        .margin({ top: 90 })
      Text('安全模式')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text('上次启动出现异常，已进入安全模式。\n播放与本地功能保持可用，网络与扩展功能已禁用。')
        .fontSize(14)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .padding({ left: 30, right: 30 })

      Column({ space: 1 }) {
        SafeActionRow({
          title: '导出诊断报告',
          subtitle: '崩溃/冻结记录 + 详情 + 最近日志，保存为文本文件',
          onTap: () => {
            this.exportDiagnostics();
          }
        })
        SafeActionRow({
          title: '复制诊断摘要',
          subtitle: '将最近故障记录摘要复制到剪贴板',
          onTap: () => {
            this.copyDiagnosticsSummary();
          }
        })
        SafeActionRow({
          title: '恢复正常模式',
          subtitle: '清除崩溃标记并重启流程',
          onTap: () => this.onRestoreNormal()
        })
      }
      .width('88%')
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius(Theme.cardRadius())
      .clip(true)
      .margin({ top: 20 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}

@Component
struct SafeActionRow {
  title: string = '';
  subtitle: string = '';
  onTap: () => void = () => {};

  build() {
    Column({ space: 2 }) {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary(Theme.isDark()))
      Text(this.subtitle)
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onTap())
  }
}
