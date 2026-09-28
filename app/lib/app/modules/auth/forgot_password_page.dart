import 'package:flutter/material.dart';

import 'verify_account_page.dart';

/// "Forgot password?" — the web's /verify?purpose=password_reset: send a
/// reset code to the address on the account, then set a new password.
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountCodePage(purpose: CodePurpose.passwordReset);
}
