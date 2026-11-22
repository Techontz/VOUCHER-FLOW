import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../sales/sales_widgets.dart';
import 'dispatch_app.dart';

/// Every loading order, newest first, by stage: being loaded, loaded and
/// waiting at the gate, on the road, delivered, and short deliveries
/// waiting for a decision (the web's /erp/dispatch/loading).
class LoadingOrdersPage extends StatelessWidget {
  const LoadingOrdersPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'dispatch',
    permission: 'dispatch.view',
    builder: (_) {
      final erp = ErpService.to;
      return SalesRegister<LoadingOrder>(
        title: 'dsp.loadingOrders'.tr,
        subtitle: 'dsp.loadingOrdersSub'.tr,
        searchPlaceholder: 'dsp.search'.tr,
        trailing: erp.can('dispatch.load')
            ? VouchFlowButton(
                label: 'sal.new'.tr,
                icon: PhosphorIconsBold.plus,
                compact: true,
                onPressed: () => erpCreate(dispatchCreateActions.first),
              )
            : null,
        filters: [
          (null, 'sal.all'.tr),
          for (final s in [SalesStatus.open, SalesStatus.loaded, SalesStatus.dispatched, SalesStatus.delivered])
            (s, salesStatusLabel(s)),
          ('discrepancies', 'dsp.shortDeliveries'.tr),
        ],
        load: (filter, q, page) => SalesRepository.to.loadingOrders(
          status: filter == 'discrepancies' ? null : filter,
          stage: filter == 'discrepancies' ? 'discrepancies' : null,
          q: q,
          page: page,
        ),
        row: (l, divider, reload) => LoadingOrderRow(
          loading: l,
          divider: divider,
          onTap: () async {
            await Get.toNamed(Routes.dispatchLoading, arguments: l.id);
            reload();
          },
        ),
        emptyIcon: PhosphorIconsRegular.package,
        emptyTitle: 'dsp.noLoadings'.tr,
      );
    },
  );
}

/// The driver's list: trucks out of the gate waiting for proof of
/// delivery, each a card with where it goes and one button to record the
/// delivery (the web's /erp/dispatch/deliveries).
class DeliveriesPage extends StatelessWidget {
  const DeliveriesPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ErpGate(module: 'dispatch', permission: 'dispatch.view', builder: (_) => const _Deliveries());
}

class _Deliveries extends StatefulWidget {
  const _Deliveries();

  @override
  State<_Deliveries> createState() => _DeliveriesState();
}

class _DeliveriesState extends State<_Deliveries> {
  List<LoadingOrder>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await SalesRepository.to.loadingOrders(stage: 'in_transit');
      if (mounted) setState(() { _rows = page.data; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _open(LoadingOrder l) async {
    await Get.toNamed(Routes.dispatchLoading, arguments: l.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('dsp.onTheRoad'.tr, subtitle: 'dsp.onTheRoadSub'.tr),
        if (rows == null && _error == null)
          const VfLoadingView(inline: true)
        else if (rows == null)
          VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.truck, title: 'dsp.noneOnTheRoad'.tr, body: 'dsp.noneOnTheRoadBody'.tr)
        else
          for (final l in rows) ...[
            VouchFlowPanel(
              padded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VouchFlowListRow(
                    divider: false,
                    icon: PhosphorIconsRegular.truck,
                    iconColor: t.infoStrong,
                    title: l.customer?.name ?? l.number,
                    subtitle: [l.number, ?l.vehicleNumber, ?l.driverName].join(' · '),
                    trailing: SalesStatusBadge(l.status),
                    onTap: () => _open(l),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SalesFact('dsp.destination'.tr, l.destination ?? l.customer?.place),
                        SalesFact('sal.deliveryNote'.tr, l.deliveryNoteNumber),
                        SalesFact('dsp.planned'.tr, l.plannedDate == null ? null : dashDate(l.plannedDate)),
                        const SizedBox(height: 8),
                        if (ErpService.to.can('dispatch.deliver'))
                          VouchFlowButton(
                            label: 'dsp.recordDelivery'.tr,
                            icon: PhosphorIconsRegular.handArrowDown,
                            expand: true,
                            onPressed: () => _open(l),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            erpGap,
          ],
      ],
    );
  }
}
