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
  AbilityAware,
  AbilityPluginBinding,
  Any,
  BinaryMessenger,
  EventChannel,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodChannel,
  TextureRegistry
} from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import AudioSwitchManager from './audio/AudioSwitchManager';
import MethodCallHandlerImpl from './MethodCallHandlerImpl';
import { VideoRenderFactory } from './components/VideoRenderFactory';
import { common } from '@kit.AbilityKit';
import LifeCycleObserver from './LifeCycleObserver';
import { PermissionsManager } from './utils/PermissionUtils';
import { isNotEmpty } from './utils/Utils';

const TAG: string = 'FlutterWebRTCPlugin';
const CHANNEL_NAME: string = 'flutter.webrtc.ohos/RTCVideoRender';

export class FlutterWebRTCPlugin implements FlutterPlugin, AbilityAware, StreamHandler {
  private context: common.Context | null = null;
  private methodChannel: MethodChannel | null = null;
  private methodCallHandler: MethodCallHandlerImpl | null = null;
  private observer: LifeCycleObserver = new LifeCycleObserver();
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private callbackId?: number;

  constructor() {
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    binding.getPlatformViewRegistry()
      .registerViewFactory(CHANNEL_NAME, new VideoRenderFactory(binding.getBinaryMessenger()));
    this.startListening(this.context, binding.getBinaryMessenger(), binding.getTextureRegistry());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stopListening();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.methodCallHandler?.setAbility(binding.getAbility());
    this.callbackId = this.context?.getApplicationContext().on('abilityLifecycle', this.observer);
    PermissionsManager.getInstance().init(binding.getAbility().context as common.UIAbilityContext);
  }

  onDetachedFromAbilityForConfigChanges(): void {
    PermissionsManager.getInstance().init(null);
    this.methodCallHandler?.setAbility(null);
  }

  onDetachedFromAbility(): void {
    PermissionsManager.getInstance().init(null);
    this.methodCallHandler?.setAbility(null);
    if (isNotEmpty(this.callbackId)) {
      this.context?.getApplicationContext().off('abilityLifecycle', this.callbackId);
      this.callbackId = undefined;
    }
  }

  getUniqueClassName(): string {
    return TAG;
  }

  private startListening(context: Context, messenger: BinaryMessenger, textureRegistry: TextureRegistry): void {
    AudioSwitchManager.getInstance().setContext(context);
    this.methodCallHandler = new MethodCallHandlerImpl(context, messenger, textureRegistry);
    this.methodChannel = new MethodChannel(messenger, 'FlutterWebRTC.Method');
    this.methodChannel.setMethodCallHandler(this.methodCallHandler);
    this.eventChannel = new EventChannel(messenger, 'FlutterWebRTC.Event');
    this.eventChannel.setStreamHandler(this);
    this.observer.setMethodCallHandler(this.methodCallHandler);
  }

  private stopListening(): void {
    this.methodCallHandler?.dispose();
    this.methodCallHandler = null;
    this.methodChannel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);
    this.observer.setMethodCallHandler(null);
    AudioSwitchManager.instance?.stop();
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: Any): void {
    this.eventSink = null;
  }

  sendEvent(event: Any): void {
    this.eventSink?.success(event);
  }
}

