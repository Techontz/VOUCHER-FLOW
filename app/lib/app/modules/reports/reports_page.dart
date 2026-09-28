import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Reports — placeholder until the screen is built (owned by the reports work).
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.reports'.tr)],
  );
}
