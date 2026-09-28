import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../data/models/models.dart';
import '../../data/models/report_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/report_repository.dart';

/// Which filters make sense for each report — the web's FILTERS table. A
/// control that cannot change the result is not offered: the department
/// report already lists every department, the employee report already groups
/// by person, and the money reports only ever hold approved vouchers, so they
/// get a payment status instead.
class ReportFilterConfig {
  const ReportFilterConfig(this.keys, this.status, {this.money = false});

  final List<String> keys;

  /// 'full', 'payment' or null (no status filter).
  final String? status;
  final bool money;
}

const reportFilterConfigs = <String, ReportFilterConfig>{
  'vouchers': ReportFilterConfig([
    'q',
    'from',
    'to',
    'department_id',
    'requester_id',
    'voucher_type_id',
    'kind',
    'status',
  ], 'full'),
  'expenses': ReportFilterConfig([
    'from',
    'to',
    'department_id',
    'requester_id',
    'voucher_type_id',
    'kind',
    'status',
  ], 'payment'),
  'payments': ReportFilterConfig(
    [
      'q',
      'from',
      'to',
      'department_id',
      'requester_id',
      'voucher_type_id',
      'kind',
      'status',
    ],
    'payment',
    money: true,
  ),
  'cash': ReportFilterConfig(
    [
      'q',
      'from',
      'to',
      'department_id',
      'requester_id',
      'voucher_type_id',
      'status',
    ],
    'payment',
    money: true,
  ),
  'departments': ReportFilterConfig([
    'from',
    'to',
    'voucher_type_id',
    'kind',
  ], null),
  'employees': ReportFilterConfig([
    'from',
    'to',
    'department_id',
    'voucher_type_id',
    'kind',
  ], null),
  'approvals': ReportFilterConfig([
    'from',
    'to',
    'department_id',
    'requester_id',
    'voucher_type_id',
    'kind',
    'status',
  ], 'full'),
  'monthly': ReportFilterConfig([
    'from',
    'to',
    'department_id',
    'requester_id',
    'voucher_type_id',
    'kind',
  ], null),
};
const _defaultConfig = ReportFilterConfig([
  'from',
  'to',
  'department_id',
  'voucher_type_id',
  'kind',
], null);

/// A status the report can be narrowed to, with its label key.
class ReportStatusOption {
  const ReportStatusOption(this.value, this.labelKey);
  final String value, labelKey;
}

const fullStatuses = [
  ReportStatusOption('drafts', 'reports.st.drafts'),
  ReportStatusOption('pending', 'reports.st.pending'),
  ReportStatusOption('changes_requested', 'reports.st.changes'),
  ReportStatusOption('awaiting_payment', 'reports.st.awaiting'),
  ReportStatusOption('paid', 'reports.st.paid'),
  ReportStatusOption('rejected', 'reports.st.rejected'),
  ReportStatusOption('cancelled', 'reports.st.cancelled'),
];
const paymentStatuses = [
  ReportStatusOption('awaiting_payment', 'reports.st.awaiting'),
  ReportStatusOption('paid', 'reports.st.paid'),
];

const reportFilterKeys = [
  'q',
  'from',
  'to',
  'department_id',
  'requester_id',
  'voucher_type_id',
  'status',
  'kind',
];

Map<String, String> blankReportFilters() => {
  for (final k in reportFilterKeys) k: '',
};

/// The reports screen's state: the catalogue, the caller's reach, the
/// filters, the loaded report and exports.
class ReportsController {
  ReportsController(this.repo);

  final ReportRepository repo;

  final kinds = <ReportKind>[].obs;
  final scope = Rxn<ReportScope>();
  final active = 'vouchers'.obs;
  final filters = blankReportFilters().obs;
  final result = Rxn<ReportResult>();
  final loading = true.obs;
  final error = RxnString();
  final departments = <Department>[].obs;
  final types = <VoucherType>[].obs;
  final people = <ReportPerson>[].obs;

  /// The format being exported ('pdf', 'xlsx', 'csv', or 'print'), if any.
  final exporting = RxnString();

  Timer? _debounce;
  String? _lastKey;
  int _request = 0;
  String _locale = 'en';

