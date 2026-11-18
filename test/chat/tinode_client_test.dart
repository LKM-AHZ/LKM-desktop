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
