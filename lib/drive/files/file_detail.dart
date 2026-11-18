import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/files_api.dart';
import 'package:island/posts/widgets/compose/post_item.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/content/image.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:url_launcher/url_launcher_string.dart';

final fileDetailProvider = FutureProvider.autoDispose.family<LkmFile, String>((
  ref,
  id,
) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(filesApiProvider).file(id));
});

final fileVersionsProvider = FutureProvider.autoDispose
    .family<List<LkmFile>, String>((ref, id) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(filesApiProvider).versions(id));
    });

/// The file detail surface: library metadata, inline preview, downloads and
/// version history, plus the source post when the file was opened from one.
@RoutePage()
class FileDetailScreen extends HookConsumerWidget {
  final String id;
  final String? heroTag;
  final SnPost? sourcePost;

  const FileDetailScreen({
    super.key,
    required this.id,
    this.heroTag,
    this.sourcePost,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(fileDetailProvider(id));
    final versions = ref.watch(fileVersionsProvider(id));
    final busy = useState(false);
    final session = ref.watch(lkmApiSessionProvider);
    final headers = session.cachedAccessToken == null
        ? null
        : {'Authorization': 'Bearer ${session.cachedAccessToken}'};

    Future<void> download(LkmFile value) async {
      busy.value = true;
      try {
        final api = ref.read(filesApiProvider);
        final info = await session.run(() => api.downloadUrl(value.id));
        if (info.isPresigned) {
          await launchUrlString(info.url, mode: LaunchMode.externalApplication);
        } else {
          final bytes = await session.run(() => api.downloadBytes(value.id));
          await FilePicker.saveFile(
            fileName: value.originalName,
            bytes: bytes,
            mimeType: value.mimeType,
          );
        }
        if (context.mounted) showSnackBar('library.downloadStarted'.tr());
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> preview(LkmFile value) async {
      busy.value = true;
      try {
        final extension = value.mimeType == 'application/pdf'
            ? 'pdf'
            : value.mimeType.startsWith('text/')
            ? 'txt'
            : value.mimeType == 'audio/mpeg'
            ? 'mp3'
            : value.mimeType == 'video/mp4'
            ? 'mp4'
            : null;
        if (extension == null) {
          throw StateError('libraryMore.previewUnsupported'.tr());
        }
        final bytes = await session.run(
          () => ref.read(filesApiProvider).downloadBytes(value.id),
        );
        final directory = await getTemporaryDirectory();
        final output = File(
          '${directory.path}/library-${DateTime.now().microsecondsSinceEpoch}.$extension',
        );
        await output.writeAsBytes(bytes);
        final result = await OpenFile.open(output.path);
        if (result.type != ResultType.done) {
          throw StateError(result.message);
        }
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> uploadVersion(LkmFile value) async {
      busy.value = true;
      try {
        await _upload(ref, versionOf: value.id);
        ref.invalidate(fileVersionsProvider(id));
        ref.invalidate(fileDetailProvider(id));
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('library.fileTitle'.tr()),
      ),
      body: file.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(text: '$error'),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (sourcePost != null) ...[
              PostItem(
                item: sourcePost!,
                padding: EdgeInsets.zero,
                isCompact: true,
                hideAttachments: true,
                isEmbedReply: false,
                isShowReference: false,
                isTextSelectable: false,
                isTranslatable: false,
              ),
              const Divider(height: 24),
            ],
            Row(
              children: [
                Icon(_iconFor(value.mimeType), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value.originalName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: value.status),
              ],
            ),
            const SizedBox(height: 12),
            _Info('library.category'.tr(), value.categoryName),
            _Info('library.size'.tr(), _size(value.size)),
            _Info('library.uploader'.tr(), value.uploaderName),
            _Info(
              'library.downloads'.tr(),
              '${value.downloadCount} / ${value.viewCount}',
            ),
            if (value.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(value.description),
            ],
            if (value.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in value.tags) Chip(label: Text(tag)),
                ],
              ),
            ],
            if (value.reviewComment != null &&
                value.reviewComment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${'library.reviewComment'.tr()}: ${value.reviewComment}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            if (value.isApproved && value.mimeType.startsWith('image/'))
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: UniversalImage(
                  uri: ref.read(filesApiProvider).previewUrl(value.id),
                  httpHeaders: headers,
                  fit: BoxFit.contain,
                ),
              ),
            if (value.isApproved && !value.mimeType.startsWith('image/'))
              OutlinedButton.icon(
                icon: const Icon(Icons.preview),
                label: Text('libraryMore.preview'.tr()),
                onPressed: busy.value ? null : () => preview(value),
              ),
            OutlinedButton.icon(
              onPressed: busy.value ? null : () => uploadVersion(value),
              icon: const Icon(Icons.upload_file),
              label: Text('libraryMore.uploadVersion'.tr()),
            ),
            FilledButton.icon(
              onPressed: busy.value || !value.isApproved
                  ? null
                  : () => download(value),
              icon: const Icon(Icons.download),
              label: Text('library.download'.tr()),
            ),
            const SizedBox(height: 20),
            Text(
              'library.versions'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            versions.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _Message(text: '$error'),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('library.noVersions'.tr()),
                    )
                  : Column(
                      children: [
                        for (final version in items)
                          ListTile(
                            onTap: () =>
                                context.router.push(FileDetailRoute(id: version.id)),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'v${version.version} · ${version.originalName}',
                            ),
                            subtitle: Text(_size(version.size)),
                            trailing: _StatusChip(status: version.status),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => Theme.of(context).colorScheme.primary,
      'rejected' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.tertiary,
    };
    return Chip(
      label: Text(status),
      labelStyle: TextStyle(color: color),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

IconData _iconFor(String mime) {
  if (mime.startsWith('image/')) return Symbols.image;
  if (mime.startsWith('audio/')) return Symbols.audio_file;
  if (mime.startsWith('video/')) return Symbols.video_file;
  if (mime.contains('pdf')) return Symbols.picture_as_pdf;
  if (mime.contains('zip') || mime.contains('tar')) return Symbols.folder_zip;
  return Symbols.description;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<void> _upload(
  WidgetRef ref, {
  String categoryId = '',
  String? versionOf,
}) async {
  final picked = await FilePicker.pickFile();
  if (picked == null) return;
  final bytes = await picked.xFile.readAsBytes();
  final mime =
      lookupMimeType(picked.name, headerBytes: bytes) ??
      'application/octet-stream';
  final api = ref.read(filesApiProvider);
  await ref
      .read(lkmApiSessionProvider)
      .run(
        () => versionOf == null
            ? api.upload(
                bytes: bytes,
                originalName: picked.name,
                mimeType: mime,
                categoryId: categoryId,
              )
            : api.uploadVersion(
                versionOf,
                bytes: bytes,
                originalName: picked.name,
                mimeType: mime,
              ),
      );
}
