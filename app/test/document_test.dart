// The printed document must carry every part of the voucher, at any size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/widgets/common.dart';
import 'package:vouchflow/app/widgets/voucher_document.dart';

void main() {
  late Voucher voucher;
  late Company company;

  setUp(() async {
    final api = MockApi();
    final session = await api.handle('POST', '/auth/login', body: {
      'email': 'joseph@watercom.test',
      'password': 'Password123!',
    }) as Map<String, dynamic>;
    company = Company.fromJson(session['company'] as Map<String, dynamic>);

    final queue = (await api.handle('GET', '/vouchers/pending'))['data'] as List;
    final id = (queue.first as Map)['id'] as int;
    voucher = Voucher.fromJson(
      (await api.handle('GET', '/vouchers/$id'))['data'] as Map<String, dynamic>,
    );
  });

  Widget host(Widget child) => GetMaterialApp(
    translations: VfTranslations(),
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );

  testWidgets('the document carries the whole voucher', (tester) async {
    await tester.pumpWidget(host(
      SingleChildScrollView(
        child: VoucherDocument(voucher: voucher, company: company),
      ),
    ));
    await tester.pumpAndSettle();

    // Letterhead: the company's own identity, not the platform's.
    expect(find.text('WATERCOM (T) LIMITED'), findsOneWidget);
    expect(find.textContaining('P.O. Box 20831'), findsOneWidget);

    // The substance.
    // The payee heads the document and, on a bank voucher, names the account
    // as well — so more than one occurrence is correct.
    expect(find.text(voucher.payee), findsWidgets);
    expect(find.text(voucher.purpose), findsOneWidget);
    expect(find.text('PARTICULARS'), findsOneWidget,
        reason: 'the ruled form is the body of a voucher');
    expect(find.text('TOTAL PAYABLE'), findsOneWidget);
    expect(find.textContaining('shillings only'), findsOneWidget);

    // The payment particulars, which differ by format.
    expect(find.text('PAYMENT PARTICULARS'), findsOneWidget);
    expect(find.text('ACCOUNT NO.'), findsOneWidget,
        reason: 'a bank voucher names the account it settles into');
    expect(find.text('DRAWN ON'), findsOneWidget,
        reason: "and the company account it is drawn on");

    // The authorisation band, with a column for every act.
    expect(find.text('AUTHORISATION'), findsOneWidget);
    for (final caption in ['PREPARED BY', 'SIGNED BY', 'APPROVED BY']) {
      expect(find.text(caption), findsOneWidget);
    }
  });

  testWidgets('it survives being scaled down to a phone', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      DocumentFrame(child: VoucherDocument(voucher: voucher, company: company)),
    ));
    await tester.pumpAndSettle();

    // Scaling must not drop anything: the same document, smaller.
    expect(find.text('PARTICULARS'), findsOneWidget);
    expect(find.text('PAYMENT PARTICULARS'), findsOneWidget);
    expect(find.text('TOTAL PAYABLE'), findsOneWidget);
    expect(find.text('AUTHORISATION'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'a fixed A4 sheet should never overflow its own frame');
  });
}
