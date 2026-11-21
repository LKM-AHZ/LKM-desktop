import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:island/chat/tinode/tinode_client.dart';
import 'package:island/chat/tinode/tinode_provider.dart';

/// A minimal stand-in for the Tinode websocket server. Responses deliberately
/// carry no `id` field: Tinode 0.25.3 does not echo it back (verified live),
/// which is why the client matches requests in FIFO order.
class _FakeTinode {
  _FakeTinode(this._onFrame);

  final void Function(WebSocket ws, Map<String, dynamic> frame) _onFrame;
  late final HttpServer _server;
  final frames = <Map<String, dynamic>>[];

  String get url => 'ws://127.0.0.1:${_server.port}/v0/channels';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        frames.add(frame);
        _onFrame(ws, frame);
      });
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void _reply(WebSocket ws, Map<String, dynamic> ctrl) {
  ws.add(jsonEncode({'ctrl': ctrl}));
}

void main() {
  test(
    'logs in, creates a topic, sends, reads history and lists subs',
    () async {
      final server = _FakeTinode((ws, frame) {
        if (frame['hi'] != null) {
          _reply(ws, {'code': 201, 'text': 'created', 'params': {}});
          return;
        }
        final login = frame['login'];
        if (login is Map) {
          expect(
            utf8.decode(base64Decode('${login['secret']}')),
            'lkm:token-1',
          );
          _reply(ws, {
            'code': 200,
            'text': 'ok',
            'params': {'user': 'usrABC'},
          });
          return;
        }
        final sub = frame['sub'];
        if (sub is Map) {
          final topic = '${sub['topic']}';
          _reply(ws, {
            'topic': topic == 'new' ? 'grpXYZ' : topic,
            'code': 200,
            'text': 'ok',
            'params': {},
          });
          return;
        }
        final pub = frame['pub'];
        if (pub is Map) {
          final topic = '${pub['topic']}';
          ws.add(
            jsonEncode({
              'data': {
                'topic': topic,
                'from': 'usrABC',
                'seq': 1,
                'ts': '2026-11-17T00:00:00Z',
                'content': pub['content'],
              },
            }),
          );
          _reply(ws, {'topic': topic, 'code': 200, 'text': 'ok', 'params': {}});
          return;
        }
        final get = frame['get'];
        if (get is Map) {
          if (get['what'] == 'data') {
            ws.add(
              jsonEncode({
                'data': {
                  'topic': get['topic'],
                  'from': 'usrABC',
                  'seq': 1,
                  'ts': '2026-11-17T00:00:00Z',
                  'content': '{"txt":"hi"}',
                },
              }),
            );
            _reply(ws, {
              'topic': get['topic'],
              'code': 208,
              'text': 'delivered',
              'params': {},
            });
          } else {
            ws.add(
              jsonEncode({
                'meta': {
                  'topic': 'me',
                  'sub': [
                    {
                      'topic': 'grpXYZ',
                      'public': {'fn': 'Room'},
                    },
                  ],
                },
              }),
            );
          }
        }
      });
      await server.start();
      addTearDown(server.stop);

      final client = TinodeClient(
        endpoint: Uri.parse(server.url),
        apiKey: 'test-key',
      );
      addTearDown(client.close);

      expect(await client.connect('token-1'), 'usrABC');

      final created = await client.subscribe('new', create: true);
      expect(created.topic, 'grpXYZ');

      final sent = await client.send('grpXYZ', {'txt': 'hello'});
      expect(sent.seq, 1);
      expect(sent.content['txt'], 'hello');

      final history = await client.history('grpXYZ');
      expect(history.single.content['txt'], 'hi');

      final subs = await client.subscriptions();
      expect(subs.single.id, 'grpXYZ');
      expect(subs.single.name, 'Room');
      expect(subs.single.isGroup, isTrue);
    },
  );

  test('answers server heartbeats with the same timestamp', () async {
    final server = _FakeTinode((ws, frame) {
      if (frame['hi'] != null) {
        _reply(ws, {'code': 201, 'text': 'created', 'params': {}});
        ws.add(
          jsonEncode({
            'ctrl': {'ts': '2026-11-17T00:00:01Z'},
          }),
        );
      } else if (frame['login'] != null) {
        _reply(ws, {
          'code': 200,
          'text': 'ok',
          'params': {'user': 'usrABC'},
        });
      }
    });
    await server.start();
    addTearDown(server.stop);

    final client = TinodeClient(
      endpoint: Uri.parse(server.url),
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    await client.connect('token-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      server.frames.any(
        (frame) =>
            frame['ctrl'] is Map &&
            (frame['ctrl'] as Map)['ts'] == '2026-11-17T00:00:01Z',
      ),
      isTrue,
    );
  });

  test('times out when the server never answers', () async {
    final server = _FakeTinode((ws, frame) {
      if (frame['hi'] != null) _reply(ws, {'code': 201, 'params': {}});
    });
    await server.start();
    addTearDown(server.stop);

    final client = TinodeClient(
      endpoint: Uri.parse(server.url),
      apiKey: 'test-key',
      timeout: const Duration(milliseconds: 300),
    );
    addTearDown(client.close);

    await expectLater(
      client.connect('token-1'),
      throwsA(isA<TinodeException>()),
    );
  });

  test(
    'history preserves live messages outside its topic and seq window',
    () async {
      final server = _FakeTinode((ws, frame) {
        if (_replyAuth(ws, frame)) return;
        if (frame['get'] != null) {
          for (final entry in [('other', 1), ('grp', 20), ('grp', 9)]) {
            ws.add(
              jsonEncode({
                'data': {
                  'topic': entry.$1,
                  'seq': entry.$2,
                  'from': 'usrPeer',
                  'content': {'txt': '${entry.$2}'},
                },
              }),
            );
          }
          _reply(ws, {'code': 208, 'topic': 'grp'});
        }
      });
      await server.start();
      addTearDown(server.stop);
      final client = TinodeClient(
        endpoint: Uri.parse(server.url),
        apiKey: 'key',
      );
      addTearDown(client.close);
      await client.connect('token');
      final events = <TinodeEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final page = await client.history('grp', before: 10);
      await Future<void>.delayed(Duration.zero);
      expect(page.map((m) => m.seq), [9]);
      expect(events.map((e) => e.payload['topic']), ['other', 'grp']);
      expect(events.last.payload['seq'], 20);
    },
  );

  test(
    'a peer message during publish is not used as the send result',
    () async {
      final server = _FakeTinode((ws, frame) {
        if (_replyAuth(ws, frame)) return;
        final pub = frame['pub'];
        if (pub is Map) {
          for (final from in ['usrABC', 'usrPeer']) {
            ws.add(
              jsonEncode({
                'data': {
                  'topic': pub['topic'],
                  'seq': from == 'usrABC' ? 1 : 2,
                  'from': from,
                  'content': pub['content'],
                },
              }),
            );
          }
          _reply(ws, {'code': 200, 'topic': pub['topic']});
        }
      });
      await server.start();
      addTearDown(server.stop);
      final client = TinodeClient(
        endpoint: Uri.parse(server.url),
        apiKey: 'key',
      );
      addTearDown(client.close);
      await client.connect('token');
      final received = client.events.firstWhere(
        (event) => event.kind == 'data',
      );
      final sent = await client.send('grp', {'txt': 'hello'});
      expect(sent.from, 'usrABC');
      expect((await received).payload['from'], 'usrPeer');
    },
  );

  test(
    'timeout closes FIFO transport before the next queued request',
    () async {
      final server = _FakeTinode((ws, frame) {
        _replyAuth(ws, frame);
      });
      await server.start();
      addTearDown(server.stop);
      final client = TinodeClient(
        endpoint: Uri.parse(server.url),
        apiKey: 'key',
        timeout: const Duration(milliseconds: 100),
      );
      addTearDown(client.close);
      await client.connect('token');
      final first = expectLater(
        client.history('first'),
        throwsA(isA<TinodeException>()),
      );
      final second = expectLater(
        client.history('second'),
        throwsA(isA<TinodeException>()),
      );
      await Future.wait([first, second]);
      expect(client.isConnected, isFalse);
      expect(server.frames.where((f) => f['get'] != null).length, 1);
    },
  );

  test('closing the client fails in-flight requests immediately', () async {
    final requested = Completer<void>();
    final server = _FakeTinode((ws, frame) {
      if (_replyAuth(ws, frame)) return;
      if (frame['get'] != null) requested.complete();
    });
    await server.start();
    addTearDown(server.stop);
    final client = TinodeClient(endpoint: Uri.parse(server.url), apiKey: 'key');
    await client.connect('token');
    final failure = expectLater(
      client.history('grp'),
      throwsA(isA<TinodeException>()),
    );
    await requested.future;
    await client.close();
    await failure.timeout(const Duration(milliseconds: 500));
  });

  test('tinodeEndpoint rewrites the LKM base URL to the chat websocket', () {
    expect(
      tinodeEndpoint(Uri.parse('https://community.example'))?.toString(),
      'wss://community.example/v0/channels',
    );
    expect(
      tinodeEndpoint(Uri.parse('http://127.0.0.1:8000'))?.toString(),
      'ws://127.0.0.1:8000/v0/channels',
    );
  });
}

bool _replyAuth(WebSocket ws, Map<String, dynamic> frame) {
  if (frame['hi'] != null) {
    _reply(ws, {'code': 201, 'params': {}});
    return true;
  }
  if (frame['login'] != null) {
    _reply(ws, {
      'code': 200,
      'params': {'user': 'usrABC'},
    });
    return true;
  }
  return false;
}
