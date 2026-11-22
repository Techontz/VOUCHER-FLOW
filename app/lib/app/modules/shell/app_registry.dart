import 'package:flutter/widgets.dart';

import '../erp/web_only_page.dart';
import '../inventory/inventory_app.dart';
import '../procurement/procurement_app.dart';
import '../finance/finance_app.dart';
import '../assets/assets_app.dart';
import '../sales/sales_app.dart';
import '../dispatch/dispatch_app.dart';
import '../production/production_app.dart';
import '../crm/crm_app.dart';
import '../files/files_app.dart';
import '../fleet/fleet_app.dart';
import '../hr/hr_app.dart';
import 'nav.dart';

/*
 * The ERP apps the shell can open, one entry each, the app's counterpart of
 * the web's lib/modules/index.ts.
 *
 * To bring an app to the phone, write its module (see inventory/) and
 * replace its `webOnlyApp(...)` line below with it. The shell, launcher,
 * switcher and tab bar pick it up from here; nothing else changes.
 */

/// Something an app's "+" creates (the web's CREATE_ACTIONS): a pushed
/// page ([route] with [arguments]) or one of the app's own tabs ([route]
/// equal to one of its menu entries).
class VfCreateAction {
  const VfCreateAction({
    required this.label,
    required this.icon,
    required this.route,
    this.arguments,
    this.hint,
    this.permission,
  });

  final String label; // translation key
  final String? hint; // translation key
  final IconData icon;
  final String route;
  final Object? arguments;

  /// The ERP permission it needs; null when the role decides.
  final String? permission;
}

/// One ERP app's contribution to the shell.
class VfAppModule {
  const VfAppModule({
    required this.area,
    required this.nav,
    required this.pages,
    this.create = const [],
  });

  /// The area key it fills ('inventory', 'sales' …).
  final String area;

  /// Its menu entries, home first. The first four the person may open are
  /// its tab bar; the drawer lists them all.
  final List<VfNavItem> nav;

  /// The page shown inside the shell for each of its entries.
  final Map<String, WidgetBuilder> pages;

  /// What its "+" in the top bar offers.
  final List<VfCreateAction> create;
}

/// Every ERP app, in the web's menu order.
final List<VfAppModule> vfAppModules = [
  inventoryApp,
  salesApp,
  procurementApp,
  financeApp,
  assetsApp,
  productionApp,
  dispatchApp,
  fleetApp,
  hrApp,
  crmApp,
  filesApp,
];

/// Every ERP menu entry, filtered per person in [VfApps.of].
List<VfNavItem> get erpAppNav => [for (final app in vfAppModules) ...app.nav];

/// The page for an ERP entry, or null when no app owns [href].
Widget? erpPageFor(String href, BuildContext context) {
  for (final app in vfAppModules) {
    final builder = app.pages[href];
    if (builder != null) return builder(context);
  }
  return null;
}

/// What the "+" offers inside [area].
List<VfCreateAction> createActionsFor(String area) =>
    vfAppModules.where((a) => a.area == area).firstOrNull?.create ?? const [];

/// An app that is not on the phone yet: one entry, opening a page that
/// says so and points to the web. Its gates match the web's menu, so the
/// launcher offers it to exactly the people the web does.
VfAppModule webOnlyApp(
  String area,
  String href,
  IconData icon,
  IconData activeIcon, {
  required String module,
  required List<String> permissions,
}) => VfAppModule(
  area: area,
  nav: [
    VfNavItem(href, 'area.$area', icon, activeIcon, module: module, permissions: permissions),
  ],
  pages: {href: (_) => ErpWebOnlyPage(area: area)},
);
