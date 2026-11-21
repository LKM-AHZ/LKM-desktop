import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/config.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a cached avatar decodes at its physical display size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(400, 400);
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lkm_avatar_cache_'),
    ))!;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => directory.path,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      await tester.runAsync(() => directory.delete(recursive: true));
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const url = 'https://avatar.example/large.png';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 400);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await DefaultCacheManager().putFile(
        url,
        bytes!.buffer.asUint8List(),
        fileExtension: 'png',
      );
      image.dispose();
      picture.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProfilePictureWidget(
                imageUrl: url,
                radius: 20,
                fallbackName: 'Alice',
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final provider = image.image as ResizeImage;
    expect(provider.width, 80);
    expect(provider.height, 80);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => DefaultCacheManager().dispose());
  });
}
