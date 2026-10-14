/**
 * 网易云 web 端内置表情目录（上游 data/model/comments/NeteaseEmoteCatalog.kt 直译）。
 *
 * 只内置「名称 -> 官方 CDN 图片 id」映射（取自网易云 web core.js 的 i5n 表，59 项），
 * 不上架图片：表情图仍由网易云官方 CDN 按需加载，不增加包体积，也不打包再分发官方表情。
 */

const NETEASE_EMOTE_URL_TEMPLATE: string = 'https://s1.music.126.net/style/web2/emt/emoji_%s.png';

/** 名称 -> 图片 id（与上游逐项一致）。 */
const NETEASE_EMOTE_IDS: string[][] = [
  ['大笑', '86'], ['可爱', '85'], ['憨笑', '359'], ['色', '95'], ['亲亲', '363'],
  ['惊恐', '96'], ['流泪', '356'], ['亲', '362'], ['呆', '352'], ['哀伤', '342'],
  ['呲牙', '343'], ['吐舌', '348'], ['撇嘴', '353'], ['怒', '361'], ['奸笑', '341'],
  ['汗', '97'], ['痛苦', '346'], ['惶恐', '354'], ['生病', '350'], ['口罩', '351'],
  ['大哭', '357'], ['晕', '355'], ['发怒', '115'], ['开心', '360'], ['鬼脸', '94'],
  ['皱眉', '87'], ['流感', '358'], ['爱心', '33'], ['心碎', '34'], ['钟情', '303'],
  ['星星', '309'], ['生气', '314'], ['便便', '89'], ['强', '13'], ['弱', '372'],
  ['拜', '14'], ['牵手', '379'], ['跳舞', '380'], ['禁止', '374'], ['这边', '262'],
  ['爱意', '106'], ['示爱', '376'], ['嘴唇', '367'], ['狗', '81'], ['猫', '78'],
  ['猪', '100'], ['兔子', '459'], ['小鸡', '450'], ['公鸡', '461'], ['幽灵', '116'],
  ['圣诞', '411'], ['外星', '101'], ['钻石', '52'], ['礼物', '107'], ['男孩', '0'],
  ['女孩', '1'], ['蛋糕', '337'], ['圈', '312'], ['叉', '313']
];

let cachedEmoteUrls: Map<string, string> | null = null;

/**
 * 网易云的「正文标记 -> 表情图 URL」表，供 Mapper 展开正文里的 `[名称]` 标记。
 * 惰性构建一次，避免每条评论重复拼 59 个地址。
 */
export function neteaseEmoteUrlMap(): Map<string, string> {
  if (cachedEmoteUrls === null) {
    const urls = new Map<string, string>();
    for (const pair of NETEASE_EMOTE_IDS) {
      urls.set(pair[0], NETEASE_EMOTE_URL_TEMPLATE.replace('%s', pair[1]));
    }
    cachedEmoteUrls = urls;
  }
  return cachedEmoteUrls;
}

/** 网易云表情名称 -> 表情图 CDN 直链；名称不在表内时返回 null。 */
export function neteaseEmoteUrl(name: string): string | null {
  const id = neteaseEmoteUrlMap().get(name);
  return id ?? null;
}
