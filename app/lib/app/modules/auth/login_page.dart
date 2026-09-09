import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';

class LoginController extends GetxController {
  final session = Get.find<SessionService>();

  final email = TextEditingController();
  final password = TextEditingController();
  final busy = false.obs;
  final error = RxnString();
  final obscure = true.obs;

  /// One account per step of the default route, plus the administrator.
  /// One account per step of the default route, plus the administrator.
  static const demoAccounts = [
    ('Employee · Frank', 'frank@watercom.test', 'raises vouchers, sees only their own'),
    ('HOD · Joseph', 'joseph@watercom.test', 'reviews and signs — never approves'),
    ('MD · Emmanuel', 'emmanuel@watercom.test', 'approves or rejects — the final say'),
    ('Cashier · Mwajuma', 'mwajuma@watercom.test', 'releases the funds, records the reference'),
    ('Administrator · Neema', 'admin@watercom.test', 'runs Watercom (T) Limited'),
  ];


  void useDemo(String address) {
    email.text = address;
    password.text = 'Password123!';
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      error.value = 'Enter your email and password.';
      return;
    }

    busy.value = true;
    error.value = null;
    try {
      await session.signIn(email.text.trim(), password.text);
      Get.offAllNamed(Routes.shell);
    } on ApiException catch (e) {
      error.value = e.field('email') ?? e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    email.dispose();
    password.dispose();
    super.onClose();
  }
}

class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = Get.find<SessionService>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'VouchFlow',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Obx(
                        () => SegmentedButton<String>(
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'sw', label: Text('SW')),
                          ],
                          selected: {session.locale.value},
                          onSelectionChanged: (s) => session.setLocale(s.first),
                          showSelectedIcon: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('auth.subtitle'.tr, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 28),

                  Obx(
                    () => controller.error.value == null
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: VfColors.bad,
                              border: Border.all(
                                color: VfColors.bad.withValues(alpha: .5),
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 18,
                                  color: VfColors.bad,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    controller.error.value!,
                                    style: const TextStyle(
                                      color: VfColors.bad,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  TextField(
                    controller: controller.email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: 'auth.email'.tr),
                  ),
                  const SizedBox(height: 14),
                  Obx(
                    () => TextField(
                      controller: controller.password,
                      obscureText: controller.obscure.value,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => controller.submit(),
                      decoration: InputDecoration(
                        labelText: 'auth.password'.tr,
                        suffixIcon: IconButton(
                          icon: Icon(
                            controller.obscure.value
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => controller.obscure.toggle(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Obx(
                    () => FilledButton(
                      onPressed: controller.busy.value
                          ? null
                          : controller.submit,
                      child: controller.busy.value
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: VfTheme.onPrimary(context),
                              ),
                            )
                          : Text('action.signIn'.tr),
                    ),
                  ),

                  const SizedBox(height: 30),
                  Text(
                    'auth.demo'.tr.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 8),
                  ...LoginController.demoAccounts.map(
                    (account) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: () => controller.useDemo(account.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.$1,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                '${account.$2} · ${account.$3}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Password for every demo account: Password123!  ·  This prototype runs on local demo data.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
