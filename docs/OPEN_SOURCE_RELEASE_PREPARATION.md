# 开源发布前必办任务清单（OPEN_SOURCE_RELEASE_PREPARATION）

> 2026-09-14 编制（基于当日代码级全面对比审计，审计范围：两侧源码静态审计 + 定点 grep 核实，非文档转抄）。
> **2026-09-14 执行轮**：本清单在分支 `release/open-source-prep` 上执行，各条目完成后附证据行（日期 + 改动 + 结果）。4.1（隐私政策定稿）为作者本人操作，未执行；5.2（CI 门禁）按 §6 明确解耦不阻塞。
> 本文档列出**打第一个公开发布 tag 之前必须完成**的任务。与既有两份文档的分工：
>
> - `RELEASE_CHECKLIST.md`：设备形态/UX/合规的**验证矩阵**（已做了什么、验证到什么程度）。
> - 本文档：发布前的**未完成待办**（还差什么必须补）。两者互补，做完本清单后按 `RELEASE_CHECKLIST.md` §8 的 CD 流程打 tag。
> - 完整功能对齐 Android 原版的长期 backlog 见 `ANDROID_PARITY_BACKLOG.md`，**不属于发布门槛**。
>
> 结论回顾（2026-09-14 审计）：开源发布就绪度「中」，修复 1 个法律硬阻断 + 若干文档失实后可达「高」；商业发布不可行（第三方音源逆向无法过审 + GPL-3.0 传染性 + 隐私政策草案），本清单不面向商业上架。

## 0. 完成定义（DoD）

本清单全部勾完 = 具备推 `v1.0.0`（或首个公开 tag）的条件。每项完成后在条目后追加证据行（日期 + 命令/改动 + 结果）。

---

## 1. 法律与许可证（硬阻断，最高优先级）

### 1.1 [x] 补根目录 LICENSE 文件（GPL-3.0 全文）

- **事实**：`git ls-files | grep -i license` 为空——仓库不追踪任何 LICENSE 文件。GPL-3.0 全文只存在于被 `.gitignore` 排除的 `NeriPlayer-master/` 快照里，克隆者拿到的仓库没有许可证，法律上默认「保留所有权利」，他人不能合法使用/修改/分发。
- **做法**：从 `NeriPlayer-master/LICENSE`（已核实为标准 GPL-3.0 文本）复制到仓库根 `LICENSE`，`git add` 确认入库。
- 验证：`git ls-files | grep -i license` 非空；GitHub 仓库页右侧出现 License 标识。
- **✅ 已完成（2026-09-14，分支 release/open-source-prep）**：`cp NeriPlayer-master/LICENSE ./LICENSE`，md5 `1ebbd3e34237af26da5dc08a4e440464` 与上游逐字节一致；入库后 `git ls-files | grep -i license` 命中根 `LICENSE`。

### 1.2 [x] 源码补 GPL-3.0 版权声明头

- **事实**：全工程 257 个 `.ets` 源文件中仅 1 个文件含 GPL 字样（`view/theme/SwatchData.ets` 的 MIT 数据集来源标注），无任何文件带 GPL-3.0 版权头。`CONTRIBUTING.md:36` 自家约定「复制或改写上游代码时保留 GPL-3.0 许可和来源说明」未被源码兑现。
- **做法**：至少为**从 Android 上游语义移植而来**的模块（player/download/sync/lyrics/listentogether/network 各核心文件）批量补 `SPDX-License-Identifier: GPL-3.0` + 上游 `cwuom/NeriPlayer` 来源行。完全自研文件（如 HdsSpikePanel、SwatchData）可标注自研 + GPL-3.0。用脚本批处理，避免手改 257 个文件。
- 验证：`grep -rl 'SPDX-License-Identifier\|GNU General Public' entry/src/main/ets | wc -l` 覆盖核心模块；抽查 3-5 个文件头格式。
- **✅ 已完成（2026-09-14）**：新增 `tools/add-spdx-headers.py`（入库留档），对 257 个 `.ets` 中的 256 个加头——player/download/sync/lyrics/listentogether/network 全目录 + 13 个上游语义对应的 model/data/util 文件带 `Ported from the Android upstream project NeriPlayer` 来源行，其余自研文件仅 SPDX 行；`SwatchData.ets` 保持原 MIT 数据集标注不加头（已核实该文件头注释为数据集来源声明，非 GPL 声明）。CRLF 文件按原换行符写入，仓库 `text=auto` 下统一存 LF。验证：`grep -rl SPDX-License-Identifier entry/src/main/ets | wc -l` = 256；`hvigorw assembleHap` BUILD SUCCESSFUL（47.6s）证明注释头无编译影响。

