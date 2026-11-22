import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/finance_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'fin_widgets.dart';
import 'finance_app.dart';
import 'finance_widgets.dart';

/// The general cashbook: receipts and payments that are not a customer's
/// or a supplier's (rent, utilities, scrap sales), with what was posted in
/// and out (the web's /erp/finance/cashbook).
class CashbookPage extends StatelessWidget {
  const CashbookPage({super.key});

  @override
  Widget build(BuildContext context) {
    final erp = ErpService.to;
    return ErpGate(
      module: 'accounting',
      permission: 'finance.view',
      builder: (_) => FinPagedList<CashbookEntry>(
        title: 'fin.nav.cashbook'.tr,
        searchPlaceholder: 'fin.searchCashbook'.tr,
        filters: [
          FinFilter('inv.all'.tr, null),
          FinFilter('fin.receipts'.tr, 'type:receipt'),
          FinFilter('fin.payments'.tr, 'type:payment'),
          FinFilter('fin.status.draft'.tr, 'status:draft'),
          FinFilter('fin.status.posted'.tr, 'status:posted'),
        ],
        trailing: erp.can('finance.cashbook')
            ? VouchFlowButton(
                label: 'prc.new'.tr,
                icon: PhosphorIconsBold.plus,
                compact: true,
                onPressed: () => _choose(context),
              )
            : null,
        load: (page, filter, q) async {
          final type = filter != null && filter.startsWith('type:') ? filter.substring(5) : null;
          final status = filter != null && filter.startsWith('status:') ? filter.substring(7) : null;
          final r = await FinanceRepository.to.cashbook(type: type, status: status, q: q.isEmpty ? null : q, page: page);
          _totals = (r.receipts, r.payments);
          return r.page;
        },
        header: (context, _) => _TotalsCard(_totals),
        emptyIcon: PhosphorIconsRegular.bookOpenText,
        emptyTitle: 'fin.noCashbook'.tr,
        row: (context, e, divider, reload) => CashbookRow(
          entry: e,
          divider: divider,
          onTap: () async {
            await Get.toNamed(Routes.finCashbookEntry, arguments: e.id);
            reload();
          },
        ),
      ),
    );
  }

  static (double, double) _totals = (0, 0);

