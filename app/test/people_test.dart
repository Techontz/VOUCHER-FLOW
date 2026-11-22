// The Fleet and HR apps against the in-app mock: which tabs a driver, an
// employee and HR staff get, the main pages in light and dark at a 360px
// phone width, and the two flows phones matter most for: a driver logging
// fuel and an employee applying for leave.

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
import 'package:vouchflow/app/modules/fleet/fuel_form_page.dart';
import 'package:vouchflow/app/modules/fleet/my_trips_page.dart';
import 'package:vouchflow/app/modules/fleet/overview_page.dart';
import 'package:vouchflow/app/modules/fleet/trip_page.dart';
import 'package:vouchflow/app/modules/fleet/vehicle_page.dart';
import 'package:vouchflow/app/modules/hr/leave_form_page.dart';
import 'package:vouchflow/app/modules/hr/me_page.dart';
import 'package:vouchflow/app/modules/hr/my_leave_page.dart';
import 'package:vouchflow/app/modules/hr/overview_page.dart';
import 'package:vouchflow/app/modules/hr/payslip_page.dart';
import 'package:vouchflow/app/modules/shell/areas.dart';
import 'package:vouchflow/app/routes/routes.dart';

import 'support/mock_sign_in.dart';

const _driver = 'baraka@watercom.test';
const _employee = 'frank@watercom.test';

void _people(MockApi mock) {
  mock.erp.modules = [...mock.erp.modules, 'fleet', 'hr'];
  mock.erp.permissionsFor[_driver] = ['fleet.own', 'hr.self'];
  mock.erp.permissionsFor[_employee] = ['hr.self'];
}

Future<MockApi> _signIn(WidgetTester tester, String email) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi(instant: true);
  _people(mock);
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
    GetPage(name: Routes.erpFleetFuelNew, page: () => const FuelFormPage()),
    GetPage(name: Routes.erpFleetTrip, page: () => const TripPage()),
    GetPage(name: Routes.erpFleetVehicle, page: () => const VehiclePage()),
    GetPage(name: Routes.erpHrLeaveNew, page: () => const LeaveFormPage()),
    GetPage(name: Routes.erpHrPayslip, page: () => const PayslipPage()),
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
  await _settle(tester, 10);
}

Future<VfApps> _apps(String email) async {
  final mock = MockApi(instant: true);
  _people(mock);
  final data = await mockSignIn(mock, email);
  final config = ErpConfig.fromJson(((await mock.handle('GET', '/erp/config')) as Map)['data'] as Map<String, dynamic>);
  return VfApps.of(AppUser.fromJson(data['user'] as Map<String, dynamic>), config);
}

const _modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

