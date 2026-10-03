import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models/report_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/report_repository.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../approvals/list_bits.dart';
import 'report_filter_sheet.dart';
import 'report_format.dart';
import 'report_row_card.dart';
import 'reports_controller.dart';

/// Reports — the web's /reports: the reports this role may run, the reach
/// ("Company-wide" or its departments), filters, the summary figures, the
/// rows, and export to PDF, Excel or CSV. The server applies the same
/// visibility rules to the screen and to every export.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.repository});

  /// For tests; the app uses the shared [ReportRepository].
  final ReportRepository? repository;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final ReportsController c = ReportsController(
    widget.repository ?? ReportRepository.instance,
  )..start();
  final _search = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _sw => Get.locale?.languageCode == 'sw';

  Future<void> _export(String format, {bool print = false}) async {
    if (c.exporting.value != null) return;
    c.exporting.value = print ? 'print' : format;
    try {
      final bytes = await c.repo.export(c.active.value, c.params, format);
      final name = c.fileName(format);
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      } else {
        await Share.shareXFiles([
          XFile.fromData(
            bytes,
            name: name,
            mimeType: switch (format) {
              'pdf' => 'application/pdf',
              'xlsx' =>
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              _ => 'text/csv',
            },
          ),
        ], subject: name);
        showToast('reports.exportReady'.tr, body: format.toUpperCase());
      }
    } on ApiException catch (e) {
      showToast(
        'reports.exportFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (e) {
      showToast('reports.exportFailed'.tr, body: '$e', kind: ToastKind.bad);
    } finally {
      c.exporting.value = null;
    }
  }

  /// Export and print, as a sheet of choices.
  Future<void> _openExport() async {
    final choice = await showVouchFlowBottomSheet<(String, bool)>(
      context,
      title: 'reports.export'.tr,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Builder(
          builder: (ctx) {
            final t = ctx.vf;
            Widget row(
              IconData icon,
              String label,
              (Color, Color) tint,
              (String, bool) value,
            ) {
              final (fg, bg) = tint;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: AppIconTile(icon: icon, fg: fg, bg: bg, size: 38),
                title: Text(
                  label,
                  style: VfType.body.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(value),
              );
            }

            return AppListGroup(
              indent: 66,
              children: [
                row(
                  PhosphorIconsFill.filePdf,
                  'PDF',
                  (t.dangerStrong, t.dangerSoft),
                  ('pdf', false),
                ),
                // Excel needs the live server, as on the web.
                if (!VfConfig.useMock)
                  row(
                    PhosphorIconsFill.microsoftExcelLogo,
                    'Excel',
                    (t.successStrong, t.successSoft),
                    ('xlsx', false),
                  ),
                row(
                  PhosphorIconsFill.fileCsv,
                  'CSV',
                  (t.infoStrong, t.infoSoft),
                  ('csv', false),
                ),
                row(
                  PhosphorIconsFill.printer,
                  'reports.print'.tr,
                  (t.text2, t.surface3),
                  ('pdf', true),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (choice != null) await _export(choice.$1, print: choice.$2);
  }

  Future<void> _openFilters() async {
    final values = await showReportFilterSheet(context, c);
    if (values != null) c.applyFilters(values);
  }

  void _clearAll() {
    _search.clear();
    c.clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    // The server words some cells, so a language change reloads the report.
    final locale = Get.locale?.languageCode ?? 'en';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.localeChanged(locale);
    });
    return Obx(() {
      final t = context.vf;
      final r = c.result.value;
      final err = c.error.value;
      final loading = c.loading.value;
      final busy = c.exporting.value;
      final scope = c.scope.value;
      final rows = err == null && r != null ? r.rows : const <List<Object?>>[];
      final count = c.sheetFilterCount;

      final head = <Widget>[
        AppScreenTitle(
          title: 'reports.title'.tr,
          trailing: [
            busy != null
                ? SizedBox(
                    width: 42,
                    height: 42,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.text2,
                        ),
                      ),
                    ),
                  )
                : VfBarButton(
                    icon: PhosphorIconsRegular.export,
                    tooltip: 'reports.export'.tr,
                    onPressed: _openExport,
                  ),
          ],
        ),
        if (scope != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                scope.level == 'company'
                    ? PhosphorIconsRegular.eye
                    : PhosphorIconsRegular.lockKey,
                size: 15,
                color: t.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scope.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.small.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (c.kinds.isNotEmpty) ...[
          _KindStrip(controller: c, sw: _sw),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            if (c.shows('q'))
              Expanded(
                child: VouchFlowSearchField(
                  controller: _search,
                  placeholder: 'reports.searchPh'.tr,
                  onChanged: (v) => c.setFilter('q', v),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 10),
            _FilterButton(count: count, onTap: _openFilters),
          ],
        ),
        if (c.hasFilters) ...[
          const SizedBox(height: 10),
          _ActiveFilters(controller: c, sw: _sw, onClear: _clearAll),
        ],
        const SizedBox(height: 16),
        if (loading && r != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VfSize.radiusPill),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: t.primary,
                backgroundColor: t.surface3,
              ),
            ),
          ),
        if (r != null && err == null) ...[
          _Figures(
            result: r,
            money: c.config.money,
            cash: c.active.value == 'cash',
            sw: _sw,
          ),
          const SizedBox(height: 16),
        ],
        if (err != null)
          VouchFlowErrorState(
            message: err,
            onRetry: () => c.reload(force: true),
            retryLabel: 'action.retry'.tr,
          )
        else if (loading && r == null)
          const VouchFlowLoadingState(rows: 6, rowHeight: 72)
        else if (r != null && r.rows.isEmpty)
          VouchFlowCard(
            radius: VfSize.radiusXl,
            padding: EdgeInsets.zero,
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.chartLine,
              title: 'reports.noResults'.tr,
            ),
          ),
      ];

      final icon = ReportFormat.icon(c.activeKind?.icon ?? '');
      return RefreshIndicator(
        onRefresh: c.refreshAll,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            VfSize.pagePad,
            16,
            VfSize.pagePad,
            32,
          ),
          itemCount: head.length + rows.length,
          itemBuilder: (context, i) {
            if (i < head.length) return head[i];
            final k = i - head.length;
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: loading ? .6 : 1,
              child: ReportRowCard(
                headings: r!.headings,
                row: rows[k],
                sw: _sw,
                icon: icon,
                first: k == 0,
                last: k == rows.length - 1,
              ),
            );
          },
        ),
      );
    });
  }
}

