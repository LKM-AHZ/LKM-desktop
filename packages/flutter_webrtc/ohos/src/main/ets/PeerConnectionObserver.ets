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

import { BinaryMessenger, Log, MethodResult } from '@ohos/flutter_ohos';
import EventChannel, { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import webrtc, {
  MediaStreamTrack,
  RTCDataChannel,
  RTCRtpReceiver,
  RTCRtpSender,
  RTCRtpCapabilities,
  RTCRtpCodec,
  RTCRtpTransceiverDirection,
  RTCPeerConnection,
  MediaStream,
  RTCRtpTransceiver,
  RTCConfiguration,
  RTCPeerConnectionIceEvent,
  Event,
  RTCRtpEncodingParameters,
  RTCRtpSendParameters,
  RTCStatsReport,
  RTCStats,
  RTCRtpTransceiverInit,
  RTCDataChannelEvent,
  RTCTrackEvent,
  RTCIceCandidate,
} from 'libohos_webrtc.so'
import StateProvider from './StateProvider';
import { HashMap, util } from '@kit.ArkTS';
import { ConstraintsMap } from './utils/ConstraintsMap';
import { ConstraintsArray } from './utils/ConstraintsArray';
import AudioSwitchManager from './audio/AudioSwitchManager';
import { DataChannelObserver } from './DataChannelObserver';
import { DataArray, DataMap, ObjectType } from './utils/ObjectType';
import { DataChannelInit } from './DataChannelInit';
import { candidateToMap, mediaTrackToMap, rtpReceiverToMap, rtpSenderToMap, transceiverToMap } from './utils/PCOUtils';
import { dataMapToString } from './utils/Utils';
import { mediaStreamTrackToMap } from './utils/TrackUtils';

const TAG = 'FlutterWebRTCPlugin-PeerConnectionObserver';
const CHANNEL_NAME = 'FlutterWebRTC/peerConnectionEvent';

export default class PeerConnectionObserver implements StreamHandler {
  private peerConnection: RTCPeerConnection;
  private configuration: RTCConfiguration;
  private stateProvider: StateProvider;
  private messenger: BinaryMessenger;
  private id: string;
  private eventChannel: EventChannel;
  private eventSink: EventSink | null = null;
  private dataChannels: HashMap<String, RTCDataChannel> = new HashMap();
  remoteStreams: HashMap<String, MediaStream> = new HashMap();
  remoteTracks: HashMap<String, MediaStreamTrack> = new HashMap();
  transceivers: HashMap<String, RTCRtpTransceiver> = new HashMap();

  constructor(configuration: RTCConfiguration, stateProvider: StateProvider, messenger: BinaryMessenger,
    id: string, peerConnection: RTCPeerConnection) {
    this.configuration = configuration;
    this.stateProvider = stateProvider;
    this.messenger = messenger;
    this.id = id;
    this.peerConnection = peerConnection;
    this.setPeerConnectionCallback();
    this.eventChannel = new EventChannel(messenger, `${CHANNEL_NAME}${id}`);
    this.eventChannel.setStreamHandler(this);
  }

  registerDataChannelObserver(dcId: string, dataChannel: RTCDataChannel) {
    Log.d(TAG, 'registerDataChannelObserver dcId: ' + JSON.stringify(dcId));
    new DataChannelObserver(this.messenger, this.id, dcId, dataChannel);
  }

  resultError(method: string, error: string, result: MethodResult) {
    let errorMsg: string = `${method}(): ${error}`;
    Log.e(TAG, errorMsg);
    result.error(method, error, null);
  }

  onListen(args: Object, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: ESObject): void {
    this.eventSink = null;
  }

  sendEvent(event: DataMap) {
    this.eventSink?.success(event);
  }

  getPeerConnection(): RTCPeerConnection {
    return this.peerConnection;
  }

  setPeerConnection(peerConnection: RTCPeerConnection): void {
    this.peerConnection = peerConnection;
    this.setPeerConnectionCallback();
  }

  setPeerConnectionCallback(): void {
    this.peerConnection.onicecandidate = (data) => this.onIceCandidate(data);
    this.peerConnection.oniceconnectionstatechange = (data) => this.onIceconnectionstatechange(data);
    this.peerConnection.onicegatheringstatechange = (data) => this.onIcegatheringstatechange(data);
    this.peerConnection.ontrack = (data) => this.onTrack(data);
    this.peerConnection.onnegotiationneeded = (data) => this.onNegotiationneeded(data);
    this.peerConnection.onsignalingstatechange = (data) => this.onSignalingstatechange(data);
    this.peerConnection.onconnectionstatechange = (data) => this.onConnectionstatechange(data);
    this.peerConnection.ondatachannel = (data) => this.onDatachannel(data);
  }

  onIceCandidate(event: RTCPeerConnectionIceEvent) {
    Log.d(TAG, `onIceCandidate: ${event.candidate?.toJSON()}`);
    let params: DataMap = new Map();
    params.set('event', 'onCandidate');
    params.set('candidate', candidateToMap(event.candidate));
    this.sendEvent(params);
  }

  onIceconnectionstatechange(event: Event) {
    Log.d(TAG, `onIceconnectionstatechange: ${this.peerConnection.iceConnectionState}`);
    let params: DataMap = new Map();
    params.set('event', 'iceConnectionState');
    params.set('state', this.peerConnection.iceConnectionState);
    this.sendEvent(params);
  }

  onIcegatheringstatechange(event: Event) {
    Log.d(TAG, `onIcegatheringstatechange: ${this.peerConnection.iceGatheringState}`);
    let params: DataMap = new Map();
    params.set('event', 'iceGatheringState');
    params.set('state', this.peerConnection.iceGatheringState);
    this.sendEvent(params);
  }

  onTrack(event: RTCTrackEvent) {
    Log.d(TAG, 'onTrack : ' + JSON.stringify(event.track));
    for (let stream of event.streams) {
      let track = event.receiver.track;
      let params = new ConstraintsMap();
      params.putString('event', 'onAddTrack');
      params.putString('streamId', stream.id);
      params.putString('ownerTag', this.id);
      params.putString('trackId', track.id);
      params.putMap('track', mediaStreamTrackToMap(track, true));
      Log.d(TAG, `onTrack params: ${params.toString()}`);
      this.sendEvent(params.toMap());
      if ('audio' == track.kind) {
        AudioSwitchManager.instance.start();
      }
    }

    let params = new ConstraintsMap();
    let streams: DataMap[] = [];
    for (let stream of event.streams) {
      streams.push(this.mediaStreamToMap(stream));
      this.remoteStreams.set(stream.id, stream);
    }
    params.putString('event', 'onTrack');
    params.putArray('streams', streams);
    params.putMap('track', mediaTrackToMap(event.receiver.track));
    params.putMap('receiver', rtpReceiverToMap(event.receiver));
    // TODO 没有属性
    // if (this.configuration.sdpSemantics == PeerConnection.SdpSemantics.UNIFIED_PLAN) {
    //   List<RtpTransceiver> transceivers = peerConnection.getTransceivers();
    //   for (RtpTransceiver transceiver : transceivers) {
    //     if (transceiver.getReceiver() != null && receiver.id().equals(transceiver.getReceiver().id())) {
    //       String transceiverId = transceiver.getMid();
    //       if (null == transceiverId) {
    //         transceiverId = stateProvider.getNextStreamUUID();
    //       }
    //       params.putMap('transceiver', transceiverToMap(transceiverId, transceiver));
    //     }
    //   }
    // }
    Log.d(TAG, `onTrack params: ${params.toString()}`);
    this.sendEvent(params.toMap());
  }

  onNegotiationneeded(event: Event) {
    Log.d(TAG, 'onNegotiationneeded');
    let params: DataMap = new Map();
    params.set('event', 'onRenegotiationNeeded');
    this.sendEvent(params);
  }

  onSignalingstatechange(event: Event) {
    Log.d(TAG, `onSignalingstatechange: ${this.peerConnection.signalingState}`);
    let params: DataMap = new Map();
    params.set('event', 'signalingState');
    params.set('state', this.peerConnection.signalingState);
    this.sendEvent(params);
  }

  onConnectionstatechange(event: Event) {
    Log.d(TAG, `onConnectionstatechange: ${this.peerConnection.connectionState}`);
    let params: DataMap = new Map();
    params.set('event', 'peerConnectionState');
    params.set('state', this.peerConnection.connectionState);
    this.sendEvent(params);
  }

  onDatachannel(event: RTCDataChannelEvent) {
    let flutterId = this.stateProvider.getNextStreamUUID();
    let params: DataMap = new Map();
    params.set('event', 'didOpenDataChannel');
    params.set('id', event.channel.id!);
    params.set('label', event.channel.label);
    params.set('flutterId', flutterId);
    Log.d(TAG, `onDatachannel params: ${dataMapToString(params)}`);
    this.dataChannels.set(flutterId, event.channel);
    //订阅事件
    this.registerDataChannelObserver(flutterId, event.channel);
    this.sendEvent(params);
  }

  mediaStreamToMap(stream: MediaStream): DataMap {
    let params: DataMap = new Map()
    params.set('streamId', stream.id);
    params.set('ownerTag', this.id);
    let audioTracks: DataArray = [];
    let videoTracks: DataArray = []
    for (let track of stream.getAudioTracks()) {
      audioTracks.push(mediaTrackToMap(track))
    }
    for (let track of stream.getVideoTracks()) {
      videoTracks.push(mediaTrackToMap(track))
    }
    params.set('audioTracks', audioTracks);
    params.set('videoTracks', videoTracks);
    return params;
  }

  restartIce(): void {
    this.peerConnection.restartIce();
  }

  close(): void {
    this.peerConnection.close();
    this.remoteStreams.clear();
    this.remoteTracks.clear();
    this.dataChannels.clear();
  }

  dispose() {
    this.close();
    // this.peerConnection.dispose();
    this.eventChannel.setStreamHandler(null);
  }

  createDataChannel(label: string, config: ConstraintsMap, result: MethodResult) {
    let init: DataChannelInit = new DataChannelInit();
    if (config.getType('id') === ObjectType.Number) {
      init.id = config.getNumber('id');
    }
    if (config.getType('ordered') === ObjectType.Boolean) {
      init.ordered = config.getBoolean('ordered');
    }
    if (config.getType('maxRetransmits') === ObjectType.Number) {
      init.maxRetransmits = config.getNumber('maxRetransmits');
    }
    if (config.getType('protocol') === ObjectType.String) {
      init.protocol = config.getString('protocol');
    }
    if (config.getType('negotiated') === ObjectType.Boolean) {
      init.negotiated = config.getBoolean('negotiated');
    }
    Log.d(TAG, 'createDataChannel init = ' + JSON.stringify(init));
    let dataChannel: RTCDataChannel | undefined = this.peerConnection.createDataChannel(label, init);
    let flutterId: string = this.getNextDataChannelUUID();
    Log.d(TAG, 'createDataChannel flutterId = ' + flutterId);
    if (!dataChannel) {
      this.resultError('createDataChannel', 'Can\'t create data-channel for id: ' + init.id, result);
      return;
    }
    this.dataChannels.set(flutterId, dataChannel);
    this.registerDataChannelObserver(flutterId, dataChannel);
    let params: ConstraintsMap = new ConstraintsMap();
    params.putNumber('id', dataChannel.id);
    params.putString('label', dataChannel.label);
    params.putString('flutterId', flutterId);
    result.success(params.toMap());
    Log.d(TAG, 'createDataChannel params = ' + params.toString());
  }

  dataChannelClose(dataChannelId: string) {
    let dataChannel: RTCDataChannel = this.dataChannels.get(dataChannelId);
    if (dataChannel) {
      dataChannel.close();
      this.dataChannels.remove(dataChannelId);
    } else {
      Log.d(TAG, 'dataChannelClose() dataChannel is null');
    }
  }

  dataChannelSend(dataChannelId: string, byteBuffer: ArrayBuffer, isBinary: boolean) {
    let dataChannel: RTCDataChannel = this.dataChannels.get(dataChannelId);
    if (dataChannel) {
      // TODO isBinary 二进制判断暂未处理，看后续是否需要
      dataChannel.send(byteBuffer);
    } else {
      Log.d(TAG, 'dataChannelSend() dataChannel is null');
    }
  }

  getRtpSenderById(id: string): RTCRtpSender | null {
    let senders: Array<RTCRtpSender> = this.peerConnection.getSenders();
    Log.d(TAG, 'senders length : ' + senders.length);
    for (let sender of senders) {
      Log.d(TAG, 'sender id : ' + sender.id);
      Log.d(TAG, ' id : ' + id);
      if (id === sender.id) {
        return sender;
      }
    }
    return null;
  }

  getRtpReceiverById(id: string): RTCRtpReceiver | null {
    let receivers: Array<RTCRtpReceiver> = this.peerConnection.getReceivers();
    Log.d(TAG, 'receivers length : ' + receivers.length);
    for (let receiver of receivers) {
      Log.d(TAG, 'receiver id : ' + receiver.id);
      Log.d(TAG, ' id : ' + id);
      if (id === receiver.id) {
        return receiver;
      }
    }
    return null;
  }

  /* TODO 不能添加 protected 外部调用不了  20240914 依照安卓逻辑适配先 */
  getTransceiversTrack(trackId: string): MediaStreamTrack | null {
    // if (this.configuration.sdpSemantics != this.peerConnection!.SdpSemantics.UNIFIED_PLAN) {
    //   return null;
    // }
    let track: MediaStreamTrack | null = null;
    let transceivers: RTCRtpTransceiver[] = this.peerConnection.getTransceivers();
    for (let i = 0; i < transceivers.length; i++) {
      let receiver: RTCRtpReceiver = transceivers[i].receiver;
      if (receiver != null) {
        if (receiver.track != null && receiver.track.id === trackId) {
          track = receiver.track;
          break;
        }
      }
    }

    return track;
  }

  getTransceivers(result: MethodResult) {
    let transceivers = this.peerConnection.getTransceivers();
    let transceiversParams: ConstraintsArray = new ConstraintsArray();
    for (let transceiver of transceivers) {
      let transceiverId = transceiver.mid;
      if (!transceiverId) {
        transceiverId = this.stateProvider.getNextStreamUUID();
      }
      transceiversParams.pushMap(transceiverToMap(transceiverId, transceiver));
    }
    let params = new ConstraintsMap();
    params.putArray('transceivers', transceiversParams.toArrayList());
    result.success(params.toMap());
  }

  getSenders(result: MethodResult) {
    let senders = this.peerConnection.getSenders();
    let sendersParams = new ConstraintsArray();
    for (let sender of senders) {
      sendersParams.pushMap(rtpSenderToMap(sender));
    }
    let params = new ConstraintsMap();
    params.putArray('senders', sendersParams.toArrayList());
    result.success(params.toMap());
  }

  getReceivers(result: MethodResult) {
    let receivers = this.peerConnection.getReceivers();
    let receiversParams = new ConstraintsArray();
    for (let receiver of receivers) {
      receiversParams.pushMap(rtpReceiverToMap(receiver));
    }
    let params = new ConstraintsMap();
    params.putArray('receivers', receiversParams.toArrayList());
    result.success(params.toMap());
  }

  addTransceiver(trackOrKind: MediaStreamTrack | string, result: MethodResult, transceiverInit?: DataMap) {
    let transceiver: RTCRtpTransceiver | undefined = undefined
    transceiver = this.peerConnection.addTransceiver(trackOrKind, this.mapToRtpTransceiverInit(transceiverInit))
    let transceiverId = transceiver?.mid ?? this.stateProvider.getNextStreamUUID();
    this.transceivers.set(transceiverId, transceiver)
    result.success(transceiverToMap(transceiverId!, transceiver!))
  }

  mapToRtpTransceiverInit(parameters?: DataMap): RTCRtpTransceiverInit | undefined {
    if (!parameters) {
      return undefined;
    }
    let streams: MediaStream[] = parameters.get('streams') ?? [];
    let encodingsParams: DataMap[] = parameters.get('sendEncodings');
    let direction: RTCRtpTransceiverDirection = parameters.get('direction') ?? 'sendrecv';
    let sendEncodings: RTCRtpEncodingParameters[] = [];
    let init: RTCRtpTransceiverInit | undefined = undefined;
    if (encodingsParams != null) {
      for (let i = 0; i < encodingsParams.length; i++) {
        let params: DataMap = encodingsParams[i];
        sendEncodings.push(this.mapToEncoding(params));
      }
      //sendEncodings会造成音频流失效 先注释, sendEncodings: sendEncodings
      init = {
        direction: direction, streams: streams
      }
    } else {
      init = {
        direction: direction,
      }
    }
    return init;
  }

  addTrack(track: MediaStreamTrack, streams: MediaStream[], result: MethodResult) {
    let sender: RTCRtpSender = this.peerConnection.addTrack(track, ...streams);
    result.success(rtpSenderToMap(sender));
  }

  removeTrack(senderId: string, result: MethodResult) {
    let sender: RTCRtpSender | null = this.getRtpSenderById(senderId);
    if (!sender) {
      this.resultError('removeTrack', 'sender is null', result);
      return;
    }
    let res: boolean = false;
    if (this.peerConnection) {
      this.peerConnection.removeTrack(sender)
      res = true
    }
    let params: DataMap = new Map<string, Object>();
    params.set('result', res);
    result.success(params);
  }

  async rtpSenderSetParameters(rtpSenderId: string, parameters: DataMap, result: MethodResult) {
    Log.d(TAG, 'rtpSenderSetParameters 1111 ');
    let sender: RTCRtpSender | null = this.getRtpSenderById(rtpSenderId);
    if (!sender) {
      this.resultError('rtpSenderSetParameters', 'sender is null', result);
      return;
    }
    Log.d(TAG, 'rtpSenderSetParameters 2222 ');
    let updatedParameters: RTCRtpSendParameters = this.updateRtpParameters(sender.getParameters(), parameters)
    let params: DataMap = new Map()
    Log.d(TAG, 'rtpSenderSetParameters 3333 ');
    try {
      await sender.setParameters(updatedParameters)
      params.set('result', true)
    } catch (e) {
      params.set('result', false)
    }
    Log.d(TAG, 'rtpSenderSetParameters 4444 ');
    result.success(params)
  }

  async rtpSenderSetTrack(rtpSenderId: string, track: MediaStreamTrack | null, result: MethodResult, replace: boolean) {
    let sender: RTCRtpSender | null = this.getRtpSenderById(rtpSenderId);
    if (!sender) {
      this.resultError('rtpSenderSetTrack', 'sender is null', result);
      return;
    }
    try {
      await sender.replaceTrack(track)
      result.success(null)
    } catch (e) {
      this.resultError('rtpSenderSetTrack', JSON.stringify(e), result);
    }
  }

  mapToEncoding(parameters: DataMap): RTCRtpEncodingParameters {
    let encoding: RTCRtpEncodingParameters = {}
    if (parameters.get('active')) {
      encoding.active = parameters.get('active');
    }
    if (parameters.get('maxBitrate')) {
      encoding.maxBitrate = parameters.get('maxBitrate');
    }
    if (parameters.get('maxFramerate')) {
      encoding.maxBitrate = parameters.get('maxFramerate');
    }
    if (parameters.get('scaleResolutionDownBy')) {
      encoding.maxBitrate = parameters.get('scaleResolutionDownBy');
    }
    return encoding
  }

  getStats(result: MethodResult, selector?: MediaStreamTrack) {
    if (selector) {
      this.peerConnection.getStats(selector).then((rtcStatsReport) => {
        this.handleStatsReport(rtcStatsReport, result);
      })
    } else {
      this.peerConnection.getStats().then((rtcStatsReport) => {
        this.handleStatsReport(rtcStatsReport, result);
      })
    }
  }

  private handleStatsReport(rtcStatsReport: RTCStatsReport, result: MethodResult): void {
    let reports: Map<string, ESObject> = rtcStatsReport.stats;
    let params: ConstraintsMap = new ConstraintsMap();
    let stats: ConstraintsArray = new ConstraintsArray();
    reports.forEach((v: ESObject, k: string) => {
      let report_map: DataMap = new Map();
      report_map.set('id', v.id)
      report_map.set('type', v.type)
      report_map.set('timestamp', v.timestamp)
      let v_map: DataMap = new Map();
      Object.keys(v).forEach((value, key) => {
        Log.i(TAG, 'reports.forEach :  ' + JSON.stringify(value))
        v_map.set(value, v[value]);
      })
      report_map.set('values', v_map);
    })
    params.putArray('stats', stats.toArrayList());
    Log.i(TAG, 'handleStatsReport stats = ' + Array.from(params.toMap().entries()))
    result.success(params.toMap());
  }

  getStatsForTrack(trackId: string, result: MethodResult): void {
    if (trackId == null || trackId === '') {
      this.resultError('peerConnectionGetStats', 'MediaStreamTrack not found for id: ' + trackId, result);
      return;
    }
    if (this.peerConnection == null) {
      this.resultError('peerConnectionGetStats', 'peerConnection is null!', result);
      return;
    }

    let sender: RTCRtpSender | undefined = undefined
    let receiver: RTCRtpReceiver | undefined = undefined
    this.peerConnection.getSenders().forEach((s) => {
      if (s.track !== null && trackId === s.track.id) {
        sender = s;
        return; // 退出循环
      }
    });
    this.peerConnection.getReceivers().forEach((r) => {
      if (r.track !== null && trackId === r.track.id) {
        receiver = r;
        return; // 退出循环
      }
    });
    if (sender !== undefined) {
      (sender as RTCRtpSender).getStats().then((rtcStatsReport) => {
        this.handleStatsReport(rtcStatsReport, result);
      })
    } else if (receiver != undefined) {
      (receiver as RTCRtpReceiver).getStats().then((rtcStatsReport) => {
        this.handleStatsReport(rtcStatsReport, result);
      })
    } else {
      this.resultError('peerConnectionGetStats', 'MediaStreamTrack not found for id: ' + trackId, result);
    }
  }

  getNextDataChannelUUID() {
    let uuid: string;
    do {
      uuid = util.generateRandomUUID(false);
    } while (this.dataChannels.get(uuid) != null);

    return uuid;
  }

  updateRtpParameters(parameters: RTCRtpSendParameters, newParameters: DataMap): RTCRtpSendParameters {
    let encodings: DataMap[] = newParameters.get('encodings')
    let nativeEncodings: RTCRtpEncodingParameters[] = parameters.encodings
    let degradationPreference: string = newParameters.get('degradationPreference')
    if (degradationPreference != null) {
      //此属性被注掉掉了
      // parameters.degradationPreference = RtpParameters.DegradationPreference.valueOf(degradationPreference.toUpperCase().replace('-', '_'));
    }

    for (let encoding of encodings) {
      let currentParams: RTCRtpEncodingParameters | null = null
      let rid: string = encoding.get('rid')
      if (rid != null) {
        for (let x of nativeEncodings) {
          if (x.rid == rid) {
            currentParams = x
            break
          }
        }
      }

      if (currentParams == null) {
        let idx: number = encodings.indexOf(encoding)
        if (idx < nativeEncodings.length) {
          currentParams = nativeEncodings[idx]
        }
      } else {
        if (encoding.has('active')) {
          currentParams.active = encoding.get('active')
        }
        if (encoding.has('maxBitrate')) {
          currentParams.maxBitrate = encoding.get('maxBitrate')
        }
        // if (encoding.has('minBitrate')) {
        //   currentParams.minBitrate = encoding.get('minBitrate')
        // }
        if (encoding.has('maxFramerate')) {
          currentParams.maxFramerate = encoding.get('maxFramerate')
        }
        // if (encoding.has('numTemporalLayers')) {
        //   currentParams.numTemporalLayers = encoding.get('numTemporalLayers')
        // }
        if (encoding.has('scaleResolutionDownBy')) {
          currentParams.scaleResolutionDownBy = encoding.get('scaleResolutionDownBy')
        }
      }
    }
    return parameters
  }

  rtpSenderSetStreams(rtpSenderId: string, streams: MediaStream[], result: MethodResult) {
    let sender = this.getRtpSenderById(rtpSenderId)
    if (sender == null) {
      this.resultError('rtpSenderSetStream', 'sender is null', result)
      return
    }
    sender.setStreams(...streams)
    result.success(null)
  }

  rtpTransceiverGetCurrentDirection(transceiverId: string, result: MethodResult): void {
    const transceiver = this.getRtpTransceiverById(transceiverId);
    if (!transceiver) {
      this.resultError('rtpTransceiverGetCurrentDirection', 'transceiver is null', result);
      return;
    }
    const direction = transceiver.direction;
    if (!direction) {
      result.success(null);
    } else {
      const params = new ConstraintsMap();
      params.putString('result', direction);
      result.success(params.toMap());
    }
  }

  rtpTransceiverStop(transceiverId: string, result: MethodResult): void {
    const transceiver = this.getRtpTransceiverById(transceiverId);
    if (!transceiver) {
      this.resultError('rtpTransceiverStop', 'transceiver is null', result);
      return;
    }
    transceiver.stop();
    result.success(null);
  }

  private getRtpTransceiverById(id: string): RTCRtpTransceiver | undefined {
    let transceiver: RTCRtpTransceiver | undefined = this.transceivers.get(id);
    if (!transceiver) {
      transceiver =
        this.peerConnection.getTransceivers().filter((transceiver: RTCRtpTransceiver) => {
          return transceiver.mid === id
        })[0]
    }
    return transceiver;
  }

  rtpTransceiverSetDirection(direction: RTCRtpTransceiverDirection, transceiverId: string, result: MethodResult) {
    let transceiver = this.getRtpTransceiverById(transceiverId);
    if (!transceiver) {
      this.resultError('rtpTransceiverSetDirection', 'transceiver is null', result);
      return;
    }
    transceiver.direction = direction
    result.success(null);
  }

  rtpTransceiverGetDirection(transceiverId: string, result: MethodResult) {
    let transceiver = this.getRtpTransceiverById(transceiverId);
    if (!transceiver) {
      this.resultError('rtpTransceiverGetDirection', 'transceiver is null', result);
      return;
    }
    let params: ConstraintsMap = new ConstraintsMap();
    params.putString('result', transceiver.direction);
    result.success(params.toMap());
  }

  /*
   * Sets the priority of the encoder (codec) used in this transmitter for the sender and receiver.
   * */
  rtpTransceiverSetCodecPreferences(transceiverId: string, codecs: DataArray, result: MethodResult): void {
    const transceiver = this.getRtpTransceiverById(transceiverId);
    if (!transceiver) {
      this.resultError('rtpTransceiverSetCodecPreferences', 'transceiver is null', result);
      return;
    }
    let preferedCodecs: RTCRtpCodec[] = [];

    codecs.forEach((element: DataMap) => {
      let codecMap = new ConstraintsMap(element);
      let codec: RTCRtpCodec = {
        mimeType: '', clockRate: 0
      };
      // TODO 缺少 name、kind
      codec.mimeType = codecMap.getString('mimeType');
      codec.clockRate = codecMap.getNumber('clockRate');
      if (codecMap.getType('payloadType') === ObjectType.Number) {
        codec.payloadType = codecMap.getNumber('payloadType');
      }
      if (codecMap.getType('numChannels') === ObjectType.Number) {
        codec.channels = codecMap.getNumber('numChannels');
      }
      if (codecMap.getType('sdpFmtpLine') === ObjectType.String) {
        codec.sdpFmtpLine = codecMap.getString('sdpFmtpLine');
      } else {
        codec.sdpFmtpLine = '';
      }
      preferedCodecs.push(codec);
    });

    transceiver.setCodecPreferences(preferedCodecs);
    result.success(null);
    Log.d(TAG, 'rtpTransceiverSetCodecPreferences success! ');
  }
}