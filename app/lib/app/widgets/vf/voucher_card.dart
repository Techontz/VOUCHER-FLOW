import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import 'surfaces.dart';

/// A voucher in a list, as an app row in its own rounded card: a kind tile
/// tinted bank (primary) or cash (green), the purpose, "number · payee", and
/// the amount over the status pill.
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
    const tabular = [FontFeature.tabularFigures()];
    final partial = v.isPartiallyPaid && v.balanceText != null;
    final meta = [v.number, v.payee].where((s) => s.isNotEmpty && s != 'null').join(' · ');

    return VouchFlowCard(
      onTap: onTap,
      radius: VfSize.radiusXl,
      borderColor: selected ? t.primary : null,
      color: selected ? t.primarySoft : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: v.isCash ? t.successSoft : t.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              v.isCash ? PhosphorIconsFill.money : PhosphorIconsFill.bank,
              size: 21,
              color: v.isCash ? t.successStrong : t.primaryText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.purpose,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3),
                ),
                const SizedBox(height: 3),
                Text(
                  partial ? v.balanceText! : meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.meta.copyWith(
                    fontSize: 13,
                    color: partial ? t.warningStrong : t.muted,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 136),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    v.amountText,
                    maxLines: 1,
                    style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3, fontFeatures: tabular),
                  ),
                ),
                const SizedBox(height: 5),
                VouchFlowStatusBadge(label: v.statusLabel, tag: v.displayTag),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
