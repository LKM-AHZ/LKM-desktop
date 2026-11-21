import 'dart:async';
import 'dart:developer' as developer;

import 'package:island/accounts/account_pod.dart';
import 'package:island/accounts/screens/progress.dart';
import 'package:auto_route/auto_route.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island/community/my_content_screen.dart'
    show myApplicationsProvider, myProjectsProvider, myQuestionsProvider;
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/points_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/core/database.dart';
import 'package:island/core/network.dart';
import 'package:island/core/services/responsive.dart';
import 'package:island/core/theme.dart';
import 'package:island/discovery/widgets/explore_card.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/api_page_list.dart';
import 'package:island/shared/widgets/sliver_floating_tab_bar.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// The profile's post/column tabs narrow the unified content read by type.
final _userContentProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmContentItem>, ({String userId, String type, int page})>((
      ref,
      key,
    ) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(contentApiProvider)
            .items(authorId: key.userId, contentType: key.type, page: key.page),
      );
    });

/// Resolves a username onto the stable user id the profile reads use.
final profileUserIdByNameProvider = FutureProvider.autoDispose
    .family<String, String>((ref, name) {
      final session = ref.watch(lkmApiSessionProvider);
      return session
          .run(() => UsersApi(session.client).profileByUsername(name))
          .then((profile) => profile.userId);
    });

/// Another account's page: profile plus the follow relation. The deep link
/// carries a username; the service reads by user id, so the name is resolved
/// first.
@RoutePage()
class AccountProfileScreen extends HookConsumerWidget {
  final String name;
  final String? id;

  const AccountProfileScreen({
    super.key,
    @PathParam('name') required this.name,
    @QueryParam('id') this.id,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explicitId = id;
    if (explicitId != null && explicitId.isNotEmpty) {
      return AccountProfileView(userId: explicitId);
    }
    final userId = ref.watch(profileUserIdByNameProvider(name));
    return userId.when(
      loading: () => AppScaffold(
        isNoBackground: false,
        appBar: AppBar(leading: const AutoLeadingButton()),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AppScaffold(
        isNoBackground: false,
        appBar: AppBar(leading: const AutoLeadingButton()),
        body: _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(profileUserIdByNameProvider(name)),
        ),
      ),
      data: (id) => AccountProfileView(userId: id),
    );
  }
}

/// One account's page by stable user id. Used by both the username route above
/// and the id-based community route.
class AccountProfileView extends HookConsumerWidget {
  const AccountProfileView({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(profile.value?.displayName ?? 'account'.tr()),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(userProfileProvider(userId)),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileBody extends HookConsumerWidget {
  const _ProfileBody({required this.profile});

  final LkmUserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = useMaterialTabController(initialLength: 4);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final me = ref.watch(lkmMeProvider).value;
    final isSelf = me != null && me.id == profile.userId;
    final leaderboard = ref.watch(pointsLeaderboardProvider('total')).value;
    final entry = leaderboard?.items
        .where((e) => e.userId == profile.userId)
        .firstOrNull;
    final balance = isSelf
        ? ref.watch(pointsBalanceProvider).value?.balance
        : entry?.balance;
    final follow = ref.watch(followProvider(profile.userId));
    final followNotifier = ref.read(followProvider(profile.userId).notifier);

    Future<void> toggleFollow() async {
      try {
        await followNotifier.toggle();
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      }
    }

    final infoCard = _ProfileInfoCard(
      profile: profile,
      balance: balance,
      entry: entry,
      follow: follow,
      showFollow: signedIn && !isSelf,
      onToggleFollow: toggleFollow,
    );

    // Pulled from the old account page: the segmented indicator keeps the four
    // content tabs readable without a divider line.
    final tabBar = Padding(
      padding: const EdgeInsets.only(top: SolSpace.sm, bottom: SolSpace.xs),
      child: TabBar(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: SolSpace.md),
        indicator: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(SolRadius.lg),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        labelColor: theme.colorScheme.onSecondaryContainer,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        splashBorderRadius: BorderRadius.circular(SolRadius.lg),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(text: 'authFlow.tabPosts'.tr()),
          Tab(text: 'authFlow.tabProjects'.tr()),
          Tab(text: 'authFlow.tabQuestions'.tr()),
          Tab(text: 'hub.tabColumns'.tr()),
        ],
      ),
    );

    final tabViews = <Widget>[
      _ProfilePosts(userId: profile.userId),
      _ProfileProjects(userId: profile.userId, isSelf: isSelf),
      _ProfileQuestions(userId: profile.userId),
      _ProfileColumns(userId: profile.userId),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWide = isWideScreen(context) && constraints.maxWidth >= 900;

        if (useWide) {
          return Row(
            spacing: SolSpace.sm,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: SolSpace.md,
                    top: kExploreCardGap,
                  ),
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverFloatingTabBar(
                        backgroundColor: theme.colorScheme.surface,
                        child: tabBar,
                      ),
                    ],
                    body: TabBarView(
                      controller: controller,
                      children: tabViews,
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: kExploreCardGap,
                    horizontal: SolSpace.md,
                  ),
                  child: infoCard,
                ),
              ),
            ],
          );
        }

        return NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SolSpace.md,
                  kExploreCardGap,
                  SolSpace.md,
                  0,
                ),
                child: infoCard,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProfileTabBarHeaderDelegate(
                child: tabBar,
                backgroundColor: theme.colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(controller: controller, children: tabViews),
        );
      },
    );
  }
}

