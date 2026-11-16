// HarmonyOS backend for the shared notification API. See package LICENSE.
import { FlutterPlugin, FlutterPluginBinding, AbilityAware, AbilityPluginBinding,
  MethodCallHandler, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { NewWantListener } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { AbilityConstant } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import reminderAgentManager from '@ohos.reminderAgentManager';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import { image } from '@kit.ImageKit';
import i18n from '@ohos.i18n';
import { BusinessError } from '@kit.BasicServicesKit';

interface NotificationAction { id: string; title: string; }
interface NotificationDetails { imagePath?: string; actions?: NotificationAction[]; }

export default class FlutterLocalNotificationsPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler, NewWantListener {
  private channel: MethodChannel | null = null;
  private binding: AbilityPluginBinding | null = null;
  private context: common.UIAbilityContext | null = null;
  private initialized: boolean = false;
  private generation: number = 0;
  private launch: Map<string, Object> | null = null;
  private queuedClick: Map<string, Object> | null = null;
  private pending: Set<MethodResult> = new Set();
  // Serialize replacement/cancellation so a late publish cannot resurrect a cancelled reminder.
  private operation: Promise<void> = Promise.resolve();
  getUniqueClassName(): string { return 'FlutterLocalNotificationsPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dexterous.com/flutter/local_notifications');
    this.channel.setMethodCallHandler(this);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.binding = binding; this.context = binding.getAbility().context;
    this.launch = this.response(binding.getAbility().launchWant);
    binding.addOnNewWantListener(this);
  }
  onDetachedFromAbility(): void {
    this.generation++;
    this.binding?.removeOnNewWantListener(this); this.binding = null; this.context = null;
    for (const result of this.pending) result.error('notification_error', 'Notification ability detached', null);
    this.pending.clear();
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility(); this.initialized = false;
    this.channel?.setMethodCallHandler(null); this.channel = null;
  }
  private response(want: Want): Map<string, Object> | null {
    if (want?.parameters?.lkmNotification !== true) return null;
    const id = want.parameters.lkmNotificationId;
    const payload = want.parameters.lkmNotificationPayload;
    const action = want.parameters.lkmNotificationAction;
    if (typeof id !== 'number' || !Number.isInteger(id) || typeof payload !== 'string' ||
      (action !== undefined && typeof action !== 'string')) return null;
    const row = new Map<string, Object>([['id', id], ['payload', payload]]);
    if (typeof action === 'string') row.set('actionId', action);
    return row;
  }
  onNewWant(want: Want, params: AbilityConstant.LaunchParam): void {
    const response = this.response(want);
    if (response === null) return;
    if (this.initialized) this.channel?.invokeMethod('didReceiveNotificationResponse', response);
    else this.queuedClick = response;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (!['initialize','requestPermissions','show','cancel','cancelAll','getNotificationAppLaunchDetails',
      'zonedSchedule','periodicallyShow','pendingNotificationRequests','cancelAllPendingNotifications'].includes(call.method)) {
      result.notImplemented(); return;
    }
    this.pending.add(result);
    this.operation = this.operation.then(async (): Promise<void> => {
      if (!this.pending.has(result)) return;
      try {
        const value = await this.handle(call);
        if (this.pending.delete(result)) result.success(value);
      } catch (error) {
        const failure = error as BusinessError;
        if (this.pending.delete(result)) result.error('notification_error', failure.message, failure.code ?? null);
      }
    });
  }
  private parameters(call: MethodCall, action?: string): ESObject {
    const parameters: ESObject = {
      lkmNotification: true, lkmNotificationId: this.id(call),
      lkmNotificationPayload: (call.argument('payload') ?? '') as string,
    };
    if (action !== undefined) parameters.lkmNotificationAction = action;
    return parameters;
  }
  private async agent(call: MethodCall, context: common.UIAbilityContext, action?: string): Promise<WantAgent> {
    return await wantAgent.getWantAgent({
      wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
        action: action === undefined ? 'lkm.notification.tap' : `lkm.notification.action.${action}`, parameters: this.parameters(call, action) }],
      actionType: wantAgent.OperationType.START_ABILITY,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG], requestCode: this.id(call),
    });
  }
  private async cancelScheduled(id: number): Promise<void> {
    // Query the system, not an in-memory map, so cancellation works after process death.
    for (const info of await reminderAgentManager.getAllValidReminders()) {
      if (info.reminderReq.notificationId === id) await reminderAgentManager.cancelReminder(info.reminderId);
    }
  }
  private async handle(call: MethodCall): Promise<Object | null> {
    switch (call.method) {
      case 'initialize':
        this.initialized = true;
        if (this.queuedClick !== null) {
          this.channel?.invokeMethod('didReceiveNotificationResponse', this.queuedClick); this.queuedClick = null;
        }
        return true;
      case 'getNotificationAppLaunchDetails': return this.launch;
      case 'requestPermissions':
        if (await notificationManager.isNotificationEnabled()) return true;
        if (this.context === null) throw new Error('Notification ability missing');
        await notificationManager.requestEnableNotification(this.context);
        return await notificationManager.isNotificationEnabled();
      case 'pendingNotificationRequests':
        return (await reminderAgentManager.getAllValidReminders()).map(info => new Map<string, Object>([
          ['id', info.reminderReq.notificationId ?? 0], ['title', info.reminderReq.title ?? ''],
          ['body', info.reminderReq.content ?? ''],
          ['payload', info.reminderReq.wantAgent?.parameters?.lkmNotificationPayload ?? ''],
        ]));
      case 'cancelAllPendingNotifications': await reminderAgentManager.cancelAllReminders(); return null;
      case 'cancelAll':
        await reminderAgentManager.cancelAllReminders(); await notificationManager.cancelAll(); return null;
      case 'cancel':
        await this.cancelScheduled(this.id(call)); await notificationManager.cancel(this.id(call)); return null;
      case 'show': return await this.show(call);
      case 'zonedSchedule':
      case 'periodicallyShow': return await this.schedule(call);
    }
    return null;
  }
  private details(call: MethodCall): NotificationDetails {
    // StandardMessageCodec decodes nested Dart maps as Map, not ArkTS records.
    const row = call.argument('details') as Map<string, Object> | null;
    if (row === null || row === undefined) return {};
    const imagePath = row.get('imagePath');
    if (imagePath !== null && imagePath !== undefined && typeof imagePath !== 'string') throw new Error('Invalid image path');
    const rows = row.get('actions') as Map<string, Object>[] | undefined;
    if (rows !== undefined && !Array.isArray(rows)) throw new Error('Invalid notification actions');
    const actions: NotificationAction[] = (rows ?? []).map((action): NotificationAction => {
      const id = action.get('id'); const title = action.get('title');
      if (typeof id !== 'string' || typeof title !== 'string') throw new Error('Invalid notification action');
      const parsed: NotificationAction = { id, title };
      return parsed;
    });
    return { imagePath: typeof imagePath === 'string' ? imagePath : undefined, actions };
  }
  private async show(call: MethodCall): Promise<null> {
    if (!await notificationManager.isNotificationEnabled()) throw new Error('Notification permission denied');
    const context = this.context;
    const generation = this.generation;
    if (context === null) throw new Error('Notification ability missing');
    const id = this.id(call);
    const details = this.details(call);
    const actions = details?.actions ?? [];
    if (actions.length > 2 || actions.some(action => !action.id || !action.title) ||
      new Set(actions.map(action => action.id)).size !== actions.length) {
      throw new Error('Notification requires at most two uniquely identified nonempty foreground actions');
    }
    const request: notificationManager.NotificationRequest = {
      id, wantAgent: await this.agent(call, context),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: (call.argument('title') ?? '') as string, text: (call.argument('body') ?? '') as string } },
      actionButtons: [],
    };
    for (const action of actions) request.actionButtons!.push({ title: action.title, wantAgent: await this.agent(call, context, action.id) });
    let source: image.ImageSource | null = null;
    let picture: image.PixelMap | null = null;
    try {
      if (details?.imagePath !== undefined && details.imagePath !== null) {
        if (!details.imagePath.startsWith('/') && !details.imagePath.startsWith('file://')) throw new Error('Notification image must be a local path or file URI');
        source = image.createImageSource(details.imagePath);
        picture = await source.createPixelMap();
        if (picture.getPixelBytesNumber() > 2 * 1024 * 1024) throw new Error('Notification image exceeds the system 2 MiB pixel limit');
        const title = (call.argument('title') ?? '') as string;
        const body = (call.argument('body') ?? '') as string;
        if (!title || !body) throw new Error('Picture notifications require nonempty title and body');
        request.content = { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_PICTURE,
          picture: { title, text: body, briefText: body, expandedTitle: title, picture } };
      }
      if (this.context !== context || this.generation !== generation) throw new Error('Notification ability detached');
      await notificationManager.publish(request);
      if (this.context !== context || this.generation !== generation) {
        await notificationManager.cancel(id);
        throw new Error('Notification ability detached');
      }
    } finally {
      try { await picture?.release(); } finally { await source?.release(); }
    }
    return null;
  }
  private async schedule(call: MethodCall): Promise<null> {
    if (!await notificationManager.isNotificationEnabled()) throw new Error('Notification permission denied');
    const context = this.context;
    const generation = this.generation;
    if (context === null) throw new Error('Notification ability missing');
    const id = this.id(call);
    const details = this.details(call);
    if (details?.imagePath || (details?.actions?.length ?? 0) > 0) throw new Error('System reminders support text only; image and foreground actions are unsupported');
    const title = (call.argument('title') ?? '') as string;
    const content = (call.argument('body') ?? '') as string;
    const wantAgent: reminderAgentManager.WantAgent = {
      pkgName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
      parameters: this.parameters(call),
    };
    let request: reminderAgentManager.ReminderRequest;
    if (call.method === 'periodicallyShow') {
      const seconds = call.argument('repeatSeconds') as number;
      if (!Number.isSafeInteger(seconds) || seconds < 86400) throw new Error('System reminder repeat intervals require whole seconds and at least one day');
      const timer: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        notificationId: id, title, content, ringDuration: 0,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION, wantAgent,
        triggerTimeInSeconds: seconds, repeatInterval: seconds, repeatCount: 0,
      };
      request = timer;
    } else {
      const epoch = call.argument('epochMilliseconds') as number;
      if (!Number.isSafeInteger(epoch)) throw new Error('Invalid scheduled timestamp');
      const match = call.argument('match') as string | null;
      if (match === null) {
        const seconds = Math.ceil((epoch - Date.now()) / 1000);
        if (seconds < 1) throw new Error('Scheduled date must be in the future');
        const timer: reminderAgentManager.ReminderRequestTimer = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
          notificationId: id, title, content, ringDuration: 0,
          slotType: notificationManager.SlotType.SERVICE_INFORMATION, wantAgent,
          triggerTimeInSeconds: seconds,
        };
        request = timer;
      } else {
        // Calendar reminders follow the device's timezone; they cannot retain another IANA timezone's DST rules.
        if (call.argument('timeZoneName') !== i18n.getTimeZone().getID()) throw new Error('Repeating calendar reminders require the device timezone');
        const calendar: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          notificationId: id, title, content, ringDuration: 0,
          slotType: notificationManager.SlotType.SERVICE_INFORMATION, wantAgent,
          dateTime: { year: call.argument('year') as number, month: call.argument('month') as number,
            day: call.argument('day') as number, hour: call.argument('hour') as number,
            minute: call.argument('minute') as number, second: call.argument('second') as number },
        };
        if (match === 'time') calendar.daysOfWeek = [1,2,3,4,5,6,7];
        else if (match === 'dayOfWeekAndTime') calendar.daysOfWeek = [call.argument('weekday') as number];
        else if (match === 'dayOfMonthAndTime') { calendar.repeatMonths = [1,2,3,4,5,6,7,8,9,10,11,12]; calendar.repeatDays = [calendar.dateTime.day]; }
        else if (match === 'dateAndTime') { calendar.repeatMonths = [calendar.dateTime.month]; calendar.repeatDays = [calendar.dateTime.day]; }
        else throw new Error('Unsupported calendar match component');
        request = calendar;
      }
    }
    if (this.context !== context || this.generation !== generation) throw new Error('Notification ability detached');
    // Publish before removing previous schedules so SDK rejection preserves the existing reminder.
    const reminder = await reminderAgentManager.publishReminder(request);
    try {
      if (this.context !== context || this.generation !== generation) throw new Error('Notification ability detached');
      for (const info of await reminderAgentManager.getAllValidReminders()) {
        if (info.reminderId !== reminder && info.reminderReq.notificationId === id) await reminderAgentManager.cancelReminder(info.reminderId);
      }
      if (this.context !== context || this.generation !== generation) throw new Error('Notification ability detached');
    } catch (error) {
      await reminderAgentManager.cancelReminder(reminder);
      throw new Error(String(error));
    }
    return null;
  }
  private id(call: MethodCall): number {
    const id = call.argument('id') as number;
    if (!Number.isInteger(id) || id < 0 || id > 2147483647) throw new Error('Notification id must fit signed int32');
    return id;
  }
}
