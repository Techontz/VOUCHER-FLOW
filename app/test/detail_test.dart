// The voucher page, its workflow dialogs, bulk approval and the payment queue,
// pumped at small phone widths against the offline mock to catch overflows —
// plus the pure rules mirrored from the web.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/detail_models.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/data/services/voucher_repository.dart';
import 'package:vouchflow/app/modules/approvals/bulk_approve_page.dart';
import 'package:vouchflow/app/modules/payments/payment_queue_page.dart';
import 'package:vouchflow/app/modules/vouchers/detail_bits.dart';
import 'package:vouchflow/app/modules/vouchers/voucher_detail_page.dart';
import 'package:vouchflow/app/routes/routes.dart';
import 'package:vouchflow/app/widgets/vf/vf.dart';

import 'support/mock_sign_in.dart';

late MockApi _mock;
late SessionService _session;

Future<void> _boot() async {
  SharedPreferences.setMockInitialValues({});
  _mock = MockApi();
  final api = await ApiService(mock: _mock).init();
  Get.put(api);
  _session = SessionService(api);
  Get.put(_session);
  Get.put(VoucherRepository(api));
}

Future<void> _as(String email) async => _session.startSessionFrom(await mockSignIn(_mock, email));

Future<Map<String, dynamic>> _act(int id, String action, [Map<String, dynamic> body = const {}]) async =>
    (await _mock.handle('POST', '/vouchers/$id/$action', body: body))['data'] as Map<String, dynamic>;

/// A cash voucher raised by Frank and signed by Joseph, awaiting the CEO.
Future<int> _signedVoucher() async {
  await mockSignIn(_mock, 'frank@watercom.test');
  final created =
      (await _mock.handle(
            'POST',
            '/vouchers',
            body: {
              'kind': 'cash',
              'voucher_type_id': 102,
              'department_id': 2,
              'payee': 'Kariakoo Stationers and General Supplies Limited',
              'purpose': 'Branch stationery restock for the whole of the coming quarter',
              'amount': 412500,
              'payment_method': 'Cash',
            },
          ))['data']
          as Map<String, dynamic>;
  final id = created['id'] as int;
  await _act(id, 'submit');
  await mockSignIn(_mock, 'joseph@watercom.test');
  await _act(id, 'sign', {'use_saved_signature': true});
  await _act(id, 'submit-signed');
  return id;
}

Widget _app({Widget? home, ThemeMode mode = ThemeMode.dark}) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  getPages: [GetPage(name: Routes.voucher, page: () => const VoucherDetailPage())],
  home: home ?? const Scaffold(body: SizedBox()),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await _settle(tester);
}

/// Presses a dialog button by its label (a sheet's buttons may sit under
/// the test view's edge).
Future<void> _press(WidgetTester tester, String label) async {
  final button = find.byWidgetPredicate((w) => w is VouchFlowButton && w.label == label).last;
  expect(button, findsOneWidget);
  tester.widget<VouchFlowButton>(button).onPressed!();
  await _settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await _settle(tester);
}

