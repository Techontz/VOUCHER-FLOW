// The Procurement, Finance and Assets apps against the in-app mock, in
// light and dark at a 360px phone width: which menus a person is offered,
// the overviews, approving a requisition, raising a payment voucher from a
// supplier invoice, the reports, recording a cashbook payment, and an
// asset's page.

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
import 'package:vouchflow/app/modules/assets/assets_pages.dart';
import 'package:vouchflow/app/modules/finance/cashbook_page.dart';
import 'package:vouchflow/app/modules/finance/detail_pages.dart';
import 'package:vouchflow/app/modules/finance/finance_overview_page.dart';
import 'package:vouchflow/app/modules/finance/reports_page.dart';
import 'package:vouchflow/app/modules/procurement/invoice_page.dart';
import 'package:vouchflow/app/modules/procurement/lists_page.dart';
import 'package:vouchflow/app/modules/procurement/overview_page.dart';
import 'package:vouchflow/app/modules/procurement/requisition_page.dart';
import 'package:vouchflow/app/modules/procurement/supplier_page.dart';
import 'package:vouchflow/app/modules/shell/areas.dart';
import 'package:vouchflow/app/routes/routes.dart';
import 'package:vouchflow/app/widgets/vf/vf.dart';

import 'support/mock_sign_in.dart';

Future<MockApi> _signIn(WidgetTester tester, String email, {void Function(MockApi mock)? setup}) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi(instant: true);
  mock.erp.modules.add('assets');
  setup?.call(mock);
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

/// Where a raised voucher lands, standing in for the voucher page.
class _VoucherStub extends StatelessWidget {
  const _VoucherStub();

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Voucher ${Get.arguments}')));
}

Widget _app(Widget home, ThemeMode mode) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  getPages: [
    GetPage(name: Routes.voucher, page: () => const _VoucherStub()),
    GetPage(name: Routes.prcRequisition, page: () => const RequisitionPage()),
    GetPage(name: Routes.prcInvoice, page: () => const SupplierInvoicePage()),
    GetPage(name: Routes.prcSupplier, page: () => const SupplierPage()),
    GetPage(name: Routes.finJournal, page: () => const JournalPage()),
    GetPage(name: Routes.finCashbookEntry, page: () => const CashbookEntryPage()),
    GetPage(name: Routes.astAsset, page: () => const AssetPage()),
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

/// Lets a confirmation toast run out so no timer outlives the test.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester, 10);
}

Future<void> _scrollTo(WidgetTester tester, Finder target) => tester.scrollUntilVisible(
  target,
  200,
  scrollable: find.byType(Scrollable).first,
);

const _modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

Future<ErpConfig> _config(MockApi mock) async =>
    ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);

