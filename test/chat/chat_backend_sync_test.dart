import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/chat/backend/chat_api.dart';
import 'package:island/chat/backend/chat_backend.dart';
import 'package:island/chat/tinode/tinode_client.dart';
import 'package:island/chat/tinode/tinode_provider.dart';

class _HistoryClient extends TinodeClient {
  _HistoryClient() : super(endpoint: Uri(), apiKey: '') {
    userId = 'usrMe';
  }
  final boundaries = <int?>[];
  final List<TinodeMessage> messages = [
    for (var seq = 1; seq <= 250; seq++)
      TinodeMessage(
        topic: 'grp',
        from: 'usrPeer',
        seq: seq,
        ts: DateTime.fromMillisecondsSinceEpoch(seq * 1000, isUtc: true),
        content: {'txt': 'message $seq'},
      ),
  ];
  Completer<void>? pause;
  int roomRequests = 0;
  bool ignoreBefore = false;

  @override
  Future<Map<String, dynamic>?> meta(String topic, String what) async {
    roomRequests++;
    return {
      'sub': [
        {'topic': 'grp', 'seq': 250},
      ],
    };
  }

  @override
  Future<List<TinodeMessage>> history(
    String topic, {
    int limit = 50,
    int? before,
    int? since,
  }) async {
    boundaries.add(before);
    await pause?.future;
    final available = messages
        .where(
          (m) =>
              (ignoreBefore || before == null || m.seq < before) &&
              (since == null || m.seq >= since),
        )
        .toList();
    return available.reversed.take(limit).toList().reversed.toList();
  }
}

void main() {
  late _HistoryClient client;
  late ProviderContainer container;
  setUp(() async {
    client = _HistoryClient();
    container = ProviderContainer(
      overrides: [tinodeClientProvider.overrideWith((ref) async => client)],
    );
    await container.read(tinodeClientProvider.future);
  });
  tearDown(() => container.dispose());

  test('live arrivals advance read receipts without a rooms refresh', () {
    final backend = container.read(chatBackendProvider);
    backend.messageJsonFor(client.messages.last);
    expect(backend.unreadSeqFor('grp'), 250);
    backend.messageJsonFor(client.messages.first);
    expect(backend.unreadSeqFor('grp'), 250);
  });

  test(
    'catch-up fetches beyond 100 rows and includes the timestamp boundary',
    () async {
      final backend = container.read(chatBackendProvider);
      final messages = await backend.messagesAfterTimestamp('grp', 50000);
      expect(messages, hasLength(201));
      expect(messages.map((m) => m.id).toSet(), hasLength(201));
      expect(messages.any((m) => m.id == 'grp:50'), isTrue);
      expect(client.boundaries, [null, 151, 51]);
    },
  );

  test(
    'sequence paging handles deleted rows without skipping older messages',
    () async {
      client.messages.removeWhere((m) => m.seq >= 180 && m.seq <= 230);
      final result = await container
          .read(chatBackendProvider)
          .messagesAfterTimestamp('grp', 50000);
      expect(result, hasLength(150));
      expect(result.any((m) => m.id == 'grp:50'), isTrue);
    },
  );

  test(
    'a stalled history cursor fails instead of accepting incomplete sync',
    () async {
      client.ignoreBefore = true;
      await expectLater(
        container.read(chatBackendProvider).messagesAfterTimestamp('grp', 0),
        throwsStateError,
      );
      expect(client.boundaries, [null, 151]);
    },
  );

  test(
    'sync response uses its start boundary, rather than completion time',
    () async {
      final apiProvider = Provider<Dio>(
        (ref) => Dio()..interceptors.add(ChatApiInterceptor(ref)),
      );
      client.pause = Completer<void>();
      final before = DateTime.now().millisecondsSinceEpoch;
      final sync = container
          .read(apiProvider)
          .post('/messager/chat/sync', data: {'last_sync_timestamp': 50000});
      while (client.boundaries.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final release = DateTime.now().millisecondsSinceEpoch;
      client.pause!.complete();
      final response = await sync;
      final body = response.data as Map<String, dynamic>;
      expect(body['messages'], hasLength(201));
      expect(body['current_timestamp'], greaterThanOrEqualTo(before));
      expect(body['current_timestamp'], lessThan(release));
      expect(client.roomRequests, 1);
    },
  );
}
