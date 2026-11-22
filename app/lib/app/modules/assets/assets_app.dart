import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'assets_pages.dart';

/*
 * The Assets app (the web's /erp/assets): the overview, the register and
 * the monthly depreciation runs. Registering, capitalising, transferring
 * and disposing need the accounts and funding a desk gives room for, so
 * they stay on the web; the phone reads the register and each asset's
 * history and schedule.
 */

const _assets = 'assets';

const assetsNav = [
  VfNavItem(
    '/erp/assets',
    'ast.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _assets,
    permissions: ['assets.view'],
  ),
  VfNavItem(
    '/erp/assets/register',
    'ast.nav.register',
    PhosphorIconsRegular.buildings,
    PhosphorIconsFill.buildings,
    module: _assets,
    permissions: ['assets.view'],
  ),
  VfNavItem(
    '/erp/assets/depreciation',
    'ast.nav.depreciation',
    PhosphorIconsRegular.trendDown,
    PhosphorIconsFill.trendDown,
    module: _assets,
    permissions: ['assets.view'],
  ),
];

final assetsApp = VfAppModule(
  area: _assets,
  nav: assetsNav,
  pages: {
    '/erp/assets': (_) => const AssetsOverviewPage(),
    '/erp/assets/register': (_) => const AssetRegisterPage(),
    '/erp/assets/depreciation': (_) => const DepreciationRunsPage(),
  },
);
