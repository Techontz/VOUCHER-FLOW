import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';

/// What an app not yet built for the phone shows: its icon, that it works
/// on the web today, and nothing that pretends otherwise.
class ErpWebOnlyPage extends StatelessWidget {
  const ErpWebOnlyPage({super.key, required this.area});

  final String area;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final name = 'area.$area'.tr;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VfAppIcon(app: area, size: 84),
              const SizedBox(height: 22),
              Text(
                'apps.webOnlyTitle'.trParams({'app': name}),
                textAlign: TextAlign.center,
                style: VfType.sectionTitle.copyWith(color: t.text, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'apps.webOnlyBody'.trParams({'app': name}),
                textAlign: TextAlign.center,
                style: VfType.body.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
