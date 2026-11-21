import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/calendar_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

part 'event_calendar.g.dart';

/// `uname` 是用户名（'me'/空 = 当前用户）；日历接口只认 auth user id。
Future<String?> _resolveUserId(CalendarApi api, String? uname) async {
  if (uname == null || uname.isEmpty || uname == 'me') return null;
  return api.resolveUserId(uname);
}

/// Search result item that can be either a user event or a notable day
class CalendarSearchResult {
  final String type; // 'UserEvent' or 'NotableDay'
  final DateTime startTime;
  final DateTime endTime;
  final SnUserCalendarEvent? userEvent;
  final SnNotableDayDetail? notableDay;

  const CalendarSearchResult({
    required this.type,
    required this.startTime,
    required this.endTime,
    this.userEvent,
    this.notableDay,
  });

  factory CalendarSearchResult.fromJson(Map<String, dynamic> json) {
    // API returns type as int: 0=UserEvent, 1=NotableDay
    final typeValue = json['type'];
    final isUserEvent = typeValue is int
        ? typeValue == 0
        : (typeValue as String) == 'UserEvent';

    if (isUserEvent) {
      return CalendarSearchResult(
        type: 'UserEvent',
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: DateTime.parse(json['end_time'] as String),
        userEvent: json['user_event'] != null
            ? SnUserCalendarEvent.fromJson(
                json['user_event'] as Map<String, dynamic>,
              )
            : null,
      );
    } else {
      return CalendarSearchResult(
        type: 'NotableDay',
        startTime: DateTime.parse(json['start_time'] as String),
        endTime: DateTime.parse(json['end_time'] as String),
        notableDay: json['notable_day'] != null
            ? SnNotableDayDetail.fromJson(
                json['notable_day'] as Map<String, dynamic>,
              )
            : null,
      );
    }
  }
}

/// Query parameters for fetching event calendar data
class EventCalendarQuery {
  /// Username to fetch calendar for, null means current user ('me')
  final String? uname;

  /// Year to fetch calendar for
  final int year;

  /// Month to fetch calendar for
  final int month;

  /// Whether to include notable days (holidays)
  final bool includeNotableDays;

  /// Whether to use merged calendar view
  final bool useMergedView;

