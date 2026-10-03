import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/models/vouchers_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/create_repository.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show Fmt, showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import 'create_steps.dart';
import 'edit_voucher_page.dart';
import 'preview_frame_stub.dart' if (dart.library.js_interop) 'preview_frame_web.dart';
import 'voucher_form_bits.dart';

const voucherMethods = ['Bank Transfer', 'Mobile Money', 'Cash', 'Cheque'];
const voucherCurrencies = ['TZS', 'USD', 'KES', 'EUR'];
const voucherCategories = [
  'Fuel',
  'Transport',
  'Vehicle maintenance',
  'Travel & accommodation',
  'Meals & refreshments',
  'Office supplies & stationery',
  'Internet & communications',
  'Procurement',
  'Logistics',
  'Staff welfare',
  'Equipment',
  'Repairs & maintenance',
  'Utilities',
  'Professional fees',
  'Premises',
  'Other',
];

/// Which fields each step owns, in order — the server's refusal of a field
/// takes the reader back to its step.
const _stepFields = [
  ['voucher_type_id', 'kind'],
  ['voucher_date', 'department_id', 'category', 'payee', 'purpose', 'description'],
  [
    'amount',
    'currency',
    'payment_method',
    'account_ref',
    'payee_bank',
    'payee_account_name', //
    'payee_account_number', 'payee_bank_branch', 'cash_float',
  ],
  ['files', 'notes_to_approver'],
  <String>[],
];

/// The server's upload rules (web lib/attachments.ts).
const maxUploadMb = 10;
const maxFilesPerUpload = 10;
const _extensionTypes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

/// A supporting document picked on the device, not yet uploaded.
class PickedDocument {
  PickedDocument({required this.name, required this.size, required this.file});

  final String name;
  final int size;
  final XFile file;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isImage => (_extensionTypes[extension] ?? '').startsWith('image/');
}

/// A picked file the server would refuse, and why: `type`, `size`, `count`.
typedef RejectedDocument = ({String name, String reason});

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// The guided five-step create flow (web `/vouchers/new`): type → details →
/// payment → documents → review, with the server-rendered live preview.
class CreateVoucherController extends GetxController {
  final vouchers = Get.find<VoucherRepository>();
  final repo = CreateRepository.to;
  final session = Get.find<SessionService>();

  final step = 0.obs;
  final busy = RxnString();

  /// Bumped on every edit, so the words, review and preview follow the form.
  final rev = 0.obs;

  final types = <VoucherTypeOption>[].obs;
  final typesLoaded = false.obs;
  final typesError = RxnString();
  final departments = <Department>[].obs;
  final workflows = <RouteWorkflow>[].obs;

  final kind = 'bank'.obs;
  final typeId = RxnInt();
  final departmentId = RxnInt();
  final category = 'Logistics'.obs;
  final method = 'Bank Transfer'.obs;
  final currency = 'TZS'.obs;
  final voucherDate = DateTime.now().obs;

  final payee = TextEditingController();
  final purpose = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  final accountRef = TextEditingController();
  final payeeBank = TextEditingController();
  final payeeAccountName = TextEditingController();
  final payeeAccountNumber = TextEditingController();
  final payeeBankBranch = TextEditingController();
  final cashFloat = TextEditingController();
  final notes = TextEditingController();

  final files = <PickedDocument>[].obs;
  final rejected = <RejectedDocument>[].obs;

  final serverErrors = <String, String>{}.obs;
  final localErrors = <String, String>{}.obs;

  final previewHtml = RxnString();
  final previewFailed = false.obs;
  Timer? _previewTimer;
  String? _previewKey;
  int _previewTicket = 0;

  final scroll = ScrollController();
  Worker? _watch;

  List<TextEditingController> get _texts => [
    payee,
    purpose,
    description,
    amount,
    accountRef,
    payeeBank,
    payeeAccountName, //
    payeeAccountNumber, payeeBankBranch, cashFloat, notes,
  ];

  VoucherTypeOption? get selectedType => types.firstWhereOrNull((t) => t.id == typeId.value);
  Department? get department => departments.firstWhereOrNull((d) => d.id == departmentId.value);
  double get amountValue => parseAmount(amount.text);
  String get words => amountInWords(amountValue, currency.value);
  bool get onReview => step.value == 4;
  bool get sw => Get.locale?.languageCode == 'sw';

  List<String> get route => routeFor(resolveWorkflow(workflows, typeId.value), amountValue, sw: sw);

