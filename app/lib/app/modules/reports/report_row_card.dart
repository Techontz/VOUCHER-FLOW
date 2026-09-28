import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';
import 'report_format.dart';

/// One report row as a card: the row's first column as its title, the
/// headline figure on the right, the status as a badge, and every other
/// column underneath — the same information as the web table's row.
class ReportRowCard extends StatelessWidget {
  const ReportRowCard({
    super.key,
    required this.headings,
    required this.row,
    required this.sw,
  });

  final List<String> headings;
  final List<Object?> row;
  final bool sw;

  static const _figureHeadings = [
    'Amount',
    'Total value',
    'Approved value',
    'Requested value',
  ];
  static const _subtitleHeadings = ['Purpose', 'Payee'];
  static const _statusHeadings = ['Status', 'Outcome'];

  int _find(List<String> names) {
    for (final name in names) {
      final i = headings.indexOf(name);
      if (i >= 0 && i < row.length) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final figure = _find(_figureHeadings);
    final currency = _find(const ['Currency']);
    final status = _find(_statusHeadings);
    final subtitle = _find(_subtitleHeadings);
    final used = {0, figure, currency, status, subtitle};

    final title = ReportFormat.cell(row.isEmpty ? null : row.first, sw: sw);
    final isRef = row.isNotEmpty && ReportFormat.isRef(row.first);

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
      for (var i = 0; i < headings.length && i < row.length; i++)
        if (!used.contains(i)) (headings[i], ReportFormat.cell(row[i], sw: sw)),
      // With no figure to fold it into, the currency is an ordinary field.
      if (figure < 0 && currency >= 0)
        (headings[currency], ReportFormat.cell(row[currency], sw: sw)),
    ];

    return VouchFlowCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        fontFeatures: isRef
                            ? const [FontFeature.tabularFigures()]
                            : null,
                      ),
                    ),
                    if (status >= 0 && row[status] != null) ...[
                      const SizedBox(height: 6),
                      VouchFlowStatusBadge(
                        label: ReportFormat.cell(row[status], sw: sw),
                        tag: ReportFormat.statusTag('${row[status]}'),
                      ),
                    ],
                  ],
                ),
              ),
              if (figureText != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (headings[figure] != 'Amount')
                        Text(
                          headings[figure],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          figureText,
                          maxLines: 1,
                          style: VfType.bodyStrong.copyWith(
                            color: t.text,
                            fontSize: 15.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (subtitle >= 0 && row[subtitle] != null) ...[
            const SizedBox(height: 8),
            Text(
              ReportFormat.cell(row[subtitle], sw: sw),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: VfType.small.copyWith(color: t.text2),
            ),
          ],
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: t.border),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) {
                const gap = 12.0;
                final half = (box.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: 10,
                  children: [
                    for (final (label, value) in fields)
                      SizedBox(
                        width: value.length > 26 ? box.maxWidth : half,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.meta.copyWith(color: t.muted),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              value,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.small.copyWith(
                                color: t.text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
