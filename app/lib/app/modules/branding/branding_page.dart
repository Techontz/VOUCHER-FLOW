import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart';

/// The artwork slots the API accepts on POST /company/logo.
enum LogoSlot { logo, logoMark }

extension on LogoSlot {
  String get field => this == LogoSlot.logo ? 'logo' : 'logo_mark';
}

/// A company administrator's own identity: details, logos, the interface
/// colour, the letterhead's small print and the account bank vouchers are
/// drawn on. The same fields, and the same endpoints, as the web's branding
/// page: text to PUT /company, each logo to POST /company/logo.
class BrandingController extends GetxController {
  final session = Get.find<SessionService>();
  final _api = Get.find<ApiService>();

  final name = TextEditingController();
  final legalName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final website = TextEditingController();
  final tin = TextEditingController();
  final footer = TextEditingController();
  final bankName = TextEditingController();
  final bankBranch = TextEditingController();
  final bankAccountName = TextEditingController();
  final bankAccountNumber = TextEditingController();

  final colorTheme = 'blue'.obs;
  final busy = false.obs;
  final fieldErrors = <String, String>{}.obs;

  /// New artwork waiting for save, and artwork marked for removal.
  final picked = <LogoSlot, File>{}.obs;
  final removed = <LogoSlot>{}.obs;

  /// The logo currently on the server, for display.
  String? serverUrl(LogoSlot slot) {
    final company = session.company.value;
    return slot == LogoSlot.logo ? company?.logoUrl : company?.logoMarkUrl;
  }

  @override
  void onInit() {
    super.onInit();
    final c = session.company.value;
    if (c == null) return;
    name.text = c.name;
    legalName.text = c.legalName ?? '';
    email.text = c.email;
    phone.text = c.phone ?? '';
    address.text = c.address ?? '';
    website.text = c.website ?? '';
    tin.text = c.tin ?? '';
    footer.text = c.voucherFooterText ?? '';
    bankName.text = c.bankName ?? '';
    bankBranch.text = c.bankBranch ?? '';
    bankAccountName.text = c.bankAccountName ?? '';
    bankAccountNumber.text = c.bankAccountNumber ?? '';
    colorTheme.value = c.colorTheme;
  }

  /// Previews a colour across the app; it becomes the company's on save.
  void chooseColour(String key) {
    colorTheme.value = key;
    session.applyAccent(key, persist: false);
  }

  Future<void> pickLogo(LogoSlot slot) async {
    // Downscaled and re-encoded as JPEG on the device, which keeps the file
    // inside the API's 2 MB and 4000 px limits and turns HEIC into JPEG.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (file == null) return;

    final size = await File(file.path).length();
    if (size > 2 * 1024 * 1024) {
      showToast(
        'branding.logoTooLarge'.tr,
        body: 'branding.logoRules'.tr,
        kind: ToastKind.warn,
      );
      return;
    }
    picked[slot] = File(file.path);
    removed.remove(slot);
  }

  void removeLogo(LogoSlot slot) {
    picked.remove(slot);
    removed.add(slot);
  }

  Future<void> save() async {
    busy.value = true;
    fieldErrors.clear();
    try {
      await _api.put('/company', {
        'name': name.text.trim(),
        'legal_name': legalName.text.trim(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'website': website.text.trim(),
        'tin': tin.text.trim(),
        'color_theme': colorTheme.value,
        'voucher_footer_text': footer.text.trim(),
        'bank_name': bankName.text.trim(),
        'bank_branch': bankBranch.text.trim(),
        'bank_account_name': bankAccountName.text.trim(),
        'bank_account_number': bankAccountNumber.text.trim(),
      });

      for (final slot in LogoSlot.values) {
        final file = picked[slot];
        if (file != null) {
          await _api.upload(
            '/company/logo',
            [await http.MultipartFile.fromPath('logo', file.path)],
            fields: {'slot': slot.field},
          );
        } else if (removed.contains(slot)) {
          await _api.delete('/company/logo?slot=${slot.field}');
        }
      }

      picked.clear();
      removed.clear();
      await session.refresh();
      showToast('msg.saved'.tr, body: 'branding.savedBody'.tr);
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.errors.map((k, v) => MapEntry(k, v.first)));
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    // Leaving without saving puts the company's own colour back.
    session.applyAccent(session.company.value?.colorTheme, persist: false);
    for (final c in [
      name,
      legalName,
      email,
      phone,
      address,
      website,
      tin,
      footer,
      bankName,
      bankBranch,
      bankAccountName,
      bankAccountNumber,
    ]) {
      c.dispose();
    }
    super.onClose();
  }
}

class BrandingPage extends GetView<BrandingController> {
  const BrandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget field(
      String key,
      TextEditingController c,
      String label, {
      TextInputType? type,
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Obx(
        () => TextField(
          controller: c,
          keyboardType: type,
          minLines: lines,
          maxLines: lines,
          textInputAction: lines > 1
              ? TextInputAction.newline
              : TextInputAction.next,
          decoration: InputDecoration(
            labelText: label,
            errorText: controller.fieldErrors[key],
          ),
        ),
      ),
    );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(text.toUpperCase(), style: theme.textTheme.labelSmall),
    );

