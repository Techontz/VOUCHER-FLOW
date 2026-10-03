import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../admin/audit_page.dart';
import '../admin/departments_page.dart';
import '../admin/employees_page.dart';
import '../admin/settings_page.dart';
import '../admin/subscription_page.dart';
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
import 'nav.dart';

/// The signed-in workspace, as the website draws it below 980px: a navy top
/// bar, a drawer holding the sidebar, and a five-slot tab bar. Which entries
/// appear follows the role exactly as the web's navigation does.
class ShellController extends GetxController {
  final session = Get.find<SessionService>();
  final repo = Get.find<VoucherRepository>();

  /// The destination on screen (a web route: '/dashboard', '/vouchers' …).
  final current = '/dashboard'.obs;
  final pendingCount = 0.obs;
  final payCount = 0.obs;

  /// Nested entries the user folded shut in the drawer.
  final closedGroups = <String>[].obs;

  late final List<VfNavItem> items = navFor(session.me.role);
  /// With a create button in the middle of the bar, four tabs flank it.
  late final List<VfNavItem> tabs = tabsFor(
    session.me.role,
  ).take(session.me.canCreateVouchers ? 4 : 5).toList();

  late final VoucherListController register = Get.put(
    VoucherListController(),
    tag: 'register',
  );

  bool get canCreate => session.me.canCreateVouchers;

  /// Shows a destination. "Create voucher" is a page of its own, pushed over
  /// the shell as on the web's New voucher button.
  void go(String href) {
    if (href == '/vouchers/new') {
      openCreate();
      return;
    }
    current.value = href;
    refreshCurrent();
    refreshCounts();
  }

  Future<void> openCreate() async {
    await Get.toNamed(Routes.createVoucher);
    refreshCurrent();
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
    // Development only (profile web builds): open on a given page.
    final route = DevHooks.route;
    if (route != null && items.any((i) => i.href == route)) {
      current.value = route;
    }
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
      final href = controller.current.value;
      return Scaffold(
        backgroundColor: t.background,
        appBar: _TopBar(controller: controller),
        drawer: _Drawer(controller: controller),
        body: KeyedSubtree(
          key: ValueKey(href),
          child: shellPageFor(href, controller),
        ),
        bottomNavigationBar: _TabBar(controller: controller),
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
      return AppBar(
        backgroundColor: t.background,
        systemOverlayStyle: t.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
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
                  icon: PhosphorIconsRegular.squaresFour,
                  tooltip: 'nav.openMenu'.tr,
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(
                    fontSize: 15.5,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
      child: VouchFlowAvatar(initials: me.initials, size: 42),
    );
  }

  void _open(BuildContext context) {
    final session = controller.session;
    final me = session.me;
    final profileLabel =
        controller.items.firstWhereOrNull((i) => i.href == '/profile')?.label ??
        'nav.profile';
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
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
              Divider(color: t.border),
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
              Divider(color: t.border),
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
                      () => SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'en', label: Text('EN')),
                          ButtonSegment(value: 'sw', label: Text('SW')),
                        ],
                        selected: {session.locale.value},
                        onSelectionChanged: (s) => session.setLocale(s.first),
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
              Divider(color: t.border),
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

class _Drawer extends StatelessWidget {
  const _Drawer({required this.controller});
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final session = controller.session;
    final me = session.me;
    final groups = drawerGroups(me.role);
    final groupLabel = {
      VfNavGroup.workspace: 'nav.groupWorkspace',
      VfNavGroup.admin: 'nav.groupAdministration',
      VfNavGroup.platform: 'nav.groupPlatform',
    };

    return Drawer(
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
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
                  border: Border(bottom: BorderSide(color: t.border)),
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
                        border: Border.all(color: t.border),
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
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
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
                    IconButton(
                      tooltip: 'nav.closeMenu'.tr,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        PhosphorIconsRegular.x,
                        color: t.muted,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              _WorkspaceCard(controller: controller),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                        child: Text(
                          groupLabel[entry.key]!.tr.toUpperCase(),
                          style: VfType.eyebrow.copyWith(
                            fontSize: 11,
                            color: t.faint,
                          ),
                        ),
                      ),
                      ..._entries(context, entry.value, current),
                    ],
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
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
              borderRadius: BorderRadius.circular(VfSize.radiusM),
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

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge,
    this.caretOpen,
    this.onCaret,
  });

  final VfNavItem item;
  final bool active;
  final VoidCallback onTap;
  final int? badge;
  final bool? caretOpen;
  final VoidCallback? onCaret;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = active ? t.primaryText : t.text2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? t.primarySoftStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: t.surface3,
          child: Container(
            height: 48,
            padding: EdgeInsets.only(
              left: 16,
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
                    style: VfType.label.copyWith(fontSize: 15, color: fg),
                  ),
                ),
                if (badge != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.dangerStrong,
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
      final create = controller.canCreate;
      final half = (tabs.length / 2).ceil();

      Widget slot(VfNavItem item) => Expanded(
        child: _TabSlot(
          item: item,
          active: item.href == current,
          badge: controller.badgeFor(item),
          onTap: () => controller.go(item.href),
        ),
      );

      return Container(
        decoration: BoxDecoration(
          color: t.tabBar,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: t.isDark ? Border(top: BorderSide(color: t.border)) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: t.isDark ? .35 : .07),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(8, 8, 8, bottom > 0 ? bottom - 6 : 10),
        child: SizedBox(
          height: 58,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!create)
                for (final item in tabs) slot(item)
              else ...[
                for (final item in tabs.take(half)) slot(item),
                Expanded(child: Center(child: _CreateButton(controller.openCreate))),
                for (final item in tabs.skip(half)) slot(item),
              ],
            ],
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
    final colour = active ? t.primary : t.muted;
    Widget icon = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: active ? 52 : 40,
      height: 30,
      decoration: BoxDecoration(
        color: active ? t.primarySoftStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Icon(active ? item.activeIcon : item.icon, size: 22, color: colour),
    );
    if (badge != null) {
      icon = Badge(
        backgroundColor: VfBadge.background(Theme.of(context).brightness),
        textColor: Colors.white,
        offset: const Offset(-2, -2),
        label: Text(badge! > 99 ? '99+' : '$badge'),
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: active,
      label: item.label.tr,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              (item.short ?? item.label).tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(
                fontSize: 11,
                height: 1.1,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised "+" in the middle of the tab bar: create a voucher.
class _CreateButton extends StatelessWidget {
  const _CreateButton(this.onTap);
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: 'nav.newVoucher'.tr,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.palette.hoverDark, t.palette.primaryLight],
          ),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: .45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const Icon(
              PhosphorIconsBold.plus,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
