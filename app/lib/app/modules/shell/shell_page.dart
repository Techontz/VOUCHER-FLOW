import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../admin/audit_page.dart';
import '../admin/departments_page.dart';
import '../admin/employees_page.dart';
import '../admin/settings_page.dart';
import '../admin/subscription_page.dart';
import '../apps/launcher_page.dart';
import '../approvals/bulk_approve_page.dart';
import '../auth/pending_page.dart';
import '../branding/branding_page.dart';
import '../dashboard/dashboard_tab.dart';
import '../notifications/notifications_tab.dart';
import '../payments/payment_queue_page.dart';
import '../platform/companies_page.dart';
import '../platform/plans_page.dart';
import '../platform/platform_payments_page.dart';
import '../platform/users_page.dart';
import '../profile/profile_tab.dart';
import '../reports/reports_page.dart';
import '../vouchers/voucher_list_tab.dart';
import 'app_registry.dart';
import 'areas.dart';
import 'nav.dart';

/// The signed-in workspace, as the website draws it below 980px: a clear top
/// bar over the glass wallpaper, a glass drawer holding the sidebar, and a
/// floating glass tab bar. Which entries appear follows the role exactly as
/// the web's navigation does.
///
/// With more than one app (VouchFlow, Inventory, Settings …) the shell opens
/// on the launcher; the tab bar then carries the open app's first four
/// entries after an Apps tab, and the top bar names the app and switches
/// between them. Someone with a single app never sees the launcher.
class ShellController extends GetxController {
  final session = Get.find<SessionService>();
  final repo = Get.find<VoucherRepository>();
  final erp = ErpService.to;

  /// The destination on screen (a web route: '/dashboard', '/erp/stock' …,
  /// or '/home' for the launcher).
  final current = '/dashboard'.obs;

  /// The open app; null on the launcher.
  final area = RxnString();

  /// False until the ERP configuration has been read, so the first screen
  /// is the right one rather than VouchFlow swapped for the launcher.
  final ready = false.obs;

  final pendingCount = 0.obs;
  final payCount = 0.obs;

  /// What waits in each ERP app, for the launcher's badges.
  final appCounts = <String, int>{}.obs;

  /// Nested entries the user folded shut in the drawer.
  final closedGroups = <String>[].obs;

  /// The app last open, whose tabs the launcher's tab bar keeps.
  String? _lastArea;

  /// The role's VouchFlow navigation (the web's NAV map).
  late final List<VfNavItem> items = navFor(session.me.role);

  late final VoucherListController register = Get.put(
    VoucherListController(),
    tag: 'register',
  );

  /// What this person can reach, by app. Read inside Obx: it follows the
  /// ERP configuration.
  VfApps get apps => VfApps.of(session.me, erp.config.value);

  bool get canCreate => session.me.canCreateVouchers;

  static const appsItem = VfNavItem(
    '/home',
    'apps.apps',
    PhosphorIconsRegular.squaresFour,
    PhosphorIconsFill.squaresFour,
  );

  /// The tab bar: the role's tabs with one app, otherwise Apps then the open
  /// app's first entries (three beside VouchFlow's create button, four
  /// elsewhere).
  List<VfNavItem> get tabs {
    final a = apps;
    if (!a.multi) {
      return tabsFor(session.me.role).take(canCreate ? 4 : 5).toList();
    }
    final key = area.value ?? _lastArea ?? a.open.first.key;
    final own = a.menuOf(key).where((i) => i.href != '/vouchers/new');
    return [appsItem, ...own.take(key == 'vouchflow' && showCreate ? 3 : 4)];
  }

  /// VouchFlow's "+" sits in the middle of the bar while VouchFlow is open.
  bool get showCreate {
    if (!canCreate) return false;
    if (!apps.multi) return true;
    return (area.value ?? _lastArea) == 'vouchflow' && current.value != '/home';
  }

  /// What the top bar's "+" offers in the open ERP app.
  List<VfCreateAction> get createActions {
    final key = area.value;
    if (key == null) return const [];
    return createActionsFor(key).where((a) => a.permission == null || erp.can(a.permission!)).toList();
  }