### 1.3 [x] 修正 README 中 LICENSE 链接

- **事实**：根 `README.md:16` 的 `<a href="LICENSE">` 与 `README.md:272` 的 `[GPL-3.0 License](LICENSE)` 指向不存在的文件（404）；`NeriPlayer-HarmonyOS/README.md:6` 指向 `../LICENSE`（1.1 完成后即生效，无需改）。
- **做法**：1.1 完成后链接自然修复，逐一点开验证即可。
- **✅ 已完成（2026-09-14）**：LICENSE 文件落地后，根 README 徽章链接 `LICENSE` 与协议节 `[GPL-3.0 License](LICENSE)` 均指向已存在文件；工程 README `../LICENSE` 同步生效。无需改动 README 本身。

### 1.4 [x] 应用内「关于」页来源声明核对

- **事实**：`SettingsDetailPage.ets:1457` 已展示 `GPL-3.0 · github.com/cwuom/NeriPlayer`，合规；本项仅为发布前复核，无需改动（除非 1.2 的版权头策略要求同步）。
- **✅ 已复核（2026-09-14）**：关于页来源声明原样保留；同节版本串由 `版本 1.0.0 (HarmonyOS 6.1.1 / API 24)` 更正为 `版本 1.0.0 (HarmonyOS 26 / API 26)`（见 2.3）。

## 2. README 与文档失实修正（发布门面）

### 2.1 [x] 删除 `READ_AUDIO` 权限的过时说明

- **事实**：`NeriPlayer-HarmonyOS/README.md:107`、根 `README.md:137`、根 `README.md:241`、`docs/FEATURE_MATRIX.md:29` 四处声称本地扫描依赖 `ohos.permission.READ_AUDIO`，但 `module.json5` 已不声明该权限（2026-08-25 已删），实际走 `AudioViewPicker` 免权限选择。四处改为「系统文件选择器手动选取（免权限）」。
- 证据：`module.json5` requestPermissions 仅 4 项（INTERNET / GET_NETWORK_INFO / FILE_ACCESS_PERSIST / KEEP_BACKGROUND_RUNNING）。
- **✅ 已完成（2026-09-14）**：四处全部改为「系统文件选择器手动选取（`AudioViewPicker` 免权限）」表述——根 README 功能表「本地音乐与沙箱」行、根 README「快速体验与安装」节首启说明、工程 README「运行与权限说明」第 2 条、FEATURE_MATRIX「本地媒体导入」行（并注明 READ_AUDIO 2026-08-25 已删与删除依据）。

### 2.2 [x] YTM 能力表述降级

- **事实**：根 `README.md:126` 已注明「单轨约 1 分钟」限制，表述准确；但 `README.md:65` 将 YTM 与网易云/B 站并列为「多源在线播放」主打能力，且 `YtmLoopbackStreamBridge.ets`（为绕过 AVPlayer Range 限制自研的回环代理）只被自身文件引用、未接入播放器。发布文案应将 YTM 明确标注「实验性/受限」。
- **做法**：README 功能表中 YTM 一行加「实验性」标记，明确单轨约 1 分钟限制与原因（Google 直链签名策略）。
- **✅ 已完成（2026-09-14）**：根 README 功能表 YTM 行状态由「⏳ 演进中」改为「🧪 实验性」，说明补「受 Google 直链签名限制当前单轨约 1 分钟即中断」；新「已知限制」节（3.x）实验性分组再次列出。

