import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/erp_models.dart';
import '../../data/models/models.dart';
import 'app_registry.dart';
import 'nav.dart';

/*
 * The apps a person chooses between on the launcher, the web's lib/areas.ts
 * and lib/use-areas.ts. Every menu entry belongs to exactly one app, and the
 * tab bar and drawer show only the entries of the one that is open, so a
 * company running fifteen modules still sees a short menu.
 */

/// One app on the launcher.
class VfArea {
  const VfArea({
    required this.key,
    required this.category,
    required this.icon,
    required this.tint,
    this.module,
  });

  final String key;

  /// 'finance' | 'sales' | 'supply' | 'people' | 'productivity' | 'admin'.
  final String category;

  /// A plain glyph for places too small for the illustrated icon.
  final IconData icon;

  /// One system colour per app, so each is recognisable at a glance.
  final Color tint;

  /// The company module that switches it on; apps without one are always
  /// available.
  final String? module;

  String get label => 'area.$key';
  String get blurb => 'area.${key}Blurb';
}

/// Every app, in launcher order (the web's AREAS).
const vfAreas = [
  VfArea(key: 'vouchflow', category: 'finance', icon: PhosphorIconsRegular.receipt, tint: Color(0xFF0A84FF), module: 'vouchflow'),
  VfArea(key: 'inventory', category: 'supply', icon: PhosphorIconsRegular.package, tint: Color(0xFFFF9F0A), module: 'inventory'),
  VfArea(key: 'sales', category: 'sales', icon: PhosphorIconsRegular.storefront, tint: Color(0xFF30D158), module: 'sales'),
  VfArea(key: 'dispatch', category: 'sales', icon: PhosphorIconsRegular.truckTrailer, tint: Color(0xFF40C8E0), module: 'dispatch'),
  VfArea(key: 'procurement', category: 'supply', icon: PhosphorIconsRegular.shoppingCart, tint: Color(0xFF5E5CE6), module: 'procurement'),
  VfArea(key: 'finance', category: 'finance', icon: PhosphorIconsRegular.bank, tint: Color(0xFFBF5AF2), module: 'accounting'),
  VfArea(key: 'assets', category: 'finance', icon: PhosphorIconsRegular.buildings, tint: Color(0xFFAC8E68), module: 'assets'),
  VfArea(key: 'production', category: 'supply', icon: PhosphorIconsRegular.factory, tint: Color(0xFFFF453A), module: 'production'),
  VfArea(key: 'fleet', category: 'supply', icon: PhosphorIconsRegular.truck, tint: Color(0xFFFFB340), module: 'fleet'),
  VfArea(key: 'hr', category: 'people', icon: PhosphorIconsRegular.usersThree, tint: Color(0xFFFF375F), module: 'hr'),
  VfArea(key: 'crm', category: 'sales', icon: PhosphorIconsRegular.handshake, tint: Color(0xFF64D2FF), module: 'crm'),
  VfArea(key: 'files', category: 'productivity', icon: PhosphorIconsRegular.folderSimple, tint: Color(0xFF8E8E93), module: 'documents'),
  VfArea(key: 'settings', category: 'admin', icon: PhosphorIconsRegular.gearSix, tint: Color(0xFF636366)),
  VfArea(key: 'platform', category: 'admin', icon: PhosphorIconsRegular.globeHemisphereEast, tint: Color(0xFF0A84FF)),
];

/// The launcher's grouping, in the order a business thinks about its work.
const vfAreaCategories = ['finance', 'sales', 'supply', 'people', 'productivity', 'admin'];

VfArea vfArea(String key) => vfAreas.firstWhere((a) => a.key == key, orElse: () => vfAreas.first);

const _adminHrefs = ['/employees', '/departments', '/settings', '/branding', '/subscription', '/audit'];

/// ERP screens that belong to an app other than their module's.
const _pathAreas = [
  ('/erp/dispatch', 'dispatch'),
  ('/erp/assets', 'assets'),
  ('/erp/files', 'files'),
  ('/erp/crm', 'crm'),
];

