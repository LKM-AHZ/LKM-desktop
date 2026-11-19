import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:island/chat/backend/chat_models.dart';
import 'package:island/chat/tinode/tinode_client.dart';
import 'package:island/chat/tinode/tinode_provider.dart';
import 'package:island/accounts/account_pod.dart';
import 'package:island/community/user_pod.dart';

/// One page of history, newest first, in the shape the message sync service
/// expects from the old REST endpoint.
class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.totalCount,
    required this.hasMore,
  });

  final List<SnChatMessage> messages;
  final int totalCount;
  final bool hasMore;
}

/// The one chat backend: Tinode topics, messages and membership, translated
/// into the shapes the Solar chat pipeline already consumes.
///
/// Everything the UI and sync services used to read from `/messager/chat/*`
/// goes through here, so the rest of the chat module stays unchanged.
class ChatBackend {
  ChatBackend(this._ref);

  final Ref _ref;
  final _logger = Logger('ChatBackend');

  /// Latest subscription rows from `get me what=sub`, keyed by topic.
  final Map<String, Map<String, dynamic>> _subs = {};

  /// `topic → uid → member json`, filled from subscriber rows.
  final Map<String, Map<String, Map<String, dynamic>>> _members = {};

  /// `topic → highest seq` so pagination does not need a meta round trip.
  final Map<String, int> _maxSeq = {};

  TinodeClient get _client {
    final client = _ref.read(tinodeClientProvider).value;
    if (client == null) {
      throw StateError('聊天服务尚未登录');
    }
    return client;
  }

  String? get selfUid {
    final client = _ref.read(tinodeClientProvider).value;
    return client?.userId == null ? null : tinodeUid(client!.userId!);
  }

  /// Signed-in member's display name/avatar, used to label outgoing messages
  /// so other clients can show a name without a second lookup.
  String get selfName => _ref.read(chatSelfProfileProvider).name;
  String? get selfAvatar => _ref.read(chatSelfProfileProvider).avatar;