void main() {
  tearDown(Get.reset);

  group('menus', () {
    test('an administrator gets all three apps with their tabs', () async {
      final mock = MockApi(instant: true)..erp.modules.add('assets');
      final data = await mockSignIn(mock, 'admin@watercom.test');
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), await _config(mock));
      expect(apps.open.map((a) => a.key), containsAll(['procurement', 'finance', 'assets']));
      expect(apps.menuOf('procurement').map((i) => i.href).take(4), [
        '/erp/procurement', '/erp/procurement/requisitions', '/erp/procurement/orders', '/erp/procurement/invoices',
      ]);
      expect(apps.menuOf('procurement').map((i) => i.href), contains('/erp/suppliers'));
      expect(apps.menuOf('finance').map((i) => i.href), [
        '/erp/finance', '/erp/finance/banks', '/erp/finance/journals', '/erp/finance/reports', '/erp/finance/cashbook',
      ]);
      expect(apps.menuOf('assets').map((i) => i.href), ['/erp/assets', '/erp/assets/register', '/erp/assets/depreciation']);
    });

    test('a ledger reader without finance permissions sees journals and reports only', () async {
      final mock = MockApi(instant: true);
      mock.erp.permissionsFor['joseph@watercom.test'] = ['accounting.view'];
      final data = await mockSignIn(mock, 'joseph@watercom.test');
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), await _config(mock));
      expect(apps.menuOf('finance').map((i) => i.href), ['/erp/finance/journals', '/erp/finance/reports']);
      expect(apps.open.map((a) => a.key), isNot(contains('procurement')));
    });
  });

  for (final entry in _modes.entries) {
    group('in ${entry.key}', () {
      final mode = entry.value;

      testWidgets('the procurement overview shows what is waiting and owed', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: ProcurementOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Open requisitions'), findsOneWidget);
        expect(find.text('Orders to approve'), findsOneWidget);
        expect(find.text('Invoices to match'), findsOneWidget);
        expect(find.text('Owed to suppliers'), findsOneWidget);
        await _scrollTo(tester, find.text('Recent orders'));
        expect(find.text('Kariakoo Packaging Traders'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an approver approves a submitted requisition', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: RequisitionsPage()), mode));
        await _settle(tester);

        // An approver lands on what is waiting.
        expect(find.text('Service the factory compressor before the peak'), findsOneWidget);
        expect(find.text('Labels for the new 1.5 litre artwork'), findsNothing);
        await tester.tap(find.text('Service the factory compressor before the peak'));
        await _settle(tester);
        expect(find.byType(RequisitionPage), findsOneWidget);

        await tester.tap(find.widgetWithText(VouchFlowButton, 'Approve').last);
        await _settle(tester, 4);
        expect(find.text('Approve PRQ-2026-000003?'), findsOneWidget);
        await tester.tap(find.widgetWithText(VouchFlowButton, 'Approve').last);
        await _settle(tester, 6);

        final r = mock.erp.finance.requisitions.firstWhere((r) => r['id'] == 3);
        expect(r['status'], 'approved');
        expect(find.text('Approved'), findsWidgets);
        await _drainToast(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a posted invoice raises a payment voucher, then links to it', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: SupplierInvoicesPage()), mode));
        await _settle(tester);

        await tester.tap(find.textContaining('EAPI-INV-4519').first);
        await _settle(tester);
        expect(find.text('Three-way match'), findsOneWidget);
        await tester.tap(find.text('Raise payment voucher'));
        await _settle(tester, 4);
        expect(find.textContaining('Raise a payment voucher for TZS 1,062,000'), findsOneWidget);
        await tester.tap(find.text('Raise payment voucher').last);
        await _settle(tester, 6);

        expect(mock.erp.finance.vouchers[2]?['number'], 'PV-2026-009001');
        // The new voucher opens, as on the web.
        expect(find.text('Voucher 9001'), findsOneWidget);
        Get.back();
        await _settle(tester, 6);
        // Back on the invoice: the link replaces the button.
        expect(find.text('Voucher PV-2026-009001'), findsOneWidget);
        expect(find.text('Raise payment voucher'), findsNothing);
        await _drainToast(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a supplier statement runs from opening to closing balance', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: SuppliersPage()), mode));
        await _settle(tester);
        await tester.tap(find.text('Mlimani Tyre Centre'));
        await _settle(tester);
        expect(find.text('Statement'), findsOneWidget);
        await _scrollTo(tester, find.text('Closing balance'));
        expect(find.text('TZS 2,832,000'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the finance overview shows the cash position and the month', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: FinanceOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Cash and bank'), findsOneWidget);
        expect(find.text('Owed to you'), findsOneWidget);
        expect(find.text('You owe'), findsOneWidget);
        await _scrollTo(tester, find.text('Cash position'));
        expect(find.text('Gross profit'), findsOneWidget);
        await _scrollTo(tester, find.text('NMB Bank: operations'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the reports read as phone statements', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: ReportsPage()), mode));
        await _settle(tester);

        expect(find.text('Profit & loss'), findsWidgets);
        expect(find.text('Sales revenue'), findsOneWidget);
        await _scrollTo(tester, find.text('Net profit'));

        await tester.ensureVisible(find.text('Balance sheet'));
        await _settle(tester, 2);
        await tester.tap(find.text('Balance sheet'));
        await _settle(tester);
        expect(find.text('Balanced'), findsOneWidget);
        expect(find.text('Plant & machinery'), findsOneWidget);

        await tester.ensureVisible(find.text('Trial balance'));
        await _settle(tester, 2);
        await tester.tap(find.text('Trial balance'));
        await _settle(tester);
        expect(find.text('Cash on hand'), findsOneWidget);
        await _scrollTo(tester, find.text('Total debits'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a cashbook payment is saved as a draft', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const CashbookFormPage(type: 'payment'), mode));
        await _settle(tester);

        expect(find.text('Record a payment'), findsWidgets);
        await tester.enterText(find.byType(TextField).at(0), '180000');
        await tester.tap(find.text('Choose an account'));
        await _settle(tester, 4);
        await tester.tap(find.text('Utilities'));
        await _settle(tester, 4);
        await tester.enterText(find.byType(TextField).at(2), 'Internet, November');
        await _settle(tester, 2);
        await tester.tap(find.text('Save draft'));
        await _settle(tester, 6);

        final saved = mock.erp.finance.cashbook.first;
        expect(saved['description'], 'Internet, November');
        expect(saved['status'], 'draft');
        expect(saved['account_id'], 27);
        expect(find.byType(CashbookEntryPage), findsOneWidget);
        expect(find.text('Post to ledger'), findsOneWidget);
        await _drainToast(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the assets overview and an asset with its schedule', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: AssetsOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Book value'), findsOneWidget);
        expect(find.text('Assets in use'), findsOneWidget);
        await tester.pumpWidget(_app(const Scaffold(body: AssetRegisterPage()), mode));
        await _settle(tester);
        await tester.tap(find.text('Isuzu FVR delivery truck'));
        await _settle(tester);
        expect(find.byType(AssetPage), findsOneWidget);
        expect(find.text('Where and with whom'), findsOneWidget);
        await _scrollTo(tester, find.text('Months ahead'));
        await _scrollTo(tester, find.text('History'));
        expect(find.text('Capitalised'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}