  String? errorFor(String name) => serverErrors[name] ?? localErrors[name];

  @override
  void onInit() {
    super.onInit();
    currency.value = session.company.value?.currency ?? 'TZS';
    departmentId.value = session.me.departmentId;
    for (final c in _texts) {
      c.addListener(touch);
    }
    _watch = everAll([kind, typeId, category, method, currency, voucherDate], (_) => touch());
    loadOptions();
    _schedulePreview(immediate: true);
  }

  /// Something on the form changed.
  void touch() {
    rev.value++;
    _schedulePreview();
  }

  Future<void> loadOptions() async {
    typesError.value = null;
    try {
      final loaded = await repo.types();
      types.assignAll(loaded);
      typeId.value ??= loaded.firstOrNull?.id;
    } on ApiException catch (e) {
      typesError.value = e.message;
    } catch (_) {
      typesError.value = 'create.offline'.tr;
    } finally {
      typesLoaded.value = true;
    }
    try {
      departments.assignAll(await vouchers.departments());
      departmentId.value = session.me.departmentId;
    } catch (_) {}
    final companyId = session.company.value?.id;
    if (companyId != null) {
      try {
        workflows.assignAll(await repo.workflows(companyId));
      } catch (_) {
        // The route is an aid on the review step; its absence never blocks.
      }
    }
  }

  void chooseKind(String value) {
    kind.value = value;
    method.value = value == 'bank' ? 'Bank Transfer' : 'Cash';
  }

  /* ── steps ──────────────────────────────────────────────────────────── */

  /// What must be true before leaving a step — what the server insists on.
  Map<String, String> _problemsAt(int index) {
    final out = <String, String>{};
    if (index == 1) {
      if (payee.text.trim().isEmpty) out['payee'] = 'create.required'.tr;
      if (purpose.text.trim().isEmpty) out['purpose'] = 'create.required'.tr;
    }
    if (index == 2 && amountValue <= 0) {
      out['amount'] = 'create.amountRequired'.tr;
    }
    return out;
  }

  /// Moving forward checks every step being passed; moving back never does.
  void go(int next) {
    if (next > step.value) {
      for (var i = step.value; i < next; i++) {
        final problems = _problemsAt(i);
        if (problems.isNotEmpty) {
          localErrors.assignAll(problems);
          _setStep(i);
          return;
        }
      }
    }
    localErrors.clear();
    _setStep(next);
  }

