import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// One navigation entry, exactly as the web client's `lib/nav.ts` defines it:
/// the route, its label, the shorter label for the tab bar, its icon and the
/// count it carries.
class VfNavItem {
  const VfNavItem(
    this.href,
    this.label,
    this.icon,
    this.activeIcon, {
    this.short,
    this.badge,
  });

  final String href;
  final String label; // translation key
  final String? short; // translation key for the tab bar
  final IconData icon;
  final IconData activeIcon;
  final String? badge; // 'pending' | 'payments' | 'notifications'
}

const _home = VfNavItem(
  '/dashboard',
  'nav.home',
  PhosphorIconsRegular.house,
  PhosphorIconsFill.house,
);
const _dashboard = VfNavItem(
  '/dashboard',
  'nav.dashboard',
  PhosphorIconsRegular.squaresFour,
  PhosphorIconsFill.squaresFour,
);
const _create = VfNavItem(
  '/vouchers/new',
  'nav.createVoucher',
  PhosphorIconsRegular.plusCircle,
  PhosphorIconsFill.plusCircle,
);
const _notifications = VfNavItem(
  '/notifications',
  'nav.notifications',
  PhosphorIconsRegular.bell,
  PhosphorIconsFill.bell,
  badge: 'notifications',
);
const _profile = VfNavItem(
  '/profile',
  'nav.profile',
  PhosphorIconsRegular.user,
  PhosphorIconsFill.user,
);
const _profileSig = VfNavItem(
  '/profile',
  'nav.profileSig',
  PhosphorIconsRegular.signature,
  PhosphorIconsFill.signature,
  short: 'nav.profile',
);
const _reports = VfNavItem(
  '/reports',
  'nav.reports',
  PhosphorIconsRegular.chartLine,
  PhosphorIconsFill.chartLine,
);
const _approvalsHome = VfNavItem(
  '/dashboard',
  'nav.approvals',
  PhosphorIconsRegular.house,
  PhosphorIconsFill.house,
  // The bar already has an Approvals tab: this one is home.
  short: 'nav.home',
  badge: 'pending',
);
const _bulk = VfNavItem(
  '/approvals',
  'nav.bulkApprove',
  PhosphorIconsRegular.checks,
  PhosphorIconsFill.checks,
  short: 'nav.approvals',
);
const _deptRegister = VfNavItem(
  '/vouchers',
  'nav.deptRegister',
  PhosphorIconsRegular.receipt,
  PhosphorIconsFill.receipt,
  short: 'nav.vouchers',
);
const _register = VfNavItem(
  '/vouchers',
  'nav.voucherRegister',
  PhosphorIconsRegular.receipt,
  PhosphorIconsFill.receipt,
  short: 'nav.vouchers',
);
const _queueHome = VfNavItem(
  '/dashboard',
  'nav.paymentQueue',
  PhosphorIconsRegular.wallet,
  PhosphorIconsFill.wallet,
  short: 'nav.payments',
  badge: 'payments',
);
const _queue = VfNavItem(
  '/payments',
  'nav.paymentQueue',
  PhosphorIconsRegular.wallet,
  PhosphorIconsFill.wallet,
  short: 'nav.payments',
  badge: 'payments',
);

