// A UI walk through the app: each persona signs in, lands on the right home
// screen, and sees exactly the actions their step permits.
//
// The workflow rules themselves are covered by test/workflow_test.dart; this
// checks that the screens above them show the right thing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vouchflow/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Settles the tree, then keeps pumping for a moment so the mock's latency
  /// has landed. A live binding never truly settles while anything animates —
  /// a blinking text cursor is enough — so the settle is given a bound and a
  /// timeout is not a failure.
  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 80),
        EnginePhase.sendSemanticsUpdate,
        Duration(milliseconds: ms + 4000),
      );
    } on FlutterError {
      // Something animates indefinitely; fall through to plain pumping.
    }
    final deadline = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    await settle(tester);
    if (find.byType(FloatingActionButton).evaluate().isNotEmpty ||
        find.byType(NavigationBar).evaluate().isNotEmpty) {
      // Already inside the app — drop the session and come back to login.
      Get.offAllNamed('/login');
      await settle(tester);
    }
    await tester.enterText(find.byType(TextField).first, email);
    await tester.enterText(find.byType(TextField).at(1), 'Password123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in').first);
    await settle(tester, 1600);
  }

  testWidgets(
    'each persona lands on the right home screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await app.main();
      await settle(tester, 2000);

      // ── employee ──
      await signIn(tester, 'john@acme.test');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.textContaining('You see only your own vouchers'),
        findsWidgets,
        reason: 'the employee dashboard states its own scope',
      );
      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'an employee raises vouchers',
      );
      expect(
        find.byIcon(Icons.fact_check_outlined),
        findsNothing,
        reason: 'nothing is ever routed to an employee, so no approvals tab',
      );

      // ── head of department ──
      await signIn(tester, 'peter@acme.test');
      expect(
        find.byIcon(Icons.fact_check_outlined),
        findsWidgets,
        reason: 'an approver gets an approvals tab',
      );
      expect(
        find.textContaining('signature'),
        findsWidgets,
        reason: 'the HOD headline speaks of signing, not deciding',
      );

      // ── cashier ──
      await signIn(tester, 'fatuma@acme.test');
      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsWidgets,
        reason: 'the cashier gets a payment queue, not an approvals queue',
      );
      expect(find.textContaining('awaiting payment'), findsWidgets);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'a cashier releases money; they do not raise vouchers',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'the HOD step signs and never approves',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await app.main();
      await settle(tester, 2000);

      await signIn(tester, 'peter@acme.test');
      await tester.tap(find.byIcon(Icons.fact_check_outlined).last);
      await settle(tester, 1400);

      final queued = find.textContaining('Awaiting HOD signature');
      expect(queued, findsWidgets, reason: 'something is waiting on the HOD');

      await tester.tap(queued.first);
      await settle(tester, 1600);

      expect(find.text('Sign voucher'), findsWidgets);
      expect(
        find.text('Approve voucher'),
        findsNothing,
        reason: 'signing is not approving — the decision belongs downstream',
      );
      expect(find.textContaining('Signing does not approve'), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'the cashier records a payment against an approved voucher',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await app.main();
      await settle(tester, 2000);

      await signIn(tester, 'fatuma@acme.test');
      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined).last);
      await settle(tester, 1400);

      final due = find.textContaining('Approved — awaiting payment');
      expect(due, findsWidgets, reason: 'the queue holds approved vouchers');

      await tester.tap(due.first);
      await settle(tester, 1600);

      // Target the action itself: "Record payment" also appears in the timeline
      // as the step's permitted actions.
      final payButton = find.descendant(
        of: find.byType(FilledButton),
        matching: find.textContaining(RegExp('Release funds|Record payment')),
      );
      expect(payButton, findsOneWidget);
      await tester.tap(payButton);
      await settle(tester, 1400);

      // The label follows the format: a reference for cash, a cheque or
      // transfer number for a bank voucher.
      expect(
        find.textContaining(RegExp('Payment reference|Cheque / transfer no.')),
        findsWidgets,
      );
      await tester.enterText(find.byType(TextField).first, 'TRF-2026-9001');
      await settle(tester, 400);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid'));
      await settle(tester, 2600);

      expect(
        find.textContaining('Paid & completed'),
        findsWidgets,
        reason: 'the voucher closes once the funds are released',
      );
      expect(
        find.textContaining('TRF-2026-9001'),
        findsWidgets,
        reason: 'the reference is recorded on the voucher',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
