import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/profile_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/profile_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast, ToastKind, decodeSignature;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show DashPanel, dashDateTime;
import 'profile_bits.dart';
import 'signature_canvas.dart';

enum SignatureMode { draw, upload, saved }

/// The signed-in user's own page: personal details, signature, password and
/// sessions, appearance and language — the web's four profile tabs.
class ProfileController extends GetxController {
  final repo = ProfileRepository.to;
  final session = Get.find<SessionService>();

  final tab = 0.obs;

  // — personal details —
  final name = TextEditingController();
  final phone = TextEditingController();
  final jobTitle = TextEditingController();
  final avatar = Rxn<({Uint8List bytes, String filename})>();
  final savingProfile = false.obs;
  final profileErrors = <String, String>{}.obs;

  // — signature —
  final pad = SignatureCanvasController();
  final mode = SignatureMode.draw.obs;
  final signature = RxnString(); // the value Save would store
  final savedSignature = RxnString();
  final signatureUpdatedAt = Rxn<DateTime>();
  final savingSignature = false.obs;
  final signatureError = RxnString();

  // — password & sessions —
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  final changingPassword = false.obs;
  final passwordErrors = <String, String>{}.obs;
  final sessions = Rxn<List<ProfileSession>>();
  final signingOutEverywhere = false.obs;

  @override
  void onInit() {
    super.onInit();
    _fillDetails();
    loadSessions();
    _loadSignature();
  }

  @override
  void onClose() {
    for (final c in [
      name,
      phone,
      jobTitle,
      currentPassword,
      newPassword,
      confirmPassword,
    ]) {
      c.dispose();
    }
    pad.dispose();
    super.onClose();
  }

  void _fillDetails() {
    final user = session.user.value;
    if (user == null) return;
    name.text = user.name;
    phone.text = user.phone ?? '';
    jobTitle.text = user.jobTitle ?? '';
  }

  Future<void> loadSessions() async {
    try {
      sessions.value = await repo.sessions();
    } catch (_) {
      sessions.value = const [];
    }
  }

  Future<void> _loadSignature() async {
    if (session.user.value?.hasSignature != true) return;
    try {
      savedSignature.value = await repo.savedSignature();
      if (savedSignature.value != null) {
        mode.value = SignatureMode.saved;
        signature.value = savedSignature.value;
      }
      final me = await repo.me();
      signatureUpdatedAt.value = DateTime.tryParse(
        '${me['signature_updated_at'] ?? ''}',
      )?.toLocal();
    } catch (_) {
      // The pad still works; the saved copy is an offer, not a requirement.
    }
  }

  /* ─────────────────────────────────────────── personal details ── */

