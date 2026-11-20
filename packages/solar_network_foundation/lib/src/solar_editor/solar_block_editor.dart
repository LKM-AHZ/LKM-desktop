/// The configured Solar Network editor widget on top of Island Editor.
///
/// Everything opinionated about Solar lives here so all clients render the
/// same: standard Island Editor blocks with Solar text styles, the `/` slash
/// menu, a floating format toolbar, and the markdown bridge
/// ([solarMarkdownToDocument]/[solarDocumentToMarkdown]) through
/// [SolarEditorController].
///
/// Custom blocks registered through [SolarEditorConfig] round-trip through
/// markdown via their [NodeParser]s.
library;

import 'dart:async';

import 'package:island_editor/island_editor.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'blocks/solar_highlight_spoiler_syntaxes.dart';
import 'solar_context_menu.dart';
import 'solar_html_codec.dart';
import 'solar_paste_command.dart';

// The global image-src resolver Island Editor's image block consults.
export 'package:island_editor/island_editor.dart' show imageCustomResolver;
import 'solar_markdown_codec.dart';

/// Host-specific extension points. All optional.
class SolarEditorConfig {
  const SolarEditorConfig({
    this.blockComponentBuilders = const {},
    this.slashMenuItems = const [],
    this.markdownNodeParsers = const [],
    this.slashTriggerCharacter = '/',
    this.imageUrlResolver,
    this.onPickImage,
    this.onPaste,
    this.onEscape,
    this.placeholder = 'Type / for commands…',
  });

  /// Additional/overriding block builders merged over the standard set.
  /// Keys are Island Editor node types (e.g. `'my_callout'`).
  final Map<String, BlockComponentBuilder> blockComponentBuilders;

  /// Additional `/` menu items appended after the standard set.
  final List<SelectionMenuItem> slashMenuItems;

  /// Markdown encoders for custom block types (see [NodeParser]).
  final List<NodeParser> markdownNodeParsers;

  /// The character that opens the insert menu. Defaults to `/`.
  final String slashTriggerCharacter;

  /// Resolves an image block's `src` to a widget. Return null to fall back
  /// to Island Editor's default rendering (network/base64/local file).
  ///
  /// Use this for app-specific schemes — e.g. Solian's
  /// `solian://files/<id>` resolves through its cloud file widget; a plain
  /// `Image.network` would fail because the scheme is not http(s).
  final Widget? Function(BuildContext context, String src)? imageUrlResolver;

  /// When provided, the menu's image entry calls this instead of showing
  /// Island Editor's URL prompt — the host decides how to pick the file (e.g.
  /// its own cloud file picker) and returns the URL to insert, or null to
  /// cancel.
  final Future<String?> Function()? onPickImage;

  /// Fired on Cmd/Ctrl+V before the markdown text path runs. The host reads
  /// the platform clipboard itself (images, files — payloads the text path
  /// cannot represent), uploads/attaches what it found and returns `true` to
  /// consume the paste. Return `false` to fall through to markdown text.
  final Future<bool> Function()? onPaste;

  /// Fired when Escape is pressed while the editor holds the caret.
  ///
  /// The editor handles Escape before a sheet-level listener can see it, so
  /// without this the composer's "Esc keeps what was written and closes" would
  /// never fire. Return `true` when the host acted on it; `false` keeps the
  /// editor's own behaviour (clear the selection).
  final bool Function()? onEscape;

  /// Shown on empty, unfocused paragraphs.
  final String placeholder;
}

/// Owns an [EditorState] and mirrors it with markdown.
///
/// Markdown is what pages and posts persist; mail persists `text/html`, which
/// [htmlBody] encodes on demand from the same document. Changes flow editor →
/// markdown through [onChange]; external content enters through [setMarkdown]
/// or [setHTML].
class SolarEditorController {
  SolarEditorController({
    String? initialMarkdown,
    this.config = const SolarEditorConfig(),
  }) : _markdown = initialMarkdown ?? '' {
    editorState = _buildEditorState(initialMarkdown);
    _subscription = editorState.transactionStream.listen(_onTransaction);
  }

