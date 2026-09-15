// SPDX-License-Identifier: GPL-3.0

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Logger } from '../../app/Logger';
import { LyricLine } from '../../model/LyricLine';
import { DynamicTheme } from '../theme/DynamicTheme';
import { PaletteSwatch } from '../theme/Palette';
import { Theme } from '../Theme';

/**
 * Lyric share card sheet, the HarmonyOS counterpart of Android
 * LyricShareSheet (scaled down): multi-select lyric lines, render a square
 * brand card on a Canvas (seed-color gradient + app name + selected lines +
 * song credits), then either copy the text or export the canvas as PNG into
 * the system gallery. Saving uses the SaveButton security component, which
 * grants a temporary write authorization without any standing permission
 * (official media-library pattern for API 24).
 */
@Component
export struct LyricShareSheet {
  // @Prop inputs: the parent feeds them from its own state-linked values,
  // and ArkTS forbids assigning a parent @StorageProp into a regular member.
  @Prop lyrics: LyricLine[] = [];
  @Prop songName: string = '';
  @Prop artistName: string = '';
  @Prop coverSeedHex: string = '';
  /** Pre-selected line (usually the currently playing one). */
  @Prop initialSelection: number = -1;
  onClose: () => void = () => {};

  @State selectedLines: number[] = [];
  @State statusMessage: string = '';

  private renderContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private cardReady: boolean = false;

  aboutToAppear(): void {
    this.selectedLines = this.initialSelection >= 0 && this.initialSelection < this.lyrics.length
      ? [this.initialSelection]
      : [];
  }

  private isSelected(index: number): boolean {
    return this.selectedLines.indexOf(index) >= 0;
  }

  private toggle(index: number): void {
    const at = this.selectedLines.indexOf(index);
    if (at >= 0) {
      this.selectedLines.splice(at, 1);
    } else if (this.selectedLines.length < 6) {
      this.selectedLines.push(index);
    }
    this.statusMessage = '';
    this.drawCard();
  }

  private seedColor(): string {
    const seed = DynamicTheme.normalizeSeedHex(this.coverSeedHex);
    return seed !== null ? seed : '#7C4DFF';
  }

  private darkerSeed(): string {
    const rgb = DynamicTheme.hexToRgb(this.seedColor());
    const hsl = PaletteSwatch.rgbToHsl(rgb[0], rgb[1], rgb[2]);
    const dark = PaletteSwatch.hslToRgb(hsl[0], Math.min(hsl[1] * 0.9, 0.6), Math.max(0.08, hsl[2] * 0.45));
    return DynamicTheme.rgbToHex(dark[0], dark[1], dark[2]);
  }

