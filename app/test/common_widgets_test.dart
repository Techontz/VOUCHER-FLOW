// The shared legacy widgets keep their constructors and lay out on a small
// phone in both appearances, now drawn with the web's components.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/widgets/common.dart';

void main() {
  for (final (name, theme) in [('dark', VfTheme.dark()), ('light', VfTheme.light())]) {
    testWidgets('legacy widgets lay out at 320px ($name)', (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var selected = false;
      await tester.pumpWidget(
        GetMaterialApp(
          translations: VfTranslations(),
          locale: const Locale('en'),
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatusChip(label: 'Awaiting HOD signature', tag: 'tag-info'),
                  const Row(children: [KindChip(kind: 'cash'), KindChip(kind: 'bank', dense: false)]),
                  Row(
                    children: [
                      Expanded(child: StatTile(label: 'Approved vouchers', value: 'TZS 239,807,255', sub: 'Awaiting payment', icon: 'seal', trend: '+12%')),
                      const SizedBox(width: 12),
                      const Expanded(child: StatTile(label: 'Pending', value: '5', icon: 'ph-hourglass', up: false, trend: '-2')),
                    ],
                  ),
                  const StatTile(label: 'Amount raised', value: 'TZS 221,024,789', icon: 'coins'),
                  const VfPanel(child: Text('Panel')),
                  ChoiceCard(
                    selected: selected,
                    onTap: () => selected = true,
                    icon: PhosphorIconsRegular.bank,
                    label: 'Bank Voucher',
                    sub: 'Transfer or cheque to a bank account',
                  ),
                  const VfNote('Approving moves the voucher to the next step.'),
                  VfNote('A warning', tone: Colors.orange),
                  const SectionHeader(title: 'Drafts and returns', trailing: Text('3')),
                  const EmptyView(title: 'Nothing here', body: 'No vouchers yet', action: Text('Create')),
                  ErrorView(message: 'Cannot reach the server.', onRetry: () {}),
                  const Disclosure(title: 'Attachments', count: 3, icon: PhosphorIconsRegular.paperclip, child: Text('files')),
                  const DocumentFrame(child: SizedBox(width: 794, height: 1123)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Attachments'));
      await tester.pumpAndSettle();
      expect(find.text('files'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);

      showToast('Export ready', body: 'PDF');
      await tester.pumpAndSettle();
      expect(find.text('Export ready'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }

  test('Fmt output is unchanged', () {
    expect(Fmt.money(450000), 'TZS 450,000');
    expect(Fmt.money(1234.5), 'TZS 1,234.50');
    expect(Fmt.plain(1234567), '1,234,567');
    expect(Fmt.date(DateTime(2026, 9, 24)), '24 Sep 2026');
  });
}
