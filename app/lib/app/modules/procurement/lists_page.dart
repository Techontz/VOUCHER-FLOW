import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/finance_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/procurement_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../finance/fin_widgets.dart';
import 'procurement_app.dart';
import 'procurement_widgets.dart';

/*
 * The Procurement lists: requisitions, orders, supplier invoices, supplier
 * payments, suppliers and the payables ageing. Each searches and filters
 * as the web's list does, and opens the record over the shell.
 */

ProcurementRepository get _repo => ProcurementRepository.to;

Future<void> _push(String route, int id, VoidCallback reload) async {
  await Get.toNamed(route, arguments: id);
  reload();
}

/// Purchase requisitions, the ones waiting for approval a tap away.
class RequisitionsPage extends StatelessWidget {
  const RequisitionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final erp = ErpService.to;
    return ErpGate(
      module: 'procurement',
      permission: 'procurement.view',
      builder: (_) => FinPagedList<PurchaseRequisition>(
        title: 'prc.nav.requisitions'.tr,
        searchPlaceholder: 'prc.searchRequisitions'.tr,
        // An approver lands on what is waiting for them.
        initialFilter: erp.can('procurement.approve') ? 'submitted' : null,
        filters: [
          FinFilter('inv.all'.tr, null),
          for (final s in ['submitted', 'approved', 'draft', 'ordered', 'rejected']) FinFilter('fin.status.$s'.tr, s),
        ],
        trailing: erp.can('procurement.request')
            ? VouchFlowButton(
                label: 'prc.new'.tr,
                icon: PhosphorIconsBold.plus,
                compact: true,
                onPressed: () => erpCreate(procurementCreateActions.first),
              )
            : null,
        load: (page, status, q) => _repo.requisitions(status: status, q: q.isEmpty ? null : q, page: page),
        emptyIcon: PhosphorIconsRegular.clipboardText,
        emptyTitle: 'prc.noRequisitions'.tr,
        row: (context, r, divider, reload) => RequisitionRow(
          requisition: r,
          divider: divider,
          onTap: () => _push(Routes.prcRequisition, r.id, reload),
        ),
      ),
    );
  }
}

/// Purchase orders, by state.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'procurement.view',
    builder: (_) => FinPagedList<PurchaseOrder>(
      title: 'prc.nav.orders'.tr,
      searchPlaceholder: 'prc.searchOrders'.tr,
      initialFilter: ErpService.to.can('procurement.approve') ? 'submitted' : null,
      filters: [
        FinFilter('inv.all'.tr, null),
        FinFilter('fin.status.submitted'.tr, 'submitted'),
        FinFilter('prc.toReceive'.tr, 'to_receive'),
        for (final s in ['draft', 'approved', 'received', 'closed']) FinFilter('fin.status.$s'.tr, s),
      ],
      load: (page, status, q) => _repo.orders(status: status, q: q.isEmpty ? null : q, page: page),
      emptyIcon: PhosphorIconsRegular.shoppingCart,
      emptyTitle: 'prc.noOrders'.tr,
      row: (context, o, divider, reload) =>
          OrderRow(order: o, divider: divider, onTap: () => _push(Routes.prcOrder, o.id, reload)),
    ),
  );
}

/// Supplier invoices: to match, unpaid, posted.
class SupplierInvoicesPage extends StatelessWidget {
  const SupplierInvoicesPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'procurement.view',
    builder: (_) => FinPagedList<SupplierInvoice>(
      title: 'prc.nav.invoices'.tr,
      searchPlaceholder: 'prc.searchInvoices'.tr,
      filters: [
        FinFilter('inv.all'.tr, null),
        FinFilter('prc.unpaid'.tr, 'unpaid'),
        FinFilter('prc.toMatch'.tr, 'to_match'),
        FinFilter('fin.status.awaiting_approval'.tr, 'awaiting_approval'),
        FinFilter('fin.status.posted'.tr, 'posted'),
      ],
      load: (page, status, q) => _repo.invoices(status: status, q: q.isEmpty ? null : q, page: page),
      emptyIcon: PhosphorIconsRegular.receipt,
      emptyTitle: 'prc.noInvoices'.tr,
      row: (context, i, divider, reload) =>
          InvoiceRow(invoice: i, divider: divider, onTap: () => _push(Routes.prcInvoice, i.id, reload)),
    ),
  );
}