  Future<void> _choose(BuildContext context) async {
    final chosen = await showVouchFlowBottomSheet<int>(
      context,
      title: 'fin.newEntry'.tr,
      child: Column(
        children: [
          for (var i = 0; i < financeCreateActions.length; i++)
            Builder(
              builder: (ctx) => VouchFlowListRow(
                divider: i > 0,
                icon: financeCreateActions[i].icon,
                title: financeCreateActions[i].label.tr,
                subtitle: financeCreateActions[i].hint?.tr,
                onTap: () => Navigator.of(ctx).pop(i),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (chosen != null) await erpCreate(financeCreateActions[chosen]);
  }
}

/// Posted receipts and payments for the filter, side by side.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard(this.totals);

  final (double, double) totals;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget cell(String label, double v, Color c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: VfType.meta.copyWith(color: t.muted)),
          const SizedBox(height: 2),
          Text(finCompact(v), style: VfType.figureS.copyWith(color: c, fontSize: 18, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: VouchFlowPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
          child: Row(
            children: [
              cell('fin.postedIn'.tr, totals.$1, t.successStrong),
              cell('fin.postedOut'.tr, totals.$2, t.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cashbook entry, with Post and Cancel draft for whoever records them.
class CashbookEntryPage extends StatelessWidget {
  const CashbookEntryPage({super.key, this.entryId});

  final int? entryId;

  @override
  Widget build(BuildContext context) {
    final id = entryId ?? finArgId();
    final repo = FinanceRepository.to;
    return FinDetail<CashbookEntry>(
      load: () => repo.cashbookEntry(id),
      title: (e) => e?.number ?? 'fin.nav.cashbook'.tr,
      actions: (context, e, reload) {
        if (e.status != 'draft' || !ErpService.to.can('finance.cashbook')) return const [];
        final summary = [
          VfSummaryRow('fin.bankAccount'.tr, e.bankAccount?.name ?? '-'),
          VfSummaryRow('fin.amount'.tr, finMoney(e.amount, cents: true)),
        ];
        return [
          VouchFlowButton(
            label: 'inv.cancelDraft'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: () async {
              final done = await finConfirm(
                context,
                title: 'inv.cancelDraftQ'.trParams({'number': e.number}),
                icon: PhosphorIconsRegular.xCircle,
                tone: VfTone.warn,
                summary: summary,
                danger: true,
                confirmLabel: 'inv.cancelDraft'.tr,
                run: (_) async {
                  await repo.cancelCashbookEntry(e.id);
                  return 'fin.status.cancelled'.tr;
                },
              );
              if (done == null) return;
              showToast(done);
              await reload();
            },
          ),
          VouchFlowButton(
            label: 'inv.post'.tr,
            icon: PhosphorIconsRegular.checkCircle,
            onPressed: () async {
              final message = await finConfirm(
                context,
                title: 'inv.postQ'.trParams({'number': e.number}),
                subtitle: 'fin.postSub'.tr,
                summary: summary,
                confirmLabel: 'inv.post'.tr,
                run: (_) => repo.postCashbookEntry(e.id),
              );
              if (message == null) return;
              showToast(message.isEmpty ? 'fin.status.posted'.tr : message);
              await reload();
            },
          ),
        ];
      },
      children: (context, e, reload) {
        final t = context.vf;
        return [
          FinHead(
            icon: e.isReceipt ? PhosphorIconsRegular.arrowCircleDown : PhosphorIconsRegular.arrowCircleUp,
            tint: e.isReceipt ? t.successStrong : t.warningStrong,
            kicker: e.isReceipt ? 'fin.receipt'.tr : 'fin.payment'.tr,
            title: e.number,
            subtitle: [?e.counterparty, if (e.entryDate != null) dashDate(e.entryDate)].join(' · '),
            amount: finMoney(e.amount, cents: true),
            badges: [FinStatusBadge(e.status, large: true)],
          ),
          VouchFlowPanel(
            title: 'inv.details'.tr,
            child: Column(
              children: [
                ErpFact('fin.description'.tr, e.description),
                ErpFact(e.isReceipt ? 'fin.receivedInto'.tr : 'fin.paidFrom'.tr, e.bankAccount?.name ?? '-'),
                ErpFact('fin.ledgerAccount'.tr, accountLabel(e.account)),
                if (e.reference != null) ErpFact('inv.reference'.tr, e.reference!),
                if (e.creator != null) ErpFact('inv.prepared'.tr, e.creator!.name),
                if (e.poster != null)
                  ErpFact('inv.postedBy'.tr, [e.poster!.name, if (e.postedAt != null) dashDateTime(e.postedAt)].join(' · ')),
                if (e.journal != null) ErpFact('fin.journal'.tr, e.journal!.name, onTap: finJournalTap(e.journal!.id)),
                if (e.reversalReason != null) ErpFact('inv.reason'.tr, e.reversalReason!),
              ],
            ),
          ),
        ];
      },
    );
  }
}

/// Records a receipt or a payment as a draft (the web's cashbook dialog).
/// Opened with {'type': 'receipt' | 'payment'}.
class CashbookFormPage extends StatefulWidget {
  const CashbookFormPage({super.key, this.type});

  final String? type;

  @override
  State<CashbookFormPage> createState() => _CashbookFormPageState();
}

class _CashbookFormPageState extends State<CashbookFormPage> {
  final _repo = FinanceRepository.to;
  late final _draft = CashbookDraft(type: widget.type ?? '${(Get.arguments as Map?)?['type'] ?? 'payment'}');
  List<BankAccount>? _banks;
  List<LedgerAccount> _accounts = const [];
  String? _loadError;
  bool _busy = false;
  ApiException? _error;

  bool get _receipt => _draft.type == 'receipt';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait<Object>([_repo.bankAccounts(), _repo.cashbookAccounts()]);
      if (!mounted) return;
      setState(() {
        _banks = (results[0] as List<BankAccount>).where((b) => b.isActive).toList();
        _accounts = results[1] as List<LedgerAccount>;
        _draft.bankAccountId ??= _banks!.firstOrNull?.id;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  /// Income accounts first for a receipt, expenses first for a payment.
  List<LedgerAccount> get _sortedAccounts {
    final first = _receipt ? 'income' : 'expense';
    return [..._accounts.where((a) => a.type == first), ..._accounts.where((a) => a.type != first)];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _draft.entryDate, firstDate: DateTime(now.year - 1), lastDate: now);
    if (picked != null) setState(() => _draft.entryDate = picked);
  }

  Future<void> _pickAccount() async {
    final picked = await showVfSheet<int>(context, builder: (_) => _AccountPicker(accounts: _sortedAccounts));
    if (picked != null) setState(() => _draft.accountId = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final e = await _repo.createCashbookEntry(_draft);
      showToast('inv.saved'.tr, body: e.number);
      Get.offNamed(Routes.finCashbookEntry, arguments: e.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _draft.bankAccountId != null && _draft.accountId != null && (_draft.amountValue ?? 0) > 0 && _draft.description.trim().isNotEmpty;
    return VouchFlowPushedScaffold(
      title: _receipt ? 'fin.newReceipt'.tr : 'fin.newPayment'.tr,
      body: ErpGate(
        module: 'accounting',
        permission: 'finance.cashbook',
        builder: (context) {
          if (_banks == null) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          return _form(context);
        },
      ),
      bottomBar: _banks == null
          ? null
          : FinActionBar(
              children: [
                VouchFlowButton(
                  label: 'inv.saveDraft'.tr,
                  icon: PhosphorIconsRegular.floppyDisk,
                  loading: _busy,
                  onPressed: _busy || !ready ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final banks = _banks!;
    final account = _accounts.where((a) => a.id == _draft.accountId).firstOrNull;
    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Text(_receipt ? 'fin.newReceiptHint'.tr : 'fin.newPaymentHint'.tr, style: VfType.small.copyWith(color: t.text2)),
        ),
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowTextField(
                label: 'fin.amount'.tr,
                required: true,
                initialValue: _draft.amount,
                prefixText: '${ErpService.to.currency} ',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                error: _error?.field('amount'),
                onChanged: (v) => setState(() => _draft.amount = v),
              ),
              const SizedBox(height: 14),
              VouchFlowDropdown<int>(
                label: _receipt ? 'fin.receivedInto'.tr : 'fin.paidFrom'.tr,
                required: true,
                items: [for (final b in banks) b.id],
                value: _draft.bankAccountId,
                itemLabel: (id) => banks.firstWhere((b) => b.id == id).name,
                error: _error?.field('bank_account_id'),
                onChanged: (v) => setState(() => _draft.bankAccountId = v),
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: _receipt ? 'fin.incomeAccount'.tr : 'fin.expenseAccount'.tr,
                required: true,
                readOnly: true,
                key: ValueKey(_draft.accountId),
                initialValue: account?.label ?? '',
                placeholder: 'fin.pickAccount'.tr,
                error: _error?.field('account_id'),
                suffix: Icon(PhosphorIconsBold.caretDown, size: 14, color: t.muted),
                onTap: _pickAccount,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'fin.description'.tr,
                required: true,
                initialValue: _draft.description,
                placeholder: _receipt ? 'fin.receiptPlaceholder'.tr : 'fin.paymentPlaceholder'.tr,
                maxLength: 255,
                error: _error?.field('description'),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (v) => setState(() => _draft.description = v),
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: _receipt ? 'fin.receivedFrom'.tr : 'fin.paidTo'.tr,
                hint: 'inv.optional'.tr,
                initialValue: _draft.counterparty,
                maxLength: 160,
                onChanged: (v) => _draft.counterparty = v,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'inv.date'.tr,
                readOnly: true,
                key: ValueKey(_draft.entryDate),
                initialValue: dashDate(_draft.entryDate),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                error: _error?.field('entry_date'),
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'inv.reference'.tr,
                hint: 'inv.optional'.tr,
                initialValue: _draft.reference,
                maxLength: 80,
                onChanged: (v) => _draft.reference = v,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          erpGap,
          VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
        ],
      ],
    );
  }
}

class _AccountPicker extends StatefulWidget {
  const _AccountPicker({required this.accounts});

  final List<LedgerAccount> accounts;

  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final q = _q.trim().toLowerCase();
    final rows = widget.accounts.where((a) => q.isEmpty || a.label.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('fin.pickAccount'.tr, style: VfType.sectionTitle.copyWith(color: t.text)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: VouchFlowSearchField(placeholder: 'fin.searchAccounts'.tr, onChanged: (v) => setState(() => _q = v)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: rows.length,
                itemBuilder: (_, i) => VouchFlowListRow(
                  divider: i > 0,
                  title: rows[i].name,
                  subtitle: '${rows[i].code} · ${'fin.acct.${rows[i].type}'.tr}',
                  onTap: () => Navigator.of(context).pop(rows[i].id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
