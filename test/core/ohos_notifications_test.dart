import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'OHOS notification public API initializes and retains cold/warm payloads',
    () async {
      final previous = LinuxFlutterLocalNotificationsPlugin();
      debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
      OhosFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => true,
          'requestPermissions' => false,
          'pendingNotificationRequests' => [
            {
              'id': 12,
              'title': 'Later',
              'body': 'Body',
              'payload': 'scheduled',
            },
          ],
          'getNotificationAppLaunchDetails' => {
            'id': 4,
            'payload': 'lkm://cold',
          },
          _ => null,
        };
      });
      try {
        NotificationResponse? response;
        final plugin = FlutterLocalNotificationsPlugin();
        expect(
          await plugin.initialize(
            settings: const InitializationSettings(),
            onDidReceiveNotificationResponse: (value) => response = value,
          ),
          true,
        );
        expect(
          await plugin
              .resolvePlatformSpecificImplementation<
                OhosFlutterLocalNotificationsPlugin
              >()!
              .requestPermissions(),
          false,
        );
        expect(
          (await plugin.getNotificationAppLaunchDetails())!
              .notificationResponse!
              .payload,
          'lkm://cold',
        );
        await plugin.show(
          id: 9,
          title: 'Title',
          body: 'Body',
          payload: 'lkm://test',
        );
        expect(calls.last.arguments, containsPair('payload', 'lkm://test'));
        await plugin.show(
          id: 10,
          title: 'Picture',
          body: 'Body',
          notificationDetails: const NotificationDetails(
            ohos: OhosNotificationDetails(
              imagePath: '/cache/image.png',
              actions: [OhosNotificationAction('open', 'Open')],
            ),
          ),
        );
        expect((calls.last.arguments as Map)['details'], {
          'imagePath': '/cache/image.png',
          'actions': [
            {'id': 'open', 'title': 'Open'},
          ],
        });
        final scheduled = tz.TZDateTime.from(
          DateTime.now().add(const Duration(days: 1)),
          tz.UTC,
        );
        await plugin.zonedSchedule(
          id: 12,
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(),
          androidScheduleMode: AndroidScheduleMode.exact,
          payload: 'scheduled',
        );
        expect(calls.last.method, 'zonedSchedule');
        expect(
          calls.last.arguments,
          containsPair('epochMilliseconds', scheduled.millisecondsSinceEpoch),
        );
        expect(calls.last.arguments, containsPair('payload', 'scheduled'));
        await plugin.periodicallyShow(
          id: 13,
          repeatInterval: RepeatInterval.daily,
          notificationDetails: const NotificationDetails(),
          androidScheduleMode: AndroidScheduleMode.exact,
          payload: 'daily',
        );
        expect(calls.last.arguments, containsPair('repeatSeconds', 86400));
        expect(calls.last.arguments, containsPair('payload', 'daily'));
        await expectLater(
          plugin.periodicallyShow(
            id: 13,
            repeatInterval: RepeatInterval.hourly,
            notificationDetails: const NotificationDetails(),
            androidScheduleMode: AndroidScheduleMode.exact,
          ),
          throwsUnsupportedError,
        );
        expect(
          (await plugin.pendingNotificationRequests()).single.payload,
          'scheduled',
        );
        await plugin.cancelAllPendingNotifications();
        expect(calls.last.method, 'cancelAllPendingNotifications');
        await plugin.cancel(id: 9);
        expect(calls.last.arguments, containsPair('id', 9));
        await plugin.cancelAll();
        expect(calls.last.method, 'cancelAll');
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('didReceiveNotificationResponse', {
              'id': 9,
              'payload': 'lkm://warm',
              'actionId': 'open',
            }),
          ),
          (_) {},
        );
        expect(response!.payload, 'lkm://warm');
        expect(response!.id, 9);
        expect(response!.actionId, 'open');
        expect(
          response!.notificationResponseType,
          NotificationResponseType.selectedNotificationAction,
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        channel.setMethodCallHandler(null);
        FlutterLocalNotificationsPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
