import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';

/*
 * Pieces the Sales and Dispatch screens share: how a status looks, money,
 * the rows of every register, a paged register, the head of a document,
 * its timeline and totals, and the confirmation sheet every action runs
 * behind.
 */

String salesStatusLabel(String status) => 'sal.st.$status'.tr;

/// "TZS 1,416,000" in the company's currency.
String salesMoney(num value) => '${ErpService.to.currency} ${ErpFmt.amount(value)}';

String salesMethodLabel(String method) => 'sal.method.$method'.tr;

/// A sales or dispatch status as the web's SalesBadge colours it.
class SalesStatusBadge extends StatelessWidget {
  const SalesStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) =>
      VouchFlowStatusBadge(label: salesStatusLabel(status), tag: SalesStatus.tag(status), large: large);
}

/// An amount, right-aligned figures, in the body's strong weight.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.style, this.color});

  final num value;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Text(
      salesMoney(value),
      maxLines: 1,
      textAlign: TextAlign.right,
      style: (style ?? VfType.bodyStrong.copyWith(fontSize: 14.5)).copyWith(
        color: color ?? style?.color ?? t.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A row's trailing pair: the amount over the status.
class _AmountStatus extends StatelessWidget {
  const _AmountStatus({required this.amount, required this.status});

  final num amount;
  final String status;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      MoneyText(amount, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      SalesStatusBadge(status),
    ],
  );
}

class SalesOrderRow extends StatelessWidget {
  const SalesOrderRow({super.key, required this.order, required this.onTap, this.divider = true});

  final SalesOrder order;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => VouchFlowListRow(
    divider: divider,
    icon: PhosphorIconsRegular.shoppingCart,
    iconColor: context.vf.successStrong,
    title: order.customer?.name ?? order.number,
    subtitle: [order.number, if (order.orderDate != null) dashDate(order.orderDate)].join(' · '),
    trailing: _AmountStatus(amount: order.totals.total, status: order.status),
    onTap: onTap,
  );
}

class SalesInvoiceRow extends StatelessWidget {
  const SalesInvoiceRow({super.key, required this.invoice, required this.onTap, this.divider = true});

  final SalesInvoice invoice;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final i = invoice;
    final due = i.isOpen && i.dueDate != null
        ? (i.isOverdue ? 'sal.overdueSince' : 'sal.dueOn').trParams({'date': dashDate(i.dueDate)})
        : null;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.receipt,
      iconColor: i.isOverdue ? t.dangerStrong : t.infoStrong,
      title: i.customer?.name ?? i.number,
      subtitle: [i.number, ?due].join(' · '),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(i.totals.total, style: VfType.small.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          if (i.isOpen)
            VouchFlowStatusBadge(
              label: 'sal.owes'.trParams({'amount': ErpFmt.amount(i.balance)}),
              tag: i.isOverdue ? 'tag-accent-2' : 'tag-warn',
            )
          else if (i.status == SalesStatus.posted)
            VouchFlowStatusBadge(label: 'sal.st.paid'.tr, tag: 'tag-accent')
          else
            SalesStatusBadge(i.status),
        ],
      ),
      onTap: onTap,
    );
  }
}

class SalesQuotationRow extends StatelessWidget {
  const SalesQuotationRow({super.key, required this.quotation, required this.onTap, this.divider = true});

  final SalesQuotation quotation;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => VouchFlowListRow(
    divider: divider,
    icon: PhosphorIconsRegular.notePencil,
    iconColor: context.vf.primary,
    title: quotation.customer?.name ?? quotation.number,
    subtitle: [
      quotation.number,
      if (quotation.validUntil != null) 'sal.validUntil'.trParams({'date': dashDate(quotation.validUntil)}),
    ].join(' · '),
    trailing: _AmountStatus(amount: quotation.totals.total, status: quotation.status),
    onTap: onTap,
  );
}

class SalesReceiptRow extends StatelessWidget {
  const SalesReceiptRow({super.key, required this.receipt, required this.onTap, this.divider = true});