  Future<void> pickAvatar() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2048 * 1024) {
        profileErrors['avatar'] = 'profile.photoTooLarge'.tr;
        return;
      }
      profileErrors.remove('avatar');
      avatar.value = (bytes: bytes, filename: file.name);
    } catch (_) {
      // Picker cancelled or unavailable.
    }
  }

  Future<void> saveProfile() async {
    profileErrors.clear();
    if (name.text.trim().isEmpty) {
      profileErrors['name'] = 'profile.required'.tr;
      return;
    }
    savingProfile.value = true;
    try {
      await repo.updateProfile(
        name: name.text.trim(),
        phone: phone.text.trim(),
        jobTitle: jobTitle.text.trim(),
        avatar: avatar.value,
      );
      await session.refresh();
      avatar.value = null;
      _fillDetails();
      showToast('profile.updated'.tr);
    } on ApiException catch (e) {
      for (final key in ['name', 'phone', 'job_title', 'avatar']) {
        final message = e.field(key);
        if (message != null) profileErrors[key] = message;
      }
      showToast(
        'profile.updateFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'profile.updateFailed'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      savingProfile.value = false;
    }
  }

  /* ─────────────────────────────────────────────────── signature ── */

  void setMode(SignatureMode next) {
    if (next == SignatureMode.saved && savedSignature.value == null) return;
    mode.value = next;
    signatureError.value = null;
    switch (next) {
      case SignatureMode.saved:
        signature.value = savedSignature.value;
      case SignatureMode.draw:
        pad.clear();
        signature.value = null;
      case SignatureMode.upload:
        signature.value = null;
    }
  }

  /// A finished stroke: the drawing becomes the value to save.
  Future<void> commitDrawing() async {
    final png = await pad.toPng();
    signature.value = png == null
        ? null
        : 'data:image/png;base64,${base64Encode(png)}';
  }

  void clearDrawing() {
    pad.clear();
    signature.value = null;
  }

  Future<void> pickSignatureImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) {
        signature.value = null;
        return;
      }
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
          ? 'image/jpeg'
          : (file.mimeType ?? 'image/png');
      signatureError.value = null;
      signature.value = 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      // Picker cancelled or unavailable.
    }
  }

  Future<void> storeSignature() async {
    final value = signature.value;
    if (value == null) return;
    savingSignature.value = true;
    signatureError.value = null;
    try {
      final at = await repo.storeSignature(value);
      savedSignature.value = value;
      signatureUpdatedAt.value = at ?? DateTime.now();
      await session.refresh();
      showToast('profile.sig.savedToast'.tr, body: 'profile.sig.savedBody'.tr);
    } on ApiException catch (e) {
      signatureError.value = e.field('signature') ?? e.message;
      showToast(
        'profile.sig.saveFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'profile.sig.saveFailed'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      savingSignature.value = false;
    }
  }

  Future<void> removeSignature() async {
    try {
      await repo.removeSignature();
      savedSignature.value = null;
      signatureUpdatedAt.value = null;
      setMode(SignatureMode.draw);
      await session.refresh();
      showToast('profile.sig.removed'.tr, kind: ToastKind.warn);
    } on ApiException catch (e) {
      showToast(
        'profile.sig.removeFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'profile.sig.removeFailed'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    }
  }

  /* ─────────────────────────────────────────── password & sessions ── */

  Future<void> changePassword() async {
    passwordErrors.clear();
    if (currentPassword.text.isEmpty) {
      passwordErrors['current_password'] = 'profile.required'.tr;
    }
    if (newPassword.text.length < 8) {
      passwordErrors['password'] = 'profile.passwordShort'.tr;
    }
    if (confirmPassword.text.isEmpty) {
      passwordErrors['password_confirmation'] = 'profile.required'.tr;
    } else if (confirmPassword.text != newPassword.text) {
      passwordErrors['password_confirmation'] = 'profile.passwordMismatch'.tr;
    }
    if (passwordErrors.isNotEmpty) return;

    changingPassword.value = true;
    try {
      await repo.changePassword(
        current: currentPassword.text,
        password: newPassword.text,
        confirmation: confirmPassword.text,
      );
      currentPassword.clear();
      newPassword.clear();
      confirmPassword.clear();
      showToast('profile.passwordUpdated'.tr);
    } on ApiException catch (e) {
      for (final key in ['current_password', 'password']) {
        final message = e.field(key);
        if (message != null) passwordErrors[key] = message;
      }
      showToast(
        'profile.passwordFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'profile.passwordFailed'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      changingPassword.value = false;
    }
  }

  Future<void> revoke(ProfileSession s) async {
    try {
      await repo.revokeSession(s.id);
      await loadSessions();
      showToast('profile.sessionRevoked'.tr, kind: ToastKind.warn);
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    }
  }

  Future<void> signOutEverywhere() async {
    signingOutEverywhere.value = true;
    try {
      await repo.logoutAll();
      showToast('profile.signedOutEverywhere'.tr);
      await session.signOut();
      unawaited(Get.offAllNamed(Routes.login));
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      signingOutEverywhere.value = false;
    }
  }
}

class ProfileTab extends GetView<ProfileController> {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final user = controller.session.user.value;
      if (user == null) {
        return const VouchFlowPageBody(
          children: [VouchFlowLoadingState(rows: 4)],
        );
      }
      final t = context.vf;
      // Read here, not inside LayoutBuilder, so Obx tracks it.
      final tab = controller.tab.value;
      final line = [
        ?user.jobTitle,
        user.roleLabel,
        ?user.departmentName,
      ].where((s) => s.isNotEmpty).join(' · ');

      return LayoutBuilder(
        builder: (context, box) {
          final pad = box.maxWidth >= 700 ? 24.0 : VfSize.pagePad;
          return VouchFlowPageBody(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 32),
            onRefresh: () async {
              await controller.session.refresh();
              await controller.loadSessions();
            },
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          VouchFlowAvatar(
                            initials: user.initials,
                            size: 48,
                            imageUrl: user.avatarUrl,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: VfType.pageTitle.copyWith(
                                    color: t.text,
                                    fontSize: 24,
                                  ),
                                ),
                                if (line.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    line,
                                    style: VfType.small.copyWith(
                                      color: t.text2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      VouchFlowTabs(
                        labels: [
                          'profile.tab.details'.tr,
                          'profile.tab.signature'.tr,
                          'profile.tab.security'.tr,
                          'profile.tab.appearance'.tr,
                        ],
                        icons: const [
                          PhosphorIconsRegular.user,
                          PhosphorIconsRegular.signature,
                          PhosphorIconsRegular.lockKey,
                          PhosphorIconsRegular.palette,
                        ],
                        current: tab,
                        onChanged: (i) => controller.tab.value = i,
                      ),
                      const SizedBox(height: 20),
                      switch (tab) {
                        0 => _Details(
                          controller: controller,
                          email: user.email,
                        ),
                        1 => _Signature(controller: controller),
                        2 => _Security(controller: controller),
                        _ => _Appearance(controller: controller),
                      },
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.controller, required this.email});
  final ProfileController controller;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final errors = c.profileErrors;
      final avatar = c.avatar.value;
      return ProfilePanel(
        footer: ProfileFormFoot(
          end: VouchFlowButton(
            label: 'profile.saveChanges'.tr,
            loading: c.savingProfile.value,
            onPressed: c.saveProfile,
          ),
        ),
        child: ProfileFormSection(
          title: 'profile.details.title'.tr,
          description: 'profile.details.body'.tr,
          children: [
            VouchFlowTextField(
              label: 'profile.fullName'.tr,
              controller: c.name,
              required: true,
              error: errors['name'],
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
            ),
            VouchFlowTextField(
              label: 'profile.email'.tr,
              initialValue: email,
              readOnly: true,
              hint: 'profile.emailHint'.tr,
            ),
            ProfileFormRow(
              children: [
                VouchFlowTextField(
                  label: 'profile.phone'.tr,
                  controller: c.phone,
                  error: errors['phone'],
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                ),
                VouchFlowTextField(
                  label: 'profile.jobTitle'.tr,
                  controller: c.jobTitle,
                  error: errors['job_title'],
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
            VouchFlowField(
              label: 'profile.photo'.tr,
              error: errors['avatar'],
              child: ProfileFilePicker(
                buttonLabel: 'profile.choosePhoto'.tr,
                fileName: avatar?.filename ?? 'profile.noPhoto'.tr,
                preview: avatar?.bytes,
                onPick: c.pickAvatar,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Signature extends StatelessWidget {
  const _Signature({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.vf;
    return Obx(() {
      final saved = c.savedSignature.value;
      final mode = c.mode.value;
      final value = c.signature.value;
      final updated = c.signatureUpdatedAt.value;

      final Widget body = switch (mode) {
        SignatureMode.draw => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SignatureCanvas(
              controller: c.pad,
              onEnd: c.commitDrawing,
              semanticLabel: 'profile.sig.finger'.tr,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'profile.sig.finger'.tr,
                    style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
                  ),
                ),
                VouchFlowButton(
                  label: 'profile.sig.clear'.tr,
                  icon: PhosphorIconsRegular.eraser,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: c.clearDrawing,
                ),
              ],
            ),
          ],
        ),
        SignatureMode.upload => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileFilePicker(
              buttonLabel: 'profile.sig.choose'.tr,
              fileName: 'profile.sig.formats'.tr,
              onPick: c.pickSignatureImage,
            ),
            if (value != null) ...[
              const SizedBox(height: 12),
              SignaturePreview(dataUrl: value),
            ],
          ],
        ),
        SignatureMode.saved =>
          saved != null
              ? SignaturePreview(dataUrl: saved)
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'profile.sig.none'.tr,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ),
      };

      return ProfilePanel(
        footer: ProfileFormFoot(
          start: saved != null
              ? VouchFlowButton(
                  label: 'profile.remove'.tr,
                  icon: PhosphorIconsRegular.trash,
                  variant: VfButtonVariant.danger,
                  onPressed: c.removeSignature,
                )
              : null,
          end: VouchFlowButton(
            label: 'profile.save'.tr,
            loading: c.savingSignature.value,
            onPressed: value == null ? null : c.storeSignature,
          ),
        ),
        child: ProfileFormSection(
          title: 'profile.signature'.tr,
          description: 'profile.signatureBody'.tr,
          children: [
            ProfileSegmented<SignatureMode>(
              value: mode,
              onChanged: c.setMode,
              options: [
                (SignatureMode.draw, 'profile.sig.draw'.tr, null, true),
                (SignatureMode.upload, 'profile.sig.upload'.tr, null, true),
                (
                  SignatureMode.saved,
                  'profile.sig.saved'.tr,
                  null,
                  saved != null,
                ),
              ],
            ),
            body,
            if (c.signatureError.value != null)
              Text(
                c.signatureError.value!,
                style: VfType.meta.copyWith(color: t.dangerStrong),
              ),
            if (updated != null && saved != null)
              Text(
                'profile.sig.lastUpdated'.trParams({
                  'date': dashDateTime(updated),
                }),
                style: VfType.meta.copyWith(color: t.muted),
              ),
          ],
        ),
      );
    });
  }
}

class _Security extends StatelessWidget {
  const _Security({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.vf;
    return Obx(() {
      final errors = c.passwordErrors;
      final sessions = c.sessions.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutofillGroup(
            child: ProfilePanel(
              footer: ProfileFormFoot(
                end: VouchFlowButton(
                  label: 'profile.changePassword'.tr,
                  loading: c.changingPassword.value,
                  onPressed: c.changePassword,
                ),
              ),
              child: ProfileFormSection(
                title: 'profile.changePassword'.tr,
                description: 'profile.passwordBody'.tr,
                children: [
                  VouchFlowTextField(
                    label: 'profile.currentPassword'.tr,
                    controller: c.currentPassword,
                    obscure: true,
                    required: true,
                    error: errors['current_password'],
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                  ),
                  ProfileFormRow(
                    children: [
                      VouchFlowTextField(
                        label: 'profile.newPassword'.tr,
                        controller: c.newPassword,
                        obscure: true,
                        required: true,
                        error: errors['password'],
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                      ),
                      VouchFlowTextField(
                        label: 'profile.confirmPassword'.tr,
                        controller: c.confirmPassword,
                        obscure: true,
                        required: true,
                        error: errors['password_confirmation'],
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => c.changePassword(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DashPanel(
            title: 'profile.activeSessions'.tr,
            below: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VouchFlowButton(
                  label: 'profile.signOutEverywhere'.tr,
                  icon: PhosphorIconsRegular.signOut,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  loading: c.signingOutEverywhere.value,
                  onPressed: c.signOutEverywhere,
                ),
              ),
            ),
            child: sessions == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: VouchFlowLoadingState(rows: 2, rowHeight: 48),
                  )
                : sessions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'profile.noSessions'.tr,
                      style: VfType.small.copyWith(color: t.muted),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < sessions.length; i++)
                        SessionRow(
                          session: sessions[i],
                          last: i == sessions.length - 1,
                          onRevoke: () => c.revoke(sessions[i]),
                        ),
                    ],
                  ),
          ),
        ],
      );
    });
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    return Obx(
      () => ProfilePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileFormSection(
              title: 'profile.appearance'.tr,
              description: 'profile.appearanceBody'.tr,
              children: [
                ProfileSegmented<ThemeMode>(
                  value: s.themeMode.value,
                  onChanged: (m) {
                    if (m != s.themeMode.value) s.toggleTheme();
                  },
                  options: [
                    (
                      ThemeMode.light,
                      'profile.light'.tr,
                      PhosphorIconsRegular.sun,
                      true,
                    ),
                    (
                      ThemeMode.dark,
                      'profile.dark'.tr,
                      PhosphorIconsRegular.moon,
                      true,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            ProfileFormSection(
              title: 'profile.language'.tr,
              description: 'profile.languageBody'.tr,
              children: [
                ProfileSegmented<String>(
                  value: s.locale.value,
                  onChanged: (code) {
                    if (code != s.locale.value) s.setLocale(code);
                  },
                  options: const [
                    ('en', 'English', null, true),
                    ('sw', 'Kiswahili', null, true),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved or uploaded signature on white, as it prints.
class SignaturePreview extends StatelessWidget {
  const SignaturePreview({super.key, required this.dataUrl});
  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeSignature(dataUrl);
    return Container(
      height: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: context.vf.border),
      ),
      child: bytes == null
          ? const SizedBox.shrink()
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );
  }
}
