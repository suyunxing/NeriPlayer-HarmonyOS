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
  isAllowedNeteaseLoginNavigation
} from '../../data/auth/NeteaseWebLogin';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP } from '../components/HdsSubPage';

const POLL_INTERVAL_MS: number = 1500;

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

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          Column().height(this.topInset + SUB_TITLEBAR_SPACE_VP)
          Web({ src: 'about:blank', controller: this.controller })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(true)
            .fileAccess(false)
            .mixedMode(MixedMode.Compatible)
            .onControllerAttached(() => {
              // Cookie 池已在 aboutToAppear 清空；登录页从 attached 时机显式
              // 加载（loadUrl 必须等 controller 挂载，官方 FAQ faqs-arkweb-129）。
              try {
                this.controller.loadUrl(NETEASE_WEB_LOGIN_URL);
              } catch (error) {
                const e = error as Error;
                Logger.error(`netease web login loadUrl failed: ${e.message}`);
              }
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
            .onPageEnd((_event: OnPageEndEvent) => {
              this.captureIfLoggedIn('pageEnd');
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event.request.isMainFrame()) {
                Logger.warn(`netease web login page error: ${event.error.getErrorInfo()}`);
              }
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
