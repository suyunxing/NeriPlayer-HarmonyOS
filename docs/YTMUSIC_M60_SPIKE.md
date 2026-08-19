# M6.0 Spike：YouTube Music 取流现状探测与 D2 决策记录

> 日期：2026-08-19。执行者：GLM-5.3（ZCode agent）。本文档是 M6.0 的产出物：探针实测数据 + ArkWeb JS 运行时能力调研 + D2 决策修正。结论已同步 `PORTING_EXECUTION_PLAN.md` §5/§6。

## 1. 探针实测（ytmusic_api_probe.py）

### 1.1 环境与命令

- 脚本：`NeriPlayer-master/tools_pub/ytmusic_api_probe.py`（只读快照，未改动）。
- 环境：Windows 本机，Python 3.14.5 + requests 2.34.2（pip --user 安装），node v24.15.0。
- **网络**：直连 `music.youtube.com`/`www.youtube.com`/`youtubei.googleapis.com` 全部超时（大陆网络）；本机 `127.0.0.1:7897` 有可用代理（Clash 类，出口 IP 146.70.117.114），经 `HTTPS_PROXY=http://127.0.0.1:7897` 环境变量走代理后全部可达。
- Cookie：无 YouTube 登录 cookie，用最小匿名 cookie 文件（仅 `CONSENT=YES+...`）通过脚本的非空校验。脚本默认 cookie 路径是上游作者机器路径，必须 `--cookie-file` 显式指定。
- 跳过项：`--skip-webpo`（nodriver 未安装且无登录 cookie）、`--skip-download-probe`（pydeps 未安装 yt-dlp）；IOS 直出 URL 的可下载性改用 curl Range 请求等价验证（见 §1.3）。
- 报告与 cookie 均输出在仓外 `D:\HarmonyOS\tmp-m60\`（探针报告含 googlevideo URL token，6 小时过期且属敏感值，不入库；本文档只记录脱敏摘要）。

```text
python tools_pub/ytmusic_api_probe.py \
  --cookie-file <anon-cookie.txt> --skip-webpo --skip-download-probe \
  [--video-ids JGwWNGJdvx8,4NRXx6U8ABQ,dQw4w9WgXcQ] \
  --report <report.json>
