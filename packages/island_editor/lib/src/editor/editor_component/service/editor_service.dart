import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart' hide Overlay, OverlayEntry, OverlayState;

class EditorService {
  // selection service
  final selectionServiceKey = GlobalKey(
    debugLabel: 'island_editor_selection_service',
  );
  IslandSelectionService get selectionService {
    assert(
      selectionServiceKey.currentState != null &&
          selectionServiceKey.currentState is IslandSelectionService,
    );
    return selectionServiceKey.currentState! as IslandSelectionService;
  }

  // keyboard service
  final keyboardServiceKey = GlobalKey(
    debugLabel: 'island_editor_keyboard_service',
  );
  IslandKeyboardService? get keyboardService {
    if (keyboardServiceKey.currentState != null &&
        keyboardServiceKey.currentState is IslandKeyboardService) {
      return keyboardServiceKey.currentState! as IslandKeyboardService;
    }
    return null;
  }

  // render plugin service
  // late IslandRenderPlugin renderPluginService;
  late BlockComponentRendererService rendererService;

  // scroll service
  final scrollServiceKey = GlobalKey(
    debugLabel: 'island_editor_scroll_service',
  );
  IslandScrollService? get scrollService {
    if (scrollServiceKey.currentState != null &&
        scrollServiceKey.currentState is IslandScrollService) {
      return scrollServiceKey.currentState! as IslandScrollService;
    }
    return null;
  }
}
