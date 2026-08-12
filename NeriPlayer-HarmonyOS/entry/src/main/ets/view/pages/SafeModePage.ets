import { promptAction } from '@kit.ArkUI';
import { Theme } from '../Theme';

@Component
export struct SafeModePage {
  onRestoreNormal: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text('⚠')
        .fontSize(64)
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
          title: '导出日志',
          subtitle: '日志导出将在 Debug 页面完善',
          onTap: () => {
            promptAction.openToast({ message: '日志导出将在 Debug 页面完善' });
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
