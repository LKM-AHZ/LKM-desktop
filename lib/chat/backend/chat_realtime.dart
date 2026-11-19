import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:island/chat/backend/chat_backend.dart';
import 'package:island/chat/backend/chat_models.dart';
import 'package:island/chat/tinode/tinode_client.dart';
import 'package:island/chat/tinode/tinode_provider.dart';

/// The chat realtime channel.
///
/// Tinode has no Solar gateway packets, so this service translates in both
/// directions: inbound `data`/`info`/`pres` frames become the `messages.*`
/// packets the chat pipeline already understands, and the packets the UI sends
/// (`messages.subscribe`, `read`, `typing`, `send`) become Tinode requests.
///
/// It extends the SDK service only to satisfy the chat module's existing
/// `websocketProvider` typing; no Solar socket is opened.
class ChatRealtimeService extends SolarWebSocketService {
  ChatRealtimeService(this._ref)
    : super(uri: () => Uri(), token: () async => null);

  final Ref _ref;
  final _logger = Logger('ChatRealtime');
  final _packets = StreamController<WebSocketPacket>.broadcast();
  final _statuses = StreamController<WebSocketState>.broadcast();

  StreamSubscription<TinodeEvent>? _events;
  ProviderSubscription<AsyncValue<TinodeClient?>>? _clientWatch;
  TinodeClient? _attached;
  bool _connected = false;
  bool _closed = false;
  Timer? _reconnectTimer;

  @override
  Stream<WebSocketPacket> get dataStream => _packets.stream;

