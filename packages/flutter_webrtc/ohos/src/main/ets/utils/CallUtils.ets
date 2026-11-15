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

import { MethodCall } from "@ohos/flutter_ohos";
import { RTCRtpTransceiverDirection } from "libohos_webrtc.so";
import { ConstraintsMap } from "./ConstraintsMap";
import { DataMap } from "./ObjectType";

export function getPeerConnectionId(call: MethodCall): string {
  return call.argument('peerConnectionId') ?? '';
}

export function getStreamId(call: MethodCall): string {
  return call.argument('streamId') ?? '';
}

export function getLabel(call: MethodCall): string {
  return call.argument('label') ?? '';
}

export function getTrackId(call: MethodCall): string {
  return call.argument('trackId') ?? '';
}

export function getDataChannelId(call: MethodCall): string {
  return call.argument('dataChannelId') ?? '';
}

export function getTransceiverId(call: MethodCall): string {
  return call.argument('transceiverId') ?? '';
}

export function getRtpSenderId(call: MethodCall): string {
  return call.argument('rtpSenderId') ?? '';
}

export function getSenderId(call: MethodCall): string {
  return call.argument('senderId') ?? '';
}

export function getType(call: MethodCall): string {
  return call.argument('type') ?? '';
}

export function getTone(call: MethodCall): string {
  return call.argument('tone') ?? '';
}

export function getDirection(call: MethodCall): RTCRtpTransceiverDirection {
  return call.argument('direction') ?? 'sendrecv';
}

export function getStreamIds(call: MethodCall): string[] {
  return call.argument('streamIds') ?? [];
}

export function getDuration(call: MethodCall): number | undefined {
  return call.argument('duration');
}

export function getGap(call: MethodCall): number | undefined {
  return call.argument('gap');
}

export function getConstraintsMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('constraints'));
}

export function getOptionsMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('options'));
}

export function getConfigurationMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('configuration'));
}

export function getDescriptionMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('description'));
}

export function getCandidateMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('candidate'));
}

export function getDataChannelDictMap(call: MethodCall): ConstraintsMap {
  return constructMap(call.argument('dataChannelDict'));
}

export function constructMap(map: DataMap): ConstraintsMap {
  return new ConstraintsMap(map);
}