  /// Shows a destination. "Create voucher" is a page of its own, pushed over
  /// the shell as on the web's New voucher button.
  void go(String href) {
    if (href == '/vouchers/new') {
      openCreate();
      return;
    }
    if (href == '/home') {
      if (area.value != null) _lastArea = area.value;
      area.value = null;
      current.value = '/home';
      refreshCounts();
      return;
    }
    // Account pages (profile, notifications) keep the app that is open.
    final owner = apps.areaOfHref(href);
    if (owner != null) area.value = owner;
    current.value = href;
    refreshCurrent();
    refreshCounts();
  }

  /// Where Android's back gesture leads from the screen on show: the
  /// launcher from inside an app, the only app's home from its other tabs.
  /// Null on the first screen, where back leaves the app as usual.
  String? get backTarget {
    final a = apps;
    if (a.multi) return current.value == '/home' ? null : '/home';
    final only = a.open.firstOrNull?.key;
    final home = (only == null ? null : a.homeOf(only)) ?? '/dashboard';
    return current.value == home ? null : home;
  }

  /// Opens an app on its first entry.
  void openApp(String key) {
    final home = apps.homeOf(key);
    if (home != null) go(home);
  }

  Future<void> openCreate() async {
    await Get.toNamed(Routes.createVoucher);
    refreshCurrent();
    refreshCounts();
  }

  /// Runs an app's create action: one of its tabs, or a pushed page.
  Future<void> runCreate(VfCreateAction action) async {
    if (apps.items.any((i) => i.href == action.route)) {
      go(action.route);
      return;
    }
    await Get.toNamed(action.route, arguments: action.arguments);
    refreshCounts();
  }

  void refreshCurrent() {
    switch (current.value) {
      case '/dashboard':
        if (Get.isRegistered<DashboardController>()) {
          Get.find<DashboardController>().load();
        }
      case '/vouchers':
        register.load();
      case '/notifications':
        if (Get.isRegistered<NotificationsController>()) {
          Get.find<NotificationsController>().load();
        }
    }
  }

  Future<void> refreshCounts() async {
    unawaited(session.refreshUnread());
    try {
      pendingCount.value = (await repo.pending()).length;
    } catch (_) {}
    if (items.any((i) => i.badge == 'payments')) {
      try {
        payCount.value = (await repo.list(status: 'approved')).length;
      } catch (_) {}
    }
    // Drafts waiting to be posted are Inventory's count, for whoever posts.
    if (apps.byArea.containsKey('inventory') && erp.can('inventory.post')) {
      try {
        final overview = await InventoryRepository.to.overview();
        appCounts['inventory'] = overview?.drafts ?? 0;
      } catch (_) {}
    }
  }

  int? badgeFor(VfNavItem item) {
    final n = switch (item.badge) {
      'pending' => pendingCount.value,
      'payments' => payCount.value,
      'notifications' => session.unread.value,
      _ => 0,
    };
    return n > 0 ? n : null;
  }

  @override
  void onInit() {
    super.onInit();
    if (session.me.isSuperAdmin) {
      _decide();
    } else {
      erp.ensure().whenComplete(_decide);
    }
  }

  /// The first screen: the launcher with several apps, the only app's home
  /// otherwise. A development build may ask for a page instead.
  void _decide() {
    final a = apps;
    final route = DevHooks.route;
    if (route != null && (route == '/home' ? a.multi : a.items.any((i) => i.href == route))) {
      area.value = route == '/home' ? null : a.areaOfHref(route);
      current.value = route;
    } else if (a.multi) {
      area.value = null;
      current.value = '/home';
    } else {
      final only = a.open.firstOrNull?.key;
      area.value = only;
      current.value = (only == null ? null : a.homeOf(only)) ?? '/dashboard';
    }
    ready.value = true;
  }

  @override
  void onReady() {
    super.onReady();
    refreshCounts();
    final push = DevHooks.push;
    if (push != null) {
      final args = DevHooks.pushArgs;
      final id = int.tryParse(args['id'] ?? '');
      Get.toNamed(push, arguments: id ?? args);
    }
  }
}

