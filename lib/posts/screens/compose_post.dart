import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/notifications/notification.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:auto_route/auto_route.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/discovery/widgets/pill_app_bar.dart';
import 'package:island/core/database.dart';
import 'package:island/core/theme.dart';
import 'package:island/posts/compose.dart';
import 'package:island/posts/compose_storage_db.dart';
import 'package:island/posts/screens/post_detail.dart';
import 'package:island/posts/widgets/compose/compose_card.dart';
import 'package:island/posts/widgets/compose/compose_settings_sheet.dart';
import 'package:island/posts/widgets/compose/compose_shared.dart';
import 'package:island/posts/widgets/compose/compose_state_utils.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/app_scaffold.dart' hide PageBackButton;
import 'package:island/shared/widgets/content/markdown.dart';
import 'package:island/shared/widgets/empty_state.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// A request to author a post somewhere other than the composer route.
///
/// Wide pages host the composer in a pane beside their content;
/// [ComposePaneHost] carries that pane's opener down to every reply, forward,
/// chain and edit affordance in the page, so those keep calling
/// [PostComposeScreen.show] exactly as they always have.
typedef ComposePaneRequest =
    Future<bool?> Function({
      SnPost? originalPost,
      PostComposeInitialState? initialState,
      SnPost? replyingTo,
      SnPost? forwardingTo,
      SnPost? chainingTo,
    });

/// Routes [PostComposeScreen.show] into the enclosing page's own pane.
///
/// Subtrees without a host keep pushing the composer route, so only pages that
/// opt in change where authoring happens.
class ComposePaneHost extends InheritedWidget {
  final ComposePaneRequest show;

  const ComposePaneHost({super.key, required this.show, required super.child});

  static ComposePaneHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComposePaneHost>();

  @override
  bool updateShouldNotify(ComposePaneHost oldWidget) => show != oldWidget.show;
}

/// Where a [PostComposePane] draws its own chrome.
enum PostComposeChrome {
  /// The composer route: a scaffold app bar over the page's own surface.
  page,

  /// A pane inside another page: a pill header over the content, inside the
  /// card the host draws around the pane.
  pane,
}

/// The post composer, as a page.
///
/// Authoring a post is a place you go, not a modal that interrupts the feed:
/// the composer owns the whole viewport, the keyboard and the window's own
/// back/close affordances, and a draft survives leaving it. [show] keeps the
/// push-and-await-result shape its callers already use.
@RoutePage()
class PostComposeScreen extends HookConsumerWidget {
  final SnPost? originalPost;
  final PostComposeInitialState? initialState;

  /// Reply, forward and chain targets that the caller resolved itself, used
  /// when [originalPost] carries only their ids — a draft saved on this device
  /// has no server payload to read them from.
  final SnPost? replyingTo;
  final SnPost? forwardingTo;
  final SnPost? chainingTo;

  const PostComposeScreen({
    super.key,
    this.originalPost,
    this.initialState,
    this.replyingTo,
    this.forwardingTo,
    this.chainingTo,
  });

