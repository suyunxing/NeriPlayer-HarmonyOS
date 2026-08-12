/**
 * 全局配置（对应 Android 端 shared 配置与 NeriPlayer-HarmonyOS 的 Constants）。
 */

const config = {
  appName: 'NeriPlayer',
  appVersion: '1.0.0',

  // 第三方平台端点
  neteaseBase: 'https://music.163.com',
  biliBase: 'https://api.bilibili.com',
  ytmBase: 'https://music.youtube.com',
  lrclibBase: 'https://lrclib.net/api',

  // YouTube Music 匿名搜索使用的 Web 客户端 key（公开常量）
  ytmWebApiKey: 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8',

  // 与 Android/桌面端同步数据保持兼容的稳定标识
  youtubeMusicIdentityAlbum: 'youtube_music',
  bilibiliIdentityHint: 'Bilibili',
  neteaseIdentityHint: 'Netease',
  youtubeMusicMediaPrefix: 'youtube_music|',

  // 存储 key
  keyQueueJson: 'player.queueJson',
  keySettings: 'app.settings',
  keyHistory: 'app.history',
  keyPlaylists: 'app.playlists',
  keyStats: 'app.stats',
  keyDownloads: 'app.downloads',
  keyOnboarded: 'app.onboarded',
  keyDisclaimerAgreed: 'app.disclaimerAgreed',
};

module.exports = config;
