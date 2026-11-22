import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashIsSw;

/*
 * Pieces the HR screens share: how leave, attendance and payroll states
 * read, month names, and one row each for a leave request, a day of
 * attendance and a payslip.
 */

const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsSw = ['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];
const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _daysSw = ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jms', 'Jpl'];

/// "November 2026" from "2026-11" or a date.
String monthLabel(Object? period) {
  DateTime? d;
  if (period is DateTime) d = period;
  if (period is String && period.length >= 7) d = DateTime.tryParse('${period.substring(0, 7)}-01');
  if (d == null) return '${period ?? '-'}';
  return '${(dashIsSw ? _monthsSw : _monthsEn)[d.month - 1]} ${d.year}';
}

/// "2026-11".
String periodOf(DateTime d) => '${d.year}-${'${d.month}'.padLeft(2, '0')}';

String weekdayShort(DateTime d) => (dashIsSw ? _daysSw : _daysEn)[d.weekday - 1];

/// "12 Nov 2026 to 15 Nov 2026", or one day.
String dateRange(DateTime? a, DateTime? b) =>
    a != null && b != null && a == b ? dashDate(a) : '${dashDate(a)} ${'hr.to'.tr} ${dashDate(b)}';

/// "5 days", "1 day", "2.5 days".
String daysLabel(num n) => n == 1 ? 'hr.oneDay'.tr : 'hr.nDays'.trParams({'n': ErpFmt.qty(n)});

String money(String currency, num v) => '$currency ${ErpFmt.amount(v)}';

class LeaveStatusBadge extends StatelessWidget {
  const LeaveStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: 'hr.leave.$status'.tr,
    large: large,
    tag: switch (status) {
      HrLeaveStatus.approved => 'tag-accent',
      HrLeaveStatus.rejected => 'tag-accent-2',
      HrLeaveStatus.pending => 'tag-warn',
      _ => 'tag-neutral',
    },
  );
}

/// 'present' | 'late' | 'absent' | 'leave' | 'off', or 'none' (not in yet).
class AttendanceBadge extends StatelessWidget {
  const AttendanceBadge(this.state, {super.key, this.label});

  final String state;
  final String? label;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: label ?? 'hr.att.$state'.tr,
    tag: switch (state) {
      HrAttendanceStatus.present => 'tag-accent',
      HrAttendanceStatus.late => 'tag-warn',
      HrAttendanceStatus.absent => 'tag-accent-2',
      HrAttendanceStatus.leave => 'tag-info',
      _ => 'tag-neutral',
    },
  );
}

class PayrollStatusBadge extends StatelessWidget {
  const PayrollStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: 'hr.run.$status'.tr,
    large: large,
    tag: switch (status) {
      'paid' => 'tag-accent',
      'posted' || 'locked' => 'tag-info',
      'authorised' => 'tag-warn',
      _ => 'tag-neutral',
    },
  );
}

/// A leave request: the type (and person, for HR), the dates, its state.
class LeaveRow extends StatelessWidget {
  const LeaveRow({super.key, required this.request, this.onTap, this.divider = true, this.showEmployee = false});

  final HrLeaveRequest request;
  final VoidCallback? onTap;
  final bool divider, showEmployee;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = request;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.airplaneTilt,
      iconColor: r.isPending ? t.warningStrong : t.infoStrong,
      title: showEmployee ? (r.employee ?? r.type) : r.type,
      titleMaxLines: 2,
      subtitle: [
        if (showEmployee) r.type,
        dateRange(r.start, r.end),
        daysLabel(r.days),
      ].join(' · '),
      trailing: LeaveStatusBadge(r.status),
      onTap: onTap,
    );
  }
}

/// A day's attendance: the date, the hours in and out, the state.
class AttendanceDayRow extends StatelessWidget {
  const AttendanceDayRow({super.key, required this.record, this.divider = true});