  /// Opens the composer and resolves to `true` once a post was submitted.
  ///
  /// Editing an article or a blog is a different authoring surface entirely, so
  /// those two types are routed to their own pages instead.
  static Future<bool?> show(
    BuildContext context, {
    SnPost? originalPost,
    PostComposeInitialState? initialState,
    SnPost? replyingTo,
    SnPost? forwardingTo,
    SnPost? chainingTo,
  }) async {
    if (originalPost != null && originalPost.type == 1) {
      await context.router.push(ArticleEditRoute(id: originalPost.id));
      return true;
    }
    if (originalPost != null && originalPost.type == 2) {
      await context.router.push(BlogComposeRoute(originalPost: originalPost));
      return true;
    }

    final host = ComposePaneHost.maybeOf(context);
    if (host != null) {
      return host.show(
        originalPost: originalPost,
        initialState: initialState,
        replyingTo: replyingTo,
        forwardingTo: forwardingTo,
        chainingTo: chainingTo,
      );
    }

    return context.router.push<bool?>(
      PostComposeRoute(
        originalPost: originalPost,
        initialState: initialState,
        replyingTo: replyingTo,
        forwardingTo: forwardingTo,
        chainingTo: chainingTo,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PostComposePane(
      originalPost: originalPost,
      initialState: initialState,
      replyingTo: replyingTo,
      forwardingTo: forwardingTo,
      chainingTo: chainingTo,
      chrome: PostComposeChrome.page,
      onFinished: (submitted) {
        if (submitted && context.mounted) context.router.maybePop(true);
      },
    );
  }
}

/// The composer itself — draft lifecycle, form, preview and submit — with the
/// chrome left to whoever hosts it.
///
/// The route page wraps it in a scaffold; a wide page's pane wraps it in its
/// own floating card. Either way the host decides when the form goes away, and
/// leaving it always saves the draft.
class PostComposePane extends HookConsumerWidget {
  final SnPost? originalPost;
  final PostComposeInitialState? initialState;
  final SnPost? replyingTo;
  final SnPost? forwardingTo;
  final SnPost? chainingTo;
  final PostComposeChrome chrome;

  /// Told when the host's own dismiss affordance was used. `true` reports a
  /// submission; `false` a plain close.
  final ValueChanged<bool> onFinished;

  const PostComposePane({
    super.key,
    this.originalPost,
    this.initialState,
    this.replyingTo,
    this.forwardingTo,
    this.chainingTo,
    this.chrome = PostComposeChrome.page,
    required this.onFinished,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(composeStorageProvider);
    final prompted = useState(false);
    final showPreview = useState(false);
    final isDragging = useState(false);

    final fullPostData =
        originalPost != null &&
            ComposeLogic.serverBackedPostId(originalPost!) != null
        ? ref.watch(postProvider(originalPost!.id))
        : const AsyncValue.data(null);

    final effectiveOriginalPost = fullPostData.when(
      data: (fullPost) => fullPost ?? originalPost,
      loading: () => originalPost,
      error: (_, _) => originalPost,
    );

    final repliedPost =
        replyingTo ??
        initialState?.replyingTo ??
        effectiveOriginalPost?.repliedPost;
    final forwardedPost =
        forwardingTo ??
        initialState?.forwardingTo ??
        effectiveOriginalPost?.forwardedPost;
    final chainedPost =
        chainingTo ??
        initialState?.chainingTo ??
        effectiveOriginalPost?.chainedPost;

    final ComposeState state = useMemoized(
      () => ComposeLogic.createState(
        originalPost: effectiveOriginalPost,
        forwardedPost: forwardedPost,
        repliedPost: repliedPost,
        cloudDraftId: initialState?.cloudDraftId,
        postType: 0,
      ),
      [
        effectiveOriginalPost,
        forwardedPost,
        repliedPost,
        initialState?.cloudDraftId,
      ],
    );

    final stateNotifier = useMemoized(
      () => Listenable.merge([
        state.titleController,
        state.descriptionController,
        state.contentController,
        state.visibility,
        state.attachments,
        state.attachmentProgress,
        state.currentPublisher,
        state.submitting,
      ]),
      [state],
    );
    useListenable(stateNotifier);

    ComposeStateUtils.usePublisherInitialization(
      ref,
      state,
      preferredPublisher: chainedPost?.publisher,
    );
    ComposeStateUtils.useInitialStateLoader(state, initialState);
    ComposeStateUtils.useEditorBootstrap(state);

    // A composer page never traps the user: leaving saves the draft, whether
    // they pop the route or a submit dismisses it.
    useEffect(() {
      final database = ref.read(databaseProvider);
      return () {
        state.stopAutoSave();
        ComposeLogic.saveDraftWithoutUploadWithDatabase(database, state);
        ComposeLogic.dispose(state);
      };
    }, [state]);

    useEffect(() {
      final database = ref.read(databaseProvider);
      final isNewPost =
          effectiveOriginalPost == null &&
          repliedPost == null &&
          forwardedPost == null;
      if (isNewPost) {
        state.startAutoSave(
          (composeState) => ComposeLogic.saveDraftWithoutUploadWithDatabase(
            database,
            composeState,
          ),
        );
      }
      return null;
    }, [state, effectiveOriginalPost, repliedPost, forwardedPost]);

    useEffect(
      () {
        if (!prompted.value &&
            originalPost == null &&
            initialState?.replyingTo == null &&
            initialState?.forwardingTo == null) {
          final latestDraft = ref
              .read(composeStorageProvider.notifier)
              .getLatestDraftByType(0);
          if (latestDraft == null) return null;
          prompted.value = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showRestoreDialog(ref, state, latestDraft);
          });
        }
        return null;
      },
      [
        prompted.value,
        originalPost,
        initialState?.replyingTo,
        initialState?.forwardingTo,
      ],
    );

    Future<void> performSubmit() async {
      await ComposeLogic.submitInBackground(
        ref,
        state,
        originalPost: effectiveOriginalPost,
        repliedPost: repliedPost,
        forwardedPost: forwardedPost,
        chainedPost: chainedPost,
        autoChain: state.chainWithPrevious.value,
        onSubmitted: () {
          if (context.mounted) onFinished(true);
        },
      );
    }

    final title = effectiveOriginalPost != null
        ? 'postEditing'.tr()
        : 'postCompose'.tr();

    final previewToggle = IconButton(
      icon: Icon(showPreview.value ? Symbols.preview_off : Symbols.preview),
      onPressed: () => showPreview.value = !showPreview.value,
      tooltip: 'togglePreview'.tr(),
    );
    final settingsButton = IconButton(
      icon: const Icon(Symbols.settings),
      onPressed: () => showComposeSettingsSheet(context, state),
      tooltip: 'postSettings'.tr(),
    );
    final submitButton = ValueListenableBuilder<bool>(
      valueListenable: state.submitting,
      builder: (context, submitting, _) {
        return IconButton(
          onPressed: (submitting || state.currentPublisher.value == null)
              ? null
              : performSubmit,
          icon: submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  effectiveOriginalPost != null
                      ? Symbols.edit
                      : Symbols.upload,
                ),
          tooltip: effectiveOriginalPost != null
              ? 'postUpdate'.tr()
              : 'postPublish'.tr(),
        );
      },
    );
    final closeButton = IconButton(
      icon: const Icon(Symbols.close),
      onPressed: () => onFinished(false),
      tooltip: 'close'.tr(),
    );

    final form = Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showPreview.value
                ? _ComposePreviewPane(
                    key: const ValueKey('preview'),
                    state: state,
                  )
                : PostComposeForm(
                    key: const ValueKey('compose'),
                    originalPost: effectiveOriginalPost,
                    initialState: initialState,
                    providedState: state,
                    onSubmitRequest: performSubmit,
                  ),
          ),
        ),
      ],
    );

    return PopScope(
      child: DropTarget(
        onDragEntered: (_) => isDragging.value = true,
        onDragExited: (_) => isDragging.value = false,
        onDragDone: (details) {
          isDragging.value = false;
          ComposeLogic.addDroppedFiles(ref, state, details.files);
        },
        child: Stack(
          children: [
            switch (chrome) {
              PostComposeChrome.page => AppScaffold(
                // Solid page ground like every other content screen: the wide
                // default paints the scaffold transparent, which washes the
                // window backdrop's radial orbs through as a gradient.
                isNoBackground: false,
                appBar: AppBar(
                  leading: const AutoLeadingButton(),
                  title: Text(title),
                  actions: [
                    previewToggle,
                    settingsButton,
                    submitButton,
                  ],
                ),
                body: form,
              ),
              // A pane's host draws the card; the composer floats the same
              // glass pill the rest of the page uses, with its close, settings
              // and publish actions in it. The form starts one pill below so
              // its first field never hides under the header.
              PostComposeChrome.pane => Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: kPillAppBarHeight),
                    child: form,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: PillAppBar(
                      statusTop: 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).appBarTheme.titleTextStyle,
                            ),
                          ),
                          previewToggle,
                          settingsButton,
                          submitButton,
                          closeButton,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            },
            if (isDragging.value)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.9),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.upload_file,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const Gap(SolSpace.lg),
                          Text(
                            'dropFilesHere'.tr(),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestoreDialog(
    WidgetRef ref,
    ComposeState state,
    SnPost latestDraft,
  ) async {
    final restore = await showDialog<bool>(
      context: ref.context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: Text('restoreDraftTitle'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('restoreDraftMessage'.tr()),
            const Gap(SolSpace.lg),
            _buildCompactDraftPreview(context, latestDraft),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('no'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('yes'.tr()),
          ),
        ],
      ),
    );
    if (restore == true) {
      ComposeLogic.applyDraftToState(state, latestDraft);
    }
  }

  Widget _buildCompactDraftPreview(BuildContext context, SnPost draft) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(SolSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: SolRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Symbols.description,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const Gap(SolSpace.sm),
              Text(
                'draft'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const Gap(SolSpace.sm),
          if (draft.title?.isNotEmpty ?? false)
            Text(
              draft.title!,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (draft.content?.isNotEmpty ?? false)
            Text(
              draft.content!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (draft.attachments.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.attach_file,
                  size: 12,
                  color: theme.colorScheme.secondary,
                ),
                const Gap(SolSpace.xs),
                Text(
                  'postHasAttachments',
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontSize: 11,
                  ),
                ).plural(draft.attachments.length),
              ],
            ),
        ],
      ),
    );
  }
}

