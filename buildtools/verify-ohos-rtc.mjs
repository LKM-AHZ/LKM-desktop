import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';
const root = new URL('../packages/flutter_webrtc/ohos/src/main/ets/', import.meta.url);
const types = loadArkTs(new URL('utils/ObjectType.ts',root),new Map());
const arrays = loadArkTs(new URL('utils/ConstraintsArray.ts',root),new Map([['./ObjectType',types]]));
const maps = loadArkTs(new URL('utils/ConstraintsMap.ts',root),new Map([['./ObjectType',types],['./ConstraintsArray',arrays]]));
let granted = new Set(); let requested; let requestError = false;
const api = {
  GrantStatus:{PERMISSION_GRANTED:0},createAtManager:()=>({
    checkAccessToken:async(_,p)=>granted.has(p)?0:-1,
    async requestPermissionsFromUser(_,permissions) { requested=Array.from(permissions); if(requestError)throw {code:12,message:'permission failed'};
      return {authResults:permissions.map(p=>granted.has(p)?0:-1)}; },
  }),
};
const {PermissionsManager} = loadArkTs(new URL('utils/PermissionUtils.ets',root),new Map([
  ['@ohos.abilityAccessCtrl',api], ['@ohos.bundle.bundleManager',{BundleFlag:{GET_BUNDLE_INFO_WITH_APPLICATION:1},getBundleInfoForSelf:async()=>({appInfo:{accessTokenId:1}})}],
]));
const manager=PermissionsManager.getInstance();manager.init({});
const permit=async(values)=>{let answer;await manager.processPermissions(new maps.ConstraintsMap(new Map(Object.entries(values))),(...args)=>answer=args);return answer;};
assert.equal((await permit({audio:true,video:false}))[0],'permission_denied');assert.deepEqual(requested,['ohos.permission.MICROPHONE']);
granted=new Set(['ohos.permission.MICROPHONE']);
assert.deepEqual(await permit({audio:true,video:false}),[null,null]);
assert.equal((await permit({audio:true,video:true}))[0],'permission_denied');assert.deepEqual(requested,['ohos.permission.MICROPHONE','ohos.permission.CAMERA']);
assert.deepEqual(await permit({audio:false,video:false}),[null,null]);
requestError=true;assert.equal((await permit({video:true}))[1],'permission failed');requestError=false;
manager.init(null);assert.equal((await permit({video:true}))[0],'no_ability');
const {applyTransportConfig}=loadArkTs(new URL('utils/TransportConfig.ets',root),new Map());
const config=applyTransportConfig({iceServers:[]},new Map([['iceTransportPolicy','relay'],['bundlePolicy','max-bundle'],['iceCandidatePoolSize',4]]));
assert.equal(config.iceTransportPolicy,'relay');assert.equal(config.iceCandidatePoolSize,4);
assert.throws(()=>applyTransportConfig({},new Map([['iceTransportPolicy','bad']])));
assert.throws(()=>applyTransportConfig({},new Map([['iceCandidatePoolSize',-1]])));
const Crypto=loadArkTs(new URL('FlutterRTCFrameCryptor.ets',root),new Map()).default;
let cryptor;new Crypto({}).onMethodCall({method:'frameCryptorFactoryCreateKeyProvider'},{error:code=>cryptor=code});assert.equal(cryptor,'unsupported_operation');
const renderers=[];
class NativeVideoRenderer { constructor(){renderers.push(this);}init(id){this.surface=id;}setVideoTrack(track){this.track=track;}release(){this.released=true;} }
const Renderer=loadArkTs(new URL('FlutterRTCVideoRenderer.ets',root),new Map([
  ['@ohos/flutter_ohos',{Log:{d(){},e(){},w(){}}}],['./utils/ConstraintsMap',maps],['libohos_webrtc.so',{NativeVideoRenderer}],
])).default;
const sizes=[];const renderer=new Renderer(12,{}, {notifyTextureResizing:(...args)=>sizes.push(args)});
renderer.init('surface12');const video={id:'video',stop(){throw Error('Renderer must not stop a shared track');}};
renderer.onListen(null,{success(){}});renderer.setStream({getVideoTracks:()=>[video]},'remote','video');
assert.equal(renderers[0].surface,'surface12');assert.equal(renderers[0].track,video);
renderer.frameResolutionChanged({width:640,height:480,rotation:0});assert.deepEqual(sizes[0],[12,640,480]);
renderer.setStream(null,'remote');assert.equal(renderers[0].track,null);renderer.Dispose();assert(renderers[0].released);
console.log('OHOS RTC: microphone/camera permissions, refusal/errors, ICE relay policy, truthful cryptor failure and current texture rendering lifecycle passed.');
const routes=[];let routeGate;let routeFailure=false;
let sdkApiVersion=26;let inputSupported=true;const inputs=[];
const routing={getAvailableDevices:()=>[{id:9}],getDevicesSync:()=>[{id:7,deviceType:2},{id:8,deviceType:3}],async setCommunicationDevice(type,active){if(routeGate)await routeGate;if(routeFailure)throw Error('route failed');routes.push([type,active]);}};
const audio={getAudioManager:()=>({getRoutingManager:()=>routing,getDeviceEnhanceManager:()=>({isEnhancedRoutingSupported:()=>inputSupported,selectInputDevice:async device=>inputs.push(device.id)})}),DeviceUsage:{CALL_INPUT_DEVICES:8},
 AudioSamplingRate:{SAMPLE_RATE_48000:48000},AudioChannel:{CHANNEL_2:2},AudioSampleFormat:{SAMPLE_FORMAT_S16LE:1},AudioEncodingType:{ENCODING_TYPE_RAW:0},StreamUsage:{STREAM_USAGE_UNKNOWN:0},SourceType:{SOURCE_TYPE_MIC:0},DeviceFlag:{OUTPUT_DEVICES_FLAG:1},DeviceType:{SPEAKER:2,BLUETOOTH_SCO:3,WIRED_HEADSET:4}};
