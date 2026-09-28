import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'auth_widgets.dart';
import 'onboarding_page.dart';

/// What a code confirms: a new administrator's email, or a password reset.
enum CodePurpose { registration, passwordReset }

/// The web's /verify: confirm a registration with the six-digit code, or
/// reset a password with one (`?purpose=password_reset`).
///
/// Arriving from registration the code has already been sent, so the address
/// is filled in and the button offers to resend it. Once confirmed the new
/// administrator continues to onboarding when [toOnboarding] is set.
class AccountCodePage extends StatefulWidget {
  const AccountCodePage({
    super.key,
    required this.purpose,
    this.identifier,
    this.toOnboarding = false,
  });

  final CodePurpose purpose;
  final String? identifier;
  final bool toOnboarding;

  @override
  State<AccountCodePage> createState() => _AccountCodePageState();
}

class _AccountCodePageState extends State<AccountCodePage> {
  final _repo = AuthRepository.to;
  late final _identifier = TextEditingController(text: widget.identifier ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool get _isReset => widget.purpose == CodePurpose.passwordReset;
  String get _purposeKey => _isReset ? 'password_reset' : 'registration';

  bool _busy = false;
  late bool _sent = !_isReset && (widget.identifier ?? '').isNotEmpty;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _identifier.addListener(_refresh);
    _code.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The web's reportError: the message, and the first field's detail.
  void _report(Object err, String fallback) {
    if (err is ApiException) {
      final first = err.errors.values.firstOrNull?.firstOrNull;
      showToast(
        err.message.isEmpty ? fallback : err.message,
        body: first != null && first != err.message ? first : null,
        kind: ToastKind.bad,
      );
    } else {
      showToast(fallback, body: 'state.offline'.tr, kind: ToastKind.bad);
    }
  }

  Future<void> _sendCode() async {
    final id = _identifier.text.trim();
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (_isReset) {
        await _repo.forgotPassword(id);
      } else {
        await _repo.sendOtp(id, _purposeKey);
      }
      if (!mounted) return;
      setState(() => _sent = true);
      showToast('auth.v.codeSent'.tr, body: 'auth.v.codeSentBody'.tr);
    } catch (e) {
      _report(e, 'auth.v.sendFailed'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _code.text.length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final id = _identifier.text.trim();
    try {
      if (_isReset) {
        await _repo.resetPassword(
          email: id,
          code: _code.text,
          password: _password.text,
          confirmation: _confirm.text,
        );
        showToast(
          'auth.v.passwordUpdated'.tr,
          body: 'auth.v.passwordUpdatedBody'.tr,
        );
        Get.offAllNamed(Routes.login);
        return;
      }
      await _repo.verifyOtp(id, _code.text, _purposeKey);
      showToast('auth.v.verified'.tr, body: 'auth.v.verifiedBody'.tr);
      if (widget.toOnboarding) {
        Get.offAll(() => const OnboardingPage());
      } else {
        Get.offAllNamed(Routes.shell);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _error;
    final general = e != null && e.errors.isEmpty ? e.message : null;

    return AuthFrame(
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).maybePop()
          : null,
      kicker: _isReset ? 'auth.forgot'.tr : 'auth.v.verifyNumber'.tr,
      title: _isReset ? 'auth.v.changePassword'.tr : 'auth.v.verifyNumber'.tr,
      sub: _isReset ? 'auth.v.resetSub'.tr : 'auth.v.verifySub'.tr,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (general != null) ...[
              VouchFlowAlert(
                message: general,
                tone: VfTone.bad,
                icon: PhosphorIconsRegular.warningCircle,
              ),
              const SizedBox(height: 16),
            ],
            VouchFlowField(
              label: 'auth.v.email'.tr,
              required: true,
              error: e?.field('email') ?? e?.field('identifier'),
              child: Row(
                children: [
                  Expanded(
                    child: AuthInput(
                      controller: _identifier,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      invalid:
                          (e?.field('email') ?? e?.field('identifier')) != null,
                      semanticLabel: 'auth.v.email'.tr,
                    ),
                  ),
                  const SizedBox(width: 8),
                  VouchFlowButton(
                    label: _sent
                        ? 'auth.v.resendCode'.tr
                        : 'auth.v.sendCode'.tr,
                    variant: VfButtonVariant.secondary,
                    height: VfSize.inputH,
                    onPressed: _busy || _identifier.text.trim().isEmpty
                        ? null
                        : _sendCode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            VouchFlowField(
              label: 'auth.v.code'.tr,
              error: e?.field('code'),
              child: OtpField(
                controller: _code,
                invalid: e?.field('code') != null,
                autofocus: !_isReset && (widget.identifier ?? '').isNotEmpty,
                onSubmitted: (_) => _isReset ? null : _submit(),
                semanticLabel: 'auth.v.code'.tr,
              ),
            ),
            if (_isReset) ...[
              const SizedBox(height: 16),
              VouchFlowTextField(
                label: 'auth.v.newPassword'.tr,
                required: true,
                controller: _password,
                obscure: true,
                error: e?.field('password'),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              VouchFlowTextField(
                label: 'auth.v.confirmPassword'.tr,
                required: true,
                controller: _confirm,
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 20),
            VouchFlowButton(
              label: _busy ? 'auth.loading'.tr : 'auth.v.continue'.tr,
              icon: PhosphorIconsRegular.checkCircle,
              loading: _busy,
              expand: true,
              height: 48,
              onPressed: _busy || _code.text.length < 6 ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
