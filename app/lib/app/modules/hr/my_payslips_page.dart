import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'hr_widgets.dart';

/// An employee's payslips, newest month first: only runs that are locked or
/// later are released to them (SelfServiceController@payslips).
class MyPayslipsPage extends StatelessWidget {
  const MyPayslipsPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'hr', permission: 'hr.self', builder: (_) => const _MyPayslips());
}

class _MyPayslips extends StatefulWidget {
  const _MyPayslips();

  @override
  State<_MyPayslips> createState() => _MyPayslipsState();
}

class _MyPayslipsState extends State<_MyPayslips> {
  List<HrPayslipSummary>? _slips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await HrRepository.to.myPayslips();
      if (mounted) setState(() { _slips = s; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slips = _slips;
    final c = ErpService.to.currency;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('hr.nav.payslips'.tr, subtitle: 'hr.payslipsSub'.tr),
        if (slips == null)
          _error == null ? const VfLoadingView(inline: true) : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (slips.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.receipt, title: 'hr.noPayslips'.tr, body: 'hr.noPayslipsBody'.tr)
        else ...[
          VouchFlowFigureCard(
            label: 'hr.lastPay'.tr,
            value: money(c, slips.first.net.roundToDouble()),
            hint: monthLabel(slips.first.period),
            icon: PhosphorIconsRegular.money,
            tone: VfTone.ok,
            onTap: () => Get.toNamed(Routes.erpHrPayslip, arguments: {'id': slips.first.id, 'mine': true}),
          ),
          erpGap,
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < slips.length; i++)
                  PayslipRow(
                    slip: slips[i],
                    currency: c,
                    divider: i > 0,
                    onTap: () => Get.toNamed(Routes.erpHrPayslip, arguments: {'id': slips[i].id, 'mine': true}),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
