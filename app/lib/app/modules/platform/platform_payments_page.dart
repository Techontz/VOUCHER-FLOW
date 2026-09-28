import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Platform payments — placeholder until the screen is built (owned by the platform work).
class PlatformPaymentsPage extends StatelessWidget {
  const PlatformPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.payments'.tr)],
  );
}
