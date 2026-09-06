import { Theme } from '../Theme';
import { BAND_BUTTON_VP, BAND_TEXT_VP, BP_LG, BP_MD } from '../../util/Breakpoint';

@Component
export struct OnboardingPage {
  onDone: () => void = () => {};
  @State pageIndex: number = 0;
  /** 由 util/WindowMetrics.ets 发布，决定引导内容是否竖向居中。 */
  @StorageProp('ui.breakpoint') breakpoint: string = 'sm';

  private wideLayout(): boolean {
    return this.breakpoint === BP_MD || this.breakpoint === BP_LG;
  }

  private pages(): string[][] {
    return [
      ['欢迎使用 NeriPlayer', '多源在线播放：网易云 / Bilibili / YouTube Music；本地音乐、歌词、歌单与统计。'],
      ['本地优先', '播放缓存、下载、歌单、历史、设置与授权信息默认保存在设备本地，离线时本地内容仍可继续使用。'],
      ['多源探索', '搜索你喜欢的歌曲和歌手，收藏到歌单，享受同步歌词与播放统计。']
    ];
  }

  build() {
    // 600vp 正文栏宽 + 居中。Swiper 靠 layoutWeight(1) 撑满剩余高度，所以约束
    // 手写在这里而不套 ContentBand（后者高度按内容自适应，会把 Swiper 压塌）。
    Row() {
    Column() {
      Swiper() {
        ForEach(this.pages(), (page: string[]) => {
          Column({ space: 18 }) {
            Image($r('app.media.ic_neriplayer'))
              .width(88)
              .height(88)
              // 窄屏保持原来的 80vp 顶部留白；宽屏改为整块竖向居中，固定留白
              // 会把内容顶到上半屏。
              .margin({ top: this.wideLayout() ? 0 : 80 })
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
          .justifyContent(this.wideLayout() ? FlexAlign.Center : FlexAlign.Start)
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
        .constraintSize({ maxWidth: BAND_BUTTON_VP })
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
    .constraintSize({ maxWidth: BAND_TEXT_VP })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.background(Theme.isDark()))
  }
}
