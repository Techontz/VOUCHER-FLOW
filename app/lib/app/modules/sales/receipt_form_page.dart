import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'sales_widgets.dart';

/// Records money a customer paid and applies it to their open invoices
/// (the web's /erp/sales/receipts/new). Nothing reaches the books until
/// someone else in finance verifies it. Opened with {'customerId': int?,
/// 'invoiceId': int?} as the argument; an invoice arrives pre-applied.
class SalesReceiptFormPage extends StatefulWidget {
  const SalesReceiptFormPage({super.key, this.customerId, this.invoiceId});

  final int? customerId, invoiceId;

  @override
  State<SalesReceiptFormPage> createState() => _SalesReceiptFormPageState();
}

class _SalesReceiptFormPageState extends State<SalesReceiptFormPage> {
  late final Map _args = Get.arguments is Map ? Get.arguments as Map : const {};
  final _repo = SalesRepository.to;

  SalesLookups? _lookups;
  String? _loadError;
  int? _customerId, _accountId;
  String _method = 'bank_transfer';
  DateTime _date = DateTime.now();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  List<SalesInvoice>? _open;
  final _alloc = <int, TextEditingController>{};
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    for (final c in _alloc.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _arg(String key, int? given) => given ?? (_args[key] is int ? _args[key] as int : null);

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final l = await _repo.lookups();
      if (!mounted) return;
      setState(() {
        _lookups = l;
        _accountId = (l.cashAccounts.where((a) => a.code == '1200').firstOrNull ?? l.cashAccounts.firstOrNull)?.id;
      });
      final customer = _arg('customerId', widget.customerId);
      if (customer != null) await _setCustomer(customer, preselect: _arg('invoiceId', widget.invoiceId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  Future<void> _setCustomer(int id, {int? preselect}) async {
    setState(() {
      _customerId = id;
      _open = null;
      for (final c in _alloc.values) {
        c.dispose();
      }
      _alloc.clear();
    });
    try {
      final page = await _repo.invoices(customerId: id, openOnly: true, perPage: 200);
      if (!mounted) return;
      setState(() {
        _open = page.data;
        for (final i in page.data) {
          _alloc[i.id] = TextEditingController(text: i.id == preselect ? _plain(i.balance) : '');
        }
      });
    } catch (_) {
      if (mounted) setState(() => _open = const []);
    }
  }

  String _plain(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');

  double get _total => _alloc.values.fold(0, (s, c) => s + salesNum(c.text));

  Future<void> _pickCustomer() async {
    final l = _lookups;
    if (l == null) return;
    final id = await showVouchFlowBottomSheet<int>(
      context,
      title: 'sal.pickCustomer'.tr,
      child: _CustomerList(customers: l.customers),
    );
    if (id != null) await _setCustomer(id);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 1), lastDate: now);
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_customerId == null) {
      setState(() => _error = ApiException(422, 'sal.pickCustomerFirst'.tr));
      return;
    }
    if (_total <= 0) {
      setState(() => _error = ApiException(422, 'sal.applySomething'.tr));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final (message, receipt) = await _repo.recordReceipt(
        customerId: _customerId!,
        accountId: _accountId ?? 0,
        method: _method,
        date: _date,
        reference: _reference.text,
        notes: _notes.text,
        allocations: {for (final e in _alloc.entries) e.key: salesNum(e.value.text)},
      );
      showToast(message.isEmpty ? 'sal.receiptRecorded'.tr : message);
      Get.offNamed(Routes.salesReceipt, arguments: receipt.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'sal.receivePayment'.tr,
      body: ErpGate(
        module: 'sales',
        permission: 'sales.receipt',
        builder: (context) {
          if (_lookups == null) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          return _form(context);
        },
      ),
      bottomBar: _lookups == null
          ? null
          : SalesActionBar(
              children: [
                VouchFlowButton(
                  label: _total > 0 ? 'sal.recordAmount'.trParams({'amount': salesMoney(_total)}) : 'sal.recordReceipt'.tr,
                  icon: PhosphorIconsRegular.handCoins,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final l = _lookups!;
    final customer = l.customers.where((c) => c.id == _customerId).firstOrNull;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Text('sal.receiptFormSub'.tr, style: VfType.small.copyWith(color: t.text2)),
        ),
        VouchFlowPanel(
          title: 'sal.customer'.tr,
          padded: false,
          child: VouchFlowListRow(
            divider: false,
            icon: customer == null ? PhosphorIconsRegular.userPlus : PhosphorIconsRegular.storefront,
            iconColor: customer == null ? t.primary : t.successStrong,
            title: customer?.name ?? 'sal.pickCustomer'.tr,
            subtitle: customer == null ? 'sal.pickCustomerHint'.tr : [customer.code, ?customer.city].join(' · '),
            trailing: Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
            onTap: _pickCustomer,
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.applyToInvoices'.tr,
          trailing: _open != null && _open!.isNotEmpty
              ? VouchFlowPanelAction(
                  label: 'sal.payAll'.tr,
                  onTap: () => setState(() {
                    for (final i in _open!) {
                      _alloc[i.id]?.text = _plain(i.balance);
                    }
                  }),
                )
              : null,
          padded: false,
          child: _customerId == null
              ? SalesNote('sal.pickCustomerFirst'.tr)
              : _open == null
              ? const Padding(padding: EdgeInsets.all(20), child: VfLoader(size: 28))
              : _open!.isEmpty
              ? SalesNote('sal.nothingOwed'.tr)
              : Column(
                  children: [
                    for (var n = 0; n < _open!.length; n++)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        decoration: n == 0
                            ? null
                            : BoxDecoration(border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_open![n].number, style: VfType.bodyStrong.copyWith(color: t.text)),
                                    Text(
                                      [
                                        'sal.owes'.trParams({'amount': ErpFmt.amount(_open![n].balance)}),
                                        if (_open![n].dueDate != null) 'sal.dueOn'.trParams({'date': dashDate(_open![n].dueDate)}),
                                      ].join(' · '),
                                      style: VfType.meta.copyWith(
                                        color: _open![n].isOverdue ? t.dangerStrong : t.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 130,
                              child: VouchFlowTextField(
                                label: 'sal.apply'.tr,
                                controller: _alloc[_open![n].id],
                                placeholder: '0',
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: numbers,
                                error: _error?.field('allocations.$n.amount'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'sal.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowDropdown<int>(
                label: 'sal.intoAccount'.tr,
                required: true,
                items: [for (final a in l.cashAccounts) a.id],
                value: _accountId,
                itemLabel: (id) {
                  final a = l.cashAccounts.firstWhere((x) => x.id == id);
                  return [?a.code, a.name].join(' · ');
                },
                error: _error?.field('account_id'),
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 14),
              VouchFlowDropdown<String>(
                label: 'sal.method'.tr,
                items: salesReceiptMethods,
                value: _method,
                itemLabel: salesMethodLabel,
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                key: ValueKey(_date),
                label: 'sal.date'.tr,
                readOnly: true,
                initialValue: dashDate(_date),
                error: _error?.field('receipt_date'),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'sal.reference'.tr,
                hint: 'sal.referenceHint'.tr,
                controller: _reference,
                maxLength: 80,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(label: 'sal.notes'.tr, hint: 'sal.optional'.tr, controller: _notes, maxLines: 3, minLines: 2),
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

class _CustomerList extends StatefulWidget {
  const _CustomerList({required this.customers});

  final List<SalesCustomer> customers;

  @override
  State<_CustomerList> createState() => _CustomerListState();
}

class _CustomerListState extends State<_CustomerList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.customers.where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VouchFlowSearchField(placeholder: 'sal.searchCustomers'.tr, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++)
          VouchFlowListRow(
            divider: i > 0,
            icon: PhosphorIconsRegular.storefront,
            iconColor: context.vf.successStrong,
            title: rows[i].name,
            subtitle: [rows[i].code, ?rows[i].city].join(' · '),
            onTap: () => Navigator.of(context).pop(rows[i].id),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
