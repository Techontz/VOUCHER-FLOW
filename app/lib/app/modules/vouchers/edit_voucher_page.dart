import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/models/vouchers_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/create_repository.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import 'create_steps.dart' show formRow;
import 'voucher_form_bits.dart';

/// The edit form's categories (web `/vouchers/{id}/edit`).
const editCategories = [
  'Logistics',
  'Premises',
  'Transport',
  'Capital equipment',
  'Professional fees', //
  'Staff welfare', 'Utilities', 'Other',
];
const _methods = ['Bank Transfer', 'Mobile Money', 'Cash', 'Cheque'];
const _currencies = ['TZS', 'USD', 'KES', 'EUR'];

/// Opens a voucher's edit form over the current page. Resolves to true when
/// the voucher was saved or submitted, so the caller can reload it.
Future<bool> openEditVoucher(int id) async =>
    await Get.to<bool>(() => EditVoucherPage(voucherId: id)) == true;

/// Editing a draft or a voucher returned for changes: the web's single-page
/// form in four sections, then Cancel / Save changes / Submit voucher.
class EditVoucherPage extends StatefulWidget {
  const EditVoucherPage({super.key, required this.voucherId});

  final int voucherId;

  @override
  State<EditVoucherPage> createState() => _EditVoucherPageState();
}

class _EditVoucherPageState extends State<EditVoucherPage> {
  final _vouchers = Get.find<VoucherRepository>();

  Voucher? _voucher;
  String? _loadError;
  String? _busy;
  Map<String, String> _errors = {};
  List<VoucherTypeOption> _types = [];
  List<Department> _departments = [];

  int? _typeId;
  int? _departmentId;
  DateTime _date = DateTime.now();
  String _currency = 'TZS';
  String _method = 'Bank Transfer';
  String _category = 'Logistics';

