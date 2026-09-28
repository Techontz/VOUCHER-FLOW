import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/vouchers_models.dart';
import '../../widgets/vf/vf.dart';
import 'create_voucher_page.dart';
import 'voucher_form_bits.dart';

/// "STEP n OF 5", the step's title and line, then a rule — the web's StepHead.
class StepHead extends StatelessWidget {
  const StepHead({super.key, required this.n, required this.title, this.sub});

  final int n;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VouchFlowEyebrow('create.stepOf'.trParams({'n': '$n'})),
          const SizedBox(height: 6),
          Text(
            title,
            style: VfType.sectionTitle.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!, style: VfType.body.copyWith(color: t.muted)),
          ],
        ],
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
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
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
              Expanded(
                child: i + j < children.length
                    ? children[i + j]
                    : const SizedBox.shrink(),
              ),
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
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          fields[i],
        ],
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(width: 14),
        Expanded(child: fields[i]),
      ],
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
  return (
    PhosphorIconsBold.file,
    VfCardTone.slate,
    'create.type.numbered'.trParams({'n': type.nextNumberPreview}),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.n,
    required this.title,
    required this.sub,
  });

  final int n;
  final String title, sub;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$n.   $title',
          style: VfType.cardTitle.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(sub, style: VfType.small.copyWith(fontSize: 14.5, color: t.muted)),
        const SizedBox(height: 14),
      ],
    );
  }
}

/* ── 1 · type ─────────────────────────────────────────────────────────── */

class TypeStep extends StatelessWidget {
  const TypeStep({super.key, required this.c, required this.wide});

