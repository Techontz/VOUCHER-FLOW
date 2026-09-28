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
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 720;
        return Obx(() {
          final r = c.result.value;
          final err = c.error.value;
          final loading = c.loading.value;
          final rows = err == null && r != null
              ? r.rows
              : const <List<Object?>>[];
          final perLine = wide ? 2 : 1;
          final lines = (rows.length / perLine).ceil();

          final head = <Widget>[
            VouchFlowPageHeader(
              title: 'reports.title'.tr,
              subtitle: 'reports.sub'.tr,
            ),
            const SizedBox(height: 18),
            if (c.kinds.isNotEmpty) ...[
              _KindStrip(controller: c, sw: _sw),
              const SizedBox(height: 14),
            ],
            _ReportPanel(
              controller: c,
              sw: _sw,
              wide: wide,
              search: _search,
              onExport: _export,
              onFilters: _openFilters,
              onClear: _clearAll,
            ),
            const SizedBox(height: 14),
            if (err != null)
              VouchFlowErrorState(
                message: err,
                onRetry: () => c.reload(force: true),
                retryLabel: 'action.retry'.tr,
              )
            else if (loading && r == null)
              const VouchFlowLoadingState(rows: 6, rowHeight: 120)
            else if (r != null && r.rows.isEmpty)
              VouchFlowCard(
                padding: EdgeInsets.zero,
                child: VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.chartLine,
                  title: 'reports.noResults'.tr,
                ),
              ),
          ];

          return RefreshIndicator(
            onRefresh: c.refreshAll,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                VfSize.pagePad,
                20,
                VfSize.pagePad,
                32,
              ),
              itemCount: head.length + lines,
              itemBuilder: (context, i) {
                if (i < head.length) return head[i];
                final line = i - head.length;
                final start = line * perLine;
                final cards = [
                  for (var k = start; k < start + perLine; k++)
                    k < rows.length
                        ? ReportRowCard(
                            headings: r!.headings,
                            row: rows[k],
                            sw: _sw,
                          )
                        : const SizedBox.shrink(),
                ];
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: loading ? .6 : 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: VfSize.gap),
                    child: perLine == 1
                        ? cards.first
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var k = 0; k < cards.length; k++) ...[
                                if (k > 0) const SizedBox(width: VfSize.gap),
                                Expanded(child: cards[k]),
                              ],
                            ],
                          ),
                  ),
                );
              },
            ),
          );
        });
      },
    );
  }
}

