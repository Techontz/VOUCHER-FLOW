import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/template_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../admin/admin_widgets.dart';
import 'voucher_template_panel.dart';

/// The artwork slots the API accepts on POST /company/logo.
enum LogoSlot { logo, logoMark }

extension on LogoSlot {
  String get field => this == LogoSlot.logo ? 'logo' : 'logo_mark';
}

/// A logo chosen on the device, waiting for save.
class PickedLogo {
  const PickedLogo(this.name, this.bytes, this.mime);
  final String name;
  final Uint8List bytes;
  final String mime;

  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// A company administrator's own identity — the web's Branding page: the
/// voucher design, letterhead details, logo and square mark, the document
/// colour, footer text, the interface palette and the bank account bank
/// vouchers are drawn on, with a live specimen in the chosen design. Text
/// goes to PUT /company, each logo to POST /company/logo.
class BrandingController extends GetxController {
  SessionService get session => Get.find<SessionService>();
  ApiService get _api => Get.find<ApiService>();
  AdminRepository get _repo => AdminRepository.to;

  final name = TextEditingController();
  final legalName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final website = TextEditingController();
  final tin = TextEditingController();
  final primaryColor = TextEditingController(text: '#2E3192');
  final footer = TextEditingController();
  final bankName = TextEditingController();
  final bankBranch = TextEditingController();
  final bankAccountName = TextEditingController();
  final bankAccountNumber = TextEditingController();

  final colorTheme = 'blue'.obs;
  final busy = false.obs;
  final fieldErrors = <String, String>{}.obs;

  /// The design the company prints in, and the secondary colour the
  /// letterhead uses — read from GET /company.
  final currentTemplate = 'classic'.obs;
  String? _secondaryColor;

  /// New artwork waiting for save, and artwork marked for removal.
  final picked = <LogoSlot, PickedLogo>{}.obs;
  final removed = <LogoSlot>{}.obs;

  /// The sample voucher in every design, in the letterhead as typed so far.
  final previews = <String, String>{}.obs;
  final previewsLoading = false.obs;
  final previewsFailed = false.obs;
  String? _placeholder;
  Timer? _debounce;
  String? _lastBody;

  List<TextEditingController> get _previewed => [
    name,
    legalName,
    address,
    phone,
    email,
    website,
    tin,
    footer,
    primaryColor,
  ];

  /// The logo currently on the server, for display.
  String? serverUrl(LogoSlot slot) {
    final company = session.company.value;
    return slot == LogoSlot.logo ? company?.logoUrl : company?.logoMarkUrl;
  }

  /// What the page shows for a slot: the picked image, nothing (removed), or
  /// the server's.
  String? shownUrl(LogoSlot slot) {
    if (picked[slot] != null) return picked[slot]!.dataUrl;
    if (removed.contains(slot)) return null;
    return serverUrl(slot);
  }

  @override
  void onInit() {
    super.onInit();
    for (final c in _previewed) {
      c.addListener(_schedulePreview);
    }
    _seedFromSession();
  }

  void _seedFromSession() {
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

  /// Re-reads the saved company, dropping unsaved edits — called when the
  /// page opens, as the web re-seeds its form from the company.
  Future<void> seed() async {
    picked.clear();
    removed.clear();
    fieldErrors.clear();
    _seedFromSession();
    try {
      final c = await _repo.company();
      _applyProfile(c);
    } catch (_) {
      // The session's copy stands in (the offline mock serves no /company
      // extras); the preview reports itself unavailable if it cannot load.
    }
    _schedulePreview(immediate: true);
  }

  void _applyProfile(CompanyProfile c) {
    name.text = c.name;
    legalName.text = c.legalName ?? '';
    email.text = c.email;
    phone.text = c.phone ?? '';
    address.text = c.address ?? '';
    website.text = c.website ?? '';
    tin.text = c.tin ?? '';
    primaryColor.text = c.primaryColor ?? '#2E3192';
    footer.text = c.voucherFooterText ?? '';
    bankName.text = c.bankName ?? '';
    bankBranch.text = c.bankBranch ?? '';
    bankAccountName.text = c.bankAccountName ?? '';
    bankAccountNumber.text = c.bankAccountNumber ?? '';
    colorTheme.value = c.colorTheme;
    currentTemplate.value = c.voucherTemplate;
    _secondaryColor = c.secondaryColor;
    session.applyAccent(c.colorTheme, persist: false);
  }

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// The logo the preview should print, if any: the picked image or the
  /// server's (the web's `form.logo_url`).
  String? get logoSrc => shownUrl(LogoSlot.logo);

  /// Swapped into every preview: the server prints a placeholder where a
  /// logo it does not hold belongs.
  Map<String, String> get replacements {
    final src = logoSrc;
    if (src == null || _placeholder == null) return const {};
    return {_placeholder!: src.replaceAll('"', '&quot;')};
  }

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      Duration(milliseconds: immediate ? 0 : 350),
      _fetchPreviews,
    );
  }

