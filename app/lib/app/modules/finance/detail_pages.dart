import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/finance_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'fin_widgets.dart';
import 'finance_widgets.dart';

/// One bank, cash or mobile money account: its balance, details, and its
/// ledger statement for the last three months with the running balance
/// (the web's /erp/finance/banks/[id]).
class BankAccountPage extends StatelessWidget {
  const BankAccountPage({super.key, this.accountId});

  final int? accountId;

  @override
  Widget build(BuildContext context) {
    final id = accountId ?? finArgId();
    return FinDetail<BankAccount>(
      load: () => FinanceRepository.to.bankAccount(id),
      title: (a) => a?.name ?? 'fin.account'.tr,
      children: (context, a, reload) {
        final t = context.vf;
        String money(num v) => finMoney(v, currency: a.currency, cents: true);
        return [
          FinHead(
            icon: cashTypeIcon(a.type),
            tint: cashTypeTint(t, a.type),
            kicker: 'fin.type.${a.type}'.tr,
            title: a.name,
            subtitle: [?a.bankName, ?a.accountNumber].join(' · '),
            amount: money(a.balance),
            badges: [if (!a.isActive) VouchFlowStatusBadge(label: 'prc.inactive'.tr, large: true)],
          ),
          VouchFlowPanel(
            title: 'fin.statement'.tr,
            subtitle: a.statementFrom == null ? null : '${dashDate(a.statementFrom)} - ${dashDate(a.statementTo)}',
            padded: false,
            child: Column(
              children: [
                FinAmountRow(label: 'fin.opening'.tr, amount: money(a.statementOpening ?? 0), weight: FinRowWeight.subtotal, divider: false),
                if (a.lines.isEmpty) FinPanelEmpty('fin.noMovements'.tr),
                for (final l in a.lines.reversed)
                  VouchFlowListRow(
                    icon: l.debit > 0 ? PhosphorIconsRegular.arrowDown : PhosphorIconsRegular.arrowUp,
                    iconColor: l.debit > 0 ? t.successStrong : t.warningStrong,
                    title: l.description ?? l.number,
                    titleMaxLines: 2,
                    subtitle: [
                      if (l.date != null) dashDate(l.date),
                      l.number,
                      if (l.reconciled) 'fin.reconciled'.tr,
                    ].join(' · '),
                    trailing: FinTrailing(
                      amount: l.debit > 0 ? '+${ErpAmount.of(l.debit)}' : '-${ErpAmount.of(l.credit)}',
                      tone: l.debit > 0 ? t.successStrong : null,
                    ),
                    onTap: l.journalId == null ? null : finJournalTap(l.journalId!),
                  ),
                FinAmountRow(label: 'fin.closing'.tr, amount: money(a.statementClosing ?? a.balance), weight: FinRowWeight.total),
              ],
            ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'inv.details'.tr,
            child: Column(
              children: [
                if (a.ledger != null) ErpFact('fin.ledgerAccount'.tr, accountLabel(a.ledger)),
                if (a.bankName != null) ErpFact('prc.bank'.tr, a.bankName!),
                if (a.branch != null) ErpFact('fin.branch'.tr, a.branch!),
                if (a.accountName != null) ErpFact('prc.accountName'.tr, a.accountName!),
                if (a.accountNumber != null) ErpFact('prc.accountNumber'.tr, a.accountNumber!),
                ErpFact('fin.currency'.tr, a.currency),
                ErpFact('fin.openingBalance'.tr, [money(a.openingBalance), if (a.openingDate != null) dashDate(a.openingDate)].join(' · ')),
              ],
            ),
          ),
        ];
      },
    );
  }
}

/// Plain thousands for a statement column, cents when there are any.
abstract class ErpAmount {
  static String of(double v) => finMoney(v, cents: true).split(' ').last;
}

/// One journal entry: its lines, debits and credits that balance, where it
/// came from (the web's journal dialog).
class JournalPage extends StatelessWidget {
  const JournalPage({super.key, this.journalId});

  final int? journalId;

  @override
  Widget build(BuildContext context) {
    final id = journalId ?? finArgId();
    return FinDetail<JournalEntry>(
      load: () => FinanceRepository.to.journal(id),
      title: (j) => j?.number ?? 'fin.journal'.tr,
      children: (context, j, reload) {
        final t = context.vf;
        final debit = j.lines.fold<double>(0, (s, l) => s + l.debit);
        final credit = j.lines.fold<double>(0, (s, l) => s + l.credit);
        return [
          FinHead(
            icon: PhosphorIconsRegular.notebook,
            kicker: 'fin.journal'.tr,
            title: j.number,
            subtitle: [if (j.entryDate != null) dashDate(j.entryDate), if (j.sourceType != null) journalSourceLabel(j.sourceType!)].join(' · '),
            amount: finMoney(j.total, cents: true),
            badges: [FinStatusBadge(j.status, large: true)],
          ),
          if (j.memo != null) ...[
            VouchFlowPanel(
              title: 'fin.memo'.tr,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(j.memo!, style: VfType.body.copyWith(color: t.text)),
              ),
            ),
            erpGap,
          ],
          VouchFlowPanel(
            title: 'fin.lines'.tr,
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < j.lines.length; i++)
                  FinAmountRow(
                    divider: i > 0,
                    label: j.lines[i].account.name,
                    code: [?j.lines[i].account.code, ?j.lines[i].description].join(' · '),
                    amount: j.lines[i].debit > 0
                        ? '${'fin.dr'.tr} ${ErpAmount.of(j.lines[i].debit)}'
                        : '${'fin.cr'.tr} ${ErpAmount.of(j.lines[i].credit)}',
                    tone: j.lines[i].debit > 0 ? null : t.text2,
                  ),
                FinAmountRow(label: 'fin.totalDebit'.tr, amount: ErpAmount.of(debit), weight: FinRowWeight.subtotal),
                FinAmountRow(label: 'fin.totalCredit'.tr, amount: ErpAmount.of(credit), weight: FinRowWeight.subtotal),
              ],
            ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'inv.details'.tr,
            child: Column(
              children: [
                if (j.creator != null) ErpFact('inv.prepared'.tr, j.creator!.name),
                if (j.postedAt != null) ErpFact('inv.postedBy'.tr, dashDateTime(j.postedAt)),
                if (j.reversalOf != null)
                  ErpFact('inv.reversalOf'.tr, j.reversalOf!.name,
                      onTap: () => Get.toNamed(Routes.finJournal, arguments: j.reversalOf!.id, preventDuplicates: false)),
                if (j.purpose != null) ErpFact('fin.purpose'.tr, j.purpose!),
              ],
            ),
          ),
        ];
      },
    );
  }
}
