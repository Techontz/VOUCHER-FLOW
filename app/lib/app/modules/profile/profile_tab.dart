import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';
import '../branding/branding_page.dart';
import '../../widgets/signature_pad.dart';

class ProfileController extends GetxController {
  final session = Get.find<SessionService>();
  final repo = Get.find<VoucherRepository>();

  final savedSignature = RxnString();
  final busy = false.obs;

  @override
  void onInit() {
    super.onInit();
    if (session.me.hasSignature) {
      repo
          .savedSignature()
          .then((v) => savedSignature.value = v)
          .catchError((_) => null);
    }
  }

  Future<void> captureSignature(BuildContext context) async {
    final pad = SignaturePadController();

    await showVfSheet<void>(
      context,
      builder: (sheetContext) => SheetScaffold(
        title: 'profile.mySignature'.tr,
        subtitle: 'profile.signatureHint'.tr,
        children: [
          AnimatedBuilder(
            animation: pad,
            builder: (_, _) => SignaturePad(controller: pad, height: 170),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(sheetContext);
              final png = await pad.toPng();
              navigator.pop();
              if (png == null) return;

              busy.value = true;
              try {
                final encoded = VoucherRepository.encodeSignature(png);
                await repo.storeSignature(encoded);
                savedSignature.value = encoded;
                await session.refresh();
                showToast('msg.saved'.tr, body: 'profile.signature'.tr);
              } on ApiException catch (e) {
                showToast(
                  'state.error'.tr,
                  body: e.message,
                  kind: ToastKind.bad,
                );
              } finally {
                busy.value = false;
              }
            },
            child: Text('action.save'.tr),
          ),
        ],
      ),
    );

    pad.dispose();
  }

  Future<void> changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();

    await showVfSheet<void>(
      context,
      builder: (sheetContext) => SheetScaffold(
        title: 'profile.changePassword'.tr,
        children: [
          FieldLabel('profile.currentPassword'.tr),
          TextField(controller: current, obscureText: true),
          const SizedBox(height: 14),
          FieldLabel('profile.newPassword'.tr),
          TextField(controller: next, obscureText: true),
          const SizedBox(height: 14),
          FieldLabel('profile.confirmPassword'.tr),
          TextField(controller: confirm, obscureText: true),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(sheetContext);
              final values = (current.text, next.text, confirm.text);
              navigator.pop();
              try {
                await repo.changePassword(values.$1, values.$2, values.$3);
                showToast('msg.saved'.tr, body: 'profile.changePassword'.tr);
              } on ApiException catch (e) {
                showToast(
                  'state.error'.tr,
                  body: e.message,
                  kind: ToastKind.bad,
                );
              }
            },
            child: Text('action.save'.tr),
          ),
        ],
      ),
    );

    current.dispose();
    next.dispose();
    confirm.dispose();
  }
}

class ProfileTab extends GetView<ProfileController> {
  const ProfileTab({super.key});

  Future<void> _chooseLanguage(BuildContext context) async {
    final session = controller.session;
    await showVfSheet<void>(
      context,
      builder: (sheetContext) => SheetScaffold(
        title: 'profile.language'.tr,
        children: [
          for (final option in const [('en', 'English'), ('sw', 'Kiswahili')])
            _OptionRow(
              label: option.$2,
              selected: session.locale.value == option.$1,
              onTap: () {
                Navigator.of(sheetContext).pop();
                session.setLocale(option.$1);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.session;

    return Obx(() {
      final user = session.user.value;
      if (user == null) return const SizedBox.shrink();
      final company = session.company.value;
      final signature = decodeSignature(controller.savedSignature.value);
      final dark = session.themeMode.value == ThemeMode.dark;

      return ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ScreenTitle(title: 'profile.title'.tr),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    InitialsAvatar(initials: user.initials, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            [
                              user.roleLabel,
                              user.departmentName,
                            ].whereType<String>().join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(user.email, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),

                if (company != null) ...[
                  const SizedBox(height: 18),
                  SectionCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    onTap: canEditBranding(user)
                        ? () => Get.toNamed(Routes.branding)
                        : null,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: VfColors.accent500,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            company.name
                                .split(RegExp(r'\s+'))
                                .where((w) => RegExp('^[A-Za-z]').hasMatch(w))
                                .take(2)
                                .map((w) => w[0].toUpperCase())
                                .join(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: VfColors.onAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                company.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                [
                                  company.plan?.name,
                                  company.status,
                                  if (company.daysRemaining != null)
                                    'profile.daysLeft'.trParams({
                                      'n': '${company.daysRemaining}',
                                    }),
                                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        ToneBadge(
                          label: company.isUsable
                              ? 'profile.active'.tr
                              : 'state.expired'.tr,
                          tone: company.isUsable ? VfTone.ok : VfTone.bad,
                          icon: company.isUsable
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          dense: true,
                        ),
                        if (canEditBranding(user)) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: context.vfMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                SectionCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.draw_outlined,
                            size: 19,
                            color: context.vfInk2,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'profile.mySignature'.tr,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                controller.captureSignature(context),
                            child: Text(
                              signature == null
                                  ? 'profile.draw'.tr
                                  : 'profile.redraw'.tr,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: signature != null
                            ? Container(
                                height: 76,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: SignaturePad.paper,
                                  borderRadius: BorderRadius.circular(
                                    VfTheme.rMd,
                                  ),
                                ),
                                child: Image.memory(
                                  signature,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              )
                            : Text(
                                'profile.noSignature'.tr,
                                style: theme.textTheme.bodySmall,
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.translate,
                        label: 'profile.language'.tr,
                        value: session.locale.value == 'sw'
                            ? 'Kiswahili'
                            : 'English',
                        onTap: () => _chooseLanguage(context),
                      ),
                      _SettingRow(
                        icon: dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        label: 'profile.theme'.tr,
                        value: dark
                            ? 'profile.themeDark'.tr
                            : 'profile.themeLight'.tr,
                        onTap: session.toggleTheme,
                        divider: true,
                      ),
                      if (company != null && canEditBranding(user))
                        _SettingRow(
                          icon: Icons.palette_outlined,
                          label: 'branding.title'.tr,
                          onTap: () => Get.toNamed(Routes.branding),
                          divider: true,
                        ),
                      _SettingRow(
                        icon: Icons.lock_outline,
                        label: 'profile.changePassword'.tr,
                        onTap: () => controller.changePassword(context),
                        divider: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: context.vfBad,
                    ),
                    onPressed: () async {
                      await session.signOut();
                      Get.offAllNamed(Routes.login);
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text('action.signOut'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.divider = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: divider
              ? Border(top: BorderSide(color: context.vfLine))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: context.vfInk2),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            if (value != null)
              Text(value!, style: theme.textTheme.bodySmall),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: context.vfMuted),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(VfTheme.rMd),
    child: Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 20, color: context.vfAccent),
        ],
      ),
    ),
  );
}
