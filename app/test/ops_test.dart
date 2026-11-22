// The Production, CRM and Documents apps against the in-app mock, in light
// and dark at a 360px phone width: the homes render, an order is released
// and a batch passes its quality check, a deal moves stage, an activity is
// logged, and the library opens a folder and a document.

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
import 'package:vouchflow/app/modules/crm/crm_forms.dart';
import 'package:vouchflow/app/modules/crm/lead_page.dart';
import 'package:vouchflow/app/modules/crm/opportunity_page.dart';
import 'package:vouchflow/app/modules/crm/overview_page.dart';
import 'package:vouchflow/app/modules/crm/pipeline_page.dart';
import 'package:vouchflow/app/modules/files/expiring_page.dart';
import 'package:vouchflow/app/modules/files/file_page.dart';
import 'package:vouchflow/app/modules/files/library_page.dart';
import 'package:vouchflow/app/modules/production/boms_page.dart';
import 'package:vouchflow/app/modules/production/order_page.dart';
import 'package:vouchflow/app/modules/production/overview_page.dart';
import 'package:vouchflow/app/modules/production/qc_page.dart';
import 'package:vouchflow/app/modules/shell/areas.dart';
import 'package:vouchflow/app/routes/routes.dart';

import 'support/mock_sign_in.dart';

const _ops = ['production', 'crm', 'documents'];

Future<MockApi> _signIn(String email, {bool modulesOn = true}) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi(instant: true);
  if (modulesOn) mock.erp.modules.addAll(_ops);
  final api = await ApiService(mock: mock).init();
  Get.put(api);
  Get.put(VoucherRepository(api));
  final data = await mockSignIn(mock, email);
  final session = SessionService(api);
  Get.put(session);
  session.user.value = AppUser.fromJson(data['user'] as Map<String, dynamic>);
  session.company.value = Company.fromJson(data['company'] as Map<String, dynamic>);
  await Get.put(ErpService(api, session)).ensure();
  return mock;
}

Widget _app(Widget home, ThemeMode mode) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  getPages: [
    GetPage(name: Routes.prdOrder, page: () => const ProductionOrderPage()),
    GetPage(name: Routes.prdBom, page: () => const BomPage()),
    GetPage(name: Routes.crmLead, page: () => const CrmLeadPage()),
    GetPage(name: Routes.crmOpportunity, page: () => const CrmOpportunityPage()),
    GetPage(name: Routes.crmActivityNew, page: () => const CrmActivityFormPage()),
    GetPage(name: Routes.filesDocument, page: () => const FilesDocumentPage()),
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

/// Lets a toast run out so no timer is left pending.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester, 6);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await _settle(tester, 2);
}

const _modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

