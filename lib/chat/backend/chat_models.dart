import 'dart:convert';

import 'package:island/chat/tinode/tinode_client.dart';

/// Keys this client stores inside a Tinode `content` map. Tinode only
/// interprets `txt`/`img`/`file`; everything below is ours and travels
/// untouched, so a plain Tinode client still renders the text.
class ChatContentKeys {
  static const type = 'x_type';
  static const meta = 'x_meta';
  static const clientMessageId = 'x_client_message_id';
  static const repliedMessageId = 'x_replied_message_id';
  static const threadId = 'x_thread_id';
  static const forwardedMessageId = 'x_forwarded_message_id';
  static const membersMentioned = 'x_members_mentioned';
  static const attachments = 'x_attachments';
  static const embeds = 'x_embeds';
  static const senderName = 'x_sender_name';
  static const senderAvatar = 'x_sender_avatar';
  static const replyPreview = 'x_reply_preview';
}

/// The bare Tinode uid (`abc123`) of a topic member or message sender.
///
/// Login returns `usr…`; message `from` also carries the prefix. The auth
/// bridge stores the bare value, so comparisons normalize to the prefix.
String tinodeUid(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  return value.startsWith('usr') ? value : 'usr$value';
}

String tinodeBareUid(String raw) {
  final value = raw.trim();
  return value.startsWith('usr') ? value.substring(3) : value;
}

DateTime _time(dynamic raw) {
  if (raw is DateTime) return raw.toUtc();
  if (raw is num) {
    // Tinode timestamps are RFC 3339 strings; a number is milliseconds.
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
  }
  return DateTime.tryParse('${raw ?? ''}')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

int _int(dynamic raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}') ?? fallback;
}

