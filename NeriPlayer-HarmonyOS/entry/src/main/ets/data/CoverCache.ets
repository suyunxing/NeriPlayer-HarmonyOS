// SPDX-License-Identifier: GPL-3.0

import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { Logger } from '../app/Logger';
import { LruCache } from '../util/LruCache';
import { coverThumbnailUrl } from '../util/CoverUrls';

/**
 * 进程级封面缓存（内存 LRU）。列表行被 LazyForEach 销毁重建后，系统 Image
 * 会重新走完整网络加载/解码（真机 2026-10-01 反馈：下滑再上滑封面全部重载、
 * 持续卡顿）；改由本缓存持有解码好的 PixelMap，行重建时同步命中、零加载。
 *
 * - key 用原始 URL；下载时对网易云源拼 ?param 服务端缩略（见 coverThumbnailUrl）；
 * - 解码按 desiredSize 降采样到小图尺寸，单张内存固定在几十 KB 量级；
 * - 同 URL 并发请求去重（inflight 表），快滑时不重复建连；
 * - 全部失败路径返回 null（组件显示占位），不缓存失败结果。
 */
export class CoverCache {
  /** 256 张 × 156px 解码图 ≈ 25MB 上限，足够覆盖滚动回看窗口。 */
  private static readonly MAX_ENTRIES: number = 256;
  /** 解码目标边长（px）：52vp 缩略图 @3x 屏的物理像素。 */
  private static readonly DECODE_PX: number = 156;
  private static cache: LruCache<string, image.PixelMap> = new LruCache<string, image.PixelMap>(CoverCache.MAX_ENTRIES);
  private static inflight: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();

  /** 同步查缓存（命中即最近使用）。未命中返回 null。 */
  static peek(url: string): image.PixelMap | null {
    const hit = CoverCache.cache.get(url);
    return hit === undefined ? null : hit;
  }

  /** 取封面：命中/去重合并/下载解码。失败返回 null，不抛出。 */
  static fetch(url: string): Promise<image.PixelMap | null> {
    if (url.length === 0) {
      return Promise.resolve<image.PixelMap | null>(null);
    }
    const hit = CoverCache.cache.get(url);
    if (hit !== undefined) {
      return Promise.resolve<image.PixelMap | null>(hit);
    }
    const pending = CoverCache.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<image.PixelMap | null> = CoverCache.downloadAndDecode(url)
      .then((pixelMap: image.PixelMap | null): image.PixelMap | null => {
        if (pixelMap !== null) {
          CoverCache.cache.put(url, pixelMap);
        }
        return pixelMap;
      })
      .catch((error: Error): image.PixelMap | null => {
        Logger.warn(`CoverCache: fetch failed: ${error.message}`);
        return null;
      })
      .then((pixelMap: image.PixelMap | null): image.PixelMap | null => {
        CoverCache.inflight.delete(url);
        return pixelMap;
      });
    CoverCache.inflight.set(url, task);
    return task;
  }

  private static async downloadAndDecode(url: string): Promise<image.PixelMap | null> {
    const bytes = await CoverCache.download(url);
    if (bytes === null || bytes.byteLength === 0) {
      return null;
    }
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(bytes);
      if (source === null) {
        return null;
      }
      const options: image.DecodingOptions = {
        desiredSize: { width: CoverCache.DECODE_PX, height: CoverCache.DECODE_PX }
      };
      return await source.createPixelMap(options);
    } catch (error) {
      const e = error as Error;
      Logger.warn(`CoverCache: decode failed: ${e.message}`);
      return null;
    } finally {
      if (source !== null) {
        source.release().catch((releaseError: Error): void => {
          Logger.warn(`CoverCache: source release failed: ${releaseError.message}`);
        });
      }
    }
  }

  private static async download(url: string): Promise<ArrayBuffer | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(coverThumbnailUrl(url, CoverCache.DECODE_PX * 2), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 12000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        Logger.warn(`CoverCache: http ${response.responseCode} for cover request`);
        return null;
      }
      return response.result as ArrayBuffer;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`CoverCache: download failed: ${e.message}`);
      return null;
    } finally {
      request.destroy();
    }
  }
}