/// The reports this role may run, as a sideways strip of pills.
class _KindStrip extends StatefulWidget {
  const _KindStrip({required this.controller, required this.sw});

  final ReportsController controller;
  final bool sw;

  @override
  State<_KindStrip> createState() => _KindStripState();
}

class _KindStripState extends State<_KindStrip> {
  final _keys = <String, GlobalKey>{};

  void _select(String key) {
    widget.controller.setActive(key);
    final ctx = _keys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: .5,
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Semantics(
      label: 'reports.youMayRun'.tr,
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Obx(
          () => Row(
            children: [
              for (final kind in c.kinds)
                Padding(
                  key: _keys.putIfAbsent(kind.key, GlobalKey.new),
                  padding: const EdgeInsets.only(right: 8),
                  child: _KindPill(
                    icon: ReportFormat.icon(kind.icon),
                    label: kind.title(widget.sw),
                    selected: kind.key == c.active.value,
                    onTap: () => _select(kind.key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? t.primary : t.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? t.primary : t.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: selected ? Colors.white : t.muted),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: VfType.label.copyWith(
                    color: selected ? Colors.white : t.text2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

/// The filters button: a square icon with how many sheet filters are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final on = count > 0;
    return Tooltip(
      message: 'reports.filters'.tr,
      child: Semantics(
        button: true,
        label: '${'reports.filters'.tr}${on ? ' ($count)' : ''}',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: on ? t.primarySoft : t.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(VfSize.radiusL),
                side: BorderSide(color: on ? t.primaryBorder : t.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: VfSize.controlH + 4,
                  height: VfSize.controlH + 4,
                  child: Icon(
                    PhosphorIconsRegular.slidersHorizontal,
                    size: 21,
                    color: on ? t.primaryText : t.text,
                  ),
                ),
              ),
            ),
            if (on)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(VfSize.radiusPill),
                    border: Border.all(color: t.background, width: 2),
                  ),
                  child: Text(
                    '$count',
                    style: VfType.meta.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What is narrowing the report, each removable, and Clear.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.controller,
    required this.sw,
    required this.onClear,
  });

  final ReportsController controller;
  final bool sw;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    final p = c.params;
    final chips = <Widget>[];
    for (final key in reportFilterKeys) {
      final v = p[key];
      if (v == null || key == 'q') continue;
      chips.add(
        _Chip(
          label: reportFilterValueLabel(c, key, v, sw: sw),
          onRemove: () => c.setFilter(key, ''),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips,
        TextButton(
          onPressed: onClear,
          child: Text(
            'reports.clear'.tr,
            style: VfType.label.copyWith(
              color: t.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(
                fontSize: 13,
                color: t.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'action.remove'.tr,
              onPressed: onRemove,
              icon: Icon(PhosphorIconsBold.x, size: 12, color: t.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary figures as compact tiles.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.result,
    required this.money,
    required this.cash,
    required this.sw,
  });

  final ReportResult result;
  final bool money, cash, sw;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = result.summary;
    final word = 'reports.vouchersWord'.tr;
    String n(int? v) =>
        '${NumberFormat.decimalPattern('en_US').format(v ?? 0)} $word';
    final generated = ReportFormat.date(result.generatedAt?.toLocal(), sw: sw);
    final ok = (t.successStrong, t.successSoft);
    final warn = (t.warningStrong, t.warningSoft);
    final info = (t.infoStrong, t.infoSoft);

    final stats = <AppStat>[
      if (money && cash) ...[
        AppStat(
          'reports.paidInCash'.tr,
          s.cashTotalText ?? s.paidTotalText ?? '—',
          sub: n(s.cashCount ?? s.paidCount),
          icon: PhosphorIconsFill.money,
          tint: ok,
        ),
        AppStat(
          'reports.outstanding'.tr,
          s.outstandingTotalText ?? '—',
          sub: n(s.outstandingCount),
          icon: PhosphorIconsFill.hourglassMedium,
          tint: warn,
        ),
        AppStat(
          'reports.amount'.tr,
          s.totalText,
          sub: n(s.count),
          icon: PhosphorIconsFill.wallet,
        ),
      ] else if (money) ...[
        AppStat(
          'reports.paidByBank'.tr,
          s.bankTotalText ?? '—',
          sub: n(s.bankCount),
          icon: PhosphorIconsFill.bank,
          tint: info,
        ),
        AppStat(
          'reports.paidInCash'.tr,
          s.cashTotalText ?? '—',
          sub: n(s.cashCount),
          icon: PhosphorIconsFill.money,
          tint: ok,
        ),
        AppStat(
          'reports.outstanding'.tr,
          s.outstandingTotalText ?? '—',
          sub: n(s.outstandingCount),
          icon: PhosphorIconsFill.hourglassMedium,
          tint: warn,
        ),
      ] else ...[
        AppStat(
          'reports.vouchers'.tr,
          NumberFormat.decimalPattern('en_US').format(s.count),
          icon: PhosphorIconsFill.receipt,
        ),
        AppStat(
          'reports.amount'.tr,
          s.totalText,
          icon: PhosphorIconsFill.wallet,
          tint: info,
        ),
        AppStat(
          'reports.awaitingPayment'.tr,
          s.approvedTotalText,
          icon: PhosphorIconsFill.hourglassMedium,
          tint: warn,
        ),
      ],
      AppStat(
        'reports.generated'.tr,
        generated,
        icon: PhosphorIconsFill.calendarBlank,
        tint: (t.text2, t.surface3),
      ),
    ];
    return AppStatStrip(stats: stats);
  }
}
