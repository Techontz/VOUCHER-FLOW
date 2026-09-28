import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// One company, as the platform sees it — placeholder until the screen is built (owned by the platform work).
class PlatformCompanyPage extends StatelessWidget {
  const PlatformCompanyPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPushedScaffold(
    title: 'nav.companies'.tr,
    body: const SizedBox.shrink(),
  );
}