  void _setStep(int value) {
    step.value = value;
    if (scroll.hasClients) {
      scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /* ── documents ─────────────────────────────────────────────────────── */

  /// Merges newly picked files into those already chosen, refusing what the
  /// server would refuse — before the voucher exists, not after.
  void addFiles(List<PickedDocument> picked) {
    if (picked.isEmpty) return;
    final out = <RejectedDocument>[];
    final list = [...files];
    for (final f in picked) {
      if (!_extensionTypes.containsKey(f.extension)) {
        out.add((name: f.name, reason: 'type'));
      } else if (f.size > maxUploadMb * 1024 * 1024) {
        out.add((name: f.name, reason: 'size'));
      } else if (list.any((e) => e.name == f.name && e.size == f.size)) {
        continue;
      } else if (list.length >= maxFilesPerUpload) {
        out.add((name: f.name, reason: 'count'));
      } else {
        list.add(f);
      }
    }
    files.assignAll(list);
    rejected.assignAll(out);
  }

  void removeFile(PickedDocument f) {
    files.remove(f);
    rejected.clear();
  }

  Future<void> browseFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: _extensionTypes.keys.toList(),
        withData: kIsWeb,
      );
      if (result == null) return;
      addFiles([
        for (final f in result.files)
          PickedDocument(
            name: f.name,
            size: f.size,
            file: f.bytes != null ? XFile.fromData(f.bytes!, name: f.name) : XFile(f.path!, name: f.name),
          ),
      ]);
    } catch (_) {
      showToast('create.filesNotAdded'.tr, kind: ToastKind.bad);
    }
  }

  Future<void> takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000, maxHeight: 2000);
      if (shot == null) return;
      var name = shot.name;
      if (!name.contains('.')) name = '$name.jpg';
      addFiles([PickedDocument(name: name, size: await shot.length(), file: shot)]);
    } catch (_) {
      showToast('create.filesNotAdded'.tr, kind: ToastKind.bad);
    }
  }

  /* ── preview ───────────────────────────────────────────────────────── */

  /// The draft as the server renders it — shared by the card and full size.
  Map<String, dynamic> get draft => {
    'number': selectedType?.nextNumberPreview ?? '—',
    'voucher_type_id': typeId.value,
    'department_id': departmentId.value,
    'payee': _orNull(payee),
    'purpose': _orNull(purpose),
    'description': _orNull(description),
    'amount': amountValue,
    'currency': currency.value,
    'kind': kind.value,
    'payment_method': method.value,
    'account_ref': _orNull(accountRef),
    'category': category.value,
    'voucher_date': apiDate(voucherDate.value),
    'notes_to_approver': _orNull(notes),
    if (kind.value == 'bank') ...{
      'payee_bank': _orNull(payeeBank),
      'payee_account_name': _orNull(payeeAccountName),
      'payee_account_number': _orNull(payeeAccountNumber),
      'payee_bank_branch': _orNull(payeeBankBranch),
    } else
      'cash_float': _orNull(cashFloat),
  };

  static String? _orNull(TextEditingController c) => c.text.isEmpty ? null : c.text;

  void _schedulePreview({bool immediate = false}) {
    _previewTimer?.cancel();
    _previewTimer = Timer(Duration(milliseconds: immediate ? 0 : 400), refreshPreview);
  }

  Future<void> refreshPreview({bool force = false}) async {
    final body = draft;
    final key = jsonEncode(body);
    if (!force && key == _previewKey && previewHtml.value != null) return;
    _previewKey = key;
    final ticket = ++_previewTicket;
    if (force) previewFailed.value = false;
    try {
      final html = await repo.documentPreview(body);
      if (ticket != _previewTicket) return;
      previewHtml.value = html;
      previewFailed.value = false;
    } catch (_) {
      if (ticket == _previewTicket) previewFailed.value = true;
    }
  }

  /* ── save ──────────────────────────────────────────────────────────── */

  Future<void> save({required bool submit}) async {
    if (busy.value != null) return;
    busy.value = submit ? 'submit' : 'draft';
    serverErrors.clear();
    try {
      final voucher = await vouchers.create({
        'kind': kind.value,
        'payee_bank': payeeBank.text,
        'payee_account_name': payeeAccountName.text,
        'payee_account_number': payeeAccountNumber.text,
        'payee_bank_branch': payeeBankBranch.text,
        'cash_float': cashFloat.text,
        'voucher_type_id': typeId.value,
        'department_id': departmentId.value,
        'payee': payee.text,
        'purpose': purpose.text,
        'description': description.text,
        'amount': amountValue,
        'currency': currency.value,
        'payment_method': method.value,
        'account_ref': accountRef.text,
        'category': category.value,
        'voucher_date': apiDate(voucherDate.value),
        'notes_to_approver': notes.text,
      });

      if (files.isNotEmpty) {
        try {
          final parts = <http.MultipartFile>[];
          for (final f in files) {
            parts.add(http.MultipartFile.fromBytes('files[]', await f.file.readAsBytes(), filename: f.name));
          }
          await vouchers.attach(voucher.id, parts);
        } catch (e) {
          // The voucher exists now: staying would invite a duplicate. Go to the
          // draft, where documents can be added again, and say what failed.
          final detail = e is ApiException ? (e.errors.values.firstOrNull?.firstOrNull ?? e.message) : null;
          showToast(
            'create.docsNotAttached'.tr,
            body: '${voucher.number} — ${detail ?? 'create.docsNotAttachedBody'.tr}',
            kind: ToastKind.bad,
          );
          Get.offNamed(Routes.voucher, arguments: voucher.id);
          return;
        }
      }

      if (submit) {
        final sent = await vouchers.submit(voucher.id);
        showToast('create.submitted'.tr, body: '${sent.number} — ${sent.statusLabel}');
      } else {
        showToast(
          'create.draftSaved'.tr,
          body: 'create.draftSavedBody'.trParams({'number': voucher.number}),
          kind: ToastKind.warn,
        );
      }
      Get.offNamed(Routes.voucher, arguments: voucher.id);
    } on ApiException catch (e) {
      serverErrors.assignAll(e.errors.map((k, v) => MapEntry(k, v.isEmpty ? '' : v.first)));
      final fields = e.errors.keys;
      final at = _stepFields.indexWhere((owned) => owned.any((f) => fields.any((x) => x == f || x.startsWith('$f.'))));
      if (at >= 0) _setStep(at);
      showToast('create.couldNotSave'.tr, body: e.message, kind: ToastKind.bad);
      busy.value = null;
    } catch (_) {
      showToast('create.couldNotSave'.tr, body: 'create.offline'.tr, kind: ToastKind.bad);
      busy.value = null;
    }
  }

  @override
  void onClose() {
    _previewTimer?.cancel();
    _watch?.dispose();
    for (final c in _texts) {
      c.dispose();
    }
    scroll.dispose();
    super.onClose();
  }
}

