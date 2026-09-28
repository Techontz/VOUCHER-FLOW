import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Platform users — placeholder until the screen is built (owned by the platform work).
class PlatformUsersPage extends StatelessWidget {
  const PlatformUsersPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.users'.tr)],
  );
}