  late EditorState editorState;
  final SolarEditorConfig config;

  /// Fires whenever the document changed, with the fresh markdown.
  void Function(String markdown)? onChange;

  String _markdown;
  bool _markdownDirty = false;
  Timer? _onChangeDebounce;
  bool _disposed = false;
  StreamSubscription<EditorTransactionValue>? _subscription;

  /// The current document as markdown (the posted form for pages).
  String get markdown {
    if (_markdownDirty) {
      _markdown = solarDocumentToMarkdown(
        editorState.document,
        customParsers: config.markdownNodeParsers,
      );
      _markdownDirty = false;
    }
    return _markdown;
  }

  /// The document as the HTML a mail body is sent as. An empty document
  /// encodes to an empty string, so a composer that never wrote anything
  /// saves nothing.
  String get htmlBody => solarDocumentToHTML(editorState.document);

  /// Whether the document has no content at all (used for the
  /// empty-state placeholder).
  bool get isEmpty {
    for (final node in editorState.document.root.children) {
      final delta = node.delta;
      if (delta != null && delta.isNotEmpty) return false;
      if (node.children.isNotEmpty) return false;
    }
    return true;
  }

  EditorState _buildEditorState(String? initialMarkdown) {
    final state = initialMarkdown != null && initialMarkdown.trim().isNotEmpty
        ? EditorState(document: solarMarkdownToDocument(initialMarkdown))
        : EditorState.blank(withInitialText: true);
    return state;
  }

  /// The range the platform IME currently owns, or an empty range when the
  /// IME is idle. See [IslandKeyboardService.composingTextRange].
  TextRange get _composingTextRange =>
      editorState.service.keyboardService?.composingTextRange ??
      TextRange.empty;

  /// Fires whenever the document changed. Listenable form of [onChange]
  /// for widgets that only need to know *that* something changed (e.g.
  /// the empty-state placeholder).
  final ValueNotifier<int> contentChanged = ValueNotifier<int>(0);

  void _onTransaction(EditorTransactionValue value) {
    if (_disposed) return;
    final (time, _, _) = value;
    if (time != TransactionTime.after) return;
    // Annotate Solar syntaxes typed or inserted since the last decode; the
    // markdown codec only annotates what came in through a document load.
    //
    // Never while the platform IME owns text (dictation, CJK composition):
    // normalization rewrites the run text (`==hi==` → `hi`), and the IME keeps
    // tracking the text it handed over, so the next delta lands at the wrong
    // offset and the rest of the utterance is dropped. The markers are
    // annotated once the IME commits and this runs on a later transaction —
    // and the IME is then re-synced, because it still holds the longer text
    // and would otherwise keep sending offsets the document no longer has.
    if (_composingTextRange.isCollapsed) {
      final selection = editorState.selection;
      if (selection != null) {
        final node = editorState.getNodeAtPath(selection.end.path);
        if (node != null && solarNormalizeNode(node)) {
          final maxLen = node.delta?.length ?? 0;
          if (selection.start.offset > maxLen || selection.end.offset > maxLen) {
            editorState.updateSelectionWithReason(
              Selection(
                start: Position(
                  path: selection.start.path,
                  offset: selection.start.offset.clamp(0, maxLen),
                ),
                end: Position(
                  path: selection.end.path,
                  offset: selection.end.offset.clamp(0, maxLen),
                ),
              ),
              reason: SelectionUpdateReason.transaction,
            );
          }
        }
      }
    }
    _markdownDirty = true;
    contentChanged.value++;
    if (onChange != null) {
      _onChangeDebounce?.cancel();
      _onChangeDebounce = Timer(const Duration(milliseconds: 120), () {
        if (_disposed) return;
        final prev = _markdown;
        final next = markdown;
        if (next == prev) return;
        onChange?.call(next);
      });
    }
  }

