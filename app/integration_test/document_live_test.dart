// The printed document, rendered on the phone from live API data.
//
// test/document_test.dart proves the widget carries a voucher; this proves the
// data reaching it on a device is the real thing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    final deadline = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('a voucher opened on the phone carries the tenant\'s own letterhead', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await settle(tester, 3000);

    await tester.tap(find.textContaining('mwajuma@watercom.test').first);
    await settle(tester, 1200);
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    if (signIn.evaluate().isNotEmpty) await tester.tap(signIn.first);
    await settle(tester, 5000);

    // Open the first voucher in the payment queue.
    await tester.tap(find.textContaining('Approved — awaiting payment').first);
    await settle(tester, 3000);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' | ');

    // The letterhead comes from the company record, not from a constant.
    expect(texts, contains('WATERCOM'));
    expect(texts, contains('TIN 109-482-771'));

    // Each format shows its own particulars and nothing else. A cash claim has
    // no account to be drawn on, and must not print an empty bank block.
    final isCash = texts.contains('CASH');

    if (isCash) {
      expect(texts, contains('RECEIVED BY'));
      expect(texts, isNot(contains('DRAWN ON')));
    } else {
      expect(texts, contains('DRAWN ON'));
      expect(texts, contains('CRDB Bank'));
    }

    // And the marks the workflow has actually collected.
    expect(texts, contains('SIGNED'));
    expect(texts, contains('APPROVED'));

    debugPrint('DOCUMENT >>> ${texts.substring(0, texts.length.clamp(0, 1400))}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
