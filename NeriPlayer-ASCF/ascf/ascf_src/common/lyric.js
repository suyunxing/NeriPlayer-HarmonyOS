/**
 * LRC 解析、翻译合并与歌词获取（LRCLIB → 网易云），
 * 移植自 LrcParser.ets / LyricApi.ets。
 */

const constants = require('./constants');
const http = require('./http');
const netease = require('./netease');

const TIMESTAMP_REGEX = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

function parse(text) {
  const lines = [];
  if (!text || text.length === 0) {
    return lines;
  }
  const sourceLines = String(text).split('\n');
  for (let i = 0; i < sourceLines.length; i++) {
    const sourceLine = sourceLines[i];
    const matches = collectTimestamps(sourceLine);
    if (matches.length === 0) {
      continue;
    }
    const content = lineContent(sourceLine);
    if (content.trim().length === 0) {
      continue;
    }
    for (let j = 0; j < matches.length; j++) {
      lines.push({ timeMs: matches[j], text: content, translated: '' });
    }
  }
  lines.sort(function (a, b) {
    return a.timeMs - b.timeMs;
  });
  return lines;
}

function mergeTranslation(lines, translatedText) {
  if (!translatedText || translatedText.length === 0) {
    return lines;
  }
  const translated = parse(translatedText);
  const result = lines.slice();
  for (let i = 0; i < result.length; i++) {
    for (let j = 0; j < translated.length; j++) {
      if (Math.abs(result[i].timeMs - translated[j].timeMs) < 150) {
        result[i].translated = translated[j].text;
        break;
      }
    }
  }
  return result;
}

function formatTime(timeMs) {
  const totalSeconds = Math.max(0, Math.floor((timeMs || 0) / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return minutes + ':' + (seconds < 10 ? '0' + seconds : '' + seconds);
}

function collectTimestamps(line) {
  const timestamps = [];
  TIMESTAMP_REGEX.lastIndex = 0;
  let match = TIMESTAMP_REGEX.exec(line);
  while (match !== null) {
    const minutes = Number(match[1]);
    const seconds = Number(match[2]);
    let fraction = 0;
    if (match[3] !== undefined) {
      const raw = match[3];
      fraction = Number(raw) / Math.pow(10, raw.length);
    }
    timestamps.push(minutes * 60000 + seconds * 1000 + fraction * 1000);
    match = TIMESTAMP_REGEX.exec(line);
  }
  return timestamps;
}

function lineContent(line) {
  const lastBracket = line.lastIndexOf(']');
  return lastBracket >= 0 ? line.substring(lastBracket + 1) : line;
}

async function fetchFromLrcLib(name, artist, durationMs) {
  const url =
    constants.lrclibBase +
    '/get?track_name=' +
    encodeURIComponent(name) +
    '&artist_name=' +
    encodeURIComponent(artist) +
    '&duration=' +
    Math.round((durationMs || 0) / 1000);
  const text = await http.getText(url);
  const response = JSON.parse(text);
  return {
    lyric: response.syncedLyrics || response.plainLyrics || '',
    translated: '',
  };
}

async function fetchLyrics(song) {
  // 优先网易云（有翻译），失败再试 LRCLIB
  if (song.platform === 1 && song.audioId) {
    try {
      const payload = await netease.getLyric(Number(song.audioId));
      if (payload.lyric && payload.lyric.length > 0) {
        return payload;
      }
    } catch (e) {
      console.warn('netease lyric failed: ' + e.message);
    }
  }
  try {
    const payload = await fetchFromLrcLib(song.name, song.artist, song.durationMs);
    if (payload.lyric && payload.lyric.length > 0) {
      return payload;
    }
  } catch (e) {
    console.warn('lrclib lyric failed: ' + e.message);
  }
  return { lyric: '', translated: '' };
}

module.exports = {
  parse,
  mergeTranslation,
  formatTime,
  fetchFromLrcLib,
  fetchLyrics,
};
