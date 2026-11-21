import 'api_client.dart';

/// Calendar reads/writes on LKM-service.
///
/// Returns the raw wire maps — the caller parses them into the SDK's `Sn*` models
/// (`SnUserCalendarEvent`, `SnEventCalendarEntry`, …) so every existing calendar
/// widget keeps working unchanged.
class CalendarApi {
  const CalendarApi(this._client);

  final ApiClient _client;

  static const String _base = '/calendar';

  /// Username → auth user id. The calendar endpoints key off the id.
  Future<String> resolveUserId(String username) async {
    final data = await _client.getObject(
      '/auth/user/by-username/${Uri.encodeComponent(username)}',
    );
    final id = '${data['user_id'] ?? ''}';
    if (id.isEmpty || id == 'null') {
      throw ApiException(
        code: ApiCode.notFound,
        message: '用户 $username 不存在',
        path: '/auth/user/by-username/$username',
      );
    }
    return id;
  }

  Future<ApiPage<Map<String, dynamic>>> listEvents({
    DateTime? startTime,
    DateTime? endTime,
    String? accountId,
    String? query,
    List<String>? tags,
    int offset = 0,
    int take = 50,
  }) {
    return _client.getPage<Map<String, dynamic>>(
      '$_base/events',
      query: {
        'startTime': ?startTime?.toUtc().toIso8601String(),
        'endTime': ?endTime?.toUtc().toIso8601String(),
        'accountId': ?accountId,
        'query': ?query,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        'offset': offset,
        'take': take,
      },
      parseItem: (json) => json,
    );
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async {
    final data = await _client.post('$_base/events', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateEvent(
    String id,
    Map<String, dynamic> body,
  ) async {
    final data = await _client.put('$_base/events/$id', body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> event(String id) async {
    return _client.getObject('$_base/events/$id');
  }

  Future<void> deleteEvent(String id) => _client.delete('$_base/events/$id');

  Future<List<Map<String, dynamic>>> month({
    required int year,
    required int month,
    String? userId,
    bool includeNotableDays = true,
  }) {
    return _client.getList<Map<String, dynamic>>(
      '$_base/month',
      query: {
        'year': year,
        'month': month,
        'userId': ?userId,
        'includeNotableDays': includeNotableDays,
      },
      parseItem: (json) => json,
    );
  }

  Future<Map<String, dynamic>> merged({
    required int year,
    required int month,
    String? userId,
  }) {
    return _client.getObject(
      '$_base/merged',
      query: {'year': year, 'month': month, 'userId': ?userId},
    );
  }

  Future<ApiPage<Map<String, dynamic>>> countdown({
    String? userId,
    int take = 20,
    int offset = 0,
    bool includeNotableDays = true,
    String? tag,
  }) {
    return _client.getPage<Map<String, dynamic>>(
      '$_base/countdown',
      query: {
        'userId': ?userId,
        'take': take,
        'offset': offset,
        'includeNotableDays': includeNotableDays,
        'tag': ?tag,
      },
      parseItem: (json) => json,
    );
  }

  Future<List<Map<String, dynamic>>> search({
    String? query,
    String? accountId,
    List<String>? tags,
    DateTime? startTime,
    DateTime? endTime,
    int? notableDayTag,
    int offset = 0,
    int take = 50,
  }) {
    return _client.getList<Map<String, dynamic>>(
      '$_base/search',
      query: {
        'query': ?query,
        'accountId': ?accountId,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        'startTime': ?startTime?.toUtc().toIso8601String(),
        'endTime': ?endTime?.toUtc().toIso8601String(),
        'notableDayTag': ?notableDayTag,
        'offset': offset,
        'take': take,
      },
      parseItem: (json) => json,
    );
  }

  Future<List<String>> tags() async {
    final data = await _client.get('$_base/tags');
    return (data as List? ?? const []).map((e) => '$e').toList();
  }

  Future<List<String>> subscriptions() async {
    final data = await _client.get('$_base/subscriptions');
    return (data as List? ?? const []).map((e) => '$e').toList();
  }

  Future<void> subscribe(String accountId) =>
      _client.post('$_base/subscriptions/$accountId');

  Future<void> unsubscribe(String accountId) =>
      _client.delete('$_base/subscriptions/$accountId');
}
