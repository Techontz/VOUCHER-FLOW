import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/services/session_service.dart';
import '../../routes/routes.dart';

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

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VouchFlow',
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