### 2.3 [x] 关于页 SDK 版本号漂移

- **事实**：`SettingsDetailPage.ets:1449` 显示 `版本 1.0.0 (HarmonyOS 6.1.1 / API 24)`，而工程 2026-09-07 起全量迁移 API 26（`build-profile.json5` compatibleSdkVersion 26.0.0）。改为动态读取或更新为 API 26。
- **✅ 已完成（2026-09-14）**：改为静态串 `版本 1.0.0 (HarmonyOS 26 / API 26)`（与工程 `compatibleSdkVersion: "26.0.0"` 一致；版本号本身由 CD 打 tag 时写入 `app.json5`，关于页 1.0.0 静态展示属既有形态，本次仅纠正 SDK 档位）。构建复验通过。

### 2.4 [x] `download_match_lyrics` 设置项「有开关无实现」处置

- **事实**：`SettingsDetailPage.ets:124` 有「下载完成后自动匹配歌词」开关，`SettingsRepository.ets:110` 定义 `np.download_match_lyrics` 键，但 `download/` 目录无任何消费者（2026-09-14 grep 核实）。属于文档没过时、但代码没跟上 UI 的落差。
- **做法（二选一，推荐 a）**：
  - a. 隐藏该开关，待 `ANDROID_PARITY_BACKLOG.md` §3.5 实现后再恢复；
  - b. 在开关副标题标注「实验性，暂未生效」。
- 注意：本项是**行为修正**，需走构建 + lint 收尾。
- **✅ 已完成（2026-09-14，方案 a）**：删除设置页该 ToggleRow 与对应 `@StorageProp` 状态变量（代码内留注释指向本清单 2.4 与 §3.5）；`SettingsRepository` 的键定义与默认值**保留**（未来恢复开关时旧用户偏好不丢）。`hvigorw assembleHap` BUILD SUCCESSFUL（19.8s）+ codelinter 0 error 收尾。

### 2.5 [x] `docs/FEATURE_MATRIX.md` 与当前代码状态对齐

- **事实**：除 READ_AUDIO 外（2.1），矩阵其余状态是否漂移未逐行复核（2026-09-14 审计抽查了 YTM/本地扫描两处失实）。发布前对矩阵做一次全量走查，凡与代码不符的状态行如实更新。
- 验证：抽查矩阵中 5+ 个「已闭环」行，在代码中找到对应实现；发现失实即修正或降级状态。
- **✅ 已完成（2026-09-14，子代理抽查 8 项）**：① 网易云 trackIds 差量补全（`NeteaseApi.ets:422-448`，无 500 截断）属实；② B 站收藏夹 6 页并发分页（`BiliApi.ets:376-396`，`IMPORT_CAP` 已删）属实；③ 多源自动换源（`StreamResolver.ets:59-123` + `PlayerManager.ets:1414` 接线）属实；④ 下载引擎 Range/If-Range/HLS checkpoint（`HttpStreamDownloader.ets:113-118`、`DownloadEngine.ets:304,424-477`）属实；⑤ GitHub/WebDAV 双传输真实 HTTP 实现（`OhosGhExecutor.ets`/`OhosWebDavExecutor.ets`）属实；⑥ AVSession `setLaunchAbility`/`lyric`/`singleLyricText`（`AVSessionManager.ets:124,259,279,282`）属实；⑦ 语言切换/YouTube 登录占位现状与「已知限制」一致；⑧ `build-profile.json5` compatibleSdkVersion `"26.0.0"`。**8/8 属实，0 失实**——矩阵本轮无其他降级行需要修正（READ_AUDIO 一处已由 2.1 修正）。

## 3. 占位功能与能力限制的发布说明（不阻塞，但必须如实列出）

发布（Release 正文或 README「已知限制」节）必须如实列出以下内容，避免用户误以为可用：

### 3.1 [x] 「设置页功能占位」清单固定化

