import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/chat/backend/chat_models.dart';
import 'package:island/chat/backend/chat_realtime.dart';
import 'package:island/chat/data/message_cache.dart';
import 'package:island/chat/data/message_repository.dart';
import 'package:island/chat/send/message_send_session.dart';
import 'package:island/chat/send/message_sender.dart';
import 'package:island/data/message.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

class _ConnectedSocket extends SolarWebSocketService {
  _ConnectedSocket() : super(uri: () => Uri(), token: () async => null);
  var sends = 0;
  @override
  bool get isConnected => true;
  @override
  bool sendMessage(String message) {
    sends++;
    return true;
  }
}

class _Repository extends MessageRepository {
  _Repository(Ref ref, this.member) : super(ref, 'grp', MessageCache());
  final SnChatMember member;
  final started = Completer<void>();
  Completer<void>? delivery;
  bool fail = false;
  int sends = 0;
  String? editedId;
  Map<String, dynamic>? lastPayload;

  SnChatMessage response(Map<String, dynamic> payload) => SnChatMessage(
    id: 'grp:1',
    chatRoomId: 'grp',
    senderId: member.id,
    sender: member,
    content: payload['content'] as String?,
    clientMessageId: payload['client_message_id'] as String?,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<SnChatMessage> sendMessage(
    Map<String, dynamic> payload, {
    Options? options,
  }) async {
    sends++;
    lastPayload = payload;
    if (!started.isCompleted) started.complete();
    if (fail) throw StateError('offline');
    await delivery?.future;
    return response(payload);
  }

  @override
  Future<SnChatMessage> editMessage(
    String messageId,
    Map<String, dynamic> payload, {
    Options? options,
  }) async {
    editedId = messageId;
    return sendMessage(payload);
  }

  @override
  Future<void> saveMessage(LocalChatMessage message) async {}
  @override
  Future<void> updateStatus(String messageId, MessageStatus status) async {}
  @override
  Future<void> deleteMessage(String messageId) async {}
}

void main() {
  final member = SnChatMember.fromJson(
    chatMemberJson({
      'user': 'usrMe',
      'public': {'fn': 'Me'},
    }, topic: 'grp'),
  );
  late ProviderContainer container;
  late _Repository repository;
  late MessageSender sender;
  late _ConnectedSocket socket;
  setUp(() {
    socket = _ConnectedSocket();
    final senderProvider = Provider<MessageSender>((ref) {
      repository = _Repository(ref, member);
      return MessageSender(ref, 'grp', repository, PendingMessageCache());
    });
    container = ProviderContainer(
      overrides: [chatRealtimeProvider.overrideWithValue(socket)],
    );
    sender = container.read(senderProvider);
  });
  tearDown(() => container.dispose());

  test(
    'connected sends await one transport request without a timed replay',
    () async {
      repository.delivery = Completer<void>();
      final session = sender.sendTextMessage(
        MessageSendRequest(
          roomId: 'grp',
          content: 'hello',
          attachments: const [],
          sender: member,
        ),
      );
      await session.pending;
      await repository.started.future.timeout(
        const Duration(milliseconds: 500),
      );
      expect(socket.sends, 0);
      expect(repository.sends, 1);
      repository.delivery!.complete();
      expect((await session.result).success, isTrue);
      expect(repository.sends, 1);
    },
  );

  test('retry keeps the edit target, embeds and client message id', () async {
    final request = MessageSendRequest(
      roomId: 'grp',
      content: 'edited',
      attachments: const [],
      sender: member,
      editingTo: repository
          .response({'content': 'before'})
          .copyWith(id: 'original'),
      embeds: const [
        {'type': 'survey', 'id': 'poll'},
      ],
    );
    repository.fail = true;
    final first = sender.sendTextMessage(request);
    final pending = await first.pending;
    expect((await first.result).success, isFalse);
    repository.fail = false;
    final retry = sender.retryMessage(
      pending.id,
      sender: member,
      request: request,
    );
    await retry.pending;
    final result = await retry.result;
    expect(result.success, isTrue);
    expect(result.message!.id, 'original');
    expect(result.eventMessage, isNotNull);
    expect(repository.editedId, 'original');
    expect(repository.lastPayload!['embeds'], request.embeds);
    expect(
      repository.lastPayload!['client_message_id'],
      pending.clientMessageId,
    );
  });
}