/// The page each web route shows inside the shell.
Widget shellPageFor(String href, ShellController c) {
  if (href == '/home') return const LauncherPage();
  if (href.startsWith('/erp')) {
    return Builder(builder: (context) => erpPageFor(href, context) ?? const SizedBox.shrink());
  }
  return switch (href) {
    '/dashboard' => const DashboardTab(),
    '/vouchers' => VoucherListTab(controller: c.register),
    '/approvals' => const BulkApprovePage(),
    '/payments' => const PaymentQueuePage(),
    '/reports' => const ReportsPage(),
    '/notifications' => const NotificationsTab(),
    '/profile' => const ProfileTab(),
    '/employees' => const EmployeesPage(),
    '/departments' => const DepartmentsPage(),
    '/audit' => const AuditPage(),
    '/settings' => const SettingsPage(),
    '/branding' => const BrandingPage(),
    '/subscription' => const SubscriptionPage(),
    '/platform/companies' => const PlatformCompaniesPage(),
    '/platform/plans' => const PlatformPlansPage(),
    '/platform/payments' => const PlatformPaymentsPage(),
    '/platform/users' => const PlatformUsersPage(),
    _ => const DashboardTab(),
  };
}

class ShellPage extends GetView<ShellController> {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      // A company the platform has not approved yet sees only the waiting
      // screen; the API refuses everything else for it.
      final me = controller.session.user.value;
      if (controller.session.company.value?.isPending == true &&
          me?.isSuperAdmin != true) {
        return const PendingApprovalPage();
      }
      if (!controller.ready.value) {
        return VfWallpaper(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: VfLoadingView(label: 'apps.loading'.tr),
          ),
        );
      }
      final href = controller.current.value;
      final back = controller.backTarget;
      // Android's back steps out of an app to the launcher (or to the only
      // app's home) before it leaves VouchFlow. An open drawer or sheet is
      // its own route and closes first.
      return PopScope(
        canPop: back == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && back != null) controller.go(back);
        },
        child: VfWallpaper(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          drawerScrimColor: t.overlay,
          appBar: _TopBar(controller: controller),
          drawer: _Drawer(controller: controller),
          body: KeyedSubtree(
            key: ValueKey(href),
            child: shellPageFor(href, controller),
          ),
          bottomNavigationBar: _TabBar(controller: controller),
        ),
        ),
      );
    });
  }
}

