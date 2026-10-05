// SPDX-License-Identifier: GPL-3.0

import { webview } from '@kit.ArkWeb';
import { Logger } from '../../app/Logger';
import { Theme } from '../Theme';
import { Router } from '../Router';
import { NeteaseCookieRepository } from '../../data/auth/NeteaseCookieRepository';
import {
  NETEASE_WEB_LOGIN_URL,
  NETEASE_WEB_COOKIE_FETCH_URLS,
  mergeCookieHeaderTexts,
  isNeteaseWebLoginComplete,
  isAllowedNeteaseLoginNavigation,
  sanitizeUrlForLog
} from '../../data/auth/NeteaseWebLogin';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP } from '../components/HdsSubPage';

const POLL_INTERVAL_MS: number = 1500;
/** 每次页面加载最多转发多少条页面 console 到应用日志（防页面脚本刷屏）。 */
const CONSOLE_LOG_CAP_PER_PAGE: number = 10;

/**
 * 网易云网页登录：内嵌 ArkWeb 打开官方 music.163.com 登录页（短信/扫码/
 * 密码/滑块全部由官方页面在真实浏览器上下文里自理）。这是 2026 验证码登录
 * 被风控收紧后社区的稳定登录路径（go-musicfox 在协议方案被关后合入的终态
 * 方案即 WebView 登录；本工程 Bilibili 登录同款）。完成检测轮询 WebView
 * Cookie 池，非空 MUSIC_U 即收割快照交 NeteaseCookieRepository 校验落库；
 * 进入前清空 Cookie 池防止上次会话残留误判，主框架导航限制在网易云域。
 */
@Component
export struct NeteaseWebLoginPage {
  /** 状态栏避让（util/WindowMetrics.ets 发布）；Web 内容从标题栏下沿起。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pollTimer: number = -1;
  private hasReturned: boolean = false;
  /** 当前页面加载已转发的 console 条数（onPageBegin 时清零）。 */
  private consoleLinesLogged: number = 0;

