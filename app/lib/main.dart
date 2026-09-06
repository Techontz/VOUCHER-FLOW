import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/core/theme.dart';
import 'app/core/translations.dart';
import 'app/data/services/api_service.dart';
import 'app/data/services/session_service.dart';
import 'app/data/services/voucher_repository.dart';
import 'app/modules/auth/login_page.dart';
import 'app/modules/auth/splash_page.dart';
import 'app/modules/dashboard/dashboard_tab.dart';
import 'app/modules/notifications/notifications_tab.dart';
import 'app/modules/profile/profile_tab.dart';
import 'app/modules/shell/shell_page.dart';
import 'app/modules/vouchers/create_voucher_page.dart';
import 'app/modules/vouchers/voucher_detail_page.dart';
import 'app/routes/routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Services are permanent: one API client, one session, resolved everywhere.
  final api = await Get.putAsync(() => ApiService().init(), permanent: true);
  Get.put(VoucherRepository(api), permanent: true);
  final session = await Get.putAsync(
    () => SessionService(api).init(),
    permanent: true,
  );

  runApp(VouchFlowApp(session: session));
}

class VouchFlowApp extends StatelessWidget {
  const VouchFlowApp({super.key, required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'VouchFlow',
      debugShowCheckedModeBanner: false,
      theme: VfTheme.light(),
      darkTheme: VfTheme.dark(),
      themeMode: session.themeMode.value,
      translations: VfTranslations(),
      locale: Locale(session.locale.value),
      fallbackLocale: const Locale('en'),
      initialRoute: Routes.splash,
      defaultTransition: Transition.cupertino,
      getPages: [
        GetPage(name: Routes.splash, page: () => const SplashPage()),
        GetPage(
          name: Routes.login,
          page: () => const LoginPage(),
          binding: BindingsBuilder(() => Get.lazyPut(LoginController.new)),
        ),
        GetPage(
          name: Routes.shell,
          page: () => const ShellPage(),
          binding: BindingsBuilder(() {
            Get.put(ShellController());
            Get.lazyPut(DashboardController.new);
            Get.lazyPut(NotificationsController.new);
            Get.lazyPut(ProfileController.new);
          }),
        ),
        GetPage(name: Routes.voucher, page: () => const VoucherDetailPage()),
        GetPage(
          name: Routes.createVoucher,
          page: () => const CreateVoucherPage(),
          binding: BindingsBuilder(
            () => Get.lazyPut(CreateVoucherController.new),
          ),
        ),
      ],
    );
  }
}
