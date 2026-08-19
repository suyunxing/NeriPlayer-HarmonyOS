import { Constants } from '../../app/Constants';

@Component
export struct LoadingPage {
  build() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_neriplayer'))
        .width(96)
        .height(96)
      Text(Constants.APP_NAME)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
      LoadingProgress()
        .width(48)
        .height(48)
        .color('#7C4DFF')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#121212')
  }
}
