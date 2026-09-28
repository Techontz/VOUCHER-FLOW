import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/mock/mock_api.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import 'auth_widgets.dart';
import 'login_brand.dart';
import 'login_page.dart';

/// The second step of signing in (the web's LoginVerification): choose where
/// the code goes when the account has both an email address and a phone,
/// then enter it. Reached from [LoginController] with the [LoginChallenge]
/// as the argument; the challenge lives only here, never in storage.
class VerifyLoginController extends GetxController {
  VerifyLoginController([LoginChallenge? challenge])
    : challenge = challenge ?? Get.arguments as LoginChallenge;

  final session = Get.find<SessionService>();
  final LoginChallenge challenge;

  final code = TextEditingController();

  /// Failures after which the challenge is gone and only a fresh sign-in helps.
  static const _terminal = {
    'too_many_attempts': 'auth.2s.errTooManyAttempts',
    'challenge_expired': 'auth.2s.errExpired',
    'account_unavailable': 'auth.2s.errUnavailable',
    'too_many_sends': 'auth.2s.errTooManySends',
  };

  /// Recoverable failures, worded in the active language.
  static const _recoverable = {
    'invalid_code': 'auth.2s.errInvalid',
    'code_expired': 'auth.2s.errCodeExpired',
    'no_code': 'auth.2s.errNoCode',
    'resend_cooldown': 'auth.2s.errCooldown',
    'delivery_failed': 'auth.2s.errDelivery',
  };

  /// The channel the current code went to.
  final sentTo = RxnString();
  final destination = RxnString();

  /// On the choice between email and SMS.
  final choosing = false.obs;

  /// The channel picked on the choice step.
  final picked = 'email'.obs;

  /// How long the current code lasts, in minutes.
  final codeMinutes = RxnInt();

  final verifying = false.obs;
  final sending = false.obs;
  final error = RxnString();
  final notice = RxnString();

  /// The code as typed, so the Verify button follows it.
  final typed = ''.obs;

  /// Seconds before another code may be requested.
  final resendLeft = 0.obs;
  Timer? _ticker;

  bool get hasChoice => challenge.channels.length > 1;
  bool get busy => verifying.value || sending.value;

  @override
  void onInit() {
    super.onInit();
    sentTo.value = challenge.sentTo;
    destination.value = challenge.channelFor(challenge.sentTo)?.destination;
    choosing.value = challenge.sentTo == null;
    picked.value =
        challenge.sentTo ?? challenge.channels.firstOrNull?.channel ?? 'email';
    codeMinutes.value = _minutes(challenge.codeExpiresIn);
    _startCountdown(challenge.resendIn ?? 0);
    code.addListener(() => typed.value = code.text);
  }

  static int? _minutes(int? seconds) =>
      seconds == null || seconds <= 0 ? null : (seconds / 60).round();

  String channelLabel(String channel) =>
      channel == 'sms' ? 'auth.2s.viaSms'.tr : 'auth.2s.viaEmail'.tr;

  /// Sends (or re-sends) a code by [channel].
  Future<void> send(String channel, {bool resend = false}) async {
    if (sending.value) return;
    sending.value = true;
    error.value = null;
    notice.value = null;
    try {
      final result = await session.sendLoginCode(challenge.challenge, channel);
      sentTo.value = result.sentTo;
      destination.value = result.destination;
      codeMinutes.value = _minutes(result.codeExpiresIn);
      _startCountdown(result.resendIn ?? 0);
      code.clear();
      choosing.value = false;
      if (resend) notice.value = 'auth.2s.resent'.tr;
    } catch (e) {
      _handle(e);
    } finally {
      sending.value = false;
    }
  }

  Future<void> resend() async {
    final channel = sentTo.value;
    if (channel == null || resendLeft.value > 0 || busy) return;
    await send(channel, resend: true);
  }

  /// Back to the choice between email and SMS.
  void useDifferentMethod() {
    error.value = null;
    notice.value = null;
    code.clear();
    choosing.value = true;
  }

