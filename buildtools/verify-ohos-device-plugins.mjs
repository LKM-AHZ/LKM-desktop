import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadArkTs } from './ohos-test-loader.mjs';
const channels = new Map();
class MethodChannel {
  constructor(_, name) { channels.set(name, this); }
  setMethodCallHandler(handler) { this.handler = handler; }
  invokeMethod(method, args) { this.last = [method, args]; }
}
const flutter = { MethodChannel };
const binding = { getBinaryMessenger: () => ({}) };
const call = (method, args) => ({ method, args, argument: key => args?.[key] ?? null });
const invoke = (plugin, method, args) => new Promise(resolve => plugin.onMethodCall(call(method, args), {
  success: value => resolve({ value }), error: (code, message) => resolve({ code, message }), notImplemented: () => resolve({ missing: true }),
}));
let rejecting = false;
const Maps = loadArkTs(new URL('../packages/map_launcher/ohos/src/main/ets/components/plugin/MapLauncherOhosPlugin.ets', import.meta.url), new Map([
  ['@ohos/flutter_ohos', flutter], ['@ohos.bundle.bundleManager', { canOpenLink: scheme => scheme === 'baidumap://' }],
])).default;
const maps = new Maps();maps.onAttachedToEngine(binding);
let handoff;
maps.onAttachedToAbility({ getAbility: () => ({ context: { startAbility: async want => {
  handoff = want; if (rejecting) throw { code: 16000001, message: 'No matching ability' };
} } }) });
let response = await invoke(maps, 'getInstalledMaps', new Map([['baidu', 'baidumap://'], ['bad', 'not-a-scheme']]));
assert.deepEqual(Array.from(response.value.get('installed')), ['baidu']);
assert.deepEqual(Array.from(response.value.get('undeclared')), ['bad']);
assert.equal((await invoke(maps, 'launch', { url: 'https://maps.example/point' })).value, null);
assert.equal(handoff.uri, 'https://maps.example/point');
rejecting = true;
assert.equal((await invoke(maps, 'launch', { url: 'baidumap://map' })).code, 'LAUNCH_REJECTED');
maps.onDetachedFromAbility();assert.equal((await invoke(maps, 'launch', { url: 'https://maps.example' })).code, 'NO_ABILITY');
maps.onDetachedFromEngine(binding);assert.equal(channels.get('map_launcher').handler, null);

const visibility = new Map();let shortcutFailure = false;
const Quick = loadArkTs(new URL('../packages/quick_actions_ohos/ohos/src/main/ets/QuickActionsPlugin.ets', import.meta.url), new Map([
  ['@ohos/flutter_ohos', flutter], ['@ohos.bundle.shortcutManager', {
    getAllShortcutInfoForSelf: async () => [{ id: 'compose_post' }, { id: 'chats' }],
    setShortcutVisibleForSelf: async (id, visible) => { if (shortcutFailure) throw Error('visibility denied'); visibility.set(id, visible); },
  }],
])).default;
Quick.dispatchShortcutAction('chats');
const quick = new Quick();quick.onAttachedToEngine(binding);
assert.equal((await invoke(quick, 'getLaunchAction')).value, 'chats');
assert.equal((await invoke(quick, 'getLaunchAction')).value, null);
Quick.dispatchShortcutAction('compose_post');assert.deepEqual(channels.get('plugins.flutter.io/quick_actions').last, ['launch', 'compose_post']);
await invoke(quick, 'setShortcutItems', [new Map([['type','compose_post']])]);
assert.equal(visibility.get('compose_post'), true);assert.equal(visibility.get('chats'), false);
await invoke(quick, 'clearShortcutItems');assert.equal(visibility.get('compose_post'), false);
assert.equal((await invoke(quick, 'setShortcutItems', [new Map([['type','missing']])])).code, 'shortcut_error');
shortcutFailure = true;assert.equal((await invoke(quick, 'clearShortcutItems')).code, 'shortcut_error');
quick.onDetachedFromEngine(binding);