  aboutToAppear(): void {
    // 静态 Cookie 管理器先于 Web 创建调用：清空整个 WebView Cookie 池，防
    // 上次（例如已在网页里登录过）的 MUSIC_U 残留被误判为新登录完成。
    webview.WebCookieManager.clearAllCookiesSync();
    webview.WebCookieManager.putAcceptCookieEnabled(true);
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval((): void => {
      this.captureIfLoggedIn('timer');
    }, POLL_INTERVAL_MS);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /** 抓取网易云域 Cookie 做完成判定；命中即落库返回（幂等防重入）。 */
  private captureIfLoggedIn(reason: string): void {
    if (this.hasReturned) {
      return;
    }
    const texts: string[] = [];
    try {
      for (const url of NETEASE_WEB_COOKIE_FETCH_URLS) {
        texts.push(webview.WebCookieManager.fetchCookieSync(url));
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`netease web login cookie fetch failed (${reason}): ${e.message}`);
      return;
    }
    const cookies = mergeCookieHeaderTexts(texts);
    if (!isNeteaseWebLoginComplete(cookies)) {
      return;
    }
    this.hasReturned = true;
    const keys: string[] = [];
    cookies.forEach((_value: string, key: string) => {
      keys.push(key);
    });
    // 只记键名：Cookie 值是登录凭据，不进日志。
    Logger.info(`netease web login captured (${reason}): keys=${keys.join(',')}`);
    NeteaseCookieRepository.saveFromWebLogin(cookies).then((saved: boolean): void => {
      this.getUIContext().getPromptAction().showToast({
        message: saved ? '网易云登录成功' : '网易云登录凭据校验失败，未保存',
        duration: 2000
      });
      if (saved) {
        Router.pop();
        return;
      }
      // 校验被拒（不应发生：完成判定已要求非空 MUSIC_U）时恢复轮询让用户重试。
      this.hasReturned = false;
    }).catch((error: Object): void => {
      const e = error as Error;
      Logger.error(`netease web login save failed: ${e.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '网易云登录保存失败' });
      this.hasReturned = false;
    });
  }

  private titleMenu(): SubPageMenuEntry[] {
    return [
      {
        label: '刷新页面',
        icon: $r('sys.symbol.arrow_clockwise'),
        action: (): void => this.reloadPage()
      }
    ];
  }

  private reloadPage(): void {
    try {
      this.controller.refresh();
    } catch (error) {
      const e = error as Error;
      Logger.warn(`netease web login refresh failed: ${e.message}`);
    }
  }

  /** 渲染进程退出原因转可读标签（枚举值随 SDK 演进，未知值回退数字）。 */
  private renderExitLabel(reason: RenderExitReason): string {
    switch (reason) {
      case RenderExitReason.ProcessAbnormalTermination:
        return 'abnormal_termination';
      case RenderExitReason.ProcessWasKilled:
        return 'killed';
      case RenderExitReason.ProcessCrashed:
        return 'crashed';
      case RenderExitReason.ProcessOom:
        return 'oom';
      default:
        return `unknown_${reason}`;
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
          // 登录页 URL 编译期已知，直接作为 src 加载（官方《使用Web组件加载
          // 页面》的标准写法）。此前 about:blank 起步、onControllerAttached 里
          // loadUrl 的两步模式与首次导航存在竞态：onControllerAttached 先于首
          // 次导航的 onLoadIntercept 触发，attached 里 loadUrl 时 about:blank
          // 尚挂在加载半路（该次导航还会被网易云白名单拦掉），真机两页均白屏。
          // 另按官方《定位与解决Web白屏问题》：Default 缓存模式的协商请求收
          // 到 412 不降级重试、直接白屏，登录页固定 Online 每次拉最新。
          Web({ src: NETEASE_WEB_LOGIN_URL, controller: this.controller })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(true)
            .fileAccess(false)
            .mixedMode(MixedMode.Compatible)
            .cacheMode(CacheMode.Online)
            .onControllerAttached(() => {
              Logger.info('netease web login controller attached');
            })
            .onPageBegin((event: OnPageBeginEvent) => {
              this.consoleLinesLogged = 0;
              // 日志只留 scheme/host/path：登录跳转链接的 query 可能带凭据明文。
              Logger.info(`netease web login page begin: ${sanitizeUrlForLog(event.url)}`);
            })
            .onLoadIntercept((event: OnLoadInterceptEvent) => {
              if (!event.data.isMainFrame()) {
                return false;
              }
              const allowed = isAllowedNeteaseLoginNavigation(event.data.getRequestUrl());
              if (!allowed) {
                // 不打完整 URL：登录后跳转链接的 query 可能携带凭据明文。
                Logger.warn('netease web login blocked non-allowlist main-frame navigation');
              }
              return !allowed;
            })
            .onPageEnd((event: OnPageEndEvent) => {
              Logger.info(`netease web login page end: ${sanitizeUrlForLog(event.url)}`);
              this.captureIfLoggedIn('pageEnd');
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              const scope = event.request.isMainFrame() ? 'main' : 'sub';
              Logger.warn(`netease web login load error (${scope}) code=${event.error.getErrorCode()}: ${event.error.getErrorInfo()} url=${sanitizeUrlForLog(event.request.getRequestUrl())}`);
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
              if (event.request.isMainFrame()) {
                Logger.warn(`netease web login http ${event.response.getResponseCode()} ${event.response.getReasonMessage()} url=${sanitizeUrlForLog(event.request.getRequestUrl())}`);
              }
            })
            .onRenderExited((event: OnRenderExitedEvent) => {
              Logger.warn(`netease web login render process exited: ${this.renderExitLabel(event.renderExitReason)}`);
            })
            .onConsole((event: OnConsoleEvent): boolean => {
              // 页面 JS 报错是「主资源加载成功但渲染空白」的唯一现场，转发进
              // 应用日志（同步进诊断环形缓冲）；限量防页面脚本刷屏，超出上限
              // 的消息不消费、仍走系统默认输出。
              if (this.consoleLinesLogged >= CONSOLE_LOG_CAP_PER_PAGE) {
                return false;
              }
              this.consoleLinesLogged++;
              Logger.info(`netease web login console: ${event.message.getMessage()}`);
              return true;
            })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background(Theme.isDark()))
    }
    .titleBar(subPageTitleBar('网易云网页登录', this.titleMenu()))
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
