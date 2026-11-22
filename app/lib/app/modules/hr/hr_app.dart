import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'attendance_page.dart';
import 'employees_page.dart';
import 'leave_requests_page.dart';
import 'me_page.dart';
import 'my_attendance_page.dart';
import 'my_leave_page.dart';
import 'my_payslips_page.dart';
import 'overview_page.dart';
import 'payroll_page.dart';

/*
 * The HR app, as the shell sees it. HR staff (hr.view) land on the overview
 * with employees, leave to decide and attendance as tabs; a department head
 * (hr.leave.approve) on the leave they decide; everyone else (hr.self) on
 * their own HR: profile, leave, payslips and attendance, four tabs.
 */

const _hr = 'hr';
const _payroll = ['hr.payroll.prepare', 'hr.payroll.authorise', 'hr.payroll.post'];

const hrNav = [
  VfNavItem('/erp/hr', 'hr.nav.overview', PhosphorIconsRegular.house, PhosphorIconsFill.house,
      module: _hr, permissions: ['hr.view']),
  VfNavItem('/erp/hr/employees', 'hr.nav.employees', PhosphorIconsRegular.identificationCard, PhosphorIconsFill.identificationCard,
      module: _hr, permissions: ['hr.view']),
  VfNavItem('/erp/hr/leave', 'hr.nav.leave', PhosphorIconsRegular.airplaneTilt, PhosphorIconsFill.airplaneTilt,
      short: 'hr.nav.leaveShort', module: _hr, permissions: ['hr.leave.approve']),
  VfNavItem('/erp/hr/attendance', 'hr.nav.attendance', PhosphorIconsRegular.fingerprint, PhosphorIconsFill.fingerprint,
      module: _hr, permissions: ['hr.view', 'hr.leave.approve']),
  VfNavItem('/erp/hr/payroll', 'hr.nav.payroll', PhosphorIconsRegular.money, PhosphorIconsFill.money,
      module: _hr, permissions: _payroll),
  VfNavItem('/erp/hr/me', 'hr.nav.me', PhosphorIconsRegular.identificationBadge, PhosphorIconsFill.identificationBadge,
      short: 'hr.nav.meShort', module: _hr, permissions: ['hr.self']),
  VfNavItem('/erp/hr/me/leave', 'hr.nav.myLeave', PhosphorIconsRegular.calendarPlus, PhosphorIconsFill.calendarPlus,
      short: 'hr.nav.myLeaveShort', module: _hr, permissions: ['hr.self']),
  VfNavItem('/erp/hr/me/payslips', 'hr.nav.payslips', PhosphorIconsRegular.receipt, PhosphorIconsFill.receipt,
      module: _hr, permissions: ['hr.self']),
  VfNavItem('/erp/hr/me/attendance', 'hr.nav.myAttendance', PhosphorIconsRegular.clock, PhosphorIconsFill.clock,
      short: 'hr.nav.myAttendanceShort', module: _hr, permissions: ['hr.self']),
];

/// What the HR "+" offers: applying for leave. Adding an employee stays on
/// the web.
const hrCreateActions = [
  VfCreateAction(
    label: 'hr.applyLeave',
    hint: 'hr.applyLeaveHint',
    icon: PhosphorIconsRegular.calendarPlus,
    route: Routes.erpHrLeaveNew,
    permission: 'hr.self',
  ),
];

final hrApp = VfAppModule(
  area: _hr,
  nav: hrNav,
  pages: {
    '/erp/hr': (_) => const HrOverviewPage(),
    '/erp/hr/employees': (_) => const EmployeesPage(),
    '/erp/hr/leave': (_) => const LeaveRequestsPage(),
    '/erp/hr/attendance': (_) => const AttendancePage(),
    '/erp/hr/payroll': (_) => const PayrollPage(),
    '/erp/hr/me': (_) => const MePage(),
    '/erp/hr/me/leave': (_) => const MyLeavePage(),
    '/erp/hr/me/payslips': (_) => const MyPayslipsPage(),
    '/erp/hr/me/attendance': (_) => const MyAttendancePage(),
  },
  create: hrCreateActions,
);
