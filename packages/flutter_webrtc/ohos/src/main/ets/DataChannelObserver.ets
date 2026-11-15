/* MIT License
*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* All rights reserved.
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the 'Software'), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import { Any, BinaryMessenger, Log } from '@ohos/flutter_ohos';
import EventChannel, { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { RTCDataChannel, Event, MessageEvent, DataChannelState } from 'libohos_webrtc.so';
import { ArrayList } from '@kit.ArkTS';
import { ConstraintsMap } from './utils/ConstraintsMap';
import { DataChannelStateCode } from './utils/ObjectType';
import { util } from '@kit.ArkTS';
import { isBinaryBuffer } from './utils/Utils';

const TAG = 'FlutterWebRTCPlugin-DataChannelObserver'
const CHANNEL_NAME = 'FlutterWebRTC/dataChannelEvent'

export class DataChannelObserver implements StreamHandler {
  private flutterId: string;
  private dataChannel: RTCDataChannel;
  private eventChannel: EventChannel;
  private eventSink: EventSink | null = null
  private eventQueue: ArrayList<Object> = new ArrayList();

  constructor(messenger: BinaryMessenger, peerConnectionId: string, flutterId: string, dataChannel: RTCDataChannel) {
    this.flutterId = flutterId;
    this.dataChannel = dataChannel;
    this.eventChannel = new EventChannel(messenger, `${CHANNEL_NAME}${peerConnectionId}${flutterId}`);
    this.eventChannel.setStreamHandler(this);
    this.dataChannel.onbufferedamountlow = (data) => this.onBufferedAmountChange(data);
    this.dataChannel.onmessage = (data: MessageEvent<Any>) => this.onMessage(data);
    this.dataChannel.onclosing = (data) => this.onClosing(data);
    this.dataChannel.onopen = (data) => this.onOpen(data);
    this.dataChannel.onclose = (data) => this.onClose(data);
    this.dataChannel.onerror = (data) => this.onError(data);
  }

  onClosing(ev: Event) {
    this.onStateChange(DataChannelStateCode.CLOSING)
  }

  onOpen(ev: Event) {
    this.onStateChange(DataChannelStateCode.OPEN)
  }

  onClose(ev: Event) {
    this.onStateChange(DataChannelStateCode.CLOSED)
  }

  onError(ev: Event) {
    Log.d(TAG, 'onError' + JSON.stringify(ev));
  }

  onStateChange(state: DataChannelState) {
    Log.d(TAG, 'onStateChange' + JSON.stringify(state));
    let params = new ConstraintsMap();
    params.putString('event', 'dataChannelStateChanged');
    params.putNumber('id', this.dataChannel?.id!);
    params.putString('state', state);
    this.sendEvent(params)
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
    for (const event of this.eventQueue) {
      this.eventSink.success(event);
    }
    this.eventQueue.clear();
  }

  onCancel(args: Any): void {
    this.eventSink = null;
  }

  onBufferedAmountChange(ev: Event): void {
    Log.d(TAG, 'onBufferedAmountChange' + JSON.stringify(ev.type));
    let params: ConstraintsMap = new ConstraintsMap();
    params.putString('event', 'dataChannelBufferedAmountChange');
    params.putNumber('id', this.dataChannel?.id);
    params.putNumber('bufferedAmount', this.dataChannel.bufferedAmount)
    params.putNumber('changedAmount', this.dataChannel.bufferedAmount)
    this.sendEvent(params);
  }

  onMessage(ev: MessageEvent<Any>): void {
    let params: ConstraintsMap = new ConstraintsMap();
    params.putString('event', 'dataChannelReceiveMessage');
    params.putNumber('id', this.dataChannel?.id);
    let bytes: Uint8Array;
    if (ev.data instanceof ArrayBuffer) {
      bytes = new Uint8Array(ev.data);
    } else if (ev.data instanceof Uint8Array) {
      bytes = ev.data;
    } else {
      bytes = new Uint8Array(ev.data.length);
      for (let i = 0; i < ev.data.length; i++) {
        bytes[i] = ev.data[i];
      }
    }

    if (isBinaryBuffer(bytes)) {
      params.putString('type', 'binary');
      params.putByte('data', bytes);
    } else {
      let decoder = new util.TextDecoder();
      let decodeToStringOptions: util.DecodeToStringOptions = {
        stream: false
      }
      let decodedString = decoder.decodeToString(bytes, decodeToStringOptions);
      params.putString('type', 'text');
      params.putString('data', decodedString);
    }

    this.sendEvent(params);
  }

  sendEvent(params: ConstraintsMap): void {
    if (this.eventSink) {
      this.eventSink.success(params.toMap());
    } else {
      this.eventQueue.add(params.toMap());
    }
  }
}