const Audio=loadArkTs(new URL('audio/AudioSwitchManager.ets',root),new Map([
 ['@kit.AudioKit',{audio}],['@ohos/flutter_ohos',{Log:{d(){},e(){},w(){}}}],['../utils/ObjectType',types],
 ['../utils/Utils',{isNotEmpty: x=>x!=null}],['@kit.ArkTS',{JSON}],['libohos_webrtc.so',{AudioDeviceModule:class {}}],
 ['@ohos.deviceInfo',{get sdkApiVersion(){return sdkApiVersion;}}],
])).default;
const managerAudio=Audio.getInstance();let releaseRoute;routeGate=new Promise(r=>releaseRoute=r);
let settled=false;const switching=managerAudio.enableSpeakerphone(true).then(()=>settled=true);
await new Promise(r=>setImmediate(r));assert.equal(settled,false);releaseRoute();await switching;routeGate=null;
assert.deepEqual(routes[0],[2,true]);await managerAudio.enableSpeakerButPreferBluetooth();assert.deepEqual(routes[1],[3,true]);
routeFailure=true;await assert.rejects(managerAudio.selectAudioOutput(7),/route failed/);
await assert.rejects(managerAudio.selectAudioOutput(99),/not found/);
await managerAudio.selectAudioInput('9');assert.deepEqual(inputs,[9]);
await assert.rejects(managerAudio.selectAudioInput('99'),/not found/);
inputSupported=false;await assert.rejects(managerAudio.selectAudioInput('9'),/unavailable/);inputSupported=true;
sdkApiVersion=20;await assert.rejects(managerAudio.selectAudioInput('9'),/API 26/);
console.log('OHOS RTC audio routes await actual SDK switching and propagate failures.');

const recorded=[];let failPrepare=false;let released=0;let closed=0;
const fileApi={OpenMode:{CREATE:1,READ_WRITE:2,EXCL:4},openSync:(path,mode)=>{assert.equal(mode,7);return {fd:4};},closeSync:()=>closed++};
const av={prepare:async config=>{recorded.push(config);if(failPrepare)throw Error('prepare failed');},getInputSurface:async()=>'encoder',start:async()=>recorded.push('start'),stop:async()=>recorded.push('stop'),release:async()=>released++};
const {TrackRecorder}=loadArkTs(new URL('record/TrackRecorder.ets',root),new Map([
 ['@kit.MediaKit',{media:{createAVRecorder:async()=>av,VideoSourceType:{VIDEO_SOURCE_TYPE_SURFACE_YUV:0},ContainerFormatType:{CFT_MPEG_4:'mp4'},CodecMimeType:{VIDEO_AVC:'video/avc'}}}],
 ['@ohos.file.fs',fileApi],['libohos_webrtc.so',{NativeVideoRenderer}],
]));
const recorder=new TrackRecorder();await recorder.start('/record.mp4',video,640,480);assert.equal(recorded[0].profile.videoFrameWidth,640);
assert.equal(recorded[0].url,'fd://4');assert.equal(renderers.at(-1).track,video);await recorder.stop();
assert.equal(renderers.at(-1).track,null);assert.equal(closed,1);assert.equal(released,1);
await assert.rejects(new TrackRecorder().start('/record.webm',video,640,480),/mp4/);
failPrepare=true;await assert.rejects(new TrackRecorder().start('/record.mp4',video,640,480),/prepare failed/);assert.equal(closed,2);assert.equal(released,2);
console.log('OHOS video recording prepares a real MP4 encoder surface, detaches shared tracks, and releases files on failure.');

