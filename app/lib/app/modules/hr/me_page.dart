import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import 'employee_page.dart' show personFile;
import 'hr_widgets.dart';

/// "My HR": an employee's own home. Leave left, the last payslip and this
/// month's attendance up top with one big "Apply for leave", then their own
/// file, where they may correct their contact details and next of kin (the
/// web's /erp/hr/me).
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) =>
      ErpGate(module: 'hr', permission: 'hr.self', builder: (_) => const _Me());
}

class _Me extends StatefulWidget {
  const _Me();

  @override
  State<_Me> createState() => _MeState();
}

class _MeState extends State<_Me> {
  final _repo = HrRepository.to;
  HrPersonFile? _file;
  HrPayslipSummary? _lastSlip;
  int? _daysIn;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await _repo.me();
      if (!mounted) return;
      setState(() {
        _file = f;
        _error = null;
      });
      // The extras are worth a figure each, not a failed page.
      final slips = await _repo.myPayslips().catchError(
        (_) => <HrPayslipSummary>[],
      );
      final days = await _repo
          .myAttendance(periodOf(DateTime.now()))
          .catchError((_) => <HrAttendance>[]);
      if (!mounted) return;
      setState(() {
        _lastSlip = slips.firstOrNull;
        _daysIn = days
            .where(
              (d) =>
                  d.status == HrAttendanceStatus.present ||
                  d.status == HrAttendanceStatus.late,
            )
            .length;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  Future<void> _apply() async {
    final done = await Get.toNamed(Routes.erpHrLeaveNew);
    if (done == true) _load();
  }

  Future<void> _edit(HrEmployee e) async {
    final saved = await showVfSheet<bool>(
      context,
      builder: (_) => _EditDetails(employee: e),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) {
      return _error == null
          ? const VfLoadingView()
          : ErpPageBody(
              onRefresh: _load,
              children: [
                VouchFlowErrorState(
                  message: _error!,
                  onRetry: _load,
                  retryLabel: 'action.retry'.tr,
                ),
              ],
            );
    }
    final c = ErpService.to.currency;
    final annual = f.annual;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          'hr.hello'.trParams({'name': f.employee.name.split(' ').first}),
          subtitle: 'hr.meSub'.tr,
        ),
        VouchFlowFigureGrid(
          children: [
            VouchFlowFigureCard(
              label: annual?.type ?? 'hr.leaveLeft'.tr,
              value: annual?.available == null
                  ? '-'
                  : daysLabel(
                      double.parse(annual!.available!.toStringAsFixed(1)),
                    ),
              hint: annual == null
                  ? null
                  : 'hr.takenOf'.trParams({
                      'taken': ErpFmt.qty(annual.taken),
                      'of': annual.accrued.toStringAsFixed(1),
                    }),
              icon: PhosphorIconsRegular.airplaneTilt,
              tone: VfTone.info,
              onTap: () => erpGo('/erp/hr/me/leave'),
            ),
            VouchFlowFigureCard(
              label: 'hr.lastPay'.tr,
              value: _lastSlip == null
                  ? '-'
                  : ErpFmt.compactMoney(_lastSlip!.net, c),
              hint: _lastSlip == null
                  ? 'hr.noPayslips'.tr
                  : monthLabel(_lastSlip!.period),
              icon: PhosphorIconsRegular.money,
              tone: VfTone.ok,
              onTap: () => erpGo('/erp/hr/me/payslips'),
            ),
            VouchFlowFigureCard(
              label: 'hr.daysInMonth'.tr,
              value: _daysIn == null ? '-' : '$_daysIn',
              hint: monthLabel(DateTime.now()),
              icon: PhosphorIconsRegular.fingerprint,
              tone: VfTone.neutral,
              onTap: () => erpGo('/erp/hr/me/attendance'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        VouchFlowButton(
          label: 'hr.applyLeave'.tr,
          icon: PhosphorIconsRegular.calendarPlus,
          expand: true,
          height: 56,
          onPressed: _apply,
        ),
        const SizedBox(height: 14),
        ...personFile(
          context,
          f,
          mine: true,
          onEdit: () => _edit(f.employee),
        ).skip(1),
      ],
    );
  }
}

/// The details a person may correct themselves (SelfServiceController@update).
class _EditDetails extends StatefulWidget {
  const _EditDetails({required this.employee});

  final HrEmployee employee;

  @override
  State<_EditDetails> createState() => _EditDetailsState();
}

class _EditDetailsState extends State<_EditDetails> {
  late final _fields = {
    'phone': TextEditingController(text: widget.employee.phone ?? ''),
    'address': TextEditingController(text: widget.employee.address ?? ''),
    'next_of_kin_name': TextEditingController(
      text: widget.employee.nextOfKinName ?? '',
    ),
    'next_of_kin_relation': TextEditingController(
      text: widget.employee.nextOfKinRelation ?? '',
    ),
    'next_of_kin_phone': TextEditingController(
      text: widget.employee.nextOfKinPhone ?? '',
    ),
  };
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await HrRepository.to.updateMe({
        for (final e in _fields.entries)
          e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      });
      showToast(message.isEmpty ? 'hr.saved'.tr : message);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ApiException(0, 'state.offline'.tr);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget field(String key, String label, {TextInputType? type}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VouchFlowTextField(
        label: label,
        controller: _fields[key],
        keyboardType: type,
        error: _error?.field(key),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'hr.editDetails'.tr,
              style: VfType.sectionTitle.copyWith(color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              'hr.editDetailsSub'.tr,
              style: VfType.small.copyWith(color: t.muted),
            ),
            const SizedBox(height: 16),
            field('phone', 'hr.phone'.tr, type: TextInputType.phone),
            field('address', 'hr.address'.tr),
            field('next_of_kin_name', 'hr.kinName'.tr),
            field('next_of_kin_relation', 'hr.kinRelation'.tr),
            field(
              'next_of_kin_phone',
              'hr.kinPhone'.tr,
              type: TextInputType.phone,
            ),
            if (_error != null && _error!.errors.isEmpty) ...[
              Text(
                _error!.message,
                style: VfType.small.copyWith(color: t.dangerStrong),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            VouchFlowButton(
              label: 'hr.saveDetails'.tr,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