/// Renders the post exactly as the feed would, on the composer's own surface.
class _ComposePreviewPane extends HookWidget {
  final ComposeState state;

  const _ComposePreviewPane({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = useValueListenable(state.contentController);
    final attachments = useValueListenable(state.attachments);

    if (content.text.isEmpty && attachments.isEmpty) {
      return EmptyState(
        icon: Symbols.edit_note,
        title: 'previewEmpty'.tr(),
        compact: true,
      );
    }

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(SolSpace.lg),
            child: MarkdownTextContent(
              content: content.text,
              textStyle: theme.textTheme.bodyMedium,
              attachments: attachments
                  .where((e) => e.isOnCloud)
                  .map((e) => e.data as IDisplayableCloudFile)
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AttachmentStage { uploading, pending, approved, failed }

class _Attachment {
  const _Attachment({
    required this.localId,
    required this.bytes,
    required this.name,
    required this.mime,
    this.stage = _AttachmentStage.uploading,
    this.progress,
    this.fileId,
    this.error,
  });

  final String localId;
  final Uint8List bytes;
  final String name;
  final String mime;
  final _AttachmentStage stage;
  final double? progress;
  final String? fileId;
  final String? error;

  _Attachment copyWith({
    _AttachmentStage? stage,
    double? progress,
    String? fileId,
    String? error,
  }) => _Attachment(
    localId: localId,
    bytes: bytes,
    name: name,
    mime: mime,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    fileId: fileId ?? this.fileId,
    error: error ?? this.error,
  );
}

/// Composes a forum discussion. Only active boards are offered — applying to
/// open a board is a separate review flow left for later.
///
/// Attachments upload immediately and land in `pending`: until a reviewer
/// approves one it is shown as an "under review" placeholder and its URL is
/// never written into the post (decision 3).
class ForumComposeSheet extends HookConsumerWidget {
  const ForumComposeSheet({super.key, this.initialBoardId});

  /// Preselects the board when composing from inside a board page.
  final String? initialBoardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(contentBoardsProvider);
    final filesApi = ref.watch(filesApiProvider);
    final session = ref.read(lkmApiSessionProvider);
    final title = useTextEditingController();
    final body = useTextEditingController();
    final tags = useTextEditingController();
    final selected = useState<String?>(initialBoardId);
    final submitting = useState(false);
    final error = useState<String?>(null);
    final attachments = useState<List<_Attachment>>(const []);
    final theme = Theme.of(context);

    final activeBoards = (boards.value ?? const <LkmBoard>[])
        .where((board) => board.isActive)
        .toList(growable: false);
    final boardId = selected.value ??
        (activeBoards.isEmpty ? null : activeBoards.first.id);

    void update(String localId, _Attachment Function(_Attachment) change) {
      attachments.value = [
        for (final attachment in attachments.value)
          attachment.localId == localId ? change(attachment) : attachment,
      ];
    }

    void remove(String localId) {
      attachments.value = [
        for (final attachment in attachments.value)
          if (attachment.localId != localId) attachment,
      ];
    }

    Future<void> uploadAttachment(_Attachment attachment) async {
      try {
        final file = await session.run(
          () => filesApi.upload(
            bytes: attachment.bytes,
            originalName: attachment.name,
            mimeType: attachment.mime,
            onProgress: (progress) => update(
              attachment.localId,
              (current) => current.copyWith(progress: progress),
            ),
          ),
        );
        update(
          attachment.localId,
          (current) => current.copyWith(
            stage: file.isApproved
                ? _AttachmentStage.approved
                : _AttachmentStage.pending,
            fileId: file.id,
            progress: 1,
          ),
        );
      } catch (failure) {
        update(
          attachment.localId,
          (current) => current.copyWith(
            stage: _AttachmentStage.failed,
            error: '$failure',
          ),
        );
      }
    }

    Future<void> refreshAttachment(_Attachment attachment) async {
      final fileId = attachment.fileId;
      if (fileId == null) return;
      try {
        final file = await session.run(() => filesApi.file(fileId));
        if (file.isApproved) {
          update(
            attachment.localId,
            (current) => current.copyWith(stage: _AttachmentStage.approved),
          );
        } else if (file.isRejected) {
          remove(attachment.localId);
          if (context.mounted) showSnackBar('lkmUploadRejected'.tr());
        }
      } catch (_) {
        // Transient lookup failures keep the placeholder; the next tick retries.
      }
    }

    // The service announces a registered upload over the `upload` channel;
    // use it to refresh the placeholder immediately instead of waiting for
    // the next poll tick.
    ref.listen(realtimeEventsProvider, (_, next) {
      next.whenData((event) {
        if (event.event != 'upload_registered') return;
        final file = event.data['file'];
        final fileId = file is Map ? '${file['id'] ?? ''}' : '';
        if (fileId.isEmpty) return;
        for (final attachment in attachments.value) {
          if (attachment.fileId == fileId) {
            unawaited(refreshAttachment(attachment));
          }
        }
      });
    });

    // Reviews are human-paced: poll the pending rows instead of promising a
    // push channel (the WS only carries notifications).
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 5), (_) {
        for (final attachment in attachments.value) {
          if (attachment.stage == _AttachmentStage.pending &&
              attachment.fileId != null) {
            unawaited(refreshAttachment(attachment));
          }
        }
      });
      return timer.cancel;
    }, const []);

