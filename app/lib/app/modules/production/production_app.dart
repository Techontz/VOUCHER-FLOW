import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'boms_page.dart';
import 'orders_page.dart';
import 'overview_page.dart';
import 'qc_page.dart';

/*
 * The Production app, as the shell sees it (the web's lib/modules/
 * production.ts): the floor's home, its orders, the quality-control queue
 * and the bills of materials, all behind production.view; the "+" plans an
 * order for whoever holds production.plan.
 */

const _production = 'production';

const productionNav = [
  VfNavItem(
    '/erp/production',
    'prd.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _production,
    permissions: ['production.view'],
  ),
  VfNavItem(
    '/erp/production/orders',
    'prd.nav.orders',
    PhosphorIconsRegular.clipboardText,
    PhosphorIconsFill.clipboardText,
    module: _production,
    permissions: ['production.view'],
  ),
  VfNavItem(
    '/erp/production/qc',
    'prd.nav.qc',
    PhosphorIconsRegular.sealCheck,
    PhosphorIconsFill.sealCheck,
    module: _production,
    permissions: ['production.view'],
  ),
  VfNavItem(
    '/erp/production/boms',
    'prd.nav.boms',
    PhosphorIconsRegular.listChecks,
    PhosphorIconsFill.listChecks,
    module: _production,
    permissions: ['production.view'],
  ),
];

const productionCreateActions = [
  VfCreateAction(
    label: 'prd.newOrder',
    hint: 'prd.newOrderHint',
    icon: PhosphorIconsRegular.factory,
    route: Routes.prdOrderNew,
    permission: 'production.plan',
  ),
];

final productionApp = VfAppModule(
  area: _production,
  nav: productionNav,
  pages: {
    '/erp/production': (_) => const ProductionOverviewPage(),
    '/erp/production/orders': (_) => const ProductionOrdersPage(),
    '/erp/production/qc': (_) => const QcQueuePage(),
    '/erp/production/boms': (_) => const BomsPage(),
  },
  create: productionCreateActions,
);