/// The reports this role may run, as the web's scrolling strip on a phone.
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
    final t = context.vf;
    final c = widget.controller;
    return Semantics(
      label: 'reports.youMayRun'.tr,
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          border: Border.all(color: t.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(6),
          child: Obx(
            () => Row(
              children: [
                for (final kind in c.kinds)
                  Padding(
                    key: _keys.putIfAbsent(kind.key, GlobalKey.new),
                    padding: const EdgeInsets.only(right: 2),
                    child: _KindButton(
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
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
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
        color: selected ? t.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(VfSize.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusM),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? t.primaryText : t.faint),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: VfType.bodyStrong.copyWith(
                    color: selected ? t.primaryText : t.text,
                    height: 1.2,
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

/// The report's panel: title and reach, export, the filters, the date hint
/// and the summary figures — the web's `.vf-panel` head over the table.
class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.controller,
    required this.sw,
    required this.wide,
    required this.search,
    required this.onExport,
    required this.onFilters,
    required this.onClear,
  });

  final ReportsController controller;
  final bool sw, wide;
  final TextEditingController search;
  final Future<void> Function(String format, {bool print}) onExport;
  final VoidCallback onFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final t = context.vf;
    final c = controller;
    final kind = c.activeKind;
    final scope = c.scope.value;
    final config = c.config;
    final busy = c.exporting.value;
    final hint = config.money
        ? 'reports.hintMoney'.tr
        : config.status == 'payment'
        ? 'reports.hintApproved'.tr
        : 'reports.hintVoucher'.tr;
    final r = c.result.value;
    final count = c.sheetFilterCount;

    Widget exportButton(String format, String label, IconData icon) =>
        VouchFlowButton(
          label: label,
          icon: icon,
          compact: true,
          variant: VfButtonVariant.secondary,
          loading: busy == format,
          onPressed: busy != null ? null : () => onExport(format),
        );

    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Head: which report, how far it reaches, and export.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind?.title(sw) ?? 'reports.title'.tr,
                  style: VfType.sectionTitle.copyWith(color: t.text),
                ),
                if (kind != null && kind.body(sw).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    kind.body(sw),
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ],
                if (scope != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        scope.level == 'company'
                            ? PhosphorIconsRegular.eye
                            : PhosphorIconsRegular.lockKey,
                        size: 15,
                        color: t.text2,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          scope.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    exportButton('pdf', 'PDF', PhosphorIconsRegular.filePdf),
                    // Excel needs the live server, as on the web.
                    if (!VfConfig.useMock)
                      exportButton(
                        'xlsx',
                        'Excel',
                        PhosphorIconsRegular.microsoftExcelLogo,
                      ),
                    exportButton('csv', 'CSV', PhosphorIconsRegular.fileCsv),
                    _PrintButton(
                      busy: busy == 'print',
                      onPressed: busy != null
                          ? null
                          : () => onExport('pdf', print: true),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filters: search in reach, the rest in a sheet.
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (c.shows('q')) ...[
                      Expanded(
                        child: VouchFlowSearchField(
                          controller: search,
                          placeholder: 'reports.searchPh'.tr,
                          onChanged: (v) => c.setFilter('q', v),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (c.shows('q'))
                      _FilterButton(count: count, onTap: onFilters)
                    else
                      Expanded(
                        child: _FilterButton(count: count, onTap: onFilters),
                      ),
                  ],
                ),
                if (c.hasFilters) ...[
                  const SizedBox(height: 10),
                  _ActiveFilters(
                    controller: c,
                    sw: sw,
                    onClear: onClear,
                    search: search,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        PhosphorIconsRegular.info,
                        size: 15,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hint,
                        style: VfType.small.copyWith(color: t.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (c.loading.value && r != null)
            LinearProgressIndicator(
              minHeight: 2,
              color: t.primary,
              backgroundColor: Colors.transparent,
            ),

          if (r != null && c.error.value == null)
            _Figures(
              result: r,
              money: config.money,
              cash: c.active.value == 'cash',
              sw: sw,
              wide: wide,
            ),
        ],
      ),
    );
  }
}

/// The Filters button, with how many sheet filters are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final on = count > 0;
    final button = Material(
      color: on ? t.primarySoft : t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        side: BorderSide(color: on ? t.primaryBorder : t.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: VfSize.controlH + 4,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.funnelSimple,
                size: 18,
                color: on ? t.primaryText : t.text,
              ),
              const SizedBox(width: 8),
              Text(
                'reports.filters'.tr,
                style: VfType.bodyStrong.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: on ? t.primaryText : t.text,
                ),
              ),
              if (on) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(VfSize.radiusPill),
                  ),
                  child: Text(
                    '$count',
                    style: VfType.meta.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '${'reports.filters'.tr}${on ? ' ($count)' : ''}',
      excludeSemantics: true,
      child: button,
    );
  }
}

/// What is narrowing the report, each removable, and Clear.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.controller,
    required this.sw,
    required this.onClear,
    required this.search,
  });

  final ReportsController controller;
  final bool sw;
  final VoidCallback onClear;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
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
        VouchFlowButton(
          label: 'reports.clear'.tr,
          icon: PhosphorIconsRegular.x,
          compact: true,
          variant: VfButtonVariant.ghost,
          onPressed: onClear,
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
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: t.surface3,
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
                color: t.text,
                fontWeight: FontWeight.w500,
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
              icon: Icon(PhosphorIconsRegular.x, size: 13, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary figures — the web's `.app-report-figures`, two across on a
/// phone and four on a wider screen.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.result,
    required this.money,
    required this.cash,
    required this.sw,
    required this.wide,
  });

  final ReportResult result;
  final bool money, cash, sw, wide;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = result.summary;
    final word = 'reports.vouchersWord'.tr;
    String n(int? v) =>
        '${NumberFormat.decimalPattern('en_US').format(v ?? 0)} $word';
    final generated = ReportFormat.date(result.generatedAt?.toLocal(), sw: sw);

    final cells = <(String, String, String?)>[
      if (money && cash) ...[
        (
          'reports.paidInCash'.tr,
          s.cashTotalText ?? s.paidTotalText ?? '—',
          n(s.cashCount ?? s.paidCount),
        ),
        (
          'reports.outstanding'.tr,
          s.outstandingTotalText ?? '—',
          n(s.outstandingCount),
        ),
        ('reports.amount'.tr, s.totalText, n(s.count)),
      ] else if (money) ...[
        ('reports.paidByBank'.tr, s.bankTotalText ?? '—', n(s.bankCount)),
        ('reports.paidInCash'.tr, s.cashTotalText ?? '—', n(s.cashCount)),
        (
          'reports.outstanding'.tr,
          s.outstandingTotalText ?? '—',
          n(s.outstandingCount),
        ),
      ] else ...[
        (
          'reports.vouchers'.tr,
          NumberFormat.decimalPattern('en_US').format(s.count),
          null,
        ),
        ('reports.amount'.tr, s.totalText, null),
        ('reports.awaitingPayment'.tr, s.approvedTotalText, null),
      ],
      ('reports.generated'.tr, generated, null),
    ];

    final cols = wide ? 4 : 2;
    final lines = <Widget>[];
    for (var i = 0; i < cells.length; i += cols) {
      lines.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = i; k < i + cols; k++)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
                    decoration: BoxDecoration(
                      border: Border(
                        right: k % cols == cols - 1
                            ? BorderSide.none
                            : BorderSide(color: t.border),
                        top: i == 0
                            ? BorderSide.none
                            : BorderSide(color: t.border),
                      ),
                    ),
                    child: k < cells.length
                        ? _Figure(cell: cells[k])
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.cell});

  final (String, String, String?) cell;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (label, value, sub) = cell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: VfType.meta.copyWith(color: t.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: VfType.bodyStrong.copyWith(
              color: t.text,
              fontSize: 16.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.meta.copyWith(
              color: t.muted,
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// Print the report's PDF — a square outline button beside the exports.
class _PrintButton extends StatelessWidget {
  const _PrintButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: 'reports.print'.tr,
      child: Semantics(
        button: true,
        label: 'reports.print'.tr,
        excludeSemantics: true,
        child: SizedBox(
          width: 44,
          height: 36,
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              side: BorderSide(color: t.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.text2,
                        ),
                      )
                    : Icon(
                        PhosphorIconsRegular.printer,
                        size: 17,
                        color: onPressed == null ? t.faint : t.text,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