  final CreateVoucherController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final typeError = c.errorFor('voucher_type_id');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(
          n: 1,
          title: 'create.chooseFormat'.tr,
          sub: 'create.chooseFormatSub'.tr,
        ),
        _SectionTitle(
          n: 1,
          title: 'create.methodTitle'.tr,
          sub: 'create.methodSub'.tr,
        ),
        gridOf(
          [
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
          ],
          wide ? 2 : 1,
          gap: 14,
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 24),
          height: 1,
          color: t.border,
        ),
        _SectionTitle(
          n: 2,
          title: 'create.typeTitle'.tr,
          sub: 'create.typeSub'.tr,
        ),
        if (!c.typesLoaded.value)
          const VouchFlowLoadingState(rows: 3, rowHeight: 76)
        else if (c.typesError.value != null && c.types.isEmpty)
          VouchFlowErrorState(
            message: c.typesError.value!,
            retryLabel: 'create.retry'.tr,
            onRetry: c.loadOptions,
          )
        else if (c.types.isEmpty)
          VouchFlowAlert(message: 'create.noTypes'.tr, tone: VfTone.warn)
        else
          gridOf([
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
          ], wide ? 2 : 1),
        if (typeError != null) ...[
          const SizedBox(height: 10),
          _FieldError(typeError),
        ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          PhosphorIconsRegular.warningCircle,
          size: 15,
          color: t.dangerStrong,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: VfType.meta.copyWith(color: t.dangerStrong)),
        ),
      ],
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
        StepHead(
          n: 2,
          title: 'create.stepDetails'.tr,
          sub: 'create.detailsSub'.tr,
        ),
        VouchFlowTextField(
          label: 'create.payee'.tr,
          controller: c.payee,
          required: true,
          placeholder: 'create.payeePh'.tr,
          error: c.errorFor('payee'),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        _gap(),
        VouchFlowTextField(
          label: 'create.purpose'.tr,
          controller: c.purpose,
          required: true,
          hint: 'create.purposeHint'.tr,
          error: c.errorFor('purpose'),
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
        ),
        _gap(),
        formRow(wide, [
          // A voucher stays in the requester's own department; the API refuses any other.
          VouchFlowDropdown<int>(
            key: ValueKey('dept-${c.departmentId.value}-${deptIds.length}'),
            label: 'create.department'.tr,
            items: deptIds,
            value: c.departmentId.value,
            placeholder: '—',
            hint: 'create.ownDepartmentOnly'.tr,
            error: c.errorFor('department_id'),
            itemLabel: (id) =>
                c.departments.firstWhereOrNull((d) => d.id == id)?.name ?? '—',
            onChanged: null,
          ),
          VouchFlowDropdown<String>(
            key: ValueKey('cat-${c.category.value}'),
            label: 'create.category'.tr,
            items: voucherCategories,
            value: c.category.value,
            itemLabel: (v) => v,
            onChanged: (v) => c.category.value = v ?? c.category.value,
          ),
        ]),
        _gap(),
        formRow(wide, [
          VfDateInput(
            label: 'create.date'.tr,
            value: c.voucherDate.value,
            error: c.errorFor('voucher_date'),
            onChanged: (d) {
              if (d != null) c.voucherDate.value = d;
            },
          ),
          VouchFlowTextField(
            label: 'create.requester'.tr,
            initialValue: currentUser().name,
            readOnly: true,
          ),
        ]),
        _gap(),
        VouchFlowTextField(
          label: 'create.description'.tr,
          controller: c.description,
          hint: 'create.optional'.tr,
          error: c.errorFor('description'),
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
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
        StepHead(
          n: 3,
          title: 'create.stepPayment'.tr,
          sub: bank ? 'create.paymentSubBank'.tr : 'create.paymentSubCash'.tr,
        ),
        VouchFlowField(
          label: 'create.amount'.tr,
          required: true,
          error: amountError,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('cur-${c.currency.value}'),
                  initialValue: voucherCurrencies.contains(c.currency.value)
                      ? c.currency.value
                      : null,
                  isExpanded: true,
                  icon: Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 14,
                    color: t.muted,
                  ),
                  dropdownColor: t.surface,
                  borderRadius: BorderRadius.circular(VfSize.radiusL),
                  style: VfType.bodyStrong.copyWith(color: t.text),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: t.surface2,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                  ),
                  items: [
                    for (final cur in voucherCurrencies)
                      DropdownMenuItem(value: cur, child: Text(cur)),
                  ],
                  onChanged: (v) => c.currency.value = v ?? c.currency.value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: c.amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  style: VfType.figureS.copyWith(
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    errorText: hasError ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (c.amountValue > 0) ...[
          const SizedBox(height: 8),
          Text(
            c.words,
            style: VfType.small.copyWith(
              color: t.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        _gap(),
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
            placeholder: 'INV-88213',
            hint: 'create.accountRefHint'.tr,
            error: c.errorFor('account_ref'),
          ),
        ]),
        _gap(20),
        // The two formats settle differently: a bank voucher needs an account
        // to pay into; a cash voucher needs the float it comes out of.
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
                  placeholder: c.payee.text.isNotEmpty
                      ? c.payee.text
                      : 'create.accountHolder'.tr,
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
                hint: 'create.payFromHint'.tr,
                error: c.errorFor('cash_float'),
              ),
              VfNote('create.cashReceiptNote'.tr),
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
        StepHead(
          n: 4,
          title: 'create.stepDocs'.tr,
          sub: 'create.documentsSub'.tr,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(VfSize.radiusXl),
            border: Border.all(color: t.borderStrong, width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsRegular.uploadSimple,
                  size: 22,
                  color: t.primaryText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'create.dropFiles'.tr,
                textAlign: TextAlign.center,
                style: VfType.bodyStrong.copyWith(color: t.text),
              ),
              const SizedBox(height: 2),
              Text(
                'create.fileRules'.trParams({'mb': '$maxUploadMb'}),
                textAlign: TextAlign.center,
                style: VfType.small.copyWith(color: t.muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  VouchFlowButton(
                    label: 'create.browseFiles'.tr,
                    icon: PhosphorIconsRegular.folderOpen,
                    variant: VfButtonVariant.secondary,
                    onPressed: c.browseFiles,
                  ),
                  VouchFlowButton(
                    label: 'create.takePhoto'.tr,
                    icon: PhosphorIconsRegular.camera,
                    variant: VfButtonVariant.secondary,
                    onPressed: c.takePhoto,
                  ),
                ],
              ),
            ],
          ),
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
        if (filesError != null) ...[
          const SizedBox(height: 10),
          _FieldError(filesError),
        ],
        if (c.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final f in c.files)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(VfSize.radiusL),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: BorderRadius.circular(VfSize.radiusM),
                    ),
                    child: Icon(
                      f.isImage
                          ? PhosphorIconsRegular.image
                          : PhosphorIconsRegular.filePdf,
                      size: 20,
                      color: t.text2,
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
                          style: VfType.label.copyWith(color: t.text),
                        ),
                        Text(
                          formatBytes(f.size),
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  VouchFlowIconButton(
                    icon: PhosphorIconsRegular.x,
                    tooltip: 'create.removeFile'.trParams({'name': f.name}),
                    onPressed: () => c.removeFile(f),
                  ),
                ],
              ),
            ),
        ],
        _gap(20),
        VouchFlowTextField(
          label: 'create.notesApprover'.tr,
          controller: c.notes,
          hint: 'create.optional'.tr,
          error: c.errorFor('notes_to_approver'),
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
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
    final bankLine = [
      c.payeeBank.text,
      c.payeeAccountNumber.text,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHead(
          n: 5,
          title: 'create.reviewVoucher'.tr,
          sub: 'create.reviewSub'.tr,
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VouchFlowEyebrow('create.amount'.tr),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  previewMoney(c),
                  style: VfType.figure.copyWith(
                    fontSize: 24,
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (c.amountValue > 0) ...[
                const SizedBox(height: 6),
                Text(
                  c.words,
                  style: VfType.small.copyWith(
                    color: t.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ReviewRow('create.stepType'.tr, c.selectedType?.label, () => c.go(0)),
        _ReviewRow(
          'create.voucherFormat'.tr,
          bank ? 'create.bankVoucher'.tr : 'create.cashVoucher'.tr,
          () => c.go(0),
        ),
        _ReviewRow('create.payee'.tr, c.payee.text, () => c.go(1)),
        _ReviewRow('create.purpose'.tr, c.purpose.text, () => c.go(1)),
        _ReviewRow('create.department'.tr, c.department?.name, () => c.go(1)),
        _ReviewRow('create.paymentMethod'.tr, c.method.value, () => c.go(2)),
        if (bank && bankLine.isNotEmpty)
          _ReviewRow('create.bank'.tr, bankLine, () => c.go(2)),
        _ReviewRow(
          'create.attachments'.tr,
          n == 0
              ? 'create.noneAttached'.tr
              : (n == 1
                    ? 'create.oneFile'.tr
                    : 'create.nFiles'.trParams({'n': '$n'})),
          () => c.go(3),
          last: true,
        ),
        // The route comes from the company's configured workflow, not a guess.
        if (route.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(VfSize.radiusL),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VouchFlowEyebrow('create.approvalRoute'.tr),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < route.length; i++) ...[
                      if (i > 0)
                        Icon(
                          PhosphorIconsRegular.arrowRight,
                          size: 14,
                          color: t.faint,
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(
                            VfSize.radiusPill,
                          ),
                          border: Border.all(color: t.border),
                        ),
                        child: Text(
                          route[i],
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, this.onEdit, {this.last = false});

  final String label;
  final String? value;
  final VoidCallback onEdit;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: VfType.small.copyWith(color: t.muted)),
                const SizedBox(height: 2),
                Text(
                  (value ?? '').isEmpty ? '—' : value!,
                  style: VfType.bodyStrong.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          VouchFlowButton(
            label: 'create.edit'.tr,
            variant: VfButtonVariant.ghost,
            height: 44,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
