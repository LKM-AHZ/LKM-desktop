/* MIT License
*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* All rights reserved.
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import {
  BinaryMessenger,
  SurfaceTextureEntry,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodResult,
  TextureRegistry,
  EventChannel,
  Any
} from '@ohos/flutter_ohos';
import StateProvider from './StateProvider';
import { common, UIAbility } from '@kit.AbilityKit';
import { ArrayList, HashMap, JSON, PlainArray } from '@kit.ArkTS';
import util from '@ohos.util'
import PeerConnectionObserver from './PeerConnectionObserver';
import FlutterRTCVideoRenderer from './FlutterRTCVideoRenderer';
import { ConstraintsMap } from './utils/ConstraintsMap';
import { DataArray, DataMap, ObjectType } from './utils/ObjectType';
import { ConstraintsArray } from './utils/ConstraintsArray';
import fs from '@ohos.file.fs';
import { camera } from '@kit.CameraKit';
import { audio } from '@kit.AudioKit';
import buffer from '@ohos.buffer';
import { image } from '@kit.ImageKit';
import { TrackRecorder } from './record/TrackRecorder';
import GetUserMediaImpl from './GetUserMediaImpl';
import { MethodHandlers } from './MethodHandlers';
import AudioSwitchManager from './audio/AudioSwitchManager';
import { applyTransportConfig } from './utils/TransportConfig';
import FlutterRTCFrameCryptor from './FlutterRTCFrameCryptor';
import {
  getOptionsAudioConfiguration,
  getOptionsForceSWCodec,
  getOptionsForceSWCodecList,
  getOptionsNetworkIgnoreMask
} from './utils/OptionsUtils';
import { capabilitiesToMap } from './utils/PCOUtils';
import { PermissionsManager } from './utils/PermissionUtils';
import { isEmpty, isNotEmpty } from './utils/Utils';
import {
  MediaStreamTrack,
  RTCPeerConnection,
  RTCRtpSender,
  PeerConnectionFactory,
  AudioDeviceModule,
  AudioDeviceModuleOptions,
  VideoEncoderFactory,
  VideoDecoderFactory,
  MediaStream,
  Event,
  RTCDataChannel,
  RTCRtpReceiver,
  AudioErrorEvent,
  AudioStateChangeEvent,
  AudioCapturerSamplesReadyEvent,
  RTCConfiguration,
  RTCIceServer,
  MediaStreamConstraints,
  MediaDevices,
  MediaTrackConstraints,
  DisplayMediaStreamOptions,
  VideoTrack,
  AudioTrack,
  RTCSdpType,
  RTCSessionDescriptionInit,
  RTCIceCandidateInit,
  RTCRtpTransceiverDirection,
} from 'libohos_webrtc.so'
import {
  getCandidateMap,
  getConfigurationMap,
  getConstraintsMap,
  getDataChannelDictMap,
  getDataChannelId,
  getDescriptionMap,
  getDirection,
  getDuration,
  getGap,
  getLabel,
  getOptionsMap,
  getPeerConnectionId,
  getRtpSenderId,
  getSenderId,
  getStreamId,
  getStreamIds,
  getTone,
  getTrackId,
  getTransceiverId,
  getType
} from './utils/CallUtils';
import { mediaStreamTrackToMap } from './utils/TrackUtils';

const TAG: string = 'FlutterWebRTCPlugin-MethodCallHandlerImpl';

export default class MethodCallHandlerImpl implements MethodCallHandler, StateProvider {
  private ability: UIAbility | null = null;
  private messenger: BinaryMessenger;
  private context: Context;
  private textures: TextureRegistry;
  private mPCO: HashMap<string, PeerConnectionObserver> = new HashMap();
  private pcf: PeerConnectionFactory | null = null;
  private pc?: RTCPeerConnection;
  private adm?: AudioDeviceModule;
  private recvChannel?: RTCDataChannel;
  private sendChannel?: RTCDataChannel;
  private videoEncoderFactory?: VideoEncoderFactory;
  private videoDecoderFactory?: VideoDecoderFactory;
  private localStreams: HashMap<string, MediaStream> = new HashMap();
  private localTracks: HashMap<String, MediaStreamTrack> = new HashMap();
  private renders: PlainArray<FlutterRTCVideoRenderer> = new PlainArray();
  private stateProvider: StateProvider;
  private getUserMediaImpl: GetUserMediaImpl | null = null;
  private audioDeviceModule: AudioDeviceModule | null = null;
  private frameCryptor: FlutterRTCFrameCryptor;
  // private videoEncoderFactory: CustomVideoEncoderFactory | null = null;
  private mTextureId: number = 0;
  private entry: SurfaceTextureEntry | null = null;
  private recorders: Map<number, TrackRecorder> = new Map();

  constructor(context: Context, messenger: BinaryMessenger, textureRegistry: TextureRegistry) {
    this.context = context;
    this.textures = textureRegistry;
    this.messenger = messenger;
    this.stateProvider = this;
    this.frameCryptor = new FlutterRTCFrameCryptor(this);
  }

  private methodHandlers: MethodHandlers = {
    'initialize': (call, result) => this.initialize(call, result),
    'createPeerConnection': (call, result) => this.createPeerConnection(call, result),
    'getUserMedia': (call, result) => this.getUserMedia(call, result),
    'createLocalMediaStream': (call, result) => this.createLocalMediaStream(call, result),
    'getSources': (call, result) => this.getSources(call, result),
    'createOffer': (call, result) => this.createOffer(call, result),
    'createAnswer': (call, result) => this.createAnswer(call, result),
    'mediaStreamGetTracks': (call, result) => this.mediaStreamGetTracks(call, result),
    'addStream': (call, result) => this.addStream(call, result),
    'removeStream': (call, result) => this.removeStream(call, result),
    'setLocalDescription': (call, result) => this.setLocalDescription(call, result),
    'setRemoteDescription': (call, result) => this.setRemoteDescription(call, result),
    'sendDtmf': (call, result) => this.sendDtmf(call, result),
    'addCandidate': (call, result) => this.addCandidate(call, result),
    'getStats': (call, result) => this.getStats(call, result),
    'createDataChannel': (call, result) => this.createDataChannel(call, result),
    'dataChannelSend': (call, result) => this.dataChannelSend(call, result),
    'dataChannelClose': (call, result) => this.dataChannelClose(call, result),
    'streamDispose': (call, result) => this.streamDispose(call, result),
    'mediaStreamTrackSetEnable': (call, result) => this.mediaStreamTrackSetEnable(call, result),
    'mediaStreamAddTrack': (call, result) => this.mediaStreamAddTrack(call, result),
    'mediaStreamRemoveTrack': (call, result) => this.mediaStreamRemoveTrack(call, result),
    'trackDispose': (call, result) => this.trackDispose(call, result),
    'restartIce': (call, result) => this.restartIce(call, result),
    'peerConnectionClose': (call, result) => this.peerConnectionClose(call, result),
    'peerConnectionDispose': (call, result) => this.peerConnectionDispose(call, result),
    'createVideoRenderer': (call, result) => this.createVideoRenderer(call, result),
    'videoRendererDispose': (call, result) => this.videoRendererDispose(call, result),
    'videoRendererSetSrcObject': (call, result) => this.videoRendererSetSrcObject(call, result),
    'mediaStreamTrackHasTorch': (call, result) => this.mediaStreamTrackHasTorch(call, result),
    'mediaStreamTrackSetTorch': (call, result) => this.mediaStreamTrackSetTorch(call, result),
    'mediaStreamTrackSetZoom': (call, result) => this.mediaStreamTrackSetZoom(call, result),
    'mediaStreamTrackSwitchCamera': (call, result) => this.mediaStreamTrackSwitchCamera(call, result),
    'setVolume': (call, result) => this.setVolume(call, result),
    'selectAudioOutput': (call, result) => this.selectAudioOutput(call, result),
    'setMicrophoneMute': (call, result) => this.setMicrophoneMute(call, result),
    'selectAudioInput': (call, result) => this.selectAudioInput(call, result),
    'setOhosAudioConfiguration': (call, result) => this.setOhosAudioConfiguration(call, result),
    'enableSpeakerphone': (call, result) => this.enableSpeakerphone(call, result),
    'enableSpeakerphoneButPreferBluetooth': (call, result) => this.enableSpeakerphoneButPreferBluetooth(call, result),
    'getDisplayMedia': (call, result) => this.getDisplayMedia(call, result),
    'startRecordToFile': (call, result) => this.startRecordToFile(call, result),
    'stopRecordToFile': (call, result) => this.stopRecordToFile(call, result),
    'captureFrame': (call, result) => this.captureFrame(call, result),
    'getLocalDescription': (call, result) => this.getLocalDescription(call, result),
    'getRemoteDescription': (call, result) => this.getRemoteDescription(call, result),
    'setConfiguration': (call, result) => this.setConfiguration(call, result),
    'addTrack': (call, result) => this.addTrack(call, result),
    'removeTrack': (call, result) => this.removeTrack(call, result),
    'addTransceiver': (call, result) => this.addTransceiver(call, result),
    'rtpTransceiverSetDirection': (call, result) => this.rtpTransceiverSetDirection(call, result),
    'rtpTransceiverGetDirection': (call, result) => this.rtpTransceiverGetDirection(call, result),
    'rtpTransceiverGetCurrentDirection': (call, result) => this.rtpTransceiverGetCurrentDirection(call, result),
    'rtpTransceiverStop': (call, result) => this.rtpTransceiverStop(call, result),
    'rtpSenderSetParameters': (call, result) => this.rtpSenderSetParameters(call, result),
    'rtpSenderReplaceTrack': (call, result) => this.rtpSenderReplaceTrack(call, result),
    'rtpSenderSetTrack': (call, result) => this.rtpSenderSetTrack(call, result),
    'rtpSenderSetStreams': (call, result) => this.rtpSenderSetStreams(call, result),
    'getSenders': (call, result) => this.getSenders(call, result),
    'getReceivers': (call, result) => this.getReceivers(call, result),
    'getTransceivers': (call, result) => this.getTransceivers(call, result),
    'setPreferredInputDevice': (call, result) => this.setPreferredInputDevice(call, result),
    'getRtpSenderCapabilities': (call, result) => this.getRtpSenderCapabilities(call, result),
    'getRtpReceiverCapabilities': (call, result) => this.getRtpReceiverCapabilities(call, result),
    'setCodecPreferences': (call, result) => this.setCodecPreferences(call, result),
    'getSignalingState': (call, result) => this.getSignalingState(call, result),
    'getIceGatheringState': (call, result) => this.getIceGatheringState(call, result),
    'getIceConnectionState': (call, result) => this.getIceConnectionState(call, result),
    'getConnectionState': (call, result) => this.getConnectionState(call, result)
  };

  resultError(method: string, error: string, result?: MethodResult) {
    let errorMsg: string = `${method}(): ${error}`;
    Log.e(TAG, errorMsg);
    result?.error(method, error, null);
  }

  dispose(): void {
    this.recorders.forEach((recorder: TrackRecorder): void => {
      recorder.stop().catch((error: Error): void => Log.e(TAG, error.message));
    });
    this.recorders.clear();
    for (let mediaStream of this.localStreams.values()) {
      this.handleStreamDispose(undefined, mediaStream);
    }
    this.localStreams.clear();
    this.localTracks.clear();
    for (let connection of this.mPCO.values()) {
      connection?.dispose();
    }
    this.mPCO.clear();
    for (let i = 0; i < this.renders.length; i++) {
      const render: FlutterRTCVideoRenderer = this.renders.getValueAt(i);
      try { render.Dispose(); }
      catch (error) { Log.e(TAG, 'Renderer cleanup failed'); }
      finally { this.textures.unregisterTexture(render.getId()); }
    }
    this.renders.clear();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    let method: string = call.method;
    try {
      let fun = Reflect.get(this.methodHandlers, method) as Function;
      if (fun) {
        Log.d(TAG, `onMethodCall: ${method}`);
        fun(call, result);
      } else {
        this.frameCryptor.onMethodCall(call, result);
      }
    } catch (err) {
      this.resultError(method || 'onMethodCall', `failed: ${err}`, result);
    }
  }

  getPCO(call: MethodCall, result: MethodResult): PeerConnectionObserver | null {
    let pco = this.getPeerConnectionObserver(getPeerConnectionId(call));
    if (!pco || !pco.getPeerConnection()) {
      this.resultError(call.method, 'peerConnection is null', result);
      return null;
    }
    return pco;
  }

  getPeerConnection(call: MethodCall, result: MethodResult): RTCPeerConnection | null {
    let pco = this.getPCO(call, result);
    return pco?.getPeerConnection() ?? null;
  }

  getPeerConnectionObserver(peerConnectionId: string): PeerConnectionObserver | undefined {
    return this.mPCO.get(peerConnectionId);
  }

  getMediaStream(call: MethodCall, result: MethodResult, errorMsg?: string): MediaStream | undefined {
    let mediaStream = this.getLocalStreams(getStreamId(call));
    if (!mediaStream) {
      this.resultError(call.method, errorMsg || 'mediaStream is null', result);
    }
    return mediaStream;
  }

  getLocalStreams(streamId: string): MediaStream | undefined {
    return this.localStreams.get(streamId);
  }

  getMediaStreamTrack(call: MethodCall, result: MethodResult): MediaStreamTrack | null {
    let track = this.getLocalTrack(getTrackId(call));
    if (!track) {
      this.resultError(call.method, 'track is null', result);
      return null;
    }
    return track;
  }

  getLocalTrack(trackId: string): MediaStreamTrack | undefined {
    return this.localTracks.get(trackId);
  }

  initialize(call: MethodCall, result: MethodResult): void {
    let optionsMap: ConstraintsMap = getOptionsMap(call);
    let networkIgnoreMask: number = getOptionsNetworkIgnoreMask(optionsMap);
    let forceSWCodec: boolean = getOptionsForceSWCodec(optionsMap);
    let forceSWCodecList: ArrayList<String> = getOptionsForceSWCodecList(optionsMap);
    let audioConfiguration: ConstraintsMap = getOptionsAudioConfiguration(optionsMap);
    Log.d(TAG, `initialize optionsMap= ${optionsMap.toString()}`);
    Log.d(TAG, `initialize networkIgnoreMask= ${networkIgnoreMask}`);
    Log.d(TAG, `initialize forceSWCodec= ${forceSWCodec}`);
    Log.d(TAG, `initialize forceSWCodecList= ${forceSWCodecList}`);
    Log.d(TAG, `initialize audioConfiguration= ${audioConfiguration}`);

    if (this.pcf) {
      result.success(null);
      return;
    }

    /* 创建配对工厂 */
    AudioSwitchManager.instance.createAudioDeviceModule();
    this.createPeerConnectionFactory();

    this.getUserMediaImpl = new GetUserMediaImpl(this.stateProvider, this.context);
    // this.getUserMediaImpl.audioDeviceModule = this.adm!;

    // todo 待初始化其他部分接口，当前ohos-webrtc未满足
    result.success(null);
  }

  createPeerConnection(call: MethodCall, result: MethodResult): void {
    let configurationMap: ConstraintsMap = getConfigurationMap(call);
    let constraintsMap: ConstraintsMap = getConstraintsMap(call);
    Log.d(TAG, `createPeerConnection : configurationMap=${configurationMap.toString()}`);
    Log.d(TAG, `createPeerConnection : constraints=${constraintsMap.toString()}`);
    let peerConnectionId: string = this.peerConnectionInit(configurationMap, constraintsMap);
    let res: ConstraintsMap = new ConstraintsMap();
    res.putString('peerConnectionId', peerConnectionId);
    result.success(res.toMap());
  }

  getUserMedia(call: MethodCall, result: MethodResult): void {
    let constraintsMap: ConstraintsMap = getConstraintsMap(call);
    PermissionsManager.getInstance().processPermissions(constraintsMap, (code, err) => {
      if (code !== null) { result.error('permission_denied', err, code); return; }
      this.handleGetUserMedia(constraintsMap, result).catch((error: Error) => {
        result.error('getUserMedia', error.message, null);
      });
    }).catch((error: Error) => { result.error('getUserMedia', error.message, null); });
  }

  createLocalMediaStream(call: MethodCall, result: MethodResult): void {
    const stream = new MediaStream();
    this.localStreams.set(stream.id, stream);
    const response: DataMap = new Map();
    response.set('streamId', stream.id);
    result.success(response);
  }

  createOffer(call: MethodCall, result: MethodResult): void {
    let constraintsMap: ConstraintsMap = getConstraintsMap(call);
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    peerConnection.createOffer()
      .then((data) => {
        let params: DataMap = new Map();
        params.set('sdp', data.sdp);
        params.set('type', data.type);
        result.success(params);
      })
      .catch((data: Any) => {
        this.resultError(
          call.method,
          'WEBRTC_CREATE_OFFER_ERROR: peerConnection.createOffer catch: ' + JSON.stringify(data),
          result
        )
      })
  }

  createAnswer(call: MethodCall, result: MethodResult): void {
    let constraintsMap: ConstraintsMap = getConstraintsMap(call);
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    peerConnection.createAnswer()
      .then((data) => {
        let map: DataMap = new Map();
        map.set('sdp', data.sdp);
        map.set('type', data.type);
        result.success(map);
      })
      .catch((data: Any) => {
        this.resultError(
          call.method,
          'WEBRTC_CREATE_ANSWER_ERROR: ' + JSON.stringify(data),
          result
        );
      })
  }

  mediaStreamGetTracks(call: MethodCall, result: MethodResult): void {
    let streamId: string = getStreamId(call);
    Log.d(TAG, 'mediaStreamGetTracks streamId= ' + streamId);
    let stream: MediaStream = this.getStreamForId(streamId, '');
    let resultMap: DataMap = new Map();
    let audioTracks: DataArray = [];
    let videoTracks: DataArray = [];
    stream.getAudioTracks().forEach(track => {
      this.localTracks.set(track.id, track);
      audioTracks.push(mediaStreamTrackToMap(track));
    });
    stream.getVideoTracks().forEach(track => {
      this.localTracks.set(track.id, track);
      videoTracks.push(mediaStreamTrackToMap(track));
    });
    resultMap.set('audioTracks', audioTracks);
    resultMap.set('videoTracks', videoTracks);
    result.success(resultMap);
  }

  addStream(call: MethodCall, result: MethodResult): void {
    let mediaStream = this.getMediaStream(call, result);
    if (!mediaStream) {
      return;
    }
    let peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    //addStream,新webrtc的最新规范中被废弃，建议使用 addTrack 方法作为替代。
    if (mediaStream.getTracks() != null && mediaStream.getTracks().length > 0) {
      let sender = peerConnection.addTrack(mediaStream.getTracks()[0], mediaStream);
    }
    Log.d(TAG, 'addStream' + result);
    result.success(false);
  }

  removeStream(call: MethodCall, result: MethodResult): void {
    let mediaStream = this.getMediaStream(call, result);
    if (!mediaStream) {
      return;
    }
    let peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    //removeStream,新webrtc的最新规范中被废弃，建议使用 removeTrack 方法作为替代。
    if (mediaStream.getTracks() != null && mediaStream.getTracks().length > 0) {
      let tracks = mediaStream.getTracks()[0];
      let pco = this.getPCO(call, result);
      let sender = pco?.getRtpSenderById(tracks.id);
      if (!sender) {
        this.resultError('peerConnectionRemoveStream', ' removeTrack sender is null', result);
        return;
      }
      peerConnection.removeTrack(sender);
    }
    result.success(null);
  }

  setLocalDescription(call: MethodCall, result: MethodResult): void {
    let peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let descriptionMap: ConstraintsMap = getDescriptionMap(call);
    let sdp: string = descriptionMap.getString('sdp');
    let type = descriptionMap.getString('type') as RTCSdpType;
    let sdpInit: RTCSessionDescriptionInit = {
      sdp: sdp, type: type
    }
    peerConnection.setLocalDescription(sdpInit)
      .then(() => {
        result.success(null)
      })
      .catch((data: Any) => {
        this.resultError(
          call.method,
          'WEBRTC_SET_LOCAL_DESCRIPTION_ERROR: peerConnection.setLocalDescription catch: ' + JSON.stringify(data),
          result)
      })
  }

  setRemoteDescription(call: MethodCall, result: MethodResult): void {
    let peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let descriptionMap: ConstraintsMap = getDescriptionMap(call);
    let sdp: string = descriptionMap.getString('sdp');
    let type = descriptionMap.getString('type') as RTCSdpType;
    let sdpInit: RTCSessionDescriptionInit = {
      sdp: sdp, type: type
    }
    peerConnection.setRemoteDescription(sdpInit)
      .then(() => {
        result.success(null)
      })
      .catch((data: Any) => {
        this.resultError(
          call.method,
          'WEBRTC_SET_REMOTE_DESCRIPTION_ERROR: peerConnection.setRemoteDescription catch: ' + JSON.stringify(data),
          result)
      })
  }

  sendDtmf(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let audioSender: RTCRtpSender = new RTCRtpSender();
    peerConnection.getSenders().forEach(sender => {
      if (sender.track?.kind === 'audio') {
        audioSender = sender;
        return;
      }
    });
    if (audioSender.dtmf) {
      let dtmfSender = audioSender.dtmf;
      let tone: string = getTone(call);
      Log.d(TAG, 'sendDtmf tone= ' + tone);
      let duration: number | undefined = getDuration(call);
      Log.d(TAG, 'sendDtmf duration= ' + duration);
      let gap: number | undefined = getGap(call);
      Log.d(TAG, 'sendDtmf gap= ' + gap);
      dtmfSender.insertDTMF(tone, duration, gap);
    } else {
      Log.d(TAG, 'sendDtmf audioSender.dtmf is null');
    }
    result.success('success');
  }

  addCandidate(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    let candidateMap: ConstraintsMap = getCandidateMap(call);
    let sdpMLineIndex: number = 0;
    if (candidateMap.getType('sdpMLineIndex') === ObjectType.Number) {
      sdpMLineIndex = candidateMap.getNumber('sdpMLineIndex');
    }
    let candidate: RTCIceCandidateInit = {
      sdpMid: candidateMap.getString('sdpMid'),
      sdpMLineIndex: sdpMLineIndex,
      candidate: candidateMap.getString('candidate')
    }
    peerConnection.addIceCandidate(candidate).then(() => {
      result.success(true);
    }).catch(() => {
      result.success(false);
    });
  }

  getStats(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    let pco = this.getPCO(call, result);
    if (!pco) {
      return;
    }
    if (trackId == '') {
      pco.getStats(result);
    } else {
      pco.getStatsForTrack(trackId, result);
    }
  }

  createDataChannel(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.createDataChannel(getLabel(call), getDataChannelDictMap(call), result);
  }

  dataChannelSend(call: MethodCall, result: MethodResult): void {
    const isBinary: boolean = getType(call) === 'binary';
    let byteBuffer: buffer.Buffer;
    if (isBinary) {
      byteBuffer = buffer.from(call.argument('data'));
    } else {
      let data: string = call.argument('data');
      byteBuffer = buffer.from(data, 'utf-8');
    }
    this.getPCO(call, result)?.dataChannelSend(getDataChannelId(call), byteBuffer.buffer, isBinary);
    result.success(null);
  }

  dataChannelClose(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.dataChannelClose(getDataChannelId(call));
    result.success(null);
  }

  streamDispose(call: MethodCall, result: MethodResult): void {
    let disposeStreamId: string = getStreamId(call);
    Log.d(TAG, 'streamDispose streamId= ' + disposeStreamId);
    this.handleStreamDispose(disposeStreamId, undefined);
    Log.d(TAG, 'streamDispose end');
    result.success(null);
    Log.d(TAG, 'streamDispose result.success end');
  }

  mediaStreamTrackSetEnable(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamTrackSetEnable trackId= ' + trackId);
    let enabled: boolean = call.argument('enabled');
    Log.d(TAG, 'mediaStreamTrackSetEnable enabled= ' + enabled);
    let peerConnectionId: string = getPeerConnectionId(call);
    Log.d(TAG, 'mediaStreamTrackSetEnable peerConnectionId= ' + peerConnectionId);

    let track = this.getTrackForId(trackId, peerConnectionId);
    if (track == null) {
      Log.d(TAG, 'mediaStreamTrackSetEnabled() track is null');
      return;
    } else if (track.enabled == enabled) {
      return;
    }
    track.enabled = enabled;
    result.success(null);
  }

  mediaStreamAddTrack(call: MethodCall, result: MethodResult): void {
    let streamId: string = getStreamId(call);
    Log.d(TAG, 'mediaStreamAddTrack streamId= ' + streamId);
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamAddTrack trackId= ' + trackId);
    let mediaStream = this.getMediaStream(call, result);
    if (!mediaStream) {
      this.resultError('mediaStreamAddTrack', 'mediaStreamAddTrack() stream [' + streamId + '] is null', result);
      return
    }
    let track = this.getTrackForId(trackId);
    if (!track) {
      this.resultError('mediaStreamAddTrack', 'mediaStreamAddTrack() track [' + trackId + '] is null', result);
      return
    }
    let kind = track.kind;
    //TODO kind 无 audio，需要替换情况
    if (kind === 'audio') {
      mediaStream.addTrack(track);
      result.success(null);
    } else if (kind === 'video') {
      mediaStream.addTrack(track);
      result.success(null);
    } else {
      this.resultError('mediaStreamAddTrack',
        'mediaStreamAddTrack() track [' + trackId + '] has unsupported type: ' + kind, result);
    }

    for (let i = 0; i < this.renders.length; i++) {
      let renderer = this.renders.getValueAt(i);
      if (renderer.checkMediaStream(streamId, 'local')) {
        renderer.setVideoTrack(this.localTracks.get(trackId));
      }
    }
  }

  mediaStreamRemoveTrack(call: MethodCall, result: MethodResult): void {
    let streamId: string = getStreamId(call);
    Log.d(TAG, 'mediaStreamRemoveTrack streamId= ' + streamId);
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamRemoveTrack trackId= ' + trackId);
    this.handleMediaStreamRemoveTrack(streamId, trackId, result);
    this.removeStreamForRendererById(streamId);
  }

  trackDispose(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'trackDispose id : ' + trackId);
    Log.d(TAG, 'trackDispose() track is null');
    let track = this.getMediaStreamTrack(call, result);
    if (!track) {
      return;
    }
    track.enabled = false
    track.stop()
    this.removeTrackForRendererById(trackId);

    if (track.kind == 'video') {
      // getUserMediaImpl.removeVideoCapturer(trackId); ohos不存在这一步
    }
    this.localTracks.remove(trackId)
    result.success(null);
  }

  restartIce(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.restartIce();
    result.success(null);
  }

  peerConnectionClose(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.close();
    result.success(null);
  }

  peerConnectionDispose(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.dispose();
    result.success(null);
  }

  createVideoRenderer(call: MethodCall, result: MethodResult): void {
    let textureId = this.textures.getTextureId();
    const entry = this.textures.registerTexture(textureId);
    let render: FlutterRTCVideoRenderer;
    try {
      render = new FlutterRTCVideoRenderer(textureId, this.stateProvider, this.textures);
      render.init(entry.getSurfaceId().toString());
    } catch (error) {
      this.textures.unregisterTexture(textureId);
      throw error as Error;
    }
    Log.d(TAG, 'createVideoRenderer create FlutterRTCVideoRenderer !')
    this.renders.add(textureId, render);
    let eventChannel: EventChannel =
      new EventChannel(this.messenger, 'FlutterWebRTC/Texture' + textureId);
    eventChannel.setStreamHandler(render);
    render.setEventChannel(eventChannel);
    render.setId(textureId);
    let params: ConstraintsMap = new ConstraintsMap();
    params.putNumber('textureId', textureId);
    Log.d(TAG, 'createVideoRenderer  result.success：' + Array.from(params.toMap().entries()))
    result.success(params.toMap());
  }

  videoRendererDispose(call: MethodCall, result: MethodResult): void {
    let textureId: number = call.argument('textureId');
    Log.d(TAG, 'videoRendererDispose textureId= ' + textureId);
    let render: FlutterRTCVideoRenderer = this.renders.get(textureId);
    if (!render) {
      this.resultError('videoRendererDispose', `render [${textureId}] not found !`, result);
      return;
    }
    try { render.Dispose(); } finally { this.textures.unregisterTexture(textureId); this.renders.remove(textureId); }
    result.success(null);
  }

  videoRendererSetSrcObject(call: MethodCall, result: MethodResult): void {
    let textureId: number = call.argument('textureId');
    let surfaceId: string = call.argument('surfaceId');
    let streamId: string = getStreamId(call);
    let ownerTag: string = call.argument('ownerTag');
    let trackId: string = getTrackId(call);

    Log.d(TAG, 'videoRendererSetSrcObject textureId= ' + textureId);
    Log.d(TAG, 'videoRendererSetSrcObject streamId= ' + streamId);
    Log.d(TAG, 'videoRendererSetSrcObject ownerTag= ' + ownerTag);
    Log.d(TAG, 'videoRendererSetSrcObject trackId= ' + trackId);
    Log.d(TAG, 'videoRendererSetSrcObject surfaceId= ' + surfaceId);

    let videoRender: FlutterRTCVideoRenderer = this.renders.get(textureId);
    if (!videoRender) {
      this.resultError('videoRendererSetSrcObject', `videoRender [${textureId}] not found !`, result);
      return;
    }
    // Current Flutter API only sends textureId; its native surface is created with the renderer.
    if (!surfaceId) surfaceId = videoRender.getSurfaceId();
    if (surfaceId != '' && videoRender.getSurfaceId() != surfaceId) {
      videoRender.init(surfaceId);
    }
    let stream: MediaStream;
    if (ownerTag === 'local') {
      stream = this.localStreams.get(streamId);
    } else {
      stream = this.getStreamForId(streamId, ownerTag);
    }
    if (trackId != null && !(trackId === '0')) {
      videoRender.setStream(stream, ownerTag, trackId);
    } else {
      videoRender.setStream(stream, ownerTag);
    }
    result.success(null);
  }

  mediaStreamTrackHasTorch(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamTrackHasTorch trackId= ' + trackId);
    if (this.getUserMediaImpl) {
      Log.d(TAG, 'mediaStreamTrackHasTorch hasTorch in!')
      this.getUserMediaImpl.hasTorch(trackId, result);
    } else {
      this.resultError('mediaStreamTrackHasTorch', 'getUserMediaImpl null !', result);
    }
  }

  mediaStreamTrackSetTorch(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamTrackSetTorch trackId= ' + trackId);
    let torch: boolean = call.argument('torch');
    Log.d(TAG, 'mediaStreamTrackSetTorch torch= ' + torch);
    if (this.getUserMediaImpl) {
      // TODO 无法通过trackID获取到camera进行闪光灯控制，需要添加接口调用底层功能。
      this.getUserMediaImpl.setTorch(torch, result);
    } else {
      this.resultError('mediaStreamTrackSetTorch', 'getUserMediaImpl null !', result);
    }
  }

  mediaStreamTrackSetZoom(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamTrackSetZoom trackId= ' + trackId);
    let zoomLevel: number = call.argument('zoomLevel');
    Log.d(TAG, 'mediaStreamTrackSetZoom zoomLevel= ' + zoomLevel);
    if (this.getUserMediaImpl) {
      // TODO 无法通过trackID获取到camera进行相机缩放，需要添加接口调用底层功能。
      this.getUserMediaImpl.setZoom(trackId, zoomLevel, result);
    } else {
      this.resultError('mediaStreamTrackSetZoom', 'getUserMediaImpl null !', result);
    }
  }

  mediaStreamTrackSwitchCamera(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    Log.d(TAG, 'mediaStreamTrackSetTorch trackId= ' + trackId);
    if (this.getUserMediaImpl) {
      // TODO 无法通过trackID获取到camera进行相机切换，需要添加接口调用底层功能进行切换。
      /*
       * 修改实现方式，切换摄像头，await sender.replaceTrack(newTrack); 通过替换videoTrack
       * 首先得判断当前相机是否打开，既已经获取过 getUserMedia
       * 从track获取到 mediaStream
       * 最终获取到 rtpSender
       * */
      this.getUserMediaImpl.switchCamera(trackId, result);
    } else {
      this.resultError('mediaStreamTrackSwitchCamera', 'getUserMediaImpl null !', result);
    }
  }

  setVolume(call: MethodCall, result: MethodResult): void {
    let trackId: string = getTrackId(call);
    let volume: number = call.argument('volume') ?? -1;
    let peerConnectionId: string = getPeerConnectionId(call);
    this.mediaStreamTrackSetVolume(trackId, volume, peerConnectionId);
    result.success(null);
  }

  selectAudioOutput(call: MethodCall, result: MethodResult): void {
    let deviceId: string = call.argument('deviceId');
    Log.d(TAG, 'selectAudioOutput deviceId= ' + deviceId);
    this.completeAudioOperation(AudioSwitchManager.instance.selectAudioOutput(parseInt(deviceId)), result);
  }

  setMicrophoneMute(call: MethodCall, result: MethodResult): void {
    let mute: boolean = call.argument('mute');
    AudioSwitchManager.instance.setMicrophoneMute(mute)
    result.success(null);
  }

  selectAudioInput(call: MethodCall, result: MethodResult): void {
    this.completeAudioOperation(AudioSwitchManager.instance.selectAudioInput(call.argument('deviceId')), result);
  }

  setOhosAudioConfiguration(call: MethodCall, result: MethodResult): void {
    let configuration: ConstraintsMap = getConfigurationMap(call);
    AudioSwitchManager.instance.setAudioConfiguration(configuration);
    result.success(null);
  }

  private completeAudioOperation(operation: Promise<void>, result: MethodResult): void {
    operation.then((): void => result.success(null)).catch((error: Error) => result.error('audio_route_error', error.message, null));
  }
  enableSpeakerphone(call: MethodCall, result: MethodResult): void {
    let mute: boolean = call.argument('enable');
    this.completeAudioOperation(AudioSwitchManager.instance.enableSpeakerphone(mute), result);
  }

  enableSpeakerphoneButPreferBluetooth(call: MethodCall, result: MethodResult): void {
    this.completeAudioOperation(AudioSwitchManager.instance.enableSpeakerButPreferBluetooth(), result);
  }

  async getDisplayMedia(call: MethodCall, result: MethodResult): Promise<void> {
    let constraints: ConstraintsMap = getConstraintsMap(call);
    let mediaOption: DisplayMediaStreamOptions = {}
    if (constraints.getType('audio') === ObjectType.Boolean) {
      mediaOption.audio = constraints.getBoolean('audio')
    } else if (constraints.getType('audio') == ObjectType.Map) {
      let audioOption: ConstraintsMap = constraints.getMap('audio')!
      mediaOption.audio = this.getMediaTrackConstraints(audioOption.toMap())
    }

    if (constraints.getType('video') === ObjectType.Boolean) {
      mediaOption.video = constraints.getBoolean('video')
    } else if (constraints.getType('video') == ObjectType.Map) {
      let videoOptionMap: ConstraintsMap = constraints.getMap('video')!
      mediaOption.video = this.getMediaTrackConstraints(videoOptionMap.toMap())
    }

    Log.e(TAG, `mediaOption get . ${JSON.stringify(mediaOption)}`);
    let mediaDevices = new MediaDevices();
    let mediaStream: MediaStream = await mediaDevices.getDisplayMedia(mediaOption);
    let streamId: string = mediaStream.id ?? this.getNextStreamUUID();
    Log.d(TAG, 'getDisplayMedia mediaStream.id streamId= ' + streamId)

    if (!mediaStream) {
      this.resultError('getDisplayMedia', 'Failed to create new media stream', result);
      return;
    }

    let params: DataMap = new Map()
    params.set('streamId', mediaStream.id)
    Log.d(TAG, 'getDisplayMedia userMedia.id= ' + mediaStream.id)

    let userVideoTracks: DataMap[] = []
    for (let videoTrack of mediaStream.getVideoTracks()) {
      let map: DataMap = new Map()
      map.set('enabled', videoTrack.enabled)
      map.set('id', videoTrack.id)
      map.set('kind', videoTrack.kind)
      map.set('label', videoTrack.kind)
      map.set('readyState', videoTrack.readyState)
      map.set('remote', false)
      userVideoTracks.push(map)
      this.localTracks.set(videoTrack.id, videoTrack)
    }

    let userAudioTracks: DataMap[] = []
    for (let audioTrack of mediaStream.getAudioTracks()) {
      let map: DataMap = new Map()
      map.set('enabled', audioTrack.enabled)
      map.set('id', audioTrack.id)
      map.set('kind', audioTrack.kind)
      map.set('label', audioTrack.kind)
      map.set('readyState', audioTrack.readyState)
      map.set('remote', false)
      this.localTracks.set(audioTrack.id, audioTrack)
      userAudioTracks.push(map)
    }
    params.set('videoTracks', userVideoTracks)
    params.set('audioTracks', userAudioTracks)
    this.localStreams.set(mediaStream.id, mediaStream)
    result.success(params)
  }

  startRecordToFile(call: MethodCall, result: MethodResult): void {
    // The old ADM exposes no production input/output sample sink. Never replace
    // the requested WebRTC audio with a second, unrelated microphone capture.
    if (call.argument('audioChannel') !== null && call.argument('audioChannel') !== undefined) {
      result.error('unsupported_operation', 'The OHOS runtime has no WebRTC recording audio sink; video-only MP4 is supported', null);
      return;
    }
    const id: number = call.argument('recorderId');
    if (this.recorders.has(id)) { result.error('recording_active', 'Recorder already started', null); return; }
    const track = this.getTrackForId(call.argument('videoTrackId'), getPeerConnectionId(call));
    if (!track || track.kind !== 'video') { result.error('invalid_track', 'A live video track is required', null); return; }
    let width = 640; let height = 480;
    for (let i = 0; i < this.renders.length; i++) {
      const render = this.renders.getValueAt(i);
      if (render.hasVideoTrack(track.id) && render._width > 0 && render._height > 0) {
        width = render._width; height = render._height; break;
      }
    }
    const recorder = new TrackRecorder();
    this.recorders.set(id, recorder);
    recorder.start(call.argument('path'), track, width, height).then((): void => result.success(null))
      .catch((error: Error): void => { this.recorders.delete(id); result.error('recording_error', error.message, null); });
  }

  stopRecordToFile(call: MethodCall, result: MethodResult): void {
    const id: number = call.argument('recorderId');
    const recorder = this.recorders.get(id);
    if (!recorder) { result.error('recording_inactive', 'Recorder not started', null); return; }
    this.recorders.delete(id);
    recorder.stop().then((): void => result.success(null))
      .catch((error: Error): void => result.error('recording_error', error.message, null));
  }

  captureFrame(call: MethodCall, result: MethodResult): void {
    const trackId: string = getTrackId(call);
    for (let i = 0; i < this.renders.length; i++) {
      const render = this.renders.getValueAt(i);
      if (render.hasVideoTrack(trackId) && render._width > 0 && render._height > 0) {
        this.saveSurfaceFrame(render, call.argument('path')).then((): void => result.success(null))
          .catch((error: Error): void => result.error('capture_error', error.message, null));
        return;
      }
    }
    result.error('frame_unavailable', 'Render the requested track and wait for its first frame before capturing', null);
  }

  private async saveSurfaceFrame(render: FlutterRTCVideoRenderer, path: string): Promise<void> {
    const pixels = await image.createPixelMapFromSurface(render.getSurfaceId(), {
      x: 0, y: 0, size: { width: render._width, height: render._height }
    });
    let packer: image.ImagePacker | undefined;
    try {
      packer = image.createImagePacker();
      const data = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        if (fs.writeSync(file.fd, data) !== data.byteLength) throw new Error('Incomplete PNG write');
      } finally { fs.closeSync(file); }
    } finally {
      try { await packer?.release(); } finally { await pixels.release(); }
    }
  }

  getLocalDescription(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let sdp = peerConnection.localDescription;
    let params: ConstraintsMap = new ConstraintsMap()
    params.putString('sdp', sdp!.sdp)
    params.putString('type', sdp!.type);
    result.success(params.toMap());
  }

  getRemoteDescription(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let sdp = peerConnection.remoteDescription;
    if (!sdp) {
      result.success(null);
      return
    }
    let params: ConstraintsMap = new ConstraintsMap();
    params.putString('sdp', sdp.sdp);
    params.putString('type', sdp.type);
    result.success(params.toMap());
  }

  setConfiguration(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let configurationMap: ConstraintsMap = getConfigurationMap(call);
    peerConnection.setConfiguration(this.parseRTCConfiguration(configurationMap));
    result.success(null);
  }

  addTrack(call: MethodCall, result: MethodResult): void {
    let pco = this.getPCO(call, result);
    if (!pco) {
      return;
    }
    let track = this.getMediaStreamTrack(call, result);
    if (!track) {
      return;
    }
    let streamIds: string[] = getStreamIds(call);
    let streams: MediaStream[] = [];
    for (let streamId of streamIds) {
      if (this.localStreams.hasKey(streamId)) {
        streams.push(this.localStreams.get(streamId));
      }
    }
    pco.addTrack(track, streams, result);
  }

  removeTrack(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.removeTrack(getSenderId(call), result);
  }

  addTransceiver(call: MethodCall, result: MethodResult): void {
    const pco = this.getPCO(call, result);
    if (!pco) {
      return;
    }
    let transceiverInit: DataMap = call.argument('transceiverInit');
    if (call.hasArgument('trackId')) {
      let track = this.getMediaStreamTrack(call, result);
      if (!track) {
        return;
      }
      let streams: MediaStream[] = []
      //获取flutter层传下来的流
      if (transceiverInit.has('streamIds')){
        let streamIds:string[] = transceiverInit.get('streamIds')
        streamIds.forEach((id) => {
          if (this.localStreams.hasKey(id)) {
            streams.push(this.localStreams.get(id))
          }
        })
      }
      //寻找附加的track的视频流
      this.localStreams.forEach((stream) => {
        if (stream?.getTracks().find((item) => item.id == track?.id)) {
          if (streams.find((item) => item.id == stream.id)) {
            return
          }
          streams.push(stream)
        }
      })
      if (streams.length > 0) {
        transceiverInit.set("streams", streams)
      }
      pco.addTransceiver(track, result, transceiverInit);
    } else if (call.hasArgument('mediaType')) {
      let mediaType: string = call.argument('mediaType')
      pco.addTransceiver(mediaType, result, transceiverInit);
    } else {
      this.resultError(call.method, 'Incomplete parameters', result);
    }
  }

  rtpTransceiverSetDirection(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.rtpTransceiverSetDirection(getDirection(call), getTransceiverId(call), result);
  }

  rtpTransceiverGetDirection(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.rtpTransceiverGetDirection(getTransceiverId(call), result);
  }

  rtpTransceiverGetCurrentDirection(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.rtpTransceiverGetCurrentDirection(getTransceiverId(call), result);
  }

  rtpTransceiverStop(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.rtpTransceiverStop(getTransceiverId(call), result);
  }

  rtpSenderSetParameters(call: MethodCall, result: MethodResult): void {
    let parameters: DataMap = call.argument('parameters');
    this.getPCO(call, result)?.rtpSenderSetParameters(getRtpSenderId(call), parameters, result);
  }

  rtpSenderReplaceTrack(call: MethodCall, result: MethodResult): void {
    this.handleRtpSenderSetTrack(call, result, true);
  }

  rtpSenderSetTrack(call: MethodCall, result: MethodResult): void {
    this.handleRtpSenderSetTrack(call, result, false);
  }

  rtpSenderSetStreams(call: MethodCall, result: MethodResult): void {
    let pco = this.getPCO(call, result);
    if (!pco) {
      return;
    }
    let rtpSenderId: string = getRtpSenderId(call);
    let streamIds: string[] = getStreamIds(call);
    let streams: MediaStream[] = [];
    for (let streamId of streamIds) {
      if (this.localStreams.hasKey(streamId)) {
        streams.push(this.localStreams.get(streamId));
      }
      pco.rtpSenderSetStreams(rtpSenderId, streams, result);
    }
  }

  getSenders(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.getSenders(result);
  }

  getReceivers(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.getReceivers(result);
  }

  getTransceivers(call: MethodCall, result: MethodResult): void {
    this.getPCO(call, result)?.getTransceivers(result);
  }

  setPreferredInputDevice(call: MethodCall, result: MethodResult): void {
    this.selectAudioInput(call, result);
  }

  getRtpSenderCapabilities(call: MethodCall, result: MethodResult): void {
    let kind: string = call.argument('kind') ?? '';
    let mediaType: string = kind === 'video' ? 'video' : 'audio';
    let capabilities = RTCRtpSender.getCapabilities(mediaType)
    if (capabilities) {
      let params: DataMap = capabilitiesToMap(capabilities);
      result.success(params)
    } else {
      this.resultError('getRtpReceiverCapabilities', 'peerConnection is null', result)
    }
  }

  getRtpReceiverCapabilities(call: MethodCall, result: MethodResult): void {
    let kind: string = call.argument('kind') ?? '';
    let mediaType: string = kind === 'video' ? 'video' : 'audio';
    let capabilities = RTCRtpReceiver.getCapabilities(mediaType)
    if (capabilities) {
      let params: DataMap = capabilitiesToMap(capabilities);
      result.success(params)
    } else {
      this.resultError('getRtpReceiverCapabilities', 'peerConnection is null', result)
    }
  }

  setCodecPreferences(call: MethodCall, result: MethodResult): void {
    let codecs: DataMap[] = call.argument('codecs');
    this.getPCO(call, result)?.rtpTransceiverSetCodecPreferences(getTransceiverId(call), codecs, result);
  }

  getSignalingState(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    let params: DataMap = new Map();
    params.set('state', peerConnection.signalingState);
    result.success(params);
  }

  getIceGatheringState(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return;
    }
    let params: DataMap = new Map();
    params.set('state', peerConnection.iceGatheringState);
    result.success(params);
  }

  getIceConnectionState(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let params: DataMap = new Map()
    params.set('state', peerConnection.iceConnectionState)
    result.success(params)
  }

  getConnectionState(call: MethodCall, result: MethodResult): void {
    const peerConnection = this.getPeerConnection(call, result);
    if (!peerConnection) {
      return
    }
    let params: DataMap = new Map()
    params.set('state', peerConnection.connectionState)
    result.success(params)
  }

  async createVideoEncoderFactory() {
    Log.d(TAG, 'this.videoEncoderFactory: ');
  }

  createPeerConnectionFactory(): void {
    /**/
    this.pcf = new PeerConnectionFactory({
      adm: AudioSwitchManager.instance.getAudioDeviceModule()
    });
    // MediaDevices also resolves the native default factory. Use the same ADM
    // for capture, mute, audio routing and the actual peer connections.
    PeerConnectionFactory.setDefault(this.pcf);
    Log.d(TAG, 'Log this.pcf: ' + JSON.stringify(this.pcf));

    // Production capture must not enable the upstream debug AEC audio dump.
  }

  peerConnectionInit(configurationMap: ConstraintsMap, constraintsMap: ConstraintsMap) {
    let peerConnectionId: string = this.getNextStreamUUID();
    Log.d(TAG, 'peerConnectionInit peerConnectionId= ' + peerConnectionId)
    let conf: RTCConfiguration = this.parseRTCConfiguration(configurationMap);
    let peerConnection: RTCPeerConnection = this.getPeerConnectionFactory().createPeerConnection(conf);
    let observer: PeerConnectionObserver =
      new PeerConnectionObserver(conf, this, this.messenger, peerConnectionId, peerConnection);
    this.mPCO.set(peerConnectionId, observer);
    return peerConnectionId;
  }

  parseRTCConfiguration(map: ConstraintsMap): RTCConfiguration {
    let iceServersArray = new ConstraintsArray();
    if (map.getType('iceServers') === ObjectType.Array) {
      iceServersArray = map.getArray('iceServers')!;
      Log.d(TAG, 'parseRTCConfiguration iceServersArray= ' + iceServersArray)
    }
    let conf: RTCConfiguration = {
      iceServers: this.createIceServers(iceServersArray)
    };
    Log.d(TAG, 'parseRTCConfiguration conf= ' + JSON.stringify(conf))
    return applyTransportConfig(conf, map.toMap());
  }

  createIceServers(iceServersArray: ConstraintsArray): RTCIceServer[] {
    Log.d(TAG, 'createIceServers in')
    let iceServers: RTCIceServer[] = []
    for (let i = 0; i < iceServersArray.size(); i++) {
      if (iceServersArray.getType(i) !== ObjectType.Map) {
        continue;
      }
      let iceServerMap: ConstraintsMap = new ConstraintsMap(iceServersArray.getMap(i));
      let hasUsernameAndCredential: boolean =
        iceServerMap.hasKey('username') && iceServerMap.hasKey('credential');
      if (iceServerMap.hasKey('url')) {
        if (hasUsernameAndCredential) {
          iceServers.push({
            urls: iceServerMap.getString('url'),
            username: iceServerMap.getString('username'),
            credential: iceServerMap.getString('credential')
          })
        }
      } else if (iceServerMap.hasKey('urls')) {
        if (hasUsernameAndCredential) {
          iceServers.push({
            urls: iceServerMap.getString('urls'),
            username: iceServerMap.getString('username'),
            credential: iceServerMap.getString('credential')
          })
        } else {
          iceServers.push({
            urls: iceServerMap.getString('urls'),
          })
        }
      }
    }
    return iceServers
  }

  putLocalStream(streamId: string, stream: MediaStream): boolean {
    this.localStreams.set(streamId, stream);
    return true;
  }

  putLocalTrack(trackId: string, track: MediaStreamTrack): boolean {
    this.localTracks.set(trackId, track);
    return true;
  }

  getNextTrackUUID(): string {
    let uuid: string = '';
    do {
      uuid = util.generateRandomUUID();
    } while (this.getTrackForId(uuid) != null);

    return uuid;
  }

  getPeerConnectionFactory(): PeerConnectionFactory {
    if (this.pcf) {
      return this.pcf;
    }
    return new PeerConnectionFactory({
      adm: AudioSwitchManager.instance.getAudioDeviceModule()
    });
  }

  getAbility(): UIAbility | null {
    return this.ability;
  }

  getApplicationContext(): common.ApplicationContext | undefined {
    return this.context.getApplicationContext();
  }

  getMessenger(): BinaryMessenger {
    return this.messenger;
  }

  public async handleGetUserMedia(constraints: ConstraintsMap, result: MethodResult) {
    let mediaOption: MediaStreamConstraints = {}
    if (constraints.getType('audio') === ObjectType.Boolean) {
      mediaOption.audio = constraints.getBoolean('audio')
    } else if (constraints.getType('audio') == ObjectType.Map) {
      let audioOption: ConstraintsMap = constraints.getMap('audio')!
      mediaOption.audio = this.getMediaTrackConstraints(audioOption.toMap())
    }

    if (constraints.getType('video') === ObjectType.Boolean) {
      mediaOption.video = constraints.getBoolean('video')
    } else if (constraints.getType('video') == ObjectType.Map) {
      let videoOptionMap: ConstraintsMap = constraints.getMap('video')!
      mediaOption.video = this.getMediaTrackConstraints(videoOptionMap.toMap())
    }

    Log.e(TAG, `mediaOption get . ${JSON.stringify(mediaOption)}`);

    let params: DataMap = new Map()
    let mediaDevices = new MediaDevices();
    let userMedia: MediaStream = await mediaDevices.getUserMedia(mediaOption);
    params.set('streamId', userMedia.id)

    let userVideoTracks: DataMap[] = []
    for (let userVideoTrack of userMedia.getVideoTracks()) {
      let map: DataMap = new Map()
      map.set('enabled', userVideoTrack.enabled)
      map.set('id', userVideoTrack.id)
      map.set('kind', userVideoTrack.kind)
      map.set('label', userVideoTrack.kind)
      map.set('readyState', userVideoTrack.readyState)
      map.set('remote', false)
      userVideoTracks.push(map)
      this.localTracks.set(userVideoTrack.id, userVideoTrack)
    }

    let userAudioTracks: DataMap[] = []
    for (let userAudioTrack of userMedia.getAudioTracks()) {
      let map: DataMap = new Map()
      map.set('enabled', userAudioTrack.enabled)
      map.set('id', userAudioTrack.id)
      map.set('kind', userAudioTrack.kind)
      map.set('label', userAudioTrack.kind)
      map.set('readyState', userAudioTrack.readyState)
      map.set('remote', false)
      this.localTracks.set(userAudioTrack.id, userAudioTrack)
      userAudioTracks.push(map)
    }

    params.set('videoTracks', userVideoTracks)
    params.set('audioTracks', userAudioTracks)
    this.localStreams.set(userMedia.id, userMedia)
    Log.e(TAG, `mediaOption get . ${JSON.stringify(mediaOption)}`);
    result.success(params)
  }

  getMediaTrackConstraints(videoOptionMap: DataMap): MediaTrackConstraints {
    let videoOption: MediaTrackConstraints = {}
    if (videoOptionMap.has('width')) {
      videoOption.width = videoOptionMap.get('width')
    }
    if (videoOptionMap.has('height')) {
      videoOption.height = videoOptionMap.get('height')
    }
    if (videoOptionMap.has('aspectRatio')) {
      videoOption.aspectRatio = videoOptionMap.get('aspectRatio')
    }
    if (videoOptionMap.has('frameRate')) {
      videoOption.frameRate = videoOptionMap.get('frameRate')
    }
    if (videoOptionMap.has('facingMode')) {
      videoOption.facingMode = videoOptionMap.get('facingMode')
    }
    if (videoOptionMap.has('resizeMode')) {
      videoOption.resizeMode = videoOptionMap.get('resizeMode')
    }
    if (videoOptionMap.has('sampleRate')) {
      videoOption.sampleRate = videoOptionMap.get('sampleRate')
    }
    if (videoOptionMap.has('sampleSize')) {
      videoOption.sampleSize = videoOptionMap.get('sampleSize')
    }
    if (videoOptionMap.has('echoCancellation')) {
      videoOption.echoCancellation = videoOptionMap.get('echoCancellation')
    }
    if (videoOptionMap.has('autoGainControl')) {
      videoOption.autoGainControl = videoOptionMap.get('autoGainControl')
    }
    if (videoOptionMap.has('noiseSuppression')) {
      videoOption.noiseSuppression = videoOptionMap.get('noiseSuppression')
    }
    if (videoOptionMap.has('latency')) {
      videoOption.latency = videoOptionMap.get('latency')
    }
    if (videoOptionMap.has('channelCount')) {
      videoOption.channelCount = videoOptionMap.get('channelCount')
    }
    if (videoOptionMap.has('groupId')) {
      videoOption.groupId = videoOptionMap.get('groupId')
    }
    if (videoOptionMap.has('deviceId')) {
      videoOption.deviceId = videoOptionMap.get('deviceId')
    }
    if (videoOptionMap.has('optional')) {
      let optionalList: DataMap[] = videoOptionMap.get('optional')
      for (let data of optionalList) {
        if (data.has('sourceId')) {
          videoOption.deviceId = data.get('sourceId')
        }
      }
    }
    return videoOption
  }

  /* 获取相机设备信息 */
  getSources(call: MethodCall, result: MethodResult): void {
    let resultMap: DataMap = new Map()
    let mediaDevices = new MediaDevices();
    mediaDevices.enumerateDevices().then((data) => {
      Log.i(TAG, 'getUserMediaImpl.getSources : ' + JSON.stringify(data))
      let list: DataArray = []
      for (let info of data) {
        let map: DataMap = new Map()
        map.set('deviceId', info.deviceId)
        map.set('groupId', info.deviceId)
        map.set('kind', info.kind)
        map.set('label', info.label)
        list.push(map)
      }
      resultMap.set('sources', list);
      result.success(resultMap);
    })
  }

  getCameraInfo(index: number, camera: camera.CameraDevice): ConstraintsMap {
    let params: ConstraintsMap = new ConstraintsMap();
    let facing: string = camera.cameraPosition == 2 ? 'front' : 'back';
    params.putString('label',
      'Camera ' + index + ', Facing ' + facing + ', Orientation ' + camera.cameraOrientation);
    params.putString('deviceId', '' + index);
    params.putString('facing', facing);
    params.putString('kind', 'videoinput');

    return params;
  }

  getAudioInputInfo(audioDeviceDescriptor: audio.AudioDeviceDescriptor): ConstraintsMap {
    let type = audioDeviceDescriptor.deviceType.valueOf()
    let label = audioDeviceDescriptor.name;
    let address = audioDeviceDescriptor.address;
    // ohos 麦克风 对应安卓 设备内置麦克风 AudioDeviceInfo.TYPE_BUILTIN_MIC
    if (audioDeviceDescriptor.deviceType == audio.DeviceType.MIC) {
      label = 'Built-in Microphone (' + address + ')';
    }

    // ohos 有线耳机，带麦克风。 对应安卓 有线耳机类型的音频设备 AudioDeviceInfo.TYPE_WIRED_HEADSET
    if (audioDeviceDescriptor.deviceType == audio.DeviceType.WIRED_HEADSET) {
      label = 'Wired Headset';
    }
    // ohos 蓝牙设备SCO连接 对应安卓 蓝牙SCO协议连接的音频设备 AudioDeviceInfo.TYPE_BLUETOOTH_SCO
    // 在ohos中还有A2DP协议连接，这里先放一起 TODO 后面看是否需要修改
    if (audioDeviceDescriptor.deviceType == audio.DeviceType.BLUETOOTH_SCO ||
      audioDeviceDescriptor.deviceType == audio.DeviceType.BLUETOOTH_A2DP) {
      label = 'Bluetooth SCO (' + audioDeviceDescriptor.name + ')';
    }

    let audios: ConstraintsMap = new ConstraintsMap();
    audios.putString('label', label);
    audios.putString('deviceId', '' + audioDeviceDescriptor.id);
    audios.putString('groupId', '' + type);
    audios.putString('facing', '');
    audios.putString('kind', 'audioinput');

    return audios;
  }

  getAudioOutputInfo(audioDeviceDescriptor: audio.AudioDeviceDescriptor): ConstraintsMap {

    let audioOutputMap: ConstraintsMap = new ConstraintsMap();

    audioOutputMap.putString('label', audioDeviceDescriptor.name);
    audioOutputMap.putString('deviceId', '' + audioDeviceDescriptor.id);
    audioOutputMap.putString('facing', '');
    audioOutputMap.putString('kind', 'audiooutput');

    return audioOutputMap;
  }

  setAbility(ability: UIAbility | null) {
    this.ability = ability
  }

  public getNextStreamUUID(): string {
    let uuid: string = '';
    do {
      uuid = util.generateRandomUUID();
    } while (this.getStreamForId(uuid, '') != null);

    return uuid;
  }

  /*  20240913 当前获取不到-MediaStream，依照安卓逻辑适配先*/
  getStreamForId(id: string, peerConnectionId: string): MediaStream {
    let stream: MediaStream | null = null;
    if (peerConnectionId.length > 0) {
      let pco: PeerConnectionObserver = this.mPCO.get(peerConnectionId);
      if (pco != null) {
        stream = pco.remoteStreams.get(id);
      }
    } else {
      for (let entriesElement of this.mPCO.entries()) {
        stream = entriesElement[1].remoteStreams.get(id);
        if (stream != null) {
          break;
        }
      }
    }
    if (stream == null) {
      stream = this.localStreams.get(id);
    }
    return stream;
  }

  /*  20240913 当前获取不到-MediaStreamTrack，依照安卓逻辑适配先*/
  getTrackForId(trackId: string, peerConnectionId?: string): MediaStreamTrack {
    let track: MediaStreamTrack = this.localTracks.get(trackId)
    if (track == null) {
      for (let key of this.mPCO.keys()) {
        if (peerConnectionId != null && key.localeCompare(peerConnectionId) != 0) {
          continue;
        }
        let pco: PeerConnectionObserver = this.mPCO.get(key);
        track = pco.remoteTracks.get(trackId);
        if (track == null) {
          track = pco.getTransceiversTrack(trackId)!; // 这里并不能强制确定 获取的track不为空。
        }
        if (track != null) {
          break;
        }
      }
    }
    return track
  }

  onNegotiationNeeded(event: Event) {
    Log.d(TAG, 'onNegotiationNeeded: this=' + JSON.stringify(this));
    Log.d(TAG, 'onNegotiationNeeded: event=' + JSON.stringify(event));
  }

  handleStreamDispose(streamId?: string, stream?: MediaStream) {
    let streamL: MediaStream;
    Log.d(TAG, 'function streamDispose streamId= ' + streamId);
    if (streamId) {
      streamL = this.localStreams.get(streamId);
      if (streamL) {
        Log.i(TAG, 'function streamDispose streamL= ' + stream);
        this.handleStreamDispose(undefined, streamL);
        this.localStreams.remove(streamId);
        this.removeStreamForRendererById(streamId);
        return;
      } else {
        Log.d(TAG, 'streamDispose() streamL is null');
      }
    } else {
      Log.d(TAG, 'function streamDispose() streamId is null');
    }

    if (stream) {
      Log.d(TAG, 'function streamDispose stream= ' + stream);
      let videoTracks: VideoTrack[] = stream.getVideoTracks();
      Log.d(TAG, 'function streamDispose videoTracks.length= ' + videoTracks.length);
      for (let track of videoTracks) {
        this.localTracks.remove(track.id);
        stream.removeTrack(track);
      }

      let audioTracks: AudioTrack[] = stream.getAudioTracks();
      Log.d(TAG, 'function streamDispose audioTracks.length= ' + audioTracks.length);
      for (let track of audioTracks) {
        this.localTracks.remove(track.id);
        stream.removeTrack(track);
      }
    } else {
      Log.d(TAG, 'function streamDispose() stream is null');
    }

  }

  removeStreamForRendererById(streamId: string): void {
    Log.d(TAG, 'streamDispose removeStreamForRendererById ');
    if (this.mTextureId) {
      Log.d(TAG, 'streamDispose removeStreamForRendererById textureId：' + this.mTextureId);
      Log.d(TAG, 'streamDispose removeStreamForRendererById this.renders.length：' + this.renders.length);
      let videoRender: FlutterRTCVideoRenderer = this.renders.get(this.mTextureId);
      if (videoRender == null) {
        Log.e(TAG, 'streamDispose removeStreamForRendererById videoRender [' + this.mTextureId + '] not found !');
        return;
      }
    }

    for (let i = 0; i < this.renders.length; i++) {
      let renderer: FlutterRTCVideoRenderer = this.renders.getValueAt(i);
      if (renderer.checkMediaStream(streamId, 'local')) {
        renderer.setStream(null, '');
      }
    }
  }

  removeTrackForRendererById(trackId: string) {
    for (let i = 0; i < this.renders.length; i++) {
      let renderer: FlutterRTCVideoRenderer = this.renders.getValueAt(i)
      if (renderer.checkVideoTrack(trackId, 'local')) {
        renderer.setStream(null, null)
      }
    }
  }

  handleRtpSenderSetTrack(call: MethodCall, result: MethodResult, replace: boolean) {
    const pco = this.getPCO(call, result);
    if (!pco) {
      return;
    }
    let track: MediaStreamTrack | null = null;
    if (getTrackId(call).length > 0) {
      track = this.getMediaStreamTrack(call, result);
      if (!track) {
        return;
      }
    }
    pco.rtpSenderSetTrack(getRtpSenderId(call), track, result, replace);
  }

  handleMediaStreamRemoveTrack(streamId: string, trackId: string, result: MethodResult) {
    let mediaStream = this.localStreams.get(streamId);
    if (!mediaStream) {
      this.resultError('mediaStreamRemoveTrack', 'mediaStreamRemoveTrack() stream [' + streamId + '] is null', result);
      return
    }
    let track = this.getTrackForId(trackId);
    if (!track) {
      this.resultError('mediaStreamRemoveTrack', 'mediaStreamRemoveTrack() track [' + trackId + '] is null', result);
      return
    }
    let kind = track.kind;
    //TODO kind 无 audio，需要替换情况
    if (kind === 'audio') {
      mediaStream.removeTrack(track);
      result.success(null);
    } else if (kind === 'video') {
      mediaStream.removeTrack(track);
      result.success(null);
    } else {
      this.resultError('mediaStreamRemoveTrack',
        'mediaStreamRemoveTrack() track [' + trackId + '] has unsupported type: ' + kind, result);
    }
  }

  mediaStreamTrackSetVolume(id: string, volume: number, peerConnectionId: string) {
    let track: MediaStreamTrack = this.getTrackForId(id, peerConnectionId);
    // TODO MediaStream getAudioTracks addTrack
    if (track.kind !== 'video') {
      Log.d(TAG, 'setVolume(): ' + id + ',' + volume);
    } else {
      Log.w(TAG, 'setVolume(): track not found: ' + id);
    }
  }
}
