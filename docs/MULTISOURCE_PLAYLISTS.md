# 合并歌单与多来源同步 / Merged playlists and multiple sources

## 用法 / Usage

- 打开内部歌单，在菜单中选择“合并其他歌单”，勾选要加入的歌单。歌曲去重后加入当前歌单，原歌单仍保留；已有来源绑定也会一起合并。
- 从网易云歌单或 B 站收藏夹导入时，选择新建歌单或已有内部歌单。同一个内部歌单可接收两个 B 站收藏夹和一个网易云歌单。
- 一次性导入只加入本次歌曲。打开持续同步选项会绑定该外部来源，默认仅追加；设置页可继续使用跟随远端或仅追加模式。
- 在内部歌单详情或设置中的歌单同步页查看全部来源，逐项暂停、立即同步、重置跳过记录或解绑。解绑保留目前歌曲。

Open an internal playlist and use **Merge other playlists** to select the originals to retain. External imports can create a playlist or add to an existing one. Continuous imports bind each source independently; one-shot imports remain manual entries. Each source has its own enable, sync, reset and unbind controls.

## 数据规则 / Data rules

1. 来源身份使用 `platform channel:remoteId`，区分同一平台的多个收藏夹，不按平台混为一个来源。
2. 每个来源保存自己拥有的歌曲和跳过记录。跟随远端模式只移除该来源独占且没有手动保留的歌曲；另一来源也拥有的歌曲留在歌单中。
3. 手动添加与一次性导入的歌曲保留为手动成员；同一稳定键只显示一首，已有歌曲的自定义名称、歌手与封面保留。不同平台的不同稳定键不做歌名猜测去重。
4. 手动删除对所有拥有该歌曲的来源记入跳过记录；撤销或显式重新添加清除跳过记录。
5. 解绑将其已存在歌曲转为手动成员。合并保留原歌单，重复来源不重复绑定；显式合入的可见歌曲可解除目标歌单的对应跳过记录。
6. 每次网络请求在开始时记录绑定代次，落盘前在仓库写锁内核对当前绑定和启用状态，避免解绑或停用后的旧响应写回。
7. 旧 `syncSource` 自动读取为单来源，仍保留首项兼容字段；新的 `syncSources`、来源归属和手动归属在本地快照中保存。稳定歌曲键、GitHub/WebDAV 的共享备份格式与平台取流接口不变。
8. 跨设备共享歌曲列表，但绑定配置只留在各自设备。应用共享快照时以写锁内最新本地绑定为准，避免恢复已经解绑的来源。
9. 外部适配器返回空列表可能代表平台接口出错，因此保持原有空快照保护：网络同步不凭空列表清空歌单。纯归属策略支持权威空快照；真实空收藏夹确认仍待平台适配器补充权威证明。

Each source owns an independent membership set. Shared/manual songs survive removal by another source; explicit deletion records skips for all owners. Bindings remain device-local and are retained during shared-snapshot restoration. Legacy single bindings and existing song identities remain readable. Empty network responses retain current songs rather than being treated as authoritative deletion.

## 实现入口 / Implementation

- `NeriPlayer-HarmonyOS/entry/src/main/ets/model/Playlist.ets`: local schema and legacy compatibility.
- `NeriPlayer-HarmonyOS/entry/src/main/ets/sourcesync/SourceSyncOwnership.ets`: ownership, removal, manual preservation and merge rules.
- `NeriPlayer-HarmonyOS/entry/src/main/ets/sourcesync/SourceSyncRunner.ets`: independently testable source orchestration and failure isolation.
- `NeriPlayer-HarmonyOS/entry/src/main/ets/data/LocalPlaylistRepository.ets`: serialized persistence and stale-response checks.
- `NeriPlayer-HarmonyOS/entry/src/main/ets/sync/SyncPlaylistRestore.ets`: shared-snapshot conversion preserving local sources and files.
- `NeriPlayer-HarmonyOS/entry/src/main/ets/view/components/PlaylistImportDialog.ets`, `PlaylistMergeDialog.ets`, `PlaylistSourcesPanel.ets`: reusable UI controls.

## 复测 / Verification

From the repository root:

```sh
node tools/run-playlist-regressions.cjs
```

Uses the installed TypeScript compiler (`typescript` or the configured DevEco toolchain); set `NERIPLAYER_TYPESCRIPT_PATH` if auto-discovery has no matching compiler. The runner executes the real production model/policy/orchestration code with explicitly listed native boundary fakes and Hypium-compatible Node assertions. It complements, rather than replaces, ArkTS compilation and device/network tests.

官方构建在 `NeriPlayer-HarmonyOS/` 中执行：

```sh
devecocli build --product default --modules entry@default --build-mode debug --assemble-type assembleHap
hvigorw test --mode module -p product=default -p buildMode=debug --no-daemon
devecocli check lint
```

2026-11-17 最终验证（Windows，DevEco Studio 26.0.0.865 / SDK 26.0.0）：

- Node 业务回归 **89/89** 通过，含多来源归属、真实仓库读写替身、重复导入、合并、解绑后旧响应隔离、跨设备恢复、旧快照、封面与稳定键；这是实际断言执行，不是仅编译。
- 官方 `hvigorw test -p module=entry -p coverage=true -p scope=MultiSourcePlaylist,SourceSyncCoordinator,SyncPlaylistRestore,PlaylistImportActions,SourceSync,PlaylistMerge,PlaylistDisplayCover,SongIdentitySha256`：**76/76** 通过，Failure 0 / Error 0 / Ignore 0；其中本次新增测试 39 项，直接相关旧行为 37 项。
- `devecocli build --product default --modules entry@default --build-mode debug --assemble-type assembleHap`：**BUILD SUCCESSFUL in 29 s 556 ms**，33 tasks（26 executed / 7 up-to-date）。
- `devecocli check lint --format json`：Errors **0** / Warnings **64** / Suggestions **1**，报告已解析，不仅核对退出码。
- `git diff --check`：通过。
- 首轮全项目测试实际执行 1366 项，Pass 1323 / Failure 40 / Error 3，**不是全项目全绿**。其中新增的一项编号替身导致的失败，已通过可注入的随机编号边界修正并在上述官方定向测试复核；其余失败没有做改动前基线对照，不归因为本次改动或已知存量问题。
- 日志与首轮完整报告集中在 `NeriPlayer-HarmonyOS/.cache/multisource-validation/`，最终证据为 `node-regressions-complete.log`、`scoped-test-result.txt`、`debug-build-complete.log`、`lint-complete.json` 和 `full-test-first-result.txt`。

Final verification: Node 89/89, official scoped Local Test 76/76, debug build successful, lint 0 errors (64 warnings / 1 suggestion). The first whole-project run had failures and is retained as such; no clean-baseline attribution is claimed.

当前没有已连接设备；真实网易云/B站账号、翻页、冷启动持久化以及新界面操作与多尺寸截图仍需设备验证。未修改权限、版本号、签名材料或 Android 参照目录。
