/**
 * 应用设置仓库（对应 SettingsRepository.ets）。
 */

const constants = require('./constants');
const storage = require('./storage');

const DEFAULT_SETTINGS = {
  onboarded: false,
  disclaimerAgreed: false,
  safeMode: false,
  theme: 'system', // system | light | dark
  quality: 'standard', // exhigh | high | standard
  speed: 1.0,
  autoNext: true,
  preferBiliFallback: true,
  enableStats: true,
  enableHistory: true,
  selectedPlatform: 1, // 1 网易云 / 2 哔哩哔哩 / 3 YouTube Music
  customName: 'NeriPlayer',
};

function load() {
  const saved = storage.getJson(constants.keySettings, {});
  return Object.assign({}, DEFAULT_SETTINGS, saved);
}

function save(settings) {
  storage.setJson(constants.keySettings, settings);
}

function update(patch) {
  const current = load();
  const next = Object.assign({}, current, patch);
  save(next);
  return next;
}

function get(key, fallback) {
  const settings = load();
  return settings[key] !== undefined ? settings[key] : fallback;
}

module.exports = { load, save, update, get, DEFAULT_SETTINGS };
