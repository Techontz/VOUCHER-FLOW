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
import '../dashboard/dash_bits.dart' show dashDateTime;
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

/// The profile as an app settings screen: who you are, then grouped rows
/// that open each form as its own page.
class ProfileTab extends GetView<ProfileController> {
  const ProfileTab({super.key});

  void _push(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VouchFlowPushedScaffold(title: title, body: body),
      ),
    );
  }

  void _openDetails(BuildContext context) => _push(
    context,
    'profile.tab.details'.tr,
    _DetailsPage(controller: controller),
  );

  Future<void> _pickLanguage(BuildContext context) async {
    final s = controller.session;
    final code = await showVouchFlowBottomSheet<String>(
      context,
      title: 'profile.language'.tr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Builder(
          builder: (ctx) {
            final t = ctx.vf;
            return AppListGroup(
              indent: 16,
              children: [
                for (final (c, label) in const [
                  ('en', 'English'),
                  ('sw', 'Kiswahili'),
                ])
                  ListTile(
                    title: Text(
                      label,
                      style: VfType.body.copyWith(color: t.text),
                    ),
                    trailing: s.locale.value == c
                        ? Icon(
                            PhosphorIconsBold.check,
                            size: 18,
                            color: t.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(c),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (code != null && code != s.locale.value) await s.setLocale(code);
  }

  Future<void> _signOut() async {
    await controller.session.signOut();
    unawaited(Get.offAllNamed(Routes.login));
  }

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
      final s = controller.session;
      final dark = s.themeMode.value == ThemeMode.dark;
      final locale = s.locale.value;
      final hasSig =
          controller.savedSignature.value != null || user.hasSignature;
      final sessions = controller.sessions.value;
      final line = [
        user.roleLabel,
        ?user.departmentName,
      ].where((x) => x.isNotEmpty).join(' · ');

      return VouchFlowPageBody(
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          12,
          VfSize.pagePad,
          32,
        ),
        onRefresh: () async {
          await controller.session.refresh();
          await controller.loadSessions();
        },
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // — who you are —
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(VfSize.radiusXl),
                      boxShadow: t.cardShadow,
                    ),
                    child: Material(
                      color: t.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(VfSize.radiusXl),
                        side: BorderSide(
                          color: t.isDark ? t.border : Colors.transparent,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openDetails(context),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                          child: Column(
                            children: [
                              VouchFlowAvatar(
                                initials: user.initials,
                                size: 80,
                                imageUrl: user.avatarUrl,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                user.name,
                                textAlign: TextAlign.center,
                                style: VfType.sectionTitle.copyWith(
                                  color: t.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (line.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  line,
                                  textAlign: TextAlign.center,
                                  style: VfType.small.copyWith(color: t.muted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // — account —
                  AppListGroup(
                    header: 'profile.group.account'.tr,
                    indent: 64,
                    children: [
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.user,
                        label: 'profile.tab.details'.tr,
                        tint: (t.primaryText, t.primarySoft),
                        onTap: () => _openDetails(context),
                      ),
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.signature,
                        label: 'profile.tab.signature'.tr,
                        tint: (t.successStrong, t.successSoft),
                        value: hasSig
                            ? 'profile.sigOn'.tr
                            : 'profile.sigOff'.tr,
                        onTap: () => _push(
                          context,
                          'profile.tab.signature'.tr,
                          _SignaturePage(controller: controller),
                        ),
                      ),
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.lockKey,
                        label: 'profile.tab.security'.tr,
                        tint: (t.warningStrong, t.warningSoft),
                        onTap: () => _push(
                          context,
                          'profile.tab.security'.tr,
                          _PasswordPage(controller: controller),
                        ),
                      ),
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.devices,
                        label: 'profile.activeSessions'.tr,
                        tint: (t.infoStrong, t.infoSoft),
                        value: sessions == null ? null : '${sessions.length}',
                        onTap: () => _push(
                          context,
                          'profile.activeSessions'.tr,
                          _SessionsPage(controller: controller),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // — preferences —
                  AppListGroup(
                    header: 'profile.group.preferences'.tr,
                    indent: 64,
                    children: [
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.translate,
                        label: 'profile.language'.tr,
                        tint: (t.primaryText, t.primarySoft),
                        value: locale == 'sw' ? 'Kiswahili' : 'English',
                        onTap: () => _pickLanguage(context),
                      ),
                      ProfileSettingsRow(
                        icon: dark
                            ? PhosphorIconsFill.moon
                            : PhosphorIconsFill.sun,
                        label: 'profile.darkMode'.tr,
                        tint: (t.text2, t.surface3),
                        chevron: false,
                        onTap: s.toggleTheme,
                        trailing: Switch.adaptive(
                          value: dark,
                          activeTrackColor: t.primary,
                          onChanged: (_) => s.toggleTheme(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // — sign out —
                  AppListGroup(
                    indent: 64,
                    children: [
                      ProfileSettingsRow(
                        icon: PhosphorIconsFill.signOut,
                        label: 'nav.signOut'.tr,
                        tint: (t.dangerStrong, t.dangerSoft),
                        danger: true,
                        onTap: _signOut,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/* ───────────────────────────────────────────────── pushed pages ── */

class _DetailsPage extends StatelessWidget {
  const _DetailsPage({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.vf;
    return Obx(() {
      final errors = c.profileErrors;
      final avatar = c.avatar.value;
      final user = c.session.user.value;
      return ProfilePageBody(
        children: [
          // The photo: tap to choose another.
          Center(
            child: Column(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: c.pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (avatar != null)
                        ClipOval(
                          child: Image.memory(
                            avatar.bytes,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const SizedBox(width: 88, height: 88),
                          ),
                        )
                      else
                        VouchFlowAvatar(
                          initials: user?.initials ?? '',
                          size: 88,
                          imageUrl: user?.avatarUrl,
                        ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: t.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.background, width: 3),
                          ),
                          child: const Icon(
                            PhosphorIconsFill.camera,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: c.pickAvatar,
                  child: Text(
                    'profile.choosePhoto'.tr,
                    style: VfType.label.copyWith(
                      color: t.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (errors['avatar'] != null)
                  Text(
                    errors['avatar']!,
                    textAlign: TextAlign.center,
                    style: VfType.meta.copyWith(color: t.dangerStrong),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ProfileFormCard(
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
                initialValue: user?.email ?? '',
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
            ],
          ),
          const SizedBox(height: 20),
          VouchFlowButton(
            label: 'profile.saveChanges'.tr,
            expand: true,
            loading: c.savingProfile.value,
            onPressed: c.saveProfile,
          ),
        ],
      );
    });
  }
}

class _SignaturePage extends StatelessWidget {
  const _SignaturePage({required this.controller});
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
            Material(
              color: t.surface2,
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              child: InkWell(
                borderRadius: BorderRadius.circular(VfSize.radiusL),
                onTap: c.pickSignatureImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                    border: Border.all(color: t.borderStrong),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        PhosphorIconsRegular.uploadSimple,
                        size: 24,
                        color: t.primaryText,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'profile.sig.choose'.tr,
                        style: VfType.label.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'profile.sig.formats'.tr,
                        style: VfType.meta.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
              ),
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
                  ),
                  child: Text(
                    'profile.sig.none'.tr,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ),
      };

      return ProfilePageBody(
        children: [
          ProfileFormCard(
            children: [
              ProfileSegmented<SignatureMode>(
                value: mode,
                onChanged: c.setMode,
                options: [
                  (
                    SignatureMode.draw,
                    'profile.sig.draw'.tr,
                    PhosphorIconsRegular.pencilSimple,
                    true,
                  ),
                  (
                    SignatureMode.upload,
                    'profile.sig.upload'.tr,
                    PhosphorIconsRegular.uploadSimple,
                    true,
                  ),
                  (
                    SignatureMode.saved,
                    'profile.sigOn'.tr,
                    PhosphorIconsRegular.checkCircle,
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
          const SizedBox(height: 20),
          VouchFlowButton(
            label: 'profile.save'.tr,
            expand: true,
            loading: c.savingSignature.value,
            onPressed: value == null ? null : c.storeSignature,
          ),
          if (saved != null) ...[
            const SizedBox(height: 10),
            VouchFlowButton(
              label: 'profile.remove'.tr,
              icon: PhosphorIconsRegular.trash,
              variant: VfButtonVariant.danger,
              expand: true,
              onPressed: c.removeSignature,
            ),
          ],
        ],
      );
    });
  }
}

class _PasswordPage extends StatelessWidget {
  const _PasswordPage({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final errors = c.passwordErrors;
      return ProfilePageBody(
        children: [
          AutofillGroup(
            child: ProfileFormCard(
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
          ),
          const SizedBox(height: 20),
          VouchFlowButton(
            label: 'profile.changePassword'.tr,
            expand: true,
            loading: c.changingPassword.value,
            onPressed: c.changePassword,
          ),
        ],
      );
    });
  }
}

class _SessionsPage extends StatelessWidget {
  const _SessionsPage({required this.controller});
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final sessions = c.sessions.value;
      return RefreshIndicator(
        onRefresh: c.loadSessions,
        child: ProfilePageBody(
          children: [
            if (sessions == null)
              const VouchFlowLoadingState(rows: 2, rowHeight: 56)
            else if (sessions.isEmpty)
              VouchFlowCard(
                radius: VfSize.radiusXl,
                padding: EdgeInsets.zero,
                child: VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.devices,
                  title: 'profile.noSessions'.tr,
                ),
              )
            else
              AppListGroup(
                indent: 66,
                children: [
                  for (final s in sessions)
                    SessionRow(session: s, onRevoke: () => c.revoke(s)),
                ],
              ),
            const SizedBox(height: 20),
            VouchFlowButton(
              label: 'profile.signOutEverywhere'.tr,
              icon: PhosphorIconsRegular.signOut,
              variant: VfButtonVariant.secondary,
              expand: true,
              loading: c.signingOutEverywhere.value,
              onPressed: c.signOutEverywhere,
            ),
          ],
        ),
      );
    });
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
