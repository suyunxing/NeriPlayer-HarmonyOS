@Component
export struct DisclaimerPage {
  onAgree: () => void = () => {};
  @State countdown: number = 5;

  aboutToAppear(): void {
    this.tick();
  }

  private tick(): void {
    const timer = setInterval(() => {
      if (this.countdown > 0) {
        this.countdown -= 1;
      } else {
        clearInterval(timer);
      }
    }, 1000);
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text('免责声明 / Disclaimer')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
          Text('本项目仅供学习与研究使用，请勿用于任何非法用途。')
            .fontSize(15)
          Text('本项目不提供公共云端曲库或媒体分发服务。在线音频能力依赖您在第三方平台的账号授权；VIP 或受限内容仍遵循原平台规则。')
            .fontSize(14)
            .fontColor('#9E9E9E')
          Text('第三方平台日志与风控策略由对应平台按其自身隐私政策处理。请合理配置代理规则。')
            .fontSize(14)
            .fontColor('#9E9E9E')
        }
        .padding(20)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Button(this.countdown > 0 ? `请阅读免责声明 (${this.countdown})` : '我已阅读并同意')
        .width('90%')
        .height(48)
        .enabled(this.countdown === 0)
        .backgroundColor(this.countdown === 0 ? '#7C4DFF' : '#5A5A5A')
        .fontColor('#FFFFFF')
        .margin({ bottom: 32 })
        .onClick(() => {
          this.onAgree();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121212')
    .justifyContent(FlexAlign.End)
  }
}