  /// Replaces the document contents with [markdown]. History is cleared — an
  /// import is not an editing step.
  ///
  /// The swap happens *inside* the live [EditorState] rather than by
  /// constructing a new one: [SolarBlockEditor] builds its widget tree from
  /// the state it was handed, so replacing the object left the rendered
  /// editor showing the previous document while markdown/undo pointed at the
  /// new one — editing an existing post looked empty and clicks landed on
  /// detached nodes.
  void setMarkdown(String markdown) {
    _onChangeDebounce?.cancel();
    if (!_markdownDirty && markdown == _markdown) return;
    _markdown = markdown;
    _markdownDirty = false;

    final replacement = markdown.trim().isEmpty
        ? Document.blank(withInitialText: true)
        : solarMarkdownToDocument(markdown);
    _replaceDocument(replacement);
    contentChanged.value++;
  }

  /// Replaces the document with mail [html]. Same contract as [setMarkdown]:
  /// imports are not editing steps, so history is cleared.
  ///
  /// Loading mail through the HTML codec keeps the tags markdown cannot
  /// carry (inline colours, `<code>`, soft line breaks) instead of flattening
  /// the message to prose.
  void setHTML(String html) {
    _onChangeDebounce?.cancel();
    final replacement = html.trim().isEmpty
        ? Document.blank(withInitialText: true)
        : solarHTMLToDocument(html);
    _markdown = solarDocumentToMarkdown(
      replacement,
      customParsers: config.markdownNodeParsers,
    );
    _markdownDirty = false;
    _replaceDocument(replacement);
    contentChanged.value++;
  }

  /// Replaces every root child of the live document with [replacement]'s
  /// children, in one transaction, without recording undo history.
  void _replaceDocument(Document replacement) {
    final children = editorState.document.root.children;
    final transaction = editorState.transaction;
    if (children.isNotEmpty) {
      transaction.deleteNodesAtPath([0], children.length);
    }
    // One insert per node: the transaction inserts each node *before* the
    // node at the target path, so a batch appended every node ahead of the
    // previous one and loaded documents in reverse order.
    final nodes = replacement.root.children.toList(growable: false);
    for (var index = 0; index < nodes.length; index++) {
      transaction.insertNodes([index], [nodes[index].copyWith()]);
    }
    transaction.afterSelection = null;

    editorState.undoManager.undoStack.clear();
    editorState.undoManager.redoStack.clear();
    editorState.selection = null;
    editorState.apply(
      transaction,
      options: const ApplyOptions(recordUndo: false),
    );
  }

  /// Inserts [text] at the current selection (or into the last paragraph
  /// when nothing is selected). Used by toolbar placeholders and sticker
  /// picks.
  void insertText(String text) {
    final selection = editorState.selection;
    if (selection == null) {
      final last = editorState.document.root.children.lastOrNull;
      final delta = last?.delta;
      if (last == null || delta == null) return;
      final transaction = editorState.transaction
        ..insertText(last, delta.length, text);
      editorState.apply(transaction);
      return;
    }
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null) return;
    final transaction = editorState.transaction;
    if (selection.isCollapsed) {
      transaction.insertText(node, selection.end.offset, text);
    } else {
      transaction.replaceText(
        node,
        selection.start.offset,
        selection.end.offset - selection.start.offset,
        text,
      );
    }
    editorState.apply(transaction);
  }

  void dispose() {
    _disposed = true;
    _onChangeDebounce?.cancel();
    _subscription?.cancel();
    contentChanged.dispose();
    editorState.dispose();
  }
}

/// The Solar-styled editor surface.
class SolarBlockEditor extends StatefulWidget {
  const SolarBlockEditor({
    super.key,
    required this.controller,
    this.editable = true,
    this.shrinkWrap = false,
    this.focusNode,
    this.onKeyEvent,
  });

  final SolarEditorController controller;

  final bool editable;

  /// Render the editor inside a host scrollable (compose card) instead of
  /// its own scroll view.
  final bool shrinkWrap;

  final FocusNode? focusNode;

  /// Called for every hardware key event before the editor's own shortcuts.
  /// Return the result to short-circuit (e.g. a host autocomplete popup
  /// consuming arrows/enter), or null to let the editor handle it.
  final KeyEventResult? Function(KeyEvent event)? onKeyEvent;

