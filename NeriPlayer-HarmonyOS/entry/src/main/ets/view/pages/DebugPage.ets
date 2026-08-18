import { promptAction } from '@kit.ArkUI';
import { NeteaseApi } from '../../network/NeteaseApi';
import { BiliApi } from '../../network/BiliApi';
import { YouTubeMusicApi } from '../../network/YouTubeMusicApi';
import { PlaybackStatsRepository } from '../../data/PlaybackStatsRepository';
import { SettingsRepository } from '../../data/SettingsRepository';
import { UsageRepository } from '../../data/UsageRepository';
import { SearchHistoryRepository } from '../../data/SearchHistoryRepository';
import { DownloadsRepository } from '../../data/DownloadsRepository';
import { Router } from '../Router';
import { Theme } from '../Theme';

@Component
export struct DebugPage {
  @State result: string = '';

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

  private async clearDownloads(): Promise<void> {
    await DownloadsRepository.clearAll();
    this.result = '已清空下载任务';
  }

  private simulateCrash(): void {
    SettingsRepository.setBoolean(SettingsRepository.KEY_LAST_CRASH_DETECTED, true);
    promptAction.openToast({ message: '已模拟崩溃标记，重启后进入安全模式' });
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
          this.testButton('播放统计', () => this.showStats())
          this.testButton('清空继续收听', () => this.clearUsage())
          this.testButton('清空搜索历史', () => this.clearSearchHistory())
          this.testButton('清空下载任务', () => this.clearDownloads())
          this.testButton('模拟崩溃 → 安全模式', () => this.simulateCrash())

          Text('USB 独占播放 / 下载恢复 / 一起听 / 同步 仍为待移植模块，见 PORTING.md')
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
