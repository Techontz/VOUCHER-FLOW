import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';

/// Whether a queued voucher can be approved from the list: an approving step
/// that is ready, or one the approver's saved signature can sign first.
bool bulkEligible(Voucher v) =>
    v.actions.approve || (v.actions.sign && v.currentStepCanApprove);

class BulkApproveController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final queue = <Voucher>[].obs;
  final selected = <int>{}.obs;
  final loading = true.obs;
  final busy = false.obs;
  final reviewed = false.obs;
  final comment = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    comment.dispose();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      queue.assignAll((await repo.pending()).where(bulkEligible));
      selected.removeWhere((id) => !queue.any((v) => v.id == id));
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } finally {
      loading.value = false;
    }
  }

  void toggle(int id) =>
      selected.contains(id) ? selected.remove(id) : selected.add(id);

  void toggleAll() => selected.length == queue.length
      ? selected.clear()
      : selected.addAll(queue.map((v) => v.id));

  double get total => queue
      .where((v) => selected.contains(v.id))
      .fold(0, (sum, v) => sum + v.amount);

  Future<void> approve() async {
    busy.value = true;
    try {
      final result = await repo.bulkApprove(
        selected.toList(),
        comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
      );
      final approved = (result['approved'] as List? ?? const []).length;
      final skipped = (result['skipped'] as List? ?? const []);
      showToast(
        'bulk.done'.trParams({'count': '$approved'}),
        body: skipped.isEmpty
            ? null
            : 'bulk.skipped'.trParams({'count': '${skipped.length}'}),
        kind: skipped.isEmpty ? ToastKind.ok : ToastKind.warn,
      );
      selected.clear();
      reviewed.value = false;
      comment.clear();
      await session.refreshUnread();
      await load();
    } on ApiException catch (e) {
      showToast('state.error'.tr, body: e.message, kind: ToastKind.bad);
    } finally {
      busy.value = false;
    }
  }
}

class BulkApprovePage extends StatelessWidget {
  const BulkApprovePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(BulkApproveController());
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('bulk.title'.tr)),
      body: Obx(() {
        if (c.loading.value && c.queue.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (c.queue.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('bulk.none'.tr, textAlign: TextAlign.center),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              Text('bulk.intro'.tr, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: c.selected.length == c.queue.length,
                onChanged: (_) => c.toggleAll(),
                title: Text('bulk.selectAll'.tr),
              ),
              const Divider(height: 1),
              for (final v in c.queue)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.selected.contains(v.id),
                  onChanged: (_) => c.toggle(v.id),
                  title: Text(
                    v.purpose,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${v.number} · ${v.amountText}\n${v.payee}',
                    style: theme.textTheme.bodySmall,
                  ),
                  isThreeLine: true,
                  secondary: IconButton(
                    tooltip: 'bulk.open'.tr,
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: () async {
                      await Get.toNamed(Routes.voucher, arguments: v.id);
                      await c.load();
                    },
                  ),
                ),
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (c.selected.isEmpty) return const SizedBox.shrink();
        final count = c.selected.length;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: c.busy.value ? null : () => _confirm(context, c),
              icon: const Icon(Icons.verified_outlined),
              label: Text('bulk.approveN'.trParams({'count': '$count'})),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _confirm(BuildContext context, BulkApproveController c) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'bulk.confirmTitle'.trParams({'count': '${c.selected.length}'}),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'bulk.confirmBody'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c.comment,
                decoration: InputDecoration(labelText: 'bulk.comment'.tr),
                maxLines: 2,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: c.reviewed.value,
                onChanged: (v) => c.reviewed.value = v ?? false,
                title: Text('bulk.reviewed'.tr),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: !c.reviewed.value || c.busy.value
                    ? null
                    : () async {
                        await c.approve();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                child: Text(
                  'bulk.approveN'.trParams({'count': '${c.selected.length}'}),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
