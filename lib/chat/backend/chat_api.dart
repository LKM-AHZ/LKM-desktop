import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/chat/backend/chat_backend.dart';
import 'package:island/chat/tinode/tinode_provider.dart';
import 'package:island/core/network.dart';

/// A Dio client whose only job is the old `/messager/chat/*` REST surface,
/// answered from Tinode by [ChatBackend].
///
/// The chat module was written against that REST contract; keeping the same
/// paths and payload shapes here means the UI, sync services and local
/// database stay untouched while the transport changes underneath.
final chatApiProvider = Provider<Dio>((ref) {
  // Reuse the app client so URL overrides, logging and tests keep working;
  // only `/messager/chat` is answered here.
  final dio = ref.watch(apiClientProvider);
  if (dio.interceptors.whereType<ChatApiInterceptor>().isEmpty) {
    dio.interceptors.add(ChatApiInterceptor(ref));
  }
  return dio;
});

class _ApiResult {
  const _ApiResult(this.data, {this.headers});

  final dynamic data;
  final Map<String, Object?>? headers;
}

class ChatApiInterceptor extends Interceptor {
  ChatApiInterceptor(this._ref);

  final Ref _ref;

  ChatBackend get _backend => _ref.read(chatBackendProvider);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;
    if (!path.startsWith('/messager/chat')) {
      return handler.next(options);
    }
    // Signed-out (or tests without a chat transport): keep the original
    // network path so the old fixtures still answer.
    if (_ref.read(tinodeClientProvider).value == null) {
      return handler.next(options);
    }
    try {
      final result = await _handle(options);
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: result.data,
          headers: result.headers == null
              ? null
              : Headers.fromMap({
                  for (final entry in result.headers!.entries)
                    entry.key: ['${entry.value}'],
                }),
        ),
      );
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {'message': '$error'},
          ),
        ),
      );
    }
  }

  Future<_ApiResult> _handle(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final path = options.path;
    final body = switch (options.data) {
      final Map value => Map<String, dynamic>.from(value),
      _ => const <String, dynamic>{},
    };

    if (path == '/messager/chat/summary' && method == 'GET') {
      return _ApiResult(await _backend.summaries());
    }
    if (path == '/messager/chat/unread' && method == 'GET') {
      await _backend.rooms();
      var total = 0;
      for (final room in await _backend.rooms()) {
        total += _backend.unreadOf('${room['id']}');
      }
      return _ApiResult(total);
    }
    if (path == '/messager/chat/read-all' && method == 'POST') {
      await _backend.rooms();
      _backend.markAllRead();
      return const _ApiResult(null);
    }
    if (path == '/messager/chat/invites' && method == 'GET') {
      return const _ApiResult([]);
    }
    if (path == '/messager/chat/rooms/sync' && method == 'POST') {
      await _backend.rooms();
      final rooms = await _backend.rooms();
      final summaries = await _backend.summaries();
      return _ApiResult({
        'changes': [
          for (final room in rooms) {'room_id': room['id'], 'room': room},
        ],
        'summaries': [
          for (final entry in summaries.entries)
            {'room_id': entry.key, ...entry.value},
        ],
        'groups': const [],
        'current_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    if (path == '/messager/chat/sync' && method == 'POST') {
      return _ApiResult(await _globalSync(body));
    }
    if (path == '/messager/chat' && method == 'GET') {
      return _ApiResult(await _backend.rooms());
    }
    if (path == '/messager/chat' && method == 'POST') {
      return _ApiResult(
        await _backend.createRoom(name: '${body['name'] ?? ''}'),
      );
    }
    if (path == '/messager/chat/direct' && method == 'POST') {
      final uid = '${body['related_user_id'] ?? body['account_id'] ?? ''}';
      return _ApiResult(await _backend.directRoom(uid));
    }
    if (path == '/messager/chat/messages/search' && method == 'GET') {
      // Cross-room full-text search needs a server index Tinode does not
      // expose; per-room search keeps working from the local database.
      return const _ApiResult([]);
    }
    if (path == '/messager/chat/groups') {
      // Room grouping was server-side in the Solar backend; the UI keeps its
      // local list, so these calls are accepted as no-ops.
      return const _ApiResult([]);
    }
    if (path.startsWith('/messager/chat/groups/')) {
      return const _ApiResult([]);
    }
    final inviteMatch = RegExp(
      r'^/messager/chat/invites/([^/]+)/(accept|decline)$',
    ).firstMatch(path);
    if (inviteMatch != null && method == 'POST') {
      final topic = Uri.decodeComponent(inviteMatch.group(1)!);
      if (inviteMatch.group(2) == 'accept') {
        await _backend.subscribe(topic);
      } else {
        await _backend.unsubscribe(topic);
      }
      return const _ApiResult(null);
    }
    if (path.startsWith('/messager/chat/realtime/')) {
      throw UnsupportedError('通话功能暂不可用');
    }
    if (path.startsWith('/messager/chat/accounts/me/status')) {
      return const _ApiResult({
        'online_count': 0,
        'online_user_names': [],
        'online_accounts': [],
      });
    }

    final match = RegExp(
      r'^/messager/chat/([^/]+)(?:/(.*))?$',
    ).firstMatch(path);
    if (match == null) throw UnsupportedError('未知聊天接口 $path');
    final topic = Uri.decodeComponent(match.group(1)!);
    final rest = match.group(2) ?? '';

    if (rest.isEmpty) {
      switch (method) {
        case 'GET':
          final room = await _backend.room(topic);
          if (room == null) throw StateError('聊天室不存在');
          return _ApiResult(room);
        case 'PATCH':
        case 'PUT':
          await _backend.updateRoom(
            topic,
            name: body['name']?.toString(),
            description: body['description']?.toString(),
          );
          return _ApiResult((await _backend.room(topic)) ?? const {});
        case 'DELETE':
          await _backend.unsubscribe(topic);
          return const _ApiResult(null);
      }
    }

    if (rest == 'members' && method == 'GET') {
      return _ApiResult(await _backend.members(topic));
    }
    if (rest == 'members' && method == 'POST') {
      await _backend.subscribe(topic);
      return _ApiResult(_backend.selfMember(topic));
    }
    if (rest == 'members/me' && method == 'GET') {
      return _ApiResult(_backend.selfMember(topic));
    }
    if (rest == 'members/me' && method == 'POST') {
      await _backend.subscribe(topic);
      return _ApiResult(_backend.selfMember(topic));
    }
    if (rest == 'members/me' && method == 'DELETE') {
      await _backend.unsubscribe(topic);
      return const _ApiResult(null);
    }
    if (rest == 'members/online' && method == 'GET') {
      return const _ApiResult({
        'online_count': 0,
        'online_user_names': [],
        'online_accounts': [],
      });
    }
    if (rest == 'autocomplete') return const _ApiResult([]);
    if (rest == 'members/me/notify' || rest == 'members/me/profile') {
      return _ApiResult(_backend.selfMember(topic));
    }
    if (rest == 'mls/enable') {
      throw UnsupportedError('端到端加密暂不可用');
    }
    final memberMatch = RegExp(
      r'^members/([^/]+)(?:/timeout)?$',
    ).firstMatch(rest);
    if (memberMatch != null && method == 'DELETE') {
      await _backend.removeMember(topic, memberMatch.group(1)!);
      return const _ApiResult(null);
    }
    if (rest.endsWith('/timeout')) return const _ApiResult(null);
    if (rest.endsWith('/group')) return const _ApiResult(null);

    if (rest == 'messages') {
      if (method == 'GET') {
        final offset =
            int.tryParse('${options.queryParameters['offset'] ?? 0}') ?? 0;
        final take =
            int.tryParse('${options.queryParameters['take'] ?? 20}') ?? 20;
        final page = await _backend.fetchMessages(
          topic,
          offset: offset,
          take: take,
        );
        return _ApiResult(
          [
            for (final message in page.messages)
              {...message.toJson(), 'room_sequence': _seqOf(message.id)},
          ],
          headers: {'x-total': page.totalCount},
        );
      }
      if (method == 'POST') {
        final sent = await _backend.send(topic, body);
        return _ApiResult(sent.toJson());
      }
    }

    if (rest == 'messages/voice' || rest == 'messages/placeholder') {
      throw UnsupportedError('语音与占位消息暂不可用');
    }

    final messageMatch = RegExp(
      r'^messages/([^/]+)(?:/(.*))?$',
    ).firstMatch(rest);
    if (messageMatch != null) {
      final messageId = Uri.decodeComponent(messageMatch.group(1)!);
      final sub = messageMatch.group(2) ?? '';
      if (sub.isEmpty) {
        switch (method) {
          case 'GET':
            final message = await _backend.fetchMessage(topic, messageId);
            if (message == null) throw StateError('消息不存在');
            return _ApiResult(message.toJson());
          case 'PATCH':
          case 'PUT':
            final updated = await _backend.sendEvent(
              topic,
              type: 'messages.update',
              content: '${body['content'] ?? ''}',
              meta: {
                'message_id': messageId,
                ...?(body['meta'] as Map?)?.cast<String, dynamic>(),
              },
            );
            return _ApiResult(updated.toJson());
          case 'DELETE':
            final deleted = await _backend.sendEvent(
              topic,
              type: 'messages.delete',
              meta: {'message_id': messageId},
            );
            await _backend.deleteMessage(topic, messageId);
            return _ApiResult(deleted.toJson());
        }
      }
      if (sub == 'reactions' && method == 'POST') {
        final attitude = body['attitude'];
        final symbol = '${body['symbol'] ?? ''}';
        final added = attitude is num ? attitude > 0 : true;
        final event = await _backend.sendEvent(
          topic,
          type: added ? 'messages.reaction.added' : 'messages.reaction.removed',
          meta: {
            'message_id': messageId,
            'symbol': symbol,
            'attitude': attitude,
          },
        );
        return _ApiResult(event.toJson());
      }
      if (sub == 'thread' && method == 'GET') {
        final page = await _backend.fetchMessages(topic, offset: 0, take: 200);
        return _ApiResult([
          for (final message in page.messages)
            if (message.threadId == messageId) message.toJson(),
        ]);
      }
    }

    if (rest == 'pins') {
      if (method == 'GET') return const _ApiResult([]);
      if (method == 'POST') {
        final messageId = '${body['message_id'] ?? ''}';
        await _backend.sendEvent(
          topic,
          type: 'messages.pinned',
          meta: {'message_id': messageId, ...body},
        );
        return const _ApiResult(null);
      }
    }
    if (rest.startsWith('pins/') && method == 'DELETE') {
      await _backend.sendEvent(
        topic,
        type: 'messages.unpinned',
        meta: {'message_id': rest.substring('pins/'.length)},
      );
      return const _ApiResult(null);
    }

    if (rest == 'sync' && method == 'POST') {
      return _ApiResult(await _roomSync(topic, body));
    }

    throw UnsupportedError('未知聊天接口 $path');
  }

  static int? _seqOf(String messageId) {
    final index = messageId.lastIndexOf(':');
    return index < 0 ? null : int.tryParse(messageId.substring(index + 1));
  }

  Future<Map<String, dynamic>> _roomSync(
    String topic,
    Map<String, dynamic> body,
  ) async {
    final sequences = <int>[
      for (final value in (body['missing_sequences'] as List? ?? const []))
        if (int.tryParse('$value') case final int seq) seq,
    ];
    for (final range
        in (body['missing_sequence_ranges'] as List? ?? const [])) {
      if (range is! Map) continue;
      final start = int.tryParse('${range['start_sequence']}');
      final end = int.tryParse('${range['end_sequence']}');
      if (start == null || end == null) continue;
      for (var seq = start; seq <= end; seq++) {
        sequences.add(seq);
      }
    }
    final messages = <Map<String, dynamic>>[];
    for (final seq in sequences) {
      final found = await _backend.fetchMessage(topic, '$topic:$seq');
      if (found == null) continue;
      messages.add({...found.toJson(), 'room_sequence': seq});
    }
    return {
      'messages': messages,
      'current_timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// The global sync the room-list refresh uses: every topic's messages newer
  /// than the cursor, newest page only.
  Future<Map<String, dynamic>> _globalSync(Map<String, dynamic> body) async {
    final cursor = int.tryParse('${body['last_sync_timestamp'] ?? 0}') ?? 0;
    final rooms = await _backend.rooms();
    final messages = <Map<String, dynamic>>[];
    for (final room in rooms) {
      final topic = '${room['id']}';
      final page = await _backend.fetchMessages(topic, offset: 0, take: 100);
      for (final message in page.messages) {
        if (cursor > 0 && message.createdAt.millisecondsSinceEpoch <= cursor) {
          continue;
        }
        messages.add(message.toJson());
      }
    }
    messages.sort((a, b) {
      final left = DateTime.tryParse('${a['created_at']}');
      final right = DateTime.tryParse('${b['created_at']}');
      return (right ?? DateTime(0)).compareTo(left ?? DateTime(0));
    });
    return {
      'messages': messages,
      'current_timestamp': DateTime.now().millisecondsSinceEpoch,
      'total_count': messages.length,
    };
  }
}