  final _payee = TextEditingController();
  final _purpose = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    CreateRepository.to
        .types()
        .then((v) => mounted ? setState(() => _types = v) : null)
        .catchError((_) => null);
    _vouchers
        .departments()
        .then((v) => mounted ? setState(() => _departments = v) : null)
        .catchError((_) => null);
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final v = await _vouchers.show(widget.voucherId);
      if (!mounted) return;
      setState(() {
        _voucher = v;
        _typeId = v.voucherTypeId;
        _departmentId = v.departmentId;
        _date = v.voucherDate ?? DateTime.now();
        _currency = v.currency;
        _method = v.paymentMethod ?? 'Bank Transfer';
        _category = v.category ?? 'Logistics';
        _payee.text = v.payee;
        _purpose.text = v.purpose;
        _description.text = v.description ?? '';
        _amount.text = v.amount % 1 == 0
            ? v.amount.toStringAsFixed(0)
            : '${v.amount}';
        _ref.text = v.accountRef ?? '';
        _notes.text = v.notesToApprover ?? '';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'create.offline'.tr);
    }
  }

  Future<void> _save({required bool submit}) async {
    final v = _voucher;
    if (v == null || _busy != null) return;
    setState(() {
      _busy = submit ? 'submit' : 'save';
      _errors = {};
    });
    try {
      await _vouchers.update(v.id, {
        'voucher_type_id': _typeId,
        'department_id': _departmentId,
        'payee': _payee.text,
        'purpose': _purpose.text,
        'description': _description.text,
        'amount': parseAmount(_amount.text),
        'currency': _currency,
        'payment_method': _method,
        'account_ref': _ref.text,
        'category': _category,
        'voucher_date': apiDate(_date),
        'notes_to_approver': _notes.text,
      });
      if (submit) {
        final sent = await _vouchers.submit(v.id);
        showToast(
          'create.submitted'.tr,
          body: '${sent.number} — ${sent.statusLabel}',
        );
      } else {
        showToast('create.changesSaved'.tr, body: v.number);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      showToast('create.couldNotSave'.tr, body: e.message, kind: ToastKind.bad);
      if (mounted) {
        setState(() {
          _errors = e.errors.map(
            (k, m) => MapEntry(k, m.isEmpty ? '' : m.first),
          );
          _busy = null;
        });
      }
    } catch (_) {
      showToast(
        'create.couldNotSave'.tr,
        body: 'create.offline'.tr,
        kind: ToastKind.bad,
      );
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  void dispose() {
    for (final c in [_payee, _purpose, _description, _amount, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _voucher;
    final title = v?.number ?? 'create.edit'.tr;

    if (_loadError != null) {
      return VouchFlowPushedScaffold(
        title: title,
        body: Center(
          child: VouchFlowEmptyState(
            icon: PhosphorIconsRegular.lockKey,
            title: 'create.notAuthorised'.tr,
            body: _loadError,
            actionLabel: 'create.retry'.tr,
            onAction: _load,
          ),
        ),
      );
    }
    if (v == null) {
      return VouchFlowPushedScaffold(
        title: title,
        body: const Padding(
          padding: EdgeInsets.all(VfSize.pagePad),
          child: VouchFlowLoadingState(rows: 6, rowHeight: 72),
        ),
      );
    }
    if (!v.actions.edit) {
      return VouchFlowPushedScaffold(
        title: title,
        body: Center(
          child: VouchFlowEmptyState(
            icon: PhosphorIconsRegular.lockKey,
            title: 'create.cannotEdit'.tr,
            body: 'create.cannotEditBody'.trParams({
              'number': v.number,
              'status': v.statusLabel.toLowerCase(),
            }),
            actionLabel: 'create.back'.tr,
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    return VouchFlowPushedScaffold(
      title: title,
      bottomBar: _footer(context),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 600;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              VfSize.pagePad,
              20,
              VfSize.pagePad,
              28 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              VouchFlowPageHeader(
                kicker: 'create.editKicker'.trParams({'status': v.statusLabel}),
                title: v.purpose.isNotEmpty ? v.purpose : v.number,
                subtitle: v.number,
              ),
              const SizedBox(height: 18),
              VouchFlowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'create.stepType'.tr,
                      description: 'create.detailsSub'.tr,
                      children: [
                        formRow(wide, [
                          VouchFlowDropdown<int>(
                            key: ValueKey('type-$_typeId-${_types.length}'),
                            label: 'create.stepType'.tr,
                            items: _types.isEmpty && _typeId != null
                                ? [_typeId!]
                                : _types.map((x) => x.id).toList(),
                            value: _typeId,
                            itemLabel: (id) =>
                                _types
                                    .firstWhereOrNull((x) => x.id == id)
                                    ?.label ??
                                v.voucherTypeLabel ??
                                '—',
                            error: _errors['voucher_type_id'],
                            onChanged: (id) =>
                                setState(() => _typeId = id ?? _typeId),
                          ),
                          VfDateInput(
                            label: 'create.date'.tr,
                            value: _date,
                            error: _errors['voucher_date'],
                            onChanged: (d) =>
                                setState(() => _date = d ?? _date),
                          ),
                        ]),
                        formRow(wide, [
                          // The API keeps a voucher in its own department.
                          VouchFlowDropdown<int>(
                            key: ValueKey(
                              'dept-$_departmentId-${_departments.length}',
                            ),
                            label: 'create.department'.tr,
                            items: _departments.map((d) => d.id).toList(),
                            value: _departmentId,
                            placeholder: v.departmentName ?? '—',
                            hint: 'create.ownDepartmentOnly'.tr,
                            error: _errors['department_id'],
                            itemLabel: (id) =>
                                _departments
                                    .firstWhereOrNull((d) => d.id == id)
                                    ?.name ??
                                '—',
                            onChanged: null,
                          ),
                          VouchFlowDropdown<String>(
                            key: ValueKey('cat-$_category'),
                            label: 'create.category'.tr,
                            items: editCategories.contains(_category)
                                ? editCategories
                                : [_category, ...editCategories],
                            value: _category,
                            itemLabel: (x) => x,
                            onChanged: (x) =>
                                setState(() => _category = x ?? _category),
                          ),
                        ]),
                      ],
                    ),
                    _Section(
                      title: 'create.stepDetails'.tr,
                      children: [
                        VouchFlowTextField(
                          label: 'create.payee'.tr,
                          controller: _payee,
                          required: true,
                          error: _errors['payee'],
                        ),
                        VouchFlowTextField(
                          label: 'create.purpose'.tr,
                          controller: _purpose,
                          required: true,
                          error: _errors['purpose'],
                        ),
                        VouchFlowTextField(
                          label: 'create.description'.tr,
                          controller: _description,
                          maxLines: 5,
                          minLines: 3,
                          error: _errors['description'],
                        ),
                      ],
                    ),
                    _Section(
                      title: 'create.stepPayment'.tr,
                      description: 'create.paymentSubBank'.tr,
                      children: [
                        formRow(wide, [
                          VouchFlowTextField(
                            label: 'create.amount'.tr,
                            controller: _amount,
                            required: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            error: _errors['amount'],
                          ),
                          VouchFlowDropdown<String>(
                            key: ValueKey('cur-$_currency'),
                            label: 'create.currency'.tr,
                            items: _currencies.contains(_currency)
                                ? _currencies
                                : [_currency, ..._currencies],
                            value: _currency,
                            itemLabel: (x) => x,
                            onChanged: (x) =>
                                setState(() => _currency = x ?? _currency),
                          ),
                        ]),
                        VouchFlowDropdown<String>(
                          key: ValueKey('method-$_method'),
                          label: 'create.paymentMethod'.tr,
                          items: _methods.contains(_method)
                              ? _methods
                              : [_method, ..._methods],
                          value: _method,
                          itemLabel: (x) => x,
                          onChanged: (x) =>
                              setState(() => _method = x ?? _method),
                        ),
                        VouchFlowTextField(
                          label: 'create.accountRef'.tr,
                          controller: _ref,
                          error: _errors['account_ref'],
                        ),
                      ],
                    ),
                    _Section(
                      title: 'create.notesSection'.tr,
                      last: true,
                      children: [
                        VouchFlowTextField(
                          label: 'create.notesApprover'.tr,
                          controller: _notes,
                          hint: 'create.optional'.tr,
                          maxLines: 5,
                          minLines: 3,
                          error: _errors['notes_to_approver'],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.surface2.withValues(alpha: .7), t.surface),
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < 420;
              Widget grow(Widget child) =>
                  narrow ? Expanded(child: child) : child;
              return Row(
                children: [
                  if (!narrow) ...[
                    VouchFlowButton(
                      label: 'create.cancel'.tr,
                      variant: VfButtonVariant.ghost,
                      height: 46,
                      onPressed: _busy != null
                          ? null
                          : () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                  ],
                  grow(
                    VouchFlowButton(
                      label: 'create.saveChanges'.tr,
                      variant: VfButtonVariant.secondary,
                      height: 46,
                      loading: _busy == 'save',
                      onPressed: _busy != null
                          ? null
                          : () => _save(submit: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  grow(
                    VouchFlowButton(
                      label: 'create.submitVoucher'.tr,
                      icon: narrow ? null : PhosphorIconsRegular.paperPlaneTilt,
                      height: 46,
                      loading: _busy == 'submit',
                      onPressed: _busy != null
                          ? null
                          : () => _save(submit: true),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The web's `FormSection`: a heading, an optional line, then its fields.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.description,
    required this.children,
    this.last = false,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 20),
      margin: EdgeInsets.only(bottom: last ? 0 : 20),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: VfType.cardTitle.copyWith(color: t.text)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: VfType.small.copyWith(color: t.muted)),
          ],
          for (final child in children) ...[const SizedBox(height: 16), child],
        ],
      ),
    );
  }
}
