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

import { MethodResult, EventChannel, Log, MethodCall } from '@ohos/flutter_ohos';
import { CryptorMethodHandlers } from './MethodHandlers';
import { ConstraintsMap } from './utils/ConstraintsMap';
import { DataMap } from './utils/ObjectType';
import { util } from '@kit.ArkTS';
import StateProvider from './StateProvider';

const TAG: string = 'FlutterWebRTCPlugin-FlutterRTCFrameCryptor'

export interface FrameCryptorKeyProvider {}

export default class FlutterRTCFrameCryptor {
  constructor(stateProvider: StateProvider) {}
  onMethodCall(call: MethodCall, result: MethodResult): void {
    result.error('unsupported_operation', 'The pinned OHOS WebRTC library does not implement media/data frame cryptors', null);
  }
}