void main() {
  tearDown(Get.reset);

  group('rules mirrored from the web', () {
    test('status tones follow the web', () {
      expect(statusTone('paid'), VfTone.ok);
      expect(statusTone('awaiting_payment'), VfTone.ok);
      expect(statusTone('partially_paid'), VfTone.warn);
      expect(statusTone('changes_requested'), VfTone.warn);
      expect(statusTone('rejected'), VfTone.bad);
      expect(statusTone('draft'), VfTone.neutral);
      expect(statusTone('awaiting_signature'), VfTone.info);
    });

    test('progress follows the workflow and the amount', () {
      final workflow = WorkflowInfo.fromJson({
        'id': 1,
        'steps': [
          {'position': 1, 'name': 'Request', 'role': 'employee'},
          {'position': 2, 'name': 'HOD signature', 'role': 'hod', 'role_label': 'HOD', 'can_sign': true},
          {'position': 3, 'name': 'Approval', 'role': 'ceo', 'role_label': 'CEO', 'can_approve': true},
          {
            'position': 4,
            'name': 'Board',
            'role': 'director',
            'role_label': 'Director',
            'can_approve': true,
            'min_amount': 10000000,
          },
          {'position': 5, 'name': 'Payment', 'role': 'cashier', 'role_label': 'Cashier', 'can_pay': true},
        ],
      });
      Voucher v(String status, int? at, double amount) => Voucher.fromJson({
        'id': 9,
        'status': status,
        'amount': amount,
        'workflow_id': 1,
        'current_step_position': at,
      });

      final inReview = deriveProgress(v('in_review', 3, 500000), [workflow]);
      expect(
        inReview.map((s) => s.label),
        ['prepared', 'HOD', 'CEO', 'Cashier'].map((l) => l == 'prepared' ? inReview.first.label : l),
      );
      expect(inReview.map((s) => s.state), [
        RouteStepState.done,
        RouteStepState.done,
        RouteStepState.current,
        RouteStepState.pending,
      ]);

      final big = deriveProgress(v('approved', 5, 20000000), [workflow]);
      expect(big.length, 5);
      expect(big.last.state, RouteStepState.current);

      final rejected = deriveProgress(v('rejected', 2, 500000), [workflow]);
      expect(rejected[1].state, RouteStepState.rejected);
    });

    test('bulk approval takes approving steps and sign-and-approve steps only', () {
      Voucher v(Map<String, dynamic> actions, bool stepApproves) => Voucher.fromJson({
        'id': 1,
        'actions': actions,
        'current_step': {
          'capabilities': {'approve': stepApproves},
        },
      });
      expect(bulkEligible(v({'approve': true}, true)), isTrue);
      expect(bulkEligible(v({'sign': true}, true)), isTrue);
      expect(bulkEligible(v({'sign': true}, false)), isFalse);
    });
  });

  group('screens at phone width', () {
    for (final width in [320.0, 360.0]) {
      testWidgets('the voucher page and its approve dialog fit at ${width.toInt()}px', (tester) async {
        await _size(tester, width, 720);
        final id = (await tester.runAsync(() async {
          await _boot();
          final id = await _signedVoucher();
          await _as('emmanuel@watercom.test');
          return id;
        }))!;

        await tester.pumpWidget(_app());
        Get.toNamed(Routes.voucher, arguments: id);
        await _settle(tester);

        expect(find.text('Approve voucher'), findsWidgets);
        expect(find.text('Approval progress'), findsOneWidget);

        await _tapText(tester, 'Approve voucher');
        await _settle(tester);
        expect(find.text('Approve this voucher?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('Approve this voucher?'))).pop();
        await _settle(tester);

        await _tapText(tester, 'Reject');
        await _settle(tester);
        expect(find.text('Reject this voucher?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('recording a part payment fits at ${width.toInt()}px, light', (tester) async {
        await _size(tester, width, 720);
        final id = (await tester.runAsync(() async {
          await _boot();
          final id = await _signedVoucher();
          await mockSignIn(_mock, 'emmanuel@watercom.test');
          await _act(id, 'approve');
          await _as('mwajuma@watercom.test');
          return id;
        }))!;

        await tester.pumpWidget(_app(mode: ThemeMode.light));
        Get.toNamed(Routes.voucher, arguments: id);
        await _settle(tester);

        await _tapText(tester, 'Release funds');
        await _settle(tester);
        expect(find.textContaining('Amount to pay now', findRichText: true), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '100000');
        await _settle(tester);
        expect(find.textContaining('Balance after this payment'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _press(tester, 'Record payment');
        expect(find.text('Part payment recorded'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _press(tester, 'Done');
        await _scrollTo(tester, find.text('Awaiting signed copy'));
        expect(find.text('Print acknowledgement'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the sign dialog fits at 320px', (tester) async {
      await _size(tester, 320, 720);
      final id = (await tester.runAsync(() async {
        await _boot();
        await mockSignIn(_mock, 'frank@watercom.test');
        final created =
            (await _mock.handle(
                  'POST',
                  '/vouchers',
                  body: {
                    'kind': 'bank',
                    'voucher_type_id': 101,
                    'department_id': 2,
                    'payee': 'Highland Freight',
                    'purpose': 'Freight',
                    'amount': 900000,
                    'payment_method': 'Bank Transfer',
                  },
                ))['data']
                as Map<String, dynamic>;
        final newId = created['id'] as int;
        await _act(newId, 'submit');
        await _as('joseph@watercom.test');
        return newId;
      }))!;

      await tester.pumpWidget(_app());
      Get.toNamed(Routes.voucher, arguments: id);
      await _settle(tester);

      await _tapText(tester, 'Sign voucher');
      await _settle(tester);
      expect(find.text('Confirm signature'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bulk approval fits at 320px', (tester) async {
      await _size(tester, 320, 720);
      await tester.runAsync(() async {
        await _boot();
        await _signedVoucher();
        await _as('emmanuel@watercom.test');
      });
      await tester.pumpWidget(_app(home: const Scaffold(body: BulkApprovePage())));
      await _settle(tester);
      expect(find.text('Approvals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the payment queue never crashes in the offline mock', (tester) async {
      await _size(tester, 320, 720);
      await tester.runAsync(() async {
        await _boot();
        await _as('mwajuma@watercom.test');
      });
      await tester.pumpWidget(_app(home: const Scaffold(body: PaymentQueuePage())));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
