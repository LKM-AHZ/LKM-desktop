/// An action that opens the application and reports [id] in NotificationResponse.
class OhosNotificationAction {
  const OhosNotificationAction(this.id, this.title);
  final String id;
  final String title;
  Map<String, Object> toMap() => {'id': id, 'title': title};
}

/// HarmonyOS supports one local image and foreground action buttons.
/// Scheduled reminders use text only; unsupported details are rejected.
class OhosNotificationDetails {
  const OhosNotificationDetails({this.imagePath, this.actions = const []});
  final String? imagePath;
  final List<OhosNotificationAction> actions;
  Map<String, Object?> toMap() => {
    'imagePath': imagePath,
    'actions': actions.map((action) => action.toMap()).toList(),
  };
}