  final SalesReceipt receipt;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => VouchFlowListRow(
    divider: divider,
    icon: PhosphorIconsRegular.handCoins,
    iconColor: context.vf.successStrong,
    title: receipt.customer?.name ?? receipt.number,
    subtitle: [
      receipt.number,
      salesMethodLabel(receipt.method),
      if (receipt.receiptDate != null) dashDate(receipt.receiptDate),
    ].join(' · '),
    trailing: _AmountStatus(amount: receipt.amount, status: receipt.status),
    onTap: onTap,
  );
}

class SalesCustomerRow extends StatelessWidget {
  const SalesCustomerRow({super.key, required this.customer, required this.onTap, this.divider = true});

  final SalesCustomer customer;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.storefront,
      iconColor: context.vf.successStrong,
      title: c.name,
      subtitle: [c.code, ?c.city].join(' · '),
      trailing: VouchFlowStatusBadge(
        label: c.requiresPrepayment ? 'sal.prepayment'.tr : 'sal.creditDays'.trParams({'n': '${c.paymentTermsDays}'}),
        tag: c.requiresPrepayment ? 'tag-info' : 'tag-neutral',
      ),
      onTap: onTap,
    );
  }
}

/// A loading order as one row: the truck, where it goes, and its stage.
class LoadingOrderRow extends StatelessWidget {
  const LoadingOrderRow({super.key, required this.loading, required this.onTap, this.divider = true});

