// Two-step sign-in: the password alone never yields a session; a code sent by
// email or SMS completes it. Exercised against the mock, then through the
// verification screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouchflow/app/core/translations.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/services/api_service.dart';
import 'package:vouchflow/app/data/services/session_service.dart';
import 'package:vouchflow/app/modules/auth/verify_login_page.dart';
import 'package:vouchflow/app/routes/routes.dart';

void main() {
  group('mock API', () {
    late MockApi api;
    setUp(() => api = MockApi());

    Future<Map<String, dynamic>> login(String email) async =>
        await api.handle(
              'POST',
              '/auth/login',
              body: {'email': email, 'password': 'Password123!'},
            )
            as Map<String, dynamic>;

    Future<dynamic> post(String path, Map<String, dynamic> body) =>
        api.handle('POST', path, body: body);

    Matcher rejected(int status, String reason) => throwsA(
      isA<ApiException>()
          .having((e) => e.statusCode, 'status', status)
          .having((e) => e.reason, 'reason', reason),
    );

    test('the password alone returns a challenge, not a token', () async {
      final body = await login('joseph@watercom.test');
      expect(body['requires_verification'], isTrue);
      expect(body.containsKey('token'), isFalse);
      expect(body['challenge'], isA<String>());

      // Only email is on record, so the code has already gone there.
      expect(body['channels'], hasLength(1));
      expect(body['sent_to'], 'email');
      expect(body['resend_in'], 30);

      // And nothing is reachable until the code is entered.
      await expectLater(
        api.handle('GET', '/auth/me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 401)),
      );
    });

    test('a user with a phone chooses between email and SMS', () async {
      final body = await login('frank@watercom.test');
      final channels = (body['channels'] as List).cast<Map>();
      expect(channels.map((c) => c['channel']), ['email', 'sms']);
      expect(channels.first['destination'], 'f•••@watercom.test');
      expect(channels.last['destination'], '+255 7•• ••• 418');
      expect(body['sent_to'], isNull);

      final challenge = body['challenge'];
      await expectLater(
        post('/auth/login/verify', {'challenge': challenge, 'code': '418205'}),
        rejected(422, 'no_code'),
      );

      final sent =
          await post('/auth/login/send-code', {
                'challenge': challenge,
                'channel': 'sms',
              })
              as Map<String, dynamic>;
      expect(sent['sent_to'], 'sms');
      expect(sent['resend_in'], 30);

      // A second send inside the cooldown is refused with the wait.
      await expectLater(
        post('/auth/login/send-code', {
          'challenge': challenge,
          'channel': 'sms',
        }),
        throwsA(
          isA<ApiException>()
              .having((e) => e.reason, 'reason', 'resend_cooldown')
              .having((e) => e.intValue('retry_after'), 'retry', isPositive),
        ),
      );
    });

    test('SMS is refused when no phone is on record', () async {
      final body = await login('joseph@watercom.test');
      await expectLater(
        post('/auth/login/send-code', {
          'challenge': body['challenge'],
          'channel': 'sms',
        }),
        throwsA(
          isA<ApiException>().having(
            (e) => e.field('channel'),
            'field',
            isNotNull,
          ),
        ),
      );
    });

    test('a wrong code counts down; the right one signs in', () async {
      final body = await login('joseph@watercom.test');
      final challenge = body['challenge'];

      await expectLater(
        post('/auth/login/verify', {'challenge': challenge, 'code': '000000'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.reason, 'reason', 'invalid_code')
              .having((e) => e.intValue('attempts_remaining'), 'left', 4)
              .having((e) => e.field('code'), 'field', isNotNull),
        ),
      );

      final session =
          await post('/auth/login/verify', {
                'challenge': challenge,
                'code': MockApi.mockLoginCode,
              })
              as Map<String, dynamic>;
      expect(session['token'], isA<String>());
      expect((session['user'] as Map)['email'], 'joseph@watercom.test');

      final me = await api.handle('GET', '/auth/me') as Map<String, dynamic>;
      expect((me['user'] as Map)['email'], 'joseph@watercom.test');

      // A challenge is good for one sign-in only.
      await expectLater(
        post('/auth/login/verify', {
          'challenge': challenge,
          'code': MockApi.mockLoginCode,
        }),
        rejected(422, 'challenge_expired'),
      );
    });

    test('five wrong codes end the attempt', () async {
      final body = await login('joseph@watercom.test');
      final challenge = body['challenge'];

      for (var i = 0; i < 4; i++) {
        await expectLater(
          post('/auth/login/verify', {
            'challenge': challenge,
            'code': '111111',
          }),
          rejected(422, 'invalid_code'),
        );
      }
      await expectLater(
        post('/auth/login/verify', {'challenge': challenge, 'code': '111111'}),
        rejected(422, 'too_many_attempts'),
      );
      // Even the right code no longer works: the password is needed again.
      await expectLater(
        post('/auth/login/verify', {
          'challenge': challenge,
          'code': MockApi.mockLoginCode,
        }),
        rejected(422, 'challenge_expired'),
      );
    });
  });

  group('verification screen', () {
    late SessionService session;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final api = await ApiService(mock: MockApi()).init();
      Get.put(api);
      session = await Get.putAsync(() => SessionService(api).init());
    });

    tearDown(Get.reset);

    Widget app(LoginChallenge challenge) {
      Get.put(VerifyLoginController(challenge));
      return GetMaterialApp(
        translations: VfTranslations(),
        locale: const Locale('en'),
        home: const VerifyLoginPage(),
        getPages: [
          GetPage(
            name: Routes.shell,
            page: () => const Scaffold(body: Text('signed-in shell')),
          ),
          GetPage(
            name: Routes.login,
            page: () => const Scaffold(body: Text('login')),
          ),
        ],
      );
    }

    Future<void> wait(WidgetTester tester) async {
      // The mock answers after up to 300 ms, twice over for a sign-in.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('choose a method, reject a wrong code, accept the right one', (
      tester,
    ) async {
      late LoginChallenge? challenge;
      await tester.runAsync(() async {
        challenge = await session.signIn('frank@watercom.test', 'Password123!');
      });
      expect(challenge, isNotNull);
      expect(challenge!.channels, hasLength(2));

      await tester.pumpWidget(app(challenge!));
      await tester.pump();

      // Two ways to receive the code; nothing sent yet.
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Text message (SMS)'), findsOneWidget);
      expect(find.text('+255 7•• ••• 418'), findsOneWidget);

      await tester.tap(find.text('Text message (SMS)'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
      await wait(tester);

      expect(
        find.text('We sent a 6-digit code to +255 7•• ••• 418.'),
        findsOneWidget,
      );
      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.text('Use a different method'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await wait(tester);
      expect(
        find.text('That code is not correct. 4 attempts remaining.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), MockApi.mockLoginCode);
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await wait(tester);
      await tester.pumpAndSettle();

      expect(find.text('signed-in shell'), findsOneWidget);
      expect(session.isSignedIn, isTrue);
      expect(session.me.email, 'frank@watercom.test');
    });

    testWidgets('a single channel goes straight to the code', (tester) async {
      late LoginChallenge? challenge;
      await tester.runAsync(() async {
        challenge = await session.signIn(
          'joseph@watercom.test',
          'Password123!',
        );
      });

      await tester.pumpWidget(app(challenge!));
      await tester.pump();

      expect(
        find.text('We sent a 6-digit code to j•••@watercom.test.'),
        findsOneWidget,
      );
      expect(find.text('Use a different method'), findsNothing);
      expect(find.text('Resend code in 30 s'), findsOneWidget);

      // Too short to send.
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pump();
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);

      // Leaving stops the countdown timer.
      Get.find<VerifyLoginController>().backToLogin();
      await tester.pumpAndSettle();
    });
  });
}