/* ─────────────────────────────────────────────────────────── top bar ── */

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.controller});
  final ShellController controller;

  @override
  Size get preferredSize => const Size.fromHeight(VfSize.topBarH + 4);

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final session = controller.session;
    return Obx(() {
      final me = session.user.value;
      final company = session.company.value;
      final name = me?.isSuperAdmin == true
          ? 'nav.platformName'.tr
          : (company?.name ?? 'app.name'.tr);
      final multi = controller.apps.multi;
      final app = multi ? controller.area.value : null;
      final create = controller.createActions;
      return AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: VfTheme.overlay(t.isDark),
        toolbarHeight: VfSize.topBarH + 4,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Builder(
                builder: (ctx) => VfBarButton(
                  // With apps, the four squares mean "all apps"; the menu
                  // is then the plain list icon.
                  icon: multi
                      ? PhosphorIconsRegular.list
                      : PhosphorIconsRegular.squaresFour,
                  tooltip: 'nav.openMenu'.tr,
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: app == null
                    ? Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.bodyStrong.copyWith(
                          fontSize: 15.5,
                          color: t.text,
                          letterSpacing: -.2,
                        ),
                      )
                    : _AppTitle(
                        app: app,
                        onTap: () => showAppSwitcher(context, controller),
                      ),
              ),
              const SizedBox(width: 8),
              if (create.isNotEmpty) ...[
                VfBarButton(
                  icon: PhosphorIconsRegular.plus,
                  tooltip: 'apps.createIn'.trParams({'app': 'area.$app'.tr}),
                  onPressed: () => _create(context, create),
                ),
                const SizedBox(width: 10),
              ],
              VfBarButton(
                icon: PhosphorIconsRegular.bell,
                tooltip: 'nav.notifications'.tr,
                badge: session.unread.value > 0,
                onPressed: () => controller.go('/notifications'),
              ),
              const SizedBox(width: 10),
              _UserMenu(controller: controller),
            ],
          ),
        ),
      );
    });
  }

  /// The app's "+": what it creates, behind the permission each needs.
  Future<void> _create(BuildContext context, List<VfCreateAction> actions) async {
    final app = 'area.${controller.area.value}'.tr;
    final chosen = await showVouchFlowBottomSheet<VfCreateAction>(
      context,
      title: 'apps.createIn'.trParams({'app': app}),
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++)
            Builder(
              builder: (ctx) => VouchFlowListRow(
                divider: i > 0,
                icon: actions[i].icon,
                title: actions[i].label.tr,
                subtitle: actions[i].hint?.tr,
                onTap: () => Navigator.of(ctx).pop(actions[i]),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (chosen != null) await controller.runCreate(chosen);
  }
}

/// The open app's icon and name; tapping switches app.
class _AppTitle extends StatelessWidget {
  const _AppTitle({required this.app, required this.onTap});

  final String app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '${'area.$app'.tr}, ${'apps.switch'.tr}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VfAppIcon(app: app, size: 32, shadow: false),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'area.$app'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.bodyStrong.copyWith(
                      fontSize: 15.5,
                      color: t.text,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(PhosphorIconsBold.caretDown, size: 13, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.controller});
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final me = session.me;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _open(context),
      child: VouchFlowAvatar(initials: me.initials, size: 40),
    );
  }

  void _open(BuildContext context) {
    final session = controller.session;
    final me = session.me;
    final profileLabel =
        controller.items.firstWhereOrNull((i) => i.href == '/profile')?.label ??
        'nav.profile';
    showVfSheet<void>(
      context,
      isScrollControlled: false,
      builder: (ctx) {
        final t = ctx.vf;
        Widget item(
          IconData icon,
          String label,
          VoidCallback onTap, {
          bool danger = false,
        }) => ListTile(
          leading: Icon(
            icon,
            size: 20,
            color: danger ? t.dangerStrong : t.faint,
          ),
          title: Text(
            label,
            style: VfType.body.copyWith(
              color: danger ? t.dangerStrong : t.text,
            ),
          ),
          onTap: () {
            Navigator.of(ctx).pop();
            onTap();
          },
        );
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    VouchFlowAvatar(initials: me.initials, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.name,
                            style: VfType.bodyStrong.copyWith(color: t.text),
                          ),
                          Text(
                            me.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.meta.copyWith(color: t.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: t.isDark ? t.glassBorder : t.border),
              item(
                PhosphorIconsRegular.userCircle,
                profileLabel.tr,
                () => controller.go('/profile'),
              ),
              Obx(
                () => item(
                  PhosphorIconsRegular.bell,
                  session.unread.value > 0
                      ? '${'nav.notifications'.tr} (${session.unread.value})'
                      : 'nav.notifications'.tr,
                  () => controller.go('/notifications'),
                ),
              ),
              Divider(color: t.isDark ? t.glassBorder : t.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'nav.language'.tr,
                        style: VfType.body.copyWith(color: t.text2),
                      ),
                    ),
                    Obx(
                      () => VfLanguagePicker(
                        value: session.locale.value,
                        onChanged: session.setLocale,
                        tooltip: 'nav.language'.tr,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'nav.appearance'.tr,
                        style: VfType.body.copyWith(color: t.text2),
                      ),
                    ),
                    Obx(
                      () => SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: const Icon(
                              PhosphorIconsRegular.sun,
                              size: 16,
                            ),
                            label: Text('nav.light'.tr),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: const Icon(
                              PhosphorIconsRegular.moon,
                              size: 16,
                            ),
                            label: Text('nav.dark'.tr),
                          ),
                        ],
                        selected: {session.themeMode.value},
                        onSelectionChanged: (s) {
                          if (s.first != session.themeMode.value) {
                            session.toggleTheme();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: t.isDark ? t.glassBorder : t.border),
              item(PhosphorIconsRegular.signOut, 'nav.signOut'.tr, () async {
                await session.signOut();
                Get.offAllNamed(Routes.login);
              }, danger: true),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/* ──────────────────────────────────────────────────────────── drawer ── */

/// A drawer section's heading. The switch is exhaustive on purpose: adding
/// a [VfNavGroup] (an ERP module) fails to compile until it has a heading.
String _groupLabel(VfNavGroup g) => switch (g) {
  VfNavGroup.workspace => 'nav.groupWorkspace'.tr,
  VfNavGroup.admin => 'nav.groupAdministration'.tr,
  VfNavGroup.platform => 'nav.groupPlatform'.tr,
};

class _Drawer extends StatelessWidget {
  const _Drawer({required this.controller});
  final ShellController controller;

  static const _radius = BorderRadius.horizontal(
    right: Radius.circular(VfSize.radiusSheet),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final session = controller.session;
    final me = session.me;
    final groups = drawerGroups(me.role);
    // With several sections each heading folds its list away, so a long
    // menu (the ERP modules to come) stays easy to scan.
    final foldable = groups.length > 1;

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      child: VfGlass(
        borderRadius: _radius,
        fill: t.sheetFill,
        child: SafeArea(
          right: false,
          child: Obx(() {
            final current = controller.current.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand: the VouchFlow mark, name and the role, and close.
                Container(
                  height: 76,
                  padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: t.isDark ? t.glassBorder : t.border,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(VfSize.radiusL),
                          border: Border.all(color: t.glassBorder),
                        ),
                        child: Image.asset('assets/brand/mark.png'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'app.name'.tr,
                              style: VfType.sectionTitle.copyWith(
                                color: t.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                                letterSpacing: -.5,
                              ),
                            ),
                            Text(
                              me.roleLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.meta.copyWith(color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      VfBarButton(
                        icon: PhosphorIconsRegular.x,
                        tooltip: 'nav.closeMenu'.tr,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                _WorkspaceCard(controller: controller),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    children: controller.apps.multi
                        ? _appMenu(context, current)
                        : [
                      for (final entry in groups.entries) ...[
                        _GroupHeader(
                          label: _groupLabel(entry.key),
                          open: !controller.closedGroups.contains(
                            'group:${entry.key.name}',
                          ),
                          onToggle: foldable
                              ? () {
                                  final key = 'group:${entry.key.name}';
                                  controller.closedGroups.contains(key)
                                      ? controller.closedGroups.remove(key)
                                      : controller.closedGroups.add(key);
                                }
                              : null,
                        ),
                        if (!foldable ||
                            !controller.closedGroups.contains(
                              'group:${entry.key.name}',
                            ))
                          ..._entries(context, entry.value, current),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// With several apps: the open app's whole menu, then every app.
  List<Widget> _appMenu(BuildContext context, String current) {
    final apps = controller.apps;
    final open = controller.area.value;
    return [
      if (open != null) ...[
        _GroupHeader(label: 'area.$open'.tr, open: true),
        ..._entries(context, apps.menuOf(open), current),
      ],
      _GroupHeader(label: 'apps.apps'.tr, open: true),
      _AppRow(
        icon: const Icon(PhosphorIconsRegular.squaresFour, size: 20),
        label: 'apps.allApps'.tr,
        active: current == '/home',
        onTap: () => _open(context, '/home'),
      ),
      for (final a in apps.open)
        _AppRow(
          icon: VfAppIcon(app: a.key, size: 28, shadow: false),
          label: a.label.tr,
          active: a.key == open && current != '/home',
          badge: a.key == 'vouchflow'
              ? (controller.pendingCount.value > 0 ? controller.pendingCount.value : null)
              : controller.appCounts[a.key],
          onTap: () {
            Navigator.of(context).pop();
            controller.openApp(a.key);
          },
        ),
    ];
  }

  List<Widget> _entries(
    BuildContext context,
    List<VfNavItem> items,
    String current,
  ) {
    final out = <Widget>[];
    for (final item in items) {
      if (parentOf(item, items) != null) continue;
      final children = items.where((c) => parentOf(c, items) == item).toList();
      final open = !controller.closedGroups.contains(item.href);
      out.add(
        _NavRow(
          item: item,
          active: item.href == current,
          badge: controller.badgeFor(item),
          onTap: () => _open(context, item.href),
          caretOpen: children.isEmpty ? null : open,
          onCaret: () => open
              ? controller.closedGroups.add(item.href)
              : controller.closedGroups.remove(item.href),
        ),
      );
      if (open) {
        for (final c in children) {
          out.add(
            _NavRow(
              item: c,
              active: false,
              nested: true,
              badge: controller.badgeFor(c),
              onTap: () => _open(context, c.href),
            ),
          );
        }
      }
    }
    return out;
  }

  void _open(BuildContext context, String href) {
    Navigator.of(context).pop();
    controller.go(href);
  }
}

/// A drawer section heading; tappable to fold the section when [onToggle]
/// is given.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.open, this.onToggle});

  final String label;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final text = Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: VfType.eyebrow.copyWith(fontSize: 11, color: t.muted),
    );
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 10, 8),
      child: Row(
        children: [
          Expanded(child: text),
          if (onToggle != null)
            Icon(
              open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
              size: 12,
              color: t.faint,
            ),
        ],
      ),
    );
    if (onToggle == null) return Semantics(header: true, child: row);
    return Semantics(
      header: true,
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: row,
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.controller});
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final session = controller.session;
    final me = session.me;
    final company = session.company.value;
    final isPlatform = me.isSuperAdmin;
    final name = isPlatform
        ? 'nav.platformName'.tr
        : (company?.name ?? 'app.name'.tr);
    final sub = isPlatform
        ? 'nav.groupPlatform'.tr
        : [company?.plan?.name, company?.status]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .map((s) => s[0].toUpperCase() + s.substring(1))
              .join(' · ');
    final isAdmin = me.role == 'company_admin';

    final card = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: t.glassFillStrong,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: Border.all(color: t.isDark ? t.glassBorder : t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            clipBehavior: Clip.antiAlias,
            padding: company?.logoMarkUrl != null && !isPlatform
                ? const EdgeInsets.all(3)
                : null,
            decoration: BoxDecoration(
              color: company?.logoMarkUrl != null && !isPlatform
                  ? Colors.white
                  : t.primary,
              borderRadius: BorderRadius.circular(VfSize.radiusL),
            ),
            alignment: Alignment.center,
            child: company?.logoMarkUrl != null && !isPlatform
                ? Image.network(
                    company!.logoMarkUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      name.characters.first.toUpperCase(),
                      style: VfType.bodyStrong.copyWith(color: t.primary),
                    ),
                  )
                : isPlatform
                ? const Icon(
                    PhosphorIconsRegular.globeHemisphereEast,
                    color: Colors.white,
                    size: 18,
                  )
                : Text(
                    name.characters.first.toUpperCase(),
                    style: VfType.bodyStrong.copyWith(color: Colors.white),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: t.text,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.meta.copyWith(color: t.muted),
                  ),
              ],
            ),
          ),
          if (isAdmin)
            Icon(
              PhosphorIconsRegular.caretDown,
              size: 16,
              color: t.muted,
            ),
          const SizedBox(width: 6),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: !isAdmin
          ? card
          : PopupMenuButton<String>(
              tooltip: name,
              position: PopupMenuPosition.under,
              onSelected: (href) {
                Navigator.of(context).pop();
                controller.go(href);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: '/settings',
                  child: _menuRow(
                    context,
                    PhosphorIconsRegular.buildings,
                    'nav.companyProfile'.tr,
                  ),
                ),
                PopupMenuItem(
                  value: '/branding',
                  child: _menuRow(
                    context,
                    PhosphorIconsRegular.palette,
                    'nav.branding'.tr,
                  ),
                ),
                PopupMenuItem(
                  value: '/subscription',
                  child: _menuRow(
                    context,
                    PhosphorIconsRegular.crownSimple,
                    'nav.subscription'.tr,
                  ),
                ),
              ],
              child: card,
            ),
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 18, color: context.vf.faint),
      const SizedBox(width: 12),
      Text(label),
    ],
  );
}

/// An app in the drawer: its icon, its name, what waits in it.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final Widget icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? t.tabActive : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: active
              ? BorderSide(color: t.isDark ? t.glassBorder : t.primaryBorder)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: active ? t.primaryText : t.text2),
                  child: SizedBox(width: 28, child: Center(child: icon)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(
                      fontSize: 14.5,
                      color: active ? t.text : t.text2,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VfBadge.background(t.brightness),
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    ),
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: VfType.meta.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge,
    this.caretOpen,
    this.onCaret,
    this.nested = false,
  });

  final VfNavItem item;
  final bool active;
  final VoidCallback onTap;
  final int? badge;
  final bool? caretOpen;
  final VoidCallback? onCaret;

  /// Drawn beneath its parent, indented.
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = active ? t.primaryText : t.text2;
    final radius = BorderRadius.circular(VfSize.radiusL);
    return Padding(
      padding: EdgeInsets.only(bottom: 2, left: nested ? 22 : 0),
      child: Material(
        color: active ? t.tabActive : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: active
              ? BorderSide(color: t.isDark ? t.glassBorder : t.primaryBorder)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: t.glassFill,
          child: Container(
            height: 46,
            padding: EdgeInsets.only(
              left: 14,
              right: caretOpen == null ? 12 : 4,
            ),
            child: Row(
              children: [
                Icon(active ? item.activeIcon : item.icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(
                      fontSize: 14.5,
                      color: active ? t.text : t.text2,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VfBadge.background(t.brightness),
                      borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    ),
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: VfType.meta.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (caretOpen != null)
                  IconButton(
                    tooltip:
                        '${item.label.tr}: ${caretOpen! ? 'nav.collapse'.tr : 'nav.expand'.tr}',
                    onPressed: onCaret,
                    icon: Icon(
                      caretOpen!
                          ? PhosphorIconsRegular.caretUp
                          : PhosphorIconsRegular.caretDown,
                      size: 15,
                      color: t.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ─────────────────────────────────────────────────────────── tab bar ── */

/// The floating glass tab bar, inset from the screen edges. The current
/// tab sits on a raised pill; with a create button its "+" is the middle
/// slot.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.controller});
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Obx(() {
      final tabs = controller.tabs;
      final current = controller.current.value;
      final create = controller.showCreate;
      final half = (tabs.length / 2).ceil();

      Widget slot(VfNavItem item) => Expanded(
        child: _TabSlot(
          item: item,
          active: item.href == current,
          badge: controller.badgeFor(item),
          onTap: () => controller.go(item.href),
        ),
      );

      return Padding(
        padding: EdgeInsets.fromLTRB(
          VfSize.floatingBarInset,
          4,
          VfSize.floatingBarInset,
          bottom > 0 ? bottom : VfSize.floatingBarInset,
        ),
        child: VfGlass(
          borderRadius: BorderRadius.circular(VfSize.radiusSheet),
          fill: t.barFill,
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: VfSize.floatingBarH - 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!create)
                  for (final item in tabs) slot(item)
                else ...[
                  for (final item in tabs.take(half)) slot(item),
                  Expanded(
                    child: Center(child: _CreateButton(controller.openCreate)),
                  ),
                  for (final item in tabs.skip(half)) slot(item),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final VfNavItem item;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final colour = active ? t.primaryText : t.muted;
    Widget icon = Icon(
      active ? item.activeIcon : item.icon,
      size: 20,
      color: colour,
    );
    if (badge != null) {
      icon = Badge(
        backgroundColor: VfBadge.background(Theme.of(context).brightness),
        textColor: Colors.white,
        offset: const Offset(6, -5),
        label: Text(badge! > 99 ? '99+' : '$badge'),
        child: icon,
      );
    }
    final radius = BorderRadius.circular(VfSize.radiusXl);
    return Semantics(
      button: true,
      selected: active,
      label: item.label.tr,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: active ? t.tabActive : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: active
                  ? (t.isDark ? t.glassBorder : t.primaryBorder)
                  : Colors.transparent,
            ),
            boxShadow: active && !t.isDark
                ? [
                    BoxShadow(
                      color: t.primary.withValues(alpha: .14),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 3),
                  // A long word (Swahili "Wafanyakazi") shrinks a little to
                  // fit rather than losing its end.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        (item.short ?? item.label).tr,
                        maxLines: 1,
                        style: VfType.meta.copyWith(
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active ? t.text : t.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "+" in the middle of the tab bar: create a voucher.
class _CreateButton extends StatelessWidget {
  const _CreateButton(this.onTap);
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: 'nav.newVoucher'.tr,
      child: Container(
        width: 44,
        height: 44,
        decoration: vfPrimaryGloss(t, shape: BoxShape.circle),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const VfGloss(),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  child: const Icon(
                    PhosphorIconsBold.plus,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
