// A self-registered company waits for platform approval: the model reads the
// status, registration honours the server's verification flag, and the
// waiting screen fits a small phone in both languages and appearances.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/auth_repository.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/modules/auth/pending_page.dart';

const _company = {
  'id': 9,
  'name': 'Afiya Beverages Limited',
  'status': 'pending',
  'currency': 'TZS',
  'plan': {'id': 2, 'code': 'business', 'name': 'Business', 'price': 99000},
};

const _user = {
  'id': 40,
  'company_id': 9,
  'name': 'Amina Juma',
  'initials': 'AJ',
  'email': 'amina@afiya.test',
  'role': 'company_admin',
};

void main() {
  tearDown(Get.reset);

  test('a pending company is pending; any other status is not', () {
    expect(Company.fromJson(_company).isPending, isTrue);
    expect(Company.fromJson({..._company, 'status': 'trial'}).isPending, isFalse);
  });

  test('registration reads whether an e-mail code follows', () {
    final base = {'token': 't', 'user': _user, 'company': _company};
    expect(Registration({...base, 'requires_verification': false}).requiresVerification, isFalse);
    expect(
      Registration({
        ...base,
        'requires_verification': true,
        'otp': {'identifier': 'amina@afiya.test'},
      }).requiresVerification,
      isTrue,
    );
    // An older server that does not send the flag still asks for the code.
    expect(Registration(base).requiresVerification, isTrue);
  });

  for (final locale in const ['en', 'sw']) {
    for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('the waiting screen at 320px, $locale ${mode.name}', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({});
        final api = await ApiService(mock: MockApi()).init();
        Get.put(api);
        final session = SessionService(api);
        Get.put(session);
        session.user.value = AppUser.fromJson(_user);
        session.company.value = Company.fromJson(_company);

        await tester.pumpWidget(
          GetMaterialApp(
            translations: VfTranslations(),
            locale: Locale(locale),
            theme: VfTheme.light(),
            darkTheme: VfTheme.dark(),
            themeMode: mode,
            home: const PendingApprovalPage(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(locale == 'en' ? 'Awaiting approval' : 'Inasubiri idhini'), findsOneWidget);
        expect(find.text('Afiya Beverages Limited'), findsOneWidget);
        expect(find.text('Business'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
