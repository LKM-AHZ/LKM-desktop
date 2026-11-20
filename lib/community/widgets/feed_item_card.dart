import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/timeline_api.dart';

/// One timeline entry: type, author, date, title and preview.
class FeedItemCard extends StatelessWidget {
  const FeedItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.compact = false,
  });

  final FeedItem item;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final preview = item.contentPreview.trim();

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 0 : 18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: compact ? 14 : 16,
          ),
          child: compact
              ? Row(
                  children: [
                    _TypeChip(type: item.itemType),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            [
                              item.authorName,
                              if (preview.isNotEmpty) preview,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      _formatDate(item.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeChip(type: item.itemType),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(item.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) => date.toIso8601String().substring(0, 10);

String _typeLabel(String type) => switch (type) {
  'discussion' => 'feedTypeDiscussion'.tr(),
  'article' => 'feedTypeArticle'.tr(),
  'column' => 'feedTypeColumn'.tr(),
  'qa' => 'feedTypeQa'.tr(),
  'project' => 'feedTypeProject'.tr(),
  'blog' => 'feedTypeBlog'.tr(),
  _ => type,
};

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (type) {
      'qa' => (
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
      ),
      'project' => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      'article' || 'column' => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      _ => (
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _typeLabel(type),
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
