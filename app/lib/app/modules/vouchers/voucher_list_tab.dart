import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

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
import 'voucher_card.dart';
import 'voucher_form_bits.dart';

/// The register's status pills, in the web's order.
const registerStatuses = [
  ('', 'vouchers.all'),
  ('drafts', 'vouchers.drafts'),
  ('pending', 'vouchers.pending'),
  ('approved', 'vouchers.awaitingPayment'),
  ('paid', 'vouchers.paid'),
  ('rejected', 'vouchers.rejected'),
  ('changes_requested', 'vouchers.changesRequested'),
];

/// The voucher register (web `/vouchers`): search, status pills, filters,
/// the running total, 20 vouchers a page.
class VoucherListController extends GetxController {
  final repo = CreateRepository.to;
  final session = Get.find<SessionService>();

  final result = Rxn<RegisterPage>();
  final loading = true.obs;
  final error = RxnString();
  final page = 1.obs;
  final exporting = RxnString();

  final q = ''.obs;
  final status = ''.obs;
  final kind = ''.obs;
  final departmentId = ''.obs;
  final typeId = ''.obs;
  final from = Rxn<DateTime>();
  final to = Rxn<DateTime>();

  final departments = <Department>[].obs;
  final types = <VoucherTypeOption>[].obs;

  final search = TextEditingController();
  final scroll = ScrollController();
  Timer? _debounce;
  int _request = 0;

  bool get isEmployee => session.me.role == 'employee';
  bool get canCreate => session.me.canCreateVouchers;

  Map<String, dynamic> get filters => {
    'q': q.value.trim(),
    'status': status.value,
    'kind': kind.value,
    'department_id': departmentId.value,
    'voucher_type_id': typeId.value,
    'from': from.value == null ? '' : apiDate(from.value!),
    'to': to.value == null ? '' : apiDate(to.value!),
  };

  bool get hasFilters => filters.values.any((v) => '$v'.isNotEmpty);

  int get activeFilters =>
      [
        kind.value,
        departmentId.value,
        typeId.value,
      ].where((v) => v.isNotEmpty).length +
      (from.value != null ? 1 : 0) +
      (to.value != null ? 1 : 0);

  @override
  void onInit() {
    super.onInit();
    load();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      departments.assignAll(await Get.find<VoucherRepository>().departments());
    } catch (_) {}
    try {
      types.assignAll(await repo.types());
    } catch (_) {}
  }

  /// Opens the register on one status tab — `/vouchers?status=paid` on the web.
  void setStatus(String value) {
    status.value = value;
    _changed();
  }

  void onSearch(String value) {
    q.value = value;
    page.value = 1;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), load);
  }

  void setFilter(RxString field, String value) {
    field.value = value;
    _changed();
  }

  void setDate(Rxn<DateTime> field, DateTime? value) {
    field.value = value;
    _changed();
  }

  void clearFilters() {
    search.clear();
    q.value = '';
    status.value = '';
    kind.value = '';
    departmentId.value = '';
    typeId.value = '';
    from.value = null;
    to.value = null;
    _changed();
  }

  void _changed() {
    page.value = 1;
    load();
  }

  void goToPage(int value) {
    page.value = value;
    load();
    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> load() async {
    final ticket = ++_request;
    loading.value = true;
    error.value = null;
    try {
      final data = await repo.register(filters, page: page.value);
      if (ticket == _request) result.value = data;
    } on ApiException catch (e) {
      if (ticket == _request) error.value = e.message;
    } catch (_) {
      if (ticket == _request) error.value = 'create.offline'.tr;
    } finally {
      if (ticket == _request) loading.value = false;
    }
  }

  /// Downloads exactly the rows on screen, then hands the file to the share
  /// sheet (save to Files, mail, WhatsApp …).
  Future<void> export(String format) async {
    exporting.value = format;
    try {
      final bytes = await repo.exportVouchers(filters, format);
      final date = apiDate(DateTime.now());
      final mime = switch (format) {
        'pdf' => 'application/pdf',
        'csv' => 'text/csv',
        _ =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'vouchflow-vouchers-$date.$format',
          mimeType: mime,
        ),
      ]);
      showToast('vouchers.exportReady'.tr, body: format.toUpperCase());
    } on ApiException catch (e) {
      showToast(
        'vouchers.exportFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'vouchers.exportFailed'.tr,
        body: 'create.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      exporting.value = null;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    search.dispose();
    scroll.dispose();
    super.onClose();
  }
}

class VoucherListTab extends StatelessWidget {
  const VoucherListTab({super.key, required this.controller});

  final VoucherListController controller;

