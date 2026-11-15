import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/posts/widgets/compose/compose_recorder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';
import 'package:record_ohos/record_ohos.dart';

void main() {
  testWidgets('compose recorder keeps one native instance across rebuilds', (
    tester,
  ) async {
    final original = RecordPlatform.instance;
    RecordOhos.registerWith();
    const channel = MethodChannel('com.llfbandit.record/messages');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      RecordPlatform.instance = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ComposeRecorder())),
    );
    await tester.pump();
    expect(calls.where((method) => method == 'create').length, 1);
    tester.element(find.byType(ComposeRecorder)).markNeedsBuild();
    await tester.pump();
    expect(calls.where((method) => method == 'create').length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.where((method) => method == 'dispose').length, 1);
    expect(tester.takeException(), isNull);
  });
}
