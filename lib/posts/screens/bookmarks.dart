import 'package:easy_localization/easy_localization.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/services/time.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/api_page_list.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The viewer's saved content, reading history and liked content. All three
/// read the same service-side summary shape, so one list widget serves them.
final favoriteContentProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmSavedItem>, int>((ref, page) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(contentApiProvider).favorites(page: page),
      );
    });

final readingHistoryProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmSavedItem>, int>((ref, page) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(contentApiProvider).history(page: page),
      );
    });

final likedContentProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmSavedItem>, int>((ref, page) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(contentApiProvider).likes(page: page),
      );
    });

@RoutePage()
class BookmarksScreen extends HookConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: AppScaffold(
        isNoBackground: false,
        appBar: AppBar(
          title: const Text('browseFootprints').tr(),
          bottom: TabBar(
            labelColor: Theme.of(context).appBarTheme.foregroundColor,
            unselectedLabelColor: Theme.of(
              context,
            ).appBarTheme.foregroundColor?.withOpacity(0.6),
            tabs: [
              Tab(
                icon: const Icon(Symbols.bookmark, size: 18),
                text: 'authFlow.tabFavorites'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.history, size: 18),
                text: 'authFlow.tabHistory'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.favorite, size: 18),
                text: 'reactedPosts'.tr(),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SavedTab(provider: favoriteContentProvider),
            _SavedTab(provider: readingHistoryProvider),
            _SavedTab(provider: likedContentProvider),
          ],
        ),
      ),
    );
  }
}

class _SavedTab extends StatelessWidget {
  const _SavedTab({required this.provider});

  final FutureProvider<ApiPage<LkmSavedItem>> Function(int) provider;

  @override
  Widget build(BuildContext context) {
    return ApiPageList<LkmSavedItem>(
      provider: provider,
      itemBuilder: (context, item) => ListTile(
        leading: const Icon(Symbols.article),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            item.contentType,
            if (item.at != null) item.at!.formatRelative(context),
          ].where((e) => e.isNotEmpty).join(' · '),
        ),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () =>
            context.router.push(ContentDetailRoute(id: item.contentId)),
      ),
    );
  }
}
