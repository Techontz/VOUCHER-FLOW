import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/mock/mock_api.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import 'login_page.dart';

/// The second step of signing in: a 6-digit code sent by email or SMS.
/// Reached from [LoginController] with the [LoginChallenge] as the argument.
class VerifyLoginController extends GetxController {
  VerifyLoginController([LoginChallenge? challenge])
    : challenge = challenge ?? Get.arguments as LoginChallenge;

  final session = Get.find<SessionService>();
  final LoginChallenge challenge;

  final code = TextEditingController();

  /// The channel the current code went to; null while the user chooses.
  final sentTo = RxnString();
  final destination = ''.obs;

  /// The channel picked on the choice step, before a code is sent.
  final picked = RxnString();

  final verifying = false.obs;
  final sending = false.obs;
  final error = RxnString();
  final notice = RxnString();

  /// Seconds before another code may be requested.
  final resendLeft = 0.obs;
  Timer? _ticker;

  bool get hasChoice => challenge.channels.length > 1;
  bool get busy => verifying.value || sending.value;

  @override
  void onInit() {
    super.onInit();
    picked.value = challenge.channels.firstOrNull?.channel;

    final already = challenge.sentTo;
    if (already != null) {
      sentTo.value = already;
      destination.value = challenge.channelFor(already)?.destination ?? '';
      _startCountdown(challenge.resendIn ?? 0);
    } else if (!hasChoice && challenge.channels.isNotEmpty) {
      // One way to reach the user and nothing sent yet: send it now.
      unawaited(send(challenge.channels.first.channel));
    }
  }

  /// Sends (or re-sends) a code by [channel].
  Future<void> send(String channel) async {
    if (sending.value) return;
    sending.value = true;
    error.value = null;
    notice.value = null;
    final resending = sentTo.value == channel;
    try {
      final result = await session.sendLoginCode(challenge.challenge, channel);
      sentTo.value = result.sentTo;
      destination.value = result.destination;
      code.clear();
      _startCountdown(result.resendIn ?? 0);
      if (resending) {
        notice.value = 'verify.resent'.trParams({
          'destination': result.destination,
        });
      }
    } on ApiException catch (e) {
      _handle(e);
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      sending.value = false;
    }
  }

  Future<void> resend() async {
    final channel = sentTo.value;
    if (channel == null || resendLeft.value > 0) return;
    await send(channel);
  }

  /// Back to the choice between email and SMS.
  void useDifferentMethod() {
    picked.value = challenge.channels
        .where((c) => c.channel != sentTo.value)
        .firstOrNull
        ?.channel;
    sentTo.value = null;
    code.clear();
    error.value = null;
    notice.value = null;
  }

  Future<void> verify() async {
    if (busy) return;
    final value = code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      error.value = 'verify.error.enterCode'.tr;
      return;
    }

