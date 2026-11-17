// SPDX-License-Identifier: GPL-3.0
// Execute the bounded playlist regression suites on Node; never contacts remote services.
// This complements, not replaces, hvigor's ArkTS checks and device UI/network testing.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const Module = require('node:module');
const project = path.resolve(__dirname, '../NeriPlayer-HarmonyOS');
const roots = ['DEVECO_CLI_STUDIO_PATH', 'DEVECO_SDK_HOME', 'HOS_SDK_HOME', 'HARMONYOS_SDK_HOME']
  .map(key => process.env[key]).filter(Boolean);
const candidates = [process.env.NERIPLAYER_TYPESCRIPT_PATH, 'typescript'];
for (const root of roots) {
  for (const suffix of ['plugins/codelinter/node_modules/typescript',
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript',
    'openharmony/ets/build-tools/ets-loader/node_modules/typescript',
    'tools/hvigor/hvigor/node_modules/typescript']) {
    candidates.push(path.join(root, suffix));
  }
}
let ts;
for (const candidate of candidates.filter(Boolean)) {
  try { ts = require(candidate); break; } catch (_) { /* try the next known toolchain location */ }
}
if (!ts) throw new Error('Set DEVECO_CLI_STUDIO_PATH or NERIPLAYER_TYPESCRIPT_PATH to an installed TypeScript compiler.');
// Deliberate Hypium MockKit subset used by these suites; restores original descriptors.
class BoundaryMockKit {
  constructor() { this.restores = []; }
  mockProperty(target, key, value) {
    const original = Object.getOwnPropertyDescriptor(target, key);
    this.restores.push(() => original ? Object.defineProperty(target, key, original) : delete target[key]);
    Object.defineProperty(target, key, { configurable: true, writable: true, value });
  }
  clearAll() { for (const restore of this.restores.reverse()) restore(); this.restores = []; }
}
const cases = [];
let suite = '';
const hypium = {
  MockKit: BoundaryMockKit,
  describe(name, fn) { const previous = suite; suite = name; fn(); suite = previous; },
  it(name, _filter, fn) { cases.push({ name: suite + '/' + name, fn }); },
  expect(value) { return {
    assertEqual(expected) { assert.equal(value, expected); },
    assertTrue() { assert.equal(value, true); },
    assertFalse() { assert.equal(value, false); },
    assertDeepEquals(expected) { assert.deepEqual(value, expected); },
    assertContain(expected) { assert.ok(value.includes(expected)); },
    assertUndefined() { assert.equal(value, undefined); },
    assertNull() { assert.equal(value, null); }
  }; }
};
// Only platform boundaries are faked. Domain models, policies, repositories and coordinators
// are loaded from the unchanged production sources. Unsupported boundaries fail loudly.
let boundaryUuidCounter = 0;
const boundaryUuid = () => '00000000-0000-4000-8000-' + String(++boundaryUuidCounter).padStart(12, '0');
const noop = () => {};
class KitTextDecoder extends TextDecoder {
  static create(label) { return new KitTextDecoder(label); }
}
const kitMocks = {
  '@kit.ArkTS': { util: { TextEncoder, TextDecoder: KitTextDecoder, generateRandomUUID: boundaryUuid } },
  '@kit.AssetStoreKit': { asset: {} },
  '@kit.CoreFileKit': { fileIo: {}, fileUri: {}, picker: {}, fileShare: {} },
  '@kit.MediaKit': { media: {} },
  '@kit.ArkData': { preferences: {} },
  '@kit.AbilityKit': { common: {} },
  '@kit.BackgroundTasksKit': { workScheduler: {} },
  '@kit.PerformanceAnalysisKit': { hilog: { debug: noop, info: noop, warn: noop, error: noop } }
};
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@ohos/hypium') return hypium;
  if (Object.hasOwn(kitMocks, request)) return kitMocks[request];
  if (request.startsWith('@kit.') || request.startsWith('@ohos.')) {
    throw new Error('Unmocked native dependency: ' + request);
  }
  if (parent && request.startsWith('.')) {
    const candidate = path.resolve(path.dirname(parent.filename), request);
    if (fs.existsSync(candidate + '.ets')) return originalLoad.call(this, candidate + '.ets', parent, isMain);
  }
  return originalLoad.call(this, request, parent, isMain);
};
require.extensions['.ets'] = (module, filename) => {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'), reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCanonicalFileName: f => f, getCurrentDirectory: () => project, getNewLine: () => '\n'
  }));
  module._compile(result.outputText, filename);
};
const suites = process.argv.slice(2);
if (!suites.length) suites.push('SourceSync', 'MultiSourcePlaylist', 'SourceSyncCoordinator',
  'SyncPlaylistRestore', 'PlaylistImportActions', 'PlaylistMerge', 'PlaylistDisplayCover', 'SyncSongConvert', 'SongIdentitySha256');
(async () => {
  for (const name of suites) {
    if (!/^[A-Za-z0-9]+$/.test(name)) throw new Error('Expected a test suite name, not a path: ' + name);
    require(path.join(project, 'entry/src/test/ets/test', name + '.test.ets')).default();
  }
  let failed = 0;
  for (const test of cases) {
    try { await test.fn(); console.log('PASS ' + test.name); }
    catch (error) { failed++; console.error('FAIL ' + test.name + '\n' + error.stack); }
  }
  if (!cases.length) throw new Error('No tests were registered.');
  console.log(JSON.stringify({ engine: 'Node with Hypium-compatible assertions',
    passed: cases.length - failed, failed, total: cases.length, suites }));
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
