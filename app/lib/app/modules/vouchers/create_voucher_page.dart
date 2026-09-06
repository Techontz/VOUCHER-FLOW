import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';

/// The design's five-step mobile capture flow: type → payment → description →
/// attachments → review, then submit.
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
    'step.type',
    'step.payment',
    'step.details',
    'step.attachments',
    'step.review',
  ];

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

  bool get canAdvance => switch (step.value) {
    0 => typeId.value != null,
    1 => payee.text.trim().isNotEmpty && amountValue > 0,
    2 => purpose.text.trim().isNotEmpty,
    _ => true,
  };

  void next() {
    if (!canAdvance) return;
    if (step.value < 4) step.value++;
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

    return Scaffold(
      appBar: AppBar(
        title: Text('voucher.create'.tr),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Obx(
            () => Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (i) {
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(right: i == 4 ? 0 : 4),
                          color: i <= controller.step.value
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${'step.label'.tr} ${controller.step.value + 1} ${'step.of'.tr} 5 · '
                    '${CreateVoucherController.stepTitles[controller.step.value].tr}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Obx(
        () => switch (controller.step.value) {
          0 => _TypeStep(controller: controller),
          1 => _PaymentStep(controller: controller),
          2 => _DetailStep(controller: controller),
          3 => _AttachmentStep(controller: controller),
          _ => _ReviewStep(controller: controller),
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Obx(
          () => Row(
            children: [
              if (controller.step.value > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.busy.value ? null : controller.back,
                    child: Text('action.back'.tr),
                  ),
                ),
              if (controller.step.value > 0) const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: controller.busy.value || !controller.canAdvance
                      ? null
                      : () => controller.step.value < 4
                            ? controller.next()
                            : controller.save(submit: true),
                  child: controller.busy.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          controller.step.value < 4
                              ? 'action.continue'.tr
                              : 'voucher.submit'.tr,
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

class _TypeStep extends StatelessWidget {
  const _TypeStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        Text('voucher.type'.tr, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: controller.typeId.value,
          onChanged: (v) => controller.typeId.value = v,
          child: Column(
            children: controller.types
                .map(
                  (type) => RadioListTile<int>(
                    value: type.id,
                    contentPadding: EdgeInsets.zero,
                    title: Text(type.label),
                    subtitle: Text(
                      type.nextNumberPreview,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int?>(
          initialValue: controller.departmentId.value,
          decoration: InputDecoration(labelText: 'voucher.department'.tr),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            ...controller.departments.map(
              (d) => DropdownMenuItem<int?>(value: d.id, child: Text(d.name)),
            ),
          ],
          onChanged: (v) => controller.departmentId.value = v,
        ),
      ],
    ),
  );
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        TextField(
          controller: controller.payee,
          onChanged: (_) => controller.fieldErrors.refresh(),
          decoration: InputDecoration(
            labelText: 'voucher.payee'.tr,
            errorText: controller.fieldErrors['payee'],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller.amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => controller.fieldErrors.refresh(),
                decoration: InputDecoration(
                  labelText: 'voucher.amount'.tr,
                  errorText: controller.fieldErrors['amount'],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: controller.currency.value,
                decoration: InputDecoration(labelText: 'voucher.currency'.tr),
                items: const ['TZS', 'USD', 'KES', 'EUR']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => controller.currency.value = v ?? 'TZS',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: controller.method.value,
          decoration: InputDecoration(labelText: 'voucher.method'.tr),
          items: CreateVoucherController.methods
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => controller.method.value = v ?? 'Bank Transfer',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller.reference,
          decoration: InputDecoration(labelText: 'voucher.reference'.tr),
        ),
      ],
    ),
  );
}

class _DetailStep extends StatelessWidget {
  const _DetailStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        TextField(
          controller: controller.purpose,
          onChanged: (_) => controller.fieldErrors.refresh(),
          decoration: InputDecoration(
            labelText: 'voucher.purpose'.tr,
            errorText: controller.fieldErrors['purpose'],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller.description,
          maxLines: 4,
          decoration: InputDecoration(labelText: 'voucher.description'.tr),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: controller.category.value,
          decoration: InputDecoration(labelText: 'voucher.category'.tr),
          items: CreateVoucherController.categories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => controller.category.value = v ?? 'Logistics',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller.notes,
          maxLines: 3,
          decoration: InputDecoration(labelText: 'voucher.notes'.tr),
        ),
      ],
    ),
  );
}

class _AttachmentStep extends StatelessWidget {
  const _AttachmentStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => controller.addPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => controller.addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (controller.attachments.isEmpty)
          Text(
            'Photograph the receipt or invoice. PDF and images up to 10 MB.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...controller.attachments.map(
            (file) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.file(
                  file,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                file.path.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => controller.attachments.remove(file),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.controller});

  final CreateVoucherController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final rows = <(String, String)>[
        ('voucher.type'.tr, controller.selectedType?.label ?? '—'),
        ('voucher.payee'.tr, controller.payee.text),
        ('voucher.purpose'.tr, controller.purpose.text),
        ('voucher.method'.tr, controller.method.value),
        ('voucher.category'.tr, controller.category.value),
        (
          'voucher.reference'.tr,
          controller.reference.text.isEmpty ? '—' : controller.reference.text,
        ),
        ('voucher.attachments'.tr, '${controller.attachments.length}'),
      ];

      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Get.find<SessionService>().company.value?.name ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF201E1D),
                  ),
                ),
                const Divider(
                  color: Color(0xFF201E1D),
                  thickness: 2,
                  height: 16,
                ),
                Text(
                  controller.selectedType?.nextNumberPreview ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF605D5D),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  controller.purpose.text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Color(0xFF201E1D),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  Fmt.money(controller.amountValue, controller.currency.value),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    color: Color(0xFF201E1D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.$1.toUpperCase(),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Text(row.$2, style: theme.textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: controller.busy.value
                ? null
                : () => controller.save(submit: false),
            child: Text('voucher.saveDraft'.tr),
          ),
        ],
      );
    });
  }
}
