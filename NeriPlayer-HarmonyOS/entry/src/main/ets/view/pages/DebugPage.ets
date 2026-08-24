import { promptAction } from '@kit.ArkUI';
import { NeteaseApi } from '../../network/NeteaseApi';
import { BiliApi } from '../../network/BiliApi';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import { YtmStreamResolver } from '../../network/ytm/YtmStreamResolver';
import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { SettingsRepository } from '../../data/SettingsRepository';
import { HttpClient } from '../../network/HttpClient';
import { UsageRepository } from '../../data/UsageRepository';
import { SearchHistoryRepository } from '../../data/SearchHistoryRepository';
import { DownloadEngine } from '../../download/DownloadEngine';
import { DownloadStorage } from '../../download/DownloadStorage';
import { DownloadStatus } from '../../download/DownloadModels';
import { DiagnosticsStore } from '../../app/diagnostics/DiagnosticsStore';
import { formatRecordLine } from '../../app/diagnostics/DiagnosticsModels';
import { Logger } from '../../app/Logger';
import { Router } from '../Router';
import { Theme } from '../Theme';

@Component
export struct DebugPage {
  @State result: string = '';
  @State proxyHost: string = '';
  @State proxyPort: string = '';

  aboutToAppear(): void {
    this.proxyHost = SettingsRepository.getString(SettingsRepository.KEY_PROXY_HOST, '');
    const port = SettingsRepository.getNumber(SettingsRepository.KEY_PROXY_PORT, 0);
    this.proxyPort = port > 0 ? `${port}` : '';
  }

  private applyProxy(): void {
    const host = this.proxyHost.trim();
    const port = Number(this.proxyPort.trim());
    const valid = host.length > 0 && Number.isInteger(port) && port > 0 && port <= 65535;
    if (!valid) {
      this.result = '代理配置无效：需要主机名与 1-65535 的端口';
      return;
    }
    SettingsRepository.setString(SettingsRepository.KEY_PROXY_HOST, host);
    SettingsRepository.setNumber(SettingsRepository.KEY_PROXY_PORT, port);
    HttpClient.applyConfiguredProxy();
    this.result = `已应用 HTTP 代理 ${host}:${port}（下次请求与媒体拉流生效）`;
  }

  private clearProxy(): void {
    SettingsRepository.setString(SettingsRepository.KEY_PROXY_HOST, '');
    SettingsRepository.setNumber(SettingsRepository.KEY_PROXY_PORT, 0);
    HttpClient.applyConfiguredProxy();
    this.proxyHost = '';
    this.proxyPort = '';
    this.result = '已清除 HTTP 代理（直连）';
  }

  private async testNetease(): Promise<void> {
    try {
      const items = await NeteaseApi.search('周杰伦', 5);
      this.result = `网易云搜索 OK：${items.length} 条结果`;
    } catch (error) {
      const e = error as Error;
      this.result = `网易云搜索失败：${e.message}`;
    }
  }

  private async testBili(): Promise<void> {
    try {
      const items = await BiliApi.search('周杰伦', 5);
      this.result = `Bilibili 搜索 OK：${items.length} 条结果`;
    } catch (error) {
      const e = error as Error;
      this.result = `Bilibili 搜索失败：${e.message}`;
    }
  }

  private async testYoutube(): Promise<void> {
    try {
      const items = await YouTubeMusicApi.search('周杰伦', 5);
      this.result = `YouTube Music 搜索 OK：${items.length} 条结果`;
    } catch (error) {
      const e = error as Error;
      this.result = `YouTube Music 搜索失败：${e.message}`;
    }
  }

  /**
   * M6.5 stream probe: search -> IOS direct resolution. Only reports the
   * videoId, URL length and host verdict — googlevideo URLs carry auth
   * tokens and must never be rendered.
   */
  private async probeYtmStream(): Promise<void> {
    try {
      const items = await YouTubeMusicApi.search('Linkin Park Numb', 5);
      if (items.length === 0) {
        this.result = 'YTM 取流探针：搜索返回 0 条结果';
        return;
      }
      const videoId = items[0].audioId;
      const url = await YtmStreamResolver.resolveStreamUrl(videoId, 'high');
      const hostOk = url.includes('googlevideo.com');
      this.result = `YTM 取流探针：搜索 ${items.length} 条；${videoId} 取流 OK`
        + `（直链 ${url.length} 字符，googlevideo=${hostOk}）`
        + `${hostOk ? '' : '，域名异常'}`;
    } catch (error) {
      const e = error as Error;
      this.result = `YTM 取流探针失败：${e.message}`;
    }
  }

  private async showStats(): Promise<void> {
    const totalPlays = await PlaybackStatsRepository.getTotalPlayCount();
    const totalListenMs = await PlaybackStatsRepository.getTotalListenMs();
    const hours = Math.floor(totalListenMs / 3600000);
    const minutes = Math.floor((totalListenMs % 3600000) / 60000);
    this.result = `播放 ${totalPlays} 次，累计收听 ${hours} 小时 ${minutes} 分钟`;
  }

  private async clearUsage(): Promise<void> {
    await UsageRepository.clear();
    this.result = '已清空「继续收听」记录';
  }

  private async clearSearchHistory(): Promise<void> {
    await SearchHistoryRepository.clear();
    this.result = '已清空搜索历史';
  }

  private clearDownloads(): void {
    DownloadEngine.clearAllTasks();
    this.result = '已清空下载任务（已下载文件保留）';
  }

