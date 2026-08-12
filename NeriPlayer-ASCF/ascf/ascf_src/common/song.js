/**
 * SongItem 模型与稳定身份 key（与 Android/桌面端 sync 数据格式兼容：
 *   "<id>|<album>|<mediaUri>"）。
 */

const constants = require('./constants');

const PLATFORM_LOCAL = 0;
const PLATFORM_NETEASE = 1;
const PLATFORM_BILIBILI = 2;
const PLATFORM_YOUTUBE_MUSIC = 3;

function newSong(opts) {
  const o = opts || {};
  return {
    id: o.id || 0,
    name: o.name || '',
    artist: o.artist || '',
    album: o.album || '',
    albumId: o.albumId || 0,
    durationMs: o.durationMs || 0,
    coverUrl: o.coverUrl || '',
    mediaUri: o.mediaUri || '',
    matchedLyric: o.matchedLyric || '',
    matchedTranslatedLyric: o.matchedTranslatedLyric || '',
    matchedSongId: o.matchedSongId || '',
    userLyricOffsetMs: o.userLyricOffsetMs || 0,
    customCoverUrl: o.customCoverUrl || '',
    customName: o.customName || '',
    customArtist: o.customArtist || '',
    originalName: o.originalName || '',
    originalArtist: o.originalArtist || '',
    originalCoverUrl: o.originalCoverUrl || '',
    originalLyric: o.originalLyric || '',
    originalTranslatedLyric: o.originalTranslatedLyric || '',
    localFileName: o.localFileName || '',
    localFilePath: o.localFilePath || '',
    channelId: o.channelId || '',
    audioId: o.audioId || '',
    subAudioId: o.subAudioId || '',
    playlistContextId: o.playlistContextId || '',
    sourceStableKey: o.sourceStableKey || '',
    streamUrl: o.streamUrl || '',
    addedAt: o.addedAt || 0,
    platform: o.platform !== undefined ? o.platform : PLATFORM_NETEASE,
  };
}

function displayName(song) {
  return song.customName && song.customName.length > 0 ? song.customName : song.name;
}

function displayArtist(song) {
  return song.customArtist && song.customArtist.length > 0 ? song.customArtist : song.artist;
}

function effectiveCoverUrl(song) {
  if (song.customCoverUrl && song.customCoverUrl.length > 0) {
    return song.customCoverUrl;
  }
  return song.coverUrl;
}

/**
 * FNV-1a 32-bit hash，用于为没有数字 id 的平台曲目（Bilibili/YouTube Music）生成稳定 id。
 */
function hashStableId(seed) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) {
    hash ^= seed.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

function extractYouTubeMusicVideoId(mediaUri) {
  const prefix = constants.youtubeMusicMediaPrefix;
  if (mediaUri && mediaUri.indexOf(prefix) === 0) {
    return mediaUri.substring(prefix.length);
  }
  return '';
}

function buildYouTubeMusicMediaUri(videoId) {
  return constants.youtubeMusicMediaPrefix + videoId;
}

function normalizedChannelId(song) {
  const rawChannelId = (song.channelId || '').trim();
  if (rawChannelId.length > 0) {
    const lowered = rawChannelId.toLowerCase();
    if (lowered === 'youtube' || lowered === 'ytmusic' || lowered === 'youtubemusic') {
      return constants.youtubeMusicIdentityAlbum;
    }
    return lowered;
  }
  if (extractYouTubeMusicVideoId(song.mediaUri).length > 0) {
    return constants.youtubeMusicIdentityAlbum;
  }
  if ((song.album || '').indexOf(constants.bilibiliIdentityHint) === 0) {
    return 'bilibili';
  }
  if ((song.album || '').indexOf(constants.neteaseIdentityHint) === 0) {
    return 'netease';
  }
  if ((song.mediaUri || '').length === 0) {
    return 'netease';
  }
  return '';
}

function normalizedSubAudioId(channel, rawSubAudioId, album) {
  const explicit = (rawSubAudioId || '').trim();
  if (channel !== 'bilibili') {
    return '';
  }
  if (explicit.length > 0) {
    return explicit;
  }
  const afterSeparator = (album || '').indexOf('|');
  return afterSeparator >= 0 ? album.substring(afterSeparator + 1) : '';
}

function songIdentity(song) {
  const videoId = extractYouTubeMusicVideoId(song.mediaUri);
  if (videoId.length > 0) {
    return {
      id: hashStableId(videoId),
      album: constants.youtubeMusicIdentityAlbum,
      mediaUri: buildYouTubeMusicMediaUri(videoId),
    };
  }

  const channel = normalizedChannelId(song);
  const audioId = (song.audioId || '').trim();
  const audio = audioId.length > 0 ? audioId : (song.id !== 0 ? '' + song.id : '');
  if (channel.length === 0 || audio.length === 0) {
    return { id: song.id, album: song.album, mediaUri: song.mediaUri };
  }
  if (channel === constants.youtubeMusicIdentityAlbum) {
    return {
      id: hashStableId(audio),
      album: constants.youtubeMusicIdentityAlbum,
      mediaUri: buildYouTubeMusicMediaUri(audio),
    };
  }

  const subAudio = normalizedSubAudioId(channel, song.subAudioId, song.album);
  if (channel === 'netease') {
    const numericId = Number(audio);
    return {
      id: Number.isNaN(numericId) ? hashStableId(channel + '|' + audio) : numericId,
      album: channel,
      mediaUri: '',
    };
  }
  return {
    id: hashStableId(channel + '|' + audio + '|' + subAudio),
    album: channel,
    mediaUri: '',
  };
}

function stableKeyOf(song) {
  const identity = songIdentity(song);
  return identity.id + '|' + identity.album + '|' + identity.mediaUri;
}

module.exports = {
  PLATFORM_LOCAL,
  PLATFORM_NETEASE,
  PLATFORM_BILIBILI,
  PLATFORM_YOUTUBE_MUSIC,
  newSong,
  displayName,
  displayArtist,
  effectiveCoverUrl,
  hashStableId,
  songIdentity,
  stableKeyOf,
};