`RELEASE_CHECKLIST.md` §6 已登记三处「点击只弹 toast」的占位，其中**下载目录选择已实现**（`SettingsDetailPage.ets:238` 起，Picker + 持久授权，旧记录过时）；当前真实占位为：

- 语言切换（`SettingsDetailPage.ets:1169`）：仅简体中文，其他语言「待移植」；
- YouTube 登录（`SettingsDetailPage.ets:1296-1298`）：「Cookie 会话待移植」；
- 网易云换源无 UI 标记（`StreamResolver.ets:88`）：底层已实现并运行，但用户无法感知当前音源已切换到 B 站。

- **✅ 已完成（2026-09-14）**：根 README 新增「⚠️ 已知限制 / Known Limitations」节，「设置页占位」分组固定化以上三项（子代理复核 `SettingsDetailPage.ets:1166/:1293-1295` 占位现状仍准确）。Release 正文打 tag 时按同口径复制。

### 3.2 [x] 平台限制类「永久缺失」能力声明

以下能力因 HarmonyOS 平台开放度**不可移植**（发布文案注明即可，属产品定位差异而非缺陷）：

- USB DAC 独占输出 / Bit-Perfect（无公开 USB DDK）；系统级桌面悬浮歌词（无悬浮窗权限）；状态栏歌词（无对应 API）；均衡器/响度归一化/声道平衡（AVPlayer 无 DSP 管线）；播放页音频律动背景（同前）。
- 与 Android 原版行为差异详见 `ANDROID_PARITY_BACKLOG.md` §9。

- **✅ 已完成（2026-09-14）**：README「已知限制」节「平台限制」分组逐项列出（桌面歌词一行按 M102 spike 最新结论表述：API 已打通至系统服务层、图形上屏待真机验证，当前为应用内悬浮条降级实现）。

### 3.3 [x] YTM 播放受限的如实描述

见 2.2。`RELEASE_CHECKLIST.md` §5.3 已有 YTM 条款风险记录（ToS 明确禁止），发布说明合并表述。

- **✅ 已完成（2026-09-14）**：README 功能表（2.2）+「已知限制」实验性分组双处表述。

## 4. 隐私与合规收尾

### 4.1 [x] 隐私政策定稿与「版本变更重新征同意」机制

- **事实**：应用内隐私政策与用户协议为 `v1.0.0-draft` 草案（「草案 · 待作者复核」横幅、生效日期待定，`string.json` 内嵌文案）。开源发布（GitHub Release 分发）不是应用市场上架，**不强制**要求定稿；但发布即面向公众，建议作者以自己的名义定稿 v1.0.0，替换 draft 横幅。
- **2026-09-14 文案载体迁移（本清单执行轮）**：两份法律长文从 `string.json` 单行内嵌迁移至 `NeriPlayer-HarmonyOS/entry/src/main/resources/rawfile/privacy_policy.md` / `user_agreement.md`（可读 Markdown，`LegalDocPage` 经 `resourceManager.getRawFileContent` 异步读入；标题与 draft 横幅仍在 string.json）。**定稿操作由此简化为：直接编辑 rawfile 下两个 .md**（填生效日期、去 `-draft`、按作者名义复核措辞），不再需要改 JSON 转义文本；将来上 AGC 时同一份 .md 复制到后台上传。定稿后同步删除 string.json 的 `legal_draft_notice` 键与 `LegalDocPage.ets` 中对它的引用（约一行）。
- **2026-09-20 定稿完成**：commit d3eadb3——两份正文正式定稿 `v1.0.0`、生效日期 2026-09-20、draft 横幅与 `legal_draft_notice` 已除。
- **2026-10-05 载体再迁移（用户指令「换用标准化隐私声明托管」）**：两份 .md 自应用内 `rawfile/` 迁至仓库根 `docs/legal/`（母本），并以**公开 Gist** 托管（隐私政策 <https://gist.github.com/suyunxing/fdd0a09ceef38fbcf0b8711c519eb38e>、用户协议 <https://gist.github.com/suyunxing/ff06690f25426e520ebbfee65dba6b8f>）；应用内离线渲染页 `LegalDocPage`、`LEGAL_DOC` 路由与两个标题字符串键删除，首启文字链与「设置→隐私与协议」改系统浏览器打开 Gist 链接（`Constants.LEGAL_*_URL`）。将来上 AGC 时后台隐私政策 URL 直接填 Gist 链接，与应用内同源一致。修订流程见 `docs/legal/README.md`，沿革 `hm.md` §7.22。
- 另登记：文案承诺的「重大政策变更重新征同意」代码未实现（仍是布尔标记 `KEY_DISCLAIMER_ACCEPTED`，改版本号不重新弹窗）。开源发布不阻塞；若未来上架 AGC 则为必办（`RELEASE_CHECKLIST.md` §5.5 已登记）。
- **本项性质**：文案定稿（作者本人操作），agent 不代笔最终法律文案。
- **✅ 定稿与载体均已就位**（2026-09-20 作者定稿 v1.0.0；2026-10-05 载体迁公开 Gist，见上）。

