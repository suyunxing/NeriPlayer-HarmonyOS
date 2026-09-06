import { pasteboard } from '@kit.BasicServicesKit';
import { SongItem } from '../../model/SongItem';
import { ShareLinks } from '../../util/ShareLinks';
import { Theme } from '../Theme';
import { BottomSheetPanel } from './BottomSheetPanel';

/** 「分享」面板：复制歌曲文本 / 来源链接，或转交已有的歌词卡片分享。 */
@Component
export struct SongShareSheet {
  songJson: string = '';
  onClose: () => void = () => {};
  onOpenLyricCard: () => void = () => {};

  private song(): SongItem {
    return this.songJson.length > 0 ? SongItem.fromJson(this.songJson) : new SongItem();
  }

  private copyToClipboard(text: string, toast: string): void {
    const payload = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(payload).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: toast, duration: 2000 });
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 2000 });
    });
  }

  @Builder
  actionRow(title: string, subtitle: string, onTap: () => void) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(15)
        .fontColor(Theme.textPrimary(Theme.isDark()))
        .width('100%')
      Text(subtitle)
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(12)
    .onClick(() => onTap())
  }

  build() {
    BottomSheetPanel({
      title: '分享',
      onClose: () => this.onClose()
    }) {
      Column() {
        this.actionRow('复制歌曲信息', ShareLinks.songText(this.song()), () => {
          this.copyToClipboard(ShareLinks.songText(this.song()), '已复制歌曲信息');
        })
        if (ShareLinks.songLink(this.song()).length > 0) {
          Divider()
            .color(Theme.divider(Theme.isDark()))
            .width('100%')
          this.actionRow('复制来源链接', ShareLinks.songLink(this.song()), () => {
            this.copyToClipboard(ShareLinks.songLink(this.song()), '已复制链接');
          })
        }
        Divider()
          .color(Theme.divider(Theme.isDark()))
          .width('100%')
        this.actionRow('分享歌词卡片', '生成当前歌曲的歌词分享图', () => {
          this.onClose();
          this.onOpenLyricCard();
        })
      }
      .width('100%')
    }
  }
}
