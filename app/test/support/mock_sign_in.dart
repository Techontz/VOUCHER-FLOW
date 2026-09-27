import 'package:vouchflow/app/data/mock/mock_api.dart';

/// Signs [email] in against the mock through both steps — password, then the
/// fixture's fixed code — and returns the session body ({token, user, company}).
Future<Map<String, dynamic>> mockSignIn(MockApi api, String email) async {
  final login =
      await api.handle(
            'POST',
            '/auth/login',
            body: {'email': email, 'password': 'Password123!'},
          )
          as Map<String, dynamic>;
  if (login['requires_verification'] != true) return login;

  final challenge = login['challenge'];
  if (login['sent_to'] == null) {
    await api.handle(
      'POST',
      '/auth/login/send-code',
      body: {'challenge': challenge, 'channel': 'email'},
    );
  }
  return await api.handle(
        'POST',
        '/auth/login/verify',
        body: {'challenge': challenge, 'code': MockApi.mockLoginCode},
      )
      as Map<String, dynamic>;
}
