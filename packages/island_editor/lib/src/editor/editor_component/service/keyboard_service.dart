import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [IslandKeyboardService] is responsible for processing shortcut keys,
///   like command, shift, control keys.
///
/// Usually, this service can be obtained by the following code.
/// ```dart
/// final keyboardService = editorState.service.keyboardService;
///
/// /** Simulates shortcut key input*/
/// keyboardService?.onKey(...);
///
/// /** Enables or disables this service */
/// keyboardService?.enable();
/// keyboardService?.disable();
/// ```
///
abstract class IslandKeyboardService {
  /// Enables IME shortcuts service.
  void enable();

  /// Disables IME shortcuts service.
  ///
  /// In some cases, if your custom component needs to monitor
  ///   keyboard events separately,
  ///   you can disable the keyboard service of flowy_editor.
  /// But you need to call the `enable` function to restore after exiting
  ///   your custom component, otherwise the keyboard service will fails.
  void disable({
    bool showCursor = false,
    UnfocusDisposition disposition = UnfocusDisposition.scope,
  });

  /// Enable the keyboard shortcuts
  void enableShortcuts();

  /// Disable the keyboard shortcuts
  void disableShortcuts();

  /// Closes the keyboard
  ///
  /// Used in mobile
  void closeKeyboard();

  /// The range the platform IME currently owns.
  ///
  /// While this is non-empty the IME — not the editor — owns that slice of
  /// text: it may still be replaced wholesale (dictation, CJK composition,
  /// autocorrect). Hosts that rewrite text in place must not touch it, or the
  /// next IME delta no longer lines up with the document.
  TextRange get composingTextRange;

  /// Enable the keyboard in mobile
  ///
  /// Used in mobile
  void enableKeyBoard(Selection selection);

  /// Register interceptor
  void registerInterceptor(IslandKeyboardServiceInterceptor interceptor);

  /// Unregister interceptor
  void unregisterInterceptor(IslandKeyboardServiceInterceptor interceptor);
}

/// [IslandKeyboardServiceInterceptor] is used to intercept the keyboard service.
///
/// If the interceptor returns `true`, the keyboard service will not perform
/// the built-in operation.
abstract class IslandKeyboardServiceInterceptor {
  /// Intercept insert operation
  Future<bool> interceptInsert(
    TextEditingDeltaInsertion insertion,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    return false;
  }

  /// Intercept delete operation
  Future<bool> interceptDelete(
    TextEditingDeltaDeletion deletion,
    EditorState editorState,
  ) async {
    return false;
  }

  /// Intercept replace operation
  Future<bool> interceptReplace(
    TextEditingDeltaReplacement replacement,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    return false;
  }

  /// Intercept non-text update operation
  Future<bool> interceptNonTextUpdate(
    TextEditingDeltaNonTextUpdate nonTextUpdate,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    return false;
  }

  /// Intercept perform action operation
  Future<bool> interceptPerformAction(
    TextInputAction action,
    EditorState editorState,
  ) async {
    return false;
  }

  /// Intercept floating cursor operation
  Future<bool> interceptFloatingCursor(
    RawFloatingCursorPoint point,
    EditorState editorState,
  ) async {
    return false;
  }
}
