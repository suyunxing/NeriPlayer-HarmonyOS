# NeriPlayer 移植说明（Android → HarmonyOS ASCF）

## 移植映射

| Android 模块 | HarmonyOS（ArkUI 版） | 本 ASCF 版 |
| --- | --- | --- |
| `data.model.SongItem` | `model/SongItem.ets` | `common/song.js` |
| `SongIdentity.stableKey` | `model/SongIdentity.ets` | `common/song.js:songIdentity/stableKeyOf` |
| `PlayerManager + AudioPlayerService` | `player/PlayerManager.ets`（AVPlayer） | `common/player.js`（`getBackgroundAudioManager`） |
| 网易云 weapi 签名 | `network/NeteaseCrypto.ets`（cryptoFramework） | `common/crypto.js`（纯 JS AES/RSA） |
| `NeteaseApi` | `network/NeteaseApi.ets` | `common/netease.js` |
| `BiliApi` | `network/BiliApi.ets` | `common/bili.js` |
| `YouTubeMusicApi` | `network/YouTubeMusicApi.ets` | `common/ytmusic.js` |
| `StreamResolver` | `network/StreamResolver.ets` | `common/resolver.js` |
| `LrcParser` | `lyrics/LrcParser.ets` | `common/lyric.js` |
| `SettingsRepository` 等仓库 | `data/*Repository.ets` | `common/settings|history|playlists|stats|downloads.js` |
| Compose UI | ArkUI pages | `pages/*`（hxml/js/css） |

## 关键设计

1. **稳定歌曲身份**：`<id>|<album>|<mediaUri>` 三段式 key 与 Android/桌面端保持兼容，
   歌单/历史/统计均以 stable key 存储，跨平台同步时不会因元数据变化而丢失关联。
2. **纯 JS 加密**：网易云 weapi 的 AES-128-CBC（两次）与 RSA-1024 PKCS#1 以零依赖实现，
   已用 Node `crypto` 对 AES 结果做了已知答案校验；RSA 用生成密钥对做了加解密往返验证。
3. **状态模型**：`store.js` 为全局快照 + 订阅分发（等价 AppStorage + PlayerListener），
   页面在 `onShow/onHide` 订阅/退订，迷你播放器组件由页面同步刷新。
4. **weapi IV 修正**：`0102030405060708` 是 16 个 ASCII 字节（`Buffer.from(...)`），
   不是 8 字节 hex；此前 ArkUI 移植版此处有误，本版已按官方 JS 实现修正。

## 剩余工作（待移植）

- [ ] **YouTube 流解析**：需移植 yt-dlp 的 EJS 解密引擎（signature / n 参数 / PoToken），
  或引入服务端解析代理；当前仅支持搜索。
- [ ] **本地媒体扫描**：元服务受限，无法使用 `photoAccessHelper`/`mediaLibrary`；
  如产品需要本地播放，应改为普通 App（非元服务）形态。
- [ ] **播放速度**：等待 `BackgroundAudioManager.playbackRate` 支持，或换 `InnerAudioContext`。
- [ ] **多设备/深色主题适配**：当前 UI 为深色单主题，`window` 配置支持 API 13+ 的
  `navigationBarTextStyle` 自适应，后续可按系统主题切换。
- [ ] **真实设备联调**：`has.request` 的 Referer 头、网易云反爬策略、AGC 域名白名单
  需要在真机与发布环境验证。

## 构建链版本

- DevEco Studio 6.1.1.300（SDK API 24，兼容 12）
- ASCF Support Plugin 1.0.4.306（`E:\music\ascf-support-plugin`）
- `@atomicservice/ascf-toolkit` / `-hvigor-plugin`：1.0.17（npm）
- `@atomicservice/ascfapi`：2.0.2（ohpm，`com.huawei.hms.ascfruntime` 运行时依赖）