/// `/voucher/new`. With an int argument (a voucher id) it opens that voucher's
/// edit form instead — the web's `/vouchers/{id}/edit`.
class CreateVoucherPage extends StatelessWidget {
  const CreateVoucherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int) return EditVoucherPage(voucherId: args);
    return _CreateVoucherView(controller: Get.find<CreateVoucherController>());
  }
}

class _CreateVoucherView extends StatelessWidget {
  const _CreateVoucherView({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    final steps = [
      VfStep('create.stepType'.tr),
      VfStep('create.stepDetails'.tr),
      VfStep('create.stepPayment'.tr),
      VfStep('create.stepDocs'.tr),
      VfStep('create.stepReview'.tr),
    ];
    final roomy = MediaQuery.sizeOf(context).width >= 380;

    return VouchFlowPushedScaffold(
      title: 'create.createVoucher'.tr,
      actions: [
        // The number this voucher will take, small, beside the title.
        if (roomy)
          Obx(() {
            final type = c.selectedType;
            if (type == null) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: t.primarySoft, borderRadius: BorderRadius.circular(VfSize.radiusPill)),
              child: Text(
                type.nextNumberPreview,
                style: VfType.meta.copyWith(
                  color: t.primaryText,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),
        VfBarButton(
          icon: PhosphorIconsRegular.eye,
          tooltip: 'create.fullSize'.tr,
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FullPreviewPage(controller: c))),
        ),
      ],
      bottomBar: _ActionBar(controller: c),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(VfSize.pagePad + 2, 2, VfSize.pagePad + 2, 4),
            child: Obx(
              () => VouchFlowStepper(
                steps: steps,
                current: c.step.value,
                onTap: c.go,
                progressLabel: (n, _) => 'create.stepOf'.trParams({'n': '$n'}),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 600;
                return ListView(
                  controller: c.scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    VfSize.pagePad,
                    16,
                    VfSize.pagePad,
                    28 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    Obx(() {
                      // Follow every edit and every list the steps read.
                      c.rev.value;
                      c.types.length;
                      c.typesLoaded.value;
                      c.typesError.value;
                      c.departments.length;
                      c.workflows.length;
                      c.files.length;
                      c.rejected.length;
                      c.serverErrors.length;
                      c.localErrors.length;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        // Only the arriving step is laid out; it fades and slides in.
                        layoutBuilder: (cur, _) => cur ?? const SizedBox.shrink(),
                        child: KeyedSubtree(
                          key: ValueKey(c.step.value),
                          child: switch (c.step.value) {
                            0 => TypeStep(c: c, wide: wide),
                            1 => DetailsStep(c: c, wide: wide),
                            2 => PaymentStep(c: c, wide: wide),
                            3 => DocumentsStep(c: c),
                            _ => ReviewStep(c: c),
                          },
                        ),
                      );
                    }),
                    // The sheet as it will print, on the review step.
                    Obx(
                      () => c.onReview
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 680),
                                  child: _PreviewCard(controller: c),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The sticky bottom bar: a round Back, Save draft, and a big Next (Submit on
/// the review step).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final CreateVoucherController controller;

  static const _h = 54.0;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: t.isDark ? Border(top: BorderSide(color: t.border)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? .45 : .08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < 340;
              return Obx(() {
                final busy = c.busy.value;
                final step = c.step.value;
                final review = step == 4;
                Widget round({
                  required IconData icon,
                  required String tip,
                  required VoidCallback? onTap,
                  bool loading = false,
                }) => Tooltip(
                  message: tip,
                  child: Material(
                    color: t.surface3,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onTap,
                      child: SizedBox(
                        width: _h,
                        height: _h,
                        child: loading
                            ? Padding(
                                padding: const EdgeInsets.all(17),
                                child: CircularProgressIndicator(strokeWidth: 2, color: t.text2),
                              )
                            : Icon(icon, size: 21, color: t.text, semanticLabel: tip),
                      ),
                    ),
                  ),
                );
                final forward = review
                    ? VouchFlowButton(
                        label: 'create.submitVoucher'.tr,
                        icon: narrow ? null : PhosphorIconsBold.paperPlaneTilt,
                        height: _h,
                        expand: true,
                        loading: busy == 'submit',
                        onPressed: busy != null ? null : () => c.save(submit: true),
                      )
                    : VouchFlowButton(
                        label: 'create.next'.tr,
                        trailingIcon: PhosphorIconsBold.arrowRight,
                        height: _h,
                        expand: true,
                        onPressed: () => c.go(step + 1),
                      );
                return Row(
                  children: [
                    if (step > 0) ...[
                      round(
                        icon: PhosphorIconsBold.arrowLeft,
                        tip: 'create.back'.tr,
                        onTap: busy != null ? null : () => c.go(step - 1),
                      ),
                      const SizedBox(width: 10),
                    ],
                    // On the narrowest phones the draft button gives way to an
                    // icon so the way forward never truncates.
                    if (narrow || step > 0 && box.maxWidth < 380)
                      round(
                        icon: PhosphorIconsRegular.floppyDisk,
                        tip: 'create.saveDraft'.tr,
                        loading: busy == 'draft',
                        onTap: busy != null ? null : () => c.save(submit: false),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth * .4),
                        child: VouchFlowButton(
                          label: 'create.saveDraft'.tr,
                          variant: VfButtonVariant.secondary,
                          height: _h,
                          loading: busy == 'draft',
                          onPressed: busy != null ? null : () => c.save(submit: false),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(child: forward),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }
}

/// The sheet that will print, rendered by the server in the company's own
/// voucher template and updating as the form is filled in.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: t.isDark ? Border.all(color: t.border) : null,
        boxShadow: t.cardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsFill.fileText, size: 18, color: t.primaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'create.livePreview'.tr,
                  style: VfType.bodyStrong.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
              VouchFlowIconButton(
                icon: PhosphorIconsRegular.arrowsOutSimple,
                tooltip: 'create.fullSize'.tr,
                size: 44,
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => _FullPreviewPage(controller: c))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                color: t.surface3,
                child: Obx(() {
                  final html = c.previewHtml.value;
                  if (html == null && c.previewFailed.value) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                      child: VouchFlowErrorState(
                        message: 'create.previewFailed'.tr,
                        retryLabel: 'create.retry'.tr,
                        onRetry: () => c.refreshPreview(force: true),
                      ),
                    );
                  }
                  final skeleton = AspectRatio(
                    aspectRatio: kA4Width / kA4Height,
                    child: ColoredBox(color: t.surface2),
                  );
                  if (html == null) return skeleton;
                  // The document mounts once the page has finished sliding in, so
                  // the web view never rides the route transition.
                  final route = ModalRoute.of(context)?.animation;
                  return AnimatedBuilder(
                    animation: route ?? kAlwaysCompleteAnimation,
                    builder: (context, _) {
                      if (!(route?.isCompleted ?? true)) return skeleton;
                      if (kIsWeb) {
                        return LayoutBuilder(
                          builder: (_, box) => previewFrame(html: html, width: box.maxWidth),
                        );
                      }
                      return VouchFlowDocumentView(html: html, fit: VfDocumentFit.content);
                    },
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The preview full size: pinch to zoom, scroll the whole sheet.
class _FullPreviewPage extends StatelessWidget {
  const _FullPreviewPage({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final type = c.selectedType;
    return VouchFlowPushedScaffold(
      title: type != null ? '${type.label} · ${type.nextNumberPreview}' : 'create.livePreview'.tr,
      body: Obx(() {
        final html = c.previewHtml.value;
        if (html == null) {
          return c.previewFailed.value
              ? Padding(
                  padding: const EdgeInsets.all(VfSize.pagePad),
                  child: VouchFlowErrorState(
                    message: 'create.previewFailed'.tr,
                    retryLabel: 'create.retry'.tr,
                    onRetry: () => c.refreshPreview(force: true),
                  ),
                )
              : const Center(child: CircularProgressIndicator());
        }
        return VouchFlowDocumentView(html: html, fit: VfDocumentFit.fill, interactive: true);
      }),
    );
  }
}

/// A money figure the way the web prints it.
String previewMoney(CreateVoucherController c) => Fmt.money(c.amountValue, c.currency.value);

/// The session's user, for the read-only requester field.
AppUser currentUser() => Get.find<SessionService>().me;