    verifying.value = true;
    error.value = null;
    notice.value = null;
    try {
      await session.verifyLogin(challenge.challenge, value);
      _ticker?.cancel();
      Get.offAllNamed(Routes.shell);
    } on ApiException catch (e) {
      _handle(e);
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      verifying.value = false;
    }
  }

  /// Turns the API's `reason` into a message in the user's language, falling
  /// back to the server's own wording for anything unrecognised.
  void _handle(ApiException e) {
    switch (e.reason) {
      case 'invalid_code':
        final left = e.intValue('attempts_remaining');
        error.value = left == null
            ? 'verify.error.invalidPlain'.tr
            : left == 1
            ? 'verify.error.invalidLast'.tr
            : 'verify.error.invalid'.trParams({'count': '$left'});
        code.clear();
      case 'code_expired':
        error.value = 'verify.error.codeExpired'.tr;
        code.clear();
        resendLeft.value = 0;
        _ticker?.cancel();
      case 'no_code':
        error.value = 'verify.error.noCode'.tr;
        sentTo.value = null;
      case 'resend_cooldown':
        final wait = e.intValue('retry_after') ?? 30;
        _startCountdown(wait);
        error.value = 'verify.error.cooldown'.trParams({'seconds': '$wait'});
      case 'delivery_failed':
        error.value = 'verify.error.deliveryFailed'.tr;
      case 'too_many_attempts':
        backToLogin('verify.error.tooManyAttempts'.tr);
      case 'challenge_expired':
        backToLogin('verify.error.challengeExpired'.tr);
      case 'account_unavailable':
        backToLogin('verify.error.accountUnavailable'.tr);
      case 'too_many_sends':
        backToLogin('verify.error.tooManySends'.tr);
      default:
        error.value = e.field('code') ?? e.field('channel') ?? e.message;
    }
  }

  /// Leaves this step; the password must be entered again. [message] is shown
  /// on the sign-in page.
  void backToLogin([String? message]) {
    _ticker?.cancel();
    if (Get.isRegistered<LoginController>()) {
      final login = Get.find<LoginController>();
      login.error.value = message;
      login.password.clear();
      Get.until((route) => route.settings.name == Routes.login);
    } else {
      Get.offAllNamed(Routes.login, arguments: message);
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = Get.find<SessionService>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.backToLogin();
      },
      child: Scaffold(
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
                            onSelectionChanged: (s) =>
                                session.setLocale(s.first),
                            showSelectedIcon: false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('verify.title'.tr, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 28),

                    Obx(
                      () => controller.error.value == null
                          ? const SizedBox.shrink()
                          : _Banner(
                              message: controller.error.value!,
                              color: VfColors.bad,
                              icon: Icons.error_outline,
                            ),
                    ),
                    Obx(
                      () => controller.notice.value == null
                          ? const SizedBox.shrink()
                          : _Banner(
                              message: controller.notice.value!,
                              color: VfColors.ok,
                              icon: Icons.check_circle_outline,
                            ),
                    ),

                    Obx(
                      () => controller.sentTo.value == null
                          ? _ChooseChannel(controller: controller)
                          : _EnterCode(controller: controller),
                    ),

                    const SizedBox(height: 18),
                    Obx(
                      () => TextButton(
                        onPressed: controller.verifying.value
                            ? null
                            : () => controller.backToLogin(),
                        child: Text('verify.backToLogin'.tr),
                      ),
                    ),
                    if (VfConfig.useMock) ...[
                      const SizedBox(height: 8),
                      Text(
                        'verify.demoCode'.trParams({
                          'code': MockApi.mockLoginCode,
                        }),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The step before a code exists: pick email or SMS.
class _ChooseChannel extends StatelessWidget {
  const _ChooseChannel({required this.controller});

  final VerifyLoginController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('verify.choose'.tr, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          ...controller.challenge.channels.map((option) {
            final selected = controller.picked.value == option.channel;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: controller.sending.value
                    ? null
                    : () => controller.picked.value = option.channel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? VfColors.accent : theme.dividerColor,
                      width: selected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option.channel == 'sms'
                            ? Icons.sms_outlined
                            : Icons.mail_outline,
                        size: 20,
                        color: selected ? VfColors.accent : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.channel == 'sms'
                                  ? 'verify.bySms'.tr
                                  : 'verify.byEmail'.tr,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              option.destination,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected ? VfColors.accent : theme.hintColor,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                controller.sending.value || controller.picked.value == null
                ? null
                : () => controller.send(controller.picked.value!),
            child: controller.sending.value
                ? _Spinner(color: VfTheme.onPrimary(context))
                : Text('verify.sendCode'.tr),
          ),
        ],
      ),
    );
  }
}

/// The code field, Verify, resend and the switch to the other channel.
class _EnterCode extends StatelessWidget {
  const _EnterCode({required this.controller});

  final VerifyLoginController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'verify.sentTo'.trParams({
              'destination': controller.destination.value,
            }),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text('verify.expiresNote'.tr, style: theme.textTheme.bodySmall),
          const SizedBox(height: 18),
          TextField(
            controller: controller.code,
            autofocus: true,
            enabled: !controller.verifying.value,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              letterSpacing: 10,
              fontWeight: FontWeight.w600,
            ),
            onSubmitted: (_) => controller.verify(),
            decoration: InputDecoration(labelText: 'verify.code'.tr),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: controller.busy ? null : controller.verify,
            child: controller.verifying.value
                ? _Spinner(color: VfTheme.onPrimary(context))
                : Text('verify.submit'.tr),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: controller.busy || controller.resendLeft.value > 0
                    ? null
                    : controller.resend,
                child: controller.sending.value
                    ? const _Spinner()
                    : Text(
                        controller.resendLeft.value > 0
                            ? 'verify.resendIn'.trParams({
                                'seconds': '${controller.resendLeft.value}',
                              })
                            : 'verify.resend'.tr,
                      ),
              ),
              if (controller.hasChoice)
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : controller.useDifferentMethod,
                  child: Text('verify.otherMethod'.tr),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

/// The login page's message box, in [color].
class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      border: Border.all(color: color.withValues(alpha: .5)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 13.5)),
        ),
      ],
    ),
  );
}
