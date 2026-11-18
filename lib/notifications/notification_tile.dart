import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:island/community/feed_links.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/services/time.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:island/notifications/notification.dart';
import 'package:island/route.dart';
import 'package:island/route.gr.dart';
import 'package:island/core/services/deeplink_service.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:island/shared/widgets/content/markdown.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:relative_time/relative_time.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

class NotificationTile extends ConsumerWidget {
  final SnNotification notification;
  final double? avatarRadius;
  final EdgeInsets? contentPadding;
  final bool showImages;
  final bool compact;

  const NotificationTile({
    super.key,
    required this.notification,
    this.avatarRadius,
    this.contentPadding,
    this.showImages = true,
    this.compact = false,
  });

  IconData _getNotificationIcon(String topic) {
    switch (topic) {
      case 'post.replies':
        return Symbols.reply;
      case 'wallet.transactions':
        return Symbols.account_balance_wallet;
      case 'relationships.friends.request':
        return Symbols.person_add;
      case 'invites.chat':
        return Symbols.chat;
      case 'invites.realm':
        return Symbols.domain;
      case 'auth.login':
        return Symbols.login;
      case 'posts.new':
        return Symbols.post_add;
      case 'wallet.orders.paid':
        return Symbols.shopping_bag;
      case 'posts.reactions.new':
        return Symbols.add_reaction;
      case 'content_liked':
        return Symbols.favorite_rounded;
      case 'content_commented':
        return Symbols.mode_comment_rounded;
      case 'comment_replied':
        return Symbols.reply_rounded;
      case 'qa_answer_accepted':
        return Symbols.check_circle_rounded;
      case 'review_digest':
        return Symbols.assignment_rounded;
      case 'subscription_new_post':
      case 'post_watch_activity':
        return Symbols.post_add_rounded;
      case 'project_invited':
        return Symbols.group_add_rounded;
      case 'project_join_approved':
        return Symbols.check_circle_rounded;
      case 'project_join_rejected':
      case 'project_member_removed':
        return Symbols.group_remove_rounded;
      default:
        return Symbols.notifications;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pfp = notification.meta['pfp'] as String?;
    final images = notification.meta['images'] as List?;
    final imageIds = images?.cast<String>() ?? [];

    return ListTile(
      isThreeLine: true,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: pfp != null
          ? ProfilePictureWidget(
              fileId: pfp,
              radius: avatarRadius ?? (compact ? 16 : 20),
            )
          : CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              radius: avatarRadius ?? (compact ? 16 : 20),
              child: Icon(
                _getNotificationIcon(notification.topic),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: compact ? 16 : 20,
              ),
            ),
      title: Text(
        notification.title,
        style: compact
            ? Theme.of(context).textTheme.bodySmall
            : Theme.of(context).textTheme.titleMedium,
        maxLines: compact ? 1 : null,
        overflow: compact ? TextOverflow.ellipsis : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notification.subtitle.isNotEmpty && !compact)
            Text(notification.subtitle, maxLines: compact ? 3 : null).bold(),
          Row(
            spacing: 6,
            children: [
              Text(
                notification.createdAt.toLocal().formatSystem(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: compact ? 10 : 11),
              ),
              Text(
                '·',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                RelativeTime(context).format(notification.createdAt.toLocal()),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: compact ? 10 : 11),
              ),
            ],
          ).opacity(0.75).padding(bottom: compact ? 2 : 4),
          MarkdownTextContent(
            content: (compact && notification.body.length > 60)
                ? '${notification.body.substring(0, 60).replaceAll('\n', ' ')}...'
                : notification.body,
            textStyle:
                (compact
                        ? Theme.of(context).textTheme.bodySmall
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      fontSize: compact ? 11 : null,
                    ),
          ),
          if (showImages && imageIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: imageIds.map((imageId) {
                  return SizedBox(
                    width: 80,
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CloudImageWidget(
                        fileId: imageId,
                        aspectRatio: 1,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
      trailing: notification.viewedAt != null
          ? null
          : Container(
              width: compact ? 8 : 12,
              height: compact ? 8 : 12,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
      onTap: () {
        if (notification.meta['api_type'] != null) {
          unawaited(
            markNotificationsRead(ref, ids: [notification.id]),
          );
        }
        final rawUri = notification.meta['action_uri'] as String?;
        if (rawUri == null || rawUri.isEmpty) return;
        final feedTarget = parseFeedRoute(
          rawUri,
          serverHost: ref.read(lkmServerUrlProvider),
        );
        if (feedTarget != null) {
          dismissAttentionModal('notifications');
          context.router.push(switch (feedTarget.kind) {
            FeedRouteKind.content => ContentDetailRoute(id: feedTarget.id),
            FeedRouteKind.qa => QaDetailRoute(id: feedTarget.id),
            FeedRouteKind.project => ProjectDetailRoute(id: feedTarget.id),
            FeedRouteKind.file => FileDetailRoute(id: feedTarget.id),
            FeedRouteKind.treehole => const TreeholeRoute(),
          });
          return;
        }
        unawaited(handleActionUri(ref.read(routerProvider), rawUri));
        dismissAttentionModal('notifications');
      },
    );
  }
}
