// The platform super admin screens: companies, one company (every tab),
// users, plans and payments — pumped at phone widths in both appearances
// against the API's own response shapes (test/fixtures/platform), so a
// RenderFlex overflow or a parsing slip fails here rather than on a device.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/platform_models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/platform_repository.dart';
import 'package:vouchflow/app/modules/platform/companies_page.dart';
import 'package:vouchflow/app/modules/platform/company_detail_page.dart';
import 'package:vouchflow/app/modules/platform/plans_page.dart';
import 'package:vouchflow/app/modules/platform/platform_payments_page.dart';
import 'package:vouchflow/app/modules/platform/users_page.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/platform/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Answers the platform endpoints from recorded API responses.
class _PlatformApi extends MockApi {
  final calls = <String>[];

  @override
  Future<dynamic> handle(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
  }) async {
    calls.add('$method $path');
    if (method != 'GET') return {'message': 'ok', 'data': _fixture('company')['data']};
    return switch (path) {
      '/platform/companies' => _fixture('companies'),
      '/platform/companies/1' => _fixture('company'),
      '/platform/companies/1/overview' => _fixture('overview'),
      '/platform/companies/1/users' => _fixture('company_users'),
      '/platform/companies/1/departments' => _fixture('departments'),
      '/platform/companies/1/workflows' => _fixture('workflows'),
      '/platform/companies/1/vouchers' => _fixture('vouchers'),
      '/platform/plans' => _fixture('plans'),
      '/platform/payments' => _fixture('payments'),
      '/platform/users' => _fixture('users'),
      '/audit-logs' => _fixture('audit'),
      _ => throw ApiException(404, 'Not found'),
    };
  }
}

void main() {
  late _PlatformApi mock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mock = _PlatformApi();
    Get.put(await ApiService(mock: mock).init());
  });

  tearDown(Get.reset);

  Future<void> host(WidgetTester tester, Widget home, {double width = 360, bool dark = true, String locale = 'en'}) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VfTranslations(),
        locale: Locale(locale),
        theme: VfTheme.light(),
        darkTheme: VfTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: home),
        getPages: [GetPage(name: '/platform/company', page: () => const PlatformCompanyPage())],
      ),
    );
    await tester.pumpAndSettle();
  }

  test('parses the platform API shapes', () {
    final detail = CompanyDetail.fromJson(_fixture('company'));
    expect(detail.company.name, 'Watercom (T) Limited');
    expect(detail.company.plan?.name, 'Business');
    expect(detail.metric('users')?.limit, 50);
    expect(detail.admins, isNotEmpty);
    final o = CompanyOverview.fromJson(_fixture('overview')['data'] as Map<String, dynamic>);
    expect(o.v('total'), greaterThan(0));
    expect(o.monthly, hasLength(6));
    final wf = CompanyWorkflows.fromJson(_fixture('workflows')['data'] as Map<String, dynamic>);
    expect(wf.workflows.first.steps.first.isRequestStep, isTrue);
    expect(wf.hasRouting, isTrue);
    final page = PlatformPage.fromJson(_fixture('vouchers'), PlatformVoucherRow.fromJson);
    expect(page.metaNum('total_amount'), greaterThan(0));
  });

  for (final dark in [true, false]) {
    for (final width in [320.0, 360.0]) {
      final label = '${dark ? 'dark' : 'light'} @${width.toInt()}';

      testWidgets('companies list, $label', (tester) async {
        await host(tester, const PlatformCompaniesPage(), width: width, dark: dark);
        expect(find.text('Companies'), findsWidgets);
        expect(find.text('New company'), findsOneWidget);
        expect(find.text('Baobab Business Solutions'), findsOneWidget);
        await tester.tap(find.text('New company'));
        await tester.pumpAndSettle();
        expect(find.text('Create company'), findsOneWidget);
      });

      testWidgets('users, plans and payments, $label', (tester) async {
        await host(tester, const PlatformUsersPage(), width: width, dark: dark);
        expect(find.text('Every account across all tenants.'), findsNothing);
        await host(tester, const PlatformPlansPage(), width: width, dark: dark);
        expect(find.text('Starter'), findsOneWidget);
        await tester.tap(find.byTooltip('Edit Starter'));
        await tester.pumpAndSettle();
        expect(find.text('Limits — leave blank for unlimited'.toUpperCase()), findsOneWidget);
        await host(tester, const PlatformPaymentsPage(), width: width, dark: dark);
        expect(find.text('Collected'), findsOneWidget);
        expect(find.text('Mark paid'), findsOneWidget);
      });

      testWidgets('company page, every tab, $label', (tester) async {
        await host(tester, const SizedBox.shrink(), width: width, dark: dark);
        Get.toNamed('/platform/company', arguments: 1);
        await tester.pumpAndSettle();
        expect(find.text('Watercom (T) Limited'), findsWidgets);
        expect(find.text('Edit branding'), findsOneWidget);
        for (final tab in [
          'Branding & voucher design',
          'Users',
          'Departments',
          'Workflow',
          'Vouchers',
          'Payments',
          'Subscription',
          'Activity',
          'Overview',
        ]) {
          await tester.ensureVisible(find.text(tab).first);
          await tester.tap(find.text(tab).first);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Edit branding').first);
        await tester.pumpAndSettle();
        expect(find.text('Save branding'), findsOneWidget);
      });
    }
  }

  testWidgets('the company page reads in Swahili', (tester) async {
    await host(tester, const SizedBox.shrink(), locale: 'sw');
    Get.toNamed('/platform/company', arguments: 1);
    await tester.pumpAndSettle();
    expect(find.text('Hariri chapa'), findsOneWidget);
    expect(find.text('Muhtasari'), findsOneWidget);
  });

  testWidgets('a people-by-role row opens Users filtered by that role', (tester) async {
    await host(tester, const SizedBox.shrink(), width: 390);
    Get.toNamed('/platform/company', arguments: 1);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cashier'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashier'));
    await tester.pumpAndSettle();
    expect(mock.calls, contains('GET /platform/companies/1/users'));
    expect(find.text('Search name, email or employee ID'), findsOneWidget);
  });

  test('the repository is registered once', () {
    expect(identical(PlatformRepository.to, PlatformRepository.to), isTrue);
  });
}
