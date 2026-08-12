/**
 * 基于 has.setStorageSync / has.getStorageSync 的持久化封装。
 */

function set(key, value) {
  try {
    has.setStorageSync(key, value);
  } catch (e) {
    console.error('storage.set failed', key, e);
  }
}

function get(key, fallback) {
  try {
    const value = has.getStorageSync(key);
    return value === '' || value === undefined || value === null ? fallback : value;
  } catch (e) {
    console.error('storage.get failed', key, e);
    return fallback;
  }
}

function setJson(key, value) {
  set(key, JSON.stringify(value));
}

function getJson(key, fallback) {
  const raw = get(key, '');
  if (!raw) {
    return fallback;
  }
  try {
    return JSON.parse(raw);
  } catch (e) {
    console.error('storage.getJson parse failed', key, e);
    return fallback;
  }
}

function remove(key) {
  try {
    has.removeStorageSync(key);
  } catch (e) {
    console.error('storage.remove failed', key, e);
  }
}

module.exports = { set, get, setJson, getJson, remove };
