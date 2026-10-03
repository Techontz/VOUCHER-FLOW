import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/vouchers_models.dart';
import '../../widgets/vf/vf.dart';
import 'create_voucher_page.dart';
import 'voucher_form_bits.dart';

/// A step's one short question, large and bold.
class StepHead extends StatelessWidget {
  const StepHead({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(title, style: VfType.pageTitle.copyWith(fontSize: 24, color: t.text)),
    );
  }
}

/// A rounded surface that groups a step's fields, the way native forms do.
class FormGroup extends StatelessWidget {
  const FormGroup({super.key, required this.children, this.padding = const EdgeInsets.all(16)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: t.isDark ? Border.all(color: t.border) : null,
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 16), children[i]],
        ],
      ),
    );
  }
}

/// A small label over a group of choices.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: VfType.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: t.muted),
      ),
    );
  }
}

/// Lays children out in [columns] equal columns, rows of equal height.
Widget gridOf(List<Widget> children, int columns, {double gap = 12}) {
  if (columns <= 1) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i += columns) {
    if (i > 0) rows.add(SizedBox(height: gap));
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()),
            ],
          ],
        ),
      ),
    );
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

/// Two fields side by side where there is room (the web's `.vf-form-row`).
Widget formRow(bool wide, List<Widget> fields) {
  if (!wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(height: 16), fields[i]],
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: fields[i])],
    ],
  );
}

Widget _gap([double h = 16]) => SizedBox(height: h);

/// How a voucher type is drawn: icon, tone and a line saying what it is for.
/// The six standard types are known by code; a company's own gets a neutral
/// look and its numbering as the description.
(IconData, VfCardTone, String) typeLook(VoucherTypeOption type) {
  final known = <String, (IconData, VfCardTone)>{
    'payment': (PhosphorIconsBold.fileText, VfCardTone.blue),
    'petty_cash': (PhosphorIconsBold.wallet, VfCardTone.orange),
    'expense': (PhosphorIconsBold.receipt, VfCardTone.violet),
    'advance': (PhosphorIconsBold.arrowRight, VfCardTone.teal),
    'reimbursement': (PhosphorIconsBold.arrowsClockwise, VfCardTone.rose),
    'other': (PhosphorIconsBold.dotsThree, VfCardTone.slate),
  };
  final k = known[type.code];
  if (k != null) return (k.$1, k.$2, 'create.type.${type.code}'.tr);
  return (PhosphorIconsBold.file, VfCardTone.slate, 'create.type.numbered'.trParams({'n': type.nextNumberPreview}));
}

/* ── 1 · type ─────────────────────────────────────────────────────────── */

class TypeStep extends StatelessWidget {
  const TypeStep({super.key, required this.c, required this.wide});

  final CreateVoucherController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final typeError = c.errorFor('voucher_type_id');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(title: 'create.chooseFormat'.tr),
        _GroupLabel('create.methodTitle'.tr),
        gridOf([
          VouchFlowSelectCard(
            large: true,
            selected: c.kind.value == 'bank',
            tone: VfCardTone.blue,
            icon: PhosphorIconsBold.bank,
            title: 'create.bankVoucher'.tr,
            subtitle: 'create.bankSub'.tr,
            onTap: () => c.chooseKind('bank'),
          ),
          VouchFlowSelectCard(
            large: true,
            selected: c.kind.value == 'cash',
            tone: VfCardTone.green,
            icon: PhosphorIconsBold.money,
            title: 'create.cashVoucher'.tr,
            subtitle: 'create.cashSub'.tr,
            onTap: () => c.chooseKind('cash'),
          ),
        ], wide ? 2 : 1),
        _gap(26),
        _GroupLabel('create.typeTitle'.tr),
        if (!c.typesLoaded.value)
          const VouchFlowLoadingState(rows: 3, rowHeight: 72)
        else if (c.typesError.value != null && c.types.isEmpty)
          VouchFlowErrorState(message: c.typesError.value!, retryLabel: 'create.retry'.tr, onRetry: c.loadOptions)
        else if (c.types.isEmpty)
          VouchFlowAlert(message: 'create.noTypes'.tr, tone: VfTone.warn)
        else
          gridOf(
            [
              for (final type in c.types)
                Builder(
                  builder: (_) {
                    final (icon, tone, sub) = typeLook(type);
                    return VouchFlowSelectCard(
                      selected: c.typeId.value == type.id,
                      tone: tone,
                      icon: icon,
                      title: type.label,
                      subtitle: sub,
                      onTap: () => c.typeId.value = type.id,
                    );
                  },
                ),
            ],
            wide ? 2 : 1,
            gap: 10,
          ),
        if (typeError != null) ...[const SizedBox(height: 10), _FieldError(typeError)],
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 15, color: t.dangerStrong),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: VfType.meta.copyWith(color: t.dangerStrong)),
          ),
        ],
      ),
    );
  }
}