const _moduleArea = {
  'inventory': 'inventory',
  'sales': 'sales',
  'dispatch': 'dispatch',
  'procurement': 'procurement',
  'accounting': 'finance',
  'assets': 'assets',
  'production': 'production',
  'fleet': 'fleet',
  'hr': 'hr',
  'crm': 'crm',
  'documents': 'files',
};

bool _under(String href, String prefix) => href == prefix || href.startsWith('$prefix/');

/// The app a menu entry belongs to (the web's `areaOf`).
String areaOf(VfNavItem item) {
  final href = item.href;
  if (href.startsWith('/platform')) return 'platform';
  if (_adminHrefs.any((h) => _under(href, h))) return 'settings';
  for (final (prefix, area) in _pathAreas) {
    if (_under(href, prefix)) return area;
  }
  if (item.isErp) return _moduleArea[item.module ?? 'inventory'] ?? 'inventory';
  return 'vouchflow';
}

/// Whether an entry is open to this caller (the web's `erpEntryVisible`):
/// VouchFlow's own entries follow the role, ERP entries need the company
/// set up, their module switched on and one of their permissions.
bool erpEntryVisible(VfNavItem item, ErpConfig? config) {
  if (!item.isErp) return true;
  if (config == null || !config.isSetUp) return false;
  return (item.module == null || config.has(item.module!)) && item.permissions.any(config.can);
}

/// Account pages live in the user menu, not in any app's menu.
const _accountHrefs = ['/notifications', '/profile'];

/// What a person can reach, grouped by app (the web's `useAreas`): read by
/// the shell, the launcher and the switcher so all three always agree.
class VfApps {
  const VfApps({required this.items, required this.byArea, required this.open, required this.off});

  /// Every entry this person may open, in menu order.
  final List<VfNavItem> items;
  final Map<String, List<VfNavItem>> byArea;

  /// The apps holding at least one of [items], in launcher order.
  final List<VfArea> open;

  /// Apps the plan allows but the company has not switched on, offered to
  /// the people who can switch them on.
  final List<VfArea> off;

  bool get multi => open.length > 1;

  List<VfNavItem> menuOf(String area) => byArea[area] ?? const [];

  /// The app's first entry: where opening it lands.
  String? homeOf(String area) => byArea[area]?.firstOrNull?.href;

  /// The app owning [href], or null for an account page or the launcher.
  String? areaOfHref(String href) {
    for (final entry in byArea.entries) {
      if (entry.value.any((i) => i.href == href)) return entry.key;
    }
    return null;
  }

  static VfApps of(AppUser user, ErpConfig? config) {
    final platformOnly = user.isSuperAdmin;
    final candidates = [...navFor(user.role), if (!platformOnly) ...erpAppNav];
    final items = candidates.where((item) {
      if (_accountHrefs.contains(item.href)) return false;
      if (!erpEntryVisible(item, config)) return false;
      if (user.role == 'company_admin' && settingsChildren.contains(item.href)) return false;
      return true;
    }).toList();

    final byArea = <String, List<VfNavItem>>{};
    for (final item in items) {
      // The platform operator runs one app, the platform: their overview,
      // audit log and settings all belong to it.
      final key = platformOnly ? 'platform' : areaOf(item);
      (byArea[key] ??= []).add(item);
    }

    final open = vfAreas.where((a) => byArea.containsKey(a.key)).toList();
    final off = config != null && config.can('erp.configure')
        ? vfAreas
              .where(
                (a) =>
                    a.module != null &&
                    !byArea.containsKey(a.key) &&
                    config.liveModules.contains(a.module) &&
                    !config.modules.contains(a.module) &&
                    (config.licensedModules == null || config.licensedModules!.contains(a.module)),
              )
              .toList()
        : <VfArea>[];

    return VfApps(items: items, byArea: byArea, open: open, off: off);
  }
}
