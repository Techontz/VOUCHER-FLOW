import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/sales_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'sales_app.dart';
import 'sales_widgets.dart';

/*
 * The Sales registers: orders, invoices, customers, quotations and
 * receipts, each a searchable list filtered by status (the web's
 * /erp/sales index pages), opening the record's own page.
 */

/// Opens the orders tab already filtered (the overview's pipeline and
/// "awaiting approval" cards).
void openSalesOrders([String? status]) {
  SalesOrdersPage.pendingStatus = status;
  erpGo('/erp/sales/orders');
}

Future<void> _open(String route, int id, VoidCallback reload) async {
  await Get.toNamed(route, arguments: id);
  reload();
}

Widget? _newButton(String label, String permission, String route) {
  if (!ErpService.to.can(permission)) return null;
  return VouchFlowButton(
    label: label,
    icon: PhosphorIconsBold.plus,
    compact: true,
    onPressed: () => erpCreate(salesCreateActions.firstWhere((a) => a.route == route && a.permission == permission)),
  );
}

class SalesOrdersPage extends StatelessWidget {
  const SalesOrdersPage({super.key});

  /// A status to open on, set just before the tab is shown.
  static String? pendingStatus;

  @override
  Widget build(BuildContext context) {
    final initial = pendingStatus;
    pendingStatus = null;
    return ErpGate(
      module: 'sales',
      permission: 'sales.view',
      builder: (_) => SalesRegister<SalesOrder>(
        title: 'sal.orders'.tr,
        searchPlaceholder: 'sal.searchOrders'.tr,
        initialFilter: initial,
        trailing: _newButton('sal.new'.tr, 'sales.order', Routes.salesDocumentNew),
        filters: [
          (null, 'sal.all'.tr),
          for (final s in [...SalesStatus.pipeline, SalesStatus.rejected, SalesStatus.cancelled]) (s, salesStatusLabel(s)),
        ],
        load: (filter, q, page) => SalesRepository.to.orders(status: filter, q: q, page: page),
        row: (o, divider, reload) =>
            SalesOrderRow(order: o, divider: divider, onTap: () => _open(Routes.salesOrder, o.id, reload)),
        emptyIcon: PhosphorIconsRegular.shoppingCart,
        emptyTitle: 'sal.noOrders'.tr,
      ),
    );
  }
}

class SalesInvoicesPage extends StatelessWidget {
  const SalesInvoicesPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'sales',
    permission: 'sales.view',
    builder: (_) => SalesRegister<SalesInvoice>(
      title: 'sal.invoices'.tr,
      searchPlaceholder: 'sal.searchInvoices'.tr,
      filters: [
        (null, 'sal.all'.tr),
        ('open', 'sal.filter.open'.tr),
        ('overdue', 'sal.filter.overdue'.tr),
        (SalesStatus.draft, salesStatusLabel(SalesStatus.draft)),
        (SalesStatus.posted, salesStatusLabel(SalesStatus.posted)),
        (SalesStatus.cancelled, salesStatusLabel(SalesStatus.cancelled)),
      ],
      load: (filter, q, page) => SalesRepository.to.invoices(
        status: filter == 'open' || filter == 'overdue' ? null : filter,
        openOnly: filter == 'open',
        overdue: filter == 'overdue',
        q: q,
        page: page,
      ),
      row: (i, divider, reload) =>
          SalesInvoiceRow(invoice: i, divider: divider, onTap: () => _open(Routes.salesInvoice, i.id, reload)),
      emptyIcon: PhosphorIconsRegular.receipt,
      emptyTitle: 'sal.noInvoices'.tr,
    ),
  );
}

class SalesCustomersPage extends StatelessWidget {
  const SalesCustomersPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'sales',
    permission: 'customers.view',
    builder: (_) => SalesRegister<SalesCustomer>(
      title: 'sal.customers'.tr,
      searchPlaceholder: 'sal.searchCustomers'.tr,
      load: (_, q, page) => SalesRepository.to.customers(q: q, page: page),
      row: (c, divider, reload) =>
          SalesCustomerRow(customer: c, divider: divider, onTap: () => _open(Routes.salesCustomer, c.id, reload)),
      emptyIcon: PhosphorIconsRegular.usersThree,
      emptyTitle: 'sal.noCustomers'.tr,
    ),
  );
}

class SalesQuotationsPage extends StatelessWidget {
  const SalesQuotationsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'sales',
    permission: 'sales.view',
    builder: (_) => SalesRegister<SalesQuotation>(
      title: 'sal.quotations'.tr,
      searchPlaceholder: 'sal.searchQuotations'.tr,
      trailing: _newButton('sal.new'.tr, 'sales.quote', Routes.salesDocumentNew),
      filters: [
        (null, 'sal.all'.tr),
        for (final s in [SalesStatus.draft, SalesStatus.sent, SalesStatus.converted, SalesStatus.rejected, SalesStatus.cancelled])
          (s, salesStatusLabel(s)),
      ],
      load: (filter, q, page) => SalesRepository.to.quotations(status: filter, q: q, page: page),
      row: (x, divider, reload) =>
          SalesQuotationRow(quotation: x, divider: divider, onTap: () => _open(Routes.salesQuotation, x.id, reload)),
      emptyIcon: PhosphorIconsRegular.notePencil,
      emptyTitle: 'sal.noQuotations'.tr,
    ),
  );
}

class SalesReceiptsPage extends StatelessWidget {
  const SalesReceiptsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'sales',
    permission: 'sales.view',
    builder: (_) => SalesRegister<SalesReceipt>(
      title: 'sal.receipts'.tr,
      subtitle: 'sal.receiptsSub'.tr,
      searchPlaceholder: 'sal.searchReceipts'.tr,
      trailing: _newButton('sal.record'.tr, 'sales.receipt', Routes.salesReceiptNew),
      filters: [
        (null, 'sal.all'.tr),
        for (final s in [SalesStatus.recorded, SalesStatus.verified, SalesStatus.rejected]) (s, salesStatusLabel(s)),
      ],
      load: (filter, q, page) => SalesRepository.to.receipts(status: filter, q: q, page: page),
      row: (r, divider, reload) =>
          SalesReceiptRow(receipt: r, divider: divider, onTap: () => _open(Routes.salesReceipt, r.id, reload)),
      emptyIcon: PhosphorIconsRegular.handCoins,
      emptyTitle: 'sal.noReceipts'.tr,
    ),
  );
}
