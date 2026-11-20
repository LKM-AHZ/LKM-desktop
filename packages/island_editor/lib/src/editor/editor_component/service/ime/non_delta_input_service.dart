import 'dart:math';

import 'package:island_editor/island_editor.dart';
import 'package:island_editor/src/editor/editor_component/service/ime/text_diff.dart';
import 'package:island_editor/src/editor/editor_component/service/ime/text_input_service.dart';
import 'package:island_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/services.dart';

// string from flutter callback
const String _deleteBackwardSelectorName = 'deleteBackward:';

class NonDeltaTextInputService extends TextInputService with TextInputClient {
  NonDeltaTextInputService({
    required super.onInsert,
    required super.onDelete,
    required super.onReplace,
    required super.onNonTextUpdate,
    required super.onPerformAction,
    super.contentInsertionConfiguration,
    super.onFloatingCursor,
  });

  @override
  TextRange? composingTextRange;

  @override
  bool get attached => _textInputConnection?.attached ?? false;

  @override
  bool onFocusReceived() => attached;

  @override
  AutofillScope? get currentAutofillScope => throw UnimplementedError();

  @override
  TextEditingValue? get currentTextEditingValue => _currentTextEditingValue;

  TextEditingValue? _currentTextEditingValue;
  TextEditingValue? _pendingEditingValue;

  set currentTextEditingValue(TextEditingValue? newValue) {
    _currentTextEditingValue = newValue;
  }

  TextInputConnection? _textInputConnection;

  final String debounceKey = 'updateEditingValue';

  // when using gesture to move cursor on mobile, the floating cursor will be visible
  bool _isFloatingCursorVisible = false;

  @override
  Future<bool> apply(List<TextEditingDelta> deltas) async {
    final formattedDeltas = deltas.map((e) => e.format()).toList();
    bool willApply = true;
    for (final delta in formattedDeltas) {
      _updateComposing(delta);
      if (delta is TextEditingDeltaInsertion) {
        if (!(await onInsert(delta))) willApply = false;
      } else if (delta is TextEditingDeltaDeletion) {
        if (!(await onDelete(delta))) willApply = false;
      } else if (delta is TextEditingDeltaReplacement) {
        if (!(await onReplace(delta))) willApply = false;
      } else if (delta is TextEditingDeltaNonTextUpdate) {
        if (!(await onNonTextUpdate(delta))) willApply = false;
      }
    }
    return willApply;
  }

  @override
  void attach(
    TextEditingValue textEditingValue,
    TextInputConfiguration configuration,
  ) {
    final formattedValue = textEditingValue.format();
    if (!formattedValue.isValid()) {
      return;
    }

    if (currentTextEditingValue == formattedValue &&
        _pendingEditingValue == null) {
      return;
    }

    if (_textInputConnection == null ||
        _textInputConnection!.attached == false) {
      _textInputConnection = TextInput.attach(
        this,
        configuration,
      );
    }

    // If a debounced update is already matching what we're attaching, just
    // cancel the redundant timer without resetting the native IME session.
    if (_pendingEditingValue == formattedValue) {
      Debounce.cancel(debounceKey);
      _pendingEditingValue = null;
      currentTextEditingValue = formattedValue;
      return;
    }

    Debounce.cancel(debounceKey);
    _pendingEditingValue = null;

    _textInputConnection!
      ..setEditingState(formattedValue)
      ..show();

    currentTextEditingValue = formattedValue;

    IslandEditorLog.input.debug(
      'attach text editing value: $textEditingValue',
    );
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (currentTextEditingValue == value) {
      // Cancel any pending debounced update (e.g. a transient clear during
      // mobile voice dictation) so it cannot fire later and wipe the text.
      Debounce.cancel(debounceKey);
      _pendingEditingValue = null;
      return;
    }

    if (PlatformExtension.isIOS && _isFloatingCursorVisible) {
      // on iOS, when using gesture to move cursor, this function will be called
      // which may cause the unneeded delta being applied
      // so we ignore the updateEditingValue event when the floating cursor is visible
      IslandEditorLog.editor.debug(
        'ignore updateEditingValue event when the floating cursor is visible',
      );
      return;
    }

    _pendingEditingValue = value;
    // On mobile, the IME can emit rapid intermediate updateEditingValue events
    // (such as voice dictation updates). Debounce briefly and compute deltas
    // against the latest committed value when the timer fires so rapid bursts
    // coalesce cleanly without stale diffs.
    Debounce.debounce(
      debounceKey,
      PlatformExtension.isMobile
          ? const Duration(milliseconds: 10)
          : Duration.zero,
      () async {
        _pendingEditingValue = null;
        if (_currentTextEditingValue == value) {
          return;
        }
        final oldValue = _currentTextEditingValue?.copyWith();
        final deltas = getTextEditingDeltas(oldValue, value);
        currentTextEditingValue = value;
        final willApply = await apply(deltas);
        if (!willApply && oldValue != null) {
          currentTextEditingValue = oldValue;
          _textInputConnection?.setEditingState(oldValue);
        }
      },
    );
  }

