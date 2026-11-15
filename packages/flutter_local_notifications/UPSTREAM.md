# flutter_local_notifications 23.0.0

Published source: https://pub.dev/packages/flutter_local_notifications/versions/23.0.0
Archive SHA-256: `e99e9c6078d1359ba131b2c1eb8d68837170836a01bf2cea3cf2fa13e62ac2ac`.

Original API and existing platform source retained at 23.0.0/interface 13.0.0.
OHOS metadata originated from the community fork at commit
`60d3aaef273b7cddd89312007a06419ea3c203e4`:
https://gitcode.com/oh-flutter/flutter_local_notifications
The former backend was incomplete (no payload/launch handling, cancel protocol mismatch).
The local OHOS backend is rewritten against current SDK NotificationKit and WantAgent.
The current public initialize path now invokes the OH backend and callback registrar;
show/cancel use current shared platform methods. Real cold launchWant and warm
NewWant listener callbacks carry notification payloads; detach settles pending replies.
Notification permission uses the current system requestEnableNotification API.
Shared app notification IDs are constrained to int32 on every platform.

Supports immediate text/picture notifications, up to two foreground actions on
phone/tablet, permission requests, cold/warm payload + actionId routing, cancel,
cancelAll, pendingNotificationRequests and cancelAllPendingNotifications.
OhosNotificationDetails is an optional field in the existing NotificationDetails;
the shared show/schedule methods keep all original platform dispatch paths.
A picture must be a local path/file URI and fit the SDK's 2 MiB decoded pixel
limit; ImageSource and PixelMap are released on success and failure. Foreground
actions use distinct WantAgent identities, including an action named "tap".
Background isolate actions and arbitrary file/video attachments remain unsupported.

zonedSchedule uses system ReminderAgentManager timers for single absolute instants
and Calendar reminders for repeating time/day/week/month/date components. Calendar
repetition requires the device's IANA timezone; other timezone/DST rules cannot be
retained by this SDK and are rejected. periodicallyShow[WithDuration] uses API 26
repeating system timers; whole-second intervals of at least 86400 seconds are
supported. Minute/hour periods are explicitly rejected by the SDK constraint,
not approximated with in-process timers. Scheduled reminders accept text only;
images and foreground actions are rejected. The host must declare
`ohos.permission.PUBLISH_AGENT_REMINDER` and notification permission must be granted.
System limits/permission failures propagate. Cancellation and pending queries read
system ReminderInfo records rather than process-local state, so they survive
process restart; notificationId is the SDK replacement key. Detachment settles
replies and cancels a newly scheduled reminder if its ability disappeared while
publishing. Operations serialize to avoid late scheduling after cancellation.

SDK evidence: `@ohos.reminderAgentManager.d.ts` ReminderRequestTimer repeatInterval
is API 26 and >=86400 seconds; WantAgent.parameters/getAllValidReminders are API 12.
`notification/notificationRequest.d.ts` limits phone/tablet actionButtons to two
(three is a wearable extension); `notificationContent.d.ts` limits picture pixels
to 2 MB. `node buildtools/verify-ohos-notifications.mjs` executes the real backend
with SDK stubs and asserts these installed SDK declarations. Public Dart channel
regression is in `test/core/ohos_notifications_test.dart`.

Original BSD LICENSE retained; generated native files/examples/tests are omitted.
Real permission dialogs, background delivery, timezone changes, taps, photo URI
access and system reminder quotas still require device validation.
