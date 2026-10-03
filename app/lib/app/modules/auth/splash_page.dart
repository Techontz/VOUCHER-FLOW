import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import 'auth_widgets.dart';

/// Decides where to land once the stored session has been checked.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _session = Get.find<SessionService>();
  Worker? _worker;
  bool _left = false;

  /// Public pages a development build may open straight away (screenshots).
  static const _publicPushes = {Routes.register, Routes.forgotPassword};

  @override
  void initState() {
    super.initState();
    _worker = ever<bool>(_session.booting, (booting) {
      if (!booting) _leave();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_session.booting.value) _leave();
    });
  }

  void _leave() {
    if (_left) return;
    _left = true;
    if (_session.isSignedIn) {
      Get.offAllNamed(Routes.shell);
      return;
    }
    final locale = DevHooks.locale;
    if (locale != null) _session.setLocale(locale, persist: false);
    Get.offAllNamed(Routes.login);
    final push = DevHooks.push;
    if (push != null && _publicPushes.contains(push)) Get.toNamed(push);
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Scaffold(
      backgroundColor: t.chrome,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.25),
            radius: .9,
            colors: [
              t.palette.primaryLight.withValues(alpha: .35),
              t.chrome,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: t.palette.primaryLight.withValues(alpha: .5),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const VfBrandMark(size: 84),
            ),
            const SizedBox(height: 20),
            Text(
              'app.name'.tr,
              style: VfType.pageTitle.copyWith(
                fontSize: 30,
                letterSpacing: -.8,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