    Future<void> pickImages() async {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      for (final item in picked) {
        final bytes = await item.xFile.readAsBytes();
        if (bytes.isEmpty) continue;
        final attachment = _Attachment(
          localId: '${item.name}-${DateTime.now().microsecondsSinceEpoch}',
          bytes: bytes,
          name: item.name,
          mime: lookupMimeType(item.name) ?? 'application/octet-stream',
        );
        attachments.value = [...attachments.value, attachment];
        unawaited(uploadAttachment(attachment));
      }
    }

    Future<void> submit() async {
      final heading = title.text.trim();
      final content = body.text.trim();
      if (boardId == null ||
          heading.isEmpty ||
          content.isEmpty ||
          submitting.value) {
        return;
      }
      if (attachments.value.any(
        (attachment) => attachment.stage != _AttachmentStage.approved,
      )) {
        error.value = 'lkmUploadWaitReview'.tr();
        return;
      }
      submitting.value = true;
      error.value = null;
      try {
        final withImages = [
          content,
          for (final attachment in attachments.value)
            if (attachment.fileId != null)
              '![${attachment.name}](${filesApi.previewUrl(attachment.fileId!)})',
        ].join('\n\n');
        final id = await session.run(
          () => ref.read(contentApiProvider).createDiscussion(
            boardId: boardId,
            title: heading,
            content: withImages,
            tags: tags.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toSet()
                .toList(growable: false),
          ),
        );
        if (context.mounted) Navigator.of(context).pop(id);
      } catch (failure) {
        error.value = '$failure';
      } finally {
        submitting.value = false;
      }
    }