  Future<void> _fetchPreviews() async {
    final locale = Get.locale?.languageCode ?? 'en';
    final colour = primaryColor.text.trim();
    final body = <String, dynamic>{
      'name': _v(legalName) ?? _v(name),
      'address': _v(address),
      'phone': _v(phone),
      'email': _v(email),
      'website': _v(website),
      'tin': _v(tin),
      'voucher_footer_text': _v(footer),
      'primary_color': _hex.hasMatch(colour) ? colour : null,
      'secondary_color': _secondaryColor,
      'locale': locale,
      'with_logo': logoSrc != null,
    };
    final key = jsonEncode(body);
    if (key == _lastBody && previews.isNotEmpty) return;
    _lastBody = key;
    previewsLoading.value = true;
    try {
      final r = TemplatePreviews.fromJson(
        await _api.post('/voucher-templates/preview', body),
      );
      if (key != _lastBody) return;
      _placeholder = r.logoPlaceholder;
      previews.assignAll(r.html);
      previewsFailed.value = false;
    } catch (_) {
      if (key == _lastBody) previewsFailed.value = true;
    } finally {
      if (key == _lastBody) previewsLoading.value = false;
    }
  }

  /// Previews a palette across the app; it becomes the company's on save.
  void chooseColour(String key) {
    colorTheme.value = key;
    session.applyAccent(key, persist: false);
  }

  /// Puts the company's own palette back (leaving without saving).
  void revertPreview() =>
      session.applyAccent(session.company.value?.colorTheme, persist: false);

  Future<void> pickLogo(LogoSlot slot) async {
    // Downscaled on the device, which keeps the file inside the API's 2 MB
    // and 4000 px limits.
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
    } catch (_) {
      return;
    }
    if (file == null) return;
    final lower = file.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
        ? 'image/jpeg'
        : (file.mimeType ?? '');
    if (!const ['image/png', 'image/jpeg', 'image/webp'].contains(mime)) {
      showToast(
        'admin.logoLockup'.tr,
        body: 'branding.logoType'.tr,
        kind: ToastKind.warn,
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      showToast(
        'admin.logoLockup'.tr,
        body: 'branding.logoTooLarge'.tr,
        kind: ToastKind.warn,
      );
      return;
    }
    picked[slot] = PickedLogo(file.name, bytes, mime);
    removed.remove(slot);
    if (slot == LogoSlot.logo) _schedulePreview();
  }

  void removeLogo(LogoSlot slot) {
    picked.remove(slot);
    removed.add(slot);
    if (slot == LogoSlot.logo) _schedulePreview();
  }

