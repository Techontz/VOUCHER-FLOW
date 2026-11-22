import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/erp_models.dart';
import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'count_page.dart';
import 'documents_page.dart';
import 'overview_page.dart';
import 'stock_page.dart';

/*
 * The Inventory app, as the shell sees it: its menu (the first four the
 * person may open are its tab bar), the page for each entry, and what its
 * "+" creates. This file is the pattern for every other app: copy it,
 * point its entries at the module's routes and permissions, and register
 * the result in shell/app_registry.dart.
 */

const _inventory = 'inventory';

const inventoryNav = [
  VfNavItem(
    '/erp',
    'inv.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _inventory,
    permissions: ['inventory.view'],
  ),
  VfNavItem(
    '/erp/stock',
    'inv.nav.stock',
    PhosphorIconsRegular.stack,
    PhosphorIconsFill.stack,
    module: _inventory,
    permissions: ['inventory.view'],
  ),
  // A tab of its own, so a storekeeper on the floor is one tap from it.
  VfNavItem(
    '/erp/count',
    'inv.nav.count',
    PhosphorIconsRegular.listNumbers,
    PhosphorIconsFill.listNumbers,
    module: _inventory,
    permissions: ['inventory.adjust'],
  ),
  VfNavItem(
    '/erp/documents',
    'inv.nav.documents',
    PhosphorIconsRegular.clipboardText,
    PhosphorIconsFill.clipboardText,
    module: _inventory,
    permissions: ['inventory.view'],
  ),
];

/// The documents Inventory prepares, each behind the permission the API
/// checks for it (the web's CREATE_ACTIONS.inventory).
const inventoryCreateActions = [
  VfCreateAction(
    label: 'inv.doc.grn',
    hint: 'inv.hint.grn',
    icon: PhosphorIconsRegular.trayArrowDown,
    route: Routes.erpDocumentNew,
    arguments: {'type': ErpDocType.grn},
    permission: 'inventory.receive',
  ),
  VfCreateAction(
    label: 'inv.doc.issue',
    hint: 'inv.hint.issue',
    icon: PhosphorIconsRegular.trayArrowUp,
    route: Routes.erpDocumentNew,
    arguments: {'type': ErpDocType.issue},
    permission: 'inventory.issue',
  ),
  VfCreateAction(
    label: 'inv.doc.transfer',
    hint: 'inv.hint.transfer',
    icon: PhosphorIconsRegular.arrowsLeftRight,
    route: Routes.erpDocumentNew,
    arguments: {'type': ErpDocType.transfer},
    permission: 'inventory.transfer',
  ),
  VfCreateAction(
    label: 'inv.doc.count',
    hint: 'inv.hint.count',
    icon: PhosphorIconsRegular.listNumbers,
    route: '/erp/count',
    permission: 'inventory.adjust',
  ),
];

final inventoryApp = VfAppModule(
  area: _inventory,
  nav: inventoryNav,
  pages: {
    '/erp': (_) => const InventoryOverviewPage(),
    '/erp/stock': (_) => const StockPage(),
    '/erp/count': (_) => const StockCountPage(),
    '/erp/documents': (_) => const DocumentsPage(),
  },
  create: inventoryCreateActions,
);
