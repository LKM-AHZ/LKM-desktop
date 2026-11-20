import 'package:island_editor/island_editor.dart';
import 'package:flutter/material.dart';

/// The items the editor's clipboard menus offer.
///
/// Kept in one place so the desktop right-click menu and the mobile floating
/// toolbar show the same set; only the presentation differs.
class SolarClipboardAction {
  const SolarClipboardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Builds the clipboard actions for the current selection.
///
/// Paste runs through [solarPaste] (the markdown-aware command with the host's
/// image/file hook) instead of Island Editor's plain-text `handlePaste`, so a paste
/// from the menu behaves exactly like Cmd/Ctrl+V.
List<SolarClipboardAction> solarClipboardActions(
  EditorState editorState, {
  required KeyEventResult Function(EditorState) solarPaste,
}) {
  final selection = editorState.selection;
  final l10n = IslandEditorL10n.current;
  final hasSelection = selection != null && !selection.isCollapsed;

  return [
    if (hasSelection)
      SolarClipboardAction(
        label: l10n.cut,
        icon: Icons.content_cut_rounded,
        onPressed: () => handleCut(editorState),
      ),
    if (selection != null)
      SolarClipboardAction(
        label: l10n.copy,
        icon: Icons.content_copy_rounded,
        onPressed: () => handleCopy(editorState),
      ),
    if (selection != null)
      SolarClipboardAction(
        label: l10n.paste,
        icon: Icons.content_paste_rounded,
        onPressed: () => solarPaste(editorState),
      ),
    SolarClipboardAction(
      label: l10n.cmdSelectAll,
      icon: Icons.select_all_rounded,
      onPressed: () => selectAllCommand.execute(editorState),
    ),
  ];
}

/// The desktop context menu.
///
/// Island Editor shows nothing on right-click unless the host provides a
/// [ContextMenuWidgetBuilder] — its own sample supplies one, the Solar editor
/// never did. This is that builder: a themed card of the clipboard actions
/// positioned at the pointer, clamped to stay on screen.
Widget buildSolarContextMenu(
  BuildContext context,
  Offset position,
  EditorState editorState,
  VoidCallback close, {
  required KeyEventResult Function(EditorState) solarPaste,
}) {
  final actions = solarClipboardActions(editorState, solarPaste: solarPaste);
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final screen = MediaQuery.sizeOf(context);
  const width = 180.0;
  const rowHeight = 38.0;
  final height = actions.length * rowHeight + 12;

  return Positioned(
    left: position.dx.clamp(4.0, (screen.width - width - 4).clamp(4.0, 1e6)),
    top: position.dy.clamp(4.0, (screen.height - height - 4).clamp(4.0, 1e6)),
    child: TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: 0.95 + 0.05 * value,
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final action in actions)
                  _SolarContextMenuRow(
                    action: action,
                    textStyle: textTheme.bodyMedium,
                    onPressed: () {
                      close();
                      action.onPressed();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SolarContextMenuRow extends StatefulWidget {
  const _SolarContextMenuRow({
    required this.action,
    required this.textStyle,
    required this.onPressed,
  });

  final SolarClipboardAction action;
  final TextStyle? textStyle;
  final VoidCallback onPressed;

  @override
  State<_SolarContextMenuRow> createState() => _SolarContextMenuRowState();
}

class _SolarContextMenuRowState extends State<_SolarContextMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        hoverColor: scheme.primary.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: _hovered
              ? scheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.action.icon,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.action.label,
                  style: widget.textStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mobile selection toolbar (long-press / drag selection).
///
/// Island Editor's `MobileFloatingToolbar` renders nothing on its own — the host
/// supplies the actual buttons. This is that builder: the platform's own
/// clipboard toolbar, so iOS gets its familiar callout and Android its
/// floating menu, with paste routed through [solarPaste].
Widget buildSolarMobileToolbar(
  BuildContext context,
  Offset anchor,
  VoidCallback close, {
  required EditorState editorState,
  required KeyEventResult Function(EditorState) solarPaste,
}) {
  final selection = editorState.selection;
  final hasSelection = selection != null && !selection.isCollapsed;

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: TextSelectionToolbarAnchors(primaryAnchor: anchor),
    buttonItems: [
      if (hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            close();
            handleCut(editorState);
          },
        ),
      if (selection != null)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            close();
            handleCopy(editorState);
          },
        ),
      if (selection != null)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            close();
            solarPaste(editorState);
          },
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          close();
          selectAllCommand.execute(editorState);
        },
      ),
    ],
  );
}
