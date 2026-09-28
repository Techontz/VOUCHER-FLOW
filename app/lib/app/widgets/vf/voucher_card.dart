import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import 'surfaces.dart';

/// A voucher in a list: the web register's card. Number with the bank/cash
/// mark and status, the purpose as the title, who and where, where it stands,
/// and the amount — with what is still owed when part-paid.
class VouchFlowVoucherCard extends StatelessWidget {
  const VouchFlowVoucherCard({super.key, required this.voucher, this.onTap, this.trailing, this.selected = false});

  final Voucher voucher;
  final VoidCallback? onTap;

  /// An extra control (a checkbox in bulk approve).
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final date = v.submittedAt ?? v.voucherDate ?? v.createdAt;
    final dateText = date == null ? null : DateFormat('d MMM y').format(date);
    final meta = [v.payee, v.requesterName, v.departmentName].whereType<String>().where((s) => s.isNotEmpty && s != 'null').join(' · ');
    final where = [
      if (v.currentStepName != null && !v.isTerminal) v.currentStepName!,
      ?dateText,
    ].join(' · ');

    return VouchFlowCard(
      onTap: onTap,
      borderColor: selected ? t.primary : null,
      color: selected ? t.primarySoft : null,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      v.number,
                      style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    _Kind(isCash: v.isCash),
                    VouchFlowStatusBadge(label: v.statusLabel, tag: v.statusTag),
                  ],
                ),
                const SizedBox(height: 8),
                Text(v.purpose, maxLines: 2, overflow: TextOverflow.ellipsis, style: VfType.cardTitle.copyWith(color: t.text)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.small.copyWith(color: t.muted)),
                ],
                if (where.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.small.copyWith(color: t.text2)),
                ],
                const SizedBox(height: 8),
                Text(
                  v.amountText,
                  style: VfType.bodyStrong.copyWith(fontSize: 17, color: t.text, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (v.isPartiallyPaid && v.balanceText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(v.balanceText!, style: VfType.meta.copyWith(color: t.warning, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _Kind extends StatelessWidget {
  const _Kind({required this.isCash});
  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: t.surface3, borderRadius: BorderRadius.circular(VfSize.radiusS)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isCash ? PhosphorIconsRegular.money : PhosphorIconsRegular.bank, size: 13, color: t.text2),
          const SizedBox(width: 4),
          Text(isCash ? 'Cash' : 'Bank', style: VfType.meta.copyWith(color: t.text2, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
