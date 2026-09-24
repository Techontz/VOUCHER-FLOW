import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../core/theme.dart';
import '../../widgets/design.dart';
import '../shell/shell_page.dart';
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

  String get _title {
    if (!controller.pendingOnly) return 'nav.vouchers'.tr;
    return Get.find<SessionService>().me.isCashier
        ? 'nav.payments'.tr
        : 'nav.approvals'.tr;
  }

  Future<void> _openFilters(BuildContext context) async {
    var picked = controller.status.value;
    final apply = await showVfSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => SheetScaffold(
          title: 'filter.title'.tr,
          trailing: TextButton(
            onPressed: () => setSheet(() => picked = ''),
            child: Text('filter.reset'.tr),
          ),
          children: [
            FieldLabel('filter.status'.tr),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in VoucherListController.statuses.skip(1))
                  FilterPill(
                    label: entry.$2.tr,
                    selected: picked == entry.$1,
                    onTap: () => setSheet(
                      () => picked = picked == entry.$1 ? '' : entry.$1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: Text('filter.apply'.tr),
            ),
          ],
        ),
      ),
    );
    if (apply == true && picked != controller.status.value) {
      controller.setStatus(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();
    final isPayments = controller.pendingOnly && session.me.isCashier;

    return Obx(() {
      final rows = controller.vouchers;
      final loadingFirst = controller.loading.value && rows.isEmpty;
      final failed = controller.error.value != null;

      final header = <Widget>[
        ScreenTitle(
          title: _title,
          trailing: controller.pendingOnly
              ? null
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton.outlined(
                      tooltip: 'filter.title'.tr,
                      style: IconButton.styleFrom(
                        side: BorderSide(color: context.vfLine),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(VfTheme.rMd),
                        ),
                      ),
                      onPressed: () => _openFilters(context),
                      icon: const Icon(Icons.tune, size: 20),
                    ),
                    if (controller.status.value.isNotEmpty)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: context.vfAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (!controller.pendingOnly) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: controller.search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'filter.searchHint'.tr,
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: VoucherListController.statuses.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterPill(
                    label: entry.$2.tr,
                    selected: controller.status.value == entry.$1,
                    onTap: () => controller.setStatus(entry.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];

      Widget body;
      if (loadingFirst) {
        body = const SkeletonList(count: 4);
      } else if (failed && rows.isEmpty) {
        body = ErrorState(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      } else {
        body = RefreshIndicator(
          onRefresh: controller.load,
          child: rows.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 40),
                    _empty(session, isPayments),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: rows.length + 1,
                  itemBuilder: (_, index) {
                    if (index == 0) {
                      return _ListLead(
                        controller: controller,
                        isPayments: isPayments,
                        failed: failed,
                      );
                    }
                    return VoucherCard(
                      voucher: rows[index - 1],
                      onReturn: controller.load,
                    );
                  },
                ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(child: body),
        ],
      );
    });
  }

  Widget _empty(SessionService session, bool isPayments) {
    if (controller.pendingOnly) {
      return EmptyState(
        icon: isPayments
            ? Icons.account_balance_wallet_outlined
            : Icons.done_all_rounded,
        tone: VfTone.ok,
        title: isPayments ? 'pay.nothing'.tr : 'approvals.empty'.tr,
        body: isPayments ? 'pay.nothingBody'.tr : 'approvals.emptyBody'.tr,
        action: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Get.find<ShellController>().index.value = 1,
          child: Text('approvals.seeVouchers'.tr),
        ),
      );
    }
    final filtered =
        controller.query.value.isNotEmpty || controller.status.value.isNotEmpty;
    return EmptyState(
      icon: filtered ? Icons.search_off : Icons.receipt_long_outlined,
      title: filtered ? 'filter.none'.tr : 'voucher.none'.tr,
      body: filtered ? 'filter.noneBody'.tr : 'voucher.noneBody'.tr,
      action: filtered
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => controller.setStatus(''),
              child: Text('filter.clear'.tr),
            )
          : session.me.isSuperAdmin
          ? null
          : FilledButton.icon(
              onPressed: () => Get.toNamed(
                Routes.createVoucher,
              )?.then((_) => controller.load()),
              icon: const Icon(Icons.add, size: 18),
              label: Text('voucher.new'.tr),
            ),
    );
  }
}

/// What sits above the cards: an offline notice when a refresh failed, the
/// cashier's running total, or the approver's reminder of what their step
/// may do.
class _ListLead extends StatelessWidget {
  const _ListLead({
    required this.controller,
    required this.isPayments,
    required this.failed,
  });

  final VoucherListController controller;
  final bool isPayments, failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = controller.vouchers;
    final currencies = rows.map((v) => v.currency).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed) ...[
          NoticeBanner(
            icon: Icons.wifi_off_rounded,
            title: 'state.offlineTitle'.tr,
            body: controller.error.value,
          ),
          const SizedBox(height: 12),
        ],
        if (isPayments) ...[
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('pay.waiting'.tr, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      if (currencies.length == 1)
                        AmountText(
                          amount: rows.fold<double>(0, (s, v) => s + v.amount),
                          currency: currencies.first,
                          size: 22,
                        ),
                    ],
                  ),
                ),
                ToneBadge(
                  label: 'pay.count'.trParams({'n': '${rows.length}'}),
                  tone: VfTone.neutral,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else if (controller.pendingOnly &&
            rows.any((v) => v.actions.sign && !v.currentStepCanApprove)) ...[
          Text('approvals.signOnly'.tr, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