void main() {
  tearDown(Get.reset);

  group('who gets which tabs', () {
    test('a driver gets their own trips, and their own HR', () async {
      final apps = await _apps(_driver);
      expect(apps.menuOf('fleet').map((i) => i.href), ['/erp/fleet/my']);
      expect(apps.menuOf('hr').map((i) => i.href), ['/erp/hr/me', '/erp/hr/me/leave', '/erp/hr/me/payslips', '/erp/hr/me/attendance']);
    });

    test('an employee gets self-service only', () async {
      final apps = await _apps(_employee);
      expect(apps.open.map((a) => a.key), contains('hr'));
      expect(apps.menuOf('fleet'), isEmpty);
      expect(apps.menuOf('hr').first.href, '/erp/hr/me');
    });

    test('the administrator gets the staff side first', () async {
      final apps = await _apps('admin@watercom.test');
      expect(apps.menuOf('fleet').first.href, '/erp/fleet');
      expect(apps.menuOf('hr').take(4).map((i) => i.href), ['/erp/hr', '/erp/hr/employees', '/erp/hr/leave', '/erp/hr/attendance']);
    });
  });

  for (final entry in _modes.entries) {
    group('in ${entry.key}', () {
      final mode = entry.value;

      testWidgets('a driver sees their vehicle and trip first', (tester) async {
        await _phone(tester);
        await _signIn(tester, _driver);
        await tester.pumpWidget(_app(const Scaffold(body: MyTripsPage()), mode));
        await _settle(tester);

        expect(find.text('My vehicle'), findsOneWidget);
        expect(find.text('T 101 DXA'), findsOneWidget);
        expect(find.text('Current trip'), findsOneWidget);
        expect(find.text('Arusha'), findsOneWidget);
        expect(find.text('Log fuel'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a driver logs fuel on the trip they are on', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, _driver);
        await tester.pumpWidget(_app(const Scaffold(body: MyTripsPage()), mode));
        await _settle(tester);

        await tester.tap(find.text('Log fuel'));
        await _settle(tester);
        expect(find.byType(FuelFormPage), findsOneWidget);
        // The trip on the road is chosen already, paid from cash.
        expect(find.textContaining('Dar es Salaam to Arusha'), findsOneWidget);

        await tester.enterText(find.byKey(const ValueKey('fuel-litres')).last, '120');
        await tester.enterText(find.byKey(const ValueKey('fuel-price')).last, '3200');
        await _settle(tester, 2);
        expect(find.text('TZS 384,000'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('fuel-odometer')).last, '152900');
        await tester.enterText(find.byKey(const ValueKey('fuel-station')).last, 'Puma Morogoro');

        await tester.tap(find.text('Save fuel'));
        await _settle(tester, 6);

        final entry = mock.erp.people.fuel.first;
        expect(entry['trip_id'], 31);
        expect(double.parse('${entry['litres']}'), 120);
        expect(entry['station'], 'Puma Morogoro');
        expect(entry['account_id'], 1);
        // A driver's fuel waits for the fleet manager.
        expect(entry['status'], 'pending');
        expect(find.byType(FuelFormPage), findsNothing);
        await _toastAway(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the fleet overview shows its figures', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: FleetOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('On the road'), findsWidgets);
        expect(find.text('Waiting for approval'), findsOneWidget);
        expect(find.text('Maintenance due'), findsWidgets);
        await tester.scrollUntilVisible(find.text('Papers expiring within 30 days'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('T 214 DYB'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the HR overview shows its figures', (tester) async {
        await _phone(tester);
        await _signIn(tester, 'admin@watercom.test');
        await tester.pumpWidget(_app(const Scaffold(body: HrOverviewPage()), mode));
        await _settle(tester);

        expect(find.text('Headcount'), findsOneWidget);
        expect(find.text('Leave to decide'), findsOneWidget);
        expect(find.text('In today'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an employee sees their leave, pay and details', (tester) async {
        await _phone(tester);
        await _signIn(tester, _employee);
        await tester.pumpWidget(_app(const Scaffold(body: MePage()), mode));
        await _settle(tester);

        expect(find.text('Hello, Frank'), findsOneWidget);
        expect(find.text('Annual leave'), findsOneWidget);
        expect(find.text('Last net pay'), findsOneWidget);
        expect(find.text('Apply for leave'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Contract and pay'), 300, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an employee opens a payslip', (tester) async {
        await _phone(tester);
        await _signIn(tester, _employee);
        await tester.pumpWidget(_app(PayslipPage(slipId: 108, mine: true), mode));
        await _settle(tester);

        expect(find.text('Net pay'), findsWidgets);
        expect(find.text('Earnings'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Paid by the employer'), 300, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an employee applies for leave', (tester) async {
        await _phone(tester);
        final mock = await _signIn(tester, _employee);
        final before = mock.erp.people.leave.length;
        await tester.pumpWidget(_app(const Scaffold(body: MyLeavePage()), mode));
        await _settle(tester);

        expect(find.text('My leave'), findsOneWidget);
        await tester.tap(find.text('Apply for leave'));
        await _settle(tester);
        expect(find.byType(LeaveFormPage), findsOneWidget);
        // Annual leave is chosen to start with; the first day picks the last.
        await tester.scrollUntilVisible(find.byKey(const ValueKey('start-null')), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const ValueKey('start-null')));
        await _settle(tester, 4);
        await tester.tap(find.text('OK'));
        await _settle(tester, 4);
        expect(find.textContaining('Calendar days: 1.'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'Family errand');

        await tester.tap(find.text('Send request'));
        await _settle(tester, 6);

        expect(mock.erp.people.leave.length, before + 1);
        final request = mock.erp.people.leave.first;
        expect(request['status'], 'pending');
        expect(request['leave_type_id'], 1);
        expect(request['reason'], 'Family errand');
        expect(find.byType(LeaveFormPage), findsNothing);
        await _toastAway(tester);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
