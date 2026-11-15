import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart';
import 'ohos_notification_details.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';

/// HarmonyOS notifications using the existing shared callback and payload API.
class OhosFlutterLocalNotificationsPlugin
    extends FlutterLocalNotificationsPlatform {
  static const channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static void registerWith() => FlutterLocalNotificationsPlatform.instance =
      OhosFlutterLocalNotificationsPlugin();
  Future<bool> initialize({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'didReceiveNotificationResponse') {
        onDidReceiveNotificationResponse?.call(
          _response(Map<Object?, Object?>.from(call.arguments as Map)),
        );
      }
    });
    return await channel.invokeMethod<bool>('initialize') ?? false;
  }

  Future<bool> requestPermissions() async =>
      await channel.invokeMethod<bool>('requestPermissions') ?? false;
  static NotificationResponse _response(Map<Object?, Object?> row) =>
      NotificationResponse(
        notificationResponseType: row['actionId'] == null
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        actionId: row['actionId'] as String?,
        id: row['id'] as int?,
        payload: row['payload'] as String?,
      );
  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    final row = await channel.invokeMapMethod<Object?, Object?>(
      'getNotificationAppLaunchDetails',
    );
    return NotificationAppLaunchDetails(
      row != null,
      notificationResponse: row == null ? null : _response(row),
    );
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    OhosNotificationDetails? notificationDetails,
  }) {
    validateId(id);
    return channel.invokeMethod<void>('show', {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'details': notificationDetails?.toMap(),
    });
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required TZDateTime scheduledDate,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    OhosNotificationDetails? notificationDetails,
  }) {
    validateId(id);
    return channel.invokeMethod<void>('zonedSchedule', {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'details': notificationDetails?.toMap(),
      'epochMilliseconds': scheduledDate.millisecondsSinceEpoch,
      'timeZoneName': scheduledDate.location.name,
      'match': matchDateTimeComponents?.name,
      'year': scheduledDate.year,
      'month': scheduledDate.month,
      'day': scheduledDate.day,
      'hour': scheduledDate.hour,
      'minute': scheduledDate.minute,
      'second': scheduledDate.second,
      'weekday': scheduledDate.weekday,
    });
  }

  @override
  Future<void> periodicallyShow({
    required int id,
    required RepeatInterval repeatInterval,
    String? title,
    String? body,
    String? payload,
    OhosNotificationDetails? notificationDetails,
  }) => periodicallyShowWithDuration(
    id: id,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: notificationDetails,
    repeatDurationInterval: switch (repeatInterval) {
      RepeatInterval.everyMinute => const Duration(minutes: 1),
      RepeatInterval.hourly => const Duration(hours: 1),
      RepeatInterval.daily => const Duration(days: 1),
      RepeatInterval.weekly => const Duration(days: 7),
    },
  );

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    required Duration repeatDurationInterval,
    String? title,
    String? body,
    String? payload,
    OhosNotificationDetails? notificationDetails,
  }) {
    validateId(id);
    if (repeatDurationInterval < const Duration(days: 1) ||
        repeatDurationInterval.inMicroseconds %
                Duration.microsecondsPerSecond !=
            0) {
      throw UnsupportedError(
        'OHOS system reminder intervals require whole seconds and at least one day',
      );
    }
    return channel.invokeMethod<void>('periodicallyShow', {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'details': notificationDetails?.toMap(),
      'repeatSeconds': repeatDurationInterval.inSeconds,
    });
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    final rows = await channel.invokeListMethod<Object?>(
      'pendingNotificationRequests',
    );
    return (rows ?? []).map((value) {
      final row = Map<Object?, Object?>.from(value! as Map);
      return PendingNotificationRequest(
        row['id']! as int,
        row['title'] as String?,
        row['body'] as String?,
        row['payload'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> cancelAllPendingNotifications() =>
      channel.invokeMethod<void>('cancelAllPendingNotifications');

  @override
  Future<void> cancel({required int id}) =>
      channel.invokeMethod<void>('cancel', {'id': id});
  @override
  Future<void> cancelAll() => channel.invokeMethod<void>('cancelAll');
}