### 4.2 [ ] 权限 reason 补全（低优先级，可延后）

- **事实**：4 个权限中仅 `KEEP_BACKGROUND_RUNNING` 配了 reason；3 个 normal 级无 reason 不违反规范（normal 级不展示给用户），此项为锦上添花，不阻塞。

## 5. 工程与 CI 收尾

### 5.1 [x] 发布 tag 前的验证基线

打 tag 前在服务器跑一轮完整验证并留档（结果记入本文档）：

- `hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon` → BUILD SUCCESSFUL；
- `codelinter`（以改动文件 0 error 为准，全量存量 5 个 await-thenable error 属工具版本漂移非回归）；
- 单测：Linux 侧 `hvigorw test` 只作编译级验证（执行阶段挂死属环境限制），真实通过/失败计数须 Windows 工作站执行并读取 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`；服务器无法执行的标注「未验证」。

- **✅ 已完成（2026-09-14，服务器 Ubuntu 24.04 + CLT 26.0.0.105，分支 release/open-source-prep 全部改动就位后）**：
  - 构建：`hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon` → **BUILD SUCCESSFUL in 19 s 806 ms**（版权头 257 文件改后首跑 47.6s 亦通过）；
  - 静态：`codelinter ./entry` → **Defects 25 / Errors 0 / Warns 23 / Suggestions 2**，与本轮改动前基线（25/0/23/2）持平，改动文件零新增（注：本轮工具版本下未复现旧基线的 5 个 await-thenable error，warn 23+2 suggestion 与 2026-08-27 基线 26 warn 相比属报告口径漂移，无 error）；
  - 单测：Linux 侧 `hvigorw test` 编译阶段 0 error（执行阶段环境性挂死由 timeout 截断，属已知平台限制）——**真实通过/失败计数未验证**，须 Windows 工作站执行同命令后读 `test_result.txt`。

### 5.2 [ ] CI 单测门禁修复（可与发布解耦，不阻塞打 tag）

- **事实**：`harmonyos-ci.yml` 的单测步骤 `continue-on-error: true` + 5 分钟超时（Linux hypium 挂死问题），测试失败不阻断 CI；且 CI 无 codelinter 步骤。
- 本项不阻塞开源发布（GitHub 上开源项目 CI 红不违法），但建议发布后尽快收口：如把「编译级验证 + 改动文件 lint」做成硬门禁，单测计数交由 Windows 工作站例行执行。
- **⏸ 按计划不在本轮执行**（§6 明确解耦，留待发布后迭代）。

### 5.3 [x] 发布物与签名红线复核（无需改动，确认即可）

- `build-profile.json5` `signingConfigs: []` 保持为空；Release 产物永远是 unsigned HAP + `SHA256SUMS.txt` + `INSTALL.md`（`RELEASE_CHECKLIST.md` §8 流程）。签名材料/口令/UDID 不进 GitHub。**已合规，发布时确认未破坏即可。**
- **✅ 已复核（2026-09-14）**：`signingConfigs: []` 确认为空；`git ls-files` 无任何 `.p12/.cer/.p7b/.csr/signing//local.properties` 命中（.gitignore 规则 `**/signing/`、`**/local.properties` 在位）；`harmonyos-release.yml` 零处引用 `secrets.*`。红线未破坏。

