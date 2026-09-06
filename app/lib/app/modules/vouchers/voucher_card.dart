import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/models.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';

/// One voucher in a list or queue.
class VoucherCard extends StatelessWidget {
  const VoucherCard({super.key, required this.voucher, this.onReturn});

  final Voucher voucher;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () async {
        await Get.toNamed(Routes.voucher, arguments: voucher.id);
        onReturn?.call();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                voucher.number,
                voucher.voucherTypeLabel,
                voucher.departmentName,
              ].whereType<String>().join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 3),
            Text(
              voucher.purpose,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              '${voucher.requesterName ?? ''} → ${voucher.payee}',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    voucher.amountText,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: voucher.statusLabel,
                  tag: voucher.statusTag,
                  dense: true,
                ),
              ],
            ),
            if (voucher.actions.hasWorkflowAction) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    voucher.actions.approve
                        ? Icons.verified_outlined
                        : voucher.actions.submitSigned
                        ? Icons.forward_outlined
                        : Icons.draw_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    voucher.actions.approve
                        ? 'act.approve'.tr
                        : voucher.actions.submitSigned
                        ? 'act.submitSigned'.tr
                        : 'act.sign'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
