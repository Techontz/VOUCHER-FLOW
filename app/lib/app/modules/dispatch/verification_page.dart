import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/sales_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../sales/receipt_page.dart' show rejectReceipt, verifyReceipt;
import '../sales/sales_widgets.dart';

/// Finance verification (the web's /erp/dispatch): payments recorded and
/// waiting for a second person to confirm the money arrived, prepayment
/// orders waiting for that money, and orders released for loading.
class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ErpGate(module: 'dispatch', permission: 'dispatch.verify', builder: (_) => const _Verification());
}

class _Verification extends StatefulWidget {
  const _Verification();

  @override
  State<_Verification> createState() => _VerificationState();
}

class _VerificationState extends State<_Verification> {
  final _erp = ErpService.to;
  VerificationQueue? _queue;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await SalesRepository.to.verification();
      if (mounted) setState(() { _queue = q; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  bool _mine(SalesReceipt r) {
    if (!Get.isRegistered<SessionService>()) return false;
    final me = Get.find<SessionService>().user.value?.id;
    return me != null && r.createdBy == me;
  }

  Future<void> _openOrder(SalesOrder o) async {
    if (!_erp.has('sales') || !_erp.can('sales.view')) return;
    await Get.toNamed(Routes.salesOrder, arguments: o.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _queue;
    final t = context.vf;
    if (q == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(
              onRefresh: _load,
              children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)],
            );
    }
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('dsp.verification'.tr, subtitle: 'dsp.verificationSub'.tr),
        VouchFlowPanel(
          title: 'dsp.paymentsToVerify'.tr,
          trailing: Text('${q.receipts.length}', style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w600)),
          padded: false,
          child: q.receipts.isEmpty
              ? SalesNote('dsp.nothingToVerify'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < q.receipts.length; i++)
                      Container(
                        decoration: i == 0
                            ? null
                            : BoxDecoration(border: Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SalesReceiptRow(
                              receipt: q.receipts[i],
                              divider: false,
                              onTap: () async {
                                await Get.toNamed(Routes.salesReceipt, arguments: q.receipts[i].id);
                                _load();
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: _mine(q.receipts[i])
                                  ? Text('sal.verifyOther'.tr, style: VfType.meta.copyWith(color: t.muted))
                                  : VouchFlowActions(
                                      children: [
                                        VouchFlowButton(
                                          label: 'sal.reject'.tr,
                                          variant: VfButtonVariant.secondary,
                                          compact: true,
                                          onPressed: () async {
                                            if (await rejectReceipt(context, q.receipts[i]) != null) _load();
                                          },
                                        ),
                                        VouchFlowButton(
                                          label: 'sal.verify'.tr,
                                          icon: PhosphorIconsRegular.shieldCheck,
                                          compact: true,
                                          onPressed: () async {
                                            if (await verifyReceipt(context, q.receipts[i]) != null) _load();
                                          },
                                        ),
                                      ],
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
          title: 'dsp.awaitingPayment'.tr,
          subtitle: 'dsp.awaitingPaymentSub'.tr,
          padded: false,
          child: q.awaitingPayment.isEmpty
              ? SalesNote('dsp.noneAwaiting'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < q.awaitingPayment.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.hourglassMedium,
                        iconColor: t.warningStrong,
                        title: q.awaitingPayment[i].customer?.name ?? q.awaitingPayment[i].number,
                        subtitle: [
                          q.awaitingPayment[i].number,
                          'dsp.paidOf'.trParams({
                            'paid': salesMoney(q.awaitingPayment[i].verifiedPayments),
                            'total': salesMoney(q.awaitingPayment[i].totals.total),
                          }),
                        ].join(' · '),
                        onTap: () => _openOrder(q.awaitingPayment[i]),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'dsp.readyToLoad'.tr,
          padded: false,
          child: q.ready.isEmpty
              ? SalesNote('dsp.noneReady'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < q.ready.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.checkCircle,
                        iconColor: t.successStrong,
                        title: q.ready[i].customer?.name ?? q.ready[i].number,
                        subtitle: [
                          q.ready[i].number,
                          if (q.ready[i].approvedAt != null) dashDate(q.ready[i].approvedAt),
                        ].join(' · '),
                        trailing: _erp.can('dispatch.load')
                            ? VouchFlowButton(
                                label: 'dsp.load'.tr,
                                compact: true,
                                variant: VfButtonVariant.secondary,
                                onPressed: () async {
                                  await Get.toNamed(Routes.dispatchLoadingNew, arguments: {'orderId': q.ready[i].id});
                                  _load();
                                },
                              )
                            : null,
                        onTap: () => _openOrder(q.ready[i]),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
