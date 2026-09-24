import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';

/// One voucher in a list or queue: number and date, purpose, amount, who and
/// where, then its status — and, when the API offers this person an action,
/// what that action is.
class VoucherCard extends StatelessWidget {
  const VoucherCard({super.key, required this.voucher, this.onReturn});

  final Voucher voucher;
  final VoidCallback? onReturn;

  /// The label for the action the API offers on this voucher, if any. Only
  /// the flags the API set are read — the card never infers a permission.
  static String? actionLabel(Voucher v) {
    final a = v.actions;
    if (a.pay) return 'pay.pay'.tr;
    if (a.approve) return 'act.review'.tr;
    if (a.submitSigned) return 'act.submitShort'.tr;
    if (a.sign) return 'act.signShort'.tr;
    if (a.reject || a.requestChanges) return 'act.review'.tr;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = VoucherStatusStyle.of(voucher);
    final statusColour = style.tone.colour(context);
    final action = actionLabel(voucher);
    final when = voucher.submittedAt ?? voucher.voucherDate ?? voucher.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        onTap: () async {
          await Get.toNamed(Routes.voucher, arguments: voucher.id);
          onReturn?.call();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Mono(voucher.number, size: 11.5)),
                const SizedBox(width: 8),
                if (voucher.actions.pay)
                  KindTag(kind: voucher.kind)
                else
                  Text(Fmt.relative(when), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              voucher.purpose,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            AmountText(
              amount: voucher.amount,
              currency: voucher.currency,
              size: 19,
            ),
            const SizedBox(height: 6),
            Text(
              [
                voucher.payee,
                voucher.departmentName,
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(style.icon, size: 13, color: statusColour),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    voucher.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: statusColour,
                      decoration: style.struck
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: statusColour,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    action,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: context.vfAccent,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward, size: 14, color: context.vfAccent),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