  Future<void> _create() async {
    await Get.toNamed(Routes.createVoucher);
    controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        controller: c.scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          20,
          VfSize.pagePad,
          32,
        ),
        children: [
          VouchFlowPageHeader(
            title: c.isEmployee
                ? 'vouchers.myVouchers'.tr
                : 'vouchers.register'.tr,
            subtitle: c.isEmployee ? 'vouchers.myVouchersSub'.tr : null,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final export = Obx(
                () => VouchFlowButton(
                  label: 'vouchers.exportThisList'.tr,
                  icon: box.maxWidth < 400 && box.maxWidth >= 340 ? null : PhosphorIconsRegular.downloadSimple,
                  trailingIcon: PhosphorIconsRegular.caretDown,
                  variant: VfButtonVariant.secondary,
                  expand: box.maxWidth < 340,
                  loading: c.exporting.value != null,
                  onPressed: () => _exportMenu(context),
                ),
              );
              if (!c.canCreate) {
                return Align(alignment: Alignment.centerLeft, child: export);
              }
              final create = VouchFlowButton(
                label: 'vouchers.createVoucher'.tr,
                icon: PhosphorIconsRegular.plus,
                // Fills the row on a phone, keeps its own width on a tablet.
                expand: box.maxWidth < 600,
                onPressed: _create,
              );
              // Side by side as on the web; stacked on the narrowest phones.
              if (box.maxWidth < 340) {
                return Column(
                  children: [export, const SizedBox(height: 10), create],
                );
              }
              return Row(
                children: [
                  export,
                  const SizedBox(width: 12),
                  if (box.maxWidth < 600) Expanded(child: create) else create,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _FilterCard(controller: c),
          const SizedBox(height: 16),
          _RegisterPanel(controller: c, onCreate: c.canCreate ? _create : null),
        ],
      ),
    );
  }

