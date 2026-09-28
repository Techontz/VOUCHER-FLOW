// The reports screen: every report kind lays out on a small phone, the
// filters sheet narrows the report, the scope is shown, and an offline mock
// shows the error state rather than crashing.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/models/report_models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/report_repository.dart';
import 'package:vouchflow/app/modules/reports/report_format.dart';
import 'package:vouchflow/app/modules/reports/reports_page.dart';
import 'package:vouchflow/app/widgets/vf/vf.dart';

Map<String, dynamic> _kind(String key, String icon, String title) => {
  'key': key,
  'icon': icon,
  'title': title,
  'title_sw': title,
  'body': '$title body',
  'body_sw': '$title body',
};

class FakeReportRepository extends ReportRepository {
  FakeReportRepository({this.level = 'company'}) : super(ApiService(mock: MockApi()));

  final String level;
  final calls = <(String, Map<String, String>)>[];

  @override
  Future<ReportCatalogue> catalogue() async => ReportCatalogue(
    [
      ReportKind.fromJson(_kind('vouchers', 'ph-receipt', 'Voucher report')),
      ReportKind.fromJson(_kind('payments', 'ph-wallet', 'Payment report')),
      ReportKind.fromJson(_kind('cash', 'ph-money', 'Cash report')),
      ReportKind.fromJson(_kind('departments', 'ph-buildings', 'Department report')),
      ReportKind.fromJson(_kind('approvals', 'ph-list-checks', 'Approval report')),
    ],
    ReportScope.fromJson({
      'level': level,
      'label': level == 'company' ? 'Company-wide' : 'Procurement · Production',
      'department_ids': level == 'company' ? null : [1, 2],
    }),
  );

  @override
  Future<ReportResult> show(String kind, Map<String, String> params) async {
    calls.add((kind, params));
    final (headings, row) = switch (kind) {
      'payments' => (
        ['Number', 'Format', 'Paid on', 'Payee', 'Department', 'Amount', 'Paid so far', 'Balance', 'Currency', 'Method', 'Reference', 'Paid by', 'Status'],
        <Object?>['PV-2026-000055', 'Bank', '2026-09-14', 'A payee with a very long registered company name Ltd', 'Procurement', 123456789.5, 150000, 0, 'TZS', 'Bank Transfer', 'CRDB-DEPLOY-7781', 'Mwajuma Hamisi', 'Partially paid'],
      ),
      'departments' => (
        ['Department', 'Head of department', 'Manager', 'Vouchers', 'Approved value', 'Pending value'],
        <Object?>['Procurement and Supplies Management Unit', 'Joseph Mushi', '—', 18, 91568000, 1200000],
      ),
      _ => (
        ['Number', 'Date', 'Type', 'Department', 'Requester', 'Payee', 'Purpose', 'Amount', 'Currency', 'Status'],
        <Object?>['PV-2026-000059', '2026-09-28', 'Payment Voucher', 'Human Resources', 'Neema Shirima', 'Puma Energy Tanzania Ltd', 'Vehicle fuel expenses for the quarterly field visit to all regional offices', 450000, 'TZS', 'Awaiting HOD signature'],
      ),
    };
    return ReportResult.fromJson({
      'kind': kind,
      'headings': headings,
      'rows': [row, row],
      'summary': {
        'count': 65,
        'total_text': 'TZS 239,807,255',
        'approved_total_text': 'TZS 13,360,000',
        'bank_total_text': 'TZS 114,318,000',
        'bank_count': 22,
        'cash_total_text': 'TZS 30,170,000',
        'cash_count': 12,
        'outstanding_total_text': 'TZS 13,360,000',
        'outstanding_count': 2,
      },
      'generated_at': '2026-09-28T10:00:00+03:00',
    });
  }

  @override
  Future<List<Department>> departments() async => [
    Department.fromJson({'id': 1, 'name': 'Procurement'}),
    Department.fromJson({'id': 2, 'name': 'Production'}),
    Department.fromJson({'id': 3, 'name': 'Finance'}),
  ];