  @override
  State<SolarBlockEditor> createState() => _SolarBlockEditorState();
}

class _SolarBlockEditorState extends State<SolarBlockEditor> {
  EditorScrollController? _scrollController;
  late final FocusNode _focusNode;

  EditorState get _editorState => widget.controller.editorState;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Island Editor's image block reads this global when building its widget;
    // keep it pointed at the current config's resolver.
    imageCustomResolver = widget.controller.config.imageUrlResolver == null
        ? null
        : (src) =>
              widget.controller.config.imageUrlResolver!(context, src);
    _scrollController ??= EditorScrollController(
      editorState: _editorState,
      shrinkWrap: widget.shrinkWrap,
    );
    // Register once the keyboard service exists; it is created during the
    // first frame, so retry until it is available.
    if (!_pasteInterceptorRegistered) {
      final keyboardService = _editorState.service.keyboardService;
      if (keyboardService != null) {
        keyboardService.registerInterceptor(_pasteInterceptor);
        _pasteInterceptorRegistered = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _pasteInterceptorRegistered) return;
          _editorState.service.keyboardService?.registerInterceptor(
            _pasteInterceptor,
          );
          _pasteInterceptorRegistered = true;
        });
      }
    }
  }

  final _pasteInterceptor = SolarMarkdownPasteInterceptor();
  bool _pasteInterceptorRegistered = false;

  @override
  void dispose() {
    if (_pasteInterceptorRegistered) {
      _editorState.service.keyboardService?.unregisterInterceptor(
        _pasteInterceptor,
      );
    }
    _scrollController?.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  BlockComponentConfiguration _configuration() {
    final placeholder = widget.controller.config.placeholder;
    return BlockComponentConfiguration(
      placeholderText: (node) => placeholder,
      placeholderTextStyle: (node, {textSpan}) => TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant
            .withValues(alpha: 0.6),
      ),
    );
  }

  Map<String, BlockComponentBuilder> _buildBuilders() {
    final config = _configuration();
    return {
      ...standardBlockComponentBuilderMap,
      ...widget.controller.config.blockComponentBuilders,
      // Solar styling on the text-bearing blocks.
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: config,
      ),
    };
  }

  /// The insert-menu trigger. Uses [SolarEditorConfig.slashTriggerCharacter]
  /// and appends a host-provided image entry when [SolarEditorConfig
  /// .onPickImage] is set.
  CharacterShortcutEvent _buildSlashTrigger() {
    final config = widget.controller.config;
    final items = _buildMenuItems();
    return customSlashCommand(
      items,
      shouldInsertSlash: false,
      singleColumn: true,
      style: _slashMenuStyle(context),
    ).copyWithCharacter(config.slashTriggerCharacter);
  }

  /// Island UI styling for the insert menu: theme surfaces, rounded card
  /// corners, primary highlight — instead of Island Editor's hardcoded light/dark
  /// defaults.
  SelectionMenuStyle _slashMenuStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SelectionMenuStyle(
      selectionMenuBackgroundColor: scheme.surfaceContainerHigh,
      selectionMenuItemTextColor: scheme.onSurface,
      selectionMenuItemIconColor: scheme.onSurfaceVariant,
      selectionMenuItemSelectedTextColor: scheme.onPrimary,
      selectionMenuItemSelectedIconColor: scheme.onPrimary,
      selectionMenuItemSelectedColor: scheme.primary,
      selectionMenuUnselectedLabelColor:
          scheme.onSurfaceVariant.withValues(alpha: 0.6),
      selectionMenuDividerColor: scheme.outlineVariant,
      selectionMenuLinkBorderColor: scheme.outline,
      selectionMenuInvalidLinkColor: scheme.error,
      selectionMenuButtonColor: scheme.primary,
      selectionMenuButtonBorderColor: scheme.outline,
      selectionMenuButtonIconColor: scheme.onPrimary,
      selectionMenuButtonTextColor: scheme.onPrimary,
      selectionMenuTabIndicatorColor: scheme.primary,
    );
  }

  List<SelectionMenuItem> _buildMenuItems() {
    final config = widget.controller.config;
    final items = List<SelectionMenuItem>.of(standardSelectionMenuItems);
    if (config.onPickImage != null) {
      final index = items.indexWhere(
        (item) => item.name.toLowerCase() == 'image',
      );
      final hostImageItem = SelectionMenuItem(
        getName: () => 'Image',
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'image',
          isSelected: isSelected,
          style: style,
        ),
        keywords: ['image', 'picture', 'photo', 'upload', 'cloud'],
        handler: (editorState, menuService, context) async {
          final url = await config.onPickImage!();
          if (url == null || url.isEmpty) return;
          await editorState.insertImageBlock(url);
        },
      );
      if (index >= 0) {
        items[index] = hostImageItem;
      } else {
        items.add(hostImageItem);
      }
    }
    items.addAll(config.slashMenuItems);
    return items;
  }

  /// The markdown-aware paste command, rebuilt with the current config so a
  /// menu paste behaves exactly like Cmd/Ctrl+V (including the host hook).
  late CommandShortcutEvent _pasteCommand;

  /// The standard shortcuts with Island Editor's plain-text paste replaced.
  ///
  /// Island Editor's `pastePlainText` splits the clipboard on newlines and builds
  /// plain paragraphs, so pasted markdown (`# Heading`, `**bold**`, `- item`)
  /// arrives literally. The replacement parses the clipboard as markdown into
  /// editor nodes instead, which also re-applies the Solar inline
  /// annotations through [solarMarkdownToDocument].
  List<CommandShortcutEvent> _buildCommandShortcuts() {
    _pasteCommand = buildSolarPasteCommand(
      onPaste: widget.controller.config.onPaste,
    );
    // Escape reaches the editor's own command before the host's sheet-level
    // listener ever sees it, so the host's close is wired here rather than at
    // the sheet.
    final onEscape = widget.controller.config.onEscape;
    final escapeOverride = onEscape == null
        ? null
        : CommandShortcutEvent(
            key: exitEditingCommand.key,
            command: exitEditingCommand.command,
            getDescription: () => IslandEditorL10n.current.cmdExitEditing,
            handler: (editorState) {
              if (!onEscape()) exitEditingCommand.handler(editorState);
              return KeyEventResult.handled;
            },
          );
    return [
      _pasteCommand,
      if (escapeOverride != null) escapeOverride,
      ...standardCommandShortcutEvents.where(
        (event) =>
            event.key != pasteCommand.key &&
            (escapeOverride == null || event.key != exitEditingCommand.key),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = EditorStyle.desktop(
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      textStyleConfiguration: TextStyleConfiguration(
        text: theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        href: TextStyle(color: theme.colorScheme.primary),
      ),
      padding: EdgeInsets.zero,
      textSpanDecorator: _solarSpanDecorator,
    );

    final editor = IslandEditor(
      editorState: _editorState,
      editable: widget.editable,
      shrinkWrap: widget.shrinkWrap,
      focusNode: _focusNode,
      editorScrollController: _scrollController,
      editorStyle: style,
      blockComponentBuilders: _buildBuilders(),
      characterShortcutEvents: [
        _buildSlashTrigger(),
        ...standardCharacterShortcutEvents.where(
          (event) => event.character != '/' || event.key == 'slash',
        ),
      ],
      commandShortcutEvents: _buildCommandShortcuts(),
      // Right-click: Island Editor renders nothing unless the host supplies a
      // builder, so the Solar menu (cut/copy/paste/select-all) is passed here.
      contextMenuBuilder: (context, position, editorState, close) =>
          buildSolarContextMenu(
            context,
            position,
            editorState,
            close,
            solarPaste: (state) => _pasteCommand.handler(state),
          ),
    );

    // Host key hook (autocomplete popups) runs before the editor's own
    // shortcut handling.
    Widget keyed(Widget child) {
      final onKeyEvent = widget.onKeyEvent;
      if (onKeyEvent == null) return child;
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          final result = onKeyEvent(event);
          return result ?? KeyEventResult.ignored;
        },
        child: child,
      );
    }

    final isMobile =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    // Mobile: long-press/drag selection opens the platform clipboard toolbar.
    // Island Editor only raises it when the host supplies the items, so the Solar
    // builder (cut/copy/paste/select-all) is wired here.
    // Desktop: the floating format toolbar; right-click is handled by
    // [contextMenuBuilder] on the editor itself.
    final content = isMobile
        ? MobileFloatingToolbar(
            editorState: _editorState,
            editorScrollController: _scrollController!,
            floatingToolbarHeight: 44,
            toolbarBuilder: (context, anchor, close) => buildSolarMobileToolbar(
              context,
              anchor,
              close,
              editorState: _editorState,
              solarPaste: (state) => _pasteCommand.handler(state),
            ),
            child: keyed(editor),
          )
        : FloatingToolbar(
            items: [
              paragraphItem,
              ...headingItems,
              ...markdownFormatItems,
              quoteItem,
              bulletedListItem,
              numberedListItem,
              linkItem,
            ],
            editorState: _editorState,
            editorScrollController: _scrollController!,
            textDirection: Directionality.of(context),
            child: keyed(editor),
          );

    // Empty-state placeholder: the built-in per-block placeholder only
    // shows while the block is being edited; this overlay covers the
    // empty + unfocused case with a tappable hint. Keeping a stable Stack
    // and passing [content] as [ListenableBuilder.child] prevents the editor
    // subtree from reparenting or rebuilding on selection changes.
    return ListenableBuilder(
      listenable: Listenable.merge([
        _editorState.selectionNotifier,
        widget.controller.contentChanged,
      ]),
      child: content,
      builder: (context, child) {
        final showHint =
            widget.controller.isEmpty && _editorState.selection == null;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showHint ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.controller.config.placeholder,
                      style: (theme.textTheme.bodyMedium ?? const TextStyle())
                          .copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Renders Solar's custom inline attributes (mention, highlight, spoiler,
  /// sticker) inside rich text spans.
  InlineSpan _solarSpanDecorator(
    BuildContext context,
    Node node,
    int index,
    TextInsert text,
    TextSpan before,
    TextSpan after,
  ) {
    final attributes = text.attributes;
    if (attributes == null || attributes.isEmpty) return after;

    final theme = Theme.of(context);
    TextStyle? style;

    final highlight = attributes[SolarInlineKeys.highlight] == true;
    final spoiler = attributes[SolarInlineKeys.spoiler] == true;
    final mention = attributes[SolarInlineKeys.mention];
    final sticker = attributes[SolarInlineKeys.sticker];

    final base = (style ?? after.style) ?? const TextStyle();
    if (highlight) {
      style = base.copyWith(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      );
    }
    if (spoiler) {
      style = base.copyWith(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: Colors.transparent,
      );
    }
    if (mention is String || sticker is String) {
      style = base.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      );
    }
    if (style == null) return after;
    return TextSpan(text: after.text, style: style, children: after.children);
  }
}

extension on CharacterShortcutEvent {
  CharacterShortcutEvent copyWithCharacter(String character) {
    return CharacterShortcutEvent(
      key: key,
      character: character,
      handler: handler,
    );
  }
}

extension on EditorState {
  /// Inserts an image block for [url] after the current selection.
  Future<void> insertImageBlock(String url) async {
    final node = imageNode(url: url);
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      // Append at the end.
      final path = document.root.children.lastOrNull?.path ?? [0];
      final transaction = this.transaction
        ..insertNode(path, node)
        ..afterSelection = Selection.collapsed(
          Position(path: [...path, 0], offset: 0),
        );
      await apply(transaction);
      return;
    }
    final currentNode = getNodeAtPath(selection.end.path);
    if (currentNode == null) return;
    final nextPath = [...currentNode.path]..last += 1;
    final transaction = this.transaction
      ..insertNode(nextPath, node);
    await apply(transaction);
  }
}
