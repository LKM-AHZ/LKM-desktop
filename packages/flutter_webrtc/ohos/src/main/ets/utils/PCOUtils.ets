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

import { ConstraintsMap } from './ConstraintsMap';
import { DataMap } from './ObjectType';
import {
  MediaStreamTrack,
  RTCDTMFSender,
  RTCIceCandidate,
  RTCRtpCapabilities,
  RTCRtpReceiver,
  RTCRtpSender,
  RTCRtpSendParameters,
  RTCRtpTransceiver
} from 'libohos_webrtc.so';
import { ConstraintsArray } from './ConstraintsArray';
import { dataMapToString, isNotEmpty } from './Utils';

export function capabilitiesToMap(capabilities: RTCRtpCapabilities): DataMap {
  let params: DataMap = new Map();
  let fecMechanismsArr: ConstraintsArray = new ConstraintsArray();
  params.set('codecs', capabilities.codecs);
  params.set('headerExtensions', capabilities.headerExtensions);
  params.set('fecMechanisms', fecMechanismsArr.toArrayList());
  return params;
}

export function candidateToMap(candidate?: RTCIceCandidate): DataMap {
  let params: DataMap = new Map();
  params.set('sdpMLineIndex', candidate?.sdpMLineIndex);
  params.set('sdpMid', candidate?.sdpMid);
  params.set('candidate', candidate?.candidate);
  return params;
}

export function transceiverToMap(transceiverId: string, transceiver: RTCRtpTransceiver): DataMap {
  let params: DataMap = new Map();
  params.set('transceiverId', transceiverId);
  params.set('mid', transceiver.mid ?? '');
  params.set('direction', transceiver.direction);
  params.set('sender', rtpSenderToMap(transceiver.sender));
  params.set('receiver', rtpReceiverToMap(transceiver.receiver));
  return params;
}

export function rtpParametersToMap(rtpParameters: RTCRtpSendParameters): DataMap {
  let info: ConstraintsMap = new ConstraintsMap();
  info.putString('transactionId', rtpParameters.transactionId);
  let rtcp: ConstraintsMap = new ConstraintsMap();
  // TODO 缺少 degradationPreference
  if (isNotEmpty(rtpParameters.rtcp.cname)) {
    rtcp.putString('cname', rtpParameters.rtcp.cname);
  }
  if (isNotEmpty(rtpParameters.rtcp.reducedSize)) {
    rtcp.putBoolean('reducedSize', rtpParameters.rtcp.reducedSize);
  }
  info.putMap('rtcp', rtcp.toMap());

  let headerExtensions: ConstraintsArray = new ConstraintsArray();
  for (let extension of rtpParameters.headerExtensions) {
    let map: DataMap = new Map();
    map.set('uri', extension.uri);
    map.set('id', extension.id);
    map.set('encrypted', extension.encrypted ?? false);
    headerExtensions.pushMap(map);
  }
  info.putArray('headerExtensions', headerExtensions.toArrayList());

  let encodings: ConstraintsArray = new ConstraintsArray();
  for (let encoding of rtpParameters.encodings) {
    let map: DataMap = new Map();
    // TODO 缺少 minBitrate、numTemporalLayers、ssrc
    if (isNotEmpty(encoding.active)) {
      map.set('active', encoding.active);
    }
    if (isNotEmpty(encoding.rid)) {
      map.set('rid', encoding.rid);
    }
    if (isNotEmpty(encoding.maxBitrate)) {
      map.set('maxBitrate', encoding.maxBitrate);
    }
    if (isNotEmpty(encoding.maxFramerate)) {
      map.set('maxFramerate', encoding.maxFramerate);
    }
    if (isNotEmpty(encoding.scaleResolutionDownBy)) {
      map.set('scaleResolutionDownBy', encoding.scaleResolutionDownBy);
    }
    encodings.pushMap(map);
  }
  info.putArray('encodings', encodings.toArrayList());

  let codecs: ConstraintsArray = new ConstraintsArray();
  rtpParameters.codecs.forEach(codec => {
    let map: DataMap = new Map();
    // TODO 缺少 name、numChannels、parameters、kind
    map.set('payloadType', codec.payloadType);
    map.set('clockRate', codec.clockRate);
    codecs.pushMap(map);
  })

  info.putArray('codecs', codecs.toArrayList());
  return info.toMap();
}

export function rtpSenderToMap(sender: RTCRtpSender): DataMap {
  let params: DataMap = new Map();
  params.set('senderId', sender.id ?? 'senderId');
  params.set('ownsTrack', true);
  params.set('dtmfSender', dtmfSenderToMap(sender.dtmf, sender.id));
  params.set('rtpParameters', rtpParametersToMap(sender.getParameters()));
  params.set('track', mediaTrackToMap(sender.track));
  return params;
}

export function rtpReceiverToMap(receiver: RTCRtpReceiver): DataMap {
  let params: DataMap = new Map();
  params.set('receiverId', receiver.id);
  params.set('track', mediaTrackToMap(receiver.track));
  params.set('rtpParameters', rtpParametersToMap(receiver.getParameters()));
  return params;
}

export function mediaTrackToMap(track: MediaStreamTrack | null): DataMap {
  let params: DataMap = new Map();
  if (!track) {
    return params;
  }
  params.set('id', track.id);
  params.set('label', track.kind === 'video' ? 'video' : 'audio');
  params.set('kind', track.kind);
  params.set('enabled', track.enabled);
  params.set('readyState', track.readyState);
  return params;
}

export function dtmfSenderToMap(dtmfSender: RTCDTMFSender | null, id: string | null): DataMap {
  let params: DataMap = new Map();
  params.set('dtmfSenderId', id ?? '');
  // TODO 与鸿蒙不对应,返回空map
  return params;
}