  private async probeDownloads(): Promise<void> {
    const tasks = DownloadEngine.getTasks();
    const catalog = await DownloadStorage.getCatalog();
    let catalogBytes = 0;
    for (const entry of catalog) {
      catalogBytes += DownloadStorage.fileSize(entry.audioPath);
    }
    const byStatus = (status: DownloadStatus): number =>
      tasks.filter((task) => task.status === status).length;
    this.result = `下载探针：任务 ${tasks.length}（排队 ${byStatus(DownloadStatus.QUEUED)}`
      + ` / 传输 ${byStatus(DownloadStatus.DOWNLOADING)}`
      + ` / 等网 ${byStatus(DownloadStatus.WAITING_NETWORK)}`
      + ` / 完成 ${byStatus(DownloadStatus.COMPLETED)}`
      + ` / 失败 ${byStatus(DownloadStatus.FAILED)}`
      + ` / 取消 ${byStatus(DownloadStatus.CANCELLED)}）`
      + `；编目 ${catalog.length} 首 ${(catalogBytes / 1024 / 1024).toFixed(1)} MB`
      + `；暂存文件 ${DownloadStorage.stagingFileCount()} 个`;
  }

  private simulateCrash(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, true);
    promptAction.openToast({ message: '已模拟崩溃标记，重启后进入安全模式' });
  }

  private async probeDiagnostics(): Promise<void> {
    try {
      const records = await DiagnosticsStore.listRecords();
      if (records.length === 0) {
        this.result = '诊断探针：无记录（无故障历史或未发生崩溃）';
        return;
      }
      const lines = records.map((record): string => formatRecordLine(record));
      this.result = `诊断探针：${records.length} 条记录\n${lines.join('\n')}`;
    } catch (error) {
      this.result = `诊断探针失败：${(error as Error).message}`;
    }
  }

  private async exportDiagnostics(): Promise<void> {
    try {
      const report = await DiagnosticsStore.buildExportReport(Logger.recentLogLines(), Date.now());
      const message = await DiagnosticsStore.exportViaPicker(report);
      this.result = message;
    } catch (error) {
      this.result = `诊断导出失败：${(error as Error).message}`;
    }
  }

  private async clearDiagnostics(): Promise<void> {
    await DiagnosticsStore.clearAll();
    this.result = '已清空诊断记录';
  }

  private confirmRealCrash(): void {
    this.getUIContext().showAlertDialog({
      title: '触发真实 JS 崩溃？',
      message: '应用进程将立即崩溃退出。下次启动应进入安全模式并自动记录 JSCRASH 诊断（M9.2 验证路径）。',
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '崩溃',
        fontColor: '#FF5252',
        action: (): void => {
          // Deliberately uncaught: exercises the JSCRASH -> HiAppEvent ->
          // DiagnosticsStore -> SafeMode chain on the next launch.
          throw new Error('NeriPlayer debug crash (M9.2 diagnostics probe)');
        }
      }
    });
  }

  @Builder
  testButton(label: string, action: () => void) {
    Button(label)
      .width('100%')
      .height(44)
      .backgroundColor(Theme.surface(Theme.isDark()))
      .fontColor(Theme.textPrimary(Theme.isDark()))
      .margin({ bottom: 8 })
      .onClick(() => action())
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('‹')
          .width(40)
          .height(40)
          // '‹' is punctuation to a screen reader; name the action.
          .accessibilityText('返回')
          .type(ButtonType.Circle)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(Theme.isDark()))
          .fontSize(22)
          .onClick(() => Router.pop())
        Text('调试')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 6 }) {
          this.testButton('网易云 API 测试', () => this.testNetease())
          this.testButton('Bilibili API 测试', () => this.testBili())
          this.testButton('YouTube Music API 测试', () => this.testYoutube())
          this.testButton('YTM 取流探针', () => this.probeYtmStream())
          this.testButton('播放统计', () => this.showStats())
          this.testButton('清空继续收听', () => this.clearUsage())
          this.testButton('清空搜索历史', () => this.clearSearchHistory())
          this.testButton('清空下载任务', () => this.clearDownloads())
          this.testButton('下载管线探针', () => this.probeDownloads())
          this.testButton('诊断记录探针', () => this.probeDiagnostics())
          this.testButton('导出诊断报告', () => this.exportDiagnostics())
          this.testButton('清空诊断记录', () => this.clearDiagnostics())
          this.testButton('触发真实 JS 崩溃', () => this.confirmRealCrash())
          this.testButton('模拟崩溃 → 安全模式', () => this.simulateCrash())

          Text('HTTP 代理（模拟器填宿主机 10.0.2.2:7897；同时用于接口请求与媒体拉流）')
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .width('100%')
          TextInput({ placeholder: '代理主机（如 10.0.2.2）', text: this.proxyHost })
            .height(40)
            .fontSize(13)
            .onChange((value: string) => {
              this.proxyHost = value;
            })
          TextInput({ placeholder: '代理端口（如 7897）', text: this.proxyPort })
            .height(40)
            .fontSize(13)
            .onChange((value: string) => {
              this.proxyPort = value;
            })
          Row({ space: 10 }) {
            Button('应用代理')
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Theme.primary(Theme.isDark()))
              .onClick(() => this.applyProxy())
            Button('清除')
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Theme.surface(Theme.isDark()))
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .onClick(() => this.clearProxy())
          }
          .width('100%')
          .margin({ bottom: 8 })

          Text('USB 独占播放按 M9.1 spike 结论不移植（USB DAC 走系统音频路径，见 docs/USB_M91_SPIKE.md）；YTM 完整播放待 D2 决策')
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
            .width('100%')
            .padding(12)

          Text(this.result)
            .fontSize(13)
            .fontColor(Theme.primary(Theme.isDark()))
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.surface(Theme.isDark()))
            .borderRadius(12)
        }
        .padding({ left: 16, right: 16 })
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
