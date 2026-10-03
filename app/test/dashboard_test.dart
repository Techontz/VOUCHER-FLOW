// The dashboard (every role's variant), the inbox and the profile — parsed
// from real API payloads (test/fixtures/dashboard, captured from the local
// backend) and pumped at phone widths to catch overflows.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/dashboard_models.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/dashboard_repository.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/modules/dashboard/dashboard_tab.dart';
import 'package:vouchflow/app/modules/notifications/notifications_tab.dart';
import 'package:vouchflow/app/modules/profile/profile_tab.dart';
import 'package:vouchflow/app/widgets/vf/vf.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/dashboard/$name.json').readAsStringSync())
        as Map<String, dynamic>;

List<QueueWorkflow> _routes() => (_fixture('workflows')['data'] as List)
    .map((e) => QueueWorkflow.fromJson(e as Map<String, dynamic>))
    .toList();

/// Serves the captured payloads instead of the network.
class _FakeRepo extends DashboardRepository {
  _FakeRepo(super.api, this.payload);
  final Map<String, dynamic> payload;

  @override
  Future<DashboardData> dashboard() async => DashboardData.fromJson(payload);

  @override
  Future<List<QueueWorkflow>> workflows(int companyId) async => _routes();

  @override
  Future<NotificationPage<AppNotificationItem>> notifications() async {
    final n = _fixture('notifications');
    return NotificationPage(
      (n['data'] as List)
          .map((e) => AppNotificationItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      (n['meta'] as Map)['unread_count'] as int,
    );
  }
}

const _companyJson = {
  'id': 1,
  'name': 'Watercom (T) Limited',
  'status': 'trial',
  'is_usable': true,
  'days_remaining': 5,
  'trial_ends_at': '2026-10-02T00:00:00Z',
  'currency': 'TZS',
  'plan': {'id': 2, 'code': 'business', 'name': 'Business', 'price': 99000},
};

Future<SessionService> _session(String role, {bool company = true}) async {
  SharedPreferences.setMockInitialValues({});
  final api = await ApiService(mock: MockApi()).init();
  Get.put(api);
  final session = SessionService(api);
  Get.put(session);
  session.user.value = AppUser.fromJson({
    'id': 7,
    'company_id': company ? 1 : null,
    'name': 'Neema Shirima Mwakyusa',
    'initials': 'NS',
    'email': 'admin@watercom.test',
    'phone': '+255 700 000 000',
    'role': role,
    'role_label': 'Company Administrator',
    'job_title': 'Company Administrator',
    'department': {'id': 3, 'name': 'Human Resources'},
    'has_signature': false,
  });
  if (company) session.company.value = Company.fromJson(_companyJson);
  return session;
}

Widget _app(Widget home, {ThemeMode mode = ThemeMode.dark}) => GetMaterialApp(
  translations: VfTranslations(),
  locale: const Locale('en'),
  theme: VfTheme.light(),
  darkTheme: VfTheme.dark(),
  themeMode: mode,
  home: Scaffold(body: home),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(Get.reset);

  group('the /dashboard payload', () {
    const views = {
      'frank': 'employee',
      'joseph': 'hod',
      'emmanuel': 'approver',
      'mwajuma': 'cashier',
      'admin': 'admin',
      'super': 'platform',
    };

    for (final entry in views.entries) {
      test('${entry.key} gets the ${entry.value} dashboard', () {
        final d = DashboardData.fromJson(_fixture('dashboard_${entry.key}'));
        expect(d.view, entry.value);
        expect(d.stats, isNotEmpty);
        expect(d.stats.every((s) => s.key != null), isTrue);
        expect(d.queueRoutes.length, d.queue.length);
        if (entry.value == 'platform') {
          expect(d.banner, isNull);
          expect(d.recentCompanies, isNotEmpty);
          expect(d.activity, isNull);
        } else {
          expect(d.banner, isNotNull);
          expect(d.banner!.count, d.queue.isEmpty ? 0 : greaterThan(0));
          expect(d.activity, isNotNull);
        }
      });
    }

    test('each role carries its own panels', () {
      final admin = DashboardData.fromJson(_fixture('dashboard_admin'));
      expect(admin.overview, isNotNull);
      expect(admin.hasWorkflow, isTrue);
      expect(admin.workflow!.steps, isNotEmpty);
      expect(admin.subscription, isNotNull);
      expect(admin.volume, hasLength(7));
      expect(admin.byDepartment, isNotNull);

      final hod = DashboardData.fromJson(_fixture('dashboard_joseph'));
      expect(hod.recentlySigned, isNotNull);

      final cashier = DashboardData.fromJson(_fixture('dashboard_mwajuma'));
      expect(cashier.paymentTotals, isNotNull);
      expect(
        cashier.paymentTotals!.paid.count,
        cashier.paymentTotals!.bank.count + cashier.paymentTotals!.cash.count,
      );
    });

    test('a queued voucher shows where it is in its route', () {
      final routes = _routes();
      final wf = routes.first;
      final hod = wf.steps.firstWhere((s) => s.role == 'hod');

      final atHod = deriveQueueProgress(
        status: 'in_review',
        amount: 100000,
        workflowId: wf.id,
        currentStepPosition: hod.position,
        workflows: routes,
        sw: false,
      );
      expect(atHod.first.label, 'Prepared');
      expect(atHod.first.state, QueueStepState.done);
      expect(atHod[1].state, QueueStepState.current);
      expect(atHod.last.state, QueueStepState.pending);

      final paid = deriveQueueProgress(
        status: 'paid',
        amount: 100000,
        workflowId: wf.id,
        currentStepPosition: null,
        workflows: routes,
        sw: true,
      );
      expect(paid.first.label, 'Imeandaliwa');
      expect(paid.every((s) => s.state == QueueStepState.done), isTrue);

      final rejected = deriveQueueProgress(
        status: 'rejected',
        amount: 100000,
        workflowId: wf.id,
        currentStepPosition: null,
        workflows: routes,
        sw: false,
      );
      expect(rejected.where((s) => s.state == QueueStepState.rejected), hasLength(1));

      expect(
        deriveQueueProgress(
          status: 'in_review',
          amount: 1,
          workflowId: 999,
          currentStepPosition: 2,
          workflows: routes,
          sw: false,
        ),
        isEmpty,
      );
    });
  });

  group('the dashboard fits a small phone', () {
    const roles = {
      'frank': 'employee',
      'joseph': 'hod',
      'emmanuel': 'ceo',
      'mwajuma': 'cashier',
      'admin': 'company_admin',
      'super': 'super_admin',
    };

    for (final entry in roles.entries) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        testWidgets('${entry.key} at 320 wide (${mode.name})', (tester) async {
          await _size(tester, 320, 5200);
          await _session(entry.value, company: entry.key != 'super');
          Get.put<DashboardRepository>(
            _FakeRepo(Get.find(), _fixture('dashboard_${entry.key}')),
          );
          Get.put(DashboardController());

          await tester.pumpWidget(_app(const DashboardTab(), mode: mode));
          await _settle(tester);

          expect(tester.takeException(), isNull);
          expect(find.textContaining('Neema'), findsWidgets);
          if (entry.key == 'super') {
            expect(find.text('Recent companies'), findsOneWidget);
          } else {
            // The trial ends within a week: the web's warning banner.
            expect(find.textContaining('Trial ends'), findsOneWidget);
          }
          // Home is app-like: a hero with one action, round shortcuts,
          // and no web-style "Create voucher" button (the tab bar's + is).
          expect(find.text('Create voucher'), findsNothing);
          if (entry.key == 'super') {
            expect(find.text('Monthly revenue'), findsOneWidget);
            expect(find.text('Companies'), findsWidgets);
          } else {
            expect(find.text('Review'), findsOneWidget);
            expect(find.text('Reports').evaluate().isNotEmpty ||
                find.text('Approvals').evaluate().isNotEmpty, isTrue);
          }
          if (entry.key == 'mwajuma') {
            expect(find.text('Payment totals'), findsOneWidget);
          }
          if (entry.key == 'admin') {
            expect(find.text('Approval workflow'), findsOneWidget);
            expect(find.text('Stalled vouchers'), findsOneWidget);
            expect(find.text('Stalled'), findsOneWidget);
          }
        });
      }
    }

    testWidgets('a failed load shows the error, not a crash', (tester) async {
      await _size(tester, 320, 800);
      await _session('employee');
      Get.put(DashboardRepository(Get.find()));
      Get.put(DashboardController());
      await tester.pumpWidget(_app(const DashboardTab()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('the inbox groups by day and fits 320', (tester) async {
    await _size(tester, 320, 2400);
    await _session('ceo');
    Get.put<DashboardRepository>(
      _FakeRepo(Get.find(), _fixture('dashboard_emmanuel')),
    );
    Get.put(NotificationsController());
    await tester.pumpWidget(_app(const NotificationsTab()));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('46'), findsOneWidget); // the unread count pill
    expect(find.byTooltip('Mark all read'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
  });

  testWidgets('every profile page fits 320', (tester) async {
    await _size(tester, 320, 1600);
    await _session('company_admin');
    Get.put(ProfileController());
    await tester.pumpWidget(_app(const ProfileTab()));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    // A settings list, not the web's tab strip.
    for (final row in [
      'Personal details',
      'Signature',
      'Change password',
      'Active sessions',
      'Language',
      'Dark mode',
      'Sign out',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }

    // Each row opens its form as a pushed page.
    for (final (row, inside) in [
      ('Personal details', 'Full name'),
      ('Signature', 'Draw'),
      ('Active sessions', 'Sign out everywhere'),
      ('Change password', 'Current password'),
    ]) {
      await tester.tap(find.text(row));
      await _settle(tester);
      expect(
        find.textContaining(inside, findRichText: true),
        findsWidgets,
        reason: row,
      );
      expect(tester.takeException(), isNull, reason: row);
      if (row != 'Change password') {
        await tester.tap(find.byTooltip('Back'));
        await _settle(tester);
      }
    }

    // Client-side checks mirror the web's required/minLength rules.
    final submit = find.widgetWithText(VouchFlowButton, 'Change password');
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await _settle(tester);
    expect(find.text('This is required.'), findsWidgets);
  });
}