let nfcState = 3; let nfcOpen = true; let nfcError = false;
const Nfc = loadArkTs(new URL('../packages/flutter_nfc_kit/ohos/src/main/ets/components/plugin/FlutterNfcKitPlugin.ets', import.meta.url), new Map([
  ['@ohos/flutter_ohos', flutter], ['@kit.ConnectivityKit', { tag: {}, nfcController: {
    isNfcOpen() { if (nfcError) throw Error('NFC service failed'); return nfcOpen; }, getNfcState: () => nfcState,
  } }], ['@kit.AbilityKit', {}], ['@kit.PerformanceAnalysisKit', { hilog: {} }], ['@ohos.util.json', JSON],
])).default;
const nfc = new Nfc();
assert.equal((await invoke(nfc, 'getNFCAvailability')).code, '500');
nfc.ability = {};
assert.equal((await invoke(nfc, 'getNFCAvailability')).value, 'available');
nfcOpen = false;assert.equal((await invoke(nfc, 'getNFCAvailability')).value, 'disabled');
nfcState = null;assert.equal((await invoke(nfc, 'getNFCAvailability')).value, 'not_supported');
nfcError = true;assert.match((await invoke(nfc, 'getNFCAvailability')).message, /NFC service failed/);
assert.equal(nfc.pendingResults.size, 0, 'synchronous SDK failures settle and unregister their result');
console.log('OHOS device plugins: current map protocol, launch/error/detach, real shortcut visibility and launch lifecycle, NFC availability/errors passed.');