  @override
  Stream<WebSocketState> get statusStream => _statuses.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    _closed = false;
    _clientWatch ??= _ref.listen<AsyncValue<TinodeClient?>>(
      tinodeClientProvider,
      (_, next) => _attach(next.value),
      fireImmediately: true,
    );
    await _attach(_ref.read(tinodeClientProvider).value);
  }

  Future<void> _attach(TinodeClient? client) async {
    if (identical(_attached, client) && _events != null) return;
    await _events?.cancel();
    _events = null;
    _attached = client;
    if (client == null) {
      _setConnected(false);
      return;
    }
    _events = client.events.listen(_onEvent);
    _setConnected(client.isConnected);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (_closed) return;
    _statuses.add(
      value
          ? const WebSocketState.connected()
          : const WebSocketState.disconnected(),
    );
  }

  @override
  bool sendMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return false;
      final packet = WebSocketPacket.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      unawaited(_handleOutgoing(packet));
      return true;
    } catch (error) {
      _logger.info('Dropping malformed chat frame: $error');
      return false;
    }
  }

  Future<void> _handleOutgoing(WebSocketPacket packet) async {
    final data = packet.data;
    final topic = data?['chat_room_id']?.toString();
    if (topic == null || topic.isEmpty) return;
    final backend = _ref.read(chatBackendProvider);
    try {
      switch (packet.type) {
        case 'messages.subscribe':
          await backend.subscribe(topic);
          break;
        case 'messages.unsubscribe':
          await backend.unsubscribe(topic);
          break;
        case 'messages.read':
          backend.markRead(topic, backend.unreadSeqFor(topic));
          break;
        case 'messages.typing':
          backend.typing(topic);
          break;
        case 'messages.send':
          final sent = await backend.send(topic, data!);
          _packets.add(
            WebSocketPacket(
              type: 'messages.delivered',
              endpoint: 'messager',
              data: {...sent.toJson(), 'chat_room_id': topic},
            ),
          );
          break;
        default:
          break;
      }
    } catch (error, stackTrace) {
      _logger.info('Chat ${packet.type} failed: $error', error, stackTrace);
    }
  }

  void _onEvent(TinodeEvent event) {
    switch (event.kind) {
      case 'data':
        unawaited(_onMessage(event.payload));
        break;
      case 'info':
        _onInfo(event.payload);
        break;
      case 'pres':
        final topic = '${event.payload['topic'] ?? ''}';
        if (topic.isEmpty) return;
        _packets.add(
          WebSocketPacket(
            type: 'chat.presence.updated',
            data: {'room_id': topic, 'src': event.payload['src']},
          ),
        );
        break;
      case 'meta':
      case 'read':
      case 'recv':
        break;
      case 'closed':
        _setConnected(false);
        _scheduleReconnect();
        break;
    }
  }

  Future<void> _onMessage(Map<String, dynamic> payload) async {
    final topic = '${payload['topic'] ?? ''}';
    if (topic.isEmpty) return;
    final message = TinodeMessage.fromJson(topic, payload);
    final json = _ref.read(chatBackendProvider).messageJsonFor(message);
    _packets.add(
      WebSocketPacket(type: 'messages.new', endpoint: 'messager', data: json),
    );
  }

  void _onInfo(Map<String, dynamic> payload) {
    final topic = '${payload['topic'] ?? ''}';
    if (topic.isEmpty) return;
    final from = tinodeUid('${payload['from'] ?? ''}');
    final what = '${payload['what'] ?? ''}';
    final backend = _ref.read(chatBackendProvider);
    switch (what) {
      case 'kp':
        _packets.add(
          WebSocketPacket(
            type: 'messages.typing',
            endpoint: 'messager',
            data: {
              'room_id': topic,
              'sender': backend.memberFor(topic, from),
              'type': 'typing',
              'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
            },
          ),
        );
        break;
      case 'read':
        _packets.add(
          WebSocketPacket(
            type: 'messages.read',
            endpoint: 'messager',
            data: {
              'chat_room_id': topic,
              'account_id': from,
              'last_read_at': DateTime.now().toUtc().toIso8601String(),
              'seq': payload['seq'],
            },
          ),
        );
        break;
      default:
        break;
    }
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_closed) return;
      _ref.invalidate(tinodeClientProvider);
      try {
        await _attach(await _ref.read(tinodeClientProvider.future));
      } catch (error) {
        _logger.info('Chat reconnect failed: $error');
        _scheduleReconnect();
      }
    });
  }

  @override
  void manualReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _ref.invalidate(tinodeClientProvider);
    unawaited(
      _ref.read(tinodeClientProvider.future).then(_attach).catchError((
        Object error,
      ) {
        _logger.info('Manual chat reconnect failed: $error');
      }),
    );
  }

  @override
  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _events?.cancel();
    _events = null;
    _clientWatch?.close();
    _clientWatch = null;
    _setConnected(false);
    unawaited(_packets.close());
    unawaited(_statuses.close());
  }
}

final chatRealtimeProvider = Provider<SolarWebSocketService>((ref) {
  final service = ChatRealtimeService(ref);
  ref.onDispose(service.close);
  unawaited(service.connect());
  return service;
});

final chatRealtimeStateProvider =
    NotifierProvider<ChatRealtimeStateNotifier, WebSocketState>(
      ChatRealtimeStateNotifier.new,
    );

class ChatRealtimeStateNotifier extends Notifier<WebSocketState> {
  StreamSubscription<WebSocketState>? _subscription;

  @override
  WebSocketState build() {
    _subscription?.cancel();
    final service = ref.read(chatRealtimeProvider);
    _subscription = service.statusStream.listen((event) {
      state = event;
    });
    ref.onDispose(() => _subscription?.cancel());
    return service.isConnected
        ? const WebSocketState.connected()
        : const WebSocketState.disconnected();
  }

  Future<void> connect() => ref.read(chatRealtimeProvider).connect();

  void sendMessage(String message) =>
      ref.read(chatRealtimeProvider).sendMessage(message);

  void close() {
    ref.read(chatRealtimeProvider).close();
    state = const WebSocketState.disconnected();
  }

  void manualReconnect() => ref.read(chatRealtimeProvider).manualReconnect();
}

final chatRealtimeConnectedProvider = Provider<bool>((ref) {
  return ref.watch(
    chatRealtimeStateProvider.select(
      (state) => state.maybeWhen(connected: () => true, orElse: () => false),
    ),
  );
});
