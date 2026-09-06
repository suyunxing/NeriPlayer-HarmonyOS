import { Theme } from '../Theme';

@Builder
function emptyContent() {
}

/**
 * Shared bottom sheet shell for the now-playing action panels: dim scrim +
 * bottom glass panel with a standard title row. Tapping the scrim closes the
 * sheet; taps inside the panel never do (the empty onClick keeps the gesture
 * from reaching the scrim, so editing text cannot dismiss the sheet).
 */
@Component
export struct BottomSheetPanel {
  @Prop title: string = '';
  onClose: () => void = () => {};
  @BuilderParam content: () => void = emptyContent;
  @StorageProp('np.glass_effect') glassEffect: boolean = true;

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => this.onClose())
      Column() {
        Row() {
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(Theme.primary(Theme.isDark()))
            .padding({ left: 8, right: 4, top: 4, bottom: 4 })
            .accessibilityText(`关闭${this.title}`)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ bottom: 10 })

        this.content()
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.glassEffect ? Theme.surfaceGlass(Theme.isDark()) : Theme.surface(Theme.isDark()))
      .backgroundBlurStyle(this.glassEffect ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .borderRadius({ topLeft: 22, topRight: 22 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.scrim(Theme.isDark()))
  }
}
