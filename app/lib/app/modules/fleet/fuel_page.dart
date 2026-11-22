import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/fleet_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';
import 'paged_list.dart';

/// Every fuel issue, newest first, filtered by state (the web's
/// /erp/fleet/fuel). Someone with fleet.approve taps a waiting entry to
/// approve or reject it, the decision drivers' entries wait for.
class FuelPage extends StatelessWidget {
  const FuelPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'fleet',
    permission: 'fleet.view',
    builder: (context) {
      final erp = ErpService.to;
      return PagedListBody<FleetFuel>(
        title: 'flt.nav.fuel'.tr,
        subtitle: 'flt.fuelSub'.tr,
        trailing: erp.can('fleet.fuel')
            ? VouchFlowButton(
                label: 'flt.recordFuel'.tr,
                icon: PhosphorIconsBold.plus,
                compact: true,
                onPressed: () => Get.toNamed(Routes.erpFleetFuelNew, arguments: {'mine': false}),
              )
            : null,
        searchPlaceholder: 'flt.searchFuel'.tr,
        statuses: const [null, ...FleetEntryStatus.all],
        statusLabel: (s) => s == null ? 'flt.all'.tr : entryStatusLabel(s),
        load: (q, status, page) => FleetRepository.to.fuel(q: q, status: status, page: page),
        emptyText: 'flt.noFuelLog'.tr,
        emptyIcon: PhosphorIconsRegular.gasPump,
        row: (context, f, i, reload) => FuelRow(
          fuel: f,
          currency: erp.currency,
          divider: i > 0,
          onTap: f.isPending && erp.can('fleet.approve')
              ? () async {
                  if (await decideFuel(context, f)) reload();
                }
              : () => Get.toNamed(Routes.erpFleetTrip, arguments: {'id': f.tripId, 'mine': false}),
        ),
      );
    },
  );
}

/// Asks whether to approve or reject a waiting fuel entry; true once decided.
Future<bool> decideFuel(BuildContext context, FleetFuel f) async {
  final currency = ErpService.to.currency;
  final repo = FleetRepository.to;
  final summary = [
    VfSummaryRow('flt.litres'.tr, litresLabel(f.litres)),
    VfSummaryRow('flt.amount'.tr, '$currency ${ErpFmt.amount(f.amount)}'),
    if (f.tripNumber != null) VfSummaryRow('flt.trip'.tr, [f.tripNumber!, ?f.vehicle].join(' · ')),
    if (f.station != null) VfSummaryRow('flt.station'.tr, f.station!),
    if (f.recorder != null) VfSummaryRow('flt.recordedBy'.tr, '${f.recorder} · ${dashDate(f.issueDate)}'),
  ];
  final choice = await showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: PhosphorIconsRegular.gasPump,
      tone: VfTone.warn,
      title: 'flt.decideFuelQ'.tr,
      subtitle: 'flt.decideFuelSub'.tr,
      summary: summary,
      child: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: VouchFlowActions(
            children: [
              VouchFlowButton(
                label: 'flt.reject'.tr,
                variant: VfButtonVariant.danger,
                onPressed: () => Navigator.of(ctx).pop('reject'),
              ),
              VouchFlowButton(
                label: 'flt.approve'.tr,
                icon: PhosphorIconsRegular.check,
                onPressed: () => Navigator.of(ctx).pop('approve'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final message = await showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: choice == 'approve' ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.xCircle,
      tone: choice == 'approve' ? VfTone.ok : VfTone.bad,
      title: choice == 'approve' ? 'flt.approveQ'.tr : 'flt.rejectQ'.tr,
      summary: summary,
      child: ConfirmActions(
        confirmLabel: choice == 'approve' ? 'flt.approve'.tr : 'flt.reject'.tr,
        danger: choice == 'reject',
        fieldLabel: choice == 'reject' ? 'flt.reason'.tr : null,
        fieldRequired: choice == 'reject',
        errorField: 'reason',
        run: (reason) => repo.decideFuel(f.id, approve: choice == 'approve', reason: reason),
      ),
    ),
  );
  if (message == null) return false;
  showToast(message.isEmpty ? entryStatusLabel(choice == 'approve' ? 'approved' : 'rejected') : message);
  return true;
}
