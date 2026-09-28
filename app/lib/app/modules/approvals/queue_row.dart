import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../vouchers/detail_bits.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Opens a voucher over the shell and runs [then] when the reader comes back.
Future<void> openVoucher(int id, {Future<void> Function()? then}) async {
  await Get.toNamed(Routes.voucher, arguments: id);
  await then?.call();
}

/// A voucher in a work queue — the web's `VoucherRow`: number, format and
/// status; the purpose; who, where and when; its route so far; the amount
/// (with what is still owed); and one call to action that opens the voucher.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.voucher,
    this.progress = const [],
    this.owing = false,
    this.history = false,
    this.showCta = true,
    this.onOpen,
  });

  final Voucher voucher;
  final List<ProgressStep> progress;

  /// Payment queue: "Balance TZS 1,000,000 of TZS 10,000,000".
  final bool owing;

  /// Show the stage/result and submitted/updated dates.
  final bool history;
  final bool showCta;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final cta = showCta ? primaryAction(v) : null;
    final meta = [
      v.requesterName,
      v.departmentName,
      v.voucherDate == null ? null : Fmt.date(v.voucherDate),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final balance = v.balanceText;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  v.number,
                  style: VfType.small.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text2,
                    fontFeatures: _tabular,
                  ),
                ),
                VoucherKindTag(isCash: v.isCash),
                VoucherStatusBadge(voucher: v),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              v.purpose,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.cardTitle.copyWith(color: t.text),
            ),
            const SizedBox(height: 3),
            Text(
              [v.payee, if (meta.isNotEmpty) meta].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.small.copyWith(fontSize: 14, color: t.muted),
            ),
            if (history) ...[
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: voucherStage(v),
                      style: TextStyle(color: t.text2, fontWeight: FontWeight.w600),
                    ),
                    if (v.submittedAt != null) TextSpan(text: ' · ${dt('submittedOn')} ${Fmt.date(v.submittedAt)}'),
                    if (v.updatedAt != null) TextSpan(text: ' · ${dt('lastUpdated')} ${Fmt.date(v.updatedAt)}'),
                  ],
                ),
                style: VfType.small.copyWith(fontSize: 14, color: t.muted),
              ),
            ],
            if (progress.isNotEmpty) ...[const SizedBox(height: 8), ProgressStepsLine(steps: progress)],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          v.amountText,
                          style: VfType.bodyStrong.copyWith(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                      if (v.isPartiallyPaid && balance != null)
                        Text(
                          owing
                              ? dt('balanceOfAmount', {'balance': balance, 'amount': v.amountText})
                              : dt('balanceAmount', {'amount': balance}),
                          style: VfType.meta.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.warning,
                            fontFeatures: _tabular,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (cta != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: VouchFlowButton(
                  label: cta.label,
                  icon: cta.icon,
                  compact: true,
                  variant: cta.strong ? VfButtonVariant.primary : VfButtonVariant.secondary,
                  onPressed: onOpen,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row of figures, two to a line on a phone and four on a tablet — the
/// web's `FigureStrip`.
class FigureGrid extends StatelessWidget {
  const FigureGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? 4 : 2;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      },
    );
  }
}

/// All · Bank · Cash, the web's small segmented control.
class KindFilter extends StatelessWidget {
  const KindFilter({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, label) in [('all', dt('all')), ('bank', dt('bank')), ('cash', dt('cash'))])
          VouchFlowFilterChip(label: label, selected: value == key, onTap: () => onChanged(key)),
      ],
    );
  }
}

/// The quiet footnote under a queue (the web's `.app-panel-foot`).
class PanelFoot extends StatelessWidget {
  const PanelFoot({super.key, required this.text, this.icon = PhosphorIconsRegular.info});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: t.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: VfType.meta.copyWith(fontSize: 13, color: t.muted)),
          ),
        ],
      ),
    );
  }
}
