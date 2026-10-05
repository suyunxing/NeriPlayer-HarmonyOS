/**
 * 通用格式化工具。
 */

function pad2(value) {
  return value < 10 ? '0' + value : '' + value;
}

function formatTime(ms) {
  const totalSeconds = Math.max(0, Math.floor((ms || 0) / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return minutes + ':' + pad2(seconds);
}

function formatCount(count) {
  const n = count || 0;
  if (n >= 100000000) {
    return (n / 100000000).toFixed(1) + '亿';
  }
  if (n >= 10000) {
    return (n / 10000).toFixed(1) + '万';
  }
  return '' + n;
}

// 实体须单遍一次解码（&amp; 与其他实体同一遍处理），链式多次 replace 会把 &amp;lt; 二次解码成 <
function decodeEntities(text) {
  return String(text || '').replace(/&(amp|lt|gt|quot);/g, function (match, entity) {
    switch (entity) {
      case 'amp': return '&';
      case 'lt': return '<';
      case 'gt': return '>';
      default: return '"';
    }
  });
}

function stripHtml(text) {
  // 先解码实体再剥标签，且标签剥离须循环到收敛，防止 <scri<x>pt> 这类拼接重组出 <script>
  let result = decodeEntities(text);
  let previous;
  do {
    previous = result;
    result = result.replace(/<[^>]*>/g, '');
  } while (result !== previous);
  return result.trim();
}

function parseDurationMs(durationText) {
  const parts = String(durationText || '').split(':');
  let total = 0;
  for (let i = 0; i < parts.length; i++) {
    const value = Number(parts[i]);
    if (Number.isNaN(value)) {
      return 0;
    }
    total = total * 60 + value;
  }
  return total * 1000;
}

function platformName(platform) {
  switch (platform) {
    case 0: return '本地';
    case 1: return '网易云音乐';
    case 2: return '哔哩哔哩';
    case 3: return 'YouTube Music';
    default: return '本地';
  }
}

module.exports = {
  pad2,
  formatTime,
  formatCount,
  stripHtml,
  parseDurationMs,
  platformName,
};
