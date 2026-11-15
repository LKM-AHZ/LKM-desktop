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
  MethodCall,
  MethodCallHandler,
  MethodResult,
  PlatformView,
  MethodChannel,
  BinaryMessenger,
  StandardMethodCodec,
  Log,
} from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { VideoRender } from './VideoRender';
import { common } from '@kit.AbilityKit';

const TAG: string = 'FlutterWebRTCPlugin-[VideoRenderHandler]';
const CHANNEL_NAME = 'flutter.webrtc.ohos/RTCVideoRender'

export enum ScalingMode { Fill, AspectFill, AspectFit }

@Observed
export class VideoRenderHandler extends PlatformView implements MethodCallHandler {
  methodChannel: MethodChannel;

  constructor(context: common.Context, message: BinaryMessenger, viewId: number, args: ESObject) {
    super();
    this.methodChannel =
      new MethodChannel(message, `${CHANNEL_NAME}${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this)
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    let method: string = call.method;
    Log.d(TAG, 'VideoRenderController method  :' + method);
    switch (method) {
      case 'xxx':
        break;
      default:
        break
    }
  }

  public sendMessage = (surfaceId: string) => {
    Log.d(TAG, 'VideoRenderController sendMessage')
    this.methodChannel.invokeMethod('putSurfaceId', { surfaceId: surfaceId });
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(RenderBuilder)
  }

  dispose(): void {
    this.methodChannel?.setMethodCallHandler(null);
  }
}

@Builder
function RenderBuilder(params: Params) {
  VideoRender({ params: params })
}