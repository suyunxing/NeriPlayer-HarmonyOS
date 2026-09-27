// SPDX-License-Identifier: GPL-3.0

import { webview } from '@kit.ArkWeb';
import { Logger } from '../../app/Logger';
import { Theme } from '../Theme';
import { Router } from '../Router';
import { BiliCookieRepository } from '../../data/auth/BiliCookieRepository';
import {
  BILI_WEB_LOGIN_URL,
  BILI_WEB_COOKIE_FETCH_URLS,
  mergeCookieHeaderTexts,
  shouldAutoCompleteBiliWebLogin,
  isAllowedBiliLoginNavigation
} from '../../data/auth/BiliWebLogin';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { subPageTitleBar, SubPageMenuEntry, SUB_TITLEBAR_SPACE_VP } from '../components/HdsSubPage';

const POLL_INTERVAL_MS: number = 1500;

/**
 * Bilibili 网页登录（对齐 Android 上游 BiliWebLoginActivity）：内嵌 WebView 打开
 * 官方 passport.bilibili.com/login，验证码/扫码/密码全部由官方页面自己处理。
 * 登录完成的检测不看成功页（页面结构不稳定），而是轮询 WebView Cookie 池，
 * 按 shouldAutoCompleteBiliWebLogin（非空 SESSDATA）判定；命中后快照交给
 * BiliCookieRepository.saveFromWebLogin 落库并返回。进入前清空 WebView Cookie
 * 池（对齐上游 forceFreshWebContext，防止上一次会话残留被误判为登录成功），
 * 主框架导航限制在登录相关域（onLoadIntercept）。
 */
@Component
export struct BiliWebLoginPage {
  /** 状态栏避让（util/WindowMetrics.ets 发布）；Web 内容从标题栏下沿起。 */
  @StorageProp('ui.topInsetVp') topInset: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pollTimer: number = -1;
  private hasReturned: boolean = false;

  aboutToAppear(): void {
    // 静态 Cookie 管理器先于 Web 创建调用：清空整个 WebView Cookie 池（本页
    // 是应用内唯一 WebView 使用方，等价于上游逐键过期的 forceFreshWebContext），
    // 并打开第一方/第三方 Cookie——B 站登录要跨 passport 与 .bilibili.com 域写凭据。
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

  /** 抓取各域 Cookie 合并后做完成判定；命中即落库返回（幂等防重入）。 */
  private captureIfLoggedIn(reason: string): void {
    if (this.hasReturned) {
      return;
    }
    const texts: string[] = [];
    try {
      for (const url of BILI_WEB_COOKIE_FETCH_URLS) {
        texts.push(webview.WebCookieManager.fetchCookieSync(url));
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`bili web login cookie fetch failed (${reason}): ${e.message}`);
      return;
    }
    const cookies = mergeCookieHeaderTexts(texts);
    if (!shouldAutoCompleteBiliWebLogin(cookies)) {
      return;
    }
    this.hasReturned = true;
    const keys: string[] = [];
    cookies.forEach((_value: string, key: string) => {
      keys.push(key);
    });
    Logger.info(`bili web login captured (${reason}): keys=${keys.join(',')}`);
    BiliCookieRepository.saveFromWebLogin(cookies).then((saved: boolean): void => {
      this.getUIContext().getPromptAction().showToast({
        message: saved ? 'Bilibili 登录成功' : 'Bilibili 登录凭据校验失败，未保存',
        duration: 2000
      });
      if (saved) {
        Router.pop();
        return;
      }
      // 校验被拒（不应发生：完成判定已要求非空 SESSDATA）时恢复轮询让用户重试。
      this.hasReturned = false;
    }).catch((error: Object): void => {
      const e = error as Error;
      Logger.error(`bili web login save failed: ${e.message}`);
      this.getUIContext().getPromptAction().showToast({ message: 'Bilibili 登录保存失败' });
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
      Logger.warn(`bili web login refresh failed: ${e.message}`);
    }
  }

  build() {
    // 标题栏（返回 + 标题 + 刷新菜单）由 HdsNavDestination 承载；Web 组件铺在
    // 标题栏下方直到屏幕底（页面不滚动，无需 bindToScrollable 与底部渐变遮罩）。
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
              // Cookie 池已在 aboutToAppear 清空；真正的登录页从 attached 时机
              // 显式加载（loadUrl 必须等 controller 挂载，官方 FAQ faqs-arkweb-129）。
              try {
                this.controller.loadUrl(BILI_WEB_LOGIN_URL);
              } catch (error) {
                const e = error as Error;
                Logger.error(`bili web login loadUrl failed: ${e.message}`);
              }
            })
            .onLoadIntercept((event: OnLoadInterceptEvent) => {
              if (!event.data.isMainFrame()) {
                return false;
              }
              const allowed = isAllowedBiliLoginNavigation(event.data.getRequestUrl());
              if (!allowed) {
                // 不打完整 URL：登录后跳转链接的 query 可能携带凭据明文。
                Logger.warn('bili web login blocked non-allowlist main-frame navigation');
              }
              return !allowed;
            })
            .onPageEnd((_event: OnPageEndEvent) => {
              this.captureIfLoggedIn('pageEnd');
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event.request.isMainFrame()) {
                Logger.warn(`bili web login page error: ${event.error.getErrorInfo()}`);
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
    .titleBar(subPageTitleBar('Bilibili 网页登录', this.titleMenu()))
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillDisappear(() => {
      Router.notifyReturned();
    })
  }
}
