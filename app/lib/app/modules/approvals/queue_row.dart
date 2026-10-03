import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../vouchers/detail_bits.dart';
import 'list_bits.dart';

export 'list_bits.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Opens a voucher over the shell and runs [then] when the reader comes back.
Future<void> openVoucher(int id, {Future<void> Function()? then}) async {
  await Get.toNamed(Routes.voucher, arguments: id);
  await then?.call();
}

/// A voucher in a work queue, as a banking-app row: a tile tinted by its
/// status (bank or cash), the purpose, number and payee, then the amount and
/// status on the right. In selection mode the tile becomes a round check.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.voucher,
    this.progress = const [],
    this.owing = false,
    this.history = false,
    this.showCta = true,
    this.onOpen,
    this.selecting = false,
    this.selected = false,
    this.selectable = true,
    this.onToggle,
    this.onLongPress,
  });

  final Voucher voucher;
  final List<ProgressStep> progress;

  /// Payment queue: "Balance TZS 1,000,000 of TZS 10,000,000".
  final bool owing;

  /// Show the stage/result and submitted/updated dates.
  final bool history;

  /// Name the next step ("Approve", "Record payment") under the details.
  final bool showCta;
  final VoidCallback? onOpen;

  /// Selection mode: a round check replaces the tile and a tap toggles.
  final bool selecting;
  final bool selected;
  final bool selectable;
  final VoidCallback? onToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final v = voucher;
    final cta = showCta ? primaryAction(v) : null;
    final (fg, bg) = statusTone(v.statusKey).colors(t);
    final balance = v.balanceText;
    final meta = [v.number, if (v.payee.isNotEmpty) v.payee].join(' · ');
    final who = [
      v.requesterName,
      v.departmentName,
      v.voucherDate == null ? null : Fmt.date(v.voucherDate),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    final leading = selecting
        ? SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Semantics(
                checked: selected,
                enabled: selectable,
                label: '${dt('select')} ${v.number}',
                child: AppRoundCheck(value: selected, enabled: selectable),
              ),
            ),
          )
        : AppIconTile(
            icon: v.isCash ? PhosphorIconsFill.money : PhosphorIconsFill.bank,
            fg: fg,
            bg: bg,
          );

    final muted = VfType.meta.copyWith(color: t.muted, fontSize: 13);

    return Opacity(
      opacity: selecting && !selectable ? .55 : 1,
      child: InkWell(
        onTap: selecting && selectable ? onToggle : onOpen,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          color: selecting && selected ? t.primarySoft : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.purpose,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted.copyWith(fontFeatures: _tabular),
                    ),
                    if (who.isNotEmpty)
                      Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    if (history)
                      Text(
                        [
                          voucherStage(v),
                          if (v.updatedAt != null) Fmt.date(v.updatedAt),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted.copyWith(
                          color: t.text2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (v.isPartiallyPaid && balance != null)
                      Text(
                        owing
                            ? dt('balanceOfAmount', {
                                'balance': balance,
                                'amount': v.amountText,
                              })
                            : dt('balanceAmount', {'amount': balance}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted.copyWith(
                          fontWeight: FontWeight.w600,
                          color: t.warning,
                          fontFeatures: _tabular,
                        ),
                      ),
                    if (progress.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ProgressStepsLine(steps: progress),
                    ],
                    if (cta != null && !selecting) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cta.icon, size: 15, color: t.primaryText),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              cta.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.meta.copyWith(
                                color: t.primaryText,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        v.amountText,
                        maxLines: 1,
                        style: VfType.bodyStrong.copyWith(
                          fontWeight: FontWeight.w700,
                          color: t.text,
                          height: 1.3,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    VoucherStatusBadge(voucher: v),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// All · Bank · Cash, as pills.
class KindFilter extends StatelessWidget {
  const KindFilter({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (key, label) in [
            ('all', dt('all')),
            ('bank', dt('bank')),
            ('cash', dt('cash')),
          ]) ...[
            VouchFlowFilterChip(
              label: label,
              selected: value == key,
              onTap: () => onChanged(key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
