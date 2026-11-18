import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/notification_api.dart';
import 'package:island/notifications/notification.dart';

class _FakeNotifications implements NotificationApi {
  _FakeNotifications(this.pages);

  final List<ApiPage<LkmNotification>> pages;
  final List<int> requestedPages = [];

  @override
  Future<ApiPage<LkmNotification>> list({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    requestedPages.add(page);
    return pages[page - 1];
  }

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<int> markRead({List<String> ids = const [], bool all = false}) async {
    return all ? 99 : ids.length;
  }
}

LkmNotification _notification(
  String id, {
  Map<String, dynamic> payload = const {'title': '有人回复了你'},
  bool read = false,
}) => LkmNotification(
  id: id,
  type: 'content_commented',
  payload: payload,
  createdAt: DateTime(2026, 11, 8, 12, 30),
  readAt: read ? DateTime(2026, 11, 8, 13) : null,
);

ApiPage<LkmNotification> _page(
  List<LkmNotification> items, {
  required int page,
  required int pages,
  int? total,
}) => ApiPage(
  items: items,
  total: total ?? items.length,
  page: page,
  pages: pages,
);

void main() {
  test('maps an LKM payload onto the shared SnNotification shape', () {
    final mapped = snNotificationFromPayload(
      id: 'n1',
      type: 'content_commented',
      payload: const {
        'title': '帖子标题',
        'url': '/content/posts/p1',
        'actor_name': '小明',
        'pfp': 'file-1',
      },
      createdAt: DateTime(2026, 11, 8),
      readAt: DateTime(2026, 11, 9),
      actorId: 'u1',
    );

    expect(mapped.id, 'n1');
    expect(mapped.topic, 'content_commented');
    expect(mapped.title, '帖子标题');
    expect(mapped.subtitle, '小明');
    expect(mapped.viewedAt, DateTime(2026, 11, 9));
    expect(mapped.meta['action_uri'], '/content/posts/p1');
    expect(mapped.meta['pfp'], 'file-1');
    expect(mapped.meta['api_type'], 'content_commented');
  });

  test('falls back to the localized type label when payload has no title', () {
    final mapped = snNotificationFromApi(_notification('n2', payload: const {}));
    expect(mapped.title.isNotEmpty, isTrue);
    expect(mapped.title, isNot('content_commented'));
  });

  test('list provider walks LKM pages and maps every row', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://community.example',
    );
    await session.adopt(
      const LkmTokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );
    final fake = _FakeNotifications([
      _page(
        [_notification('a'), _notification('b')],
        page: 1,
        pages: 2,
        total: 3,
      ),
      _page([_notification('c')], page: 2, pages: 2, total: 3),
    ]);
    final container = ProviderContainer(
      overrides: [
        lkmApiSessionProvider.overrideWithValue(session),
        notificationApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      notificationListProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final first = await container.read(notificationListProvider.future);
    expect(first.items.map((e) => e.id), ['a', 'b']);

    await container.read(notificationListProvider.notifier).fetchFurther();

    final second = container.read(notificationListProvider).value!;
    expect(second.items.map((e) => e.id), ['a', 'b', 'c']);
    expect(fake.requestedPages, [1, 2]);
  });
}