  @override
  void close() {
    Debounce.cancel(debounceKey);
    _pendingEditingValue = null;
    keepEditorFocusNotifier.reset();
    currentTextEditingValue = null;
    composingTextRange = null;
    _textInputConnection?.close();
    _textInputConnection = null;
  }

  @override
  void updateCaretPosition(Size size, Matrix4 transform, Rect rect) {
    _textInputConnection
      ?..setEditableSizeAndTransform(size, transform)
      ..setCaretRect(rect)
      ..setComposingRect(rect.translate(0, rect.height));
  }

  @override
  void clearComposingTextRange() {
    composingTextRange = TextRange.empty;
  }

  @override
  void connectionClosed() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  Future<void> performAction(TextInputAction action) async {
    IslandEditorLog.editor.debug('performAction: $action');
    return onPerformAction(action);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    IslandEditorLog.editor.debug('performPrivateCommand: $action, $data');
  }

  @override
  void removeTextPlaceholder() {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void showToolbar() {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    switch (point.state) {
      case FloatingCursorDragState.Start:
        _isFloatingCursorVisible = true;
        break;
      case FloatingCursorDragState.Update:
        _isFloatingCursorVisible = true;
        break;
      case FloatingCursorDragState.End:
        _isFloatingCursorVisible = false;
        break;
    }

    onFloatingCursor?.call(point);
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void performSelector(String selectorName) {
    IslandEditorLog.editor.debug('performSelector: $selectorName');

    final currentTextEditingValue = this.currentTextEditingValue?.unformat();
    if (currentTextEditingValue == null) {
      return;
    }

    if (selectorName == _deleteBackwardSelectorName) {
      final oldText = currentTextEditingValue.text;
      final selection = currentTextEditingValue.selection;
      final deleteRange = selection.isCollapsed
          ? TextRange(
              start: selection.start - 1,
              end: selection.end,
            )
          : selection;
      final deleteSelection = TextSelection(
        baseOffset: selection.baseOffset - 1,
        extentOffset: selection.extentOffset - 1,
      );

      if (!deleteRange.isValid) {
        return;
      }

      // valid the result
      onDelete(
        TextEditingDeltaDeletion(
          oldText: oldText,
          deletedRange: deleteRange,
          selection: deleteSelection,
          composing: TextRange.empty,
        ),
      );
    }
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    assert(
      contentInsertionConfiguration?.allowedMimeTypes
              .contains(content.mimeType) ??
          false,
    );
    contentInsertionConfiguration?.onContentInserted.call(content);
  }

  void _updateComposing(TextEditingDelta delta) {
    if (delta is TextEditingDeltaNonTextUpdate) {
      composingTextRange = delta.composing;
    } else {
      composingTextRange = composingTextRange != null &&
              composingTextRange!.start != -1 &&
              delta.composing.end != -1
          ? TextRange(
              start: composingTextRange!.start,
              end: delta.composing.end,
            )
          : delta.composing;
    }

    // solve the issue where the Chinese IME doesn't continue deleting after the input content has been deleted.
    if (PlatformExtension.isMacOS &&
        (composingTextRange?.isCollapsed ?? false)) {
      composingTextRange = TextRange.empty;
    }
  }
}

const String _whitespace = ' ';
const int _len = _whitespace.length;

extension on TextEditingValue {
  bool isValid() {
    if (selection.baseOffset < 0 ||
        selection.extentOffset < 0 ||
        selection.baseOffset > text.length ||
        selection.extentOffset > text.length) {
      return false;
    }
    return true;
  }

  // The IME will not report the backspace button if the cursor is at the beginning of the text.
  // Therefore, we need to add a transparent symbol at the start to ensure that we can capture the backspace event.
  TextEditingValue format() {
    final text = _whitespace + this.text;
    final selection = this.selection >> _len;

    TextRange composing = this.composing >> _len;
    final textLength = text.length;

    // check invalid composing
    if (composing.start > textLength || composing.end > textLength) {
      composing = TextRange.empty;
    }

    return TextEditingValue(
      text: text,
      selection: selection,
      composing: composing,
    );
  }

  TextEditingValue unformat() {
    return TextEditingValue(
      text: text << _len,
      selection: selection << _len,
      composing: composing << _len,
    );
  }
}

extension on TextEditingDelta {
  TextEditingDelta format() {
    if (this is TextEditingDeltaInsertion) {
      return (this as TextEditingDeltaInsertion).format();
    } else if (this is TextEditingDeltaDeletion) {
      return (this as TextEditingDeltaDeletion).format();
    } else if (this is TextEditingDeltaReplacement) {
      return (this as TextEditingDeltaReplacement).format();
    } else if (this is TextEditingDeltaNonTextUpdate) {
      return (this as TextEditingDeltaNonTextUpdate).format();
    }
    throw UnimplementedError();
  }
}

extension TextEditingDeltaInsertionExtension on TextEditingDeltaInsertion {
  TextEditingDeltaInsertion format() {
    final startWithSpace = oldText.startsWith(_whitespace);
    return TextEditingDeltaInsertion(
      oldText: startWithSpace ? oldText << _len : oldText,
      textInserted: textInserted,
      insertionOffset:
          startWithSpace ? insertionOffset - _len : insertionOffset,
      selection: startWithSpace ? selection << _len : selection,
      composing: startWithSpace ? composing << _len : composing,
    );
  }
}

extension on TextEditingDeltaDeletion {
  TextEditingDeltaDeletion format() {
    final startWithSpace = oldText.startsWith(_whitespace);
    return TextEditingDeltaDeletion(
      oldText: startWithSpace ? oldText << _len : oldText,
      deletedRange: startWithSpace ? deletedRange << _len : deletedRange,
      selection: startWithSpace ? selection << _len : selection,
      composing: startWithSpace ? composing << _len : composing,
    );
  }
}

extension on TextEditingDeltaReplacement {
  TextEditingDeltaReplacement format() {
    final startWithSpace = oldText.startsWith(_whitespace);
    return TextEditingDeltaReplacement(
      oldText: startWithSpace ? oldText << _len : oldText,
      replacementText: replacementText,
      replacedRange: startWithSpace ? replacedRange << _len : replacedRange,
      selection: startWithSpace ? selection << _len : selection,
      composing: startWithSpace ? composing << _len : composing,
    );
  }
}

extension on TextEditingDeltaNonTextUpdate {
  TextEditingDeltaNonTextUpdate format() {
    final startWithSpace = oldText.startsWith(_whitespace);
    return TextEditingDeltaNonTextUpdate(
      oldText: startWithSpace ? oldText << _len : oldText,
      selection: startWithSpace ? selection << _len : selection,
      composing: startWithSpace ? composing << _len : composing,
    );
  }
}

extension on TextSelection {
  TextSelection operator <<(int shiftAmount) => shift(-shiftAmount);

  TextSelection operator >>(int shiftAmount) => shift(shiftAmount);

  TextSelection shift(int shiftAmount) => TextSelection(
        baseOffset: max(0, baseOffset + shiftAmount),
        extentOffset: max(0, extentOffset + shiftAmount),
      );
}

extension on TextRange {
  TextRange operator <<(int shiftAmount) => shift(-shiftAmount);

  TextRange operator >>(int shiftAmount) => shift(shiftAmount);

  TextRange shift(int shiftAmount) => !isValid
      ? this
      : TextRange(
          start: max(0, start + shiftAmount),
          end: max(0, end + shiftAmount),
        );
}

extension on String {
  String operator <<(int shiftAmount) => shift(shiftAmount);

  String shift(int shiftAmount) {
    if (shiftAmount > length) {
      return '';
    }
    return substring(shiftAmount);
  }
}
