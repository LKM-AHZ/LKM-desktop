/* Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
 * Distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.
 */
import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import shortcutManager from '@ohos.bundle.shortcutManager';
import { BusinessError } from '@kit.BasicServicesKit';

export default class QuickActionsPlugin implements FlutterPlugin, MethodCallHandler {
  private static instance: QuickActionsPlugin | null = null;
  private static pending: string | null = null;
  private channel: MethodChannel | null = null;
  private ready: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  getUniqueClassName(): string { return 'QuickActionsPlugin'; }
  static dispatchShortcutAction(action: string): void {
    const plugin = QuickActionsPlugin.instance;
    if (plugin !== null && plugin.ready && plugin.channel !== null) plugin.channel.invokeMethod('launch', action);
    else QuickActionsPlugin.pending = action;
  }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    QuickActionsPlugin.instance = this;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'plugins.flutter.io/quick_actions');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = null; this.ready = false;
    if (QuickActionsPlugin.instance === this) QuickActionsPlugin.instance = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getLaunchAction') {
      const action = QuickActionsPlugin.pending; QuickActionsPlugin.pending = null; this.ready = true;
      result.success(action); return;
    }
    if (!['setShortcutItems','clearShortcutItems'].includes(call.method)) { result.notImplemented(); return; }
    this.queue = this.queue.then(async () => {
      try {
        if (this.channel === null) throw new Error('Shortcut engine detached');
        const shortcuts = await shortcutManager.getAllShortcutInfoForSelf();
        const requested: string[] = [];
        if (call.method === 'setShortcutItems') {
          const items = call.args as Map<string, string>[];
          for (const item of items) {
            const type = item.get('type');
            if (type == null || !shortcuts.some(s => s.id === type)) throw new Error('Shortcut must be declared in the application profile: ' + type);
            requested.push(type);
          }
        }
        for (const item of shortcuts) await shortcutManager.setShortcutVisibleForSelf(item.id, requested.includes(item.id));
        result.success(null);
      } catch (error) {
        const failure = error as BusinessError;
        result.error('shortcut_error', failure.message, failure.code ?? null);
      }
    });
  }
}
