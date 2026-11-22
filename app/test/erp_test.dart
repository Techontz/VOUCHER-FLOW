// The ERP side of the app: the launcher (which apps a person is offered,
// and that one app skips it), the ring loader holding still under test,
// and the Inventory app's overview and stock count, against the in-app
// mock, in light and dark, at a 360px phone width.

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
import 'package:vouchflow/app/modules/apps/launcher_page.dart';
import 'package:vouchflow/app/modules/dashboard/dashboard_tab.dart';
import 'package:vouchflow/app/modules/inventory/count_page.dart';
import 'package:vouchflow/app/modules/inventory/document_page.dart';
import 'package:vouchflow/app/modules/inventory/overview_page.dart';
import 'package:vouchflow/app/modules/notifications/notifications_tab.dart';
import 'package:vouchflow/app/modules/profile/profile_tab.dart';
import 'package:vouchflow/app/modules/shell/areas.dart';
import 'package:vouchflow/app/modules/shell/shell_page.dart';
import 'package:vouchflow/app/routes/routes.dart';
import 'package:vouchflow/app/widgets/vf/vf.dart';

import 'support/mock_sign_in.dart';

/// Signs [email] in against an instant mock and registers the services the
/// shell and the ERP screens resolve.
Future<MockApi> _signIn(
  WidgetTester tester,
  String email, {
  void Function(MockApi mock)? setup,
}) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi(instant: true);
  setup?.call(mock);
  final api = await ApiService(mock: mock).init();
  Get.put(api);
  Get.put(VoucherRepository(api));
  final data = await mockSignIn(mock, email);
  final session = SessionService(api);
  Get.put(session);
  // Set directly rather than through startSessionFrom, which also applies
  // the account's theme and locale to a GetMaterialApp not built yet.
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
    GetPage(name: Routes.erpDocument, page: () => const DocumentPage()),
  ],
  home: home,
);

/// The shell with the controllers its route binding registers.
Widget _shell(ThemeMode mode) {
  Get.put(ShellController());
  Get.lazyPut(DashboardController.new);
  Get.lazyPut(NotificationsController.new);
  Get.lazyPut(ProfileController.new);
  return _app(const ShellPage(), mode);
}

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

const _modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

