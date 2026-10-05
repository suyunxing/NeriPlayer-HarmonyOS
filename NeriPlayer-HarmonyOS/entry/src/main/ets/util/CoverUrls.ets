// SPDX-License-Identifier: GPL-3.0

/**
 * 列表小封面显示专用：网易云图片 CDN 支持 ?param=WxH 服务端缩放，拼上后
 * 避免 52vp 缩略图也整张下载原图（常见 1000px+，解码数十 MB）。只在显示层
 * 使用，不写回 SongItem、不参与落库与同步（Android 端读 URL 时本就会剥掉
 * ?param= 后缀，见 NeteaseClient.kt）。非网易云 http 源（B 站/YTM/本地）原样返回。
 */
export function coverThumbnailUrl(url: string, sizePx: number): string {
  if (sizePx <= 0 || !url.startsWith('http') || url.indexOf('music.126.net') < 0) {
    return url;
  }
  if (url.indexOf('?param=') >= 0) {
    return url;
  }
  return `${url}?param=${sizePx}y${sizePx}`;
}