---

## 6. 明确不做的事（避免范围蔓延）

- **不追求 Android 功能全量对齐**（均衡器/USB DAC/悬浮歌词等平台限制项，及工程缺口项）——那是 `ANDROID_PARITY_BACKLOG.md` 的范围，发布不等它们。
- **不面向 AppGallery 商业上架**：第三方音源逆向取流无法过版权审查、GPL-3.0 排除闭源商业化、隐私政策未定稿。开源发布定位为「GPL-3.0 研究项目」。
- **不做大规模 i18n 抽取**（956 处中文硬编码）：开源发布不阻塞，归入 backlog。

## 7. 任务汇总（按依赖排序）

> **2026-09-14 执行轮后更新**：除 4.1（作者本人定稿，开源发布不阻塞）与 5.2（明确解耦）外全部完成。执行分支 `release/open-source-prep`。

| # | 任务 | 性质 | 工作量 | 阻塞性 | 状态 |
|---|---|---|---|---|---|
| 1.1 | 根目录补 LICENSE | 法律 | 10 分钟 | **硬阻断** | ✅ 完成 |
| 1.2 | 源码 GPL 版权头 | 法律 | 半天（脚本批处理） | **硬阻断** | ✅ 完成（256/257，脚本入库 `tools/add-spdx-headers.py`） |
| 1.3 | README LICENSE 链接 | 文档 | 5 分钟 | 高（随 1.1） | ✅ 完成（随 1.1 生效） |
| 1.4 | 关于页来源声明核对 | 文档 | 5 分钟 | 低 | ✅ 复核通过 |
| 2.1 | 删 READ_AUDIO 失实说明 | 文档 | 15 分钟 | 高 | ✅ 完成（4 处） |
| 2.2 | YTM 表述降级 | 文档 | 10 分钟 | 高 | ✅ 完成 |
| 2.3 | 关于页版本号 | 代码 | 30 分钟 | 中 | ✅ 完成（→ HarmonyOS 26 / API 26） |
| 2.4 | download_match_lyrics 开关处置 | 代码 | 30 分钟 | 中 | ✅ 完成（方案 a 隐藏） |
| 2.5 | FEATURE_MATRIX 全量走查 | 文档 | 1-2 小时 | 中 | ✅ 完成（抽查 8/8 属实） |
| 3.x | 已知限制清单固定化 | 文档 | 30 分钟 | 中 | ✅ 完成（README 新增「已知限制」节） |
| 4.1 | 隐私政策定稿 | 文案 | 作者本人 | 低（开源不阻塞） | ✅ 完成（2026-09-20 定稿 v1.0.0；2026-10-05 载体迁公开 Gist；版本门控 2026-09-22 已实现） |
| 4.2 | 权限 reason 补全 | 工程 | 低 | 低 | ⏸ 可延后 |
| 5.1 | 发布前验证基线 | 验证 | 1 小时 | 高 | ✅ 完成（构建/lint 通过；单测计数待 Windows） |
| 5.2 | CI 门禁收口 | 工程 | 后续迭代 | 低 | ⏸ 明确解耦 |
| 5.3 | 签名红线复核 | 工程 | 5 分钟 | 高 | ✅ 复核通过 |

**结论**：两个法律硬阻断（1.1/1.2）已清除，文档失实已修正，验证基线已留档。剩余未办项（4.1 隐私政策定稿属作者本人操作、4.2 锦上添花、5.2 发布后迭代）均不阻塞打 tag。**待 Windows 工作站补跑单测计数后，即具备推 `v1.0.0` 的条件**（打 tag 本身须用户明确发起，按 `RELEASE_CHECKLIST.md` §8 CD 流程执行）。
