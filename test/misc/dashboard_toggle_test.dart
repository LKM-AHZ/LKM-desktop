import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:island/core/theme.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/timeline_api.dart';
import 'package:island/accounts/widgets/account/friends_overview.dart';
import 'package:island/posts/screens/post_detail.dart';
import 'package:island/posts/widgets/compose/post_featured.dart';
import 'package:island/community/widgets/feed_item_card.dart';
import 'package:island/shared/widgets/workbench_header.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/accounts/account_pod.dart';
import 'package:island/accounts/account_screen.dart';
import 'package:island/accounts/screens/me/account_qr.dart';
import 'package:island/core/config.dart';
import 'package:island/discovery/explore.dart';
import 'package:island/misc/dashboard/dash.dart';
import 'package:island/misc/dashboard/community_cards.dart';
import 'package:island/accounts/screens/progress.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/misc/tabs_screen.dart';
import 'package:island/route.dart';
import 'package:island/route.gr.dart';
import 'package:island/wallets/wallet.dart';
import 'package:native_glass_navbar/native_glass_navbar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

/// Signed-out stub: the real notifier reads the token store and hits the
/// network, which these landing-screen checks must not depend on.
class _SignedOutUserInfo extends UserInfoNotifier {
  @override
  Future<SnAccount?> build() async => null;
}

class _WorkbenchFeed extends CommunityFeedNotifier {
  @override
  Future<CommunityFeedState> build() async => CommunityFeedState(
    mode: 'hot',
    items: [
      for (final (index, title) in [
        '关于可积系统 Lax 对构造的一个疑问，希望得到严格推导',
        'Transformer 在偏微分方程数值解中的可解释性边界在哪里？',
        '招募：面向高中生的开源物理实验数据平台',
        '《线性代数及其应用》课程讲义与习题解答',
        '如何为计算化学的分子动力学结果写一份可复现的实验报告？',
        '复变函数中支点与留数定理的几何直观',
      ].indexed)
        FeedItem(
          itemType: ['qa', 'discussion', 'project', 'article'][index % 4],
          id: '$index',
          authorName: ['林间', 'Eptazocine', 'Jason'][index % 3],
          title: title,
          contentPreview: '分享思路、记录进展，与社区一起探索新的可能',
          createdAt: DateTime(2026, 11, 20),
          sortScore: 0,
        ),
    ],
  );
}

late AppRouter _router;
late ProviderContainer _container;

