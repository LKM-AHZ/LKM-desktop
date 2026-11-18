import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A control frame from Tinode (`{ctrl: …}`).
class TinodeCtrl {
  const TinodeCtrl({
    required this.code,
    required this.text,
    this.topic,
    this.params = const {},
  });

  final int code;
  final String text;
  final String? topic;
  final Map<String, dynamic> params;

  bool get ok => code < 300 && code != 204;

  factory TinodeCtrl.fromJson(Map<String, dynamic> json) => TinodeCtrl(
    code: switch (json['code']) {
      final int code => code,
      final num code => code.toInt(),
      _ => 500,
    },
    text: '${json['text'] ?? ''}',
    topic: json['topic'] as String?,
    params: switch (json['params']) {
      final Map params => Map<String, dynamic>.from(params),
      _ => const {},
    },
  );
}

/// A `{data: …}` frame — one chat message.
class TinodeMessage {
  const TinodeMessage({
    required this.topic,
    required this.from,
    required this.seq,
    required this.ts,
    required this.content,
    this.id,
  });

  final String topic;
  final String from;
  final int seq;
  final DateTime? ts;
  final Map<String, dynamic> content;

  /// Server-generated message id (`mid`), when the server supplies one.
  final String? id;

  factory TinodeMessage.fromJson(String topic, Map<String, dynamic> json) {
    final raw = json['content'];
    Map<String, dynamic> content;
    if (raw is Map) {
      content = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        content = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : {'txt': raw};
      } catch (_) {
        content = {'txt': raw};
      }
    } else {
      content = const {};
    }
    return TinodeMessage(
      topic: topic,
      from: '${json['from'] ?? ''}',
      seq: switch (json['seq']) {
        final int seq => seq,
        final num seq => seq.toInt(),
        _ => 0,
      },
      ts: DateTime.tryParse('${json['ts'] ?? ''}'),
      content: content,
      id: json['mid'] as String?,
    );
  }
}

/// A topic the user is subscribed to (from `get {what: "sub"}` on `me`).
class TinodeTopic {
  const TinodeTopic({
    required this.id,
    required this.name,
    required this.owner,
    required this.isChannel,
  });

  final String id;
  final String? name;
  final String? owner;
  final bool isChannel;

  /// `grp…` topics are groups, `p2p…` are direct chats, `chn…` are channels.
  bool get isDirect => id.startsWith('p2p');
  bool get isGroup => id.startsWith('grp');

  factory TinodeTopic.fromJson(Map<String, dynamic> json) {
    final id = '${json['topic'] ?? ''}';
    // `public.fn` is the human-readable name set at creation time.
    final public = json['public'];
    final fn = public is Map ? public['fn'] as String? : null;
    return TinodeTopic(
      id: id,
      name: fn,
      owner: json['owner'] as String?,
      isChannel: id.startsWith('chn'),
    );
  }
}

class TinodeException implements Exception {
  const TinodeException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => 'TinodeException($code): $message';
}

/// An unsolicited server frame (new message, subscription update, presence).
class TinodeEvent {
  const TinodeEvent(this.kind, this.payload);

  /// `data`, `meta`, `pres`, `recv` or `read`.
  final String kind;
  final Map<String, dynamic> payload;
}

class _Pending {
  _Pending({required this.collectData, required this.awaitMeta});

  final bool collectData;
  final bool awaitMeta;
  final data = <TinodeMessage>[];
  final meta = <Map<String, dynamic>>[];
  final completer = Completer<_Result>();
}

class _Result {
  _Result(this.ctrl);

  final TinodeCtrl? ctrl;
  final data = <TinodeMessage>[];
  final meta = <Map<String, dynamic>>[];
}

/// Client for the Tinode websocket protocol (`/v0/channels`).
///
/// Tinode answers requests strictly in order but (v0.25.3, verified against a
/// live server) does not echo the client frame `id` back, so requests are
/// serialized and matched FIFO instead of by id.
class TinodeClient {
  TinodeClient({
    required Uri endpoint,
    required String apiKey,
    this.userAgent = 'lkm-desktop/1.0',
    Duration? timeout,
  }) : _endpoint = endpoint,
       _apiKey = apiKey,
       _timeout = timeout ?? const Duration(seconds: 10);

