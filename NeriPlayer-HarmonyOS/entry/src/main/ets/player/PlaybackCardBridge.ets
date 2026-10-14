// SPDX-License-Identifier: GPL-3.0
// App-process side of the Form Kit playback card: pushes playback snapshots
// to every added card (formProvider.updateForm; the official FAQ states
// active pushes are not rate-limited) and executes card control taps that
// arrive through EntryAbility's call-event callee. Cover art is downloaded
// to the shared cacheDir and handed to the card as an fd via formImages.

import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { Logger } from '../app/Logger';
import { PlayerManager } from './PlayerManager';
import { PlayerListener } from './PlayerManager';
import {
  PlaybackCardControlParams,
  PlaybackCardSnapshot,
  buildPlaybackCardPayload,
  nextCoverImageKey,
  parsePlaybackCardControlAction
} from '../widget/PlaybackCardState';

/** 播放快照变化 → 推送卡片（class 实现：字面量实现含方法接口违反严格模式）。 */
class PlaybackCardPushListener implements PlayerListener {
  onSnapshotChanged(): void {
    PlaybackCardBridge.schedulePush();
  }
}

const PAYLOAD_FILE: string = 'widget_payload.json';
const COVER_FILE: string = 'widget_cover.img';
const TAG: string = 'NERI-PlaybackCard';

export class PlaybackCardBridge {
  private static started: boolean = false;
  private static pushing: boolean = false;
  private static pendingPush: boolean = false;
  private static coverGeneration: number = 0;
  private static lastCoverUrl: string = '';
  private static context: common.UIAbilityContext | null = null;

  /** EntryAbility.onCreate 调用（PlayerManager.initialize 之后）。 */
  static start(context: common.UIAbilityContext): void {
    PlaybackCardBridge.context = context;
    if (PlaybackCardBridge.started) {
      return;
    }
    PlaybackCardBridge.started = true;
    PlayerManager.addListener(new PlaybackCardPushListener());
  }

  /** call 事件（卡片按钮）分发：action 解析失败静默忽略。 */
  static handleControlCall(rawParams: string): void {
    try {
      const params = JSON.parse(rawParams) as PlaybackCardControlParams;
      const action = parsePlaybackCardControlAction(params);
      if (action.length === 0) {
        return;
      }
      if (action === 'toggle') {
        void PlayerManager.togglePlayPause();
      } else if (action === 'prev') {
        void PlayerManager.previous();
      } else {
        void PlayerManager.next(false);
      }
      // 状态变化会经 listener 再推一次；这里不直接推（toggle 的最终态由
      // 播放器状态机决定，避免推送中间态）。
    } catch (error) {
      Logger.warn(`${TAG} control call parse failed: ${(error as Error).message}`);
    }
  }

  static schedulePush(): void {
    void PlaybackCardBridge.pushAll();
  }

  /** 向所有已加桌卡片推送当前播放快照（切歌/暂停级频率，重入合并）。 */
  static async pushAll(): Promise<void> {
    if (PlaybackCardBridge.pushing) {
      PlaybackCardBridge.pendingPush = true;
      return;
    }
    PlaybackCardBridge.pushing = true;
    try {
      const context = PlaybackCardBridge.context;
      if (context === null) {
        return;
      }
      const song = PlayerManager.getCurrentSong();
      const snapshot = PlaybackCardSnapshot.fromSong(song, PlayerManager.getStatus());
      let coverKey = '';
      const coverUrl = snapshot.coverUrl;
      const wantsCover = snapshot.hasSong === 'true' && coverUrl.startsWith('http');
      if (wantsCover) {
        if (coverUrl !== PlaybackCardBridge.lastCoverUrl) {
          const downloaded = await PlaybackCardBridge.downloadCover(context, coverUrl);
          if (downloaded) {
            PlaybackCardBridge.lastCoverUrl = coverUrl;
          }
        }
        if (PlaybackCardBridge.coverFileExists(context)) {
          PlaybackCardBridge.coverGeneration++;
          coverKey = nextCoverImageKey(PlaybackCardBridge.coverGeneration);
        }
      } else {
        PlaybackCardBridge.lastCoverUrl = '';
      }
      const payload = buildPlaybackCardPayload(snapshot, coverKey);
      PlaybackCardBridge.persistPayload(context, JSON.stringify(payload));
      let formIds: string[] = [];
      try {
        const running = await formProvider.getPublishedRunningFormInfos();
        for (const info of running) {
          formIds.push(String(info.formId));
        }
      } catch (error) {
        // 16500100 = 桌面上没有卡片，属常态而非错误。
        const message = (error as Error).message;
        if (message.indexOf('16500100') < 0) {
          Logger.warn(`${TAG} query running forms failed: ${message}`);
        }
        return;
      }
      for (const formId of formIds) {
        await PlaybackCardBridge.pushToForm(context, formId, payload, coverKey);
      }
    } catch (error) {
      Logger.warn(`${TAG} push failed: ${(error as Error).message}`);
    } finally {
      PlaybackCardBridge.pushing = false;
      if (PlaybackCardBridge.pendingPush) {
        PlaybackCardBridge.pendingPush = false;
        PlaybackCardBridge.schedulePush();
      }
    }
  }

  private static async pushToForm(
    context: common.UIAbilityContext,
    formId: string,
    payload: Record<string, Object>,
    coverKey: string
  ): Promise<void> {
    const data: Record<string, Object> = {};
    for (const key of Object.keys(payload)) {
      data[key] = payload[key];
    }
    let coverFd: number = -1;
    if (coverKey.length > 0) {
      try {
        coverFd = fileIo.openSync(`${context.cacheDir}/${COVER_FILE}`,
          fileIo.OpenMode.READ_ONLY).fd;
        const images: Record<string, Object> = {};
        images[coverKey] = coverFd;
        data.formImages = images as Object;
      } catch (_error) {
        // 封面打开失败：卡片显示占位图。
      }
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } finally {
      if (coverFd >= 0) {
        // updateForm 返回即已消费 fd；关闭防止跨次推送累积。
        try {
          fileIo.closeSync(coverFd);
        } catch (_error) {
          // 已被系统回收时忽略。
        }
      }
    }
  }

  private static persistPayload(context: common.UIAbilityContext, json: string): void {
    try {
      const path = `${context.cacheDir}/${PAYLOAD_FILE}`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(file.fd, json);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      Logger.warn(`${TAG} persist payload failed: ${(error as Error).message}`);
    }
  }

  private static coverFileExists(context: common.UIAbilityContext): boolean {
    try {
      return fileIo.accessSync(`${context.cacheDir}/${COVER_FILE}`);
    } catch (_error) {
      return false;
    }
  }

  /** 封面小图直接整包下载覆盖单一缓存文件（LRU 不值得，一首歌一图）。 */
  private static async downloadCover(context: common.UIAbilityContext, url: string): Promise<boolean> {
    const client = http.createHttp();
    try {
      const response = await client.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 8000
      });
      if (response.responseCode !== 200 || typeof response.result === 'string') {
        return false;
      }
      const bytes = response.result as ArrayBuffer;
      if (bytes.byteLength <= 0 || bytes.byteLength > 5 * 1024 * 1024) {
        return false;
      }
      const path = `${context.cacheDir}/${COVER_FILE}`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      const file = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        fileIo.writeSync(file.fd, bytes);
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (error) {
      Logger.debug(`${TAG} cover download failed: ${(error as Error).message}`);
      return false;
    } finally {
      client.destroy();
    }
  }
}
