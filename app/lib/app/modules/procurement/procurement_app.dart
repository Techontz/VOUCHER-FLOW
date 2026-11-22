import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'lists_page.dart';
import 'overview_page.dart';

/*
 * The Procurement app, as the shell sees it (the web's lib/modules/
 * procurement.ts menu): the overview, requisitions, orders and supplier
 * invoices as its tab bar, then payments, suppliers and the payables
 * ageing in the drawer. Its "+" raises a purchase requisition; orders,
 * invoices and payments are prepared on the web, where the three-way match
 * has the room it needs.
 */

const _procurement = 'procurement';

const procurementNav = [
  VfNavItem(
    '/erp/procurement',
    'prc.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _procurement,
    permissions: ['procurement.view'],
  ),
  VfNavItem(
    '/erp/procurement/requisitions',
    'prc.nav.requisitions',
    PhosphorIconsRegular.clipboardText,
    PhosphorIconsFill.clipboardText,
    short: 'prc.nav.requisitionsShort',
    module: _procurement,
    permissions: ['procurement.view'],
  ),
  VfNavItem(
    '/erp/procurement/orders',
    'prc.nav.orders',
    PhosphorIconsRegular.shoppingCart,
    PhosphorIconsFill.shoppingCart,
    module: _procurement,
    permissions: ['procurement.view'],
  ),
  VfNavItem(
    '/erp/procurement/invoices',
    'prc.nav.invoices',
    PhosphorIconsRegular.receipt,
    PhosphorIconsFill.receipt,
    module: _procurement,
    permissions: ['procurement.view'],
  ),
  VfNavItem(
    '/erp/procurement/payments',
    'prc.nav.payments',
    PhosphorIconsRegular.handCoins,
    PhosphorIconsFill.handCoins,
    module: _procurement,
    permissions: ['procurement.view'],
  ),
  VfNavItem(
    '/erp/suppliers',
    'prc.nav.suppliers',
    PhosphorIconsRegular.truck,
    PhosphorIconsFill.truck,
    module: _procurement,
    permissions: ['suppliers.view'],
  ),
  VfNavItem(
    '/erp/procurement/ageing',
    'prc.nav.ageing',
    PhosphorIconsRegular.hourglassMedium,
    PhosphorIconsFill.hourglassMedium,
    module: _procurement,
    permissions: ['procurement.view'],
  ),
];

/// What the Procurement "+" prepares on the phone.
const procurementCreateActions = [
  VfCreateAction(
    label: 'prc.newRequisition',
    hint: 'prc.newRequisitionHint',
    icon: PhosphorIconsRegular.notePencil,
    route: Routes.prcRequisitionNew,
    permission: 'procurement.request',
  ),
];

final procurementApp = VfAppModule(
  area: _procurement,
  nav: procurementNav,
  pages: {
    '/erp/procurement': (_) => const ProcurementOverviewPage(),
    '/erp/procurement/requisitions': (_) => const RequisitionsPage(),
    '/erp/procurement/orders': (_) => const OrdersPage(),
    '/erp/procurement/invoices': (_) => const SupplierInvoicesPage(),
    '/erp/procurement/payments': (_) => const SupplierPaymentsPage(),
    '/erp/suppliers': (_) => const SuppliersPage(),
    '/erp/procurement/ageing': (_) => const AgeingPage(),
  },
  create: procurementCreateActions,
);
