import { BinaryMessenger, MethodChannel, MethodCall, MethodResult, MethodCallHandler } from '@ohos/flutter_ohos';

// Uses the same consume/onDeepLink contract as the existing Apple app host.
export class DeepLinkBridge implements MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pending: string[] = [];
  private ready: boolean = false;
  attach(messenger: BinaryMessenger): void {
    this.channel = new MethodChannel(messenger, 'ltd.lkmahz.desktop/deeplink');
    this.channel.setMethodCallHandler(this);
  }
  receive(raw: string | undefined): void {
    if (raw == null || raw.length > 8192 || !/^(lkm|solian):\/\//i.test(raw)) return;
    // ponytail: retain at most 64 links before Flutter consumes them; discard oldest on external floods.
    if (this.pending.length === 64) this.pending.shift();
    this.pending.push(raw);
    if (this.ready) this.channel?.invokeMethod('onDeepLink', null);
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'consumePendingDeepLink') { result.notImplemented(); return; }
    this.ready = true;
    result.success(this.pending.shift() ?? null);
    if (this.pending.length > 0) this.channel?.invokeMethod('onDeepLink', null);
  }
  detach(): void {
    this.channel?.setMethodCallHandler(null); this.channel = null; this.ready = false; this.pending = [];
  }
}