const factories=[];let defaultFactory;let nativeStreamId=0;const snapshots=[];
class PeerConnectionFactory { constructor(options){this.options=options;factories.push(this);}static setDefault(factory){defaultFactory=factory;}createPeerConnection(){return {factory:this};} }
class MediaStream { constructor(){this.id=`native-stream-${++nativeStreamId}`;}getTracks(){return [];}getAudioTracks(){return [];}getVideoTracks(){return [];} }
class HashMap extends Map { remove(key){return this.delete(key);} }
class PlainArray {length=0;}
let writeFails=false;
const bridgeFiles={...fileApi,OpenMode:{...fileApi.OpenMode,TRUNC:8},openSync:(path,mode)=>{assert.equal(mode,11);return {fd:4};},writeSync:(fd,data)=>{if(writeFails)throw Error('disk full');snapshots.push([fd,...new Uint8Array(data)]);return data.byteLength;}};
let pixelsReleased=0;let packerReleased=0;
const sdkImage={createPixelMapFromSurface:async(surface,region)=>{assert.equal(surface,'surface12');assert.equal(region.size.width,640);return {release:async()=>pixelsReleased++};},createImagePacker:()=>({packing:async()=>new Uint8Array([137,80,78,71]).buffer,release:async()=>packerReleased++})};
const {default:Methods}=loadArkTs(new URL('MethodCallHandlerImpl.ets',root),new Map([
 ['@ohos/flutter_ohos',{Log:{d(){},i(){},e(){},w(){}}}],['@kit.ArkTS',{HashMap,PlainArray,JSON}],['@ohos.util',{}],
 ['./PeerConnectionObserver',class {}],['./FlutterRTCVideoRenderer',Renderer],['./utils/ConstraintsMap',maps],['./utils/ObjectType',types],['./utils/ConstraintsArray',arrays],
 ['@ohos.file.fs',bridgeFiles],['@kit.AudioKit',{audio}],['@ohos.buffer',{}],['@kit.ImageKit',{image:sdkImage}],['./record/TrackRecorder',{TrackRecorder}],
 ['./GetUserMediaImpl',class {}],['./audio/AudioSwitchManager',Audio],['./utils/TransportConfig',{applyTransportConfig}],['./FlutterRTCFrameCryptor',Crypto],
 ['./utils/OptionsUtils',{}],['./utils/PCOUtils',{}],['./utils/PermissionUtils',{PermissionsManager}],
 ['libohos_webrtc.so',{MediaStream,PeerConnectionFactory}],['./utils/CallUtils',{getTrackId:call=>call.argument('trackId'),getPeerConnectionId:call=>call.argument('peerConnectionId')}],['./utils/TrackUtils',{}],
]));
const methods=new Methods({}, {}, {});assert.equal(factories.length,0,'No stray default factory before ADM initialization');
methods.createPeerConnectionFactory();assert.equal(defaultFactory,methods.getPeerConnectionFactory());
let streamAnswer;methods.createLocalMediaStream({}, {success:value=>streamAnswer=value});
const localId=streamAnswer.get('streamId');assert.equal(localId,'native-stream-1');assert.equal(methods.getLocalStreams(localId).id,localId);
methods.renders={length:1,getValueAt:()=>({hasVideoTrack:id=>id==='video',_width:640,_height:480,getSurfaceId:()=>'surface12'})};
const callFor=trackId=>({argument:key=>({trackId,path:'/frame.png'})[key]});let captureAnswer;
methods.captureFrame(callFor('video'),{success:()=>captureAnswer='ok',error:code=>captureAnswer=code});
await new Promise(r=>setImmediate(r));assert.equal(captureAnswer,'ok');assert.deepEqual(snapshots[0],[4,137,80,78,71]);
assert.equal(pixelsReleased,1);assert.equal(packerReleased,1);
methods.captureFrame(callFor('missing'),{error:code=>captureAnswer=code});assert.equal(captureAnswer,'frame_unavailable');
writeFails=true;methods.captureFrame(callFor('video'),{success:()=>captureAnswer='ok',error:code=>captureAnswer=code});
await new Promise(r=>setImmediate(r));assert.equal(captureAnswer,'capture_error');assert.equal(pixelsReleased,2);assert.equal(packerReleased,2);
console.log('OHOS RTC empty streams use native IDs; capture writes real encoded surface bytes and releases image resources; capture and peers share the selected ADM.');

const LiveKit=loadArkTs(new URL('../packages/livekit_client/ohos/src/main/ets/io/livekit/plugin/LiveKitPlugin.ets',import.meta.url),new Map([
 ['@ohos.deviceInfo',{displayVersion:'6.0'}],
 ['@ohos/flutter_ohos',{}],
])).default;
let liveKitReply;new LiveKit().onMethodCall({method:'osVersionString'},{success:value=>liveKitReply=value});assert.equal(liveKitReply,'6.0');
