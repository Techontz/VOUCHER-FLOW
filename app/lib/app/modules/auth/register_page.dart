import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Company registration — placeholder until the screen is built (owned by the auth work).
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPushedScaffold(
    title: 'app.name'.tr,
    body: const SizedBox.shrink(),
  );
}