// Exercise the actual CameraKit -> ImageReceiver -> ScanKit path for selectable cameras.
let arrival; let selectedDevice; let decoderFailure = false; let cameraOpenGate;
let framesReleased = 0; let receiversReleased = 0; let sessionsReleased = 0; let inputsClosed = 0; let outputsReleased = 0;
let decodeGate; let decoded; const scans = []; const packed = []; let zoom = 1;
const camera = {
  CameraPosition: { CAMERA_POSITION_FRONT: 2 }, ConnectionType: { CAMERA_CONNECTION_USB_PLUGIN: 1, CAMERA_CONNECTION_REMOTE: 2 },
  CameraFormat: { CAMERA_FORMAT_YUV_420_SP: 1003 }, SceneMode: { NORMAL_PHOTO: 1 },
  FlashMode: { FLASH_MODE_CLOSE: 0, FLASH_MODE_ALWAYS_OPEN: 1 }, FocusMode: { FOCUS_MODE_AUTO: 1 },
  getCameraManager: () => ({
    getSupportedCameras: () => [{ id: 'front', cameraPosition: 2, connectionType: 0 }, { id: 'usb', cameraPosition: 0, connectionType: 1 }],
    getSupportedOutputCapability: () => ({ previewProfiles: [{ format: 1003, size: { width: 4, height: 2 } }] }),
    createCameraInput: device => {selectedDevice = device.id; return {open: async()=>{if(cameraOpenGate)await cameraOpenGate;}, close:async()=>inputsClosed++};},
    createPreviewOutput: () => ({ getPreviewRotation: () => 90, setPreviewRotation: () => {}, release: async()=>outputsReleased++ }),
    createSession: () => ({
      beginConfig(){},addInput(){},canAddOutput:()=>true,addOutput(){},commitConfig:async()=>{},hasFlash:()=>false,
      getZoomRatioRange:()=>[1,4],setZoomRatio:value=>zoom=value,getZoomRatio:()=>zoom,
      isFocusModeSupported:()=>false,start:async()=>{},stop:async()=>{},release:async()=>sessionsReleased++,
    }),
  }),
};
const image = {
  ImageFormat:{JPEG:2000},ComponentType:{JPEG:4},
  createImageReceiver: () => ({
    getReceivingSurfaceId:async()=> 'analysis',on:(_,callback)=>arrival=callback,off:()=>arrival=null,
    readNextImage:async()=>({
      getComponent:async()=>({rowStride:6,byteBuffer:Uint8Array.from([1,2,3,4,99,99,5,6,7,8,99,99,9,10,11,12,99,99]).buffer}),
      release:async()=>framesReleased++,
    }),release:async()=>receiversReleased++,
  }),
};
const scanKit = { detectBarcode: {
  ImageFormat:{NV21:0},decodeImage:async input=>{decoded=input;if(decodeGate)await decodeGate;if(decoderFailure)throw Error('decode failed');return {scanResults:[],zoomValue:2};},
} };
const SelectedCamera = loadArkTs(new URL('../packages/mobile_scanner/ohos/src/main/ets/SelectedCamera.ets', import.meta.url), new Map([
  ['@kit.CameraKit',{camera}],['@kit.ImageKit',{image}],['@kit.ScanKit',scanKit],
  ['@kit.ArkUI',{display:{getDefaultDisplaySync:()=>({rotation:0})}}],
])).SelectedCamera;
const selected = new SelectedCamera((error,result)=>scans.push([error,result]),(_,frame)=>packed.push(frame));
await selected.start({},0,'preview',{},undefined,0,1,false,true);
assert.equal(selectedDevice,'front');assert.equal(selected.cameraCount,2);assert.equal(selected.torchable,false);
assert.equal(selected.previewWidth,2);assert.equal(selected.previewHeight,4);
assert.deepEqual({...selected.point(1,1)},{x:1,y:1});
assert.throws(()=>selected.setTorch(true),/no flashlight/);assert.throws(()=>selected.setZoom(5),/outside/);
assert.throws(()=>selected.setFocus(.5,.5),/autofocus is unsupported/);
arrival();await selected.processing;
assert.deepEqual(Array.from(new Uint8Array(decoded.byteBuffer)),[1,2,3,4,5,6,7,8,9,10,11,12]);
assert.equal(framesReleased,1);assert.equal(packed.length,1);assert.equal(zoom,2);
let decodeRelease;decodeGate=new Promise(resolve=>decodeRelease=resolve);
arrival();await new Promise(resolve=>setImmediate(resolve));
arrival();await new Promise(resolve=>setImmediate(resolve));
assert.equal(framesReleased,3,'busy decoding must still drain and release new camera buffers');
decodeRelease();await selected.processing;decodeGate=null;
decoderFailure=true;arrival();await selected.processing;assert.match(scans.at(-1)[0].message,/decode failed/);
await selected.close();assert.equal(arrival,null);assert.equal(sessionsReleased,1);assert.equal(outputsReleased,2);
assert.equal(inputsClosed,1);assert.equal(receiversReleased,1);
const external = new SelectedCamera(()=>{},()=>{});await external.start({},2,'preview',{},undefined,0,1,false,false);
assert.equal(selectedDevice,'usb');await external.close();
let openRelease;cameraOpenGate=new Promise(resolve=>openRelease=resolve);
const detaching = new SelectedCamera(()=>{},()=>{});
const starting = detaching.start({},0,'preview',{},undefined,0,1,false,false);
const closing = detaching.close();openRelease();await assert.rejects(starting,/detached/);await closing;
assert.equal(inputsClosed,3,'input opened during detach must still be closed');
console.log('OHOS selectable camera: actual device selection, dual preview, NV21 stride removal, ScanKit errors, zoom/flash limits and detach-during-open cleanup passed.');

