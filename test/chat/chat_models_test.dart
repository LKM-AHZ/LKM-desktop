import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:island/chat/backend/chat_models.dart';
import 'package:island/chat/tinode/tinode_client.dart';

Map<String, dynamic> _member(String uid) => chatMemberJson({
  'topic': 'grp1',
  'user': uid,
  'public': {'fn': 'bob'},
}, topic: 'grp1');

void main() {
  test('a Tinode message becomes a Solar message with its sequence', () {
    final json = chatMessageJson(
      const TinodeMessage(
        topic: 'grp1',
        from: 'usrABC',
        seq: 7,
        ts: null,
        content: {
          'txt': 'hello',
          ChatContentKeys.clientMessageId: 'c1',
          ChatContentKeys.repliedMessageId: 'grp1:3',
        },
      ),
      memberFor: _member,
    );

    expect(json['id'], 'grp1:7');
    expect(json['room_sequence'], 7);
    expect(json['chat_room_id'], 'grp1');
    expect(json['content'], 'hello');
    expect(json['client_message_id'], 'c1');
    expect(json['replied_message_id'], 'grp1:3');
    expect(json['sender_id'], 'usrABC');
    expect(json['sender']['nick'], 'bob');
  });

  test('member and message avatars round-trip as remote file references', () {
    final member = chatMemberJson({
      'user': 'usrABC',
      'public': {
        'fn': 'Bob',
        'photo': {'ref': 'https://cdn.example/bob.png'},
      },
    }, topic: 'grp1');
    expect(
      SnChatMember.fromJson(member).account.profile.picture!.storageUrl,
      'https://cdn.example/bob.png',
    );
    final json = chatMessageJson(
      const TinodeMessage(
        topic: 'grp1',
        from: 'usrABC',
        seq: 1,
        ts: null,
        content: {ChatContentKeys.senderAvatar: 'https://cdn.example/new.png'},
      ),
      memberFor: (_) => member,
    );
    final message = SnChatMessage.fromJson(json);
    expect(
      message.sender.account.profile.picture!.storageUrl,
      'https://cdn.example/new.png',
    );
    expect(message.sender.account.nick, 'Bob');
    expect(message.sender.account.profile.id, 'usrABC');
  });

  test('invalid avatar metadata preserves an existing member picture', () {
    for (final avatar in ['storage/key', 'javascript:alert(1)', '']) {
      final json = chatAccountJson(uid: 'usrABC', avatar: avatar);
      expect(json['profile']['picture'], isNull);
    }
    final member = chatMemberJson({
      'user': 'usrABC',
      'public': {
        'photo': {'ref': 'https://cdn.example/bob.png'},
      },
    }, topic: 'grp1');
    final json = chatMessageJson(
      const TinodeMessage(
        topic: 'grp1',
        from: 'usrABC',
        seq: 1,
        ts: null,
        content: {
          ChatContentKeys.senderName: 'Bob',
          ChatContentKeys.senderAvatar: 'old/storage/key',
        },
      ),
      memberFor: (_) => member,
    );
    expect(
      SnChatMessage.fromJson(json).sender.account.profile.picture!.storageUrl,
      'https://cdn.example/bob.png',
    );
  });

  test('outgoing payload keeps the fields the event pipeline needs', () {
    final content = chatContentFromPayload({
      'type': 'messages.update',
      'content': '',
      'meta': {'message_id': 'grp1:4'},
      'client_message_id': 'c2',
    }, senderName: 'alice');

    expect(content[ChatContentKeys.type], 'messages.update');
    expect(content[ChatContentKeys.clientMessageId], 'c2');
    expect(content[ChatContentKeys.meta], {'message_id': 'grp1:4'});
    expect(content[ChatContentKeys.senderName], 'alice');
  });

  test('a direct topic maps to type 1, a group topic to type 0', () {
    final direct = chatRoomJson({'topic': 'p2pABC', 'public': {}});
    final group = chatRoomJson({
      'topic': 'grpXYZ',
      'public': {'fn': 'Team'},
    });

    expect(direct['type'], 1);
    expect(direct['name'], isNull);
    expect(group['type'], 0);
    expect(group['name'], 'Team');
  });
}
