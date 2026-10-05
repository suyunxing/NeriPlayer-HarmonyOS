# 安全政策（Security Policy）

## 支持的版本

只为最新发布的 Release 与 `main` 分支提供安全修复，更早的版本不再单独回移植。

| 版本 | 支持情况 |
| --- | --- |
| 最新 Release / `main` | ✅ 支持并修复 |
| 历史 Release / tag | ❌ 不再维护 |

## 报告漏洞

**请勿通过公开 Issue、PR 或讨论披露尚未修复的安全漏洞。**

请使用 GitHub 私有漏洞报告（Private Vulnerability Reporting）提交，只有仓库维护者能看到：

👉 **https://github.com/suyunxing/NeriPlayer-HarmonyOS/security/advisories/new**

报告时请尽量包含：

- 漏洞类型与实际影响（例如本地信息泄露、任意文件读写等）
- 复现步骤或最小化 PoC
- 受影响的版本 / commit
- （可选）修复思路

## 响应约定

- 收到报告后通常一周内确认；
- 严重程度与修复节奏共同评估，严重问题优先处理；
- 修复发布后会在 Security Advisory 中致谢报告者（如希望匿名请注明）。

## 范围

本项目是 HarmonyOS 平台的音乐播放器客户端。以下内容不在本项目处理范围内：

- 第三方音乐服务 / API 自身的问题（请向对应服务提供方报告）；
- 需要篡改系统或依赖已破解环境才能成立的问题；
- 社会工程、物理接触设备类攻击。

## 仓库自身的自动化防护

仓库已启用以下自动化安全机制，告警会出现在仓库的 **Security** 标签页：

- CodeQL 代码扫描（default setup）；
- Secret scanning + push protection；
- Dependabot 依赖告警与安全更新，以及 GitHub Actions 依赖的每周版本更新（配置见 `.github/dependabot.yml`；ohpm 依赖暂不在 Dependabot 支持的生态内）。