  final Uri _endpoint;
  final String _apiKey;
  final String userAgent;
  final Duration _timeout;

  final _events = StreamController<TinodeEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  _Pending? _pending;
  Future<void> _queue = Future.value();
  int _id = 0;
  String? userId;

  Stream<TinodeEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  /// Connects, greets the server and logs in with an LKM access token.
  ///
  /// Returns the Tinode user id (`usr…`). The REST bridge on the LKM auth
  /// service exchanges the token for a Tinode account on first login.
  Future<String> connect(String accessToken) async {
    final uri = _endpoint.replace(
      queryParameters: {..._endpoint.queryParameters, 'apikey': _apiKey},
    );
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (Object error, StackTrace _) => _onClosed(error),
      cancelOnError: true,
    );

    final hi = await _call({
      'hi': {'ver': '0.25', 'ua': userAgent},
    });
    if (hi.ctrl == null) {
      throw const TinodeException('no greeting from server');
    }
    final login = await _call({
      'login': {
        'scheme': 'basic',
        'secret': base64Encode(utf8.encode('lkm:$accessToken')),
      },
    });
    final ctrl = login.ctrl;
    if (ctrl == null || !ctrl.ok) {
      throw TinodeException(
        'login failed: ${ctrl?.text ?? 'no response'}',
        code: ctrl?.code,
      );
    }
    userId = '${ctrl.params['user'] ?? ''}';
    if (userId!.isEmpty) {
      throw const TinodeException('login response carried no user');
    }
    return userId!;
  }

  /// Subscribes to (or creates) a topic.
  ///
  /// `create: true` asks the server to mint a group from `new`; the resulting
  /// `grp…`/`chn…` topic id is in `ctrl.topic`.
  Future<TinodeCtrl> subscribe(
    String topic, {
    bool create = false,
    Map<String, dynamic>? public,
    Map<String, dynamic>? private,
    int historyLimit = 0,
  }) async {
    final body = <String, dynamic>{'topic': create ? 'new' : topic};
    if (historyLimit > 0) {
      body['get'] = {
        'what': 'data',
        'data': {'limit': historyLimit},
      };
    }
    if (public != null || private != null) {
      body['set'] = {'public': ?public, 'private': ?private};
    }
    final result = await _call({'sub': body}, collectData: historyLimit > 0);
    final ctrl = result.ctrl;
    if (ctrl == null || ctrl.code >= 400) {
      throw TinodeException(
        'subscribe failed: ${ctrl?.text ?? 'no response'}',
        code: ctrl?.code,
      );
    }
    return ctrl;
  }

  /// Publishes a message; `content` is the Tinode JSON payload (`txt`, `img`…).
  Future<TinodeMessage> send(String topic, Map<String, dynamic> content) async {
    final result = await _call({
      'pub': {'topic': topic, 'content': jsonEncode(content)},
    }, collectData: true);
    final ctrl = result.ctrl;
    if (ctrl == null || ctrl.code >= 400) {
      throw TinodeException(
        'send failed: ${ctrl?.text ?? 'no response'}',
        code: ctrl?.code,
      );
    }
    // The server echoes the new message as a data frame before the ctrl.
    if (result.data.isNotEmpty) return result.data.last;
    return TinodeMessage(
      topic: topic,
      from: userId ?? '',
      seq: 0,
      ts: DateTime.now(),
      content: content,
    );
  }

  /// Fetches history; `before` is an exclusive upper seq bound.
  Future<List<TinodeMessage>> history(
    String topic, {
    int limit = 50,
    int? before,
  }) async {
    final result = await _call({
      'get': {
        'topic': topic,
        'what': 'data',
        'data': {'limit': limit, 'before': ?before},
      },
    }, collectData: true);
    final ctrl = result.ctrl;
    if (ctrl != null && ctrl.code >= 400) {
      throw TinodeException('history failed: ${ctrl.text}', code: ctrl.code);
    }
    return List.unmodifiable(result.data);
  }

  /// Lists the topics this account is subscribed to.
  Future<List<TinodeTopic>> subscriptions() async {
    final result = await _call({
      'get': {'topic': 'me', 'what': 'sub'},
    }, awaitMeta: true);
    return [
      for (final meta in result.meta)
        for (final sub in switch (meta['sub']) {
          final List subs => subs.whereType<Map>(),
          _ => const <Map>[],
        })
          TinodeTopic.fromJson(Map<String, dynamic>.from(sub)),
    ];
  }

  /// Marks messages up to [seq] as read. Notes are fire-and-forget: the
  /// server does not acknowledge them.
  void markRead(String topic, int seq) {
    _send({
      'note': {'topic': topic, 'what': 'read', 'seq': seq},
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _pending = null;
    await _events.close();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<_Result> _call(
    Map<String, dynamic> body, {
    bool collectData = false,
    bool awaitMeta = false,
  }) {
    final future = _queue.then(
      (_) => _doCall(body, collectData: collectData, awaitMeta: awaitMeta),
    );
    // Keep the chain alive even when this request fails.
    _queue = future.then<void>((_) {}, onError: (_) {});
    return future;
  }

  Future<_Result> _doCall(
    Map<String, dynamic> body, {
    required bool collectData,
    required bool awaitMeta,
  }) {
    final channel = _channel;
    if (channel == null) {
      return Future.error(const TinodeException('not connected'));
    }
    final pending = _Pending(collectData: collectData, awaitMeta: awaitMeta);
    _pending = pending;
    _send({...body, 'id': '${++_id}'});
    return pending.completer.future.timeout(
      _timeout,
      onTimeout: () {
        if (identical(_pending, pending)) _pending = null;
        throw const TinodeException('request timed out');
      },
    );
  }

  void _send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(frame));
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      frame = Map<String, dynamic>.from(decoded);
    } catch (error) {
      debugPrint('Tinode: bad frame: $error');
      return;
    }

    final ctrl = frame['ctrl'];
    if (ctrl is Map) {
      final json = Map<String, dynamic>.from(ctrl);
      if (json['code'] == null) {
        // Server heartbeat: echo the timestamp back.
        _send({
          'ctrl': {'ts': json['ts']},
        });
        return;
      }
      _onCtrl(TinodeCtrl.fromJson(json));
      return;
    }

    final data = frame['data'];
    if (data is Map) {
      final json = Map<String, dynamic>.from(data);
      final topic = '${json['topic'] ?? _lastTopic}';
      final message = TinodeMessage.fromJson(topic, json);
      final pending = _pending;
      if (pending != null && pending.collectData) {
        pending.data.add(message);
      } else {
        _events.add(TinodeEvent('data', json));
      }
      return;
    }

    final meta = frame['meta'];
    if (meta is Map) {
      final json = Map<String, dynamic>.from(meta);
      final pending = _pending;
      if (pending != null && pending.awaitMeta) {
        pending.meta.add(json);
        _finish(pending, null);
      } else {
        _events.add(TinodeEvent('meta', json));
      }
      return;
    }

    for (final kind in const ['pres', 'recv', 'read', 'info']) {
      final payload = frame[kind];
      if (payload is Map) {
        _events.add(TinodeEvent(kind, Map<String, dynamic>.from(payload)));
        return;
      }
    }
  }

  String _lastTopic = '';

  void _onCtrl(TinodeCtrl ctrl) {
    _lastTopic = ctrl.topic ?? _lastTopic;
    final pending = _pending;
    if (pending == null) return;
    _finish(pending, ctrl);
  }

  void _finish(_Pending pending, TinodeCtrl? ctrl) {
    if (identical(_pending, pending)) _pending = null;
    final result = _Result(ctrl)
      ..data.addAll(pending.data)
      ..meta.addAll(pending.meta);
    if (!pending.completer.isCompleted) pending.completer.complete(result);
  }

  void _onClosed([Object? error]) {
    _channel = null;
    _subscription = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(
        TinodeException('connection closed${error == null ? '' : ': $error'}'),
      );
    }
    _events.add(const TinodeEvent('closed', {}));
  }
}
