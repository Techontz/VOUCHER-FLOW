import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Subscription — placeholder until the screen is built (owned by the admin work).
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.subscription'.tr)],
  );
}