class ScannerChannel extends MethodChannel {}
class EventChannel { setStreamHandler(handler){this.handler=handler;} }
const log={i(){},e(){}};
const Scanner=loadArkTs(new URL('../packages/mobile_scanner/ohos/src/main/ets/MobileScannerPlugin.ets',import.meta.url),new Map([
 ['@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel',ScannerChannel],
 ['@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel',EventChannel],
 ['@ohos/flutter_ohos/src/main/ets/util/Log',log],
 ['./CameraPermissions',{cameraPermission:'camera',checkPermissions:async()=>true,requestPermissions:(_,cb)=>cb(null,'')}],
 ['./CameraUtil',{getCameraManager:()=>camera.getCameraManager({}),hasFlashUnit:()=>false}],
 ['./SelectedCamera',{SelectedCamera}],
 ['./Barcode',{Barcode:{convertToScanType:value=>value,convertScanType:value=>value},BarcodeType:{unknown:0}}],
 ['@kit.ScanKit',{...scanKit,scanCore:{ScanType:{ALL:0,FORMAT_UNKNOWN:-1}},customScan:{getFlashLightStatus(){throw Error('Selected camera must not access rear-only customScan');}}}],
 ['@kit.ArkUI',{display:{}}],['@kit.ImageKit',{image}],['@kit.CameraKit',{camera}],
 ['@kit.ArkGraphics2D',{effectKit:{}}],['@ohos.sensor',{}],
])).MobileScannerPlugin;
cameraOpenGate=null;decoderFailure=false;
const scanner=new Scanner();let unregistered=0;
const scannerBinding={getApplicationContext:()=>({}),getBinaryMessenger:()=>({}),getTextureRegistry:()=>({
 getTextureId:()=>44,registerTexture:()=>({getSurfaceId:()=>1234}),unregisterTexture:()=>unregistered++,
})};
scanner.onAttachedToEngine(scannerBinding);
const startResponse=await invoke(scanner,'start',{facing:0});
assert.equal(startResponse.value.cameraDirection,0);assert.equal(startResponse.value.numberOfCameras,2);
assert.equal(startResponse.value.torchable,false);assert.equal(startResponse.value.size.width,2);
assert.match((await invoke(scanner,'toggleTorch')).message,/no flashlight/);
assert.equal((await invoke(scanner,'pause',{})).value,null);assert.equal(scanner.selectedCamera,null);
assert.match((await invoke(scanner,'start',{facing:0,torch:true})).message,/no flashlight/);
assert.equal(scanner.selectedCamera,null,'failed startup releases partial capture');
assert.match((await invoke(scanner,'start',{facing:0,lensType:1})).message,/lens type selection is unsupported/);
assert.equal((await invoke(scanner,'start',{facing:2})).value.cameraDirection,2);
await scanner.onDetachedFromEngine(scannerBinding);assert.equal(unregistered,1);assert.equal(arrival,null);
console.log('OHOS scanner native channel: current front/external facing replies, real camera count, unsupported torch, pause/restart and engine texture teardown passed.');

const deviceSdk = process.env.DEVECO_SDK_HOME ?? join(homedir(), 'harmonyos/command-line-tools/sdk');
const cameraApi = join(deviceSdk, 'default/openharmony/ets/api/@ohos.multimedia.camera.d.ts');
if (existsSync(cameraApi)) {
  const api = readFileSync(cameraApi, 'utf8');
  assert.match(api, /CAMERA_POSITION_FRONT\s*=\s*2/);
  assert.match(api, /CAMERA_CONNECTION_USB_PLUGIN\s*=\s*1/);
  assert.match(api, /canAddOutput\(cameraOutput: CameraOutput\): boolean/);
  const decode = readFileSync(join(deviceSdk, 'default/hms/ets/api/@hms.core.scan.detectBarcode.d.ts'), 'utf8');
  assert.match(decode, /decodeImage\(image: ByteImage, options\?: scanBarcode.ScanOptions\): Promise<DetectResult>/);
  const custom = readFileSync(join(deviceSdk, 'default/hms/ets/api/@hms.core.scan.customScan.d.ts'), 'utf8');
  const view = custom.match(/interface ViewControl\s*{([\s\S]*?)\n    }/)[1];
  assert.doesNotMatch(view, /cameraId|cameraPosition|facing/);
  console.log('Installed SDK confirms selectable CameraKit input and byte decoding; customScan has no camera selector.');
}