  /// The form's one action: send the code on the choice step, verify after.
  Future<void> submit() async {
    if (choosing.value) {
      await send(picked.value);
      return;
    }
    await verify();
  }

  Future<void> verify() async {
    if (busy) return;
    final value = code.text.trim();
    if (value.length < 6) return;

    verifying.value = true;
    error.value = null;
    notice.value = null;
    try {
      await session.verifyLogin(challenge.challenge, value);
      _ticker?.cancel();
      Get.offAllNamed(Routes.shell);
    } catch (e) {
      _handle(e);
      verifying.value = false;
    }
  }

  /// Turns an API failure into a message, or hands back to the password step.
  void _handle(Object e) {
    if (e is! ApiException) {
      error.value = 'state.offline'.tr;
      return;
    }
    final reason = e.reason;
    if (reason != null && _terminal.containsKey(reason)) {
      backToLogin(_terminal[reason]!.tr);
      return;
    }
    if (reason == 'resend_cooldown') {
      final retry = e.intValue('retry_after') ?? 0;
      if (retry > 0) _startCountdown(retry);
    }
    if (reason == 'no_code' && hasChoice) choosing.value = true;

    var message = reason != null && _recoverable.containsKey(reason)
        ? _recoverable[reason]!.tr
        : (e.field('channel') ?? e.message);
    if (reason == 'invalid_code') {
      final left = e.intValue('attempts_remaining');
      if (left != null && left > 0) {
        message +=
            ' ${left == 1 ? 'auth.2s.attemptLeft'.tr : 'auth.2s.attemptsLeft'.trParams({'n': '$left'})}';
      }
      code.clear();
    }
    error.value = message;
  }

  /// Leaves this step; the password must be entered again. [message] is shown
  /// on the sign-in page.
  void backToLogin([String? message]) {
    _ticker?.cancel();
    final text = message == null || message.isEmpty ? null : message;
    if (Get.isRegistered<LoginController>()) {
      final login = Get.find<LoginController>();
      login.error.value = text;
      login.password.clear();
      Get.until((route) => route.settings.name == Routes.login);
    } else {
      Get.offAllNamed(Routes.login, arguments: text);
    }
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    resendLeft.value = seconds;
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendLeft.value <= 1) {
        resendLeft.value = 0;
        timer.cancel();
      } else {
        resendLeft.value--;
      }
    });
  }

  @override
  void onClose() {
    _ticker?.cancel();
    code.dispose();
    super.onClose();
  }
}

class VerifyLoginPage extends GetView<VerifyLoginController> {
  const VerifyLoginPage({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !controller.verifying.value) controller.backToLogin();
    },
    child: LoginFrame(card: _VerifyCard(controller: controller)),
  );
}

class _VerifyCard extends StatelessWidget {
  const _VerifyCard({required this.controller});
  final VerifyLoginController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;