/// Profile card shared by the narrow and the wide layouts.
class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({
    required this.profile,
    required this.balance,
    required this.entry,
    required this.follow,
    required this.showFollow,
    required this.onToggleFollow,
  });

  final LkmUserProfile profile;
  final int? balance;
  final LkmPointsLeaderboardEntry? entry;
  final AsyncValue<bool> follow;
  final bool showFollow;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryTitle = entry?.title;

    return ExploreCard(
      child: Padding(
        padding: const EdgeInsets.all(SolSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SolSpace.md,
          children: [
            _Avatar(
              userId: profile.userId,
              url: profile.avatar,
              name: profile.displayName,
              radius: 32,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: SolSpace.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SolSpace.sm,
                      vertical: SolSpace.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(SolRadius.chip),
                    ),
                    child: Text(
                      '@${profile.userId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: SolSpace.sm),
                  Text(
                    profile.role,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SolSpace.xs),
                  _ProfileInfoRow(
                    icon: Symbols.stars,
                    value: balance != null
                        ? '${'contribution.currentPoints'.tr()}: $balance'
                        : 'migration34.pointsUnknown'.tr(),
                  ),
                  if (entryTitle != null && entryTitle.isNotEmpty)
                    _ProfileInfoRow(
                      icon: Symbols.emoji_events,
                      value: 'contributionData.leaderboard.titles.$entryTitle'
                          .tr(),
                    ),
                ],
              ),
            ),
            if (showFollow)
              _FollowButton(follow: follow, onPressed: onToggleFollow),
          ],
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.follow, required this.onPressed});

  final AsyncValue<bool> follow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (follow.isLoading) {
      return const SizedBox(
        width: 96,
        height: 40,
        child: Center(child: LinearProgressIndicator()),
      );
    }
    return follow.value == true
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Symbols.check, size: 18),
            label: Text('following'.tr()),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Symbols.person_add, size: 18),
            label: Text('follow'.tr()),
          );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SolSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: SolSpace.xs + SolSpace.xxs),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ExploreCard(child: child);
}

