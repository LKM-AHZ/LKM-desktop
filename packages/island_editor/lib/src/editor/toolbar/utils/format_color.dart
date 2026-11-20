import 'package:island_editor/island_editor.dart';

void formatHighlightColor(
  EditorState editorState,
  Selection? selection,
  String? color, {
  bool withUpdateSelection = false,
}) {
  editorState.formatDelta(
    selection,
    {IslandRichTextKeys.backgroundColor: color},
    withUpdateSelection: withUpdateSelection,
  );
}

void formatFontColor(
  EditorState editorState,
  Selection? selection,
  String? color, {
  bool withUpdateSelection = false,
}) {
  editorState.formatDelta(
    selection,
    {IslandRichTextKeys.textColor: color},
    withUpdateSelection: withUpdateSelection,
  );
}