  /// Loads the catalogue, the pickers' lists and the first report.
  void start() {
    _locale = Get.locale?.languageCode ?? 'en';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadCatalogue(),
      repo.departments().then(departments.assignAll).catchError((_) {}),
      repo.voucherTypes().then(types.assignAll).catchError((_) {}),
    ]);
    reload();
  }

  Future<void> _loadCatalogue() async {
    try {
      final c = await repo.catalogue();
      kinds.assignAll(c.kinds);
      scope.value = c.scope;
      // Land on a report this role can actually run.
      if (c.kinds.isNotEmpty && !c.kinds.any((k) => k.key == active.value)) {
        active.value = c.kinds.first.key;
      }
      // People to filter by — only for a caller who can see anyone but
      // themselves.
      if (c.scope != null && !c.scope!.isOwn) {
        unawaited(
          repo
              .people()
              .then((p) {
                people.assignAll(p);
                reload();
              })
              .catchError((_) {}),
        );
      }
    } catch (_) {
      // The web carries on with the voucher report; so does the app.
    }
  }

  ReportFilterConfig get config =>
      reportFilterConfigs[active.value] ?? _defaultConfig;

  List<ReportStatusOption> get statusOptions => switch (config.status) {
    'full' => fullStatuses,
    'payment' => paymentStatuses,
    _ => const [],
  };

  ReportKind? get activeKind =>
      kinds.firstWhereOrNull((k) => k.key == active.value);

  /// Departments inside the caller's ceiling; the picker only narrows it.
  List<Department> get pickableDepartments {
    final s = scope.value;
    if (s == null || s.isOwn) return const [];
    if (s.isCompany) return departments;
    return departments.where((d) => s.departmentIds!.contains(d.id)).toList();
  }

  List<ReportPerson> get pickablePeople {
    final s = scope.value;
    if (s == null || s.isOwn) return const [];
    if (s.isCompany) return people;
    return people
        .where(
          (p) =>
              p.departmentId != null &&
              s.departmentIds!.contains(p.departmentId),
        )
        .toList();
  }

  bool shows(String key) {
    if (!config.keys.contains(key)) return false;
    if (key == 'department_id') return pickableDepartments.length > 1;
    if (key == 'requester_id') return pickablePeople.length > 1;
    if (key == 'status') return statusOptions.isNotEmpty;
    return true;
  }

  /// Only the filters this report shows are sent, so a value chosen on
  /// another report (or a status this report cannot hold) never silently
  /// narrows it.
  Map<String, String> paramsFor(Map<String, String> values) => {
    for (final e in values.entries)
      if (e.value.isNotEmpty &&
          shows(e.key) &&
          (e.key != 'status' || statusOptions.any((o) => o.value == e.value)))
        e.key: e.value,
  };

  Map<String, String> get params => paramsFor(filters);

  bool get hasFilters => params.isNotEmpty;

  /// Filters set in the sheet (everything but the search box).
  int get sheetFilterCount => params.keys.where((k) => k != 'q').length;

  void setActive(String key) {
    if (key == active.value) return;
    active.value = key;
    reload();
  }

  void setFilter(String key, String value) {
    filters[key] = value;
    reload(debounce: key == 'q' && value.isNotEmpty);
  }

  void applyFilters(Map<String, String> values) {
    filters.assignAll(values);
    reload();
  }

  void clearFilters() {
    filters.assignAll(blankReportFilters());
    reload();
  }

  /// The screen noticed a language change: the server words some cells.
  void localeChanged(String locale) {
    if (locale == _locale) return;
    _locale = locale;
    reload();
  }

  Future<void> refreshAll() async {
    await _loadCatalogue();
    await reload(force: true);
  }

  /// Loads the report when what would be sent has changed.
  Future<void> reload({bool debounce = false, bool force = false}) {
    final p = params;
    final key = '${active.value}|$_locale|${jsonEncode(p)}';
    if (!force && key == _lastKey) return Future.value();
    _lastKey = key;
    _debounce?.cancel();
    if (debounce) {
      final done = Completer<void>();
      _debounce = Timer(
        const Duration(milliseconds: 260),
        () => _fetch(p).whenComplete(done.complete),
      );
      return done.future;
    }
    return _fetch(p);
  }

  Future<void> _fetch(Map<String, String> p) async {
    final ticket = ++_request;
    final kind = active.value;
    loading.value = true;
    error.value = null;
    try {
      final r = await repo.show(kind, p);
      if (ticket != _request) return;
      result.value = r;
    } on ApiException catch (e) {
      if (ticket != _request) return;
      error.value = e.message;
    } catch (e) {
      if (ticket != _request) return;
      error.value = '$e';
    } finally {
      if (ticket == _request) loading.value = false;
    }
  }

  /// `vouchflow-vouchers-2026-09-28.pdf` — the web's export file name.
  String fileName(String format) =>
      'vouchflow-${active.value}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.$format';

  void dispose() {
    _debounce?.cancel();
    _disposed = true;
  }

  bool _disposed = false;
  bool get disposed => _disposed;
}
