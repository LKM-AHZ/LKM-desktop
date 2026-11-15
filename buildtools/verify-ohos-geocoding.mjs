import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';
let lastRequest;
let fail = false;
let deferred;
class MethodChannel { setMethodCallHandler(handler) { this.handler = handler; } }
const geoLocationManager = {
  isGeocoderAvailable: () => true,
  async getAddressesFromLocationName(request) {
    lastRequest = request;
    if (fail) throw { code: 42, message: 'service failed' };
    if (deferred) return await deferred;
    return [{latitude: 0, longitude: 120}, {placeName: 'missing coordinates'}];
  },
  async getAddressesFromLocation(request) { lastRequest = request; return [{locality: '杭州',countryName:'中国'}]; },
};
const Plugin = loadArkTs(new URL('../packages/geocoding_ohos/ohos/src/main/ets/components/plugin/GeocodingOhosPlugin.ets', import.meta.url),
  new Map([['@ohos/flutter_ohos', { MethodChannel }], ['@kit.LocationKit', { geoLocationManager }]])).default;
const plugin = new Plugin(); const binding = { getBinaryMessenger: () => ({}) };
plugin.onAttachedToEngine(binding);
const invoke = (method, args = {}) => new Promise(resolve => plugin.onMethodCall({method, argument: k => args[k] ?? null}, {
  success: value => resolve({value}), error: (code,message) => resolve({code,message}), notImplemented: () => resolve({code:'unimplemented'}),
}));
assert.equal((await invoke('isPresent')).value, true);
const result = await invoke('locationFromAddress', {address:'杭州',localeIdentifier:'zh-CN'});
assert.equal(result.value.length, 1); assert.equal(result.value[0].get('latitude'), 0);
assert.equal(result.value[0].has('timestamp'), false);
assert.equal(lastRequest.locale, 'zh-CN'); assert.equal(lastRequest.country, undefined);
assert.equal((await invoke('placemarkFromCoordinates', {latitude:0,longitude:120,localeIdentifier:'en-US'})).value[0].get('locality'),'杭州');
assert.equal(lastRequest.locale, 'en-US');
await invoke('placemarkFromCoordinates', {latitude:0,longitude:0}); assert.equal(lastRequest.locale, undefined);
assert.equal((await invoke('placemarkFromCoordinates', {latitude:91,longitude:0})).code,'IO_ERROR');
assert.equal((await invoke('locationFromAddress', {address:' '})).code,'IO_ERROR');
fail=true; assert.equal((await invoke('locationFromAddress', {address:'x'})).message,'service failed'); fail=false;
let release; deferred = new Promise(resolve => release=resolve);
const pending = invoke('locationFromAddress', {address:'pending'});
plugin.onDetachedFromEngine(binding);
assert.equal((await pending).message,'Geocoding engine detached');
release([]); await new Promise(resolve => setImmediate(resolve));
console.log('OHOS geocoding: current per-request locale, real coordinates, codec lists, synchronous/asynchronous errors and detach passed.');
