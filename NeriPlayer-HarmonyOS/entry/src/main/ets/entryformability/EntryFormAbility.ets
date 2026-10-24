// SPDX-License-Identifier: GPL-3.0
// Form Kit entry (FormExtensionAbility) for the playback card. Runs in the
// form process: it must not touch media/audio APIs; it only serves the last
// pushed snapshot (plain files under the shared cacheDir — preferences are
// single-process and must not be shared across the form process) when the
// user adds a card. Live updates come from the app process
// (PlaybackCardBridge → formProvider.updateForm) and control taps go through
// call events straight to EntryAbility.

import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want, common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const PAYLOAD_FILE: string = 'widget_payload.json';
const COVER_FILE: string = 'widget_cover.img';

function readCacheFile(context: common.Context, name: string): string {
  try {
    const path = `${context.cacheDir}/${name}`;
    if (!fileIo.accessSync(path)) {
      return '';
    }
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer));
    } finally {
      fileIo.closeSync(file);
    }
  } catch (_error) {
    return '';
  }
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters = want.parameters;
    const rawFormId: Object | undefined = parameters === undefined
      ? undefined : parameters[formInfo.FormParam.IDENTITY_KEY];
    const formId = rawFormId === undefined ? '' : String(rawFormId);
    const payloadJson = readCacheFile(this.context, PAYLOAD_FILE);
    const data: Record<string, Object> = {};
    data.formId = formId;
    if (payloadJson.length > 0) {
      try {
        const pushed = JSON.parse(payloadJson) as Record<string, Object>;
        for (const key of Object.keys(pushed)) {
          data[key] = pushed[key];
        }
      } catch (_error) {
        // 首次加卡或快照损坏：卡片显示默认「未在播放」态。
      }
    }
    // 封面以 fd 供给（有缓存文件且上次推送带了封面时）。
    if (String(data['hasCover'] ?? 'false') === 'true') {
      const coverKey = String(data['coverKey'] ?? '');
      try {
        const coverPath = `${this.context.cacheDir}/${COVER_FILE}`;
        if (coverKey.length > 0 && fileIo.accessSync(coverPath)) {
          const fd = fileIo.openSync(coverPath, fileIo.OpenMode.READ_ONLY).fd;
          const images: Record<string, Object> = {};
          images[coverKey] = fd;
          data.formImages = images as Object;
        }
      } catch (_error) {
        // 封面缺失时卡片回退占位图。
      }
    }
    return formBindingData.createFormBindingData(data);
  }

  onRemoveForm(_formId: string): void {
    // 应用侧推送前总是经 formProvider.getPublishedRunningFormInfos() 拉活表，
    // 这里无需维护 formId 集合。
  }
}
