import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/hr_repository.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show PanelEmpty;
import 'hr_widgets.dart';

/// An employee's own attendance, month by month: days in, late and absent,
/// hours worked, and each day's times. Times are recorded by HR or the
/// attendance device; the API offers no clock-in of one's own.
class MyAttendancePage extends StatelessWidget {
  const MyAttendancePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'hr', permission: 'hr.self', builder: (_) => const _MyAttendance());
}

class _MyAttendance extends StatefulWidget {
  const _MyAttendance();

  @override
  State<_MyAttendance> createState() => _MyAttendanceState();
}

class _MyAttendanceState extends State<_MyAttendance> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<HrAttendance>? _days;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await HrRepository.to.myAttendance(periodOf(_month));
      if (mounted) setState(() => _days = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _days = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final now = DateTime.now();
    final current = _month.year == now.year && _month.month == now.month;
    final days = _days;
    int count(String s) => days?.where((d) => d.status == s).length ?? 0;
    final hours = days?.fold<double>(0, (s, d) => s + d.hours) ?? 0;

    Widget stat(String label, String value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: vfCardDecoration(t),
        child: Column(
          children: [
            Text(value, style: VfType.figure.copyWith(fontSize: 19, color: color)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.meta.copyWith(color: t.muted)),
          ],
        ),
      ),
    );

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('hr.nav.myAttendance'.tr, subtitle: 'hr.myAttendanceSub'.tr),
        MonthSwitcher(label: monthLabel(_month), onPrev: () => _shift(-1), onNext: current ? null : () => _shift(1)),
        const SizedBox(height: 12),
        Row(
          children: [
            stat('hr.att.present'.tr, '${count('present')}', t.successStrong),
            const SizedBox(width: 8),
            stat('hr.att.late'.tr, '${count('late')}', t.warningStrong),
            const SizedBox(width: 8),
            stat('hr.att.absent'.tr, '${count('absent')}', t.dangerStrong),
            const SizedBox(width: 8),
            stat('hr.hours'.tr, ErpFmt.qty(hours.round()), t.text),
          ],
        ),
        const SizedBox(height: 14),
        if (days == null)
          _error == null ? const VfLoadingView(inline: true) : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: days.isEmpty
                ? PanelEmpty('hr.noAttendanceMonth'.tr)
                : Column(
                    children: [
                      for (var i = days.length - 1; i >= 0; i--) AttendanceDayRow(record: days[i], divider: i < days.length - 1),
                    ],
                  ),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.info, size: 15, color: t.muted),
            const SizedBox(width: 6),
            Flexible(child: Text('hr.clockNote'.tr, textAlign: TextAlign.center, style: VfType.meta.copyWith(color: t.muted))),
          ],
        ),
      ],
    );
  }
}
