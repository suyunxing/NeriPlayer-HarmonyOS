/**
 * 页面订阅 store 并同步迷你播放器组件的公共助手。
 */

const store = require('./store');

function refreshMini(page, snapshot) {
  try {
    const mini = page.selectComponent && page.selectComponent('#miniPlayer');
    if (mini && mini.refresh) {
      mini.refresh(snapshot);
    }
  } catch (e) {
    // 组件尚未渲染时忽略
  }
}

function subscribePage(page, onChange) {
  return store.subscribe(function (snapshot) {
    let data = {};
    if (onChange) {
      data = onChange(snapshot) || {};
    }
    page.setData(data);
    refreshMini(page, snapshot);
  });
}

function openPlayer() {
  has.navigateTo({
    url: '/pages/now-playing/index',
  });
}

module.exports = { refreshMini, subscribePage, openPlayer };