  @override
  Future<List<VoucherType>> voucherTypes() async => [
    VoucherType.fromJson({'id': 1, 'name': 'Payment Voucher'}),
  ];

  @override
  Future<List<ReportPerson>> people() async => [
    ReportPerson.fromJson({'id': 1, 'name': 'Frank Kessy', 'department_id': 1}),
    ReportPerson.fromJson({'id': 2, 'name': 'Baraka Mollel', 'department_id': 2}),
  ];

  @override
  Future<Uint8List> export(String kind, Map<String, String> params, String format) async => Uint8List(0);
}

Widget _host(Widget child, {ThemeData? theme}) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: theme ?? VfTheme.dark(),
  home: Scaffold(body: child),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  for (final width in [320.0, 360.0, 820.0]) {
    testWidgets('every report lays out at ${width.toInt()}px', (tester) async {
      await _size(tester, width, 900);
      final repo = FakeReportRepository();
      await tester.pumpWidget(_host(ReportsPage(repository: repo)));
      await tester.pumpAndSettle();

      expect(find.text('Company-wide'), findsOneWidget);
      expect(find.text('PV-2026-000059'), findsWidgets);
      expect(find.text('TZS 450,000'), findsWidgets);
      expect(find.text('28 Sep 2026'), findsWidgets);

      for (final title in ['Payment report', 'Cash report', 'Department report', 'Approval report']) {
        await tester.ensureVisible(find.text(title).first);
        await tester.tap(find.text(title).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(repo.calls.map((c) => c.$1), containsAll(['vouchers', 'payments', 'cash', 'departments', 'approvals']));
    });
  }

  testWidgets('money reports show the bank / cash / outstanding split', (tester) async {
    await _size(tester, 360, 900);
    await tester.pumpWidget(_host(ReportsPage(repository: FakeReportRepository()), theme: VfTheme.light()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Payment report').first);
    await tester.tap(find.text('Payment report').first);
    await tester.pumpAndSettle();

    expect(find.text('Paid by bank'), findsOneWidget);
    expect(find.text('TZS 114,318,000'), findsOneWidget);
    expect(find.text('22 vouchers'), findsOneWidget);
    expect(find.text('TZS 123,456,789.5'), findsWidgets);
  });

  testWidgets('the filters sheet narrows the report and counts what is on', (tester) async {
    await _size(tester, 360, 800);
    final repo = FakeReportRepository(level: 'departments');
    await tester.pumpWidget(_host(ReportsPage(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Procurement · Production'), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    // The department picker only offers the caller's own departments.
    expect(find.text('Employee'), findsOneWidget);
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash Voucher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(repo.calls.last.$2, {'kind': 'cash'});
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Cash Voucher'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.$2, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the offline mock shows the error state', (tester) async {
    await _size(tester, 360, 800);
    await tester.pumpWidget(_host(ReportsPage(repository: ReportRepository(ApiService(mock: MockApi())))));
    await tester.pumpAndSettle();
    expect(find.byType(VouchFlowErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('cells are formatted like the web', () {
    expect(ReportFormat.cell(1234567.891), '1,234,567.89');
    expect(ReportFormat.cell('2026-09-24'), '24 Sep 2026');
    expect(ReportFormat.cell('2026-09-24', sw: true), '24 Sep 2026');
    expect(ReportFormat.cell('2026-08-02', sw: true), '2 Ago 2026');
    expect(ReportFormat.cell('2026-09-24 10:30'), '2026-09-24 10:30');
    expect(ReportFormat.cell(null), '—');
    expect(ReportFormat.statusTag('Paid'), 'tag-accent');
    expect(ReportFormat.statusTag('Partially paid'), 'tag-warn');
    expect(ReportFormat.statusTag('Rejected'), 'tag-accent-2');
    expect(ReportFormat.statusTag('Awaiting HOD signature'), 'tag-info');
  });
}
