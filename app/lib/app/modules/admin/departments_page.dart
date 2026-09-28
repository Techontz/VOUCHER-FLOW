import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/vf/vf.dart';

/// Departments — placeholder until the screen is built (owned by the admin work).
class DepartmentsPage extends StatelessWidget {
  const DepartmentsPage({super.key});

  @override
  Widget build(BuildContext context) => VouchFlowPageBody(
    children: [VouchFlowPageHeader(title: 'nav.departments'.tr)],
  );
}
