import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';
import '../approvals/list_bits.dart';
import 'report_format.dart';

/// One report row as an app list row: a tinted tile, the row's first column
/// as its title with the purpose or payee under it, the headline figure and
/// status on the right. A tap opens every other column underneath — the
/// same information as the web table's row.
///
/// Consecutive rows join into one rounded group: [first] rounds the top,
/// [last] the bottom, and the rows between are split by inset dividers.
class ReportRowCard extends StatefulWidget {
  const ReportRowCard({
    super.key,
    required this.headings,
    required this.row,
    required this.sw,
    this.icon = PhosphorIconsFill.receipt,
    this.first = true,
    this.last = true,
  });

  final List<String> headings;
  final List<Object?> row;
  final bool sw;
  final IconData icon;
  final bool first, last;

  static const _figureHeadings = [
    'Amount',
    'Total value',
    'Approved value',
    'Requested value',
  ];
  static const _subtitleHeadings = ['Purpose', 'Payee'];
  static const _statusHeadings = ['Status', 'Outcome'];

  @override
  State<ReportRowCard> createState() => _ReportRowCardState();
}

class _ReportRowCardState extends State<ReportRowCard> {
  bool open = false;

  int _find(List<String> names) {
    for (final name in names) {
      final i = widget.headings.indexOf(name);
      if (i >= 0 && i < widget.row.length) return i;
    }
    return -1;
  }

  (Color, Color) _tint(VfTokens t, String? status) =>
      switch (status == null ? '' : ReportFormat.statusTag(status)) {
        'tag-accent' => (t.successStrong, t.successSoft),
        'tag-warn' => (t.warningStrong, t.warningSoft),
        'tag-accent-2' => (t.dangerStrong, t.dangerSoft),
        'tag-neutral' => (t.text2, t.surface3),
        _ => (t.primaryText, t.primarySoft),
      };

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final headings = widget.headings;
    final row = widget.row;
    final sw = widget.sw;
    final figure = _find(ReportRowCard._figureHeadings);
    final currency = _find(const ['Currency']);
    final status = _find(ReportRowCard._statusHeadings);
    final subtitle = _find(ReportRowCard._subtitleHeadings);
    final date = _find(const ['Date', 'Paid on']);
    final used = {0, figure, currency, status, subtitle, date};

    final title = ReportFormat.cell(row.isEmpty ? null : row.first, sw: sw);
    final isRef = row.isNotEmpty && ReportFormat.isRef(row.first);
    final statusText = status >= 0 && row[status] != null
        ? '${row[status]}'
        : null;

    String? figureText;
    if (figure >= 0) {
      final v = row[figure];
      final cur = currency >= 0 && row[currency] != null
          ? '${row[currency]} '
          : '';
      figureText = v is num
          ? '$cur${ReportFormat.number(v)}'
          : ReportFormat.cell(v, sw: sw);
    }

    final fields = <(String, String)>[
      if (figure >= 0 && headings[figure] != 'Amount')
        (headings[figure], figureText ?? '—'),
      for (var i = 0; i < headings.length && i < row.length; i++)
        if (!used.contains(i)) (headings[i], ReportFormat.cell(row[i], sw: sw)),
      // With no figure to fold it into, the currency is an ordinary field.
      if (figure < 0 && currency >= 0)
        (headings[currency], ReportFormat.cell(row[currency], sw: sw)),
    ];

    final meta = [
      if (date >= 0 && row[date] != null) ReportFormat.cell(row[date], sw: sw),
      if (subtitle >= 0 && row[subtitle] != null)
        ReportFormat.cell(row[subtitle], sw: sw),
    ].join(' · ');

    final (fg, bg) = _tint(t, statusText);
    const r = Radius.circular(VfSize.radiusXl);
    final radius = BorderRadius.vertical(
      top: widget.first ? r : Radius.zero,
      bottom: widget.last ? r : Radius.zero,
    );

    return Container(
      margin: EdgeInsets.only(bottom: widget.last ? VfSize.gap : 0),
      decoration: BoxDecoration(color: t.surface, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: fields.isEmpty ? null : () => setState(() => open = !open),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.first)
                  Divider(height: 1, indent: 70, color: t.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIconTile(icon: widget.icon, fg: fg, bg: bg),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.bodyStrong.copyWith(
                                color: t.text,
                                height: 1.3,
                                fontFeatures: isRef
                                    ? const [FontFeature.tabularFigures()]
                                    : null,
                              ),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: open ? 4 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: VfType.meta.copyWith(
                                  color: t.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (figureText != null)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  figureText,
                                  maxLines: 1,
                                  style: VfType.bodyStrong.copyWith(
                                    color: t.text,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            if (statusText != null) ...[
                              const SizedBox(height: 6),
                              VouchFlowStatusBadge(
                                label: ReportFormat.cell(row[status], sw: sw),
                                tag: ReportFormat.statusTag(statusText),
                              ),
                            ],
                            if (figureText == null &&
                                statusText == null &&
                                fields.isNotEmpty)
                              Icon(
                                open
                                    ? PhosphorIconsRegular.caretUp
                                    : PhosphorIconsRegular.caretDown,
                                size: 16,
                                color: t.faint,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: !open || fields.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Container(
                          margin: const EdgeInsets.fromLTRB(70, 0, 14, 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.surface2,
                            borderRadius: BorderRadius.circular(VfSize.radiusL),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < fields.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        fields[i].$1,
                                        style: VfType.meta.copyWith(
                                          color: t.muted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        fields[i].$2,
                                        textAlign: TextAlign.end,
                                        style: VfType.small.copyWith(
                                          color: t.text,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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
