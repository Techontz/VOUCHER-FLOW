import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/design.dart';

/// Decides where to land once the stored session has been checked.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();

    ever<bool>(session.booting, (booting) {
      if (!booting) {
        Get.offAllNamed(session.isSignedIn ? Routes.shell : Routes.login);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!session.booting.value) {
        Get.offAllNamed(session.isSignedIn ? Routes.shell : Routes.login);
      }
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VfLogo(size: 44, fontSize: 24),
            SizedBox(height: 28),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