  private drawCard(): void {
    const ctx = this.renderContext;
    const w = ctx.width;
    const h = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.cardReady = true;
    const gradient = ctx.createLinearGradient(0, 0, w, h);
    gradient.addColorStop(0, this.seedColor());
    gradient.addColorStop(1, this.darkerSeed());
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);
    const margin = w * 0.08;
    // Brand.
    ctx.fillStyle = 'rgba(255,255,255,0.72)';
    ctx.font = `600 ${Math.round(w * 0.034)}px sans-serif`;
    ctx.fillText('NeriPlayer', margin, margin + w * 0.034);
    // Lyric lines, font size shrinks as lines are added.
    const texts: string[] = [];
    for (const index of this.selectedLines) {
      texts.push(this.lyrics[index].text);
    }
    if (texts.length > 0) {
      let fontPx = Math.round(w * (texts.length <= 2 ? 0.062 : (texts.length <= 4 ? 0.05 : 0.042)));
      let fits = false;
      while (!fits && fontPx > 16) {
        ctx.font = `500 ${fontPx}px sans-serif`;
        fits = texts.every((text: string): boolean => ctx.measureText(text).width <= w - margin * 2);
        if (!fits) {
          fontPx -= 2;
        }
      }
      const lineGap = fontPx * 0.75;
      const blockHeight = texts.length * fontPx + (texts.length - 1) * lineGap;
      let y = (h - blockHeight) / 2 + fontPx * 0.8;
      ctx.fillStyle = '#FFFFFF';
      for (const text of texts) {
        ctx.fillText(text, margin, y);
        y += fontPx + lineGap;
      }
    } else {
      ctx.fillStyle = 'rgba(255,255,255,0.45)';
      ctx.font = `500 ${Math.round(w * 0.04)}px sans-serif`;
      ctx.fillText('选择歌词行', margin, h / 2);
    }
    // Credits pinned near the bottom.
    ctx.fillStyle = 'rgba(255,255,255,0.66)';
    ctx.font = `400 ${Math.round(w * 0.028)}px sans-serif`;
    const credits = `${this.songName}${this.artistName.length > 0 ? ` - ${this.artistName}` : ''}`;
    ctx.fillText(credits, margin, h - margin);
  }

  private copyText(): void {
    const texts: string[] = [];
    for (const index of this.selectedLines) {
      texts.push(this.lyrics[index].text);
    }
    const payload = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, texts.join('\n'));
    pasteboard.getSystemPasteboard().setData(payload).then(() => {
      this.statusMessage = '歌词已复制';
    }).catch((error: Error) => {
      this.statusMessage = `复制失败: ${error.message}`;
    });
  }

  private async saveToGallery(): Promise<void> {
    if (!this.cardReady) {
      this.drawCard();
    }
    const dataUrl = this.renderContext.toDataURL('image/png');
    const commaAt = dataUrl.indexOf(',');
    if (commaAt < 0) {
      this.statusMessage = '卡片尚未就绪';
      return;
    }
    const bytes = new util.Base64Helper().decodeSync(dataUrl.substring(commaAt + 1));
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined) {
      this.statusMessage = '保存失败：上下文不可用';
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const request = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context, photoAccessHelper.PhotoType.IMAGE, 'png');
      request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, bytes.buffer);
      await helper.applyChanges(request);
      this.statusMessage = '已保存到图库';
    } catch (error) {
      const e = error as Error;
      Logger.warn(`lyric card save failed: ${e.message}`);
      this.statusMessage = `保存失败: ${e.message}`;
    }
  }

  build() {
    Column() {
      Blank()
      Column({ space: 12 }) {
        Row() {
          Text('分享歌词卡片')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(Theme.primary(Theme.isDark()))
            .onClick(() => this.onClose())
        }
        .width('100%')

        // Card preview.
        Canvas(this.renderContext)
          .width('72%')
          .aspectRatio(1)
          .borderRadius(14)
          .onReady(() => {
            this.drawCard();
          })

        // Line selection.
        List({ space: 2 }) {
          ForEach(this.lyrics, (line: LyricLine, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                Checkbox()
                  .select(this.isSelected(index))
                  .selectedColor(Theme.primary(Theme.isDark()))
                  .onChange(() => this.toggle(index))
                Text(line.text)
                  .fontSize(13)
                  .fontColor(Theme.textPrimary(Theme.isDark()))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(6)
              .onClick(() => this.toggle(index))
            }
          }, (line: LyricLine, index: number) => `${index}_${line.timeMs}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .fontSize(12)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }

        Row({ space: 10 }) {
          Button('复制文本')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .onClick(() => this.copyText())
          Column() {
            SaveButton({
              icon: SaveIconStyle.FULL_FILLED,
              text: SaveDescription.SAVE_IMAGE,
              buttonType: ButtonType.Capsule
            })
              .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (result === SaveButtonOnClickResult.SUCCESS) {
                  this.saveToGallery();
                } else {
                  this.statusMessage = '未获得保存授权';
                }
              })
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
      }
      .width('100%')
      .height('76%')
      .padding(16)
      .backgroundColor(Theme.surface(Theme.isDark()))
      .borderRadius({ topLeft: 22, topRight: 22 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.scrim(Theme.isDark()))
    .onClick(() => this.onClose())
  }
}