void main() {
  tearDown(Get.reset);

  test('the loader knows it is running under flutter test', () {
    expect(vfUnderTest, isTrue);
  });

  testWidgets('the ring loader holds still under test, so pages settle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: VfTheme.light(), home: const Scaffold(body: VfLoadingView())),
    );
    // pumpAndSettle times out on an endless animation; a still ring settles.
    await tester.pumpAndSettle();
    expect(find.byType(VfLoader), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  group('which apps a person is offered', () {
    test('a company administrator: what is on, and what the plan allows', () async {
      final mock = MockApi(instant: true);
      final data = await mockSignIn(mock, 'admin@watercom.test');
      final config = ErpConfig.fromJson(
        ((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>,
      );
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
      expect(apps.open.map((a) => a.key), [
        'vouchflow', 'inventory', 'sales', 'procurement', 'finance', 'settings', //
      ]);
      // Licensed but switched off, offered to someone who can switch it on;
      // CRM is outside the plan, so it is not offered at all.
      expect(apps.off.map((a) => a.key), ['production', 'fleet', 'hr']);
      expect(apps.menuOf('inventory').map((i) => i.href), ['/erp', '/erp/stock', '/erp/count', '/erp/documents']);
    });

    test('the count tab needs inventory.adjust, the app needs inventory.view', () async {
      final mock = MockApi(instant: true);
      mock.erp.permissionsFor['joseph@watercom.test'] = ['inventory.view'];
      final data = await mockSignIn(mock, 'joseph@watercom.test');
      final config = ErpConfig.fromJson(
        ((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>,
      );
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
      expect(apps.open.map((a) => a.key), ['vouchflow', 'inventory']);
      expect(apps.menuOf('inventory').map((i) => i.href), ['/erp', '/erp/stock', '/erp/documents']);
      expect(apps.off, isEmpty);
    });

    test('a company that has not set up its ERP runs VouchFlow alone', () async {
      final mock = MockApi(instant: true)..erp.isSetUp = false;
      mock.erp.permissionsFor['joseph@watercom.test'] = ['inventory.view'];
      final data = await mockSignIn(mock, 'joseph@watercom.test');
      final config = ErpConfig.fromJson(
        ((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>,
      );
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
      expect(apps.multi, isFalse);
    });
  });

  for (final entry in _modes.entries) {
    group('in ${entry.key}', () {
      final mode = entry.value;

      testWidgets('the launcher shows the apps, and those to switch on', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_shell(mode));
        await _settle(tester);

        expect(find.byType(LauncherPage), findsOneWidget);
        expect(find.text('VouchFlow'), findsWidgets);
        expect(find.text('Inventory'), findsOneWidget);
        expect(find.text('Sales'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        final launcher = find.descendant(of: find.byType(LauncherPage), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('Production'), 200, scrollable: launcher);
        // Clear of the floating tab bar, not just at the viewport's edge.
        await tester.drag(launcher, const Offset(0, -160));
        await _settle(tester, 4);
        expect(find.text('Available for your company'), findsOneWidget);
        expect(find.text('Production'), findsOneWidget);
        expect(find.text('CRM'), findsNothing);
        // The Apps tab leads the bar.
        expect(find.text('Apps'), findsWidgets);

        // A switched-off app explains where it is switched on.
        await tester.tap(find.text('Production'));
        await _settle(tester, 4);
        expect(find.text('Production is not switched on yet'), findsOneWidget);
        await tester.tap(find.text('Got it'));
        await _settle(tester, 4);

        // Opening an app puts its tabs in the bar.
        await tester.scrollUntilVisible(find.text('Inventory'), -200, scrollable: launcher);
        await tester.tap(find.text('Inventory'));
        await _settle(tester);
        expect(find.byType(LauncherPage), findsNothing);
        expect(find.text('Stock'), findsWidgets);
        expect(find.text('Count'), findsOneWidget);
        expect(find.text('Documents'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the launcher filters apps as you type', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_shell(mode));
        await _settle(tester);

        await tester.enterText(find.byType(TextField).first, 'stock');
        await _settle(tester, 2);
        expect(find.text('Inventory'), findsOneWidget);
        expect(find.text('Sales'), findsNothing);
      });

      testWidgets('someone with one app goes straight into it', (tester) async {
        await _phone(tester);
        // A requester: VouchFlow only, no ERP permissions.
        await _signIn(tester, 'frank@watercom.test');
        await tester.pumpWidget(_shell(mode));
        await _settle(tester);

        expect(find.byType(LauncherPage), findsNothing);
        expect(find.byType(DashboardTab), findsOneWidget);
        expect(find.text('Apps'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the inventory overview shows its figures and documents', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: InventoryOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Stock value'), findsOneWidget);
        expect(find.text('Low stock'), findsOneWidget);
        expect(find.text('Drafts to post'), findsOneWidget);
        expect(find.text('Active products'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Recent stock documents'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Recent stock documents'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a stock count: pick the warehouse, add a line, save the draft', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: StockCountPage()), mode));
        await _settle(tester);

        expect(find.text('Where are you counting?'), findsOneWidget);
        await tester.tap(find.text('Factory store Mbezi'));
        await _settle(tester, 2);
        expect(find.text('Nothing counted yet'), findsOneWidget);

        // Find the product on the shelf.
        await tester.tap(find.text('Find the next product'));
        await _settle(tester, 4);
        await tester.enterText(find.byType(TextField).last, 'cap');
        await _settle(tester, 2);
        await tester.tap(find.text('Bottle cap 28mm'));
        await _settle(tester, 4);
        expect(find.text('1 product counted'), findsOneWidget);

        // Key in the batch and what was counted, then one more with +.
        await tester.enterText(find.byType(TextField).at(0), 'CAP-2410');
        await tester.enterText(find.byType(TextField).at(1), '106900');
        await tester.tap(find.byTooltip('+1'));
        await _settle(tester, 2);

        await tester.tap(find.text('Save draft'));
        await _settle(tester, 6);

        final count = mock.erp.documents.lastWhere((d) => d['type'] == 'count');
        expect(count['status'], 'draft');
        expect(count['warehouse_id'], 1);
        final line = (count['lines'] as List).single as Map;
        expect(line['product_id'], 2);
        expect(double.parse('${line['quantity']}'), 106901);
        expect(line['batch_number'], 'CAP-2410');

        // The saved draft opens, ready to post.
        expect(find.byType(DocumentPage), findsOneWidget);
        expect(find.text('Post to ledger'), findsOneWidget);
        // Let the confirmation toast run out and slide away.
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(seconds: 2));
        await _settle(tester, 10);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
