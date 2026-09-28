import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Platform companies — placeholder until the screen is built (owned by the platform work).
class PlatformCompaniesPage extends StatelessWidget {
  const PlatformCompaniesPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.companies'.tr)],
  );
}
