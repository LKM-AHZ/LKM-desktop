import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';
let channel;
class MethodChannel {
  constructor() { channel=this; this.signals=[]; }
  setMethodCallHandler(handler) { this.handler=handler; }
  invokeMethod(method, args) { this.signals.push(method); }
}
const { DeepLinkBridge } = loadArkTs(new URL('../ohos/entry/src/main/ets/entryability/DeepLinkBridge.ets',import.meta.url),
  new Map([['@ohos/flutter_ohos',{MethodChannel}]]));
const bridge = new DeepLinkBridge();
bridge.receive('https://evil.example');bridge.receive('lkm://posts/cold');bridge.attach({});
assert.equal(channel.signals.length,0);
const consume = () => { let value; bridge.onMethodCall({method:'consumePendingDeepLink'},{success:x=>value=x}); return value; };
assert.equal(consume(),'lkm://posts/cold');assert.equal(consume(),null);
bridge.receive('lkm://chat/first');bridge.receive('solian://posts/second');
assert.equal(channel.signals.length,2);
assert.equal(consume(),'lkm://chat/first');assert.equal(consume(),'solian://posts/second');
bridge.receive('lkm://'+'x'.repeat(9000));assert.equal(consume(),null);
bridge.detach();assert.equal(channel.handler,null);
console.log('OHOS app host deeplinks: cold/warm delivery, ordered bursts, scheme/size checks and detach passed.');
