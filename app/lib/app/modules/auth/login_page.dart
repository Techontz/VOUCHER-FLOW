import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import 'auth_widgets.dart';
import 'login_brand.dart';

/// One seeded account per step of the default route, plus the two admin
/// scopes — the web's DEMO list. Offered only by the offline mock
/// ([VfConfig.useMock]); a live build never shows accounts or the password.
class DemoAccount {
  const DemoAccount(this.label, this.person, this.email, this.icon, this.note);
  final String label, person, email, note;
  final IconData icon;
}

class LoginController extends GetxController {
  final session = Get.find<SessionService>();

  final email = TextEditingController();
  final password = TextEditingController();
  final busy = false.obs;

  /// Signed in; the dashboard is opening.
  final done = false.obs;

  /// A message for the alert above the form (not tied to one field).
  final error = RxnString();
  final fieldErrors = <String, String>{}.obs;
  final obscure = true.obs;
  final remember = true.obs;

  static const demoPassword = 'Password123!';

  static const demoAccounts = [
    DemoAccount(
      'auth.demo.employee',
      'Frank Kessy',
      'frank@watercom.test',
      PhosphorIconsRegular.user,
      'auth.demo.employeeNote',
    ),
    DemoAccount(
      'auth.demo.hod',
      'Joseph Mrisho',
      'joseph@watercom.test',
      PhosphorIconsRegular.signature,
      'auth.demo.hodNote',
    ),
    DemoAccount(
      'auth.demo.md',
      'Emmanuel Massawe',
      'emmanuel@watercom.test',
      PhosphorIconsRegular.sealCheck,
      'auth.demo.mdNote',
    ),
    DemoAccount(
      'auth.demo.cashier',
      'Mwajuma Hamisi',
      'mwajuma@watercom.test',
      PhosphorIconsRegular.wallet,
      'auth.demo.cashierNote',
    ),
    DemoAccount(
      'auth.demo.admin',
      'Neema Shirima',
      'admin@watercom.test',
      PhosphorIconsRegular.buildings,
      'auth.demo.adminNote',
    ),
    DemoAccount(
      'auth.demo.super',
      'Grace Kimaro',
      'super@vouchflow.test',
      PhosphorIconsRegular.globeHemisphereEast,
      'auth.demo.superNote',
    ),
  ];

  /// The picked demo account, to mark it.
  final pickedDemo = RxnString();

  @override
  void onInit() {
    super.onInit();
    // A message handed back by the verification step, e.g. an expired sign-in.
    final handedBack = Get.arguments;
    if (handedBack is String && handedBack.isNotEmpty) {
      error.value = handedBack;
    }
    email.addListener(() {
      if (pickedDemo.value != null && pickedDemo.value != email.text) {
        pickedDemo.value = null;
      }
    });
  }

  void useDemo(String address) {
    if (!VfConfig.useMock) return;
    email.text = address;
    password.text = demoPassword;
    pickedDemo.value = address;
  }

