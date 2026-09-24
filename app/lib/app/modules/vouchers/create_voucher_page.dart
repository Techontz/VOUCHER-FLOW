import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';

/// The design's four-step mobile capture flow: basic information → payment
/// details → attachments → review, then submit. The fields, their validation
/// and the calls made are the same as before; only their grouping changed.
class CreateVoucherController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final step = 0.obs;
  final busy = false.obs;
  final types = <VoucherType>[].obs;
  final departments = <Department>[].obs;
  final typeId = RxnInt();
  final departmentId = RxnInt();
  final attachments = <File>[].obs;
  final fieldErrors = <String, String>{}.obs;

  final payee = TextEditingController();
  final purpose = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  final reference = TextEditingController();
  final notes = TextEditingController();

  /// Bank or cash — the two corporate formats, chosen first.
  final kind = 'bank'.obs;
  final method = 'Bank Transfer'.obs;
  final category = 'Logistics'.obs;
  final currency = 'TZS'.obs;

  static const methods = ['Bank Transfer', 'Mobile Money', 'Cash', 'Cheque'];
  static const categories = [
    'Logistics',
    'Premises',
    'Transport',
    'Capital equipment',
    'Professional fees',
    'Staff welfare',
    'Utilities',
    'Other',
  ];

  static const stepTitles = [
    'step.basic',
    'step.payment',
    'step.attachments',
    'step.review',
  ];

  static const stepShort = [
    'step.basicShort',
    'step.paymentShort',
    'step.attachmentsShort',
    'step.reviewShort',
  ];

  static const lastStep = 3;

  double get amountValue =>
      double.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  VoucherType? get selectedType =>
      types.firstWhereOrNull((t) => t.id == typeId.value);

  @override
  void onInit() {
    super.onInit();
    currency.value = session.company.value?.currency ?? 'TZS';
    departmentId.value = session.me.departmentId;

    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final loaded = await repo.types();
      types.assignAll(loaded);
      typeId.value ??= loaded.firstOrNull?.id;
    } catch (_) {
      // The step simply shows nothing to choose; the user can retry by reopening.
    }
    try {
      departments.assignAll(await repo.departments());
    } catch (_) {}
  }

  /// The same required fields as before — type, amount, purpose, payee —
  /// asked for on the step that now holds them.
  bool get canAdvance => switch (step.value) {
    0 =>
      typeId.value != null &&
          amountValue > 0 &&
          purpose.text.trim().isNotEmpty,
    1 => payee.text.trim().isNotEmpty,
    _ => true,
  };

  void next() {
    if (!canAdvance) return;
    if (step.value < lastStep) step.value++;
  }

  void goTo(int index) => step.value = index;

  /// Bumped on every keystroke in a required field, so the Continue button
  /// re-reads [canAdvance] as the user types.
  final edits = 0.obs;
  void touched() {
    edits.value++;
    fieldErrors.refresh();
  }

  void setKind(String value) {
    kind.value = value;
    method.value = value == 'cash' ? 'Cash' : 'Bank Transfer';
  }

  void back() {
    if (step.value > 0) step.value--;
  }

  Future<void> addPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked != null) attachments.add(File(picked.path));
  }

  Future<void> save({required bool submit}) async {
    busy.value = true;
    fieldErrors.clear();
    try {
      final voucher = await repo.create({
        'kind': kind.value,
        'voucher_type_id': typeId.value,
        'department_id': departmentId.value,
        'payee': payee.text.trim(),
        'purpose': purpose.text.trim(),
        'description': description.text.trim(),
        'amount': amountValue,
        'currency': currency.value,
        'payment_method': method.value,
        'account_ref': reference.text.trim(),
        'category': category.value,
        'notes_to_approver': notes.text.trim(),
      });

      if (attachments.isNotEmpty) {
        final files = <http.MultipartFile>[];
        for (final file in attachments) {
          files.add(await http.MultipartFile.fromPath('files[]', file.path));
        }
        await repo.attach(voucher.id, files);
      }

      if (submit) {
        final sent = await repo.submit(voucher.id);
        showToast(
          'msg.submitted'.tr,
          body: '${sent.number} · ${sent.statusLabel}',
        );
      } else {
        showToast(
          'voucher.saveDraft'.tr,
          body: voucher.number,
          kind: ToastKind.warn,
        );
      }

      Get.offNamed(Routes.voucher, arguments: voucher.id);
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.errors.map((k, v) => MapEntry(k, v.first)));
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } catch (_) {
      showToast(
        'state.error'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    for (final c in [payee, purpose, description, amount, reference, notes]) {
      c.dispose();
    }
    super.onClose();
  }
}

