/*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos'
import deviceInfo from '@ohos.deviceInfo';

const TAG: string = "LiveKitPlugin";
const METHOD_CHANEL: string = "livekit_client";

export default class LiveKitPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'osVersionString':
        result.success(deviceInfo.displayVersion);
        break;
      case 'setAudioProcessingOptions':
        // Full live reconfiguration needs an AudioTrack processing API; the
        // old ADM's single noise-suppressor setter cannot honor this request.
        result.success(new Map<string, Object>([
          ['result', false], ['code', 'rejectedPlatformUnavailable'],
          ['message', 'The OHOS WebRTC runtime cannot reconfigure per-track audio processing.']
        ]));
        break;
      case 'startLocalRecording':
        result.error('rejectedPlatformUnavailable', 'The OHOS WebRTC runtime has no production audio recording control.', null);
        break;
      default:
        result.notImplemented();
    }
  }
}
