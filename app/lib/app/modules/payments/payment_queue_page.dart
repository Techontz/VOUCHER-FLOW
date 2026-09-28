import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// The payment queue — placeholder until the screen is built (owned by the payments work).
class PaymentQueuePage extends StatelessWidget {
  const PaymentQueuePage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.paymentQueue'.tr)],
  );
}