    return Obx(() {
      final choosing = c.choosing.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'auth.2s.title'.tr,
            style: VfType.pageTitle.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            choosing ? 'auth.2s.choose'.tr : 'auth.2s.sub'.tr,
            style: VfType.body.copyWith(color: t.muted),
          ),
          const SizedBox(height: 28),

          if (c.error.value != null) ...[
            VouchFlowAlert(
              message: c.error.value!,
              tone: VfTone.bad,
              icon: PhosphorIconsRegular.warningCircle,
            ),
            const SizedBox(height: 20),
          ] else if (c.notice.value != null) ...[
            VouchFlowAlert(
              message: c.notice.value!,
              tone: VfTone.ok,
              icon: PhosphorIconsRegular.checkCircle,
            ),
            const SizedBox(height: 20),
          ],

          if (choosing) ...[
            for (final option in c.challenge.channels)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChannelChoice(
                  icon: option.channel == 'sms'
                      ? PhosphorIconsRegular.deviceMobile
                      : PhosphorIconsRegular.envelopeSimple,
                  label: c.channelLabel(option.channel),
                  destination: option.destination,
                  selected: c.picked.value == option.channel,
                  onTap: c.sending.value
                      ? null
                      : () => c.picked.value = option.channel,
                ),
              ),
            const SizedBox(height: 10),
            VouchFlowButton(
              label: c.sending.value
                  ? 'auth.loading'.tr
                  : 'auth.2s.sendCode'.tr,
              trailingIcon: PhosphorIconsRegular.arrowRight,
              loading: c.sending.value,
              height: 48,
              expand: true,
              onPressed: c.busy ? null : c.submit,
            ),
          ] else ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${'auth.2s.sentTo'.tr} '),
                  TextSpan(
                    text:
                        c.destination.value ??
                        (c.sentTo.value == null
                            ? ''
                            : c.channelLabel(c.sentTo.value!)),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const TextSpan(text: '.'),
                  if (c.codeMinutes.value != null)
                    TextSpan(
                      text:
                          ' ${'auth.2s.validFor'.trParams({'n': '${c.codeMinutes.value}'})}',
                    ),
                ],
              ),
              style: VfType.body.copyWith(color: t.muted, height: 1.55),
            ),
            const SizedBox(height: 20),
            Text(
              'auth.2s.codeLabel'.tr,
              style: VfType.label.copyWith(
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
            const SizedBox(height: 8),
            OtpField(
              controller: c.code,
              enabled: !c.verifying.value,
              invalid: c.error.value != null,
              autofocus: true,
              onSubmitted: (_) => c.verify(),
              semanticLabel: 'auth.2s.codeLabel'.tr,
            ),
            const SizedBox(height: 20),
            VouchFlowButton(
              label: c.verifying.value
                  ? 'auth.2s.verifying'.tr
                  : 'auth.2s.verify'.tr,
              trailingIcon: PhosphorIconsRegular.arrowRight,
              loading: c.verifying.value,
              height: 48,
              expand: true,
              onPressed: c.busy || c.typed.value.length < 6 ? null : c.verify,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              spacing: 8,
              children: [
                VouchFlowButton(
                  label: c.resendLeft.value > 0
                      ? 'auth.2s.resendIn'.trParams({
                          'n': '${c.resendLeft.value}',
                        })
                      : 'auth.2s.resend'.tr,
                  icon: PhosphorIconsRegular.arrowClockwise,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed:
                      c.busy || c.resendLeft.value > 0 || c.sentTo.value == null
                      ? null
                      : c.resend,
                ),
                if (c.hasChoice)
                  VouchFlowButton(
                    label: 'auth.2s.otherMethod'.tr,
                    icon: PhosphorIconsRegular.swap,
                    variant: VfButtonVariant.ghost,
                    compact: true,
                    onPressed: c.busy ? null : c.useDifferentMethod,
                  ),
              ],
            ),
          ],

          if (VfConfig.useMock) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    PhosphorIconsRegular.info,
                    size: 14,
                    color: t.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'auth.2s.demoHint'.trParams({
                      'code': MockApi.mockLoginCode,
                    }),
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 22),
          Center(
            child: VouchFlowButton(
              label: 'auth.2s.back'.tr,
              icon: PhosphorIconsRegular.arrowLeft,
              variant: VfButtonVariant.ghost,
              compact: true,
              onPressed: c.verifying.value ? null : () => c.backToLogin(),
            ),
          ),
        ],
      );
    });
  }
}

/// One way to receive the code (the web's `.vf-choice`).
class _ChannelChoice extends StatelessWidget {
  const _ChannelChoice({
    required this.icon,
    required this.label,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label, destination;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? t.primarySoft : t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? t.primary : t.borderStrong,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? t.primarySoftStrong : t.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? t.primaryText : t.text2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: VfType.bodyStrong.copyWith(color: t.text),
                      ),
                      Text(
                        destination,
                        style: VfType.small.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? PhosphorIconsFill.checkCircle
                      : PhosphorIconsRegular.circle,
                  size: 22,
                  color: selected ? t.primary : t.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
