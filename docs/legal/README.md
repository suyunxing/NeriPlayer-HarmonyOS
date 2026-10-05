# 法律文档（母本与发布载体）

本目录是《隐私政策》与《用户协议》的**母本**（2026-10-05 起从应用内 `entry/src/main/resources/rawfile/` 迁出，应用内离线渲染代码 LegalDocPage 已删除，沿革见 `docs/hm.md` §7.22）。

## 当前发布载体：GitHub Gist（公开）

| 文档 | 公开 URL |
| --- | --- |
| 隐私政策 | <https://gist.github.com/suyunxing/fdd0a09ceef38fbcf0b8711c519eb38e> |
| 用户协议 | <https://gist.github.com/suyunxing/ff06690f25426e520ebbfee65dba6b8f> |

应用内两处入口（首启免责声明页文字链、设置 → 隐私与协议）经系统浏览器打开上述 URL，URL 常量在 `NeriPlayer-HarmonyOS/entry/src/main/ets/app/Constants.ets` 的 `LEGAL_PRIVACY_URL` / `LEGAL_AGREEMENT_URL`。

选型说明：仓库当前为 private（GitHub Free 计划下私有仓库 Pages 无法公开访问），而写进应用的链接必须公众可达，故先用 Gist 托管（公开、永久、零新增账号）。将来仓库转 public 后如换 GitHub Pages，只需改 `Constants.ets` 两个常量并更新本表；废弃的 gist 可在 GitHub 上删除。

## 修订流程

1. 直接编辑本目录下的 `.md`（保持「生效日期 / 版本」行准确）。
2. 同步发布载体（Gist）：

   ```bash
   gh gist edit fdd0a09ceef38fbcf0b8711c519eb38e -f privacy_policy.md   # 隐私政策
   gh gist edit ff06690f25426e520ebbfee65dba6b8f -f user_agreement.md   # 用户协议
   ```

3. 若属「重大政策变更」（新增权限、改变数据处理方式等），把
   `entry/src/main/ets/util/DisclaimerConsentPolicy.ets` 的 `CURRENT_DISCLAIMER_VERSION`
   加一——已同意旧版文本的安装会在下次启动重新进入合规页征询同意（应用内承诺见
   政策第十二节）。