  Future<void> save() async {
    busy.value = true;
    fieldErrors.clear();
    try {
      // Details, colours and bank account in one request; artwork after it,
      // one file per request, through the validated upload route.
      await _api.put('/company', {
        'name': name.text,
        'legal_name': legalName.text,
        'email': email.text,
        'phone': phone.text,
        'address': address.text,
        'website': website.text,
        'tin': tin.text,
        'primary_color': primaryColor.text.trim(),
        'color_theme': colorTheme.value,
        'voucher_footer_text': footer.text,
        'bank_name': bankName.text,
        'bank_account_name': bankAccountName.text,
        'bank_account_number': bankAccountNumber.text,
        'bank_branch': bankBranch.text,
      });

      for (final slot in LogoSlot.values) {
        final file = picked[slot];
        if (file != null) {
          await _api.upload(
            '/company/logo',
            [
              http.MultipartFile.fromBytes(
                'logo',
                file.bytes,
                filename: file.name,
              ),
            ],
            fields: {'slot': slot.field},
          );
        } else if (removed.contains(slot)) {
          await _api.delete('/company/logo?slot=${slot.field}');
        }
      }

      await session.refresh();
      showToast('branding.saved'.tr, body: 'branding.savedBody'.tr);
      await seed();
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.errors.map((k, v) => MapEntry(k, v.first)));
      adminReport(e, 'branding.couldNotSave'.tr);
    } catch (e) {
      adminReport(e, 'branding.couldNotSave'.tr);
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    revertPreview();
    for (final c in [
      name,
      legalName,
      email,
      phone,
      address,
      website,
      tin,
      primaryColor,
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

/// The Branding page. Inside the shell it is a body; opened on its own (the
/// profile's shortcut) it brings its own top bar.
class BrandingPage extends StatefulWidget {
  const BrandingPage({super.key});

  @override
  State<BrandingPage> createState() => _BrandingPageState();
}

class _BrandingPageState extends State<BrandingPage> {
  late final BrandingController c = Get.isRegistered<BrandingController>()
      ? Get.find<BrandingController>()
      : Get.put(BrandingController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.seed());
  }

  @override
  void dispose() {
    // Leaving without saving puts the company's own palette back — after
    // this frame, since the palette rebuilds the whole app.
    Future.microtask(c.revertPreview);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.settings.name == Routes.branding;
    final body = _BrandingBody(controller: c, pushed: pushed);
    if (!pushed) return body;
    return VouchFlowPushedScaffold(title: 'admin.branding'.tr, body: body);
  }
}

class _BrandingBody extends StatelessWidget {
  const _BrandingBody({required this.controller, required this.pushed});

  final BrandingController controller;

  /// Opened on its own, under an app bar that already names the page.
  final bool pushed;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.vf;
    const gap = SizedBox(height: 22);

    Widget field(
      String key,
      TextEditingController ctl,
      String label, {
      TextInputType? type,
      int lines = 1,
      bool required = false,
      IconData? icon,
    }) => Obx(
      () => VouchFlowTextField(
        label: label,
        controller: ctl,
        keyboardType: type ?? (lines > 1 ? TextInputType.multiline : null),
        minLines: lines > 1 ? lines : null,
        maxLines: lines > 1 ? lines + 2 : 1,
        required: required,
        prefixIcon: icon,
        error: c.fieldErrors[key],
        textInputAction: lines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
      ),
    );

    final saveBar = AdminSaveBar(
      child: Obx(
        () => VouchFlowButton(
          label: 'admin.saveChanges'.tr,
          icon: PhosphorIconsRegular.floppyDisk,
          loading: c.busy.value,
          expand: true,
          onPressed: c.busy.value ? null : c.save,
        ),
      ),
    );

    return AdminPageBody(
      route: '/branding',
      showNav: !pushed,
      showTitle: !pushed,
      title: 'admin.branding'.tr,
      onRefresh: c.seed,
      bottomBar: saveBar,
      children: [
        Obx(() {
          final role = c.session.user.value?.role;
          return VoucherTemplatePanel(
            mode: 'company',
            canManage: role == 'company_admin',
            previews: Map.of(c.previews),
            previewsLoading: c.previewsLoading.value,
            replacements: c.replacements,
            onChanged: (s) {
              c.currentTemplate.value = s.template;
              c.session.refresh().ignore();
            },
          );
        }),
        gap,

        // ── identity ──
        AdminSection(
          label: 'admin.companyDetails'.tr,
          child: AdminFields([
            field(
              'name',
              c.name,
              'admin.companyName'.tr,
              required: true,
              icon: PhosphorIconsRegular.buildings,
            ),
            field('legal_name', c.legalName, 'admin.legalName'.tr),
            field('address', c.address, 'admin.address'.tr, lines: 2),
            field(
              'phone',
              c.phone,
              'admin.phone'.tr,
              type: TextInputType.phone,
              icon: PhosphorIconsRegular.phone,
            ),
            field(
              'email',
              c.email,
              'admin.email'.tr,
              type: TextInputType.emailAddress,
              required: true,
              icon: PhosphorIconsRegular.envelopeSimple,
            ),
            field(
              'website',
              c.website,
              'admin.website'.tr,
              type: TextInputType.url,
              icon: PhosphorIconsRegular.globe,
            ),
            field('tin', c.tin, 'admin.tinNumber'.tr),
          ]),
        ),
        gap,

        // ── marks and colour ──
        AdminSection(
          label: 'admin.documentLetterhead'.tr,
          child: AdminFields([
            Obx(
              () => _LogoField(
                label: 'admin.logoLockup'.tr,
                url: c.shownUrl(LogoSlot.logo),
                onPick: () => c.pickLogo(LogoSlot.logo),
                onClear: () => c.removeLogo(LogoSlot.logo),
              ),
            ),
            Obx(
              () => _LogoField(
                label: 'admin.logoMark'.tr,
                url: c.shownUrl(LogoSlot.logoMark),
                square: true,
                onPick: () => c.pickLogo(LogoSlot.logoMark),
                onClear: () => c.removeLogo(LogoSlot.logoMark),
              ),
            ),
            Obx(
              () => _ColourField(
                controller: c.primaryColor,
                error: c.fieldErrors['primary_color'],
              ),
            ),
            field(
              'voucher_footer_text',
              c.footer,
              'admin.voucherFooterText'.tr,
              lines: 3,
            ),
          ], gap: 18),
        ),
        gap,

        // ── the interface palette ──
        AdminSection(
          label: 'branding.interfaceColour'.tr,
          padding: const EdgeInsets.all(12),
          child: Obx(
            () => LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 520 ? 4 : 2;
                final w = (box.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in VfAccentPalette.all)
                      SizedBox(
                        width: w,
                        child: _PaletteOption(
                          palette: p,
                          label:
                              'branding.palette${p.key[0].toUpperCase()}${p.key.substring(1)}'
                                  .tr,
                          selected: c.colorTheme.value == p.key,
                          onTap: () => c.chooseColour(p.key),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        gap,

        // ── the account bank vouchers are drawn on ──
        AdminSection(
          label: 'admin.bankDetails'.tr,
          child: AdminFields([
            field(
              'bank_name',
              c.bankName,
              'admin.bank'.tr,
              icon: PhosphorIconsRegular.bank,
            ),
            field('bank_branch', c.bankBranch, 'admin.branch'.tr),
            field(
              'bank_account_name',
              c.bankAccountName,
              'admin.accountName'.tr,
            ),
            field(
              'bank_account_number',
              c.bankAccountNumber,
              'admin.accountNo'.tr,
              type: TextInputType.number,
            ),
          ]),
        ),
        gap,

        // ── live specimen ──
        AdminSection(
          label: 'admin.livePreview'.tr,
          padding: const EdgeInsets.all(10),
          child: Obx(() {
            final html = c.previews[c.currentTemplate.value];
            if (html == null) {
              if (c.previewsFailed.value) {
                return AdminNote('branding.previewUnavailable'.tr);
              }
              return AspectRatio(
                aspectRatio: kA4Width / kA4Height,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface3,
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                  ),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              child: VouchFlowDocumentView(
                html: html,
                fit: VfDocumentFit.content,
                placeholderReplacements: c.replacements,
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// An image field that shows what is set and lets it be replaced. The well
/// is paper-white in both appearances: a logo is artwork for the printed
/// page, and a dark logo on a dark well would disappear.
class _LogoField extends StatelessWidget {
  const _LogoField({
    required this.label,
    required this.url,
    required this.onPick,
    required this.onClear,
    this.square = false,
  });

  final String label;
  final String? url;
  final bool square;
  final VoidCallback onPick, onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final value = url;
    Widget image;
    if (value == null) {
      image = const Icon(
        PhosphorIconsRegular.image,
        size: 24,
        color: Color(0xFFB8C0D0),
      );
    } else if (value.startsWith('data:')) {
      image = Image.memory(
        base64Decode(value.substring(value.indexOf(',') + 1)),
        fit: BoxFit.contain,
      );
    } else {
      image = Image.network(
        value,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(
          PhosphorIconsRegular.imageBroken,
          size: 24,
          color: Color(0xFFB8C0D0),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            child: Container(
              height: 76,
              width: square ? 76 : 112,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VfDoc.paper,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(VfSize.radiusL),
              ),
              alignment: Alignment.center,
              child: image,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 14.5,
                ),
              ),
              Text(
                'branding.logoRules'.tr,
                style: VfType.meta.copyWith(color: t.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  VouchFlowButton(
                    label: value != null
                        ? 'admin.replace'.tr
                        : 'admin.uploadImage'.tr,
                    icon: PhosphorIconsRegular.uploadSimple,
                    variant: VfButtonVariant.secondary,
                    compact: true,
                    onPressed: onPick,
                  ),
                  if (value != null)
                    VouchFlowIconButton(
                      icon: PhosphorIconsRegular.trash,
                      tooltip: 'admin.remove'.tr,
                      size: 36,
                      color: t.dangerStrong,
                      onPressed: onClear,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The document colour: a swatch that opens a palette, and its hex value.
class _ColourField extends StatefulWidget {
  const _ColourField({required this.controller, this.error});

  final TextEditingController controller;
  final String? error;

  @override
  State<_ColourField> createState() => _ColourFieldState();
}

class _ColourFieldState extends State<_ColourField> {
  static const _presets = [
    '#2E3192',
    '#1D4ED8',
    '#0369A1',
    '#0F766E',
    '#047857',
    '#15803D',
    '#4D7C0F',
    '#A16207', //
    '#C2410C',
    '#B91C1C',
    '#BE123C',
    '#9D174D',
    '#7E22CE',
    '#6D28D9',
    '#334155',
    '#0B1220',
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  Color? get _colour {
    final v = widget.controller.text.trim();
    if (!_hex.hasMatch(v)) return null;
    return Color(int.parse('FF${v.substring(1)}', radix: 16));
  }

  Future<void> _pick() async {
    final chosen = await showVouchFlowBottomSheet<String>(
      context,
      title: 'branding.colourPick'.tr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in _presets)
              Builder(
                builder: (ctx) => Semantics(
                  button: true,
                  label: hex,
                  selected: widget.controller.text.trim().toUpperCase() == hex,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                    onTap: () => Navigator.of(ctx).pop(hex),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse('FF${hex.substring(1)}', radix: 16),
                        ),
                        borderRadius: BorderRadius.circular(VfSize.radiusL),
                        border: Border.all(color: ctx.vf.borderStrong),
                      ),
                      child: widget.controller.text.trim().toUpperCase() == hex
                          ? const Icon(
                              PhosphorIconsBold.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) widget.controller.text = chosen;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final colour = _colour;
    final invalid = colour == null && widget.controller.text.trim().isNotEmpty;
    return VouchFlowField(
      label: 'admin.colour'.tr,
      error: widget.error ?? (invalid ? 'branding.colourInvalid'.tr : null),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'branding.colourPick'.tr,
            child: InkWell(
              onTap: _pick,
              customBorder: const CircleBorder(),
              child: Container(
                width: VfSize.inputH,
                height: VfSize.inputH,
                decoration: BoxDecoration(
                  color: colour ?? t.surface3,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.borderStrong),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 150,
            child: TextField(
              controller: widget.controller,
              style: VfType.body.copyWith(
                color: t.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: t.inputBg,
                prefixIcon: Icon(
                  PhosphorIconsRegular.hash,
                  size: 17,
                  color: t.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteOption extends StatelessWidget {
  const _PaletteOption({
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
    final t = context.vf;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      child: Material(
        color: selected ? t.primarySoft : t.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          side: BorderSide(
            color: selected ? palette.solid : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          PhosphorIconsBold.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(color: t.text, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether this person may edit the company's branding. The API enforces the
/// same rule; this only decides whether the entry point is shown.
bool canEditBranding(AppUser user) => user.role == 'company_admin';