void main() {
  tearDown(Get.reset);

  group('the apps a person is offered', () {
    test('with the modules on, an administrator gets all three on the phone', () async {
      final mock = MockApi(instant: true)..erp.modules.addAll(_ops);
      final data = await mockSignIn(mock, 'admin@watercom.test');
      final config = ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
      expect(apps.open.map((a) => a.key), containsAll(['production', 'crm', 'files']));
      expect(apps.menuOf('production').map((i) => i.href),
          ['/erp/production', '/erp/production/orders', '/erp/production/qc', '/erp/production/boms']);
      expect(apps.menuOf('crm').map((i) => i.href), ['/erp/crm', '/erp/crm/pipeline', '/erp/crm/leads', '/erp/crm/activities']);
      expect(apps.menuOf('files').map((i) => i.href), ['/erp/files', '/erp/files/expiring']);
    });

    test('documents.view alone opens the library, nothing else', () async {
      final mock = MockApi(instant: true)..erp.modules.addAll(_ops);
      mock.erp.permissionsFor['joseph@watercom.test'] = ['documents.view'];
      final data = await mockSignIn(mock, 'joseph@watercom.test');
      final config = ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);
      final apps = VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
      expect(apps.open.map((a) => a.key), ['vouchflow', 'files']);
    });
  });

  for (final entry in _modes.entries) {
    group('in ${entry.key}', () {
      final mode = entry.value;

      testWidgets('the production home shows the floor', (tester) async {
        await _phone(tester);
        await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: ProductionOverviewPage()), mode));
        await _settle(tester);
        expect(find.text('Released today'), findsOneWidget);
        expect(find.text('Awaiting QC'), findsOneWidget);
        expect(find.text('Open orders'), findsOneWidget);
        await _scrollTo(tester, find.text('On the floor and coming up'));
        expect(find.text('Watercom 500ml × 24'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a planned order is released from its page', (tester) async {
        await _phone(tester);
        final mock = await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const ProductionOrderPage(orderId: 10), mode));
        await _settle(tester);
        expect(find.text('PRD-2026-000010'), findsWidgets);
        await tester.tap(find.text('Release'));
        await _settle(tester, 4);
        expect(find.text('Release PRD-2026-000010 to production?'), findsOneWidget);
        await tester.tap(find.text('Release').last);
        await _settle(tester, 6);
        expect(mock.erp.ops.orders.firstWhere((o) => o['id'] == 10)['status'], 'released');
        expect(find.text('Record output'), findsOneWidget);
        await _drain(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a waiting batch passes its quality check', (tester) async {
        await _phone(tester);
        final mock = await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: QcQueuePage()), mode));
        await _settle(tester);
        expect(find.text('Inspect'), findsOneWidget);
        await tester.tap(find.text('Inspect'));
        await _settle(tester, 6);
        expect(find.text('Quality check'), findsOneWidget);
        // A failed parameter allows only Reject.
        await tester.tap(find.text('Fail').first);
        await _settle(tester, 2);
        expect(find.text('A failed parameter means the batch can only be rejected.'), findsOneWidget);
        await tester.tap(find.text('Pass').first);
        await _settle(tester, 2);
        await tester.scrollUntilVisible(find.text('Release'), 200, scrollable: find.byType(Scrollable).last);
        await tester.tap(find.text('Release'));
        await _settle(tester, 6);
        expect(mock.erp.ops.receipts.firstWhere((r) => r['id'] == 9)['status'], 'released');
        await _drain(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a recipe reads with its components', (tester) async {
        await _phone(tester);
        await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const BomPage(bomId: 2), mode));
        await _settle(tester);
        expect(find.text('PET preform 28g'), findsOneWidget);
        expect(find.text('Components'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the CRM home lists what is due and overdue', (tester) async {
        await _phone(tester);
        await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: CrmOverviewPage()), mode));
        await _settle(tester);
        expect(find.text('Open pipeline'), findsOneWidget);
        await _scrollTo(tester, find.text('Site visit: Laizer Safari Camps'));
        expect(find.text('Site visit: Laizer Safari Camps'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a deal moves to the next stage from the pipeline', (tester) async {
        await _phone(tester);
        final mock = await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: CrmPipelinePage()), mode));
        await _settle(tester);
        expect(find.text('Serena Hotel: 19L dispensers'), findsOneWidget);
        await tester.tap(find.byTooltip('Move to'));
        await _settle(tester, 4);
        await tester.tap(find.text('Proposal').last);
        await _settle(tester, 2);
        await tester.tap(find.text('Move'));
        await _settle(tester, 6);
        expect(mock.erp.ops.deals.firstWhere((d) => d['id'] == 7)['stage'], 'proposal');
        await _drain(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a call is logged on a lead', (tester) async {
        await _phone(tester);
        final mock = await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const CrmLeadPage(leadId: 7), mode));
        await _settle(tester);
        expect(find.text('Neema Laizer'), findsWidgets);
        expect(find.text('Call'), findsOneWidget);
        await tester.tap(find.text('Log activity'));
        await _settle(tester, 6);
        expect(find.byType(CrmActivityFormPage), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Agreed a trial delivery');
        await _settle(tester, 2);
        await tester.tap(find.text('Save'));
        await _settle(tester, 8);
        final logged = mock.erp.ops.activities.last;
        expect(logged['subject'], 'Agreed a trial delivery');
        expect(logged['lead_id'], 7);
        expect(logged['completed_at'], isNotNull);
        await _drain(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the library opens a folder and a document', (tester) async {
        await _phone(tester);
        await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: FilesLibraryPage()), mode));
        await _settle(tester);
        expect(find.text('Licences & permits'), findsOneWidget);
        await tester.tap(find.text('Licences & permits'));
        await _settle(tester);
        expect(find.text('Fire safety certificate'), findsOneWidget);
        expect(find.textContaining('Expired 5 days ago'), findsOneWidget);
        await tester.tap(find.text('Fire safety certificate'));
        await _settle(tester);
        expect(find.byType(FilesDocumentPage), findsOneWidget);
        expect(find.text('Open'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Version 1'), 200, scrollable: find.byType(Scrollable).last);
        expect(find.text('Version 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('expiring documents, expired first', (tester) async {
        await _phone(tester);
        await _signIn('admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: FilesExpiringPage()), mode));
        await _settle(tester);
        expect(find.text('Fire safety certificate'), findsOneWidget);
        expect(find.text('TBS product certification'), findsOneWidget);
        expect(find.textContaining('24 days left'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