  // ── Rooms ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> rooms() async {
    await _ensureClient();
    final client = _client;
    final meta = await client.meta('me', 'sub');
    final rows = meta?['sub'];
    if (rows is! List) return [for (final sub in _subs.values) sub];
    _subs.clear();
    _maxSeq.clear();
    for (final raw in rows.whereType<Map>()) {
      final sub = Map<String, dynamic>.from(raw);
      final topic = '${sub['topic'] ?? ''}';
      if (topic.isEmpty) continue;
      _subs[topic] = sub;
      _maxSeq[topic] = _int(sub['seq']);
      _rememberSelf(sub, topic);
    }
    return [
      for (final sub in _subs.values) chatRoomJson(sub, selfUid: selfUid),
    ];
  }

  Future<Map<String, dynamic>?> room(String topic) async {
    await _ensureClient();
    final client = _client;
    try {
      final desc = await client.meta(topic, 'desc');
      final public = _asMap(desc?['public']) ?? {};
      final cached = _subs[topic] ?? {};
      final merged = <String, dynamic>{
        ...cached,
        'topic': topic,
        'public': {..._asMap(cached['public']) ?? {}, ...public},
        if (desc?['owner'] != null) 'owner': desc!['owner'],
      };
      _subs[topic] = merged;
      return chatRoomJson(merged, selfUid: selfUid);
    } catch (error) {
      _logger.info('describe $topic failed: $error');
      final cached = _subs[topic];
      return cached == null ? null : chatRoomJson(cached, selfUid: selfUid);
    }
  }

  /// Subscribes to the topic so its messages stream in. Idempotent on the
  /// server side.
  Future<void> subscribe(String topic) async {
    await _ensureClient();
    await _client.subscribe(topic);
  }

  Future<void> unsubscribe(String topic) async {
    await _ensureClient();
    await _client.leave(topic);
  }

  // ── Members ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> members(String topic) async {
    await _ensureClient();
    final rows = await _client.subscribers(topic);
    final byUid = _members.putIfAbsent(topic, () => {});
    for (final sub in rows) {
      final member = chatMemberJson(sub, topic: topic, selfUid: selfUid);
      byUid['${member['id']}'] = member;
      final seq = _int(sub['seq']);
      if (seq > (_maxSeq[topic] ?? 0)) _maxSeq[topic] = seq;
    }
    return byUid.values.toList(growable: false);
  }

  Map<String, dynamic> memberFor(String topic, String uid) {
    final normalized = tinodeUid(uid);
    return _members[topic]?[normalized] ??
        chatMemberJson(
          {'topic': topic, 'user': normalized, 'public': {}},
          topic: topic,
          selfUid: selfUid,
        );
  }

  Map<String, dynamic> selfMember(String topic) {
    final uid = selfUid;
    if (uid == null) {
      return chatMemberJson({'topic': topic, 'user': ''}, topic: topic);
    }
    final existing = _members[topic]?[uid];
    if (existing != null) return existing;
    final profile = _ref.read(chatSelfProfileProvider);
    return chatMemberJson(
      {
        'topic': topic,
        'user': uid,
        'public': {if (profile.name.isNotEmpty) 'fn': profile.name},
      },
      topic: topic,
      selfUid: uid,
    );
  }

  /// Unread count of one topic, from the subscription's seq/read pair.
  int unreadOf(String topic) {
    final unread = unreadSeqFor(topic) - _int(_subs[topic]?['read']);
    return unread > 0 ? unread : 0;
  }

  /// Highest seq of [topic], the value a read receipt carries.
  int unreadSeqFor(String topic) =>
      _maxSeq[topic] ?? _int(_subs[topic]?['seq']);

  /// One realtime frame translated into the Solar message JSON shape.
  Map<String, dynamic> messageJsonFor(TinodeMessage message) => chatMessageJson(
    message,
    memberFor: (uid) => memberFor(message.topic, uid),
  );

  Future<Map<String, Map<String, dynamic>>> summaries() async {
    await _ensureClient();
    final rooms = <String, Map<String, dynamic>>{};
    for (final topic in _subs.keys) {
      final last = await _lastMessage(topic);
      final unread = unreadOf(topic);
      rooms[topic] = {
        'unread_count': unread,
        'has_unread': unread > 0,
        'last_message': last,
      };
    }
    return rooms;
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  /// History page. `offset` counts back from the newest message, matching the
  /// old REST contract.
  Future<ChatMessagePage> fetchMessages(
    String topic, {
    required int offset,
    required int take,
  }) async {
    await _ensureClient();
    final client = _client;
    final total = _maxSeq[topic] ?? _int(_subs[topic]?['seq']);
    if (total <= 0 || offset >= total) {
      return ChatMessagePage(
        messages: const [],
        totalCount: total,
        hasMore: false,
      );
    }
    final before = total - offset + 1;
    final raw = await client.history(topic, limit: take, before: before);
    final messages = [
      for (final message in raw.reversed)
        SnChatMessage.fromJson(
          chatMessageJson(message, memberFor: (uid) => memberFor(topic, uid)),
        ),
    ];
    return ChatMessagePage(
      messages: messages,
      totalCount: total,
      hasMore: offset + messages.length < total,
    );
  }

  Future<SnChatMessage?> fetchMessage(String topic, String messageId) async {
    final seq = _seqFromId(topic, messageId);
    if (seq != null) {
      await _ensureClient();
      final raw = await _client.history(
        topic,
        limit: 1,
        before: seq + 1,
        since: seq,
      );
      if (raw.isEmpty) return null;
      return _toRemote(topic, raw.last);
    }
    // Server ids are opaque; scan the newest page before giving up.
    await _ensureClient();
    final raw = await _client.history(topic, limit: 100);
    for (final message in raw) {
      final remote = _toRemote(topic, message);
      if (remote.id == messageId) return remote;
    }
    return null;
  }

  Future<SnChatMessage> send(String topic, Map<String, dynamic> payload) async {
    await _ensureClient();
    final content = chatContentFromPayload(
      payload,
      senderName: selfName,
      senderAvatar: selfAvatar,
    );
    final message = await _client.send(topic, content);
    return _toRemote(topic, message, fallbackContent: content);
  }

  /// Publishes an event row (reaction, pin, edit, delete…) as a message so
  /// other clients replay it through the same realtime pipeline.
  Future<SnChatMessage> sendEvent(
    String topic, {
    required String type,
    Map<String, dynamic> meta = const {},
    String content = '',
    String? clientMessageId,
    String? repliedMessageId,
    String? threadId,
    String? forwardedMessageId,
    List<Map<String, dynamic>> embeds = const [],
  }) {
    return send(topic, {
      'type': type,
      'content': content,
      'meta': meta,
      'client_message_id': ?clientMessageId,
      'replied_message_id': ?repliedMessageId,
      'thread_id': ?threadId,
      'forwarded_message_id': ?forwardedMessageId,
      if (embeds.isNotEmpty) 'embeds': embeds,
    });
  }

  Future<void> deleteMessage(String topic, String messageId) async {
    final seq = _seqFromId(topic, messageId);
    if (seq == null) return;
    await _ensureClient();
    await _client.deleteMessage(topic, seq);
  }

  Future<List<Map<String, dynamic>>> messagesSince(
    String topic,
    int sinceSeq, {
    int limit = 200,
  }) async {
    await _ensureClient();
    final raw = await _client.history(topic, limit: limit, since: sinceSeq + 1);
    return [
      for (final message in raw)
        chatMessageJson(message, memberFor: (uid) => memberFor(topic, uid)),
    ];
  }

  void markRead(String topic, int seq) {
    final client = _ref.read(tinodeClientProvider).value;
    client?.markRead(topic, seq);
  }

  void markAllRead() {
    for (final entry in _subs.entries) {
      markRead(entry.key, _int(entry.value['seq']));
    }
  }

  void typing(String topic) {
    final client = _ref.read(tinodeClientProvider).value;
    client?.typing(topic);
  }

  Future<Map<String, dynamic>> createRoom({
    required String name,
    Map<String, dynamic>? public,
    Map<String, dynamic>? private,
    List<String> tags = const [],
  }) async {
    await _ensureClient();
    final ctrl = await _client.subscribe(
      'new',
      create: true,
      public: {'fn': name, ...?public},
      private: private,
    );
    final topic = ctrl.topic ?? '';
    if (tags.isNotEmpty && topic.isNotEmpty) {
      await _client.setDesc(topic, tags: tags);
    }
    final created = await room(topic);
    return created ?? chatRoomJson({'topic': topic}, selfUid: selfUid);
  }

  /// Opens (or creates) a direct chat with a Tinode user.
  Future<Map<String, dynamic>> directRoom(String uid) async {
    await _ensureClient();
    final peer = tinodeUid(uid);
    await _client.subscribe(peer);
    final created = await room(peer);
    return created ??
        chatRoomJson({'topic': peer, 'public': {}}, selfUid: selfUid);
  }

  Future<void> addMember(String topic, String uid) async {
    await _ensureClient();
    await _client.addSubscriber(topic, tinodeUid(uid));
  }

  Future<void> removeMember(String topic, String uid) async {
    await _ensureClient();
    await _client.removeSubscriber(topic, tinodeUid(uid));
  }

  Future<void> updateRoom(
    String topic, {
    String? name,
    String? description,
  }) async {
    await _ensureClient();
    await _client.setDesc(topic, public: {'fn': ?name, 'note': ?description});
    _subs[topic] = {
      ...?_subs[topic],
      'topic': topic,
      'public': {
        ...?_asMap(_subs[topic]?['public']),
        'fn': ?name,
        'note': ?description,
      },
    };
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<void> _ensureClient() async {
    await _ref.read(tinodeClientProvider.future);
  }

  SnChatMessage _toRemote(
    String topic,
    TinodeMessage message, {
    Map<String, dynamic>? fallbackContent,
  }) {
    final effective = message.content.isEmpty && fallbackContent != null
        ? TinodeMessage(
            topic: message.topic,
            from: message.from.isEmpty ? (selfUid ?? '') : message.from,
            seq: message.seq,
            ts: message.ts,
            content: fallbackContent,
            id: message.id,
          )
        : message;
    return SnChatMessage.fromJson(
      chatMessageJson(effective, memberFor: (uid) => memberFor(topic, uid)),
    );
  }

  Future<Map<String, dynamic>?> _lastMessage(String topic) async {
    final max = _maxSeq[topic];
    if (max == null || max <= 0) return null;
    try {
      final raw = await _client.history(topic, limit: 1, before: max + 1);
      if (raw.isEmpty) return null;
      return chatMessageJson(
        raw.last,
        memberFor: (uid) => memberFor(topic, uid),
      );
    } catch (_) {
      return null;
    }
  }

  void _rememberSelf(Map<String, dynamic> sub, String topic) {
    final public = _asMap(sub['public']);
    if (public == null) return;
    final user = sub['user']?.toString();
    if (user == null) return;
    final existing = _members.putIfAbsent(topic, () => {});
    existing[tinodeUid(user)] = chatMemberJson(
      {...sub, 'user': user},
      topic: topic,
      selfUid: selfUid,
    );
  }

  static int? _seqFromId(String topic, String messageId) {
    final prefix = '$topic:';
    if (messageId.startsWith(prefix)) {
      return int.tryParse(messageId.substring(prefix.length));
    }
    return null;
  }
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

int _int(dynamic raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}') ?? fallback;
}

/// The signed-in chat identity as Tinode/other clients should see it.
class ChatSelfProfile {
  const ChatSelfProfile({required this.uid, required this.name, this.avatar});

  final String? uid;
  final String name;
  final String? avatar;
}

final chatBackendProvider = Provider<ChatBackend>(ChatBackend.new);

/// The signed-in Tinode uid, the identity chat rows compare against.
final chatSelfIdProvider = Provider<String?>((ref) {
  final client = ref.watch(tinodeClientProvider).value;
  final uid = client?.userId;
  if (uid != null) return tinodeUid(uid);
  // Tests and the pre-Tinode session still drive the Solar identity.
  return ref.watch(userInfoProvider).value?.id;
});

final chatSelfProfileProvider = Provider<ChatSelfProfile>((ref) {
  final client = ref.watch(tinodeClientProvider).value;
  final account = ref.watch(lkmMeProvider).value;
  final uid = client?.userId;
  final name = account?.displayName.trim() ?? '';
  return ChatSelfProfile(
    uid: uid == null ? null : tinodeUid(uid),
    name: name.isEmpty ? (uid ?? '我') : name,
    avatar: account?.avatar,
  );
});