class CreateVoucherPage extends GetView<CreateVoucherController> {
  const CreateVoucherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const total = CreateVoucherController.lastStep + 1;

    return Obx(() {
      final step = controller.step.value;
      return PopScope(
        canPop: step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.back();
        },
        child: Scaffold(
          appBar: AppBar(
            leadingWidth: 60,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: IconButton.outlined(
                  tooltip: step == 0 ? 'action.close'.tr : 'action.back'.tr,
                  style: IconButton.styleFrom(
                    side: BorderSide(color: context.vfLine),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(VfTheme.rMd),
                    ),
                  ),
                  onPressed: step == 0 ? Get.back : controller.back,
                  icon: Icon(
                    step == 0 ? Icons.close : Icons.chevron_left,
                    size: 20,
                  ),
                ),
              ),
            ),
            title: Text('voucher.new'.tr),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(total, (i) {
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: EdgeInsets.only(
                              right: i == total - 1 ? 0 : 5,
                            ),
                            decoration: BoxDecoration(
                              color: i <= step
                                  ? VfColors.accent500
                                  : context.vfLineStrong,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${'step.count'.trParams({'n': '${step + 1}', 'total': '$total'})} · '
                            '${CreateVoucherController.stepTitles[step].tr}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: context.vfInk,
                            ),
                          ),
                        ),
                        if (step < CreateVoucherController.lastStep)
                          Text(
                            'step.next'.trParams({
                              'step': CreateVoucherController
                                  .stepShort[step + 1]
                                  .tr,
                            }),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: switch (step) {
            0 => _BasicStep(controller: controller),
            1 => _PaymentStep(controller: controller),
            2 => _AttachmentStep(controller: controller),
            _ => _ReviewStep(controller: controller),
          },
          bottomNavigationBar: StickyActions(child: _Footer(controller)),
        ),
      );
    });
  }
}

class _Footer extends StatelessWidget {
  const _Footer(this.controller);

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.edits.value;
      final step = controller.step.value;
      final busy = controller.busy.value;
      final last = step == CreateVoucherController.lastStep;

      final spinner = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: VfTheme.onPrimary(context),
        ),
      );

      final primary = FilledButton(
        onPressed: busy || !controller.canAdvance
            ? null
            : () => last ? controller.save(submit: true) : controller.next(),
        child: busy && last
            ? spinner
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (last) ...[
                    const Icon(Icons.send_rounded, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      last ? 'voucher.submitShort'.tr : 'action.continue'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!last) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ],
              ),
      );

      Widget? secondary;
      if (step == 2 && controller.attachments.isEmpty) {
        secondary = OutlinedButton(
          onPressed: busy ? null : controller.next,
          child: Text('action.skip'.tr),
        );
      } else if (last) {
        secondary = OutlinedButton(
          onPressed: busy ? null : () => controller.save(submit: false),
          child: Text(
            'voucher.saveDraft'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }

      return Row(
        children: [
          if (secondary != null) ...[
            Expanded(child: secondary),
            const SizedBox(width: 10),
          ],
          Expanded(flex: 2, child: primary),
        ],
      );
    });
  }
}

IconData _typeIcon(VoucherType type) {
  final name = '${type.name} ${type.label}'.toLowerCase();
  if (name.contains('petty') || name.contains('cash')) {
    return Icons.payments_outlined;
  }
  if (name.contains('advance')) return Icons.flight_takeoff_outlined;
  if (name.contains('expense') || name.contains('claim')) {
    return Icons.receipt_outlined;
  }
  return Icons.description_outlined;
}

