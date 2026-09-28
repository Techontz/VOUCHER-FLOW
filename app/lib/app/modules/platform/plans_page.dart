import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Plans — placeholder until the screen is built (owned by the platform work).
class PlatformPlansPage extends StatelessWidget {
  const PlatformPlansPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.plansSubs'.tr)],
  );
}