    return SheetScaffold(
      titleText: 'lkmComposeTitle'.tr(),
      heightFactor: 0.9,
      actions: [
        TextButton(
          onPressed: submitting.value ? null : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('lkmComposePublish'.tr()),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          boards.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (failure, _) => Text(
              '$failure',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            data: (_) => activeBoards.isEmpty
                ? Text(
                    'lkmComposeEmptyBoards'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: boardId,
                    decoration: InputDecoration(
                      labelText: 'lkmComposeBoard'.tr(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final board in activeBoards)
                        DropdownMenuItem(
                          value: board.id,
                          child: Text(board.title),
                        ),
                    ],
                    onChanged: (value) => selected.value = value,
                  ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: title,
            decoration: InputDecoration(
              labelText: 'postTitle'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 8,
            maxLines: 20,
            decoration: InputDecoration(
              labelText: 'postContent'.tr(),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tags,
            decoration: InputDecoration(
              labelText: 'tags'.tr(),
              hintText: 'tagsHint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: pickImages,
              icon: const Icon(Symbols.add_photo_alternate, size: 18),
              label: Text('lkmAddImage'.tr()),
            ),
          ),
          if (attachments.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in attachments.value)
                  _AttachmentTile(
                    attachment: attachment,
                    onRemove: () => remove(attachment.localId),
                  ),
              ],
            ),
          ],
          if (error.value != null) ...[
            const SizedBox(height: 12),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final _Attachment attachment;
  final VoidCallback onRemove;

  String _label() {
    switch (attachment.stage) {
      case _AttachmentStage.uploading:
        final progress = attachment.progress;
        return progress == null
            ? 'lkmUploadUploading'.tr()
            : '${(progress * 100).round()}%';
      case _AttachmentStage.pending:
        return 'lkmUploadPending'.tr();
      case _AttachmentStage.approved:
        return 'lkmUploadApproved'.tr();
      case _AttachmentStage.failed:
        return 'lkmUploadFailed'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            attachment.bytes,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              _label(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
    return Tooltip(
      message: attachment.error ?? attachment.name,
      child: SizedBox(width: 88, height: 88, child: tile),
    );
  }
}
