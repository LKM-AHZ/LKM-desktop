/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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

import { FlutterPlugin, FlutterPluginBinding, MethodCallHandler, MethodCall, MethodResult, MethodChannel, AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@kit.BasicServicesKit';

export default class MapLauncherOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  getUniqueClassName(): string { return 'MapLauncherOhosPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'map_launcher'); this.channel.setMethodCallHandler(this);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void { this.context = binding.getAbility().context; }
  onDetachedFromAbility(): void { this.context = null; }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = null; this.context = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getInstalledMaps') {
      const installed: string[] = []; const undeclared: string[] = [];
      const probes = call.args as Map<string, string>;
      try {
        probes.forEach((scheme: string, id: string) => {
          if (!scheme.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:/)) { undeclared.push(id); return; }
          try { if (bundleManager.canOpenLink(scheme)) installed.push(id); }
          catch (error) { undeclared.push(id); }
        });
        result.success(new Map<string, Object>([['installed', installed], ['undeclared', undeclared]]));
      } catch (error) { result.error('PROBE_FAILED', (error as Error).message, null); }
      return;
    }
    if (call.method !== 'launch') { result.notImplemented(); return; }
    const context = this.context;
    if (context === null) { result.error('NO_ABILITY', 'Map launcher ability detached', null); return; }
    const url = call.argument('url') as string;
    if (url == null || !url.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:/)) {
      result.error('ARGUMENT_ERROR', 'A valid map URL is required', null); return;
    }
    // Preserve the current Dart URL builders. Android package names do not target OHOS bundles.
    context.startAbility({ action: 'ohos.want.action.viewData', uri: url }).then(() => result.success(null))
      .catch((error: BusinessError) => {
        // Only confirmed resolver rejection permits Dart's alternate-map/browser fallback.
        const rejected = error.code === 16000001 || error.code === 16000002;
        result.error(rejected ? 'LAUNCH_REJECTED' : 'LAUNCH_FAILED', error.message, error.code);
      });
  }
}
