import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Password reset — placeholder until the screen is built (owned by the auth work).
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPushedScaffold(
    title: 'auth.forgot'.tr,
    body: const SizedBox.shrink(),
  );
}
