import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'overview_page.dart';
import 'registers.dart';

/*
 * The Sales app, as the shell sees it (the web's lib/modules/sales.ts nav
 * and CREATE_ACTIONS.sales): its menu, the first four of which a person
 * may open are its tab bar, the page for each, and what its "+" creates.
 * Price lists, returns and the reports stay on the web for now.
 */

const _sales = 'sales';

const salesNav = [
  VfNavItem(
    '/erp/sales',
    'sal.nav.overview',
    PhosphorIconsRegular.chartLineUp,
    PhosphorIconsFill.chartLineUp,
    module: _sales,
    permissions: ['sales.view'],
  ),
  VfNavItem(
    '/erp/sales/orders',
    'sal.nav.orders',
    PhosphorIconsRegular.shoppingCart,
    PhosphorIconsFill.shoppingCart,
    module: _sales,
    permissions: ['sales.view'],
  ),
  VfNavItem(
    '/erp/sales/invoices',
    'sal.nav.invoices',
    PhosphorIconsRegular.receipt,
    PhosphorIconsFill.receipt,
    module: _sales,
    permissions: ['sales.view'],
  ),
  VfNavItem(
    '/erp/customers',
    'sal.nav.customers',
    PhosphorIconsRegular.usersThree,
    PhosphorIconsFill.usersThree,
    module: _sales,
    permissions: ['customers.view'],
  ),
  VfNavItem(
    '/erp/sales/quotations',
    'sal.nav.quotations',
    PhosphorIconsRegular.notePencil,
    PhosphorIconsFill.notePencil,
    module: _sales,
    permissions: ['sales.view'],
  ),
  VfNavItem(
    '/erp/sales/receipts',
    'sal.nav.receipts',
    PhosphorIconsRegular.handCoins,
    PhosphorIconsFill.handCoins,
    module: _sales,
    permissions: ['sales.view'],
  ),
];

/// What a salesperson or cashier starts on the phone, each behind the
/// permission the API checks for it.
const salesCreateActions = [
  VfCreateAction(
    label: 'sal.newOrder',
    hint: 'sal.hint.order',
    icon: PhosphorIconsRegular.shoppingCart,
    route: Routes.salesDocumentNew,
    arguments: {'quotation': false},
    permission: 'sales.order',
  ),
  VfCreateAction(
    label: 'sal.newQuotation',
    hint: 'sal.hint.quotation',
    icon: PhosphorIconsRegular.notePencil,
    route: Routes.salesDocumentNew,
    arguments: {'quotation': true},
    permission: 'sales.quote',
  ),
  VfCreateAction(
    label: 'sal.receivePayment',
    hint: 'sal.hint.receipt',
    icon: PhosphorIconsRegular.handCoins,
    route: Routes.salesReceiptNew,
    permission: 'sales.receipt',
  ),
];

final salesApp = VfAppModule(
  area: _sales,
  nav: salesNav,
  pages: {
    '/erp/sales': (_) => const SalesOverviewPage(),
    '/erp/sales/orders': (_) => const SalesOrdersPage(),
    '/erp/sales/invoices': (_) => const SalesInvoicesPage(),
    '/erp/customers': (_) => const SalesCustomersPage(),
    '/erp/sales/quotations': (_) => const SalesQuotationsPage(),
    '/erp/sales/receipts': (_) => const SalesReceiptsPage(),
  },
  create: salesCreateActions,
);
