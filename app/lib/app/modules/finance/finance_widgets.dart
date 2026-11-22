import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import 'fin_widgets.dart';

/*
 * Pieces the Finance screens share: how a cash, bank or mobile money
 * account looks, and a cashbook entry and a journal as list rows.
 */

IconData cashTypeIcon(String type) => switch (type) {
  'bank' => PhosphorIconsRegular.bank,
  'mobile_money' => PhosphorIconsRegular.deviceMobile,
  _ => PhosphorIconsRegular.money,
};

Color cashTypeTint(VfTokens t, String type) => switch (type) {
  'bank' => t.primary,
  'mobile_money' => t.successStrong,
  _ => t.warningStrong,
};

/// A receipt (money in, green) or a payment (money out).
class CashbookRow extends StatelessWidget {
  const CashbookRow({super.key, required this.entry, required this.onTap, this.divider = true});

  final CashbookEntry entry;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final e = entry;
    return VouchFlowListRow(
      divider: divider,
      icon: e.isReceipt ? PhosphorIconsRegular.arrowCircleDown : PhosphorIconsRegular.arrowCircleUp,
      iconColor: e.isReceipt ? t.successStrong : t.warningStrong,
      title: e.description.isEmpty ? e.number : e.description,
      subtitle: [e.number, ?e.counterparty, if (e.entryDate != null) dashDate(e.entryDate)].join(' · '),
      trailing: FinTrailing(
        amount: '${e.isReceipt ? '+' : '-'}${finCompact(e.amount)}',
        tone: e.isReceipt ? t.successStrong : null,
        badge: e.status == 'posted' ? null : FinStatusBadge(e.status),
      ),
      onTap: onTap,
    );
  }
}

/// A journal entry: number, memo, date, total.
class JournalRow extends StatelessWidget {
  const JournalRow({super.key, required this.journal, required this.onTap, this.divider = true});

  final JournalEntry journal;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final j = journal;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.notebook,
      iconColor: j.reversalOf != null ? context.vf.warningStrong : context.vf.primary,
      title: j.memo ?? j.number,
      subtitle: [j.number, if (j.entryDate != null) dashDate(j.entryDate), if (j.sourceType != null) journalSourceLabel(j.sourceType!)].join(' · '),
      trailing: FinTrailing(amount: finCompact(j.total), badge: j.status == 'posted' ? null : FinStatusBadge(j.status)),
      onTap: onTap,
    );
  }
}

/// "Supplier invoice", "Cashbook", "Manual" for a journal's source.
String journalSourceLabel(String source) {
  final key = 'fin.source.$source';
  final label = key.tr;
  return label == key ? source.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ') : label;
}