/// Supplier payments.
class SupplierPaymentsPage extends StatelessWidget {
  const SupplierPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'procurement.view',
    builder: (_) => FinPagedList<SupplierPayment>(
      title: 'prc.nav.payments'.tr,
      subtitle: 'prc.paymentsSub'.tr,
      searchPlaceholder: 'prc.searchPayments'.tr,
      filters: [
        FinFilter('inv.all'.tr, null),
        for (final s in ['posted', 'draft', 'cancelled']) FinFilter('fin.status.$s'.tr, s),
      ],
      load: (page, status, q) => _repo.payments(status: status, q: q.isEmpty ? null : q, page: page),
      emptyIcon: PhosphorIconsRegular.handCoins,
      emptyTitle: 'prc.noPayments'.tr,
      row: (context, p, divider, reload) =>
          PaymentRow(payment: p, divider: divider, onTap: () => _push(Routes.prcPayment, p.id, reload)),
    ),
  );
}

/// The suppliers, each opening its details and statement.
class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'suppliers.view',
    builder: (_) => FinPagedList<Supplier>(
      title: 'prc.nav.suppliers'.tr,
      searchPlaceholder: 'prc.searchSuppliers'.tr,
      load: (page, _, q) => _repo.suppliers(q: q.isEmpty ? null : q, page: page),
      emptyIcon: PhosphorIconsRegular.truck,
      emptyTitle: 'prc.noSuppliers'.tr,
      row: (context, s, divider, reload) => VouchFlowListRow(
        divider: divider,
        icon: PhosphorIconsRegular.truck,
        iconColor: s.isActive ? context.vf.primary : context.vf.muted,
        title: s.name,
        subtitle: [s.code, ?s.category, ?s.city].join(' · '),
        trailing: s.isActive ? finCaret(context) : VouchFlowStatusBadge(label: 'prc.inactive'.tr),
        onTap: () => _push(Routes.prcSupplier, s.id, reload),
      ),
    ),
  );
}

/// What is owed to whom, by how late (the web's /erp/procurement/ageing):
/// the company total in buckets, then each supplier, tapping through to
/// its statement.
class AgeingPage extends StatelessWidget {
  const AgeingPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'procurement',
    permission: 'procurement.view',
    builder: (_) => FinAsync<PayablesAgeing>(
      load: _repo.ageing,
      builder: (context, a, reload) {
        final t = context.vf;
        final total = a.totals['total'] ?? 0;
        return [
          ErpPageTitle('prc.nav.ageing'.tr, subtitle: 'prc.ageingSub'.tr),
          VouchFlowPanel(
            title: 'prc.totalOwed'.tr,
            trailing: Text(
              finMoney(total),
              style: VfType.bodyStrong.copyWith(color: t.text, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < PayablesAgeing.bucketKeys.length; i++)
                  _BucketRow(
                    label: 'prc.bucket.${PayablesAgeing.bucketKeys[i]}'.tr,
                    amount: a.totals[PayablesAgeing.bucketKeys[i]] ?? 0,
                    share: total <= 0 ? 0 : (a.totals[PayablesAgeing.bucketKeys[i]] ?? 0) / total,
                    color: _bucketColor(t, i),
                    divider: i > 0,
                  ),
              ],
            ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'prc.bySupplier'.tr,
            padded: false,
            child: a.rows.isEmpty
                ? FinPanelEmpty('prc.nothingOwed'.tr)
                : Column(
                    children: [
                      for (var i = 0; i < a.rows.length; i++)
                        VouchFlowListRow(
                          divider: i > 0,
                          icon: PhosphorIconsRegular.truck,
                          title: a.rows[i].supplier.name,
                          subtitle: _oldest(a.rows[i]),
                          trailing: FinTrailing(
                            amount: finCompact(a.rows[i].total),
                            tone: (a.rows[i].buckets['over_90'] ?? 0) > 0 ? t.dangerStrong : null,
                          ),
                          onTap: () => _push(Routes.prcSupplier, a.rows[i].supplier.id, reload),
                        ),
                    ],
                  ),
          ),
        ];
      },
    ),
  );

  static Color _bucketColor(VfTokens t, int i) =>
      [t.successStrong, t.infoStrong, t.warningStrong, t.warningStrong, t.dangerStrong][i];

  /// The latest bucket the supplier has money in ("31-60 days").
  static String _oldest(AgeingRow r) {
    for (final b in PayablesAgeing.bucketKeys.reversed) {
      if ((r.buckets[b] ?? 0) > 0) return 'prc.oldest'.trParams({'bucket': 'prc.bucket.$b'.tr});
    }
    return '';
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({required this.label, required this.amount, required this.share, required this.color, required this.divider});

  final String label;
  final double amount, share;
  final Color color;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: t.border.withValues(alpha: .7), width: .6)) : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: VfType.small.copyWith(color: t.text))),
              Text(
                finMoney(amount),
                style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FinProgress(value: share, color: color, height: 5),
        ],
      ),
    );
  }
}
