/* Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND. See the License for the specific language governing
 * permissions and limitations under the License.
 */
import { AbilityAware, AbilityPluginBinding, FlutterPlugin, FlutterPluginBinding,
  MethodCall, MethodResult, MethodCallHandler, MethodChannel, BinaryMessenger } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { RecorderSession } from './RecorderSession';

export default class RecordOhosPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private messenger: BinaryMessenger | null = null;
  private context: common.UIAbilityContext | null = null;
  private generation: number = 0;
  private recorders: Map<string, RecorderSession> = new Map();
  // ponytail: serialize microphone/resource operations; per-recorder queues only if parallel capture is needed.
  private queue: Promise<void> = Promise.resolve();
  getUniqueClassName(): string { return 'RecordOhosPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.messenger = binding.getBinaryMessenger();
    this.channel = new MethodChannel(this.messenger, 'com.llfbandit.record/messages');
    this.channel.setMethodCallHandler(this);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void { this.context = binding.getAbility().context; }
  onDetachedFromAbility(): void {
    this.context = null; this.generation++;
    this.queue = this.queue.then(async () => {
      const sessions: RecorderSession[] = Array.from(this.recorders.values());
      this.recorders.clear();
      for (const session of sessions) {
        try { await session.dispose(); } catch (error) { console.error('Recorder detach cleanup failed'); }
      }
    });
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();
    this.channel?.setMethodCallHandler(null); this.channel = null; this.messenger = null;
  }

  private async permission(request: boolean): Promise<boolean> {
    const context = this.context;
    if (context === null) return false;
    const manager = abilityAccessCtrl.createAtManager();
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    if (manager.checkAccessTokenSync(info.appInfo.accessTokenId, 'ohos.permission.MICROPHONE') ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) return true;
    if (!request) return false;
    const response = await manager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
    return response.authResults.length === 1 &&
      response.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const generation = this.generation;
    this.queue = this.queue.then(async () => {
      try {
        if (generation !== this.generation) throw new Error('Recording ability detached');
        result.success(await this.handle(call, generation));
      } catch (error) {
        const failure = error as BusinessError;
        result.error('record_error', failure.message, failure.code ?? null);
      }
    });
  }

  private async handle(call: MethodCall, generation: number): Promise<Object | null> {
    const id = call.argument('recorderId') as string;
    if (id == null || id.trim() === '') throw new Error('Missing recorderId');
    if (call.method === 'create') {
      if (this.messenger === null) throw new Error('Recording engine detached');
      if (!this.recorders.has(id)) this.recorders.set(id, new RecorderSession(id, this.messenger,
        (session: RecorderSession, message: string) => {
          this.queue = this.queue.then(async () => {
            // Finalize any useful prefix after an asynchronous device/write error; keep it until stop/cancel.
            try { await session.recover(); } catch (error) { console.error('Recorder error cleanup failed'); }
          });
        }));
      return null;
    }
    const recorder = this.recorders.get(id);
    if (recorder === undefined) throw new Error('Recorder is not created or has been disposed');
    switch (call.method) {
      case 'hasPermission': return await this.permission(call.argument('request') !== false);
      case 'isEncoderSupported': return RecorderSession.supported(call.argument('encoder') as string);
      case 'listInputDevices': return []; // Mobile API: use the system-selected microphone.
      case 'start':
      case 'startStream':
        if (!await this.permission(false)) throw new Error('Microphone permission denied; call hasPermission first');
        if (generation !== this.generation || this.context === null) throw new Error('Recording ability detached');
        await recorder.start(call, call.method === 'startStream');
        if (generation !== this.generation || this.context === null) {
          await recorder.finish(true); throw new Error('Recording ability detached');
        }
        return null;
      case 'pause': await recorder.pause(); return null;
      case 'resume': await recorder.resume(); return null;
      case 'stop': return await recorder.finish(false);
      case 'cancel': await recorder.finish(true); return null;
      case 'isRecording': return recorder.states.state !== 2;
      case 'isPaused': return recorder.states.state === 0;
      case 'getAmplitude': return await recorder.amplitude();
      case 'dispose':
        this.recorders.delete(id); await recorder.dispose(); return null;
      default: throw new Error('Unsupported recorder method: ' + call.method);
    }
  }
}