Map<String, dynamic>? _map(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<T> _list<T>(dynamic raw) =>
    raw is List ? raw.whereType<T>().toList(growable: false) : const [];

/// `typing`-style synthetic members and system senders have no server row;
/// the UI still needs a displayable account.
Map<String, dynamic> chatAccountJson({
  required String uid,
  String? name,
  String? avatar,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();
  final display = (name == null || name.isEmpty) ? uid : name;
  return {
    'id': uid,
    'name': display,
    'nick': display,
    'language': '',
    'is_superuser': false,
    'automated_id': null,
    'profile': {
      'id': uid,
      'experience': 0,
      'level': 1,
      'leveling_progress': 0,
      // Avatars live in the LKM file store, not the Solar drive the picture
      // widget resolves; show the initials fallback until a chat avatar path
      // exists.
      'picture': null,
      'background': null,
      'verification': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    },
    'perk_subscription': null,
    'activated_at': null,
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
  };
}

/// One subscriber row (`meta.sub[]`) as a Solar-shaped chat member.
Map<String, dynamic> chatMemberJson(
  Map<String, dynamic> sub, {
  required String topic,
  String? selfUid,
}) {
  final uid = tinodeUid('${sub['user'] ?? sub['topic'] ?? ''}');
  final public = _map(sub['public']) ?? const {};
  final name = '${public['fn'] ?? ''}';
  final avatar = _map(public['photo'])?['ref']?.toString();
  final lastReadAt = sub['read'];
  final now = DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();
  return {
    'id': uid,
    'chat_room_id': topic,
    'chat_room': null,
    'account_id': uid,
    'account': chatAccountJson(
      uid: uid,
      name: name.isEmpty ? uid : name,
      avatar: avatar,
    ),
    'nick': name.isEmpty ? null : name,
    'notify': _int(sub['notify'], 3),
    'joined_at': _timeOrNull(sub['created_at'] ?? sub['updated_at']),
    'leave_at': null,
    'confirmed_at': null,
    'break_until': null,
    'timeout_until': null,
    'chat_group_id': null,
    'chat_group': null,
    'last_read_at': lastReadAt is num
        ? _time(
            DateTime.fromMillisecondsSinceEpoch(
              lastReadAt.toInt() * 1000,
              isUtc: true,
            ),
          ).toIso8601String()
        : null,
    'status': null,
    'realm_nick': null,
    'realm_bio': null,
    'realm_experience': null,
    'realm_level': null,
    'realm_leveling_progress': null,
    'realm_label': null,
    'created_at': _timeOrNull(sub['created_at']) ?? now,
    'updated_at': _timeOrNull(sub['updated_at']) ?? now,
    'deleted_at': null,
  };
}

String? _timeOrNull(dynamic raw) {
  if (raw == null) return null;
  final parsed = DateTime.tryParse('$raw');
  if (parsed == null) return null;
  return parsed.toUtc().toIso8601String();
}

/// One subscription row from `get me what=sub` as a Solar-shaped room.
Map<String, dynamic> chatRoomJson(Map<String, dynamic> sub, {String? selfUid}) {
  final topic = '${sub['topic'] ?? ''}';
  final public = _map(sub['public']) ?? const {};
  final name = '${public['fn'] ?? ''}';
  final isDirect = topic.startsWith('p2p');
  final private = _map(sub['private']) ?? const {};
  final created =
      _timeOrNull(sub['created_at']) ?? _timeOrNull(public['created_at']);
  final updated =
      _timeOrNull(sub['updated_at']) ?? _timeOrNull(sub['touched_at']);
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'id': topic,
    'name': (isDirect && name.isEmpty) ? null : (name.isEmpty ? null : name),
    'description': public['note'] as String?,
    'slug': null,
    'type': isDirect ? 1 : 0,
    'encryption_mode': 0,
    'mls_group_id': null,
    'is_public': public['is_public'] == true,
    'is_community': false,
    'is_read_receipts_public': true,
    'picture': _chatPictureJson(public['photo']),
    'background': null,
    'realm_id': null,
    'account_id': tinodeUid('${sub['owner'] ?? selfUid ?? ''}'),
    'realm': null,
    'created_at': created ?? now,
    'updated_at': updated ?? created ?? now,
    'deleted_at': null,
    'members': null,
    'is_pinned': private['is_pinned'] == true,
  };
}

Map<String, dynamic>? _chatPictureJson(dynamic raw) {
  final photo = _map(raw);
  if (photo == null) return null;
  final ref = '${photo['ref'] ?? ''}';
  if (ref.isEmpty) return null;
  return {
    'id': ref,
    'name': null,
    'size': _int(photo['size']),
    'mime_type': photo['type'],
    'width': photo['width'],
    'height': photo['height'],
  };
}

/// A Tinode `data` frame as a Solar-shaped chat message.
Map<String, dynamic> chatMessageJson(
  TinodeMessage message, {
  required Map<String, dynamic> Function(String uid) memberFor,
}) {
  final content = message.content;
  final text = content['txt'];
  final type = '${content[ChatContentKeys.type] ?? 'text'}';
  final meta = _map(content[ChatContentKeys.meta]) ?? const {};
  final attachments = _list<Map>(
    content[ChatContentKeys.attachments],
  ).map((e) => Map<String, dynamic>.from(e)).toList();
  final embeds = _list<Map>(
    content[ChatContentKeys.embeds],
  ).map((e) => Map<String, dynamic>.from(e)).toList();
  final senderUid = tinodeUid(message.from);
  final id = message.id?.isNotEmpty == true
      ? message.id!
      : '${message.topic}:${message.seq}';
  final ts = (message.ts ?? DateTime.now()).toUtc();
  final sender = memberFor(senderUid);
  final senderName = content[ChatContentKeys.senderName]?.toString();
  final labelledSender = (senderName == null || senderName.isEmpty)
      ? sender
      : () {
          final account = _map(sender['account']) ?? <String, dynamic>{};
          account['name'] = senderName;
          account['nick'] = senderName;
          return {...sender, 'nick': senderName, 'account': account};
        }();
  final messageMeta = <String, dynamic>{
    ...meta,
    if (content[ChatContentKeys.senderName] != null)
      'sender_name': content[ChatContentKeys.senderName],
    if (content[ChatContentKeys.senderAvatar] != null)
      'sender_avatar': content[ChatContentKeys.senderAvatar],
    if (content[ChatContentKeys.replyPreview] != null)
      'reply_preview': content[ChatContentKeys.replyPreview],
  };
  return {
    'id': id,
    'created_at': ts.toIso8601String(),
    'updated_at': ts.toIso8601String(),
    'deleted_at': null,
    'type': type,
    'content': text is String ? text : null,
    'client_message_id': content[ChatContentKeys.clientMessageId]?.toString(),
    'nonce': null,
    'encryption_meta': null,
    'meta': messageMeta,
    'members_mentioned': _list<String>(
      content[ChatContentKeys.membersMentioned],
    ),
    'edited_at': null,
    'attachments': attachments,
    'reactions': const [],
    'reactions_count': const <String, dynamic>{},
    'reactions_made': const <String, dynamic>{},
    'is_thread_root': false,
    'thread_replies_count': 0,
    'thread_replies': const [],
    'replied_message_id': content[ChatContentKeys.repliedMessageId]?.toString(),
    'thread_id': content[ChatContentKeys.threadId]?.toString(),
    'forwarded_message_id': content[ChatContentKeys.forwardedMessageId]
        ?.toString(),
    'sender_id': senderUid,
    'sender': labelledSender,
    'chat_room_id': message.topic,
    'room_sequence': message.seq,
    'embeds': embeds,
  };
}

/// A Solar send payload (`content`, `attachments_id`, `meta`…) as Tinode
/// content. The textual form is kept in `txt` so other clients still show it.
Map<String, dynamic> chatContentFromPayload(
  Map<String, dynamic> payload, {
  required String senderName,
  String? senderAvatar,
}) {
  final meta = _map(payload['meta']) ?? const {};
  final embeds = _list<Map>(
    payload['embeds'],
  ).map((e) => Map<String, dynamic>.from(e)).toList();
  return {
    'txt': payload['content'] ?? '',
    ChatContentKeys.type: '${payload['type'] ?? 'text'}',
    if (payload['client_message_id'] != null)
      ChatContentKeys.clientMessageId: payload['client_message_id'],
    if (payload['replied_message_id'] != null)
      ChatContentKeys.repliedMessageId: payload['replied_message_id'],
    if (payload['thread_id'] != null)
      ChatContentKeys.threadId: payload['thread_id'],
    if (payload['forwarded_message_id'] != null)
      ChatContentKeys.forwardedMessageId: payload['forwarded_message_id'],
    if (meta.isNotEmpty) ChatContentKeys.meta: meta,
    if (embeds.isNotEmpty) ChatContentKeys.embeds: embeds,
    ChatContentKeys.senderName: senderName,
    if (senderAvatar != null && senderAvatar.isNotEmpty)
      ChatContentKeys.senderAvatar: senderAvatar,
    if (payload['attachments_id'] is List &&
        (payload['attachments_id'] as List).isNotEmpty)
      ChatContentKeys.attachments: [
        for (final id in (payload['attachments_id'] as List)) {'id': '$id'},
      ],
  };
}
