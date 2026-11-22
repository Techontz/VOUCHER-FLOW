import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/hr_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'hr_widgets.dart';

/// The day's register: everyone active, when they came in and left, or
/// their leave (the web's /erp/hr/attendance). A department head without
/// hr.view reads their own team.
class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(module: 'hr', builder: (_) => const _Attendance());
}

class _Attendance extends StatefulWidget {
  const _Attendance();

  @override
  State<_Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<_Attendance> {
  late final bool _team = !ErpService.to.can('hr.view');
  DateTime _day = DateTime.now();
  List<HrDailyRow>? _rows;
  String? _filter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await HrRepository.to.attendance(date: _day, team: _team);
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  void _shift(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _rows = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final now = DateTime.now();
    final isToday = _day.year == now.year && _day.month == now.month && _day.day == now.day;
    final rows = _rows;
    final counts = <String, int>{};
    for (final r in rows ?? const <HrDailyRow>[]) {
      counts[r.state] = (counts[r.state] ?? 0) + 1;
    }
    final shown = rows?.where((r) => _filter == null || r.state == _filter).toList();
    const states = ['present', 'late', 'absent', 'leave', 'none'];

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('hr.nav.attendance'.tr, subtitle: _team ? 'hr.teamOnly'.tr : 'hr.attendanceSub'.tr),
        MonthSwitcher(
          label: isToday ? '${'hr.today'.tr} · ${dashDate(_day)}' : '${weekdayShort(_day)} ${dashDate(_day)}',
          onPrev: () => _shift(-1),
          onNext: isToday ? null : () => _shift(1),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              VouchFlowFilterChip(label: 'hr.all'.tr, count: rows?.length, selected: _filter == null, onTap: () => setState(() => _filter = null)),
              for (final s in states) ...[
                const SizedBox(width: 8),
                VouchFlowFilterChip(label: 'hr.att.$s'.tr, count: counts[s] ?? 0, selected: _filter == s, onTap: () => setState(() => _filter = s)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (rows == null)
          _error == null ? const VfLoadingView(inline: true) : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (shown!.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.fingerprint, title: 'hr.noAttendance'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.user,
                    iconColor: t.primary,
                    title: shown[i].name,
                    subtitle: [
                      ?shown[i].department,
                      if (shown[i].record?.checkIn != null) '${shown[i].record!.checkIn} to ${shown[i].record!.checkOut ?? '--:--'}',
                      ?shown[i].onLeave,
                    ].join(' · '),
                    trailing: AttendanceBadge(shown[i].state),
                    onTap: _team ? null : () => Get.toNamed(Routes.erpHrEmployee, arguments: shown[i].employeeId),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