```

### 1.2 结果矩阵（2026-08-19 19:43，区域 US/en-US，匿名）

bootstrap（抓 music.youtube.com 首页）：**成功**。`INNERTUBE_API_KEY` 可得、visitorData 可得、`signatureTimestamp=20681`、player.js URL 可得、`WEB_REMIX` 版本 `1.20260811.15.00`、`logged_in=false`。

player API 回放（`youtubei/v1/player`，探针内置 client 模板）：

| 视频 | client | playability | 音频格式 | 直连 URL | signatureCipher |
| --- | --- | --- | --- | --- | --- |
| fbvvS8e1KgI | tvhtml5 7.20260114.12.00 | OK | 4 | **0（被剥离）** | 0 |
| fbvvS8e1KgI | tvhtml5_downgraded 5.20260114 | OK | 4 | 0 | **4（全部需解签）** |
| fbvvS8e1KgI | **ios 21.03.2** | OK | 5 | **5（直出）** | **0** |
| JGwWNGJdvx8 / 4NRXx6U8ABQ / dQw4w9WgXcQ | 同上三行模式 | 全 OK | 同上 | 同上 | 同上 |
| o2x1DBRCZJg（受限视频） | 全部 | LOGIN_REQUIRED | 0 | 0 | 0（"This video is private"/"Please sign in"） |

- 最佳音频一致为 itag 251（audio/webm; opus，~140kbps，AUDIO_QUALITY_MEDIUM），次选 itag 140（audio/mp4; AAC ~130kbps）；contentLength/approxDurationMs 均完整给出。
- tvhtml5 完整版：4 个格式既无 `url` 也无 `signatureCipher`——服务端 URL 剥离，该 client 当前**不可用**（Android 端仍把它列为回退 2，依赖 `PlayerClientHealthTracker` 压制，印证 client 可用性会漂移）。
- tvhtml5_downgraded（降级版本号 5.20260114 + 简化 UA）：格式齐全但全部 `signatureCipher`，需要 JS 解签才能用。
- **ios 21.03.2：全部视频匿名直出无 cipher 的 googlevideo URL，无需 PoToken。**

### 1.3 IOS 直出 URL 下载验证

对 fbvvS8e1KgI 的 itag 251 URL 执行 `curl -r 0-65535`（经代理）：**HTTP 206，65,536 字节，content-type audio/webm**。URL `expire` 参数为签发后约 21,540 秒（≈6 小时，标准 innertube 直链寿命）。

### 1.4 未执行项（如实记录）

- webpo 探测（nodriver mint GVS PoToken）：未装依赖且无登录 cookie，未跑。主路径决策不依赖它。
- yt-dlp 全链下载探测：未装 pydeps，未跑；IOS URL 可下载性已由 curl Range 等价覆盖。
- 登录态（Cookie/HAR 模板）链路：`web_remix_official` profile 需 HAR 模板，无登录环境未跑。待用户提供 cookie 后可复跑。
- 模拟器/真机网络下的复测：模拟器共享主机网络栈，主机系统代理关闭时 YouTube 不可达（实测直连超时）。**M6.5 验收需用户开启 TUN/系统级代理**，否则 YTM 包括现有搜索在内的全部真网测试都无法进行。

### 1.5 M6.1 复测补充（2026-08-19 晚，实现收尾时）

实现 `network/ytm/` 期间在主机重跑探针 + 手写矩阵实验，两个新事实：

1. **IOS 直出窗口仍开**：fbvvS8e1KgI IOS 21.03.2 匿名 player `OK`、5 音频格式全部 direct URL 零 cipher（itag 251 webm ~140k / 140 mp4 ~130k / 250 / 249），与 §1.2 一致；`web_remix_official` 因无 HAR 模板在探针汇总里 fail（与本次无关）。
2. **googlevideo Range 策略与 UA 绑定（新发现）**：探针这次对 direct URL 的三段 range 探测 start 206 / mid、tail 403（spike 时只测过 start 206，未暴露）。矩阵实验（同一 URL，3s 间隔顺序请求）定位根因：
   | 请求 | IOS UA | Web UA / 无 UA |
   |---|---|---|
   | `Range: bytes=0-65535`（可重复） | **206** | 206 |
   | `Range: bytes=0-` / 无 Range 纯 GET | **403** | 206 |
   | `Range: bytes=N-…`（任意中段/尾部，开区间或闭区间） | **403** | **206** |

   即 googlevideo 对 IOS 客户端 UA 只放行 iOS 原生渐进下载形态（bytes=0-N 闭区间），其余一律 403；非 IOS UA 无此限制。**对鸿蒙端口无影响**：IOS UA 仅用于 player API 取 URL；AVPlayer 播放与 HttpStreamDownloader 下载均以各自默认 UA（非 IOS UA）拉流，任意 Range（含 seek/断点续传）按矩阵右列 206。此结论已作为 M6.1 证据记入 PORTING_EXECUTION_PLAN §6。
3. bootstrap 页面改版：`"VISITOR_DATA":"…"` 不再出现（变为 `"EOM_VISITOR_DATA":"…"`），`"STS":n` 引号形式消失；抽不到 visitor/STS 时省略字段即可（实测 visitor 为空的 IOS player 请求仍 OK）。`YtmPlayerParser.parseYtmBootstrapHtml` 已按此适配（EOM 兜底 + STS 双键名 + 字段可省）。

## 2. Android 侧架构事实（Explore 快照调研）

来源：`NeriPlayer-master/app/src/main/java/moe/ouom/neriplayer/core/api/youtube/YouTubeMusicPlaybackRepository.kt` 等，行号见引文。

1. player 回退链（`playerClientProfiles()` :4317-4349）= **WEB_REMIX → TVHTML5 → TVHTML5 downgraded**；ANDROID_MUSIC 因需要 OAuth 被显式排除（:4346）；**没有 IOS client 参与 player API**——IOS 仅在流下载阶段作为 UA 选择维度（`YouTubeMusicSupport.kt` :413-420，且注释明确「ANDROID_MUSIC/TVHTML5/IOS 等直链不需要 pot」）。
2. direct URL 本来就优先：`resolveFormatUrl` :932-983 第一步读 `format.url`，非空直接用（只再处理 n 参数），空才走 signatureCipher 分支。
3. EJS solver（`YouTubeEjsChallengeSolver`）不按 client 门控，仅在响应实际含 cipher/n 时触发（NewPipe 与 EJS 赛跑取先）；PoToken（`YouTubeWebPoTokenProvider`）严格仅服务 WEB_REMIX。
4. client 健康追踪 `PlayerClientHealthTracker`（:280-325）：连续失败 3 次压制 30 分钟，全压制则原样放行。
5. 搜索用 WEB_REMIX（`buildMusicContext` :2952-2976）。

**推论**：Android 需要 EJS solver/PoToken 全家桶，是因为其 client 链全部落在 web/tv 系（必产 cipher）。探针证明当前 IOS client 匿名直出可下载 URL——换主路径即可让 solver 降级为兜底。

## 3. ArkWeb 执行外部 JS 能力调研（doc-researcher，2026-08-19）

结论基于 OpenHarmony 官方文档（master 分支，接口覆盖 API 24）：

1. **离屏 Web 可行且有官方方案**：`web-offline-mode.md`——`@Builder`+`BuilderNode` 创建不挂视图树的 Web 组件 + 独立 `WebviewController`，需要 UIContext（`loadContent` 后任意时机）。隐藏/遮盖/0 尺寸也可承载。URL: gitee.com/openharmony/docs `/blob/master/zh-cn/application-dev/web/web-offline-mode.md`。
2. **时序**：`onControllerAttached`（未加载页面，可 loadUrl($rawfile)+registerJavaScriptProxy）→ onPageBegin → onPageEnd；**runJavaScript/runJavaScriptExt 官方明文要求 loadUrl 完成后（onPageEnd）调用**；未绑定时调用抛 17100001，绑定但未加载完则静默在旧上下文执行（返 null）。URL: `.../web/web-event-sequence.md`、`.../faqs/faqs-arkui-web.md`。
3. **资源开销**：单 Web 组件约 **200MB** 内存 + 渲染进程常驻（全部 Web 组件销毁才终止）；实例 >10 系统回收后台数据；销毁重建不被建议，官方推荐复用（闲置 `loadUrl('about:blank')`）；`setWebDestroyMode(FAST_MODE)`（20+）可立即释放 JS/渲染上下文。
4. **消息通道**：`runJavaScriptExt` 返回 JsMessageExt（STRING/NUMBER/BOOLEAN/ARRAY/ARRAY_BUFFER），入参支持 ArrayBuffer（几百 KB solver JS 可注入）；Promise 包装的异步计算可回传；`createWebMessagePorts` 双端口推送（仅 string/ArrayBuffer）。
5. **替代运行时**：ArkTS 禁 eval（`arkts-limited-stdlib`）；官方 JSVM（capi-jsvm，API 11+，仅 C/C++ 交互，须 NAPI 封装，带 JIT/快照/codecache）是轻量正道；三方 `third_party_quickjs` 仅为源码 vendoring，成熟度低。
6. **后台行为**：`onInactive()` 不暂停 JavaScript（暂停需 `pauseAllTimers()`，12+）；退后台渲染子进程可能被系统回收（`onRenderExited` 恢复）；后台定时器降频无官方量化——周期性跑 solver 的后台可靠性需真机实测。

**评估**：方案 A 技术可行，但 200MB 常驻对播放器偏重，且 Android 的 solver 场景（偶发解签）用「按需创建→用完 FAST_MODE 销毁」可以摊薄；既然主路径已不需要 solver，A 的实施优先级进一步下降。

## 4. D2 决策（修正案）

> 原 D2（2026-08-16）：「优先方案 A：ArkWeb 离屏加载 yt.solver；备选 B：NAPI QuickJS」。

**修正（2026-08-19，依据本 spike）**：

1. **M6 主路径 = IOS client 直连取流，零 JS 运行时依赖**：`youtubei/v1/player` 以 IOS client 上下文（21.03.2 起，版本号集中管理）匿名回放 → direct URL 优先（对齐 Android `resolveFormatUrl` 语义）→ itag 251/140 音质映射 → AVPlayer 播放。搜索维持 WEB_REMIX（现状）。URL 6 小时过期按短缓存处理。
2. **兜底链**：IOS 失败/受限 → tvhtml5_downgraded（响应含 signatureCipher，**当前无法解签，明确报错「需解签兜底未实现」**）→ （可选增强）WEB_REMIX+登录。client 健康追踪对齐 `PlayerClientHealthTracker` 语义；IOS 版本漂移用降级版本号重试（参考 tvhtml5_downgraded 技巧）。
3. **方案 A（ArkWeb 离屏 EJS solver）降级为 M6.3 可选兜底**：仅当 M6.2 上线后实测 tvhtml5_downgraded 兜底命中率高（IOS 被风控/要求 PoToken 时）才实施；实现按 §3 调研结论（onControllerAttached 加载 $rawfile + onPageEnd 后 runJavaScriptExt，单实例、按需创建 FAST_MODE 销毁）。方案 B（NAPI QuickJS）搁置；若未来需要常驻 JS 运行时优先评估官方 JSVM-NAPI。
4. **M6.4 登录（WebView cookie 导出）天然仍需 Web 组件**，与本次决策不冲突。

**风险登记**：
- YouTube 对未登录 client 的 PoToken 政策随时收紧，IOS 直出窗口（当前 2026-08 有效）可能关闭——兜底链与 solver 保留即是应对；FEATURE_MATRIX 不提前承诺。
- 鸿蒙设备网络可达性是用户环境前提（YouTube 大陆不可达），M6.5 验收依赖代理环境，文档如实标注。
- 探针样本为 4 个公开音乐视频 + 1 个受限视频；年龄限制/地区限制等边缘 playability 形态未覆盖，M6.2 落地时补错误分类。

## 5. 重跑指引

```powershell
# 前提：本机代理可用（如 127.0.0.1:7897）；Python 3.x + requests
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
Set-Content -Path <anon-cookie.txt> -Value 'CONSENT=YES+cb.20210328-17-p0.en+FX+419' -NoNewline
python NeriPlayer-master/tools_pub/ytmusic_api_probe.py `
  --cookie-file <anon-cookie.txt> --skip-webpo --skip-download-probe `
  --video-ids <id1,id2,...> --report <out.json>
# 登录态全链（webpo/yt-dlp 下载探测）需另备：登录 cookie 文件、HAR 模板、
# pydeps（nodriver/yt_dlp/yt_dlp_ejs/getpot_wpc）——本次未搭建。
```
