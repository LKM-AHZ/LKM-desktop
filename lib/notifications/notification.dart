import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/lkm_ws.dart';
import 'package:island/core/api/notification_api.dart';
import 'package:island/core/config.dart';
import 'package:island/core/utils/bounded_id_set.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:island/shared/widgets/content/markdown.dart';
import 'package:island/shared/widgets/layouts/attention_modal_scaffold.dart';
import 'package:island/notifications/notification_tile.dart';
import 'package:island/shared/widgets/pagination_list.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:styled_widget/styled_widget.dart';

part 'notification.g.dart';

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(lkmApiSessionProvider).client);
});

/// Live LKM push frames (`upload` + `notify`). Scoped to whoever listens, so
/// the socket only stays open while a consumer is on screen. Delivery is
/// best-effort — consumers also refresh on open.
final realtimeEventsProvider = StreamProvider.autoDispose<LkmWsEvent>((ref) {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return const Stream<LkmWsEvent>.empty();
  final client = LkmWsClient(
    serverUrl: session.serverUrl,
    tokenProvider: () => session.cachedAccessToken,
  );
  ref.onDispose(client.close);
  client.connect();
  return client.events;
});

class SkeletonNotificationTile extends StatelessWidget {
  const SkeletonNotificationTile({super.key});

  @override
  Widget build(BuildContext context) {
    const fakeTitle = 'New notification';
    const fakeSubtitle = 'You have a new message from someone';
    const fakeContent =
        'This is a preview of the notification content. It may contain formatted text.';
    const List<String> fakeImageIds = []; // Empty list for no images
    const String? fakePfp = null; // No profile picture

    return ListTile(
      isThreeLine: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: fakePfp != null
          ? ProfilePictureWidget(file: null, radius: 20)
          : CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Symbols.notifications,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
      title: const Text(fakeTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fakeSubtitle).bold(),
          Row(
            spacing: 6,
            children: [
              Text('loading'.tr()).fontSize(11),
              Skeleton.ignore(child: Text('·').fontSize(11).bold()),
              Text('now'.tr()).fontSize(11),
            ],
          ).opacity(0.75).padding(bottom: 4),
          MarkdownTextContent(
            content: fakeContent,
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          if (fakeImageIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fakeImageIds.map((imageId) {
                  return SizedBox(
                    width: 80,
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CloudImageWidget(
                        fileId: imageId,
                        aspectRatio: 1,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
      trailing: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
      ),
      onTap: () {},
    );
  }
}

/// Localized label for an LKM notification type. Unknown types fall back to
/// the raw value so new backend events still render something readable.
String notificationTypeLabel(String type) => switch (type) {
  'content_liked' => 'notificationTypeContentLiked'.tr(),
  'content_commented' => 'notificationTypeContentCommented'.tr(),
  'comment_replied' => 'notificationTypeCommentReplied'.tr(),
  'qa_answer_accepted' => 'notificationTypeQaAccepted'.tr(),
  'review_digest' => 'notificationTypeReviewDigest'.tr(),
  'subscription_new_post' => 'notificationTypeSubscriptionNewPost'.tr(),
  'post_watch_activity' => 'notificationTypePostWatchActivity'.tr(),
  'project_invited' => 'notificationTypeProjectInvited'.tr(),
  'project_join_approved' => 'notificationTypeProjectJoinApproved'.tr(),
  'project_join_rejected' => 'notificationTypeProjectJoinRejected'.tr(),
  'project_member_removed' => 'notificationTypeProjectMemberRemoved'.tr(),
  _ => type,
};

/// Adapts an LKM in-app notification onto the SDK model the shared tile,
/// dashboard card and system-notification bridges already render.
///
/// The payload carries `title` / `url`, the actor name and, for some system
/// notices, attachments (`pfp`, `images`). Missing fields stay empty rather
/// than inventing content; the tile treats an empty body as "no preview".
SnNotification snNotificationFromPayload({
  required String id,
  required String type,
  required Map<String, dynamic> payload,
  DateTime? createdAt,
  DateTime? readAt,
  String? actorId,
}) {
  final title = payload['title'];
  final actorName = payload['actor_name'];
  final url = payload['url'];
  final pfp = payload['pfp'];
  final images = payload['images'];
  final body = payload['content'] ?? payload['body'];
  return SnNotification(
    createdAt: createdAt ?? DateTime.now(),
    id: id,
    topic: type,
    title: title is String && title.trim().isNotEmpty
        ? title
        : notificationTypeLabel(type),
    subtitle: actorName is String ? actorName : '',
    body: body is String ? body : '',
    meta: {
      if (url is String && url.isNotEmpty) 'action_uri': url,
      if (pfp is String && pfp.isNotEmpty) 'pfp': pfp,
      if (images is List) 'images': images,
      'api_type': type,
      if (actorId != null) 'actor_id': actorId,
    },
    viewedAt: readAt,
    accountId: '',
  );
}

SnNotification snNotificationFromApi(LkmNotification notification) =>
    snNotificationFromPayload(
      id: notification.id,
      type: notification.type,
      payload: notification.payload,
      createdAt: notification.createdAt,
      readAt: notification.readAt,
      actorId: notification.actorId,
    );

/// Marks [ids] (or every notification) read on the LKM service.
Future<void> markNotificationsRead(
  WidgetRef ref, {
  List<String> ids = const [],
  bool all = false,
}) async {
  final session = ref.read(lkmApiSessionProvider);
  if (!session.isSignedIn) return;
  await session.run(
    () => ref.read(notificationApiProvider).markRead(ids: ids, all: all),
  );
  ref.invalidate(notificationUnreadCountProvider);
}

@riverpod
class NotificationUnreadCountNotifier
    extends _$NotificationUnreadCountNotifier {
  /// Ids already counted. Push delivery is at-least-once, so the same
  /// notification can be re-sent; `refresh()` reconciles the true total.
  final _countedNotificationIds = BoundedIdSet(512);

  @override
  Future<int> build() async {
    // Subscribe to push events when this provider is built. The LKM session
    // owns the socket lifecycle; `realtimeEventsProvider` reconnects itself.
    ref.listen(realtimeEventsProvider, (_, next) {
      next.whenData((event) {
        if (event.event != 'notification_created') return;
        final id = event.data['notification_id'];
        if (id is String && !_countedNotificationIds.add(id)) return;
        _incrementCounter();
      });
    });

    final session = ref.watch(lkmApiSessionProvider);
    if (!session.isSignedIn) return 0;
    try {
      return await session.run(
        () => ref.read(notificationApiProvider).unreadCount(),
      );
    } catch (_) {
      return 0;
    }
  }

  Future<void> _incrementCounter() async {
    final current = await future;
    state = AsyncData(current + 1);
  }

  Future<void> decrement(int count) async {
    final current = await future;
    state = AsyncData(math.max(current - count, 0));
  }

  void clear() async {
    state = AsyncData(0);
  }

  Future<void> refresh() async {
    final session = ref.read(lkmApiSessionProvider);
    if (!session.isSignedIn) {
      state = const AsyncData(0);
      return;
    }
    try {
      final count = await session.run(
        () => ref.read(notificationApiProvider).unreadCount(),
      );
      state = AsyncData(count);
    } catch (_) {
      // Keep the current state if refresh fails
    }
  }
}

final notificationListProvider = AsyncNotifierProvider.autoDispose(
  NotificationListNotifier.new,
);

class NotificationListNotifier
    extends AsyncNotifier<PaginationState<SnNotification>>
    with AsyncPaginationController<SnNotification> {
  static const int pageSize = 5;

  /// Next LKM page to request. The controller's `fetchedCount` cannot carry
  /// this: LKM pages are not offset windows and a refresh rebuilds the state.
  int _nextPage = 1;

  @override
  FutureOr<PaginationState<SnNotification>> build() async {
    _nextPage = 1;
    final items = await fetch();
    return PaginationState(
      items: items,
      isLoading: false,
      isReloading: false,
      totalCount: totalCount,
      hasMore: hasMore,
      cursor: cursor,
    );
  }

  @override
  Future<List<SnNotification>> fetch() async {
    final session = ref.read(lkmApiSessionProvider);
    if (!session.isSignedIn) {
      totalCount = 0;
      return const [];
    }
    final page = _nextPage;
    final response = await session.run(
      () => ref.read(notificationApiProvider).list(page: page, limit: pageSize),
    );
    _nextPage = page + 1;
    totalCount = response.total;
    return response.items.map(snNotificationFromApi).toList(growable: false);
  }

  /// Flips every loaded entry to read without another round-trip; used after
  /// `mark all read` succeeds so the dots disappear immediately.
  void markAllLoadedRead() {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        items: current.items
            .map((e) => e.viewedAt == null ? e.copyWith(viewedAt: now) : e)
            .toList(growable: false),
      ),
    );
  }
}

class NotificationModal extends HookConsumerWidget {
  final VoidCallback onDismiss;

  const NotificationModal({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(() async {
        await ref.read(notificationUnreadCountProvider.notifier).refresh();
        // The notification list provider fetches its first page from build().
        // Refreshing it here starts a second request; the API marks a fetched
        // page as viewed, so that request can replace the unread snapshot with
        // an already-viewed response.
      });
      return null;
    }, []);

    final isLoading = useState(false);

    Future<void> markAllRead() async {
      isLoading.value = true;
      try {
        await markNotificationsRead(ref, all: true);
      } finally {
        if (context.mounted) isLoading.value = false;
      }
      ref.read(notificationListProvider.notifier).markAllLoadedRead();
      ref.read(notificationUnreadCountProvider.notifier).clear();
    }

    final titleText = 'notifications'.tr();

    return AttentionModalScaffold(
      titleText: titleText,
      onDismiss: onDismiss,
      actions: [
        IconButton(
          onPressed: markAllRead,
          icon: const Icon(Symbols.mark_as_unread),
          tooltip: 'markAllRead'.tr(),
        ),
      ],
      child: Column(
        children: [
          if (isLoading.value)
            LinearProgressIndicator(
              minHeight: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          Expanded(
            child: PaginationList(
              provider: notificationListProvider,
              notifier: notificationListProvider.notifier,
              footerSkeletonChild: Skeletonizer(
                enabled: true,
                child: const SkeletonNotificationTile(),
              ),
              itemBuilder: (context, index, notification) {
                return NotificationTile(notification: notification);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Custom App Notifications (POST /api/private/apps/{appId}/notifications)
// ==========================================

/// Request body for sending a custom-app notification.
/// Docs: DysonNetwork/docs/CUSTOM_APP_NOTIFICATIONS.md
class CustomAppNotificationRequest {
  final String topic;
  final String title;
  final String? accountId;
  final List<String>? accountIds;
  final bool broadcastToAll;
  final String? subtitle;
  final String? body;
  final String? actionUri;
  final String? pushType;
  final bool? isSilent;
  final bool? isSavable;
  final Map<String, dynamic>? meta;

  CustomAppNotificationRequest({
    required this.topic,
    required this.title,
    this.accountId,
    this.accountIds,
    this.broadcastToAll = false,
    this.subtitle,
    this.body,
    this.actionUri,
    this.pushType,
    this.isSilent,
    this.isSavable,
    this.meta,
  }) : assert(
         broadcastToAll || accountId != null || (accountIds?.isNotEmpty == true),
         'Must provide at least one of: broadcastToAll, accountId, or accountIds',
       );

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'topic': topic,
      'title': title,
    };
    if (broadcastToAll) data['broadcast_to_all'] = true;
    if (accountId != null) data['account_id'] = accountId;
    if (accountIds?.isNotEmpty == true) {
      data['account_ids'] = accountIds;
    }
    if (subtitle != null) data['subtitle'] = subtitle;
    if (body != null) data['body'] = body;
    if (actionUri != null) data['action_uri'] = actionUri;
    if (pushType != null) data['push_type'] = pushType;
    if (isSilent != null) data['is_silent'] = isSilent;
    if (isSavable != null) data['is_savable'] = isSavable;
    if (meta != null) data['meta'] = meta;
    return data;
  }
}

/// Response from sending a custom-app notification.
class CustomAppNotificationResponse {
  final int sent;
  final String scope;
  final bool broadcastToAll;

  CustomAppNotificationResponse({
    required this.sent,
    required this.scope,
    required this.broadcastToAll,
  });

  factory CustomAppNotificationResponse.fromJson(Map<String, dynamic> json) {
    return CustomAppNotificationResponse(
      sent: (json['sent'] as num).toInt(),
      scope: json['scope'] as String,
      broadcastToAll: json['broadcast_to_all'] as bool,
    );
  }
}

/// Sends a custom-app notification using the app's API key.
///
/// Uses X-Api-Key auth (not Bearer). See CUSTOM_APP_NOTIFICATIONS.md.
Future<CustomAppNotificationResponse> sendCustomAppNotification({
  required String serverUrl,
  required String appId,
  required String apiKey,
  required CustomAppNotificationRequest request,
}) async {
  final dio = Dio(BaseOptions(
    baseUrl: serverUrl,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Api-Key': apiKey,
    },
  ));
  try {
    final response = await dio.post<Map<String, dynamic>>(
      '/api/private/apps/$appId/notifications',
      data: request.toJson(),
    );
    return CustomAppNotificationResponse.fromJson(response.data!);
  } finally {
    dio.close();
  }
}

/// Riverpod provider that creates a Dio instance for custom-app notification requests.
@riverpod
Dio customAppNotificationDio(Ref ref, String apiKey) {
  final serverUrl = ref.watch(serverUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: serverUrl,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Api-Key': apiKey,
    },
  ));
  ref.onDispose(() => dio.close());
  return dio;
}