  final LoadingOrder loading;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final l = loading;
    return VouchFlowListRow(
      divider: divider,
      icon: l.onTheRoad ? PhosphorIconsRegular.truck : PhosphorIconsRegular.package,
      iconColor: l.discrepancyOpen ? t.dangerStrong : (l.onTheRoad ? t.infoStrong : t.primary),
      title: l.customer?.name ?? l.number,
      subtitle: [
        l.number,
        ?l.vehicleNumber,
        ?(l.warehouse?.name),
        if (l.plannedDate != null) dashDate(l.plannedDate),
      ].join(' · '),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SalesStatusBadge(l.status),
          if (l.discrepancyOpen) ...[
            const SizedBox(height: 5),
            VouchFlowStatusBadge(label: 'dsp.shortOpen'.tr, tag: 'tag-accent-2'),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/* ────────────────────────────────────────────────────── the register ── */

/// One filter pill of a register: its value (null for "All") and label.
typedef SalesFilter = (String?, String);

/// A paged, searchable, filterable list of one kind of record (the web's
/// usePaged registers): title, an optional button, the pills, the rows.
class SalesRegister<T> extends StatefulWidget {
  const SalesRegister({
    super.key,
    required this.title,
    required this.load,
    required this.row,
    required this.emptyIcon,
    required this.emptyTitle,
    this.subtitle,
    this.searchPlaceholder,
    this.filters = const [],
    this.initialFilter,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? searchPlaceholder;
  final List<SalesFilter> filters;
  final String? initialFilter;
  final Widget? trailing;
  final Future<ErpPage<T>> Function(String? filter, String? q, int page) load;

  /// One row; [reload] re-reads the list after a detail page closes.
  final Widget Function(T item, bool divider, VoidCallback reload) row;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  State<SalesRegister<T>> createState() => _SalesRegisterState<T>();
}

class _SalesRegisterState<T> extends State<SalesRegister<T>> {
  late String? _filter = widget.initialFilter;
  String _q = '';
  Timer? _debounce;
  final _rows = <T>[];
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = _rows.isEmpty;
        _error = null;
      }
    });
    try {
      final page = await widget.load(_filter, _q.trim().isEmpty ? null : _q.trim(), more ? _page + 1 : 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(page.data);
        _page = page.currentPage;
        _more = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'state.offline'.tr);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(widget.title, subtitle: widget.subtitle, trailing: widget.trailing),
        if (widget.searchPlaceholder != null) ...[
          VouchFlowSearchField(placeholder: widget.searchPlaceholder!, onChanged: _search),
          const SizedBox(height: 10),
        ],
        if (widget.filters.isNotEmpty) ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (value, label) in widget.filters) ...[
                  VouchFlowFilterChip(
                    label: label,
                    selected: _filter == value,
                    onTap: () {
                      setState(() => _filter = value);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: widget.emptyIcon, title: widget.emptyTitle)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) widget.row(_rows[i], i > 0, _load),
                if (_more)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _loadingMore
                        ? const VfLoader(size: 28)
                        : VouchFlowButton(
                            label: 'erp.loadMore'.tr,
                            variant: VfButtonVariant.ghost,
                            compact: true,
                            onPressed: () => _load(more: true),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/* ────────────────────────────────────────────────────── detail pieces ── */

/// The head of a document page: its icon, kind, number, a line about it,
/// and its status.
class SalesDocHead extends StatelessWidget {
  const SalesDocHead({
    super.key,
    required this.icon,
    required this.tint,
    required this.kind,
    required this.number,
    required this.status,
    this.subtitle,
    this.extra,
  });

  final IconData icon;
  final Color tint;
  final String kind, number, status;
  final String? subtitle;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: t.isDark ? .18 : .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 25, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind, style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w500)),
                Text(
                  number,
                  style: VfType.pageTitle.copyWith(
                    color: t.text,
                    fontSize: 19,
                    letterSpacing: -.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: VfType.small.copyWith(color: t.text2)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [SalesStatusBadge(status, large: true), ?extra],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled fact in a details card; nothing when [value] is empty.
class SalesFact extends StatelessWidget {
  const SalesFact(this.label, this.value, {super.key, this.onTap, this.strong = false});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 124, child: Text(label, style: VfType.small.copyWith(color: t.muted))),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                value!,
                style: VfType.small.copyWith(
                  color: onTap == null ? t.text : t.primaryText,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtotal, discount, VAT and the total, with any [extra] rows below.
class SalesTotalsBlock extends StatelessWidget {
  const SalesTotalsBlock({super.key, required this.totals, this.extra = const []});

  final SalesTotals totals;
  final List<(String, num, bool)> extra;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget row(String label, num value, {bool strong = false, bool divider = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: divider
          ? BoxDecoration(border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? VfType.bodyStrong : VfType.small).copyWith(color: strong ? t.text : t.muted),
            ),
          ),
          MoneyText(
            value,
            style: strong ? VfType.bodyStrong.copyWith(fontSize: 16) : VfType.small.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
    return Column(
      children: [
        row('sal.subtotal'.tr, totals.subtotal),
        if (totals.discount > 0) row('sal.discount'.tr, -totals.discount),
        row('sal.vat'.tr, totals.tax),
        row('sal.total'.tr, totals.total, strong: true, divider: true),
        for (final (label, value, strong) in extra) row(label, value, strong: strong),
      ],
    );
  }
}

/// One step of a document's timeline: done when [at] is set.
typedef SalesStep = (String label, DateTime? at, String? who);

/// The steps a document has been through, done ones ticked (the web's
/// Timeline).
class SalesTimeline extends StatelessWidget {
  const SalesTimeline({super.key, required this.steps});

  final List<SalesStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    // The first step not done yet is "next"; the rest wait quietly.
    final next = steps.indexWhere((s) => s.$2 == null);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 26,
                  child: Column(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: steps[i].$2 != null
                              ? t.successStrong
                              : (i == next ? t.primarySoftStrong : Colors.transparent),
                          border: Border.all(
                            color: steps[i].$2 != null ? t.successStrong : (i == next ? t.primary : t.faint),
                            width: 1.5,
                          ),
                        ),
                        child: steps[i].$2 != null
                            ? const Icon(PhosphorIconsBold.check, size: 11, color: Colors.white)
                            : null,
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: steps[i].$2 != null ? t.successStrong.withValues(alpha: .5) : t.faint.withValues(alpha: .5),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].$1,
                          style: VfType.small.copyWith(
                            color: steps[i].$2 != null || i == next ? t.text : t.muted,
                            fontWeight: i == next ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        if (steps[i].$2 != null)
                          Text(
                            [?steps[i].$3, dashDateTime(steps[i].$2)].where((s) => s.isNotEmpty).join(' · '),
                            style: VfType.meta.copyWith(color: t.muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The glass bar at the foot of a document page, holding its actions.
class SalesActionBar extends StatelessWidget {
  const SalesActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VfGlass(
      borderRadius: BorderRadius.zero,
      fill: t.barFill,
      highlight: false,
      shadow: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 12, VfSize.pagePad, 12),
          // Shrink-wrapped: stacked actions must not take the whole page.
          child: children.length <= 2
              ? Column(mainAxisSize: MainAxisSize.min, children: [VouchFlowActions(children: children)])
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(mainAxisSize: MainAxisSize.min, children: [VouchFlowActions(children: children.sublist(children.length - 2))]),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: children.sublist(0, children.length - 2),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A secondary action shown as a quiet text button (the bar's third and
/// later actions, and "more" links).
class SalesQuietAction extends StatelessWidget {
  const SalesQuietAction({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      VouchFlowButton(label: label, icon: icon, variant: VfButtonVariant.ghost, compact: true, onPressed: onPressed);
}

/* ─────────────────────────────────────────────────── confirm an action ── */

/// The optional reason field of a confirmation sheet.
class SalesReason {
  const SalesReason({required this.label, this.required = true, this.min = 3, this.initial, this.hint});

  final String label;
  final bool required;
  final int min;
  final String? initial;
  final String? hint;
}

/// Opens a confirmation sheet for one action and runs it: [run] gets the
/// reason typed (or ''), returns the API's message, and the sheet closes
/// with it; a refusal shows in place. Returns null when dismissed.
Future<String?> confirmSalesAction(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<String> Function(String reason) run,
  String? subtitle,
  IconData icon = PhosphorIconsRegular.checkCircle,
  VfTone tone = VfTone.info,
  List<VfSummaryRow> summary = const [],
  SalesReason? reason,
  bool danger = false,
  String? backLabel,
  Widget Function(BuildContext context, StateSetter setState)? extra,
  bool Function()? ready,
}) {
  return showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: icon,
      tone: tone,
      title: title,
      subtitle: subtitle,
      summary: summary,
      child: _SalesConfirm(
        confirmLabel: confirmLabel,
        backLabel: backLabel,
        danger: danger,
        reason: reason,
        extra: extra,
        ready: ready,
        run: run,
      ),
    ),
  );
}

class _SalesConfirm extends StatefulWidget {
  const _SalesConfirm({
    required this.confirmLabel,
    required this.run,
    this.backLabel,
    this.danger = false,
    this.reason,
    this.extra,
    this.ready,
  });

  final String confirmLabel;
  final String? backLabel;
  final bool danger;
  final SalesReason? reason;
  final Widget Function(BuildContext context, StateSetter setState)? extra;
  final bool Function()? ready;
  final Future<String> Function(String reason) run;

  @override
  State<_SalesConfirm> createState() => _SalesConfirmState();
}

class _SalesConfirmState extends State<_SalesConfirm> {
  late final _reason = TextEditingController(text: widget.reason?.initial ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.run(_reason.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.field('reason') ?? e.field('override_reason') ?? e.field('note') ?? e.field('name') ??
              e.field('received_by_name') ?? e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'state.offline'.tr;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = widget.reason;
    final typed = _reason.text.trim().length;
    final ready = (r == null || !r.required || typed >= r.min) && (widget.ready?.call() ?? true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.extra != null) widget.extra!(context, setState),
        if (r != null) ...[
          VouchFlowTextField(
            label: r.label,
            required: r.required,
            hint: r.required ? null : 'sal.optional'.tr,
            controller: _reason,
            placeholder: r.hint,
            autofocus: widget.extra == null,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        if (_error != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.dangerStrong),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!, style: VfType.small.copyWith(color: t.dangerStrong))),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: widget.backLabel ?? 'action.back'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            VouchFlowButton(
              label: widget.confirmLabel,
              variant: widget.danger ? VfButtonVariant.dangerSolid : VfButtonVariant.primary,
              loading: _busy,
              onPressed: ready && !_busy ? _go : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A quantity field for an action sheet: the label above, the number in.
class SalesQtyField extends StatelessWidget {
  const SalesQtyField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.error,
  });

  final String label;
  final String? hint, error;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: VouchFlowTextField(
      label: label,
      hint: hint,
      error: error,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
    ),
  );
}

double salesNum(String s) => double.tryParse(s.trim()) ?? 0;

/// A short note in a panel ("Nothing owed").
class SalesNote extends StatelessWidget {
  const SalesNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Text(text, textAlign: TextAlign.center, style: VfType.small.copyWith(color: context.vf.muted)),
  );
}