class _BasicStep extends StatelessWidget {
  const _BasicStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    // Read here, not inside the LayoutBuilder, so Obx tracks them.
    final types = controller.types.toList();
    final selected = controller.typeId.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        FieldLabel('voucher.type'.tr, required: true),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final type in types)
                  SizedBox(
                    width: width,
                    child: _TypeChip(
                      type: type,
                      selected: selected == type.id,
                      onTap: () => controller.typeId.value = type.id,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        FieldLabel('voucher.amount'.tr, required: true),
        _AmountField(controller: controller),
        const SizedBox(height: 20),
        FieldLabel('voucher.purpose'.tr, required: true),
        TextField(
          controller: controller.purpose,
          onChanged: (_) => controller.touched(),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'create.purposeHint'.tr,
            errorText: controller.fieldErrors['purpose'],
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.description'.tr),
        TextField(
          controller: controller.description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.category'.tr),
        DropdownButtonFormField<String>(
          initialValue: controller.category.value,
          isExpanded: true,
          items: CreateVoucherController.categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => controller.category.value = v ?? 'Logistics',
        ),
      ],
    );
  });
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final VoucherType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.vfAccent;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfTheme.rMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.vfAccentTint : context.vfElev1,
            border: Border.all(
              color: selected ? brand.withValues(alpha: .7) : context.vfLine,
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(VfTheme.rMd),
          ),
          child: Row(
            children: [
              Icon(
                _typeIcon(type),
                size: 18,
                color: selected ? brand : context.vfMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: selected ? context.vfInk : context.vfInk2,
                      ),
                    ),
                    if (type.nextNumberPreview.isNotEmpty)
                      Mono(type.nextNumberPreview, size: 10.5),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The amount gets its own large field: currency on the left, the figure in
/// tabular digits.
class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.fieldErrors['amount'];
    final big = TextStyle(
      fontFamily: VfTheme.fontFamily,
      fontSize: 30,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: context.vfInk,
      fontFeatures: VfTheme.tabular,
    );
    return TextField(
      controller: controller.amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => controller.touched(),
      style: big,
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: big.copyWith(color: context.vfFaint),
        errorText: error,
        contentPadding: const EdgeInsets.fromLTRB(4, 18, 14, 18),
        prefixIcon: PopupMenuButton<String>(
          tooltip: 'voucher.currency'.tr,
          initialValue: controller.currency.value,
          onSelected: (v) => controller.currency.value = v,
          itemBuilder: (_) => const ['TZS', 'USD', 'KES', 'EUR']
              .map((c) => PopupMenuItem(value: c, child: Text(c)))
              .toList(),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => Text(
                    controller.currency.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.vfMuted,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: context.vfMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        VfSegmented<String>(
          value: controller.kind.value,
          options: [
            ('bank', 'voucher.bankShort'.tr, Icons.account_balance_outlined),
            ('cash', 'voucher.cashShort'.tr, Icons.payments_outlined),
          ],
          onChanged: controller.setKind,
        ),
        const SizedBox(height: 6),
        Text(
          controller.kind.value == 'cash'
              ? 'voucher.cashSub'.tr
              : 'voucher.bankSub'.tr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        FieldLabel('voucher.payee'.tr, required: true),
        TextField(
          controller: controller.payee,
          onChanged: (_) => controller.touched(),
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(errorText: controller.fieldErrors['payee']),
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.method'.tr),
        DropdownButtonFormField<String>(
          // Re-keyed so switching Bank / Cash shows the method it implies.
          key: ValueKey(controller.method.value),
          initialValue: controller.method.value,
          isExpanded: true,
          items: CreateVoucherController.methods
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => controller.method.value = v ?? 'Bank Transfer',
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.reference'.tr),
        TextField(
          controller: controller.reference,
          style: Mono.style(context, size: 14.5, colour: context.vfInk),
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.department'.tr),
        DropdownButtonFormField<int?>(
          // The department is pre-filled from the signed-in user before the
          // list arrives; offering a value with no matching item throws.
          initialValue:
              controller.departments.any(
                (d) => d.id == controller.departmentId.value,
              )
              ? controller.departmentId.value
              : null,
          isExpanded: true,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            ...controller.departments.map(
              (d) => DropdownMenuItem<int?>(value: d.id, child: Text(d.name)),
            ),
          ],
          onChanged: (v) => controller.departmentId.value = v,
        ),
        const SizedBox(height: 16),
        FieldLabel('voucher.notes'.tr),
        TextField(
          controller: controller.notes,
          minLines: 2,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    ),
  );
}

class _AttachmentStep extends StatelessWidget {
  const _AttachmentStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(
      () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('attach.title'.tr, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('attach.body'.tr, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DashedAction(
                  icon: Icons.photo_camera_outlined,
                  label: 'attach.camera'.tr,
                  onTap: () => controller.addPhoto(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DashedAction(
                  icon: Icons.photo_library_outlined,
                  label: 'attach.gallery'.tr,
                  onTap: () => controller.addPhoto(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.attachments.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = (constraints.maxWidth - 20) / 3;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final file in controller.attachments)
                      _Thumb(
                        file: file,
                        size: size,
                        onRemove: () => controller.attachments.remove(file),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DashedAction extends StatelessWidget {
  const _DashedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(VfTheme.rMd),
    child: Container(
      height: 50,
      decoration: BoxDecoration(
        color: context.vfElev1,
        border: Border.all(color: context.vfLineStrong),
        borderRadius: BorderRadius.circular(VfTheme.rMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: context.vfInk2),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: context.vfInk2,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.size, required this.onRemove});

  final File file;
  final double size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = file.path.split('/').last;
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VfTheme.rMd),
        child: Container(
          decoration: BoxDecoration(
            color: context.vfElev2,
            border: Border.all(color: context.vfLine),
            borderRadius: BorderRadius.circular(VfTheme.rMd),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.insert_drive_file_outlined,
                  color: context.vfMuted,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: .55),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Mono(name, size: 10, colour: Colors.white),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black.withValues(alpha: .6),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final department = controller.departments.firstWhereOrNull(
        (d) => d.id == controller.departmentId.value,
      );

      Widget edit(String text, int step) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: InfoRows.value(context, text)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => controller.goTo(step),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'action.edit'.tr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.vfAccent,
                ),
              ),
            ),
          ),
        ],
      );

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SectionCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              children: [
                Text(
                  [
                    controller.selectedType?.label,
                    controller.kind.value == 'cash'
                        ? 'voucher.cashShort'.tr
                        : 'voucher.bankShort'.tr,
                  ].whereType<String>().join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Center(
                  child: AmountText(
                    amount: controller.amountValue,
                    currency: controller.currency.value,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'create.toPayee'.trParams({'payee': controller.payee.text}),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InfoRows(
            rows: [
              ('voucher.purpose'.tr, edit(controller.purpose.text, 0)),
              ('voucher.category'.tr, edit(controller.category.value, 0)),
              ('voucher.payee'.tr, edit(controller.payee.text, 1)),
              ('voucher.method'.tr, edit(controller.method.value, 1)),
              (
                'voucher.reference'.tr,
                edit(
                  controller.reference.text.isEmpty
                      ? '—'
                      : controller.reference.text,
                  1,
                ),
              ),
              ('voucher.department'.tr, edit(department?.name ?? '—', 1)),
              (
                'voucher.attachments'.tr,
                edit(
                  'create.files'.trParams({
                    'n': '${controller.attachments.length}',
                  }),
                  2,
                ),
              ),
            ],
          ),
          if (controller.description.text.trim().isNotEmpty ||
              controller.notes.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.description.text.trim().isNotEmpty) ...[
                    Text(
                      'voucher.description'.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.description.text.trim(),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (controller.notes.text.trim().isNotEmpty) ...[
                    Text('voucher.notes'.tr, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      controller.notes.text.trim(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}
