import 'package:auto_route/auto_route.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/core/config.dart';
import 'package:island/core/debug_sheet.dart';
import 'package:island/core/services/responsive.dart';
import 'package:island/discovery/widgets/pill_app_bar.dart';
import 'package:island/notifications/notification.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/attention_modal.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/page_app_bar.dart';

@RoutePage()
class AccountListScreen extends StatelessWidget {
  const AccountListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (isWideScreen(context)) return const SizedBox.shrink();
    return const AccountFeatureWidget();
  }
}

@RoutePage()
class AccountScreen extends HookConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = isWideScreen(context);
    if (!isWide) {
      return AppBackground(isRoot: true, child: const AutoRouter());
    }

    // 宽屏的 master-detail：只有进入具体子页（设置/贴纸等）时才分栏。
    // 停在默认子路由时右侧本来什么都没有，分栏会留下大片空白——此时让账户页
    // 居中占满，与桌面端其它单栏页面一致。
    final inner = context.router.innerRouterOf<StackRouter>(AccountRoute.name);

    return AppBackground(
      isRoot: true,
      child: ListenableBuilder(
        listenable: inner == null
            ? context.router
            : Listenable.merge([context.router, inner]),
        builder: (context, _) {
          final hasDetail = (inner?.stack.length ?? 1) > 1;
          if (!hasDetail) {
            return Stack(
              children: [
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: const AccountFeatureWidget(),
                    ),
                  ),
                ),
                // 保活嵌套路由的控制器：否则回到默认子路由时 AutoRouter 被卸载，
                // 下一次 push 需要重新挂载整个子栈。
                const Offstage(child: AutoRouter()),
              ],
            );
          }
          return SafeArea(
            child: Row(
              children: [
                Flexible(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    child: const AccountFeatureWidget(isAside: true),
                  ),
                ),
                const VerticalDivider(width: 1),
                Flexible(flex: 3, child: const AutoRouter()),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The account page: LKM-service identity when signed in, the login entry
/// when not.
class AccountFeatureWidget extends HookConsumerWidget {
  final bool isAside;
  const AccountFeatureWidget({super.key, this.isAside = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(lkmMeProvider);
    if (!me.hasValue && me.isLoading) {
      return const AppScaffold(
        isNoBackground: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final account = me.value;
    if (account == null) return const _UnauthorizedAccountScreen();

    return _LkmAccountPage(account: account, isWide: isWideScreen(context));
  }
}

class _LkmAccountPage extends HookConsumerWidget {
  const _LkmAccountPage({required this.account, required this.isWide});

  final LkmAccount account;
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusTop = MediaQuery.paddingOf(context).top;
    final unread = ref.watch(notificationUnreadCountProvider).value ?? 0;
    final following = ref.watch(myFollowingProvider);
    final isDeveloperMode = ref.watch(developerModeProvider);

    Future<void> signOut() async {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text('lkmSignOutConfirm'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('confirm'.tr()),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      await ref.read(lkmApiSessionProvider).signOut();
      ref.invalidate(lkmMeProvider);
      ref.invalidate(myFollowingProvider);
    }

    return AppScaffold(
      isNoBackground: isWide,
      appBarOverContent: true,
      appBar: PillAppBar(
        statusTop: statusTop,
        child: Row(
          children: [
            const SolDrawerButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'account'.tr(),
                  style: Theme.of(context).appBarTheme.titleTextStyle,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: statusTop + kPillAppBarHeight,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          _ProfileHeader(
            account: account,
            onEdit: () =>
                context.router.push(const AccountUpdateProfileRoute()),
            onAvatarTap: () => context.router.push(
              AccountProfileRoute(name: '', id: account.id),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Symbols.notifications),
            ),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('notifications'.tr()),
            onTap: () => showAttentionModal(
              id: 'notifications',
              replaceIfExists: true,
              barrierDismissible: true,
              builder: (context, dismiss) =>
                  NotificationModal(onDismiss: dismiss),
            ),
          ),
          ListTile(
            leading: const Icon(Symbols.folder_open),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('library.title'.tr()),
            onTap: () => context.router.push(const LibraryRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.edit_document),
            title: Text('seriesEditor.title'.tr()),
            onTap: () => context.router.push(const SeriesEditorRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.apps),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('miniApps.title'.tr()),
            onTap: () => context.router.pushPath('/mini-apps'),
          ),
          ListTile(
            leading: const Icon(Symbols.article),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('authFlow.myContent'.tr()),
            onTap: () => context.router.push(const MyContentRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.group),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('authFlow.myFollowing'.tr()),
            onTap: () => context.router.push(const MyFollowRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.shield_person),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('accountSettings'.tr()),
            onTap: () => context.router.push(const AccountSettingsRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.settings),
            trailing: const Icon(Symbols.chevron_right),
            title: Text('appSettings'.tr()),
            onTap: () => context.router.push(const SettingsRoute()),
          ),
          if (isDeveloperMode)
            ListTile(
              leading: const Icon(Symbols.bug_report),
              trailing: const Icon(Symbols.chevron_right),
              title: Text('debugOptions'.tr()),
              onTap: () => toggleDebugOverlay(ref),
            ),
          // Admin surfaces are only offered to admin accounts; the panel then
          // signs in with its own cookie session (a bearer token cannot be
          // reused — every `/admin/*` endpoint reads `admin_session`).
          if (account.isAdmin)
            ListTile(
              leading: const Icon(Symbols.admin_panel_settings),
              trailing: const Icon(Symbols.chevron_right),
              title: Text('adminPanel.title'.tr()),
              onTap: () => context.router.push(AdminRoute()),
            ),
          ListTile(
            leading: const Icon(Symbols.logout),
            title: Text('logout'.tr()),
            onTap: signOut,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'following'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          following.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            data: (users) => users.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'lkmFollowingEmpty'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final user in users)
                        ListTile(
                          leading: _LkmAvatar(
                            userId: user.userId,
                            url: user.avatar,
                            name: user.displayName,
                            radius: 18,
                          ),
                          title: Text(user.displayName),
                          trailing: const Icon(Symbols.chevron_right),
                          onTap: () => context.router.push(
                            AccountProfileRoute(name: '', id: user.userId),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.account,
    required this.onAvatarTap,
    required this.onEdit,
  });

  final LkmAccount account;
  final VoidCallback onAvatarTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: _LkmAvatar(
              userId: account.id,
              url: account.avatar,
              name: account.displayName,
              radius: 40,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            account.displayName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '@${account.username}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (account.role.isNotEmpty)
                Chip(
                  label: Text(account.role),
                  visualDensity: VisualDensity.compact,
                ),
              if (account.accountLevel.isNotEmpty)
                Chip(
                  label: Text(account.accountLevel),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Symbols.edit, size: 18),
            label: Text('updateYourProfile'.tr()),
          ),
          if (account.email != null && account.email!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              account.email!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LkmAvatar extends ConsumerWidget {
  const _LkmAvatar({
    required this.url,
    required this.userId,
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

class _UnauthorizedAccountScreen extends HookConsumerWidget {
  const _UnauthorizedAccountScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeveloperMode = ref.watch(developerModeProvider);
    final statusTop = MediaQuery.paddingOf(context).top;

    return AppScaffold(
      appBarOverContent: true,
      appBar: PillAppBar(
        statusTop: statusTop,
        child: Row(
          children: [
            const SolDrawerButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'account'.tr(),
                  style: Theme.of(context).appBarTheme.titleTextStyle,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(top: statusTop + kPillAppBarHeight),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    elevation: 0,
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: () {
                        context.router.push(const RegisterRoute());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Symbols.person_add, size: 48),
                            const SizedBox(height: 8),
                            Text(
                              'createAccount'.tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('createAccountDescription'.tr()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    elevation: 0,
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: () {
                        context.router.push(LoginRoute());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Symbols.login, size: 48),
                            const SizedBox(height: 8),
                            Text(
                              'login'.tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('loginDescription'.tr()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        context.router.push(const AboutRoute());
                      },
                      iconSize: 18,
                      color: Theme.of(context).colorScheme.secondary,
                      icon: const Icon(Icons.info, fill: 1),
                      tooltip: 'about'.tr(),
                    ),
                    if (isDeveloperMode)
                      IconButton(
                        icon: const Icon(Icons.bug_report, fill: 1),
                        onPressed: () {
                          toggleDebugOverlay(ref);
                        },
                        iconSize: 18,
                        color: Theme.of(context).colorScheme.secondary,
                        tooltip: 'debugOptions'.tr(),
                      ),
                    IconButton(
                      onPressed: () {
                        context.router.push(const SettingsRoute());
                      },
                      icon: const Icon(Icons.settings, fill: 1),
                      iconSize: 18,
                      color: Theme.of(context).colorScheme.secondary,
                      tooltip: 'appSettings'.tr(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
