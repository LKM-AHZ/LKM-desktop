
import { Want, AbilityConstant } from '@kit.AbilityKit';
import HuaweiPushPlugin from 'huawei_push';
import QuickActionsPlugin from 'quick_actions_ohos';
import { DeepLinkBridge } from './DeepLinkBridge';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  private deepLinks: DeepLinkBridge = new DeepLinkBridge();
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    HuaweiPushPlugin.initialize(this);
    this.dispatchShortcut(want);
    this.deepLinks.receive(want.uri);
    super.onCreate(want, launchParam);
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    this.dispatchShortcut(want);
    this.deepLinks.receive(want.uri);
  }
  private dispatchShortcut(want: Want): void {
    const action = want.parameters?.['flutter_quick_action'];
    if (typeof action === 'string') QuickActionsPlugin.dispatchShortcutAction(action);
  }
  onDestroy(): void {
    try { HuaweiPushPlugin.dispose(); } catch (error) { console.error('Push Kit cleanup failed'); }
    this.deepLinks.detach();
    super.onDestroy();
  }
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.deepLinks.attach(flutterEngine.getDartExecutor().getBinaryMessenger())
  }
}
