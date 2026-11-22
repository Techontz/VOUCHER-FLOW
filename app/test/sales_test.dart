// The Sales and Dispatch apps against the in-app mock, in light and dark,
// at a 360px phone width: what each app offers, the overview, approving
// an order, taking a new order on the phone, a customer's statement,
// receiving and verifying a payment, and a truck from the loading bay to
// the customer's signature.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/erp_models.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/erp_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/data/services/voucher_repository.dart';
import 'package:vouchflow/app/modules/dispatch/loading_form_page.dart';
import 'package:vouchflow/app/modules/dispatch/loading_list_page.dart';
import 'package:vouchflow/app/modules/dispatch/loading_page.dart';
import 'package:vouchflow/app/modules/dispatch/verification_page.dart';
import 'package:vouchflow/app/modules/sales/customer_page.dart';
import 'package:vouchflow/app/modules/sales/invoice_page.dart';
import 'package:vouchflow/app/modules/sales/order_form_page.dart';
import 'package:vouchflow/app/modules/sales/order_page.dart';
import 'package:vouchflow/app/modules/sales/overview_page.dart';
import 'package:vouchflow/app/modules/sales/quotation_page.dart';
import 'package:vouchflow/app/modules/sales/receipt_form_page.dart';
import 'package:vouchflow/app/modules/sales/receipt_page.dart';
import 'package:vouchflow/app/modules/sales/registers.dart';
import 'package:vouchflow/app/modules/shell/areas.dart';
import 'package:vouchflow/app/routes/routes.dart';

import 'support/mock_sign_in.dart';

Future<MockApi> _signIn(WidgetTester tester, String email) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi(instant: true);
  mock.erp.modules.add('dispatch');
  final api = await ApiService(mock: mock).init();
  Get.put(api);
  Get.put(VoucherRepository(api));
  final data = await mockSignIn(mock, email);
  final session = SessionService(api);
  Get.put(session);
  session.user.value = AppUser.fromJson(data['user'] as Map<String, dynamic>);
  session.company.value = Company.fromJson(data['company'] as Map<String, dynamic>);
  final erp = Get.put(ErpService(api, session));
  await erp.ensure();
  return mock;
}

Widget _app(Widget home, ThemeMode mode) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  getPages: [
    GetPage(name: Routes.salesOrder, page: () => const SalesOrderPage()),
    GetPage(name: Routes.salesQuotation, page: () => const SalesQuotationPage()),
    GetPage(name: Routes.salesInvoice, page: () => const SalesInvoicePage()),
    GetPage(name: Routes.salesReceipt, page: () => const SalesReceiptPage()),
    GetPage(name: Routes.salesCustomer, page: () => const SalesCustomerPage()),
    GetPage(name: Routes.salesDocumentNew, page: () => const SalesDocumentFormPage()),
    GetPage(name: Routes.salesReceiptNew, page: () => const SalesReceiptFormPage()),
    GetPage(name: Routes.dispatchLoading, page: () => const LoadingOrderPage()),
    GetPage(name: Routes.dispatchLoadingNew, page: () => const LoadingFormPage()),
  ],
  home: home,
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets a confirmation toast run out and slide away.
Future<void> _toastAway(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester, 6);
}

Future<void> _tapText(WidgetTester tester, String text, {bool last = true}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  await tester.ensureVisible(f);
  await _settle(tester, 2);
  await tester.tap(f);
  await _settle(tester, 6);
}

const _modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

