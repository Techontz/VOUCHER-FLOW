import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/design.dart';

class LoginController extends GetxController {
  final session = Get.find<SessionService>();

  final email = TextEditingController();
  final password = TextEditingController();
  final busy = false.obs;
  final error = RxnString();
  final obscure = true.obs;

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
      error.value = 'auth.missing'.tr;
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const VfLogo(),
                      const Spacer(),
                      Obx(
                        () => VfSegmented<String>(
                          compact: true,
                          value: session.locale.value,
                          options: const [
                            ('en', 'EN', null),
                            ('sw', 'SW', null),
                          ],
                          onChanged: session.setLocale,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Text('auth.welcome'.tr, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 6),
                  Text(
                    'auth.workspace'.tr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.vfMuted,
                    ),
                  ),
                  const SizedBox(height: 28),

                  Obx(
                    () => controller.error.value == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: NoticeBanner(
                              icon: Icons.error_outline,
                              tone: VfTone.bad,
                              title: 'auth.failed'.tr,
                              body: controller.error.value!,
                            ),
                          ),
                  ),

                  FieldLabel('auth.email'.tr),
                  TextField(
                    controller: controller.email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  FieldLabel('auth.password'.tr),
                  Obx(
                    () => TextField(
                      controller: controller.password,
                      obscureText: controller.obscure.value,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => controller.submit(),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: 'auth.showPassword'.tr,
                          icon: Icon(
                            controller.obscure.value
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => controller.obscure.toggle(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Obx(
                    () => FilledButton(
                      // While signing in the button keeps its colour and
                      // shows progress, rather than looking disabled.
                      style: FilledButton.styleFrom(
                        disabledBackgroundColor: VfColors.accent500,
                        disabledForegroundColor: VfColors.onAccent,
                      ),
                      onPressed: controller.busy.value
                          ? null
                          : controller.submit,
                      child: controller.busy.value
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: VfColors.onAccent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('auth.signingIn'.tr),
                              ],
                            )
                          : Text('action.signIn'.tr),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'auth.staffNote'.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),

                  const SizedBox(height: 36),
                  Text(
                    'auth.demo'.tr.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 10),
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < LoginController.demoAccounts.length;
                            i++)
                          InkWell(
                            onTap: () => controller.useDemo(
                              LoginController.demoAccounts[i].$2,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                border: i == 0
                                    ? null
                                    : Border(
                                        top: BorderSide(color: context.vfLine),
                                      ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          LoginController.demoAccounts[i].$1,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          LoginController.demoAccounts[i].$3,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.north_west,
                                    size: 16,
                                    color: context.vfMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Password for every demo account: Password123!'
                    '${VfConfig.useMock ? '  ·  Running on local demo data.' : ''}',
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
