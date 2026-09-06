import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'profile.signature'.tr,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: pad,
              builder: (_, _) => SignaturePad(controller: pad),
            ),
            const SizedBox(height: 12),
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
      ),
    );

    pad.dispose();
  }

  Future<void> changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'profile.changePassword'.tr,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: current,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'profile.currentPassword'.tr,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: next,
              obscureText: true,
              decoration: InputDecoration(labelText: 'profile.newPassword'.tr),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'profile.confirmPassword'.tr,
              ),
            ),
            const SizedBox(height: 16),
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
      ),
    );

    current.dispose();
    next.dispose();
    confirm.dispose();
  }
}

class ProfileTab extends GetView<ProfileController> {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.session;

    return Obx(() {
      final user = session.user.value;
      if (user == null) return const SizedBox.shrink();
      final company = session.company.value;

      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: VfColors.accent200,
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: VfColors.accent800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.titleLarge),
                    Text(user.roleLabel, style: theme.textTheme.bodySmall),
                    Text(user.email, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (company != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(company.name, style: theme.textTheme.titleSmall),
                        Text(
                          '${company.plan?.name ?? ''} · ${company.status}'
                          '${company.daysRemaining != null ? ' · ${company.daysRemaining} days left' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    label: company.status,
                    tag: company.isUsable ? 'tag-accent' : 'tag-accent-2',
                    dense: true,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 26),
          Text(
            'profile.signature'.tr.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          if (controller.savedSignature.value != null)
            Container(
              height: 96,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: theme.dividerColor),
              ),
              child: Image.memory(
                _decode(controller.savedSignature.value!),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            )
          else
            Text('No saved signature yet.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => controller.captureSignature(context),
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: Text(
              controller.savedSignature.value == null
                  ? 'profile.signature'.tr
                  : 'action.save'.tr,
            ),
          ),

          const SizedBox(height: 26),
          Text(
            'profile.language'.tr.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'sw', label: Text('Kiswahili')),
            ],
            selected: {session.locale.value},
            onSelectionChanged: (s) => session.setLocale(s.first),
            showSelectedIcon: false,
          ),

          const SizedBox(height: 22),
          Text(
            'profile.theme'.tr.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: session.themeMode.value == ThemeMode.dark,
            onChanged: (_) => session.toggleTheme(),
            contentPadding: EdgeInsets.zero,
            title: Text(
              session.themeMode.value == ThemeMode.dark
                  ? 'profile.themeDark'.tr
                  : 'profile.themeLight'.tr,
            ),
          ),

          const SizedBox(height: 14),
          Text(
            'profile.security'.tr.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => controller.changePassword(context),
            icon: const Icon(Icons.lock_outline, size: 18),
            label: Text('profile.changePassword'.tr),
          ),

          const SizedBox(height: 26),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: VfColors.accent2700,
              side: const BorderSide(color: VfColors.accent2500),
            ),
            onPressed: () async {
              await session.signOut();
              Get.offAllNamed(Routes.login);
            },
            icon: const Icon(Icons.logout, size: 18),
            label: Text('action.signOut'.tr),
          ),
        ],
      );
    });
  }
}

Uint8List _decode(String dataUrl) {
  final index = dataUrl.indexOf(',');
  return base64Decode(index == -1 ? dataUrl : dataUrl.substring(index + 1));
}