    return Scaffold(
      appBar: AppBar(title: Text('branding.title'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Text('branding.intro'.tr, style: theme.textTheme.bodySmall),

          label('branding.colour'.tr),
          Text('branding.colourHint'.tr, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Obx(
            () => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final palette in VfAccentPalette.all)
                  _ColourOption(
                    palette: palette,
                    label: 'branding.colour.${palette.key}'.tr,
                    selected: controller.colorTheme.value == palette.key,
                    onTap: () => controller.chooseColour(palette.key),
                  ),
              ],
            ),
          ),

          label('branding.logos'.tr),
          Obx(
            () => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _LogoTile(
                    title: 'branding.logo'.tr,
                    hint: 'branding.logoHint'.tr,
                    file: controller.picked[LogoSlot.logo],
                    url: controller.removed.contains(LogoSlot.logo)
                        ? null
                        : controller.serverUrl(LogoSlot.logo),
                    onPick: () => controller.pickLogo(LogoSlot.logo),
                    onRemove: () => controller.removeLogo(LogoSlot.logo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LogoTile(
                    title: 'branding.mark'.tr,
                    hint: 'branding.markHint'.tr,
                    file: controller.picked[LogoSlot.logoMark],
                    url: controller.removed.contains(LogoSlot.logoMark)
                        ? null
                        : controller.serverUrl(LogoSlot.logoMark),
                    onPick: () => controller.pickLogo(LogoSlot.logoMark),
                    onRemove: () => controller.removeLogo(LogoSlot.logoMark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('branding.logoRules'.tr, style: theme.textTheme.bodySmall),

          label('branding.details'.tr),
          field('name', controller.name, 'branding.name'.tr),
          field('legal_name', controller.legalName, 'branding.legalName'.tr),
          field(
            'email',
            controller.email,
            'branding.email'.tr,
            type: TextInputType.emailAddress,
          ),
          field(
            'phone',
            controller.phone,
            'branding.phone'.tr,
            type: TextInputType.phone,
          ),
          field('address', controller.address, 'branding.address'.tr, lines: 2),
          field(
            'website',
            controller.website,
            'branding.website'.tr,
            type: TextInputType.url,
          ),
          field('tin', controller.tin, 'branding.tin'.tr),
          field(
            'voucher_footer_text',
            controller.footer,
            'branding.footer'.tr,
            lines: 3,
          ),

          label('branding.bank'.tr),
          field('bank_name', controller.bankName, 'branding.bankName'.tr),
          field('bank_branch', controller.bankBranch, 'branding.bankBranch'.tr),
          field(
            'bank_account_name',
            controller.bankAccountName,
            'branding.accountName'.tr,
          ),
          field(
            'bank_account_number',
            controller.bankAccountNumber,
            'branding.accountNumber'.tr,
            type: TextInputType.number,
          ),
          VfNote('branding.cashNote'.tr),

          const SizedBox(height: 22),
          Obx(
            () => FilledButton(
              onPressed: controller.busy.value ? null : controller.save,
              child: controller.busy.value
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VfTheme.onPrimary(context),
                      ),
                    )
                  : Text('action.save'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColourOption extends StatelessWidget {
  const _ColourOption({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final VfAccentPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfTheme.rMd),
        child: Container(
          width: 150,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.vfAccentTint : context.vfElev1,
            border: Border.all(
              color: selected ? palette.solid : context.vfLine,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(VfTheme.rMd),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: palette.solid,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 15,
                        color: VfColors.accentInk,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.title,
    required this.hint,
    required this.file,
    required this.url,
    required this.onPick,
    required this.onRemove,
  });

  final String title, hint;
  final File? file;
  final String? url;
  final VoidCallback onPick, onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = file != null || url != null;

    // Paper-white in both appearances: a logo is artwork for the printed
    // page, and a dark logo on a dark well would disappear.
    final Widget preview = file != null
        ? Image.file(file!, fit: BoxFit.contain)
        : url != null
        ? Image.network(
            url!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: VfDoc.faint),
          )
        : const Icon(Icons.image_outlined, color: VfDoc.faint);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Container(
          height: 76,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VfDoc.paper,
            border: Border.all(color: context.vfLine),
            borderRadius: BorderRadius.circular(VfTheme.rMd),
          ),
          child: Center(child: preview),
        ),
        const SizedBox(height: 6),
        Text(hint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: onPick,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          child: Text(has ? 'branding.replace'.tr : 'branding.upload'.tr),
        ),
        if (has)
          TextButton(onPressed: onRemove, child: Text('action.remove'.tr)),
      ],
    );
  }
}

/// Whether this person may edit the company's branding. The API enforces the
/// same rule; this only decides whether the entry point is shown.
bool canEditBranding(AppUser user) => user.role == 'company_admin';
