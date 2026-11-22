import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'cashbook_page.dart';
import 'finance_lists_page.dart';
import 'finance_overview_page.dart';
import 'reports_page.dart';

/*
 * The Finance app (the web's lib/modules/finance.ts menu with the core
 * accounts and journals): the cash position, bank and cash accounts, the
 * journals and the reports as its tab bar, then the cashbook in the
 * drawer. Its "+" records a receipt or a payment in the cashbook.
 */

const _accounting = 'accounting';

const financeNav = [
  VfNavItem(
    '/erp/finance',
    'fin.nav.overview',
    PhosphorIconsRegular.house,
    PhosphorIconsFill.house,
    module: _accounting,
    permissions: ['finance.view'],
  ),
  VfNavItem(
    '/erp/finance/banks',
    'fin.nav.banks',
    PhosphorIconsRegular.bank,
    PhosphorIconsFill.bank,
    module: _accounting,
    permissions: ['finance.view'],
  ),
  VfNavItem(
    '/erp/finance/journals',
    'fin.nav.journals',
    PhosphorIconsRegular.notebook,
    PhosphorIconsFill.notebook,
    module: _accounting,
    permissions: ['accounting.view'],
  ),
  VfNavItem(
    '/erp/finance/reports',
    'fin.nav.reports',
    PhosphorIconsRegular.chartLineUp,
    PhosphorIconsFill.chartLineUp,
    module: _accounting,
    permissions: ['finance.statements', 'accounting.view'],
  ),
  VfNavItem(
    '/erp/finance/cashbook',
    'fin.nav.cashbook',
    PhosphorIconsRegular.bookOpenText,
    PhosphorIconsFill.bookOpenText,
    module: _accounting,
    permissions: ['finance.view'],
  ),
];

const financeCreateActions = [
  VfCreateAction(
    label: 'fin.newPayment',
    hint: 'fin.newPaymentHint',
    icon: PhosphorIconsRegular.arrowCircleUp,
    route: Routes.finCashbookNew,
    arguments: {'type': 'payment'},
    permission: 'finance.cashbook',
  ),
  VfCreateAction(
    label: 'fin.newReceipt',
    hint: 'fin.newReceiptHint',
    icon: PhosphorIconsRegular.arrowCircleDown,
    route: Routes.finCashbookNew,
    arguments: {'type': 'receipt'},
    permission: 'finance.cashbook',
  ),
];

final financeApp = VfAppModule(
  area: 'finance',
  nav: financeNav,
  pages: {
    '/erp/finance': (_) => const FinanceOverviewPage(),
    '/erp/finance/banks': (_) => const BankAccountsPage(),
    '/erp/finance/journals': (_) => const JournalsPage(),
    '/erp/finance/reports': (_) => const ReportsPage(),
    '/erp/finance/cashbook': (_) => const CashbookPage(),
  },
  create: financeCreateActions,
);
