import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/config.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:island/shared/widgets/content/image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

const _serverUrl = 'https://api.example.com';

Future<void> _pumpAvatar(
  WidgetTester tester,
  IDisplayableCloudFile? file, {
  String? imageUrl,
  double radius = 20,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverUrlProvider.overrideWithValue(_serverUrl),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: ProfilePictureWidget(
              file: file,
              imageUrl: imageUrl,
              radius: radius,
              fallbackName: 'Littlesheep',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ProfilePictureWidget image source', () {
    testWidgets('loads a remote avatar from its storage url', (tester) async {
      // Fediverse actors arrive as a file reference with an empty id: the image
      // lives on the remote instance, so it must not be fetched from the local
      // drive endpoint.
      await _pumpAvatar(
        tester,
        const SnCloudFileReference(
          id: '',
          storageUrl: 'https://files.mastodon.social/a.png',
        ),
      );

      final image = tester.widget<UniversalImage>(find.byType(UniversalImage));
      expect(image.uri, 'https://files.mastodon.social/a.png');
    });

    testWidgets('loads a local avatar from the drive endpoint', (tester) async {
      await _pumpAvatar(tester, const SnCloudFileReference(id: 'file-1'));

      final image = tester.widget<UniversalImage>(find.byType(UniversalImage));
      expect(image.uri, '$_serverUrl/drive/files/file-1');
    });

    testWidgets('loads a local avatar over a blank storage url', (
      tester,
    ) async {
      // A blank storage url is not an address. Falling through to the drive
      // endpoint is what keeps the avatar visible instead of failing with
      // "No host specified in URI".
      await _pumpAvatar(
        tester,
        const SnCloudFileReference(id: 'file-1', storageUrl: ''),
      );

      final image = tester.widget<UniversalImage>(find.byType(UniversalImage));
      expect(image.uri, '$_serverUrl/drive/files/file-1');
    });

    testWidgets('falls back when the reference has no image', (tester) async {
      await _pumpAvatar(tester, const SnCloudFileReference(id: ''));

      expect(find.byType(UniversalImage), findsNothing);
      expect(find.text('LI'), findsOneWidget);
    });
  });

  testWidgets('direct avatars use the shared fallback and actual decode size', (
    tester,
  ) async {
    await _pumpAvatar(
      tester,
      null,
      imageUrl: 'https://community.example/avatar?v=2',
      radius: 13,
    );
    final image = tester.widget<UniversalImage>(find.byType(UniversalImage));
    expect(image.uri, 'https://community.example/avatar?v=2');
    expect(image.width, 26);
    expect(image.height, 26);
    expect(image.errorBuilder, isNotNull);
    expect(find.text('LI'), findsOneWidget);

    await _pumpAvatar(tester, null, imageUrl: 'not-an-image-url', radius: 13);
    expect(find.byType(CachedImageErrorWidget), findsNothing);
    expect(find.text('LI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composite avatars fill all cells and preserve names and remote URLs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      for (final count in [0, 1, 2, 3, 4, 7]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              serverUrlProvider.overrideWithValue(_serverUrl),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SplitAvatarWidget(
                    files: List.generate(
                      count,
                      (index) => index == 1
                          ? const SnCloudFileReference(
                              id: '',
                              storageUrl: 'https://cdn.example/avatar.png',
                            )
                          : null,
                    ),
                    fallbackNames: const ['Alice', 'Bob', '陈明', 'Dana'],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$count members');
        expect(
          tester.getSize(find.byType(SplitAvatarWidget)),
          const Size(40, 40),
        );
        if (count > 0) expect(find.text('AL'), findsOneWidget);
        if (count >= 2) {
          final image = tester.widget<UniversalImage>(
            find.byType(UniversalImage),
          );
          expect(image.uri, 'https://cdn.example/avatar.png');
        }
        if (count == 3) {
          final cells = find.byType(ProfilePictureWidget);
          expect(tester.getSize(cells.at(0)), const Size(20, 20));
          expect(tester.getSize(cells.at(1)), const Size(20, 20));
          expect(tester.getSize(cells.at(2)), const Size(20, 40));
        }
        if (count > 4) expect(find.text('+4'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'small fallback avatars fit large text and expose the full name',
    (tester) async {
      await _pumpAvatar(tester, null, radius: 8, textScale: 4);
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(ProfilePictureWidget)).label,
        'Littlesheep',
      );
      semantics.dispose();
    },
  );

  group('avatarFallbackText', () {
    test('uses up to two letters for a single Latin word', () {
      expect(avatarFallbackText('alice'), 'AL');
      expect(avatarFallbackText(' A '), 'A');
      expect(avatarFallbackText('123'), '12');
      expect(avatarFallbackText('#code'), '#C');
    });

    test('uses one CJK grapheme for CJK names', () {
      expect(avatarFallbackText('太阳'), '太');
      expect(avatarFallbackText('李四'), '李');
    });

    test('uses one whole emoji grapheme', () {
      expect(avatarFallbackText('😀'), '😀');
      expect(avatarFallbackText('👨‍👩‍👧'), '👨‍👩‍👧');
      expect(avatarFallbackText('1️⃣ team'), '1️⃣');
      expect(avatarFallbackText('🇨🇳'), '🇨🇳');
    });

    test('uses word initials for multi-word Latin names', () {
      expect(avatarFallbackText('Alice Zhang'), 'AZ');
      expect(avatarFallbackText('john doe'), 'JD');
    });

    test('does not create fallback text for missing nicknames', () {
      expect(avatarFallbackText(null), isNull);
      expect(avatarFallbackText('   '), isNull);
    });
  });
}