/// Boots the real router at `/` with a real `SharedPreferences` store, so the
/// dashboard settings are read exactly as the app reads them.
Future<void> _pumpApp(
  WidgetTester tester,
  Map<String, Object> prefsValues, {
  bool preview = false,
}) async {
  final locale = preview ? const Locale('zh', 'CN') : const Locale('en', 'US');
  SharedPreferences.setMockInitialValues({
    kAppDashboardConfig: jsonEncode({
      'vertical_layouts': [],
      'horizontal_layouts': [],
      'show_clock_and_countdown': false,
      'show_search_bar': true,
    }),
    ...prefsValues,
  });
  final prefs = await SharedPreferences.getInstance();

  _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      userInfoProvider.overrideWith(_SignedOutUserInfo.new),
      dashboardEntriesProvider.overrideWith((ref, kind) async => []),
      if (preview) ...[
        communityFeedProvider.overrideWith(_WorkbenchFeed.new),
        friendsOverviewProvider.overrideWith((ref) async => []),
        featuredPostsProvider.overrideWith((ref) async => []),
        contentBoardsProvider.overrideWith(
          (ref) async => [
            for (final title in ['基础学科', '应用学科', '语言学习', '项目与协作', '资料与文献'])
              LkmBoard(id: title, slug: title, title: title, status: 'active'),
          ],
        ),
      ],
      pointsLeaderboardProvider.overrideWith(
        (ref, period) async => const ApiPage.empty(),
      ),
    ],
  );
  addTearDown(_container.dispose);

  final router = _container.read(routerProvider);
  _router = router;
  final config = router.config();

  // Real async room so EasyLocalization's file-backed load completes.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container,
        child: EasyLocalization(
          supportedLocales: [locale],
          startLocale: locale,
          path: 'assets/i18n',
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig: config,
              debugShowCheckedModeBanner: false,
              theme: preview ? _container.read(themeProvider).light : null,
              locale: locale,
              supportedLocales: [locale],
              localizationsDelegates: [
                ...context.localizationDelegates,
                ...GlobalMaterialLocalizations.delegates,
                flutter_localizations.GlobalMaterialLocalizations.delegate,
                flutter_localizations.GlobalCupertinoLocalizations.delegate,
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();

  final state = await config.routeInformationParser!
      .parseRouteInformationWithDependencies(
        RouteInformation(uri: Uri.parse('/')),
        tester.element(find.byType(MaterialApp)),
      );
  await config.routerDelegate.setNewRoutePath(state);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Tears the tree down and lets provider-scheduled timers fire, so the binding
/// sees none pending.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  _container.dispose();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('light workbench keeps navigation and discussion rows usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (family, assets) in {
      'Nunito': [
        'assets/fonts/Nunito-Regular.ttf',
        'assets/fonts/Nunito-Bold.ttf',
      ],
      'NotoSansSC': [
        'assets/fonts/NotoSansSC-Regular.otf',
        'assets/fonts/NotoSansSC-Bold.otf',
      ],
      'packages/material_symbols_icons/MaterialSymbolsRounded': [
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
      ],
      'packages/material_symbols_icons/MaterialSymbolsOutlined': [
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
      ],
    }.entries.map((entry) => (entry.key, entry.value))) {
      final loader = FontLoader(family);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
    await _pumpApp(tester, const {
      'app_dashboard_enabled': false,
    }, preview: true);
    await tester.tap(find.byIcon(Symbols.menu_rounded).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('社区板块'), findsOneWidget);
    expect(find.byType(FeedItemCard), findsNWidgets(6));
    expect(
      tester.getSize(find.byType(FeedItemCard).first).height,
      lessThan(100),
    );
    final brandContext = tester.element(find.byType(WorkbenchBrand));
    expect(
      Theme.of(brandContext).colorScheme.surface.computeLuminance(),
      greaterThan(0.8),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/workbench_light.png'),
    );

    // The directory yields space as the window narrows; rows and toolbar fit.
    tester.view.physicalSize = const Size(980, 720);
    await tester.pumpAndSettle();
    expect(find.text('社区板块'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Symbols.search).last);
    await tester.pumpAndSettle();
    expect(_router.currentPath, '/search');
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));

  group('app settings', () {
    Future<(ProviderContainer, SharedPreferences)> makeContainer(
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return (container, prefs);
    }

    test('the dashboard is enabled unless turned off', () async {
      final (container, _) = await makeContainer(const {});
      expect(container.read(appSettingsProvider).dashboardEnabled, isTrue);

      final (offContainer, _) = await makeContainer(const {
        kAppDashboardEnabled: false,
      });
      expect(offContainer.read(appSettingsProvider).dashboardEnabled, isFalse);
    });

    test(
      'turning the dashboard off never leaves it as the start screen',
      () async {
        final (container, prefs) = await makeContainer(const {
          kAppDefaultScreen: 'dashboard',
        });

        container.read(appSettingsProvider.notifier).setDashboardEnabled(false);

        expect(prefs.getBool(kAppDashboardEnabled), isFalse);
        expect(prefs.getString(kAppDefaultScreen), 'explore');
        expect(container.read(appSettingsProvider).defaultScreen, 'explore');
      },
    );

    test('turning the dashboard off keeps an unrelated start screen', () async {
      final (container, prefs) = await makeContainer(const {
        kAppDefaultScreen: 'chat',
      });

      container.read(appSettingsProvider.notifier).setDashboardEnabled(false);

      expect(prefs.getString(kAppDefaultScreen), 'chat');
      expect(container.read(appSettingsProvider).defaultScreen, 'chat');
    });
  });

  testWidgets('dashboard on by default: / renders the dashboard', (
    tester,
  ) async {
    await _pumpApp(tester, const {});

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardGrid), findsOneWidget);
    expect(find.byType(ExploreScreen), findsNothing);
    // The dashboard is one of the ten navigation destinations.
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 9);

    await _teardown(tester);
  });

  testWidgets('dashboard disabled: / lands on explore and drops the tab', (
    tester,
  ) async {
    await _pumpApp(tester, const {'app_dashboard_enabled': false});

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardGrid), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(_router.currentPath, '/explore');
    // One fewer navigation destination: the dashboard is not reachable.
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 8);

    await _teardown(tester);
  });

  testWidgets('long-pressing Explore opens its entrance sheet', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {'app_dashboard_enabled': false});

    expect(find.byType(NavigationBar), findsOneWidget);
    // Long-pressing the Explore destination no longer opens the entrance sheet;
    // the entrances live behind the More action button in Explore's header.
    await tester.longPress(find.byIcon(Symbols.explore_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Symbols.category), findsNothing);

    await tester.tap(find.byIcon(Symbols.more_vert));
    await tester.pumpAndSettle();

    // The entrances that used to sit in the long-press sheet now live in
    // Explore's top-right action sheet.
    expect(find.byIcon(Symbols.category), findsOneWidget);
    expect(find.byIcon(Symbols.shuffle), findsOneWidget);
    expect(find.byIcon(Symbols.footprint), findsOneWidget);
    expect(find.byIcon(Symbols.drafts), findsOneWidget);

    // The draft box entry resolves: it is a top-level route.
    await tester.tap(find.byIcon(Symbols.drafts));
    await tester.pumpAndSettle();
    expect(_router.currentPath, '/drafts');

    await _teardown(tester);
  });

  testWidgets('the footprints entrance pushes the bookmarks page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {'app_dashboard_enabled': false});
    await tester.tap(find.byIcon(Symbols.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Symbols.footprint));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_router.currentPath, '/bookmarks');

    await _teardown(tester);
  });

  testWidgets('the Explore header action opens its entrance sheet on wide', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {'app_dashboard_enabled': false});
    expect(find.byType(NavigationRail), findsOneWidget);

    final railExplore = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.byIcon(Symbols.explore_rounded),
    );
    expect(railExplore, findsOneWidget);
    await tester.longPress(railExplore);
    await tester.pumpAndSettle();
    expect(find.byIcon(Symbols.category), findsNothing);

    await tester.tap(find.byIcon(Symbols.more_vert));
    await tester.pumpAndSettle();

    expect(find.byIcon(Symbols.category), findsOneWidget);
    expect(find.byIcon(Symbols.shuffle), findsOneWidget);
    expect(find.byIcon(Symbols.footprint), findsOneWidget);
    expect(find.byIcon(Symbols.drafts), findsOneWidget);

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the menu expands the rail instead of opening a drawer', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A rail the user trimmed to two entries: the drawer's job here is to
    // reach what the collapsed rail dropped.
    await _pumpApp(tester, const {
      'app_dashboard_enabled': false,
      'app_rail_nav_layouts': '["explore","chat"]',
    });

    NavigationRail rail() =>
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail().destinations.length, 2);
    expect(rail().extended, isFalse);
    // The wide layout carries no drawer at all.
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(NavigationDrawer), findsNothing);

    await tester.tap(find.byIcon(Symbols.menu_rounded).first);
    await tester.pumpAndSettle();

    // Expanded: the whole reachable set, in rail order with the rest behind.
    expect(rail().extended, isTrue);
    expect(rail().destinations.length, 8);
    expect(find.byType(Drawer), findsNothing);

    // A destination only the expanded rail offers is selectable, and picking
    // one navigates without collapsing the rail.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Wallet'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_router.currentPath, '/wallet');
    expect(rail().extended, isTrue);
    expect(rail().destinations.length, 8);

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'the Explore header action opens its entrance sheet on the wide rail',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, const {'app_dashboard_enabled': false});
      await tester.tap(find.byIcon(Symbols.menu_rounded).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );

      final railExplore = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Explore'),
      );
      expect(railExplore, findsOneWidget);
      await tester.tap(railExplore);
      await tester.pumpAndSettle();

      // The entrances live behind the More action button in Explore's header.
      await tester.tap(find.byIcon(Symbols.more_vert));
      await tester.pumpAndSettle();

      expect(find.byIcon(Symbols.category), findsOneWidget);
      expect(find.byIcon(Symbols.shuffle), findsOneWidget);
      expect(find.byIcon(Symbols.footprint), findsOneWidget);
      expect(find.byIcon(Symbols.drafts), findsOneWidget);

      await _teardown(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('the menu still opens the drawer on a narrow layout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {'app_dashboard_enabled': false});
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.byIcon(Symbols.menu_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationDrawer),
        matching: find.text('Wallet'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_router.currentPath, '/wallet');
    expect(find.byType(NavigationDrawer), findsNothing);

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a tab the rail does not carry selects no rail entry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {
      'app_rail_nav_layouts': '["explore","chat"]',
    });
    final tabs = _router.innerRouterOf<TabsRouter>(TabsRoute.name)!;

    // Explore is carried, so it is the selection.
    tabs.setActiveIndex(1);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      0,
    );

    // Wallet is not carried. Selecting the first entry instead would paint
    // Explore as the current page while the wallet is open — and that first
    // entry is what a tap on the false selection navigates to.
    tabs.setActiveIndex(6);
    await tester.pumpAndSettle();
    expect(_router.currentPath, '/wallet');
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      isNull,
      reason: 'an uncarried tab selects no rail entry',
    );

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('opening the wallet from the account tab switches tabs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {});
    await tester.tap(find.byIcon(Symbols.account_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(_router.currentPath, '/account');

    openWalletFromAccount(tester.element(find.byType(AccountScreen)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_router.currentPath, '/wallet');
    // Pushing the tab route would stack a second shell, and the two collide on
    // the shared scaffold key.
    expect(find.byType(TabsScreen), findsOneWidget);
    expect(find.byType(WalletScreen), findsOneWidget);

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the wallet opens from a page above the shell too', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {});
    _router.push(ContentDetailRoute(id: 'abc'));
    await tester.pumpAndSettle();

    // No tab to switch to up here: the route is navigated, which pops back to
    // the shell and selects the tab there.
    openWalletFromAccount(tester.element(find.byType(Scaffold).first));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_router.currentPath, '/wallet');
    expect(find.byType(TabsScreen), findsOneWidget);
    expect(_router.stack.map((p) => p.name), [TabsRoute.name]);

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the iOS glass bar is never handed a tab it does not carry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, const {});
    final tabs = _router.innerRouterOf<TabsRouter>(TabsRoute.name)!;

    // Carried by the default bottom bar: the glass bar paints it.
    tabs.setActiveIndex(3);
    await tester.pumpAndSettle();
    final chatBar = tester.widget<NativeGlassNavBar>(
      find.byType(NativeGlassNavBar),
    );
    expect(chatBar.currentIndex, 2);

    // Thoughts is opt-in for the bottom bar. The native bar is a real
    // `UITabBarController` that echoes the index it is given back through
    // `onTap`, so handing it a fallback index 0 does not mean "nothing
    // selected" — it means Dashboard, and the echo sent the shell there.
    tabs.setActiveIndex(8);
    await tester.pumpAndSettle();
    expect(_router.currentPath, '/thoughts');
    expect(
      find.byType(NativeGlassNavBar),
      findsNothing,
      reason: 'an uncarried tab must not build a native bar',
    );

    await _teardown(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
