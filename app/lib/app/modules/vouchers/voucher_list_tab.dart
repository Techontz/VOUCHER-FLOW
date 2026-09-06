import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import 'voucher_card.dart';

class VoucherListController extends GetxController {
  VoucherListController({this.pendingOnly = false});

  final bool pendingOnly;
  final repo = Get.find<VoucherRepository>();

  final vouchers = <Voucher>[].obs;
  final loading = true.obs;
  final error = RxnString();
  final status = ''.obs;
  final query = ''.obs;

  Timer? _debounce;

  static const statuses = [
    ('', 'filter.all'),
    ('pending', 'filter.pending'),
    ('approved', 'filter.approved'),
    ('rejected', 'filter.rejected'),
    ('drafts', 'filter.drafts'),
  ];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void setStatus(String value) {
    status.value = value;
    load();
  }

  void search(String value) {
    query.value = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), load);
  }

  Future<void> load() async {
    error.value = null;
    try {
      vouchers.value = pendingOnly
          ? await repo.pending()
          : await repo.list(
              status: status.value.isEmpty ? null : status.value,
              query: query.value.trim().isEmpty ? null : query.value.trim(),
            );
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

class VoucherListTab extends StatelessWidget {
  const VoucherListTab({super.key, required this.controller});

  final VoucherListController controller;

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();

    return Obx(() {
      if (controller.loading.value && controller.vouchers.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value != null && controller.vouchers.isEmpty) {
        return ErrorView(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      }

      final rows = controller.vouchers;

      return Column(
        children: [
          if (!controller.pendingOnly) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: TextField(
                onChanged: controller.search,
                decoration: InputDecoration(
                  hintText: 'action.search'.tr,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: VoucherListController.statuses.map((entry) {
                  final selected = controller.status.value == entry.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2.tr),
                      selected: selected,
                      onSelected: (_) => controller.setStatus(entry.$1),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (controller.pendingOnly && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Text(
                'approvals.signOnly'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.load,
              child: rows.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 60),
                        EmptyView(
                          icon: controller.pendingOnly
                              ? Icons.check_circle_outline
                              : Icons.inbox_outlined,
                          title: controller.pendingOnly
                              ? 'approvals.empty'.tr
                              : (controller.query.value.isEmpty &&
                                        controller.status.value.isEmpty
                                    ? 'voucher.none'.tr
                                    : 'filter.none'.tr),
                          body: controller.pendingOnly
                              ? 'approvals.emptyBody'.tr
                              : 'voucher.noneBody'.tr,
                          action:
                              controller.pendingOnly || session.me.isSuperAdmin
                              ? null
                              : FilledButton(
                                  onPressed: () => Get.toNamed(
                                    Routes.createVoucher,
                                  )?.then((_) => controller.load()),
                                  child: Text('voucher.create'.tr),
                                ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                      itemCount: rows.length,
                      itemBuilder: (_, index) => VoucherCard(
                        voucher: rows[index],
                        onReturn: controller.load,
                      ),
                    ),
            ),
          ),
        ],
      );
    });
  }
}
