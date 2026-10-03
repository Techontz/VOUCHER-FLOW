// Screenshots of every screen against the offline fixture, for design work:
//   flutter test integration_test/mock_shots_test.dart -d <simulator> \
//     --dart-define=API_MODE=mock --dart-define=SHOT_ACCOUNTS=frank@watercom.test
// Each screen prints `SHOT <name>` and holds still so a host script can
// capture the simulator. Layout errors are printed, not fatal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/data/services/voucher_repository.dart';
import 'package:vouchflow/app/modules/shell/nav.dart';
import 'package:vouchflow/app/modules/shell/shell_page.dart';
import 'package:vouchflow/app/routes/routes.dart';
import 'package:vouchflow/main.dart' as app;

const _accounts = String.fromEnvironment(
  'SHOT_ACCOUNTS',
  defaultValue: 'frank@watercom.test',
);
const _only = String.fromEnvironment('SHOT_ONLY');
const _hold = int.fromEnvironment('SHOT_HOLD_MS', defaultValue: 1400);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  bool wanted(String name) =>
      _only.isEmpty || _only.split(',').any((s) => name.contains(s));

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, _hold);
    // ignore: avoid_print
    print('SHOT $name');
    await wait(tester, 2600);
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('screenshots', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      // ignore: avoid_print
      print('LAYOUT-ERROR ${d.exceptionAsString().split('\n').first}');
    };

    await app.main();
    await waitFor(tester, () => find.byType(EditableText).evaluate().length >= 2);
    final session = Get.find<SessionService>();
    if (wanted('login')) {
      if (session.themeMode.value != ThemeMode.dark) await session.toggleTheme();
      await shot(tester, 'login-dark');
      await session.toggleTheme();
      await shot(tester, 'login-light');
      await session.toggleTheme();
    }

    var n = 0;
    for (final email in _accounts.split(',')) {
      final dark = n.isEven;
      n++;
      final who = email.split('@').first;
      final mode = dark ? 'dark' : 'light';
      if ((session.themeMode.value == ThemeMode.dark) != dark) {
        await session.toggleTheme();
      }

      final challenge = await tester.runAsync(
        () => session.signIn(email, 'Password123!'),
      );
      if (challenge != null) {
        if (wanted('verify') && n == 1) {
          Get.toNamed(Routes.verifyLogin, arguments: challenge);
          await shot(tester, 'verify-$mode');
          Get.back();
          await wait(tester, 400);
        }
        await tester.runAsync(() async {
          if (challenge.sentTo == null) {
            await session.sendLoginCode(challenge.challenge, 'email');
          }
          await session.verifyLogin(challenge.challenge, MockApi.mockLoginCode);
        });
      }
      Get.offAllNamed(Routes.shell);
      await waitFor(tester, () => Get.isRegistered<ShellController>());

      if (wanted('home')) await shot(tester, '$who-home-$mode');
      final shell = Get.find<ShellController>();
      final seen = <String>{'/dashboard'};
      for (final item in navFor(session.me.role)) {
        if (item.href == '/vouchers/new' || !seen.add(item.href)) continue;
        final name = '$who-${item.href.substring(1).replaceAll('/', '-')}-$mode';
        if (!wanted(name)) continue;
        shell.go(item.href);
        await shot(tester, name);
      }
      for (final href in const ['/notifications', '/profile']) {
        if (!seen.add(href) || !wanted('$who-${href.substring(1)}')) continue;
        shell.go(href);
        await shot(tester, '$who-${href.substring(1)}-$mode');
      }
      shell.go('/dashboard');

      if (wanted('voucher') && session.me.role != 'super_admin') {
        final list = await tester.runAsync(
          () => Get.find<VoucherRepository>().list(scope: 'all'),
        );
        if (list != null && list.isNotEmpty) {
          Get.toNamed(Routes.voucher, arguments: list.first.id);
          await shot(tester, '$who-voucher-$mode');
          Get.back();
          await wait(tester, 500);
        }
      }
      if (wanted('create') && shell.canCreate) {
        Get.toNamed(Routes.createVoucher);
        await shot(tester, '$who-create-$mode');
        Get.back();
        await wait(tester, 500);
      }
      if (wanted('menu')) {
        final state = tester.state<ScaffoldState>(find.byType(Scaffold).first);
        state.openDrawer();
        await shot(tester, '$who-drawer-$mode');
        state.closeDrawer();
        await wait(tester, 400);
      }

      await tester.runAsync(session.signOut);
      Get.offAllNamed(Routes.login);
      await wait(tester, 800);
    }

    FlutterError.onError = original;
  });
}