  const EventCalendarQuery({
    required this.uname,
    required this.year,
    required this.month,
    this.includeNotableDays = true,
    this.useMergedView = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventCalendarQuery &&
          runtimeType == other.runtimeType &&
          uname == other.uname &&
          year == other.year &&
          month == other.month &&
          includeNotableDays == other.includeNotableDays &&
          useMergedView == other.useMergedView;

  @override
  int get hashCode =>
      uname.hashCode ^
      year.hashCode ^
      month.hashCode ^
      includeNotableDays.hashCode ^
      useMergedView.hashCode;
}

/// Provider for fetching event calendar data
/// This can be used anywhere in the app where calendar data is needed
@riverpod
Future<List<SnEventCalendarEntry>> eventCalendar(
  Ref ref,
  EventCalendarQuery query,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  final isMe = query.uname == null || query.uname == 'me';
  if (isMe && !session.isSignedIn) return const [];

  final api = CalendarApi(session.client);
  return session.run(() async {
    final userId = await _resolveUserId(api, query.uname);
    final entries = await api.month(
      year: query.year,
      month: query.month,
      userId: userId,
      includeNotableDays: query.includeNotableDays,
    );
    return entries.map(SnEventCalendarEntry.fromJson).toList();
  });
}

/// Provider for fetching merged calendar for a specific month
@riverpod
Future<SnEventCalendarEntry> mergedCalendar(
  Ref ref, {
  required int year,
  required int month,
  String? username,
}) async {
  final session = ref.watch(lkmApiSessionProvider);
  final api = CalendarApi(session.client);
  return session.run(() async {
    final userId = await _resolveUserId(api, username);
    final entry = await api.merged(year: year, month: month, userId: userId);
    return SnEventCalendarEntry.fromJson(entry);
  });
}

/// Query parameters for listing calendar events
class CalendarEventListQuery {
  final DateTime? startTime;
  final DateTime? endTime;
  final int offset;
  final int take;

  const CalendarEventListQuery({
    this.startTime,
    this.endTime,
    this.offset = 0,
    this.take = 50,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEventListQuery &&
          runtimeType == other.runtimeType &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          offset == other.offset &&
          take == other.take;

  @override
  int get hashCode =>
      startTime.hashCode ^ endTime.hashCode ^ offset.hashCode ^ take.hashCode;
}

/// Provider for listing user's calendar events
@riverpod
Future<PaginatedResult<SnUserCalendarEvent>> calendarEvents(
  Ref ref,
  CalendarEventListQuery query,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) {
    return const PaginatedResult(items: [], totalCount: 0);
  }
  final api = CalendarApi(session.client);
  final page = await session.run(
    () => api.listEvents(
      startTime: query.startTime,
      endTime: query.endTime,
      offset: query.offset,
      take: query.take,
    ),
  );
  return PaginatedResult(
    items: page.items.map(SnUserCalendarEvent.fromJson).toList(),
    totalCount: page.total,
  );
}

/// Provider for a single calendar event
@riverpod
Future<SnUserCalendarEvent> calendarEvent(Ref ref, String eventId) async {
  final session = ref.watch(lkmApiSessionProvider);
  final api = CalendarApi(session.client);
  return session.run(
    () async => SnUserCalendarEvent.fromJson(await api.event(eventId)),
  );
}

/// Query parameters for event countdowns
class EventCountdownQuery {
  final String? username;
  final bool includeNotableDays;
  final String? tag;

  const EventCountdownQuery({
    this.username,
    this.includeNotableDays = true,
    this.tag,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventCountdownQuery &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          includeNotableDays == other.includeNotableDays &&
          tag == other.tag;

  @override
  int get hashCode => username.hashCode ^ includeNotableDays.hashCode ^ tag.hashCode;
}

/// Provider for paginated event countdowns
final eventCountdownListProvider = AsyncNotifierProvider.autoDispose.family(
  EventCountdownListNotifier.new,
);

class EventCountdownListNotifier
    extends AsyncNotifier<PaginationState<SnEventCountdownItem>>
    with AsyncPaginationController<SnEventCountdownItem> {
  static const int pageSize = 20;

  final EventCountdownQuery query;
  EventCountdownListNotifier(this.query);

  @override
  FutureOr<PaginationState<SnEventCountdownItem>> build() async {
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
  Future<List<SnEventCountdownItem>> fetch() async {
    final session = ref.read(lkmApiSessionProvider);
    if (!session.isSignedIn) {
      totalCount = 0;
      return const [];
    }
    final api = CalendarApi(session.client);

    final result = await session.run(() async {
      final userId = await _resolveUserId(api, query.username);
      return api.countdown(
        userId: userId,
        take: pageSize,
        offset: fetchedCount,
        includeNotableDays: query.includeNotableDays,
        tag: query.tag,
      );
    });

    totalCount = result.total;

    return result.items.map(SnEventCountdownItem.fromJson).toList();
  }
}

/// Provider for the list of account IDs the current user has subscribed to
@riverpod
Future<List<String>> calendarSubscriptions(Ref ref) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return const [];
  final api = CalendarApi(session.client);
  return session.run(api.subscriptions);
}

/// Checks if the current user is subscribed to a specific account's calendar
@riverpod
Future<bool> isCalendarSubscribed(Ref ref, String accountId) async {
  final subscriptions = await ref.watch(calendarSubscriptionsProvider.future);
  return subscriptions.contains(accountId);
}

/// Provider for fetching the current user's used calendar tags
@riverpod
Future<List<String>> usedCalendarTags(Ref ref) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return const [];
  final api = CalendarApi(session.client);
  return session.run(api.tags);
}

/// Query parameters for calendar search
class CalendarSearchQuery {
  final String? query;
  final String? accountId;
  final List<String> tags;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? notableDayTag;
  final int offset;
  final int take;
  final bool isSearchActive;

  const CalendarSearchQuery({
    this.query,
    this.accountId,
    this.tags = const [],
    this.startTime,
    this.endTime,
    this.notableDayTag,
    this.offset = 0,
    this.take = 50,
    this.isSearchActive = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarSearchQuery &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          accountId == other.accountId &&
          _listEquals(tags, other.tags) &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          notableDayTag == other.notableDayTag &&
          offset == other.offset &&
          take == other.take &&
          isSearchActive == other.isSearchActive;

  @override
  int get hashCode =>
      Object.hash(
        query,
        accountId,
        Object.hashAll(tags),
        startTime,
        endTime,
        notableDayTag,
        offset,
        take,
        isSearchActive,
      );

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Provider for searching calendar events + notable days
@riverpod
Future<List<CalendarSearchResult>> calendarSearch(
  Ref ref,
  CalendarSearchQuery query,
) async {
  final normalizedQuery = query.query?.trim();
  final hasFilters =
      (normalizedQuery?.isNotEmpty ?? false) ||
      query.tags.isNotEmpty ||
      query.notableDayTag != null;

  // Return empty if search is not active (avoids unnecessary API calls)
  if (!query.isSearchActive || !hasFilters) {
    return const [];
  }

  final session = ref.watch(lkmApiSessionProvider);
  final api = CalendarApi(session.client);
  final results = await session.run(
    () => api.search(
      query: normalizedQuery,
      accountId: query.accountId,
      tags: query.tags.isEmpty ? null : query.tags,
      startTime: query.startTime,
      endTime: query.endTime,
      notableDayTag: query.notableDayTag,
      offset: query.offset,
      take: query.take,
    ),
  );
  return results
      .map((json) => CalendarSearchResult.fromJson(json))
      .toList();
}
