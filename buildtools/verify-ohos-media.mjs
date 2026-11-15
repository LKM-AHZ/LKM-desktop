import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadArkTs } from './ohos-test-loader.mjs';

const channels = new Map();
class MethodChannel {
  constructor(_, name) { channels.set(name, this); }
  setMethodCallHandler(handler) { this.handler = handler; }
}
const Plugin = loadArkTs(new URL('../packages/media_kit_video/ohos/src/main/ets/components/plugin/MediaKitVideoPlugin.ets', import.meta.url),
  new Map([['@ohos/flutter_ohos', { MethodChannel }]])).default;
let nextId = 0;
const active = new Set(); const sizes = [];
let failCreate = false;
const registry = {
  getTextureId: () => ++nextId,
  registerTexture(id) {
    if (failCreate) throw Error('Surface allocation failed');
    active.add(id); return { getTextureId: () => id, getSurfaceId: () => 10101 + id, release() { throw Error('SDK release is unimplemented'); } };
  },
  unregisterTexture(id) { assert(active.delete(id), 'texture must be released exactly once'); },
  notifyTextureResizing(id, width, height) { assert(active.has(id)); sizes.push([id, width, height]); },
};
const plugin = new Plugin();
plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}), getTextureRegistry: () => registry });
function invoke(method, args = {}) {
  let response; let replies = 0;
  plugin.onMethodCall({ method, argument: key => args[key] ?? null }, {
    success(value) { replies++; response = { value }; },
    error(code, message) { replies++; response = { code, message }; },
    notImplemented() { replies++; response = { unimplemented: true }; },
  });
  assert.equal(replies, 1); return response;
}
const handle = '18446744073709550000'; // Pointer identifiers must not pass through lossy JS Number.
const created = invoke('VideoOutputManager.Create', { handle });
assert.equal(created.value.get('id'), 1); assert.equal(created.value.get('wid'), '10102');
assert.match(invoke('VideoOutputManager.Create', { handle }).message, /already exists/);
assert.equal(invoke('VideoOutputManager.SetSurfaceSize', { handle, width: 1920, height: 1080 }).value, null);
assert.deepEqual(sizes, [[1, 1920, 1080]]);
assert.match(invoke('VideoOutputManager.SetSurfaceSize', { handle, width: -1, height: 1080 }).message, /Invalid surface/);
assert.equal(invoke('VideoOutputManager.Dispose', { handle }).value, null);
assert.equal(invoke('VideoOutputManager.Dispose', { handle }).value, null);
assert.equal(active.size, 0);
failCreate = true;
assert.match(invoke('VideoOutputManager.Create', { handle }).message, /Surface allocation failed/);
assert.equal(active.size, 0); failCreate = false;
invoke('VideoOutputManager.Create', { handle: '123' });
plugin.onDetachedFromEngine({}); assert.equal(active.size, 0);
assert.equal(channels.get('com.alexmercerind/media_kit_video').handler, null);
assert.match(invoke('VideoOutputManager.Create', { handle }).message, /detached/);
console.log('OHOS media texture protocol, pointer precision, resize, failure and exact cleanup passed.');

const flutterRoot = process.env.FLUTTER_ROOT ?? join(homedir(), 'flutter');
const packagedEmbedding = new URL('../ohos/entry/oh_modules/@ohos/flutter_ohos/src/main/ets/', import.meta.url);
const packagedRegistry = new URL('view/TextureRegistry.ets', packagedEmbedding);
const registryApi = existsSync(packagedRegistry) ? packagedRegistry : join(flutterRoot, 'engine/src/flutter/shell/platform/ohos/flutter_embedding/flutter/src/main/ets/view/TextureRegistry.ets');
if (existsSync(registryApi)) {
  const api = readFileSync(registryApi, 'utf8');
  assert.match(api, /interface OnFrameConsumedListener/);
  assert.match(api, /onFrameConsumed\(\): void/);
  // A standalone listener declaration does not offer a way to register it on an output.
  const entry = api.match(/interface SurfaceTextureEntry\s*{([\s\S]*?)\n}/)[1];
  const registry = api.match(/interface TextureRegistry\s*{([\s\S]*?)\n}/)[1];
  assert.doesNotMatch(entry + registry, /OnFrameConsumedListener|setOnFrame|onFrameConsumed/);
  const rendererPath = existsSync(packagedRegistry) ? new URL('embedding/engine/renderer/FlutterRenderer.ets', packagedEmbedding) : join(flutterRoot, 'engine/src/flutter/shell/platform/ohos/flutter_embedding/flutter/src/main/ets/embedding/engine/renderer/FlutterRenderer.ets');
  const renderer = readFileSync(rendererPath, 'utf8');
  assert.doesNotMatch(renderer, /OnFrameConsumedListener|onFrameConsumed/);
  console.log('Installed OH-Flutter declares an unused frame-consumed listener but exposes no registration or renderer callback; first-frame getter remains unsupported.');
}
