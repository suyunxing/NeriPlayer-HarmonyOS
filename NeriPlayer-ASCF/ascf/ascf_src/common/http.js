/**
 * has.request 的 Promise 封装（对应 Android 端共享 OkHttpClient）。
 */

const DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

function request(options) {
  return new Promise(function (resolve, reject) {
    has.request({
      url: options.url,
      method: options.method || 'GET',
      data: options.data,
      header: options.header || {},
      timeout: options.timeoutMs || 15000,
      dataType: 'text',
      responseType: 'text',
      success: function (res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data);
        } else {
          reject(new Error('HTTP ' + res.statusCode + ' for ' + options.method + ' ' + options.url));
        }
      },
      fail: function (res) {
        reject(new Error((res && res.errMsg) || 'network error'));
      },
    });
  });
}

function getText(url, headers) {
  const merged = { 'User-Agent': DEFAULT_UA };
  if (headers) {
    for (const key of Object.keys(headers)) {
      merged[key] = headers[key];
    }
  }
  return request({ url, method: 'GET', header: merged });
}

function postForm(url, form) {
  const parts = [];
  for (const key of Object.keys(form)) {
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(form[key]));
  }
  return request({
    url,
    method: 'POST',
    header: {
      'User-Agent': DEFAULT_UA,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    data: parts.join('&'),
  });
}

function postJson(url, jsonBody, headers) {
  const merged = {
    'User-Agent': DEFAULT_UA,
    'Content-Type': 'application/json',
  };
  if (headers) {
    for (const key of Object.keys(headers)) {
      merged[key] = headers[key];
    }
  }
  return request({ url, method: 'POST', header: merged, data: jsonBody });
}

module.exports = { getText, postForm, postJson };
