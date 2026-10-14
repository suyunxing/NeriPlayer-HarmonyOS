// SPDX-License-Identifier: GPL-3.0
// Unit tests for the YouTube Music creator parsers (upstream
// YouTubeMusicCreatorParserTest, commit 4c085185).

import { describe, it, expect } from '@ohos/hypium';
import {
  YtmCreatorItem,
  YtmCreatorItemType,
  YtmCreatorSummary,
  buildYtmCreatorPlaybackQueue,
  extractYtmSearchContinuation,
  mergeYtmCreatorItems,
  parseYtmCreatorDetail,
  parseYtmCreatorItemsContinuation,
  parseYtmCreatorItemsPage,
  parseYtmCreatorSearchResults,
  upgradeYtmThumbnailUrl,
  ytmCreatorItemKey,
  ytmCreatorItemToSongItem
} from '../../../main/ets/network/ytm/YtmCreatorParser';

function data(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

function summary(browseId: string, title: string): YtmCreatorSummary {
  const out = new YtmCreatorSummary();
  out.browseId = browseId;
  out.title = title;
  return out;
}

/** creators 搜索根：musicShelf + itemSection 两个内容数组（上游 findSearchResultContentArrays）。 */
const SEARCH_ROOT = `{
  "contents": {"tabbedSearchResultsRenderer": {"tabs": [{"tabRenderer": {"content": {"sectionListRenderer": {"contents": [
    {"musicShelfRenderer": {"contents": [
      {"musicTwoRowItemRenderer": {
        "title": {"runs": [{"text": "Two Row Artist"}]},
        "subtitle": {"runs": [{"text": "Artist"}, {"text": " • "}, {"text": "1.2M subscribers"}]},
        "thumbnailRenderer": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
          {"url": "https://yt3.ggpht.com/photo=w48-h48"},
          {"url": "https://yt3.ggpht.com/photo=w120-h120"}
        ]}}},
        "navigationEndpoint": {"browseEndpoint": {"browseId": "UCtwo", "params": "abc"}}
      }},
      {"musicResponsiveListItemRenderer": {
        "flexColumns": [
          {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "List Artist"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "980K subscribers"}]}}}
        ],
        "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
          {"url": "https://yt3.ggpht.com/list=w120-h120"}
        ]}}},
        "navigationEndpoint": {"browseEndpoint": {"browseId": "VLlist"}},
        "menu": {"menuRenderer": {"items": [
          {"toggleMenuServiceItemRenderer": {"defaultServiceEndpoint": {"subscribeEndpoint": {"channelIds": ["UCfromMenu"]}}}}
        ]}}
      }},
      {"musicTwoRowItemRenderer": {
        "title": {"runs": [{"text": "No Endpoint"}]},
        "subtitle": {"runs": [{"text": "Artist"}]}
      }},
      {"musicTwoRowItemRenderer": {
        "title": {"runs": [{"text": "Two Row Artist"}]},
        "subtitle": {"runs": [{"text": "Artist"}]},
        "navigationEndpoint": {"browseEndpoint": {"browseId": "UCtwo"}}
      }}
    ]}},
    {"itemSectionRenderer": {"contents": [
      {"musicResponsiveListItemRenderer": {
        "flexColumns": [
          {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Shelf Artist"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "12K subscribers"}]}}}
        ],
        "navigationEndpoint": {"browseEndpoint": {"browseId": "UCshelf"}}
      }}
    ]}}
  ]}}}}}
}`;

const SONG_ITEM = `{"musicResponsiveListItemRenderer": {
  "flexColumns": [
    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": "Song One"}]}}},
    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
      {"text": "Song"},
      {"text": " • "},
      {"text": "Artist A", "navigationEndpoint": {"browseEndpoint": {"browseId": "UCA"}}},
      {"text": " • "},
      {"text": "Album X", "navigationEndpoint": {"browseEndpoint": {"browseId": "MPRE1"}}},
      {"text": " • "},
      {"text": "3:45"}
    ]}}}
  ],
  "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
    {"url": "https://i.ytimg.com/vi/vid1/hq720.jpg"}
  ]}}},
  "playlistItemData": {"videoId": "vid1"},
  "overlay": {"musicItemThumbnailOverlayRenderer": {"content": {"musicPlayButtonRenderer": {"playNavigationEndpoint": {"watchEndpoint": {
    "videoId": "vid1",
    "watchEndpointMusicSupportedConfigs": {"watchEndpointMusicConfig": {"musicVideoType": "MUSIC_VIDEO_TYPE_ATV"}}
  }}}}}}
}}`;

export default function YtmCreatorParserTest() {
  describe('YtmCreatorParser', () => {
    it('searchResults_parsesBothRendererShapesAndDedupes', 0, () => {
      const results = parseYtmCreatorSearchResults(data(SEARCH_ROOT), 30);
      // 无 browseEndpoint 的条目被过滤；重复 browseId 只留首个。
      expect(results.length).assertEqual(3);
      expect(results[0].browseId).assertEqual('UCtwo');
      expect(results[0].title).assertEqual('Two Row Artist');
      expect(results[0].subtitle).assertEqual('Artist • 1.2M subscribers');
      // channelId：UC 前缀直接取 browseId；尺寸参数被提升为 w1200。
      expect(results[0].channelId).assertEqual('UCtwo');
      expect(results[0].coverUrl).assertEqual('https://yt3.ggpht.com/photo=w1200-h120');
      expect(results[1].browseId).assertEqual('VLlist');
      // 非 UC 前缀的 browseId 走 menu subscribeEndpoint 提取 channelId。
      expect(results[1].channelId).assertEqual('UCfromMenu');
      expect(results[1].coverUrl).assertEqual('https://yt3.ggpht.com/list=w1200-h120');
      expect(results[2].browseId).assertEqual('UCshelf');
      const capped = parseYtmCreatorSearchResults(data(SEARCH_ROOT), 1);
      expect(capped.length).assertEqual(1);
    });

    it('searchContinuation_readsShelfTokens', 0, () => {
      const root = data(`{"contents": {"tabbedSearchResultsRenderer": {"tabs": [{"tabRenderer": {"content": {"sectionListRenderer": {"contents": [
        {"musicShelfRenderer": {"contents": [], "continuations": [{"nextContinuationData": {"continuation": "searchTok"}}]}}
      ]}}}}}}}`);
      expect(extractYtmSearchContinuation(root)).assertEqual('searchTok');
      const fromContinuation = data(`{"continuationContents": {"musicShelfContinuation": {
        "contents": [], "continuations": [{"nextContinuationData": {"continuation": "shelfTok"}}]}}}`);
      expect(extractYtmSearchContinuation(fromContinuation)).assertEqual('shelfTok');
      expect(extractYtmSearchContinuation(data('{}'))).assertEqual('');
    });

    it('detail_parsesHeaderSectionsAndMoreEndpoints', 0, () => {
      const detail = parseYtmCreatorDetail(data(`{
        "header": {"musicImmersiveHeaderRenderer": {
          "title": {"runs": [{"text": "Detail Artist"}]},
          "straplineTextOne": {"runs": [{"text": "2.3M subscribers"}]},
          "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
            {"url": "https://yt3.ggpht.com/detail=w120-h120"}
          ]}}},
          "shortSubscriberCountText": {"simpleText": "2.3M subscribers"},
          "monthlyListenerCount": {"simpleText": "5.6M monthly listeners"}
        }},
        "contents": {"singleColumnBrowseResultsRenderer": {"tabs": [{"tabRenderer": {"content": {"sectionListRenderer": {"contents": [
          {"musicDescriptionShelfRenderer": {"description": {"runs": [{"text": "Artist bio"}]}}},
          {"musicShelfRenderer": {
            "title": {"runs": [{"text": "Songs"}]},
            "contents": [${SONG_ITEM}],
            "moreContentButton": {"buttonRenderer": {"navigationEndpoint": {"browseEndpoint": {"browseId": "UCtwo", "params": "songsAll"}}}}
          }},
          {"musicCarouselShelfRenderer": {
            "header": {"musicCarouselShelfBasicHeaderRenderer": {"title": {"runs": [{"text": "Albums"}]}}},
            "contents": [
              {"musicTwoRowItemRenderer": {
                "title": {"runs": [{"text": "Album Card"}]},
                "subtitle": {"runs": [{"text": "Album"}, {"text": " • "}, {"text": "2024"}]},
                "navigationEndpoint": {"browseEndpoint": {
                  "browseId": "MPRE2",
                  "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {"pageType": "MUSIC_PAGE_TYPE_ALBUM"}}
                }}
              }}
            ],
            "bottomEndpoint": {"browseEndpoint": {"browseId": "UCtwo", "params": "albumsAll"}}
          }},
          {"itemSectionRenderer": {"contents": [
            {"musicShelfRenderer": {"title": {"runs": [{"text": "Nested"}]}, "contents": []}}
          ]}}
        ]}}}}]}}
      }`), summary('UCtwo', 'Fallback'));
      // subtitle：header.subtitle 空 → straplineTextOne；description 回退 section 描述架。
      expect(detail.header.title).assertEqual('Detail Artist');
      expect(detail.header.browseId).assertEqual('UCtwo');
      expect(detail.header.subtitle).assertEqual('2.3M subscribers');
      expect(detail.header.description).assertEqual('Artist bio');
      expect(detail.header.subscriberCountText).assertEqual('2.3M subscribers');
      expect(detail.header.monthlyListenerCountText).assertEqual('5.6M monthly listeners');
      expect(detail.header.coverUrl).assertEqual('https://yt3.ggpht.com/detail=w1200-h120');
      // 空 items 的分区（Nested）被过滤。
      expect(detail.sections.length).assertEqual(2);
      expect(detail.sections[0].title).assertEqual('Songs');
      expect(detail.sections[0].moreEndpoint?.browseId).assertEqual('UCtwo');
      expect(detail.sections[0].moreEndpoint?.params).assertEqual('songsAll');
      expect(detail.sections[1].title).assertEqual('Albums');
      expect(detail.sections[1].moreEndpoint?.params).assertEqual('albumsAll');
      const song = detail.sections[0].items[0];
      expect(song.type).assertEqual(YtmCreatorItemType.SONG);
      expect(song.title).assertEqual('Song One');
      expect(song.videoId).assertEqual('vid1');
      expect(song.artist).assertEqual('Artist A');
      expect(song.album).assertEqual('Album X');
      expect(song.durationMs).assertEqual(225000);
      const card = detail.sections[1].items[0];
      expect(card.type).assertEqual(YtmCreatorItemType.ALBUM);
      expect(card.browseId).assertEqual('MPRE2');
      expect(card.videoId).assertEqual('');
    });

    it('detail_fallsBackToSummaryWhenHeaderMissing', 0, () => {
      const detail = parseYtmCreatorDetail(data(`{"contents": {}}`),
        summary('UCx', 'Fallback Artist'));
      expect(detail.header.title).assertEqual('Fallback Artist');
      expect(detail.header.browseId).assertEqual('UCx');
      expect(detail.sections.length).assertEqual(0);
    });

    it('twoRowItem_resolvesVideoTypeArtistAndDuration', 0, () => {
      const page = parseYtmCreatorItemsPage(data(`{
        "contents": {"singleColumnBrowseResultsRenderer": {"tabs": [{"tabRenderer": {"content": {"sectionListRenderer": {"contents": [
          {"gridRenderer": {
            "header": {"gridHeaderRenderer": {"title": {"runs": [{"text": "Videos Grid"}]}}},
            "items": [
              {"musicTwoRowItemRenderer": {
                "title": {"runs": [{"text": "Video One"}]},
                "subtitle": {"runs": [{"text": "Video"}, {"text": " • "}, {"text": "Artist V"}, {"text": " • "}, {"text": "12:34"}]},
                "navigationEndpoint": {"watchEndpoint": {
                  "videoId": "vid2",
                  "watchEndpointMusicSupportedConfigs": {"watchEndpointMusicConfig": {"musicVideoType": "MUSIC_VIDEO_TYPE_UGC"}}
                }}
              }},
              {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "gridTok"}}}}
            ]
          }}
        ]}}}}]}}
      }`), 'Fallback Title');
      expect(page.title).assertEqual('Videos Grid');
      expect(page.items.length).assertEqual(1);
      const video = page.items[0];
      expect(video.type).assertEqual(YtmCreatorItemType.VIDEO);
      expect(video.title).assertEqual('Video One');
      expect(video.videoId).assertEqual('vid2');
      expect(video.artist).assertEqual('Artist V');
      expect(video.durationMs).assertEqual(754000);
      expect(page.continuation).assertEqual('gridTok');
    });

    it('itemsPage_readsPlaylistShelfAndFallsBack', 0, () => {
      const page = parseYtmCreatorItemsPage(data(`{
        "contents": {"sectionListRenderer": {"contents": [
          {"musicPlaylistShelfRenderer": {
            "title": {"runs": [{"text": "Playlist Shelf"}]},
            "contents": [${SONG_ITEM}, ${SONG_ITEM}],
            "continuations": [{"nextContinuationData": {"continuation": "shelfTok"}}}
          }}
        ]}}
      }`), 'Fallback Title');
      expect(page.title).assertEqual('Playlist Shelf');
      expect(page.items.length).assertEqual(1);
      expect(page.continuation).assertEqual('shelfTok');
      // title 空 → fallbackTitle；items 空 → continuation 丢弃。
      const empty = parseYtmCreatorItemsPage(data(`{
        "contents": {"sectionListRenderer": {"contents": [
          {"musicShelfRenderer": {"title": {}, "contents": [], "continuations": [{"nextContinuationData": {"continuation": "t"}}]}}
        ]}}
      }`), 'Fallback Title');
      expect(empty.title).assertEqual('Fallback Title');
      expect(empty.items.length).assertEqual(0);
      expect(empty.continuation).assertEqual('');
      const noSource = parseYtmCreatorItemsPage(data('{}'), 'Nothing');
      expect(noSource.title).assertEqual('Nothing');
      expect(noSource.items.length).assertEqual(0);
    });

    it('itemsContinuation_readsAppendActions', 0, () => {
      const fromAppend = parseYtmCreatorItemsContinuation(data(`{
        "onResponseReceivedActions": [{"appendContinuationItemsAction": {"continuationItems": [
          ${SONG_ITEM},
          {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "nextTok"}}}}
        ]}}]
      }`));
      expect(fromAppend.items.length).assertEqual(1);
      expect(fromAppend.items[0].videoId).assertEqual('vid1');
      expect(fromAppend.continuation).assertEqual('nextTok');
      const fromGrid = parseYtmCreatorItemsContinuation(data(`{
        "continuationContents": {"gridContinuation": {"items": [${SONG_ITEM}]}}
      }`));
      expect(fromGrid.items.length).assertEqual(1);
      expect(fromGrid.title).assertEqual('');
    });

    it('mergeAndKeys_dedupeByVideoThenBrowseId', 0, () => {
      const a = ytmCreatorItemToSongItem(parseYtmCreatorItemsPage(data(`{
        "contents": {"sectionListRenderer": {"contents": [{"musicShelfRenderer": {
          "title": {"runs": [{"text": "S"}]}, "contents": [${SONG_ITEM}]
        }}]}}
      }`), '').items[0]);
      expect(a !== null).assertTrue();
      expect(a?.name).assertEqual('Song One');
      expect(a?.artist).assertEqual('Artist A');
      expect(a?.audioId).assertEqual('vid1');
      expect(a?.album).assertEqual('Album X');
      // videoId 缺失（专辑卡）映射为 null。
      const albumCard = parseYtmCreatorDetail(data(`{
        "contents": {"sectionListRenderer": {"contents": [{"musicCarouselShelfRenderer": {
          "header": {"musicCarouselShelfBasicHeaderRenderer": {"title": {"runs": [{"text": "A"}]}}},
          "contents": [{"musicTwoRowItemRenderer": {
            "title": {"runs": [{"text": "Card"}]},
            "subtitle": {"runs": [{"text": "Album"}]},
            "navigationEndpoint": {"browseEndpoint": {"browseId": "MPRE9"}}
          }}]
        }}]}}
      }`), summary('UCx', 'x')).sections[0].items[0];
      expect(ytmCreatorItemToSongItem(albumCard)).assertNull();
      // key 优先级：videoId > browseId。
      const bareItem = new YtmCreatorItem();
      bareItem.videoId = 'vid9';
      bareItem.browseId = 'MPRE8';
      expect(ytmCreatorItemKey(bareItem)).assertEqual('vid9');
      const songItem = parseYtmCreatorItemsPage(data(`{
        "contents": {"sectionListRenderer": {"contents": [{"musicShelfRenderer": {
          "title": {"runs": [{"text": "S"}]}, "contents": [${SONG_ITEM}, ${SONG_ITEM}]
        }}]}}
      }`), '').items;
      expect(songItem.length).assertEqual(2);
      expect(mergeYtmCreatorItems(songItem).length).assertEqual(1);
      expect(ytmCreatorItemKey(songItem[0])).assertEqual('vid1');
      expect(ytmCreatorItemKey(albumCard)).assertEqual('MPRE9');
    });

    it('playbackQueue_filtersUnplayableAndLocatesStart', 0, () => {
      const songs = parseYtmCreatorItemsPage(data(`{
        "contents": {"sectionListRenderer": {"contents": [{"musicShelfRenderer": {
          "title": {"runs": [{"text": "S"}]}, "contents": [${SONG_ITEM}]
        }}]}}
      }`), '').items;
      const queue = buildYtmCreatorPlaybackQueue([], songs[0]);
      expect(queue).assertNull();
      const bare = new YtmCreatorItem();
      bare.browseId = 'MPRE7';
      const playable = buildYtmCreatorPlaybackQueue([songs[0], bare], songs[0]);
      expect(playable !== null).assertTrue();
      expect(playable?.songs.length).assertEqual(1);
      expect(playable?.startIndex).assertEqual(0);
    });

    it('thumbnailUpgrade_rewritesGoogleImageParams', 0, () => {
      expect(upgradeYtmThumbnailUrl('https://yt3.ggpht.com/a=w48-h48'))
        .assertEqual('https://yt3.ggpht.com/a=w1200-h120');
      expect(upgradeYtmThumbnailUrl('https://yt3.ggpht.com/plain'))
        .assertEqual('https://yt3.ggpht.com/plain=w1200-h120');
      expect(upgradeYtmThumbnailUrl('https://i.ytimg.com/vi/v/hq720.jpg'))
        .assertEqual('https://i.ytimg.com/vi/v/hq720.jpg');
      expect(upgradeYtmThumbnailUrl('')).assertEqual('');
    });
  });
}
