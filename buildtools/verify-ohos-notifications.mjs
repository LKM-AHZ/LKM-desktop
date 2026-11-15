import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadArkTs } from './ohos-test-loader.mjs';
let handler;
const callbacks=[];
class MethodChannel {
  setMethodCallHandler(value) { handler=value; }
  invokeMethod(name,args) { callbacks.push([name,args]); }
}
const shown=[]; const cancelled=[]; const reminders=new Map(); let reminderId=0;
let reminderGate; let reminderFailure=false; let pixelFailure=false; let pixelBytes=16; let sourceReleases=0; let pixelReleases=0;
const reminderAgentManager={
 ReminderType:{REMINDER_TYPE_TIMER:0,REMINDER_TYPE_CALENDAR:1},
 publishReminder:async request=>{if(reminderGate)await reminderGate;if(reminderFailure)throw Error('reminder limit exceeded');
   for(const [key,value] of reminders)if(value.notificationId===request.notificationId)reminders.delete(key);
   const id=++reminderId;reminders.set(id,request);return id;},
 getAllValidReminders:async()=>Array.from(reminders,([reminderId,reminderReq])=>({reminderId,reminderReq})),
 cancelReminder:async id=>reminders.delete(id),cancelAllReminders:async()=>reminders.clear(),
};
const image={createImageSource:()=>({
 createPixelMap:async()=>{if(pixelFailure)throw Error('invalid image');return {getPixelBytesNumber:()=>pixelBytes,release:async()=>pixelReleases++};},
 release:async()=>sourceReleases++,
})};
let enabled=false;let publishFailure=false;let gate;
const notificationManager={
  SlotType:{SERVICE_INFORMATION:1},ContentType:{NOTIFICATION_CONTENT_BASIC_TEXT:0,NOTIFICATION_CONTENT_PICTURE:3},
  isNotificationEnabled:async()=>enabled,
  requestEnableNotification:async()=>{enabled=true;},
  publish:async request=>{if(gate)await gate;if(publishFailure)throw Error('publish failed');shown.push(request);},
  cancel:async id=>cancelled.push(id),cancelAll:async()=>cancelled.push('all'),
};
const Plugin=loadArkTs(new URL('../packages/flutter_local_notifications/ohos/src/main/ets/components/plugin/FlutterLocalNotificationsPlugin.ets',import.meta.url),new Map([
 ['@ohos/flutter_ohos',{MethodChannel}],['@ohos.reminderAgentManager',reminderAgentManager],
 ['@kit.ImageKit',{image}],['@ohos.i18n',{getTimeZone:()=>({getID:()=> 'Asia/Shanghai'})}],['@kit.NotificationKit',{notificationManager}],
 ['@ohos.app.ability.wantAgent',{getWantAgent:async info=>info,OperationType:{START_ABILITY:0},WantAgentFlags:{UPDATE_PRESENT_FLAG:1}}],
])).default;
const plugin=new Plugin();const context={abilityInfo:{bundleName:'ltd.lkmahz.desktop',name:'EntryAbility'}};
let listener;
const binding={getAbility:()=>({context,launchWant:{parameters:{lkmNotification:true,lkmNotificationId:4,lkmNotificationPayload:'lkm://cold'}}}),addOnNewWantListener:value=>listener=value,removeOnNewWantListener:value=>{assert.equal(value,listener);listener=null;}};
plugin.onAttachedToEngine({getBinaryMessenger:()=>({})});plugin.onAttachedToAbility(binding);
const call=(method,args={})=>new Promise(resolve=>plugin.onMethodCall({method,argument:key=>key==='details'&&args.details ? new Map([['imagePath',args.details.imagePath],['actions',(args.details.actions??[]).map(action=>new Map(Object.entries(action)))]]) : args[key]??null},{success:value=>resolve({value}),error:(code,message)=>resolve({code,message}),notImplemented:()=>resolve({notImplemented:true})}));
const cold=(await call('getNotificationAppLaunchDetails')).value;
assert.equal(cold.get('payload'),'lkm://cold');
listener.onNewWant({parameters:{lkmNotification:true,lkmNotificationId:5,lkmNotificationPayload:'lkm://queued'}},{});
assert.equal(callbacks.length,0);
assert.equal((await call('initialize')).value,true);assert.equal(callbacks[0][1].get('payload'),'lkm://queued');
assert.match((await call('show',{id:1})).message,/permission denied/);
assert.equal((await call('requestPermissions')).value,true);
assert.equal((await call('show',{id:1,title:'Title',body:'Body',payload:'lkm://warm'})).value,null);
assert.equal(shown[0].content.normal.title,'Title');
assert.equal(shown[0].wantAgent.wants[0].bundleName,'ltd.lkmahz.desktop');
assert.equal(shown[0].wantAgent.wants[0].parameters.lkmNotificationPayload,'lkm://warm');
listener.onNewWant(shown[0].wantAgent.wants[0],{});assert.equal(callbacks.at(-1)[1].get('payload'),'lkm://warm');
const count=callbacks.length;listener.onNewWant({parameters:{lkmNotification:true,lkmNotificationId:'bad',lkmNotificationPayload:'bad'}},{});assert.equal(callbacks.length,count);
assert.match((await call('show',{id:Date.now()})).message,/int32/);
publishFailure=true;assert.match((await call('show',{id:7})).message,/publish failed/);publishFailure=false;
await call('cancel',{id:1});await call('cancelAll');assert.deepEqual(cancelled,[1,'all']);
assert.match((await call('zonedSchedule',{id:10,epochMilliseconds:1})).message,/future/);
const tomorrow=Date.now()+86400000;
assert.equal((await call('zonedSchedule',{id:10,epochMilliseconds:tomorrow,payload:'scheduled'})).value,null);
assert.equal(reminders.get(1).triggerTimeInSeconds,86400);
assert.equal(reminders.get(1).wantAgent.parameters.lkmNotificationPayload,'scheduled');
assert.equal((await call('periodicallyShow',{id:11,repeatSeconds:172800})).value,null);
assert.equal(reminders.get(2).repeatInterval,172800);assert.equal(reminders.get(2).repeatCount,0);
assert.match((await call('periodicallyShow',{id:11,repeatSeconds:3600})).message,/at least one day/);
reminderFailure=true;assert.match((await call('periodicallyShow',{id:11,repeatSeconds:86400})).message,/limit/);
assert.equal(reminders.get(2).repeatInterval,172800,'failed replacement keeps existing system reminder');reminderFailure=false;
assert.equal((await call('pendingNotificationRequests')).value.length,2);
await call('cancel',{id:10});assert.equal(reminders.size,1);
const calendar={id:12,epochMilliseconds:tomorrow,timeZoneName:'Asia/Shanghai',match:'dayOfWeekAndTime',year:2026,month:11,day:16,hour:10,minute:30,second:5,weekday:1};
await call('zonedSchedule',calendar);assert.equal(reminders.get(3).daysOfWeek[0],1);
assert.match((await call('zonedSchedule',{...calendar,timeZoneName:'America/New_York'})).message,/device timezone/);
assert.match((await call('zonedSchedule',{...calendar,details:{actions:[{id:'x',title:'X'}]}})).message,/text only/);
await call('cancelAllPendingNotifications');assert.equal(reminders.size,0);
await call('show',{id:13,title:'Image',body:'Body',details:{imagePath:'/cache/image.png',actions:[{id:'reply',title:'Reply'},{id:'tap',title:'Tap'}]}});
const imageRequest=shown.at(-1);assert.equal(imageRequest.content.notificationContentType,3);
assert.equal(sourceReleases,1);assert.equal(pixelReleases,1);
assert.notEqual(imageRequest.actionButtons[0].wantAgent.wants[0].action,imageRequest.actionButtons[1].wantAgent.wants[0].action);
assert.notEqual(imageRequest.wantAgent.wants[0].action,imageRequest.actionButtons[1].wantAgent.wants[0].action,'action named tap must not overwrite the body WantAgent');
listener.onNewWant(imageRequest.actionButtons[0].wantAgent.wants[0],{});assert.equal(callbacks.at(-1)[1].get('actionId'),'reply');
pixelBytes=3*1024*1024;assert.match((await call('show',{id:13,title:'T',body:'B',details:{imagePath:'/cache/huge.png'}})).message,/2 MiB/);
assert.equal(sourceReleases,2);assert.equal(pixelReleases,2);
pixelFailure=true;assert.match((await call('show',{id:13,details:{imagePath:'/cache/invalid.png'}})).message,/invalid image/);
assert.equal(sourceReleases,3);pixelFailure=false;
assert.match((await call('show',{id:13,details:{actions:[{id:'x',title:'X'},{id:'x',title:'Y'}]}})).message,/uniquely/);

