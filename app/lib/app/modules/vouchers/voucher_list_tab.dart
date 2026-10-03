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

  static const _gutter = EdgeInsets.symmetric(horizontal: VfSize.pagePad);

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        controller: c.scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        children: [
          Padding(
            padding: _gutter,
            child: Text(
              c.isEmployee
                  ? 'vouchers.myVouchers'.tr
                  : 'vouchers.register'.tr,
              style: VfType.pageTitle.copyWith(color: t.text),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: _gutter,
            child: Row(
              children: [
                Expanded(child: _PillSearch(controller: c)),
                const SizedBox(width: 10),
                Obx(
                  () => _RoundButton(
                    icon: PhosphorIconsRegular.slidersHorizontal,
                    tooltip: 'vouchers.filters'.tr,
                    badge: c.activeFilters,
                    onTap: () => _openFilters(context),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(
                  () => _RoundButton(
                    icon: PhosphorIconsRegular.export,
                    tooltip: 'vouchers.export'.tr,
                    loading: c.exporting.value != null,
                    onTap: () => _exportMenu(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _StatusChips(controller: c),
          Obx(() {
            final r = c.result.value;
            if (r == null || r.rows.isEmpty) return const SizedBox(height: 14);
            final money = r.totalAmount == null
                ? null
                : Fmt.money(
                    r.totalAmount!,
                    r.currency ?? c.session.company.value?.currency ?? 'TZS',
                  );
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                VfSize.pagePad + 4,
                12,
                VfSize.pagePad + 4,
                10,
              ),
              child: Text(
                [
                  'vouchers.count'.trParams({
                    'shown': '${r.rows.length}',
                    'total': '${r.total}',
                  }),
                  ?money,
                ].join(' · '),
                style: VfType.meta.copyWith(
                  color: t.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),
          Padding(
            padding: _gutter,
            child: _RegisterPanel(
              controller: c,
              onCreate: c.canCreate ? _create : null,
            ),
          ),
        ],
      ),
    );
  }

  /// PDF, Excel or CSV of exactly the rows the filters select.
  void _exportMenu(BuildContext context) {
    final t = context.vf;
    Widget item(IconData icon, String label, String format) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: t.primarySoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 21, color: t.primaryText),
      ),
      title: Text(label, style: VfType.bodyStrong.copyWith(color: t.text)),
      trailing: Icon(PhosphorIconsRegular.caretRight, size: 16, color: t.faint),
      minTileHeight: 60,
      onTap: () {
        Navigator.of(context).pop();
        controller.export(format);
      },
    );
    showVouchFlowBottomSheet(
      context,
      title: 'vouchers.export'.tr,
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

/// A pill search bar: filled, borderless, a magnifier and a clear button.
class _PillSearch extends StatefulWidget {
  const _PillSearch({required this.controller});

  final VoucherListController controller;

  @override
  State<_PillSearch> createState() => _PillSearchState();
}

class _PillSearchState extends State<_PillSearch> {
  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = widget.controller;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VfSize.radiusPill),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 48,
      child: TextField(
        controller: c.search,
        onChanged: (v) {
          setState(() {});
          c.onSearch(v);
        },
        textInputAction: TextInputAction.search,
        style: VfType.body.copyWith(color: t.text),
        cursorColor: t.primary,
        decoration: InputDecoration(
          filled: true,
          fillColor: t.surface3,
          hintText: 'vouchers.searchPh'.tr,
          hintMaxLines: 1,
          hintStyle: VfType.body.copyWith(color: t.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          isDense: true,
          border: pill,
          enabledBorder: pill,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(VfSize.radiusPill),
            borderSide: BorderSide(color: t.primary, width: 1.5),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              PhosphorIconsRegular.magnifyingGlass,
              size: 19,
              color: t.muted,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: c.search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  icon: Icon(PhosphorIconsBold.x, size: 14, color: t.muted),
                  onPressed: () {
                    c.search.clear();
                    setState(() {});
                    c.onSearch('');
                  },
                ),
        ),
      ),
    );
  }
}

/// A 48px round icon button beside the search bar, with a count badge.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: badge > 0 ? t.primarySoft : t.surface3,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: loading ? null : onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.primary,
                          ),
                        )
                      : Icon(
                          icon,
                          size: 20,
                          color: badge > 0 ? t.primaryText : t.text,
                          semanticLabel: tooltip,
                        ),
                ),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 19),
                height: 19,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(VfSize.radiusPill),
                  border: Border.all(color: t.background, width: 2),
                ),
                child: Text(
                  '$badge',
                  style: VfType.meta.copyWith(
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The status chips in one swipeable row; a Clear chip leads while any
/// filter is on.
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.controller});

  final VoucherListController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    return SizedBox(
      height: 42,
      child: Obx(() {
        final total = c.result.value?.total;
        final clear = c.hasFilters;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: VfSize.pagePad),
          itemCount: registerStatuses.length + (clear ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (clear && i == 0) {
              return Center(
                child: Tooltip(
                  message: 'vouchers.clearFilters'.tr,
                  child: Material(
                    color: t.dangerSoft,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: c.clearFilters,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          PhosphorIconsBold.x,
                          size: 15,
                          color: t.dangerStrong,
                          semanticLabel: 'vouchers.clearFilters'.tr,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            final (value, key) = registerStatuses[i - (clear ? 1 : 0)];
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
    );
  }
}

/// The register itself: rows grouped in one rounded card, then the pager.
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
        return const VouchFlowLoadingState(rows: 6, rowHeight: 72);
      }

      if (rows.isEmpty) {
        final filtered = c.hasFilters;
        return VouchFlowCard(
          padding: EdgeInsets.zero,
          radius: VfSize.radiusXl,
          child: VouchFlowEmptyState(
            icon: filtered
                ? PhosphorIconsRegular.funnelSimple
                : PhosphorIconsRegular.receipt,
            title: filtered
                ? 'vouchers.noResults'.tr
                : 'vouchers.noVouchersYet'.tr,
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
              radius: VfSize.radiusXl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 70,
                        endIndent: 14,
                        color: t.border.withValues(alpha: t.isDark ? 1 : .7),
                      ),
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
            const SizedBox(height: 16),
            _Pager(
              page: r.currentPage,
              lastPage: r.lastPage,
              onChange: c.goToPage,
            ),
          ],
        ],
      );
    });
  }
}

/// Round back and next buttons around "2 / 4".
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.lastPage,
    required this.onChange,
  });

  final int page, lastPage;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget arrow(IconData icon, String tip, int? to) => Opacity(
      opacity: to == null ? .4 : 1,
      child: Tooltip(
        message: tip,
        child: Material(
          color: t.surface3,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: to == null ? null : () => onChange(to),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 18, color: t.text, semanticLabel: tip),
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(
          PhosphorIconsBold.caretLeft,
          'vouchers.back'.tr,
          page > 1 ? page - 1 : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            '$page / $lastPage',
            style: VfType.bodyStrong.copyWith(
              color: t.text2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        arrow(
          PhosphorIconsBold.caretRight,
          'vouchers.next'.tr,
          page < lastPage ? page + 1 : null,
        ),
      ],
    );
  }
}