  void _exportMenu(BuildContext context) {
    final t = context.vf;
    Widget item(IconData icon, String label, String format) => ListTile(
      leading: Icon(icon, color: t.text2),
      title: Text(label, style: VfType.body.copyWith(color: t.text)),
      minTileHeight: 52,
      onTap: () {
        Navigator.of(context).pop();
        controller.export(format);
      },
    );
    showVouchFlowBottomSheet(
      context,
      title: 'vouchers.exportThisList'.tr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(PhosphorIconsRegular.filePdf, 'PDF', 'pdf'),
          item(
            PhosphorIconsRegular.microsoftExcelLogo,
            'vouchers.excel'.tr,
            'xlsx',
          ),
          item(PhosphorIconsRegular.fileCsv, 'CSV', 'csv'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Search, the Filters sheet, "Showing N of M · total" and the status pills.
class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.controller});

  final VoucherListController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return VouchFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowSearchField(
            placeholder: 'vouchers.searchPh'.tr,
            controller: c.search,
            onChanged: c.onSearch,
          ),
          const SizedBox(height: 12),
          Obx(() {
            final r = c.result.value;
            final n = c.activeFilters;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                VouchFlowButton(
                  label: '${'vouchers.filters'.tr}${n > 0 ? ' · $n' : ''}',
                  icon: PhosphorIconsRegular.slidersHorizontal,
                  variant: VfButtonVariant.secondary,
                  onPressed: () => _openFilters(context),
                ),
                Text.rich(
                  TextSpan(
                    text:
                        '${'vouchers.showing'.tr} ${r?.rows.length ?? 0} ${'vouchers.of'.tr} ${r?.total ?? 0}',
                    children: [
                      if (r?.totalAmount != null)
                        TextSpan(
                          text:
                              ' · ${Fmt.money(r!.totalAmount!, r.currency ?? c.session.company.value?.currency ?? 'TZS')}',
                          style: TextStyle(
                            color: t.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  style: VfType.small.copyWith(
                    color: t.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (c.hasFilters)
                  VouchFlowButton(
                    label: 'vouchers.clearFilters'.tr,
                    icon: PhosphorIconsRegular.x,
                    variant: VfButtonVariant.ghost,
                    compact: true,
                    onPressed: c.clearFilters,
                  ),
              ],
            );
          }),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: Obx(() {
              final total = c.result.value?.total;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: registerStatuses.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (value, key) = registerStatuses[i];
                  final selected = c.status.value == value;
                  return Center(
                    child: VouchFlowFilterChip(
                      label: key.tr,
                      selected: selected,
                      count: selected && !c.loading.value ? total : null,
                      onTap: () => c.setStatus(value),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  void _openFilters(BuildContext context) {
    final c = controller;
    showVouchFlowBottomSheet(
      context,
      title: 'vouchers.filters'.tr,
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VouchFlowDropdown<String>(
              key: ValueKey('kind-${c.kind.value}'),
              label: 'vouchers.voucherKind'.tr,
              items: const ['', 'bank', 'cash'],
              value: c.kind.value,
              itemLabel: (v) => switch (v) {
                'bank' => 'vouchers.bankVoucher'.tr,
                'cash' => 'vouchers.cashVoucher'.tr,
                _ => 'vouchers.all'.tr,
              },
              onChanged: (v) => c.setFilter(c.kind, v ?? ''),
            ),
            if (c.departments.isNotEmpty) ...[
              const SizedBox(height: 14),
              VouchFlowDropdown<String>(
                key: ValueKey(
                  'dept-${c.departmentId.value}-${c.departments.length}',
                ),
                label: 'vouchers.department'.tr,
                items: ['', ...c.departments.map((d) => '${d.id}')],
                value: c.departmentId.value,
                itemLabel: (v) => v.isEmpty
                    ? 'vouchers.allDepartments'.tr
                    : c.departments
                              .firstWhereOrNull((d) => '${d.id}' == v)
                              ?.name ??
                          v,
                onChanged: (v) => c.setFilter(c.departmentId, v ?? ''),
              ),
            ],
            const SizedBox(height: 14),
            VouchFlowDropdown<String>(
              key: ValueKey('type-${c.typeId.value}-${c.types.length}'),
              label: 'vouchers.voucherType'.tr,
              items: ['', ...c.types.map((x) => '${x.id}')],
              value: c.typeId.value,
              itemLabel: (v) => v.isEmpty
                  ? 'vouchers.allTypes'.tr
                  : c.types.firstWhereOrNull((x) => '${x.id}' == v)?.label ?? v,
              onChanged: (v) => c.setFilter(c.typeId, v ?? ''),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: VfDateInput(
                    label: 'vouchers.from'.tr,
                    value: c.from.value,
                    placeholder: 'vouchers.anyDate'.tr,
                    clearable: true,
                    onChanged: (d) => c.setDate(c.from, d),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: VfDateInput(
                    label: 'vouchers.to'.tr,
                    value: c.to.value,
                    placeholder: 'vouchers.anyDate'.tr,
                    clearable: true,
                    onChanged: (d) => c.setDate(c.to, d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        VouchFlowButton(
          label: 'vouchers.clearFilters'.tr,
          icon: PhosphorIconsRegular.x,
          variant: VfButtonVariant.secondary,
          onPressed: () {
            c.kind.value = '';
            c.departmentId.value = '';
            c.typeId.value = '';
            c.from.value = null;
            c.to.value = null;
            c._changed();
          },
        ),
        Builder(
          builder: (ctx) => VouchFlowButton(
            label: 'vouchers.done'.tr,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ),
      ],
    );
  }
}

/// The register itself: rows in one panel, then the pager.
class _RegisterPanel extends StatelessWidget {
  const _RegisterPanel({required this.controller, this.onCreate});

  final VoucherListController controller;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return Obx(() {
      final r = c.result.value;
      final rows = r?.rows ?? const <RegisterRow>[];

      if (c.error.value != null && rows.isEmpty) {
        return VouchFlowErrorState(
          message: c.error.value!,
          onRetry: c.load,
          retryLabel: 'vouchers.retry'.tr,
        );
      }
      if (r == null) {
        return const VouchFlowLoadingState(rows: 5, rowHeight: 128);
      }

      if (rows.isEmpty) {
        final filtered = c.hasFilters;
        return VouchFlowCard(
          padding: EdgeInsets.zero,
          child: VouchFlowEmptyState(
            title: filtered
                ? 'vouchers.noResults'.tr
                : 'vouchers.noVouchersYet'.tr,
            body: filtered ? null : 'vouchers.noVouchersBody'.tr,
            actionLabel: filtered
                ? 'vouchers.clearFilters'.tr
                : (onCreate != null ? 'vouchers.createVoucher'.tr : null),
            onAction: filtered ? c.clearFilters : onCreate,
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.error.value != null) ...[
            VouchFlowAlert(
              message: c.error.value!,
              tone: VfTone.bad,
              icon: PhosphorIconsRegular.warningCircle,
            ),
            const SizedBox(height: 12),
          ],
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: c.loading.value ? .55 : 1,
            child: VouchFlowCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: t.border),
                    VoucherRow(
                      voucher: rows[i].voucher,
                      row: rows[i],
                      history: true,
                      showCta: false,
                      onReturn: c.load,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (r.lastPage > 1) ...[
            const SizedBox(height: 14),
            _Pager(
              page: r.currentPage,
              lastPage: r.lastPage,
              total: r.total,
              onChange: c.goToPage,
            ),
          ],
        ],
      );
    });
  }
}

/// The web's `Pagination`: "Showing 65 · Page 1 of 4", Back and Next.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onChange,
  });

  final int page, lastPage, total;
  final ValueChanged<int> onChange;

  static Widget _dim(bool off, Widget child) =>
      Opacity(opacity: off ? .45 : 1, child: child);

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${'vouchers.showing'.tr} $total · ${'vouchers.page'.tr} $page ${'vouchers.of'.tr} $lastPage',
            style: VfType.small.copyWith(color: t.muted),
          ),
        ),
        const SizedBox(width: 8),
        _dim(
          page <= 1,
          VouchFlowButton(
            label: 'vouchers.back'.tr,
            icon: PhosphorIconsRegular.caretLeft,
            variant: VfButtonVariant.secondary,
            compact: true,
            onPressed: page <= 1 ? null : () => onChange(page - 1),
          ),
        ),
        const SizedBox(width: 8),
        _dim(
          page >= lastPage,
          VouchFlowButton(
            label: 'vouchers.next'.tr,
            trailingIcon: PhosphorIconsRegular.caretRight,
            variant: VfButtonVariant.secondary,
            compact: true,
            onPressed: page >= lastPage ? null : () => onChange(page + 1),
          ),
        ),
      ],
    );
  }
}
