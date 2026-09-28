// The company-administration screens, pumped at phone width against real
// API responses (test/support/admin_fixtures.dart), to catch overflows and
// broken states — and the workflow payload rule the web learned the hard way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/admin_models.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/admin_repository.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/modules/admin/audit_page.dart';
import 'package:vouchflow/app/modules/admin/departments_page.dart';
import 'package:vouchflow/app/modules/admin/employees_page.dart';
import 'package:vouchflow/app/modules/admin/settings_page.dart';
import 'package:vouchflow/app/modules/admin/subscription_page.dart';
import 'package:vouchflow/app/modules/admin/admin_widgets.dart';

import 'support/admin_fixtures.dart';

Map<String, dynamic> _fx(String k) => Map<String, dynamic>.from(adminFixtures[k] as Map);
List<Map<String, dynamic>> _rows(String k) => [for (final r in _fx(k)['data'] as List) Map<String, dynamic>.from(r as Map)];

/// Serves the captured responses instead of the network.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin() : super(ApiService(mock: MockApi()));

  @override
  Future<Paginated<Employee>> employees({String q = '', String role = '', String status = '', String departmentId = '', int page = 1}) async =>
      Paginated.fromJson(_fx('employees'), Employee.fromJson);
  @override
  Future<List<AdminDepartment>> departments() async => [for (final r in _rows('departments')) AdminDepartment.fromJson(r)];
  @override
  Future<List<DirectoryUser>> directory() async => [for (final r in _rows('directory')) DirectoryUser.fromJson(r)];
  @override
  Future<Paginated<AuditEntry>> audit({String q = '', String action = '', String from = '', String to = '', int page = 1}) async =>
      Paginated.fromJson(_fx('audit'), AuditEntry.fromJson);
  @override
  Future<List<String>> auditActions() async => [for (final a in _fx('auditActions')['data'] as List) '$a'];
  @override
  Future<List<AdminVoucherType>> voucherTypes({bool includeInactive = false}) async =>
      [for (final r in _rows('types')) AdminVoucherType.fromJson(r)];
  @override
  Future<List<Workflow>> workflows() async => [for (final r in _rows('workflows')) Workflow.fromJson(r)];
  @override
  Future<List<WorkflowPreset>> presets() async => [for (final r in _rows('presets')) WorkflowPreset.fromJson(r)];
  @override
  Future<WorkflowRouting> routing(int workflowId) async => WorkflowRouting.fromJson(Map<String, dynamic>.from(_fx('routing')['data'] as Map));
  @override
  Future<CompanyProfile> company() async => CompanyProfile.fromJson(Map<String, dynamic>.from(_fx('company')['data'] as Map));
  @override
  Future<BillingState> billing() async => BillingState.fromJson(_fx('billing'));
  @override
  Future<List<Invoice>> invoices() async => [for (final r in _rows('invoices')) Invoice.fromJson(r)];
}

void main() {
  late _FakeAdmin repo;

  setUp(() {
    Get.testMode = true;
    final api = ApiService(mock: MockApi());
    Get.put<ApiService>(api);
    final session = Get.put(SessionService(api));
    session.company.value = Company.fromJson(Map<String, dynamic>.from(_fx('company')['data'] as Map));
    session.user.value = AppUser.fromJson({'id': 1, 'name': 'Neema Shirima', 'email': 'admin@watercom.test', 'role': 'company_admin'});
    repo = _FakeAdmin();
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Widget page, {double width = 320}) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VfTranslations(),
        locale: const Locale('en'),
        theme: VfTheme.light(),
        darkTheme: VfTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(body: page),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('employees list lays out at 320', (tester) async {
    await pump(tester, EmployeesPage(repository: repo));
    expect(tester.takeException(), isNull);
    expect(find.text('Invite user'), findsOneWidget);
  });

  testWidgets('departments list lays out at 320', (tester) async {
    await pump(tester, DepartmentsPage(repository: repo));
    expect(tester.takeException(), isNull);
    expect(find.text('Add department'), findsOneWidget);
  });

  testWidgets('audit log lays out at 320', (tester) async {
    await pump(tester, AuditPage(repository: repo));
    expect(tester.takeException(), isNull);
    expect(find.text('All actions'), findsOneWidget);
  });

  testWidgets('subscription lays out at 320', (tester) async {
    await pump(tester, SubscriptionPage(repository: repo));
    expect(tester.takeException(), isNull);
    expect(find.text('Change plan'), findsOneWidget);
  });

  for (final section in ['workflow', 'types', 'company']) {
    testWidgets('settings › $section lays out at 320', (tester) async {
      AdminSettings.section.value = section;
      await pump(tester, SettingsPage(repository: repo));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a workflow step opens without overflow', (tester) async {
    AdminSettings.section.value = 'workflow';
    await pump(tester, SettingsPage(repository: repo));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pump();
    final level = find.textContaining('HOD signature').first;
    await tester.ensureVisible(level);
    await tester.tap(level);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Step name'), findsOneWidget);
  });

  test('the workflow payload sends every stored flag back', () {
    final wf = Workflow.fromJson(_rows('workflows').first);
    final body = workflowPayload(wf, wf.steps);
    final steps = body['steps'] as List;
    expect(steps, hasLength(wf.steps.length));
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i] as Map;
      for (final k in ['can_sign', 'can_approve', 'can_reject', 'can_request_changes', 'can_pay', 'can_print', 'can_download', 'requires_signature']) {
        expect(s.containsKey(k), isTrue, reason: k);
      }
      expect(s['can_pay'], wf.steps[i].canPay);
      expect(s['position'], i + 1);
    }
    expect(body.containsKey('voucher_type_id'), isTrue);
    expect(body.containsKey('name_sw'), isTrue);
  });
}
