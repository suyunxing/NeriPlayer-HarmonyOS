import { Theme } from '../Theme';

@Component
export struct OnboardingPage {
  onDone: () => void = () => {};
  @State pageIndex: number = 0;

  private pages(): string[][] {
    return [
      ['欢迎使用 NeriPlayer', '多源在线播放：网易云 / Bilibili / YouTube Music；本地音乐、歌词、歌单与统计。'],
      ['本地优先', '播放缓存、下载、歌单、历史、设置与授权信息默认保存在设备本地，离线时本地内容仍可继续使用。'],
      ['多源探索', '搜索你喜欢的歌曲和歌手，收藏到歌单，享受同步歌词与播放统计。']
    ];
  }

  build() {
    Column() {
      Swiper() {
        ForEach(this.pages(), (page: string[]) => {
          Column({ space: 18 }) {
            Text('♫')
              .fontSize(72)
              .fontColor(Theme.primary(Theme.isDark()))
              .margin({ top: 80 })
            Text(page[0])
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .textAlign(TextAlign.Center)
            Text(page[1])
              .fontSize(15)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .textAlign(TextAlign.Center)
              .lineHeight(22)
              .padding({ left: 34, right: 34 })
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Center)
        }, (page: string[]) => page[0])
      }
      .width('100%')
      .layoutWeight(1)
      .index(this.pageIndex)
      .onChange((index: number) => {
        this.pageIndex = index;
      })
      .indicator(true)

      Button(this.pageIndex >= 2 ? '开始使用' : '下一步')
        .width('78%')
        .height(48)
        .fontSize(16)
        .fontColor(Theme.onPrimary(Theme.isDark()))
        .backgroundColor(Theme.primary(Theme.isDark()))
        .borderRadius(24)
        .margin({ bottom: 42 })
        .onClick(() => {
          if (this.pageIndex >= 2) {
            this.onDone();
          } else {
            this.pageIndex += 1;
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
