// The public screens at phone width, against the offline mock: sign-in (no
// demo accounts outside mock mode), registration through all five steps,
// password reset and onboarding — each must lay out without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/modules/auth/forgot_password_page.dart';
import 'package:vouchflow/app/modules/auth/login_page.dart';
import 'package:vouchflow/app/modules/auth/onboarding_page.dart';
import 'package:vouchflow/app/modules/auth/register_page.dart';

import 'support/mock_sign_in.dart';

void main() {
  late MockApi mock;
  late SessionService session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mock = MockApi();
    final api = await ApiService(mock: mock).init();
    Get.put(api);
    session = await Get.putAsync(() => SessionService(api).init());
  });

  tearDown(Get.reset);

  Future<void> phone(WidgetTester tester, Widget home, {double width = 360, bool dark = true}) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VfTranslations(),
        locale: const Locale('en'),
        theme: VfTheme.light(),
        darkTheme: VfTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      ),
    );
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text, {bool first = false}) async {
    final f = first ? find.text(text).first : find.text(text).last;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  testWidgets('sign-in at 320px, with no demo accounts outside mock mode', (tester) async {
    Get.put(LoginController());
    await phone(tester, const LoginPage(), width: 320);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Register your company'), findsOneWidget);
    expect(find.text('Demo sign-in as'.toUpperCase()), findsNothing);
    expect(find.textContaining('Password123!'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration walks all five steps at 360px, light and dark', (tester) async {
    for (final dark in [true, false]) {
      await phone(tester, const RegisterPage(), dark: dark);
      expect(find.text('Tell us about your company'), findsOneWidget);

      // Continue with nothing filled: the required field is flagged.
      await tapText(tester, 'Continue');
      expect(find.text('This is required.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Afiya Beverages Limited');
      await tapText(tester, 'Continue');
      expect(find.text('How can we reach you?'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Amina Juma');
      await tester.enterText(find.byType(TextField).at(1), 'accounts@afiya.co.tz');
      await tapText(tester, 'Continue');
      expect(find.text('Make it yours'), findsOneWidget);
      // The mock has no design catalogue: the gallery says so, never crashes.
      expect(find.text('Previews are unavailable right now.'), findsOneWidget);

      await tapText(tester, 'Continue');
      expect(find.text('Create the administrator'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Amina Juma');
      await tester.enterText(find.byType(TextField).at(1), 'amina@afiya.co.tz');
      await tester.enterText(find.byType(TextField).at(2), 'Secret#2026');
      await tester.enterText(find.byType(TextField).at(3), 'Secret#2026');
      await tapText(tester, 'Continue');
      expect(find.text('Review and create'), findsOneWidget);
      expect(find.text('Afiya Beverages Limited'), findsOneWidget);

      // Edit returns to the step.
      await tapText(tester, 'Edit', first: true);
      expect(find.text('Tell us about your company'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    }
  });

  testWidgets('Swahili sign-in and registration at 320px', (tester) async {
    Get.put(LoginController());
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VfTranslations(),
        locale: const Locale('sw'),
        theme: VfTheme.light(),
        darkTheme: VfTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const LoginPage(),
      ),
    );
    await settle(tester);
    expect(find.text('Karibu tena'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: VfTranslations(),
        locale: const Locale('sw'),
        theme: VfTheme.light(),
        home: const RegisterPage(),
      ),
    );
    await settle(tester);
    expect(find.text('Tueleze kuhusu kampuni yako'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password reset at 360px', (tester) async {
    await phone(tester, const ForgotPasswordPage());
    expect(find.text('Change password'), findsOneWidget);
    expect(find.textContaining('New password'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding at 360px', (tester) async {
    late Map<String, dynamic> data;
    await tester.runAsync(() async {
      data = await mockSignIn(mock, 'admin@watercom.test');
      await session.startSessionFrom(data);
    });
    await phone(tester, const OnboardingPage());
    expect(find.text('Company details'), findsWidgets);
    expect(find.text('Setup checklist'.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The mock answers after up to 300 ms.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}
