import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart';

Future<void> onPerformAction(
  TextInputAction action,
  EditorState editorState,
) async {
  IslandEditorLog.input.debug('onPerformAction: $action');
}
