import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/finance_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'fin_widgets.dart';
import 'finance_widgets.dart';

/// Every bank, cash and mobile money account with its ledger balance (the
/// web's /erp/finance/banks).
class BankAccountsPage extends StatelessWidget {
  const BankAccountsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'accounting',
    permission: 'finance.view',
    builder: (_) => FinAsync<List<BankAccount>>(
      load: FinanceRepository.to.bankAccounts,
      builder: (context, accounts, reload) {
        final t = context.vf;
        final total = accounts.where((a) => a.isActive).fold<double>(0, (s, a) => s + a.balance);
        return [
          ErpPageTitle('fin.nav.banks'.tr, subtitle: 'fin.banksSub'.tr),
          VouchFlowFigureCard(
            label: 'fin.inTheseAccounts'.tr,
            value: finCompact(total),
            hint: finMoney(total),
            icon: PhosphorIconsRegular.wallet,
          ),
          erpGap,
          if (accounts.isEmpty)
            VouchFlowEmptyState(icon: PhosphorIconsRegular.bank, title: 'fin.noAccounts'.tr)
          else
            VouchFlowPanel(
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < accounts.length; i++)
                    VouchFlowListRow(
                      divider: i > 0,
                      icon: cashTypeIcon(accounts[i].type),
                      iconColor: accounts[i].isActive ? cashTypeTint(t, accounts[i].type) : t.muted,
                      title: accounts[i].name,
                      subtitle: [
                        'fin.type.${accounts[i].type}'.tr,
                        ?accounts[i].accountNumber,
                        if (!accounts[i].isActive) 'prc.inactive'.tr,
                      ].join(' · '),
                      trailing: FinTrailing(
                        amount: finMoney(accounts[i].balance, currency: accounts[i].currency),
                        tone: accounts[i].balance < 0 ? t.dangerStrong : null,
                      ),
                      onTap: () async {
                        await Get.toNamed(Routes.finBank, arguments: accounts[i].id);
                        await reload();
                      },
                    ),
                ],
              ),
            ),
        ];
      },
    ),
  );
}

/// The general ledger's journal entries, newest first, searchable by
/// number or memo (the web's /erp/accounts journals).
class JournalsPage extends StatelessWidget {
  const JournalsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'accounting',
    permission: 'accounting.view',
    builder: (_) => FinPagedList<JournalEntry>(
      title: 'fin.nav.journals'.tr,
      subtitle: 'fin.journalsSub'.tr,
      searchPlaceholder: 'fin.searchJournals'.tr,
      filters: [
        FinFilter('inv.all'.tr, null),
        for (final s in ['CashbookEntry', 'SupplierInvoice', 'SupplierPayment', 'AssetDepreciationRun'])
          FinFilter(journalSourceLabel(s), s),
      ],
      load: (page, source, q) => FinanceRepository.to.journals(q: q.isEmpty ? null : q, sourceType: source, page: page),
      emptyIcon: PhosphorIconsRegular.notebook,
      emptyTitle: 'fin.noJournals'.tr,
      row: (context, j, divider, reload) => JournalRow(
        journal: j,
        divider: divider,
        onTap: () async {
          await Get.toNamed(Routes.finJournal, arguments: j.id);
          reload();
        },
      ),
    ),
  );
}
