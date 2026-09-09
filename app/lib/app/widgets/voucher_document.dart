import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme.dart';
import '../data/models/models.dart';
import 'common.dart';
import 'stamps.dart';

/// The voucher as it prints.
///
/// The same document the web client renders, at the same proportions: the
/// company's own letterhead, a ruled particulars table with the amount beneath
/// the description, the payment particulars alongside — which differ by format,
/// because a bank voucher settles into an account and a cash voucher comes out
/// of a float — and an authorisation band carrying every mark.
///
/// It is always white with dark ink, because it is a preview of paper.
class VoucherDocument extends StatelessWidget {
  const VoucherDocument({
    super.key,
    required this.voucher,
    required this.company,
    this.width = 794,
  });

  final Voucher voucher;
  final Company? company;

  /// A4 at 96dpi. The caller scales the whole sheet rather than reflowing it,
  /// so what is on screen is exactly what prints.
  final double width;

  @override
  Widget build(BuildContext context) {
    final locale = Get.locale?.languageCode ?? 'en';
    final isCash = voucher.isCash;
    final brand = _hexColour(company?.primaryColor) ?? VfColors.accent;

    final rows = voucher.timeline;
    TimelineEntry? find(bool Function(TimelineEntry) test) {
      for (final r in rows) {
        if (test(r)) return r;
      }
      return null;
    }

    final signRow = find(
      (r) => r.capabilitySign && !r.capabilityApprove && r.when != null,
    );
    final approveRow = find((r) => r.capabilityApprove && r.when != null);
    final payRow = find((r) => r.capabilityPay && r.when != null);

    /* A4 at 96dpi, fixed. The sheet keeps its real geometry and the caller
       scales the whole thing, so what is on screen is exactly what prints —
       and the ruled form can stretch to the page the way a voucher book does. */
    return Container(
      width: width,
      height: width * 1123 / 794,
      padding: const EdgeInsets.fromLTRB(46, 40, 46, 34),
      color: VfDoc.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            color: brand,
            margin: const EdgeInsets.only(bottom: 14),
          ),

          _Letterhead(voucher: voucher, company: company, isCash: isCash),

          const SizedBox(height: 11),
          _MetaStrip(voucher: voucher, locale: locale),

          const SizedBox(height: 13),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 155, child: _Particulars(voucher: voucher)),
                const SizedBox(width: 20),
                Expanded(
                  flex: 100,
                  child: _PaymentPanel(
                    voucher: voucher,
                    company: company,
                    isCash: isCash,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _Remarks(voucher: voucher),

          const SizedBox(height: 16),
          Text('AUTHORISATION', style: VfDoc.label),
          const SizedBox(height: 7),
          // A Column hands its non-flex children unbounded height, so a Row
          // that stretches its children needs an intrinsic height to size
          // against — otherwise it asks for infinity.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AuthorisationBlock(
                    caption: 'doc.preparedBy'.tr,
                    name: voucher.requesterName,
                    title: null,
                    date: Fmt.dateTime(voucher.submittedAt),
                    note: 'doc.notSubmitted'.tr,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: AuthorisationBlock(
                    caption: 'doc.signedBy'.tr,
                    name: signRow?.person,
                    title: signRow?.personTitle,
                    date: Fmt.dateTime(signRow?.when),
                    signature: signRow?.signature,
                    stamp: StampKind.signed,
                    note: 'doc.awaitingSignature'.tr,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: AuthorisationBlock(
                    caption: 'doc.approvedBy'.tr,
                    name: approveRow?.person,
                    title: approveRow?.personTitle,
                    date: Fmt.dateTime(approveRow?.when),
                    signature: approveRow?.signature,
                    stamp: voucher.status == 'rejected'
                        ? StampKind.rejected
                        : StampKind.approved,
                    note: 'doc.awaitingApproval'.tr,
                    emphasis: true,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: AuthorisationBlock(
                    caption: isCash ? 'doc.paidReceivedBy'.tr : 'doc.paidBy'.tr,
                    name: payRow?.person ?? voucher.paidBy,
                    title: payRow?.personTitle,
                    date: Fmt.dateTime(payRow?.when ?? voucher.paidAt),
                    signature: payRow?.signature,
                    stamp: StampKind.paid,
                    reference: voucher.paymentReference,
                    note: 'doc.awaitingPayment'.tr,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: VfDoc.rule)),
            ),
            child: Text(
              [
                company?.voucherFooterText ??
                    'This voucher is valid only with the authorisations above.',
                if (voucher.verificationCode != null)
                  'Verification code ${voucher.verificationCode}',
              ].join('\n'),
              style: VfDoc.faintStyle.copyWith(fontSize: 8, color: VfDoc.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Letterhead extends StatelessWidget {
  const _Letterhead({
    required this.voucher,
    required this.company,
    required this.isCash,
  });

  final Voucher voucher;
  final Company? company;
  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final logo = company?.logoUrl;

    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: VfDoc.ink, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logo != null && logo.isNotEmpty) ...[
            Image.asset(
              logo,
              height: 52,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  company?.legalName ?? company?.name ?? 'VouchFlow',
                  style: const TextStyle(
                    fontFamily: VfTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                    height: 1.2,
                    color: VfDoc.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    company?.address,
                    [company?.phone, company?.email]
                        .whereType<String>()
                        .where((v) => v.isNotEmpty)
                        .join(' · '),
                    [
                          company?.website,
                          company?.tin != null ? 'TIN ${company!.tin}' : null,
                        ]
                        .whereType<String>()
                        .where((v) => v.isNotEmpty)
                        .join(' · '),
                  ].whereType<String>().where((v) => v.isNotEmpty).join('\n'),
                  style: VfDoc.faintStyle.copyWith(
                    fontSize: 8.5,
                    color: VfDoc.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (voucher.voucherTypeLabel ?? 'Payment Voucher').toUpperCase(),
                style: const TextStyle(
                  fontFamily: VfTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: VfDoc.ink,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isCash
                        ? const Color(0xFFC48A1A)
                        : const Color(0xFF2F6FD0),
                  ),
                  color: isCash
                      ? const Color(0xFFFFF8EC)
                      : const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  isCash ? 'CASH VOUCHER' : 'BANK VOUCHER',
                  style: TextStyle(
                    fontFamily: VfTheme.fontFamily,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: isCash
                        ? const Color(0xFF8A5A00)
                        : const Color(0xFF1A4FAE),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                voucher.number,
                style: const TextStyle(
                  fontFamily: VfTheme.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
                  color: VfDoc.ink,
                ),
              ),
              Text(
                'Original · page 1 of 1',
                style: VfDoc.faintStyle.copyWith(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.voucher, required this.locale});

  final Voucher voucher;
  final String locale;

  @override
  Widget build(BuildContext context) {
    Widget cell(String term, String value, [String? sub]) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(term.toUpperCase(), style: VfDoc.label),
          const SizedBox(height: 2),
          Text(value, style: VfDoc.strong.copyWith(fontSize: 11.5)),
          if (sub != null && sub.isNotEmpty)
            Text(sub, style: VfDoc.faintStyle.copyWith(fontSize: 8.5)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.only(bottom: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: VfDoc.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell('doc.date'.tr, Fmt.date(voucher.voucherDate)),
          cell(
            'doc.department'.tr,
            voucher.departmentName ?? '—',
            voucher.costCentre,
          ),
          cell('doc.requestedBy'.tr, voucher.requesterName ?? '—'),
          cell('doc.category'.tr, voucher.category ?? '—'),
        ],
      ),
    );
  }
}

class _Particulars extends StatelessWidget {
  const _Particulars({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final figure = Fmt.plain(voucher.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('doc.payee'.tr.toUpperCase(), style: VfDoc.label),
        const SizedBox(height: 2),
        Text(
          voucher.payee,
          style: const TextStyle(
            fontFamily: VfTheme.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
            color: VfDoc.ink,
          ),
        ),
        const SizedBox(height: 10),

        /* The ruled particulars, the way a voucher book is printed: what is
           being paid for, then the total. The blank rule carries the form down
           the page rather than leaving a hole in the middle of it. */
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: VfDoc.rule)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: const BoxDecoration(color: VfDoc.wash),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'doc.particulars'.tr.toUpperCase(),
                          style: VfDoc.label.copyWith(color: VfDoc.muted),
                        ),
                      ),
                      Text(
                        '${'doc.amount'.tr.toUpperCase()} · ${voucher.currency}',
                        style: VfDoc.label.copyWith(color: VfDoc.muted),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: VfDoc.rule),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              voucher.purpose,
                              style: VfDoc.strong.copyWith(fontSize: 11.5),
                            ),
                            if (voucher.description != null) ...[
                              const SizedBox(height: 3),
                              Text(voucher.description!, style: VfDoc.bodyText),
                            ],
                            if (voucher.accountRef != null &&
                                voucher.accountRef!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${'doc.reference'.tr}: ${voucher.accountRef}',
                                style: VfDoc.mutedStyle.copyWith(fontSize: 9),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(figure, style: VfDoc.strong.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                Container(height: 1, color: VfDoc.rule),
                const Expanded(child: SizedBox.shrink()),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 9,
                  ),
                  decoration: const BoxDecoration(
                    color: VfDoc.wash,
                    border: Border(top: BorderSide(color: VfDoc.ink, width: 2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'doc.totalPayable'.tr.toUpperCase(),
                          style: VfDoc.label.copyWith(
                            fontSize: 8.5,
                            color: VfDoc.ink,
                          ),
                        ),
                      ),
                      Text(
                        figure,
                        style: const TextStyle(
                          fontFamily: VfTheme.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3,
                          color: VfDoc.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: const BoxDecoration(
            color: VfDoc.wash,
            border: Border(
              left: BorderSide(color: VfDoc.ink, width: 3),
              top: BorderSide(color: VfDoc.rule),
              right: BorderSide(color: VfDoc.rule),
              bottom: BorderSide(color: VfDoc.rule),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'doc.amountWords'.tr.toUpperCase(),
                style: VfDoc.label.copyWith(fontSize: 7),
              ),
              const SizedBox(height: 1),
              Text(
                voucher.amountInWords ?? voucher.amountText,
                style: const TextStyle(
                  fontFamily: VfTheme.fontFamily,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: VfDoc.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.voucher,
    required this.company,
    required this.isCash,
  });

  final Voucher voucher;
  final Company? company;
  final bool isCash;

  @override
  Widget build(BuildContext context) {
    Widget row(String term, String value, {bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: VfDoc.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              term.toUpperCase(),
              style: VfDoc.label.copyWith(fontSize: 7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: strong
                  ? VfDoc.strong.copyWith(fontSize: 11.5)
                  : VfDoc.bodyText.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: VfDoc.body,
                    ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: VfDoc.rule),
            borderRadius: BorderRadius.circular(5),
            color: VfDoc.paper,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: VfDoc.wash,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  'doc.paymentParticulars'.tr.toUpperCase(),
                  style: VfDoc.label.copyWith(color: VfDoc.muted),
                ),
              ),
              Container(height: 1, color: VfDoc.rule),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row('doc.amount'.tr, voucher.amountText, strong: true),
                    row('doc.currency'.tr, voucher.currency),
                    row(
                      'doc.method'.tr,
                      voucher.paymentMethod ?? (isCash ? 'Cash' : 'Bank'),
                    ),
                    row('doc.voucherType'.tr, voucher.voucherTypeLabel ?? '—'),
                    row(
                      'doc.reference'.tr,
                      (voucher.accountRef?.isNotEmpty ?? false)
                          ? voucher.accountRef!
                          : '—',
                    ),
                    if (isCash) ...[
                      row(
                        'doc.payFrom'.tr,
                        voucher.cashFloat ?? 'Petty cash float',
                      ),
                      row('doc.receivedBy'.tr, voucher.receivedBy ?? '—'),
                    ] else ...[
                      row('doc.bank'.tr, voucher.payeeBank ?? '—'),
                      row(
                        'doc.accountName'.tr,
                        voucher.payeeAccountName ?? voucher.payee,
                      ),
                      row(
                        'doc.accountNo'.tr,
                        voucher.payeeAccountNumber ?? '—',
                      ),
                      row('doc.branch'.tr, voucher.payeeBankBranch ?? '—'),
                    ],
                    if (voucher.paymentReference != null)
                      row('doc.paymentRef'.tr, voucher.paymentReference!),
                  ],
                ),
              ),

              /* A bank voucher is drawn on the company's own account; saying so
                 on the document is what makes it a bank voucher. */
              if (!isCash &&
                  (company?.bankAccountNumber?.isNotEmpty ?? false)) ...[
                Container(height: 1, color: VfDoc.rule),
                Container(
                  width: double.infinity,
                  color: VfDoc.wash,
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'doc.drawnOn'.tr.toUpperCase(),
                        style: VfDoc.label.copyWith(fontSize: 7),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        company!.bankName ?? '',
                        style: VfDoc.strong.copyWith(fontSize: 9.5),
                      ),
                      Text(
                        [
                              company!.bankAccountName,
                              [company!.bankAccountNumber, company!.bankBranch]
                                  .where((v) => v != null && v.isNotEmpty)
                                  .join(' · '),
                            ]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join('\n'),
                        style: VfDoc.bodyText.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              border: Border.all(color: VfDoc.rule),
              borderRadius: BorderRadius.circular(5),
              color: VfDoc.paper,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'doc.supportingDocs'.tr.toUpperCase(),
                  style: VfDoc.label.copyWith(fontSize: 7),
                ),
                const SizedBox(height: 4),
                if (voucher.attachments.isEmpty)
                  Text(
                    'doc.noneAttached'.tr,
                    style: VfDoc.bodyText.copyWith(
                      color: const Color(0xFFC2C9D6),
                    ),
                  )
                else
                  ...voucher.attachments.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Text(
                        '${e.key + 1}.  ${e.value.name}',
                        style: VfDoc.bodyText.copyWith(fontSize: 9.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Remarks extends StatelessWidget {
  const _Remarks({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    // The most recent decision note is what a remarks box would carry.
    String? note = voucher.notesToApprover;
    if (note == null || note.isEmpty) {
      for (final r in voucher.timeline) {
        if (r.comment != null && r.comment!.isNotEmpty && r.when != null) {
          note = r.comment;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('doc.remarks'.tr.toUpperCase(), style: VfDoc.label),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            border: Border.all(color: VfDoc.rule),
            borderRadius: BorderRadius.circular(4),
            color: VfDoc.paper,
          ),
          child: Text(
            note?.isNotEmpty == true ? note! : '—',
            style: VfDoc.bodyText.copyWith(
              color: note?.isNotEmpty == true
                  ? VfDoc.body
                  : const Color(0xFFC2C9D6),
            ),
          ),
        ),
      ],
    );
  }
}

Color? _hexColour(String? value) {
  if (value == null || !value.startsWith('#') || value.length != 7) return null;
  final v = int.tryParse(value.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
