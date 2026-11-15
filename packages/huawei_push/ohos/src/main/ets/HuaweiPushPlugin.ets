import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCallHandler,
  MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { UIAbility } from '@kit.AbilityKit';
import { pushService, pushCommon } from '@kit.PushKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Host calls initialize(this) in UIAbility.onCreate, before Flutter engine startup. */
export default class HuaweiPushPlugin implements FlutterPlugin, MethodCallHandler {
  private static channel: MethodChannel | null = null;
  private static initialized: boolean = false;
  private static ready: boolean = false;
  private static failure: string | null = null;

  static initialize(ability: UIAbility): void {
    if (HuaweiPushPlugin.initialized) return;
    try {
      // receiveMessage must be registered during onCreate, including push cold starts.
      pushService.receiveMessage('DEFAULT', ability, (payload: pushCommon.PushPayload): void => {
        if (HuaweiPushPlugin.ready) HuaweiPushPlugin.channel?.invokeMethod('message', payload.data);
      });
      // tokenUpdate was added in API 18; older devices refresh via getToken at startup/resume.
      if (deviceInfo.sdkApiVersion >= 18) {
        pushService.on('tokenUpdate', ability, (token: string): void => {
          if (HuaweiPushPlugin.ready) HuaweiPushPlugin.channel?.invokeMethod('tokenUpdate', token);
        });
      }
      HuaweiPushPlugin.initialized = true;
      HuaweiPushPlugin.failure = null;
    } catch (error) {
      const failure = error as BusinessError;
      HuaweiPushPlugin.failure = `${failure.code}: ${failure.message}`;
    }
  }

  static dispose(): void {
    if (deviceInfo.sdkApiVersion >= 18 && HuaweiPushPlugin.initialized) {
      pushService.off('tokenUpdate');
    }
    HuaweiPushPlugin.initialized = false;
    HuaweiPushPlugin.ready = false;
  }

  getUniqueClassName(): string { return 'HuaweiPushPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    HuaweiPushPlugin.channel = new MethodChannel(binding.getBinaryMessenger(), 'lkm.huawei_push');
    HuaweiPushPlugin.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    HuaweiPushPlugin.channel?.setMethodCallHandler(null);
    HuaweiPushPlugin.channel = null;
    HuaweiPushPlugin.ready = false;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (!['getToken', 'deleteToken'].includes(call.method)) { result.notImplemented(); return; }
    if (HuaweiPushPlugin.failure !== null || !HuaweiPushPlugin.initialized) {
      result.error('huawei_push_unavailable', HuaweiPushPlugin.failure ?? 'Push Kit host lifecycle is not initialized', null);
      return;
    }
    const operation = call.method === 'getToken' ? this.getToken() : this.deleteToken();
    operation.then((token: string | null): void => { result.success(token); })
      .catch((failure: BusinessError): void => {
        result.error('huawei_push_error', failure.message, failure.code ?? null);
      });
  }
  private async getToken(): Promise<string> {
    // getToken is the authority even if an update arrived before the engine attached.
    const token = await pushService.getToken();
    HuaweiPushPlugin.ready = true;
    return token;
  }
  private async deleteToken(): Promise<null> {
    await pushService.deleteToken();
    return null;
  }
}