let reminderRelease;reminderGate=new Promise(resolve=>reminderRelease=resolve);
const scheduling=call('periodicallyShow',{id:14,repeatSeconds:86400});await new Promise(resolve=>setImmediate(resolve));
plugin.onDetachedFromAbility();assert.match((await scheduling).message,/detached/);
reminderRelease();await new Promise(resolve=>setImmediate(resolve));assert.equal(reminders.size,0,'detach rolls back a system reminder even after publish resolves');
reminderGate=null;plugin.onAttachedToAbility(binding);
let release;gate=new Promise(resolve=>release=resolve);
const pending=call('show',{id:8});await new Promise(resolve=>setImmediate(resolve));
plugin.onDetachedFromAbility();assert.match((await pending).message,/detached/);release();await new Promise(resolve=>setImmediate(resolve));
plugin.onDetachedFromEngine({});assert.equal(handler,null);
console.log('OHOS notifications: persistent system reminders, calendar/timezone limits, foreground actions, image release/error handling, permissions, show/cancel, WantAgent/cold and warm payloads, error and detach replies passed.');

const notificationSdk = process.env.DEVECO_SDK_HOME ?? join(homedir(), 'harmonyos/command-line-tools/sdk');
const reminderApi = join(notificationSdk, 'default/openharmony/ets/api/@ohos.reminderAgentManager.d.ts');
if (existsSync(reminderApi)) {
  const api = readFileSync(reminderApi, 'utf8');
  assert.match(api, /getAllValidReminders\(\): Promise<Array<ReminderInfo>>/);
  assert.match(api, /parameters\?: Record<string, Object>/);
  assert.match(api, /value range is \[86400, \+∞\)/);
  const request = readFileSync(join(notificationSdk, 'default/openharmony/ets/api/notification/notificationRequest.d.ts'), 'utf8');
  assert.match(request, /maximum of two buttons/);
  const picture = readFileSync(join(notificationSdk, 'default/openharmony/ets/api/notification/notificationContent.d.ts'), 'utf8');
  assert.match(picture, /cannot exceed 2 MB/);
  console.log('Installed SDK confirms ReminderAgent permission/API26 interval, two phone actions, and 2 MiB picture limit.');
}