class _ProfilePosts extends StatelessWidget {
  const _ProfilePosts({required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => ApiPageList<LkmContentItem>(
    key: ValueKey(userId),
    provider: (page) =>
        _userContentProvider((userId: userId, type: 'discussion', page: page)),
    itemBuilder: (context, item) => _ContentCard(
      child: ListTile(
        title: Text(item.title),
        subtitle: Text(
          [item.authorName, _formatDate(item.createdAt)].join(' · '),
        ),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => context.router.push(ContentDetailRoute(id: item.id)),
      ),
    ),
  );
}

class _ProfileProjects extends ConsumerWidget {
  const _ProfileProjects({required this.userId, required this.isSelf});

  final String userId;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(myProjectsProvider(userId));
    final AsyncValue<List<ProjectApplication>> applications = isSelf
        ? ref.watch(myApplicationsProvider)
        : const AsyncValue.data(<ProjectApplication>[]);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myProjectsProvider(userId));
        if (isSelf) ref.invalidate(myApplicationsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ...projects.when(
            loading: () => [const _Loading()],
            error: (error, _) => [_Message(text: '$error')],
            data: (items) => items.isEmpty
                ? [_Message(text: 'authFlow.empty'.tr())]
                : [
                    for (final project in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ContentCard(
                          child: ListTile(
                            title: Text(project.title),
                            subtitle: Text(project.summary),
                            trailing: const Icon(Symbols.chevron_right),
                            onTap: () => context.router.push(
                              ProjectDetailRoute(id: project.id),
                            ),
                          ),
                        ),
                      ),
                  ],
          ),
          if (isSelf)
            ...applications.when(
              loading: () => [const _Loading()],
              error: (error, _) => [_Message(text: '$error')],
              data: (items) => [
                for (final application in items)
                  if (application.status != 'approved')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ContentCard(
                        child: ListTile(
                          title: Text(application.title),
                          subtitle: Text(
                            '${application.status} · ${application.summary}',
                          ),
                        ),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileQuestions extends StatelessWidget {
  const _ProfileQuestions({required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => ApiPageList<QaQuestion>(
    key: ValueKey(userId),
    provider: (page) => myQuestionsProvider((authorId: userId, page: page)),
    itemBuilder: (context, question) => _ContentCard(
      child: ListTile(
        title: Text(question.title),
        subtitle: Text(
          '${question.status} · ${question.answerCount} ${'authFlow.answers'.tr()}',
        ),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => context.router.push(QaDetailRoute(id: question.id)),
      ),
    ),
  );
}

class _ProfileColumns extends StatelessWidget {
  const _ProfileColumns({required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => ApiPageList<LkmContentItem>(
    key: ValueKey(userId),
    provider: (page) =>
        _userContentProvider((userId: userId, type: 'column_post', page: page)),
    itemBuilder: (context, item) => _ContentCard(
      child: ListTile(
        title: Text(item.title),
        subtitle: Text(item.columnTitle),
        trailing: const Icon(Symbols.chevron_right),
        onTap: () => context.router.push(ContentDetailRoute(id: item.id)),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}

String _formatDate(DateTime date) {
  final iso = date.toIso8601String();
  return iso.substring(0, 10);
}

class _Avatar extends ConsumerWidget {
  const _Avatar({
    required this.userId,
    required this.url,
    required this.name,
    required this.radius,
  });

  final String? url;
  final String userId;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ProfilePictureWidget(
    imageUrl: userAvatarUrl(ref.watch(lkmServerUrlProvider), userId, url),
    fallbackName: name,
    radius: radius,
  );
}

/// Pinned strip used by the narrow layout; the wide layout hands its tabs to
/// [SliverFloatingTabBar] instead.
class _ProfileTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color backgroundColor;

  _ProfileTabBarHeaderDelegate({
    required this.child,
    required this.backgroundColor,
  });

  @override
  double get minExtent => kFloatingTabBarHeight;

  @override
  double get maxExtent => kFloatingTabBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: backgroundColor,
      elevation: 0,
      child: SizedBox(height: kFloatingTabBarHeight, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'userNotFound'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text('feedRetry'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Solar account lookup used by widgets that still render Solar identities.
/// Kept beside the merged profile page because its consumers already import
/// this file.
final accountProvider = FutureProvider.autoDispose.family<SnAccount, String>((
  ref,
  uname,
) async {
  if (uname == 'me') {
    final userInfo = ref.watch(userInfoProvider);
    if (userInfo.hasValue && userInfo.value != null) {
      return userInfo.value!;
    }
  }
  final database = ref.watch(databaseProvider);
  final cached = await database.getAccountByUsername(uname);
  if (cached != null) {
    unawaited(() async {
      try {
        final fresh = await ref
            .read(solarNetworkClientProvider)
            .accounts
            .getAccountByUsername(uname);
        await database.saveAccount(fresh, source: '/stargate/accounts/$uname');
      } catch (error, stackTrace) {
        developer.log(
          'Account endpoint returned an invalid profile: /stargate/accounts/$uname',
          name: 'AccountProvider',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
    return cached;
  }
  final client = ref.watch(solarNetworkClientProvider);
  final account = await client.accounts.getAccountByUsername(uname);
  await database.saveAccount(account, source: '/stargate/accounts/$uname');
  return account;
});