void main() {
  tearDown(Get.reset);

  test('the Sales and Dispatch apps: their menus, for an administrator', () async {
    final mock = MockApi(instant: true)..erp.modules.add('dispatch');
    final data = await mockSignIn(mock, 'admin@watercom.test');
    final config = ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);
    final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
    expect(apps.open.map((a) => a.key), containsAll(['sales', 'dispatch']));
    expect(apps.menuOf('sales').map((i) => i.href), [
      '/erp/sales', '/erp/sales/orders', '/erp/sales/invoices', '/erp/customers', '/erp/sales/quotations', '/erp/sales/receipts', //
    ]);
    expect(apps.menuOf('dispatch').map((i) => i.href), ['/erp/dispatch', '/erp/dispatch/deliveries', '/erp/dispatch/verification']);
  });

  test('a storekeeper sees loading, not verification', () async {
    final mock = MockApi(instant: true)..erp.modules.add('dispatch');
    mock.erp.permissionsFor['joseph@watercom.test'] = ['dispatch.view', 'dispatch.load'];
    final data = await mockSignIn(mock, 'joseph@watercom.test');
    final config = ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);
    final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
    expect(apps.menuOf('dispatch').map((i) => i.href), ['/erp/dispatch', '/erp/dispatch/deliveries']);
    expect(apps.menuOf('sales'), isEmpty);
  });

  for (final entry in _modes.entries) {
    group('in ${entry.key}', () {
      final mode = entry.value;

      testWidgets('the overview shows the month and what needs action', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: SalesOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Sales this month'), findsOneWidget);
        expect(find.text('Received this month'), findsOneWidget);
        expect(find.text('Receivables'), findsOneWidget);
        expect(find.text('Overdue'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Order pipeline'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Orders awaiting approval'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Recent orders'), 200, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });

      testWidgets('approve an order waiting for approval', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: SalesOrdersPage()), mode));
        await _settle(tester);

        expect(find.text('Sales orders'), findsOneWidget);
        await _tapText(tester, 'Awaiting approval', last: false);
        expect(find.text('Serena Hotel Dar es Salaam'), findsOneWidget);
        await _tapText(tester, 'Serena Hotel Dar es Salaam');

        expect(find.byType(SalesOrderPage), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Credit policy'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Within the credit policy'), findsOneWidget);
        await _tapText(tester, 'Approve');
        expect(find.text('Approve SO-${DateTime.now().year}-000002?'), findsOneWidget);
        await tester.tap(find.text('Approve').last);
        await _settle(tester, 6);

        expect(mock.erp.sales.orders[1]['status'], 'ready');
        await _toastAway(tester);
        expect(find.text('As checked at approval'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('take a new order on the phone and submit it', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const SalesDocumentFormPage(quotation: false), mode));
        await _settle(tester);

        await _tapText(tester, 'Choose the customer');
        await _tapText(tester, 'Arusha Distributors');
        expect(find.textContaining('21 days credit'), findsWidgets);

        await _tapText(tester, 'Add product');
        await tester.enterText(find.byType(TextField).last, '500');
        await _settle(tester, 2);
        await _tapText(tester, 'Watercom 500ml × 24');
        // The wholesale price list applies.
        expect(find.text('8000'), findsOneWidget);
        await tester.tap(find.byTooltip('+1'));
        await _settle(tester, 2);

        await tester.tap(find.text('Submit'));
        await _settle(tester, 8);

        final order = mock.erp.sales.orders.last;
        expect(order['customer_id'], 5);
        expect(order['status'], 'submitted');
        final line = (order['lines'] as List).single as Map;
        expect(line['product_id'], 5);
        expect(double.parse('${line['quantity_ordered']}'), 2);
        expect(double.parse('${line['unit_price']}'), 8000);
        expect(find.byType(SalesOrderPage), findsOneWidget);
        await _toastAway(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets("a customer's statement and what they owe by age", (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const SalesCustomerPage(customerId: 4), mode));
        await _settle(tester);

        expect(find.text('Serena Hotel Dar es Salaam'), findsWidgets);
        expect(find.text('Balance due'), findsOneWidget);
        expect(find.text('What they owe, by age'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Closing balance'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Statement'), findsOneWidget);
        expect(find.text('Receive payment'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('receive a payment against an invoice', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        final invoice = mock.erp.sales.invoices.firstWhere((i) => i['customer_id'] == 4);
        await tester.pumpWidget(_app(SalesReceiptFormPage(customerId: 4, invoiceId: invoice['id'] as int), mode));
        await _settle(tester);

        expect(find.text('Apply to invoices'), findsOneWidget);
        expect(find.text(invoice['number'] as String), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '100000');
        await _settle(tester, 2);
        await tester.tap(find.textContaining('Record TZS'));
        await _settle(tester, 8);

        final receipt = mock.erp.sales.receipts.last;
        expect(receipt['status'], 'recorded');
        expect(double.parse('${receipt['amount']}'), 100000);
        expect(find.byType(SalesReceiptPage), findsOneWidget);
        await _toastAway(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('finance verifies a payment someone else recorded', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: VerificationPage()), mode));
        await _settle(tester);

        expect(find.text('Payments to verify'), findsOneWidget);
        expect(find.text('Mama Ntilie Kiosk Network'), findsWidgets);
        await _tapText(tester, 'Verify', last: false);
        expect(find.textContaining('Verify receipt'), findsOneWidget);
        await tester.tap(find.text('Verify').last);
        await _settle(tester, 8);

        expect(mock.erp.sales.receipts.first['status'], 'verified');
        // The prepayment order it paid is released for loading.
        expect(mock.erp.sales.orders[2]['status'], 'ready');
        await _toastAway(tester);
        expect(find.text('No payments waiting'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the warehouse loads a truck and confirms it', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        final open = mock.erp.sales.loadings.firstWhere((l) => l['status'] == 'open');
        await tester.pumpWidget(_app(LoadingOrderPage(loadingId: open['id'] as int), mode));
        await _settle(tester);

        expect(find.text('Next'), findsOneWidget);
        await tester.enterText(find.byType(TextField).at(0), '90');
        await tester.enterText(find.byType(TextField).at(1), '38');
        await _settle(tester, 2);
        await _tapText(tester, 'Save loaded quantities');
        await _toastAway(tester);
        await tester.tap(find.text('Confirm loading').last);
        await _settle(tester, 6);
        await tester.tap(find.text('Confirm loading').last);
        await _settle(tester, 8);

        expect(open['status'], 'loaded');
        expect(double.parse('${(open['lines'] as List)[1]['quantity_loaded']}'), 38);
        await _toastAway(tester);
        expect(find.text('Driver confirms'), findsOneWidget);
        expect(find.text('Gate confirms'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the driver records proof of delivery, short by two', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: DeliveriesPage()), mode));
        await _settle(tester);

        expect(find.text('On the road'), findsWidgets);
        await _tapText(tester, 'Record delivery');
        expect(find.byType(LoadingOrderPage), findsOneWidget);
        await tester.tap(find.text('Record delivery').last);
        await _settle(tester, 6);

        expect(find.text('Proof of delivery'), findsWidgets);
        await tester.enterText(find.byType(TextField).at(0), 'Abdul Karim');
        await tester.enterText(find.byType(TextField).at(2), '38');
        await _settle(tester, 2);
        expect(find.textContaining('Less than was loaded'), findsOneWidget);
        await tester.ensureVisible(find.text('Record delivery').last);
        await _settle(tester, 2);
        await tester.tap(find.text('Record delivery').last);
        await _settle(tester, 8);

        final lo = mock.erp.sales.loadings.firstWhere((l) => l['received_by_name'] == 'Abdul Karim' && l['status'] == 'delivered' && l['discrepancy_status'] == 'open' && l['delivery_remark'] == null);
        expect(double.parse('${(lo['lines'] as List)[0]['quantity_received']}'), 38);
        await _toastAway(tester);
        expect(find.text('Short delivery'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