  final HrAttendance record;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = record;
    final d = r.date;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.fingerprint,
      iconColor: switch (r.status) {
        HrAttendanceStatus.late => t.warningStrong,
        HrAttendanceStatus.absent => t.dangerStrong,
        HrAttendanceStatus.present => t.successStrong,
        _ => t.infoStrong,
      },
      title: d == null ? '-' : '${weekdayShort(d)} ${dashDate(d)}',
      subtitle: [
        if (r.checkIn != null || r.checkOut != null) '${r.checkIn ?? '--:--'} to ${r.checkOut ?? '--:--'}',
        if (r.hours >= .05) 'hr.hoursN'.trParams({'n': ErpFmt.qty(double.parse(r.hours.toStringAsFixed(1)))}),
        if (r.overtime >= .05) 'hr.overtimeN'.trParams({'n': ErpFmt.qty(double.parse(r.overtime.toStringAsFixed(1)))}),
      ].join(' · '),
      trailing: AttendanceBadge(r.status),
    );
  }
}

/// A payslip in a list: the month, when it was paid, the net pay.
class PayslipRow extends StatelessWidget {
  const PayslipRow({super.key, required this.slip, required this.currency, required this.onTap, this.divider = true, this.title});

  final HrPayslipSummary slip;
  final String currency;
  final VoidCallback onTap;
  final bool divider;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.money,
      iconColor: t.successStrong,
      title: title ?? monthLabel(slip.period),
      subtitle: [
        if (slip.paymentDate != null) 'hr.paidOn'.trParams({'date': dashDate(slip.paymentDate)}) else if (slip.runStatus != null) 'hr.run.${slip.runStatus}'.tr,
        ?slip.runNumber,
      ].join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ErpFmt.amount(slip.net.round()),
            style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text('hr.netPay'.tr, style: VfType.meta.copyWith(color: t.muted)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A leave balance as a tile: days left large, the type, taken of entitled.
class BalanceTile extends StatelessWidget {
  const BalanceTile({super.key, required this.balance, this.selected = false, this.onTap});

  final HrLeaveBalance balance;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final b = balance;
    final left = b.available;
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            left == null ? 'hr.noLimit'.tr : ErpFmt.qty(double.parse(left.toStringAsFixed(1))),
            style: VfType.figure.copyWith(fontSize: left == null ? 18 : 21, color: selected ? t.primaryText : t.text),
          ),
          Text(left == null ? '' : 'hr.daysLeft'.tr, style: VfType.meta.copyWith(color: t.muted)),
          const SizedBox(height: 6),
          Text(b.type, maxLines: 2, overflow: TextOverflow.ellipsis, style: VfType.label.copyWith(color: t.text, height: 1.25)),
          if (b.limited)
            Text(
              'hr.takenOf'.trParams({'taken': ErpFmt.qty(b.taken), 'of': ErpFmt.qty(double.parse(b.accrued.toStringAsFixed(1)))}),
              style: VfType.meta.copyWith(color: t.muted),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: vfCardDecoration(t).copyWith(
        border: Border.all(color: selected ? t.primary : (t.isDark ? t.glassBorder : t.border), width: selected ? 2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// A row of month arrows: "< November 2026 >".
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.label, required this.onPrev, this.onNext});

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DecoratedBox(
      decoration: vfCardDecoration(t),
      child: Row(
        children: [
          IconButton(
            tooltip: 'hr.previous'.tr,
            iconSize: 20,
            padding: const EdgeInsets.all(14),
            onPressed: onPrev,
            icon: Icon(PhosphorIconsBold.caretLeft, color: t.text),
          ),
          Expanded(
            child: Text(label, textAlign: TextAlign.center, style: VfType.cardTitle.copyWith(color: t.text)),
          ),
          IconButton(
            tooltip: 'hr.next'.tr,
            iconSize: 20,
            padding: const EdgeInsets.all(14),
            onPressed: onNext,
            icon: Icon(PhosphorIconsBold.caretRight, color: onNext == null ? t.faint : t.text),
          ),
        ],
      ),
    );
  }
}