/* ── 2 · details ──────────────────────────────────────────────────────── */

class DetailsStep extends StatelessWidget {
  const DetailsStep({super.key, required this.c, required this.wide});

  final CreateVoucherController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final deptIds = c.departments.map((d) => d.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(title: 'create.q.details'.tr),
        FormGroup(
          children: [
            VouchFlowTextField(
              label: 'create.payee'.tr,
              controller: c.payee,
              required: true,
              placeholder: 'create.payeePh'.tr,
              error: c.errorFor('payee'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            VouchFlowTextField(
              label: 'create.purpose'.tr,
              controller: c.purpose,
              required: true,
              error: c.errorFor('purpose'),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
            ),
            VouchFlowTextField(
              label: 'create.description'.tr,
              controller: c.description,
              placeholder: 'create.optional'.tr,
              error: c.errorFor('description'),
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        _gap(14),
        FormGroup(
          children: [
            formRow(wide, [
              VouchFlowDropdown<String>(
                key: ValueKey('cat-${c.category.value}'),
                label: 'create.category'.tr,
                items: voucherCategories,
                value: c.category.value,
                itemLabel: (v) => v,
                onChanged: (v) => c.category.value = v ?? c.category.value,
              ),
              VfDateInput(
                label: 'create.date'.tr,
                value: c.voucherDate.value,
                error: c.errorFor('voucher_date'),
                onChanged: (d) {
                  if (d != null) c.voucherDate.value = d;
                },
              ),
            ]),
            formRow(wide, [
              // A voucher stays in the requester's own department; the API
              // refuses any other, so the field is locked.
              VouchFlowDropdown<int>(
                key: ValueKey('dept-${c.departmentId.value}-${deptIds.length}'),
                label: 'create.department'.tr,
                items: deptIds,
                value: c.departmentId.value,
                placeholder: '—',
                error: c.errorFor('department_id'),
                itemLabel: (id) => c.departments.firstWhereOrNull((d) => d.id == id)?.name ?? '—',
                onChanged: null,
              ),
              VouchFlowTextField(label: 'create.requester'.tr, initialValue: currentUser().name, readOnly: true),
            ]),
          ],
        ),
      ],
    );
  }
}

/* ── 3 · payment ──────────────────────────────────────────────────────── */

class PaymentStep extends StatelessWidget {
  const PaymentStep({super.key, required this.c, required this.wide});

  final CreateVoucherController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final bank = c.kind.value == 'bank';
    final company = c.session.company.value;
    final amountError = c.errorFor('amount');
    final hasError = amountError != null && amountError.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(title: 'create.q.payment'.tr),
        FormGroup(
          children: [
            VouchFlowField(
              label: 'create.amount'.tr,
              required: true,
              error: amountError,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('cur-${c.currency.value}'),
                      initialValue: voucherCurrencies.contains(c.currency.value) ? c.currency.value : null,
                      isExpanded: true,
                      icon: Icon(PhosphorIconsBold.caretDown, size: 13, color: t.primaryText),
                      dropdownColor: t.surface,
                      borderRadius: BorderRadius.circular(vfInputRadius),
                      style: VfType.bodyStrong.copyWith(color: t.primaryText),
                      decoration: vfInputDecoration(
                        context,
                        contentPadding: const EdgeInsets.fromLTRB(14, 19, 10, 19),
                      ).copyWith(fillColor: t.primarySoft),
                      items: [for (final cur in voucherCurrencies) DropdownMenuItem(value: cur, child: Text(cur))],
                      onChanged: (v) => c.currency.value = v ?? c.currency.value,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: c.amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      cursorColor: t.primary,
                      style: VfType.figureS.copyWith(color: t.text, fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: vfInputDecoration(
                        context,
                        hintText: '0',
                        hasError: hasError,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      ).copyWith(hintStyle: VfType.figureS.copyWith(color: t.placeholder)),
                    ),
                  ),
                ],
              ),
            ),
            if (c.amountValue > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  c.words,
                  style: VfType.small.copyWith(color: t.muted, fontStyle: FontStyle.italic),
                ),
              ),
            formRow(wide, [
              VouchFlowDropdown<String>(
                key: ValueKey('method-${c.method.value}'),
                label: 'create.paymentMethod'.tr,
                items: voucherMethods,
                value: c.method.value,
                itemLabel: (v) => v,
                onChanged: (v) => c.method.value = v ?? c.method.value,
              ),
              VouchFlowTextField(
                label: 'create.accountRef'.tr,
                controller: c.accountRef,
                placeholder: 'create.accountRefHint'.tr,
                error: c.errorFor('account_ref'),
              ),
            ]),
          ],
        ),
        _gap(14),
        // The two formats settle differently: a bank voucher needs an account
        // to pay into; a cash voucher needs the float it comes out of.
        FormGroup(
          children: [
            if (bank)
              VfFieldset(
                legend: 'create.payeeBankDetails'.tr,
                children: [
                  formRow(wide, [
                    VouchFlowTextField(
                      label: 'create.bank'.tr,
                      controller: c.payeeBank,
                      placeholder: 'CRDB Bank',
                      error: c.errorFor('payee_bank'),
                    ),
                    VouchFlowTextField(
                      label: 'create.branch'.tr,
                      controller: c.payeeBankBranch,
                      placeholder: 'Tower Branch',
                    ),
                  ]),
                  formRow(wide, [
                    VouchFlowTextField(
                      label: 'create.accountName'.tr,
                      controller: c.payeeAccountName,
                      placeholder: c.payee.text.isNotEmpty ? c.payee.text : 'create.accountHolder'.tr,
                    ),
                    VouchFlowTextField(
                      label: 'create.accountNo'.tr,
                      controller: c.payeeAccountNumber,
                      placeholder: '0150000000000',
                      keyboardType: TextInputType.number,
                      error: c.errorFor('payee_account_number'),
                    ),
                  ]),
                  if ((company?.bankAccountNumber ?? '').isNotEmpty)
                    VfNote(
                      '${'create.drawnOn'.tr}: ${[company!.bankName, company.bankAccountNumber, company.bankBranch].whereType<String>().where((s) => s.isNotEmpty).join(' · ')}',
                    ),
                ],
              )
            else
              VfFieldset(
                legend: 'create.cashDetails'.tr,
                children: [
                  VouchFlowTextField(
                    label: 'create.payFrom'.tr,
                    controller: c.cashFloat,
                    placeholder: 'create.payFromPh'.tr,
                    error: c.errorFor('cash_float'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/* ── 4 · documents ────────────────────────────────────────────────────── */

class DocumentsStep extends StatelessWidget {
  const DocumentsStep({super.key, required this.c});

  final CreateVoucherController c;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final filesError = c.errorFor('files');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(title: 'create.q.docs'.tr),
        Row(
          children: [
            Expanded(
              child: _PickTile(
                icon: PhosphorIconsFill.folderOpen,
                label: 'create.browseFiles'.tr,
                onTap: c.browseFiles,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PickTile(icon: PhosphorIconsFill.camera, label: 'create.takePhoto'.tr, onTap: c.takePhoto),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'create.fileRules'.trParams({'mb': '$maxUploadMb'}),
          textAlign: TextAlign.center,
          style: VfType.meta.copyWith(color: t.faint),
        ),
        if (c.rejected.isNotEmpty) ...[
          const SizedBox(height: 12),
          VouchFlowAlert(
            tone: VfTone.bad,
            icon: PhosphorIconsRegular.warningCircle,
            title: 'create.filesNotAdded'.tr,
            message: c.rejected
                .map(
                  (r) =>
                      '${r.name} — ${switch (r.reason) {
                        'type' => 'create.fileWrongType'.tr,
                        'size' => '${'create.fileTooLarge'.tr} $maxUploadMb MB',
                        _ => 'create.fileTooMany'.tr,
                      }}',
                )
                .join('\n'),
          ),
        ],
        if (filesError != null) ...[const SizedBox(height: 10), _FieldError(filesError)],
        if (c.files.isNotEmpty) ...[
          const SizedBox(height: 16),
          FormGroup(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            children: [
              for (final f in c.files)
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: f.isImage ? t.infoSoft : t.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        f.isImage ? PhosphorIconsFill.image : PhosphorIconsFill.filePdf,
                        size: 21,
                        color: f.isImage ? t.infoStrong : t.dangerStrong,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.label.copyWith(color: t.text, fontWeight: FontWeight.w600),
                          ),
                          Text(formatBytes(f.size), style: VfType.meta.copyWith(color: t.muted)),
                        ],
                      ),
                    ),
                    VouchFlowIconButton(
                      icon: PhosphorIconsRegular.x,
                      tooltip: 'create.removeFile'.trParams({'name': f.name}),
                      size: 40,
                      color: t.muted,
                      onPressed: () => c.removeFile(f),
                    ),
                  ],
                ),
            ],
          ),
        ],
        _gap(16),
        FormGroup(
          children: [
            VouchFlowTextField(
              label: 'create.notesApprover'.tr,
              controller: c.notes,
              placeholder: 'create.optional'.tr,
              error: c.errorFor('notes_to_approver'),
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ],
    );
  }
}

/// A big square-ish tap target for adding documents.
class _PickTile extends StatelessWidget {
  const _PickTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final radius = BorderRadius.circular(VfSize.radiusXl);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: radius,
        border: t.isDark ? Border.all(color: t.border) : null,
        boxShadow: t.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
                  child: Icon(icon, size: 26, color: t.primaryText),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(fontSize: 14.5, color: t.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ── 5 · review ───────────────────────────────────────────────────────── */

class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.c});

  final CreateVoucherController c;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final bank = c.kind.value == 'bank';
    final n = c.files.length;
    final route = c.route;
    final bankLine = [c.payeeBank.text, c.payeeAccountNumber.text].where((s) => s.isNotEmpty).join(' · ');
    final rows = <Widget>[
      _ReviewRow('create.stepType'.tr, c.selectedType?.label, () => c.go(0)),
      _ReviewRow('create.voucherFormat'.tr, bank ? 'create.bankVoucher'.tr : 'create.cashVoucher'.tr, () => c.go(0)),
      _ReviewRow('create.payee'.tr, c.payee.text, () => c.go(1)),
      _ReviewRow('create.purpose'.tr, c.purpose.text, () => c.go(1)),
      _ReviewRow('create.department'.tr, c.department?.name, () => c.go(1)),
      _ReviewRow('create.paymentMethod'.tr, c.method.value, () => c.go(2)),
      if (bank && bankLine.isNotEmpty) _ReviewRow('create.bank'.tr, bankLine, () => c.go(2)),
      _ReviewRow(
        'create.attachments'.tr,
        n == 0 ? 'create.noneAttached'.tr : (n == 1 ? 'create.oneFile'.tr : 'create.nFiles'.trParams({'n': '$n'})),
        () => c.go(3),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(title: 'create.reviewVoucher'.tr),
        // The total, highlighted in the brand colour.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VfSize.radiusXl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.primary, Color.lerp(t.primary, Colors.black, .28)!],
            ),
            boxShadow: [
              BoxShadow(
                color: t.primary.withValues(alpha: .30),
                blurRadius: 24,
                spreadRadius: -10,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'create.total'.tr,
                style: VfType.label.copyWith(color: Colors.white.withValues(alpha: .78), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  previewMoney(c),
                  style: VfType.figure.copyWith(
                    fontSize: 30,
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (c.amountValue > 0) ...[
                const SizedBox(height: 6),
                Text(
                  c.words,
                  style: VfType.small.copyWith(color: Colors.white.withValues(alpha: .78), fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        FormGroup(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: t.border),
                  rows[i],
                ],
              ],
            ),
          ],
        ),
        // The route comes from the company's configured workflow, not a guess.
        if (route.isNotEmpty) ...[
          const SizedBox(height: 14),
          FormGroup(
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsFill.flowArrow, size: 18, color: t.primaryText),
                  const SizedBox(width: 8),
                  Text(
                    'create.approvalRoute'.tr,
                    style: VfType.bodyStrong.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.text),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < route.length; i++) ...[
                    if (i > 0) Icon(PhosphorIconsBold.caretRight, size: 12, color: t.faint),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.primarySoft,
                        borderRadius: BorderRadius.circular(VfSize.radiusPill),
                      ),
                      child: Text(
                        route[i],
                        style: VfType.small.copyWith(color: t.primaryText, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A label / value line in the review summary; tapping it goes to its step.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, this.onEdit);

  final String label;
  final String? value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      hint: 'create.edit'.tr,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(label, style: VfType.small.copyWith(color: t.muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  (value ?? '').isEmpty ? '—' : value!,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(PhosphorIconsBold.caretRight, size: 13, color: t.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