/// Navigation per role — the web's NAV map, entry for entry.
const Map<String, List<VfNavItem>> vfNav = {
  'employee': [
    _home,
    VfNavItem(
      '/vouchers',
      'nav.myVouchers',
      PhosphorIconsRegular.receipt,
      PhosphorIconsFill.receipt,
      short: 'nav.vouchers',
    ),
    _create,
    _notifications,
    _profile,
  ],
  'hod': [
    _approvalsHome,
    _deptRegister,
    _create,
    _reports,
    _notifications,
    _profileSig,
  ],
  'manager': [
    _approvalsHome,
    _bulk,
    _deptRegister,
    _create,
    _reports,
    _notifications,
    _profileSig,
  ],
  'ceo': [
    VfNavItem(
      '/dashboard',
      'nav.finalApprovals',
      PhosphorIconsRegular.sealCheck,
      PhosphorIconsFill.sealCheck,
      short: 'nav.approvals',
      badge: 'pending',
    ),
    _bulk,
    _register,
    _create,
    _reports,
    _notifications,
    _profileSig,
  ],
  'cashier': [_queueHome, _register, _reports, _notifications, _profile],
  'finance': [
    _approvalsHome,
    _bulk,
    _register,
    _queue,
    _create,
    _reports,
    _notifications,
    _profileSig,
  ],
  'director': [
    _approvalsHome,
    _bulk,
    _register,
    _reports,
    _notifications,
    _profileSig,
  ],
  'company_admin': [
    _dashboard,
    VfNavItem(
      '/vouchers',
      'nav.vouchers',
      PhosphorIconsRegular.receipt,
      PhosphorIconsFill.receipt,
    ),
    _create,
    VfNavItem(
      '/approvals',
      'nav.approvals',
      PhosphorIconsRegular.listChecks,
      PhosphorIconsFill.listChecks,
      badge: 'pending',
    ),
    _queue,
    VfNavItem(
      '/employees',
      'nav.employees',
      PhosphorIconsRegular.usersThree,
      PhosphorIconsFill.usersThree,
    ),
    VfNavItem(
      '/departments',
      'nav.departments',
      PhosphorIconsRegular.buildings,
      PhosphorIconsFill.buildings,
    ),
    _reports,
    VfNavItem(
      '/subscription',
      'nav.subscription',
      PhosphorIconsRegular.crownSimple,
      PhosphorIconsFill.crownSimple,
    ),
    VfNavItem(
      '/branding',
      'nav.branding',
      PhosphorIconsRegular.palette,
      PhosphorIconsFill.palette,
    ),
    VfNavItem(
      '/audit',
      'nav.auditLogs',
      PhosphorIconsRegular.scroll,
      PhosphorIconsFill.scroll,
      short: 'nav.auditLogs',
    ),
    VfNavItem(
      '/settings',
      'nav.settings',
      PhosphorIconsRegular.gear,
      PhosphorIconsFill.gear,
    ),
  ],
  'super_admin': [
    _dashboard,
    VfNavItem(
      '/platform/companies',
      'nav.companies',
      PhosphorIconsRegular.buildings,
      PhosphorIconsFill.buildings,
      short: 'nav.companies',
    ),
    VfNavItem(
      '/platform/plans',
      'nav.plansSubs',
      PhosphorIconsRegular.crownSimple,
      PhosphorIconsFill.crownSimple,
      short: 'nav.plan',
    ),
    VfNavItem(
      '/platform/payments',
      'nav.payments',
      PhosphorIconsRegular.creditCard,
      PhosphorIconsFill.creditCard,
      short: 'nav.payments',
    ),
    VfNavItem(
      '/platform/users',
      'nav.users',
      PhosphorIconsRegular.usersThree,
      PhosphorIconsFill.usersThree,
      short: 'nav.users',
    ),
    VfNavItem(
      '/audit',
      'nav.auditLogs',
      PhosphorIconsRegular.scroll,
      PhosphorIconsFill.scroll,
      short: 'nav.auditLogs',
    ),
    _notifications,
    _profile,
  ],
};

List<VfNavItem> navFor(String role) => vfNav[role] ?? vfNav['employee']!;

/// The five tab-bar slots: home first, then the rest in order, without
/// "Create voucher" (the top bar's + does that) — the web's mobileNavFor.
List<VfNavItem> tabsFor(String role) {
  final items = navFor(role);
  final home = items.first;
  final rest = items.where((i) => i != home && i.href != '/vouchers/new');
  return [home, ...rest].take(5).toList();
}

enum VfNavGroup { workspace, admin, platform }

/// Which drawer group an entry belongs to; account pages (notifications,
/// profile) live in the user menu instead — as in the web layout.
VfNavGroup? groupOf(VfNavItem item) {
  if (item.href == '/notifications' || item.href == '/profile') return null;
  if (item.href.startsWith('/platform')) return VfNavGroup.platform;
  const admin = [
    '/employees',
    '/departments',
    '/settings',
    '/branding',
    '/subscription',
    '/audit',
  ];
  if (admin.contains(item.href)) return VfNavGroup.admin;
  return VfNavGroup.workspace;
}

/// Company settings pages a company administrator reaches through the
/// company menu rather than the drawer list.
const settingsChildren = ['/branding', '/subscription'];

/// The drawer's entries for a role, grouped, in order.
Map<VfNavGroup, List<VfNavItem>> drawerGroups(String role) {
  final out = <VfNavGroup, List<VfNavItem>>{};
  for (final item in navFor(role)) {
    final g = groupOf(item);
    if (g == null) continue;
    if (role == 'company_admin' && settingsChildren.contains(item.href)) {
      continue;
    }
    out.putIfAbsent(g, () => []).add(item);
  }
  return out;
}

/// The entry an entry is drawn beneath (Create voucher under Vouchers).
VfNavItem? parentOf(VfNavItem item, List<VfNavItem> siblings) {
  for (final p in siblings) {
    if (p != item && item.href.startsWith('${p.href}/')) return p;
  }
  return null;
}