  Future<void> submit() async {
    if (busy.value || done.value) return;
    busy.value = true;
    error.value = null;
    fieldErrors.clear();
    try {
      final challenge = await session.signIn(email.text.trim(), password.text);
      if (challenge == null) {
        done.value = true;
        Get.offAllNamed(Routes.shell);
      } else {
        // The password was right; the second step confirms it is the user.
        busy.value = false;
        Get.toNamed(Routes.verifyLogin, arguments: challenge);
      }
    } on ApiException catch (e) {
      final byField = {
        if (e.field('email') != null) 'email': e.field('email')!,
        if (e.field('password') != null) 'password': e.field('password')!,
      };
      if (byField.isEmpty) {
        error.value = e.message;
      } else {
        fieldErrors.assignAll(byField);
      }
      busy.value = false;
    } catch (_) {
      error.value = 'state.offline'.tr;
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

/// Sign in — the web's /login on a phone: hero, the form in a card, then the
/// product detail.
class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) =>
      LoginFrame(card: _LoginForm(controller: controller));
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.controller});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;

    return AutofillGroup(
      child: Obx(() {
        final emailError = c.fieldErrors['email'];
        final passwordError = c.fieldErrors['password'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'auth.welcome'.tr,
              style: VfType.pageTitle.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
                color: t.text,
              ),
            ),
            const SizedBox(height: 24),

            if (c.error.value != null) ...[
              VouchFlowAlert(
                message: c.error.value!,
                tone: VfTone.bad,
                icon: PhosphorIconsRegular.warningCircle,
              ),
              const SizedBox(height: 16),
            ],

            AuthInput(
              controller: c.email,
              placeholder: 'auth.emailAddress'.tr,
              icon: PhosphorIconsRegular.envelopeSimple,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              invalid: emailError != null,
              semanticLabel: 'auth.emailAddress'.tr,
            ),
            if (emailError != null) _FieldError(emailError),
            const SizedBox(height: 14),
            AuthInput(
              controller: c.password,
              placeholder: 'auth.password'.tr,
              icon: PhosphorIconsRegular.lockSimple,
              obscure: c.obscure.value,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => c.submit(),
              invalid: passwordError != null,
              semanticLabel: 'auth.password'.tr,
              suffix: RevealButton(
                revealed: !c.obscure.value,
                onTap: c.obscure.toggle,
              ),
            ),
            if (passwordError != null) _FieldError(passwordError),
            Align(
              alignment: Alignment.centerRight,
              child: AuthLink(
                'auth.forgot'.tr,
                size: 13.5,
                onTap: () => Get.toNamed(Routes.forgotPassword),
              ),
            ),
            const SizedBox(height: 14),

            VouchFlowButton(
              label: c.done.value
                  ? 'auth.signedInOpening'.tr
                  : c.busy.value
                  ? 'auth.signingIn'.tr
                  : 'auth.signIn'.tr,
              icon: c.done.value ? PhosphorIconsBold.check : null,
              loading: c.busy.value && !c.done.value,
              height: 56,
              expand: true,
              onPressed: c.busy.value ? null : c.submit,
            ),

            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'auth.newCompany'.tr,
                  style: VfType.body.copyWith(fontSize: 14, color: t.muted),
                ),
                const SizedBox(width: 4),
                AuthLink(
                  'auth.registerShort'.tr,
                  onTap: () => Get.toNamed(Routes.register),
                ),
              ],
            ),

            if (VfConfig.useMock) ...[
              const SizedBox(height: 26),
              _DemoAccounts(controller: c),
            ],
          ],
        );
      }),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              PhosphorIconsRegular.warningCircle,
              size: 15,
              color: t.dangerStrong,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: VfType.meta.copyWith(color: t.dangerStrong),
            ),
          ),
        ],
      ),
    );
  }
}

/// The demo sign-in panel — offline mock only, as the web shows it only
/// outside a live production build.
class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.controller});
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'auth.demoSignInAs'.tr.toUpperCase(),
            style: VfType.eyebrow.copyWith(fontSize: 12, color: t.muted),
          ),
          const SizedBox(height: 12),
          for (final a in LoginController.demoAccounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Obx(() {
                final on = controller.pickedDemo.value == a.email;
                return Material(
                  color: on ? t.primarySoft : t.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: on ? t.primary : t.border,
                      width: on ? 1.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => controller.useDemo(a.email),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: t.primarySoftStrong,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(a.icon, size: 16, color: t.primaryText),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: a.label.tr,
                                    children: [
                                      TextSpan(
                                        text: ' · ${a.person}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w400,
                                          color: t.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: VfType.bodyStrong.copyWith(
                                    fontSize: 14.5,
                                    color: t.text,
                                  ),
                                ),
                                Text(
                                  a.note.tr,
                                  style: VfType.meta.copyWith(color: t.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 6),
          Text('auth.demoNote'.tr, style: VfType.meta.copyWith(color: t.muted)),
        ],
      ),
    );
  }
}
