// The voucher register and the create/edit voucher screens, pumped at phone
// widths against the offline mock to catch overflows, plus the pure rules the
// create flow mirrors from the web (amount in words, the approval route).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/vouchers_models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/data/services/voucher_repository.dart';
import 'package:vouchflow/app/modules/vouchers/create_voucher_page.dart';
import 'package:vouchflow/app/modules/vouchers/edit_voucher_page.dart';
import 'package:vouchflow/app/modules/vouchers/voucher_list_tab.dart';

import 'support/mock_sign_in.dart';

Future<MockApi> _signIn(String email) async {
  SharedPreferences.setMockInitialValues({});
  final mock = MockApi();
  final api = await ApiService(mock: mock).init();
  Get.put(api);
  final session = SessionService(api);
  Get.put(session);
  Get.put(VoucherRepository(api));
  await session.startSessionFrom(await mockSignIn(mock, email));
  return mock;
}

Widget _app(Widget home, {ThemeMode mode = ThemeMode.dark}) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  home: home,
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets the mock's latency and the debounce timers run out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  tearDown(Get.reset);

  group('rules mirrored from the web', () {
    test('amount in words matches the server', () {
      expect(amountInWords(450000, 'TZS'), 'Four hundred Fifty thousand shillings only');
      expect(amountInWords(1250.5, 'USD'), 'One thousand Two hundred Fifty dollars and Fifty cents only');
      expect(amountInWords(0, 'TZS'), 'Zero shillings only');
      expect(parseAmount('TZS 1,200.50'), 1200.5);
    });

    test('the route follows the type-bound workflow and the amount', () {
      RouteWorkflow wf(int id, int? type, {bool def = false, List<Map<String, dynamic>> steps = const []}) =>
          RouteWorkflow.fromJson({
            'id': id,
            'voucher_type_id': type,
            'is_default': def,
            'is_active': true,
            'steps': steps,
          });
      final general = wf(
        1,
        null,
        def: true,
        steps: [
          {'position': 1, 'role': 'employee', 'name': 'Request', 'role_label': 'Employee'},
          {'position': 2, 'role': 'hod', 'name': 'HOD signature', 'role_label': 'HOD'},
          {'position': 3, 'role': 'ceo', 'name': 'CEO approval', 'role_label': 'CEO', 'min_amount': 1000000},
          {'position': 4, 'role': 'cashier', 'name': 'Payment', 'role_label': 'Cashier', 'can_pay': true},
        ],
      );
      final bound = wf(
        2,
        7,
        steps: [
          {'position': 1, 'role': 'employee', 'name': 'Request'},
          {'position': 2, 'role': 'finance', 'name': 'Finance', 'role_label': 'Finance'},
        ],
      );
      expect(resolveWorkflow([general, bound], 7)?.id, 2);
      expect(resolveWorkflow([general, bound], 3)?.id, 1);
      expect(routeFor(general, 500000), ['HOD', 'Cashier']);
      expect(routeFor(general, 2000000), ['HOD', 'CEO', 'Cashier']);
    });
  });

  testWidgets('the register fits a 320px phone', (tester) async {
    await tester.runAsync(() => _signIn('admin@watercom.test'));
    await _size(tester, 320, 700);
    final c = Get.put(VoucherListController(), tag: 'register');
    await tester.pumpWidget(_app(Scaffold(body: VoucherListTab(controller: c))));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Voucher register'), findsOneWidget);
    expect(find.text('Create voucher'), findsWidgets);

    // Status pills and the filters sheet.
    await tester.tap(find.text('Drafts'));
    await _settle(tester);
    await tester.tap(find.text('Filters'));
    await _settle(tester);
    expect(find.text('Voucher format'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an employee sees "My vouchers" in light mode', (tester) async {
    await tester.runAsync(() => _signIn('frank@watercom.test'));
    await _size(tester, 360, 740);
    final c = Get.put(VoucherListController(), tag: 'register');
    await tester.pumpWidget(
      _app(
        Scaffold(body: VoucherListTab(controller: c)),
        mode: ThemeMode.light,
      ),
    );
    await _settle(tester);
    expect(find.text('My vouchers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every create step fits 320px and validation holds the way', (tester) async {
    await tester.runAsync(() => _signIn('frank@watercom.test'));
    await _size(tester, 320, 640);
    Get.put(CreateVoucherController());
    await tester.pumpWidget(_app(const CreateVoucherPage()));
    await _settle(tester);
    expect(find.text('What kind of voucher?'), findsOneWidget);
    expect(find.text('Bank Voucher'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Details refuses to pass without a payee and purpose.
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Who is being paid, and what for.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('This is required.'), findsNWidgets(2));

    final c = Get.find<CreateVoucherController>();
    c.payee.text = 'Puma Energy Tanzania Limited, Kurasini Depot';
    c.purpose.text = 'Vehicle fuel expenses for the September field programme';
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('How much, and the account it goes into.'), findsOneWidget);
    c.amount.text = '450000';
    await _settle(tester);
    expect(find.text('Four hundred Fifty thousand shillings only'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Browse files'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Review voucher'), findsOneWidget);
    expect(find.text('Submit voucher'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Cash asks for the float instead of a bank account.
    c.chooseKind('cash');
    c.go(2);
    await _settle(tester);
    expect(find.text('Pay from'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the edit form loads a draft at 360px', (tester) async {
    final mock = (await tester.runAsync(() => _signIn('frank@watercom.test')))!;
    final created = (await tester.runAsync(
      () => mock.handle(
        'POST',
        '/vouchers',
        body: {
          'kind': 'bank',
          'voucher_type_id': 101,
          'payee': 'Kariakoo Stationers',
          'purpose': 'Branch stationery restock',
          'amount': 412500,
          'payment_method': 'Bank Transfer',
        },
      ),
    ))!;
    final id = (created['data'] as Map)['id'] as int;
    await _size(tester, 360, 740);
    await tester.pumpWidget(_app(EditVoucherPage(voucherId: id)));
    await _settle(tester);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Branch stationery restock'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
