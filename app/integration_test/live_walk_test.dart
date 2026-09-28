// A walk through every screen against a running backend, on a real device or
// simulator: each account signs in through the login screen, opens every
// page its navigation offers, a voucher, and Create voucher, then signs out.
// Any layout error (overflow, a thrown build) fails the run.
//
// Local demo data only — the accounts and password come from the command:
//   flutter test integration_test/live_walk_test.dart -d <device> \
//     --dart-define=API_URL=http://127.0.0.1:8130/api \
//     --dart-define=WALK_ACCOUNTS=admin@watercom.test,frank@watercom.test \
//     --dart-define=WALK_PASSWORD=...
//
// Each screen prints `SHOT <name>` and holds still for a moment, so a host
// script can capture the simulator (`xcrun simctl io booted screenshot`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/data/services/voucher_repository.dart';
import 'package:vouchflow/app/modules/shell/nav.dart';
import 'package:vouchflow/app/modules/shell/shell_page.dart';
import 'package:vouchflow/app/routes/routes.dart';
import 'package:vouchflow/main.dart' as app;

const _accounts = String.fromEnvironment('WALK_ACCOUNTS');
const _password = String.fromEnvironment('WALK_PASSWORD');
const _hold = int.fromEnvironment('WALK_HOLD_MS', defaultValue: 2500);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final problems = <String>[];

  /// Pumps for [ms] of wall time — a live API answers on its own clock.
  Future<void> wait(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, _hold);
    // ignore: avoid_print
    print('SHOT $name');
    await wait(tester, 900);
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done, {int ms = 20000}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('every screen, every account, live API', (tester) async {
    expect(_accounts, isNotEmpty, reason: 'pass --dart-define=WALK_ACCOUNTS=a@x,b@y');
    expect(_password, isNotEmpty, reason: 'pass --dart-define=WALK_PASSWORD=...');

    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      problems.add(details.exceptionAsString().split('\n').first);
      // ignore: avoid_print
      print('LAYOUT-ERROR ${details.exceptionAsString().split('\n').first}');
      // ignore: avoid_print
      print(details.stack.toString().split('\n').take(12).join('\n'));
    };

    await app.main();
    await waitFor(tester, () => find.byType(EditableText).evaluate().length >= 2);

    var n = 0;
    for (final email in _accounts.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final dark = n.isEven;
      n++;
      final who = email.split('@').first;

      await waitFor(tester, () => find.byType(EditableText).evaluate().length >= 2);
      await tester.enterText(find.byType(EditableText).at(0), email);
      await tester.enterText(find.byType(EditableText).at(1), _password);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(tester, () => Get.isRegistered<ShellController>() && find.byType(NavigationBar).evaluate().isNotEmpty);
      expect(find.byType(NavigationBar), findsOneWidget, reason: '$email did not reach the app');

      final session = Get.find<SessionService>();
      final wantDark = session.themeMode.value == ThemeMode.dark;
      if (wantDark != dark) await session.toggleTheme();
      final mode = dark ? 'dark' : 'light';
      await shot(tester, '$who-home-$mode');

      final shell = Get.find<ShellController>();
      final seen = <String>{'/dashboard'};
      for (final item in navFor(session.me.role)) {
        if (item.href == '/vouchers/new' || !seen.add(item.href)) continue;
        shell.go(item.href);
        await shot(tester, '$who-${item.href.substring(1).replaceAll('/', '-')}-$mode');
      }
      for (final href in const ['/notifications', '/profile']) {
        if (!seen.add(href)) continue;
        shell.go(href);
        await shot(tester, '$who-${href.substring(1)}-$mode');
      }

      if (session.me.role != 'super_admin') {
        final list = await tester.runAsync(() => Get.find<VoucherRepository>().list(scope: 'all'));
        if (list != null && list.isNotEmpty) {
          Get.toNamed(Routes.voucher, arguments: list.first.id);
          await shot(tester, '$who-voucher-$mode');
          Get.back();
          await wait(tester, 600);
        }
      }

      if (shell.canCreate) {
        Get.toNamed(Routes.createVoucher);
        await shot(tester, '$who-create-$mode');
        Get.back();
        await wait(tester, 600);
      }

      shell.go('/dashboard');
      await tester.runAsync(session.signOut);
      Get.offAllNamed(Routes.login);
      await wait(tester, 1200);
    }

    FlutterError.onError = original;
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
